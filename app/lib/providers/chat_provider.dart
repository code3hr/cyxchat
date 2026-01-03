import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';

/// Received message from native layer
class ReceivedMessage {
  final String fromNodeId;
  final int type;
  final List<int> rawData;
  final DateTime receivedAt;

  ReceivedMessage({
    required this.fromNodeId,
    required this.type,
    required this.rawData,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();

  /// Parse text message from raw data
  /// Wire format: text_len(2 bytes LE) + text(N) + reply_to(8 optional)
  TextMessageData? parseTextMessage() {
    if (type != CyxChatMsgType.text || rawData.length < 2) return null;

    // 2-byte little-endian length
    final textLen = rawData[0] | (rawData[1] << 8);
    if (rawData.length < 2 + textLen) return null;

    final textBytes = rawData.sublist(2, 2 + textLen);
    final text = utf8.decode(textBytes, allowMalformed: true);

    String? replyToMsgId;
    if (rawData.length >= 2 + textLen + 8) {
      final replyToBytes = rawData.sublist(2 + textLen, 2 + textLen + 8);
      if (!replyToBytes.every((b) => b == 0)) {
        replyToMsgId = _bytesToHex(replyToBytes);
      }
    }

    return TextMessageData(
      text: text,
      replyToMsgId: replyToMsgId,
    );
  }

  /// Parse ACK from raw data
  /// Wire format: msg_id(8) + status(1)
  AckData? parseAck() {
    if (type != CyxChatMsgType.ack || rawData.length < 9) return null;

    final msgIdBytes = rawData.sublist(0, 8);
    final msgId = _bytesToHex(msgIdBytes);
    final status = rawData[8];

    return AckData(
      msgId: msgId,
      status: status,
    );
  }

  /// Parse typing indicator from raw data
  /// Wire format: is_typing(1)
  bool? parseTyping() {
    if (type != CyxChatMsgType.typing || rawData.isEmpty) return null;
    return rawData[0] != 0;
  }

  /// Parse reaction from raw data
  /// Wire format: msg_id(8) + remove(1) + reaction(N)
  ReactionData? parseReaction() {
    if (type != CyxChatMsgType.reaction || rawData.length < 10) return null;

    final msgIdBytes = rawData.sublist(0, 8);
    final msgId = _bytesToHex(msgIdBytes);
    final remove = rawData[8] != 0;
    final reactionBytes = rawData.sublist(9);
    final reaction = utf8.decode(reactionBytes, allowMalformed: true);

    return ReactionData(
      msgId: msgId,
      reaction: reaction,
      remove: remove,
    );
  }

  /// Parse delete request from raw data
  /// Wire format: msg_id(8)
  String? parseDelete() {
    if (type != CyxChatMsgType.delete || rawData.length < 8) return null;
    return _bytesToHex(rawData.sublist(0, 8));
  }

  /// Parse edit from raw data
  /// Wire format: msg_id(8) + text_len(2) + text(N)
  EditData? parseEdit() {
    if (type != CyxChatMsgType.edit || rawData.length < 10) return null;

    final msgIdBytes = rawData.sublist(0, 8);
    final msgId = _bytesToHex(msgIdBytes);
    final textLen = rawData[8] | (rawData[9] << 8);

    if (rawData.length < 10 + textLen) return null;

    final textBytes = rawData.sublist(10, 10 + textLen);
    final text = utf8.decode(textBytes, allowMalformed: true);

    return EditData(
      msgId: msgId,
      newText: text,
    );
  }

  static String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Parsed text message data
class TextMessageData {
  final String text;
  final String? replyToMsgId;

  TextMessageData({
    required this.text,
    this.replyToMsgId,
  });
}

/// Parsed ACK data
class AckData {
  final String msgId;
  final int status;

  AckData({
    required this.msgId,
    required this.status,
  });

  bool get isDelivered => status == 1;
  bool get isRead => status == 2;
}

/// Parsed reaction data
class ReactionData {
  final String msgId;
  final String reaction;
  final bool remove;

  ReactionData({
    required this.msgId,
    required this.reaction,
    required this.remove,
  });
}

/// Parsed edit data
class EditData {
  final String msgId;
  final String newText;

  EditData({
    required this.msgId,
    required this.newText,
  });
}

/// Typing status for a peer
class TypingStatus {
  final String peerId;
  final bool isTyping;
  final DateTime timestamp;

  TypingStatus({
    required this.peerId,
    required this.isTyping,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Result of sending a message
class SendResult {
  final bool success;
  final String? nativeMsgId;
  final String? error;

  SendResult.success(this.nativeMsgId) : success = true, error = null;
  SendResult.failure(this.error) : success = false, nativeMsgId = null;
}

/// Chat provider for managing peer-to-peer messaging via FFI
class ChatProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  // State
  bool _initialized = false;
  String? _localNodeId;

  // Polling timer
  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 50);

  // Stream controllers
  final _messageController = StreamController<ReceivedMessage>.broadcast();
  final _ackController = StreamController<AckData>.broadcast();
  final _typingController = StreamController<TypingStatus>.broadcast();
  final _reactionController = StreamController<ReactionData>.broadcast();
  final _deleteController = StreamController<String>.broadcast();
  final _editController = StreamController<EditData>.broadcast();

  // Typing status tracking (auto-expire after 5s)
  final Map<String, TypingStatus> _typingStatuses = {};
  static const _typingTimeout = Duration(seconds: 5);

  // Getters
  bool get initialized => _initialized;
  String? get localNodeId => _localNodeId;

  /// Stream of incoming text messages
  Stream<ReceivedMessage> get messageStream => _messageController.stream;

  /// Stream of ACKs (delivery/read receipts)
  Stream<AckData> get ackStream => _ackController.stream;

  /// Stream of typing indicators
  Stream<TypingStatus> get typingStream => _typingController.stream;

  /// Stream of reactions
  Stream<ReactionData> get reactionStream => _reactionController.stream;

  /// Stream of delete requests
  Stream<String> get deleteStream => _deleteController.stream;

  /// Stream of edit requests
  Stream<EditData> get editStream => _editController.stream;

  /// Get current typing statuses (filtered by timeout)
  Map<String, TypingStatus> get typingStatuses {
    final now = DateTime.now();
    _typingStatuses.removeWhere(
      (_, status) => now.difference(status.timestamp) > _typingTimeout,
    );
    return Map.unmodifiable(_typingStatuses);
  }

  /// Initialize chat provider
  Future<bool> initialize({required List<int> localId}) async {
    if (_initialized) return true;

    // Store local node ID
    _localNodeId = _bytesToHex(localId);

    // Convert local ID to native pointer
    final localIdPtr = calloc<Uint8>(32);
    for (int i = 0; i < 32 && i < localId.length; i++) {
      localIdPtr[i] = localId[i];
    }

    try {
      final result = _bindings.chatCreate(localIdPtr);
      if (result != CyxChatError.ok) {
        debugPrint('Failed to create chat context: ${_bindings.errorString(result)}');
        return false;
      }

      _initialized = true;
      _startPolling();
      notifyListeners();
      return true;
    } finally {
      calloc.free(localIdPtr);
    }
  }

  /// Shutdown chat provider
  void shutdown() {
    _stopPolling();

    if (_initialized) {
      _bindings.chatDestroy();
      _initialized = false;
      _localNodeId = null;
      _typingStatuses.clear();
      notifyListeners();
    }
  }

  /// Send text message to peer
  /// Returns SendResult with native message ID on success
  Future<SendResult> sendText({
    required String toPeerId,
    required String text,
    String? replyToMsgId,
  }) async {
    if (!_initialized) {
      return SendResult.failure('Chat not initialized');
    }

    final peerIdBytes = _hexToBytes(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final msgIdHex = _bindings.chatSendText(
        peerIdPtr,
        text,
        replyToHex: replyToMsgId,
      );

      if (msgIdHex != null) {
        return SendResult.success(msgIdHex);
      } else {
        return SendResult.failure('Send failed');
      }
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send ACK for received message
  Future<bool> sendAck({
    required String toPeerId,
    required String msgId,
    int status = 1,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = _hexToBytes(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendAck(peerIdPtr, msgId, status);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send read receipt for message
  Future<bool> sendReadReceipt({
    required String toPeerId,
    required String msgId,
  }) {
    return sendAck(toPeerId: toPeerId, msgId: msgId, status: 2);
  }

  /// Send typing indicator
  Future<bool> sendTyping({
    required String toPeerId,
    required bool isTyping,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = _hexToBytes(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendTyping(peerIdPtr, isTyping);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send reaction to message
  Future<bool> sendReaction({
    required String toPeerId,
    required String msgId,
    required String reaction,
    bool remove = false,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = _hexToBytes(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendReaction(
        peerIdPtr,
        msgId,
        reaction,
        remove: remove,
      );
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Request message deletion
  Future<bool> sendDelete({
    required String toPeerId,
    required String msgId,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = _hexToBytes(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendDelete(peerIdPtr, msgId);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Send edited message
  Future<bool> sendEdit({
    required String toPeerId,
    required String msgId,
    required String newText,
  }) async {
    if (!_initialized) return false;

    final peerIdBytes = _hexToBytes(toPeerId);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _bindings.chatSendEdit(peerIdPtr, msgId, newText);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  // Private methods

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_pollInterval, (_) => _poll());
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _poll() {
    if (!_initialized) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    _bindings.chatPoll(now);

    // Process all queued messages
    while (true) {
      final msg = _bindings.chatRecvNext();
      if (msg == null) break;

      _processReceivedMessage(msg);
    }
  }

  void _processReceivedMessage(Map<String, dynamic> msg) {
    final fromBytes = msg['from'] as List<int>;
    final type = msg['type'] as int;
    final data = msg['data'] as List<int>;

    final fromNodeId = _bytesToHex(fromBytes);

    final received = ReceivedMessage(
      fromNodeId: fromNodeId,
      type: type,
      rawData: data,
    );

    switch (type) {
      case CyxChatMsgType.text:
        _messageController.add(received);
        break;

      case CyxChatMsgType.ack:
        final ack = received.parseAck();
        if (ack != null) {
          _ackController.add(ack);
        }
        break;

      case CyxChatMsgType.typing:
        final isTyping = received.parseTyping();
        if (isTyping != null) {
          final status = TypingStatus(
            peerId: fromNodeId,
            isTyping: isTyping,
          );
          if (isTyping) {
            _typingStatuses[fromNodeId] = status;
          } else {
            _typingStatuses.remove(fromNodeId);
          }
          _typingController.add(status);
          notifyListeners();
        }
        break;

      case CyxChatMsgType.reaction:
        final reaction = received.parseReaction();
        if (reaction != null) {
          _reactionController.add(reaction);
        }
        break;

      case CyxChatMsgType.delete:
        final msgId = received.parseDelete();
        if (msgId != null) {
          _deleteController.add(msgId);
        }
        break;

      case CyxChatMsgType.edit:
        final edit = received.parseEdit();
        if (edit != null) {
          _editController.add(edit);
        }
        break;

      default:
        // Unknown message type - could be group message, etc.
        debugPrint('ChatProvider: Unknown message type 0x${type.toRadixString(16)}');
        break;
    }
  }

  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        result.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    }
    return result;
  }

  @override
  void dispose() {
    shutdown();
    _messageController.close();
    _ackController.close();
    _typingController.close();
    _reactionController.close();
    _deleteController.close();
    _editController.close();
    super.dispose();
  }
}

/// Riverpod provider for ChatProvider
final chatNotifierProvider = ChangeNotifierProvider<ChatProvider>((ref) {
  return ChatProvider();
});

/// Provider for chat actions
final chatActionsProvider = Provider((ref) => ChatActions(ref));

/// Chat actions helper class
class ChatActions {
  final Ref _ref;

  ChatActions(this._ref);

  /// Send text message
  Future<SendResult> sendText({
    required String toPeerId,
    required String text,
    String? replyToMsgId,
  }) {
    return _ref.read(chatNotifierProvider).sendText(
      toPeerId: toPeerId,
      text: text,
      replyToMsgId: replyToMsgId,
    );
  }

  /// Send ACK
  Future<bool> sendAck({
    required String toPeerId,
    required String msgId,
    int status = 1,
  }) {
    return _ref.read(chatNotifierProvider).sendAck(
      toPeerId: toPeerId,
      msgId: msgId,
      status: status,
    );
  }

  /// Send read receipt
  Future<bool> sendReadReceipt({
    required String toPeerId,
    required String msgId,
  }) {
    return _ref.read(chatNotifierProvider).sendReadReceipt(
      toPeerId: toPeerId,
      msgId: msgId,
    );
  }

  /// Send typing indicator
  Future<bool> sendTyping({
    required String toPeerId,
    required bool isTyping,
  }) {
    return _ref.read(chatNotifierProvider).sendTyping(
      toPeerId: toPeerId,
      isTyping: isTyping,
    );
  }

  /// Send reaction
  Future<bool> sendReaction({
    required String toPeerId,
    required String msgId,
    required String reaction,
    bool remove = false,
  }) {
    return _ref.read(chatNotifierProvider).sendReaction(
      toPeerId: toPeerId,
      msgId: msgId,
      reaction: reaction,
      remove: remove,
    );
  }

  /// Send delete request
  Future<bool> sendDelete({
    required String toPeerId,
    required String msgId,
  }) {
    return _ref.read(chatNotifierProvider).sendDelete(
      toPeerId: toPeerId,
      msgId: msgId,
    );
  }

  /// Send edit
  Future<bool> sendEdit({
    required String toPeerId,
    required String msgId,
    required String newText,
  }) {
    return _ref.read(chatNotifierProvider).sendEdit(
      toPeerId: toPeerId,
      msgId: msgId,
      newText: newText,
    );
  }
}
