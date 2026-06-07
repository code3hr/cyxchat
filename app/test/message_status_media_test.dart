import 'dart:convert';

import 'package:cyxchat/ffi/bindings.dart';
import 'package:cyxchat/models/models.dart';
import 'package:cyxchat/providers/chat_provider.dart';
import 'package:cyxchat/services/chat_service.dart';
import 'package:cyxchat/services/database_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    ChatService.instance.resetForTesting();
    await DatabaseService.instance.clearAllData();
  });

  tearDown(() async {
    ChatService.instance.resetForTesting();
    await DatabaseService.instance.clearAllData();
  });

  tearDownAll(() async {
    await DatabaseService.instance.close();
  });

  test('message model round-trips status and group media metadata', () {
    final metadata = jsonEncode({
      'fileId': 'group-file-1',
      'filename': 'photo.jpg',
      'mimeType': 'image/jpeg',
      'size': 4096,
      'localPath': 'D:\\media\\photo.jpg',
    });
    final message = Message(
      id: 'group-msg-1',
      conversationId: 'group-1',
      senderId: 'sender-1',
      type: MessageType.image,
      content: 'photo.jpg',
      timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
      status: MessageStatus.failed,
      isOutgoing: true,
      mediaType: MediaType.image,
      mediaMetadata: metadata,
      thumbnailPath: 'D:\\media\\thumb.jpg',
    );

    final map = message.toMap();
    expect(map['type'], MessageType.image.index);
    expect(map['status'], MessageStatus.failed.index);
    expect(map['media_type'], MediaType.image.name);
    expect(map['media_metadata'], metadata);

    final restored = Message.fromMap(map);
    expect(restored.type, MessageType.image);
    expect(restored.status, MessageStatus.failed);
    expect(restored.mediaType, MediaType.image);
    expect(jsonDecode(restored.mediaMetadata!)['mimeType'], 'image/jpeg');
    expect(restored.thumbnailPath, 'D:\\media\\thumb.jpg');
  });

  test('file transfer completion persists delivered status and local path',
      () async {
    final db = await DatabaseService.instance.database;
    await _insertDirectConversation(db, unreadCount: 0);
    await _insertMessage(
      db,
      Message(
        id: 'media-msg-1',
        conversationId: 'conv-1',
        senderId: 'me',
        type: MessageType.voice,
        content: jsonEncode({
          'fileId': 'file-1',
          'filename': 'voice.ogg',
          'retrying': true,
        }),
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: MessageStatus.sending,
        isOutgoing: true,
        mediaType: MediaType.voice,
        mediaMetadata: jsonEncode({'durationMs': 1200, 'size': 2048}),
      ),
    );

    final emitted = expectLater(
      ChatService.instance.messageStream,
      emits(
        isA<Message>()
            .having((m) => m.id, 'id', 'media-msg-1')
            .having((m) => m.status, 'status', MessageStatus.delivered),
      ),
    );

    await ChatService.instance.handleFileTransferCompleted(
      'file-1',
      localPath: 'D:\\media\\voice.ogg',
    );
    await emitted;

    final stored = await _getMessage(db, 'media-msg-1');
    final content = jsonDecode(stored.content) as Map<String, dynamic>;
    expect(stored.status, MessageStatus.delivered);
    expect(content['localPath'], 'D:\\media\\voice.ogg');
    expect(content.containsKey('retrying'), isFalse);
    expect(jsonDecode(stored.mediaMetadata!)['durationMs'], 1200);
  });

  test('file transfer failure persists failed status and emits update',
      () async {
    final db = await DatabaseService.instance.database;
    await _insertDirectConversation(db, unreadCount: 0);
    await _insertMessage(
      db,
      Message(
        id: 'media-msg-2',
        conversationId: 'conv-1',
        senderId: 'me',
        type: MessageType.file,
        content: jsonEncode({
          'fileId': 'file-2',
          'filename': 'report.pdf',
        }),
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        status: MessageStatus.sending,
        isOutgoing: true,
        mediaType: MediaType.document,
        mediaMetadata: jsonEncode({'size': 8192}),
      ),
    );

    final emitted = expectLater(
      ChatService.instance.messageStream,
      emits(
        isA<Message>()
            .having((m) => m.id, 'id', 'media-msg-2')
            .having((m) => m.status, 'status', MessageStatus.failed),
      ),
    );

    await ChatService.instance.handleFileTransferFailed('file-2');
    await emitted;

    final stored = await _getMessage(db, 'media-msg-2');
    expect(stored.status, MessageStatus.failed);
    expect(jsonDecode(stored.mediaMetadata!)['size'], 8192);
  });

  test('markAsRead marks inbound messages read and clears unread count',
      () async {
    final db = await DatabaseService.instance.database;
    await _insertDirectConversation(db, unreadCount: 2);
    await _insertMessage(
      db,
      Message(
        id: 'inbound-1',
        conversationId: 'conv-1',
        senderId: 'peer-1',
        content: 'hello',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        status: MessageStatus.delivered,
        isOutgoing: false,
      ),
    );
    await _insertMessage(
      db,
      Message(
        id: 'outgoing-1',
        conversationId: 'conv-1',
        senderId: 'me',
        content: 'reply',
        timestamp: DateTime.fromMillisecondsSinceEpoch(1700000001000),
        status: MessageStatus.delivered,
        isOutgoing: true,
      ),
    );

    await ChatService.instance.markAsRead('conv-1');

    expect((await _getMessage(db, 'inbound-1')).status, MessageStatus.read);
    expect(
      (await _getMessage(db, 'outgoing-1')).status,
      MessageStatus.delivered,
    );

    final conversation = await db.query(
      'conversations',
      columns: ['unread_count'],
      where: 'id = ?',
      whereArgs: ['conv-1'],
      limit: 1,
    );
    expect(conversation.single['unread_count'], 0);
  });

  test('incoming native text is idempotent by native message ID', () async {
    final db = await DatabaseService.instance.database;
    final textBytes = utf8.encode('hello once');
    final received = ReceivedMessage(
      fromNodeId: 'peer-dup',
      type: CyxChatMsgType.text,
      msgId: '0102030405060708',
      rawData: [textBytes.length, 0, ...textBytes],
      receivedAt: DateTime.fromMillisecondsSinceEpoch(1700000002000),
    );

    await ChatService.instance.handleIncomingMessageForTesting(received);
    await ChatService.instance.handleIncomingMessageForTesting(received);

    final rows = await db.query(
      'messages',
      where: 'native_msg_id = ?',
      whereArgs: ['0102030405060708'],
    );
    expect(rows, hasLength(1));

    final conversations = await db.query(
      'conversations',
      columns: ['unread_count'],
      where: 'peer_id = ?',
      whereArgs: ['peer-dup'],
      limit: 1,
    );
    expect(conversations.single['unread_count'], 1);
  });
}

Future<void> _insertDirectConversation(
  Database db, {
  required int unreadCount,
}) {
  return db.insert('conversations', {
    'id': 'conv-1',
    'type': ConversationType.direct.index,
    'peer_id': 'peer-1',
    'display_name': 'Peer One',
    'unread_count': unreadCount,
    'last_activity_at': 1700000000000,
  });
}

Future<void> _insertMessage(Database db, Message message) {
  return db.insert('messages', message.toMap());
}

Future<Message> _getMessage(Database db, String id) async {
  final rows = await db.query(
    'messages',
    where: 'id = ?',
    whereArgs: [id],
    limit: 1,
  );
  return Message.fromMap(rows.single);
}
