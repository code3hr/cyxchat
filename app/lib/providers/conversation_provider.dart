import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/chat_service.dart';
import 'network_provider.dart';

/// Provider for all conversations
final conversationsProvider = FutureProvider<List<Conversation>>((ref) async {
  return ChatService.instance.getConversations();
});

/// Provider for a specific conversation
final conversationProvider =
    FutureProvider.family<Conversation?, String>((ref, id) async {
  return ChatService.instance.getConversation(id);
});

/// Provider for messages in a conversation
final messagesProvider =
    FutureProvider.family<List<Message>, String>((ref, conversationId) async {
  return ChatService.instance.getMessages(conversationId);
});

/// Provider for message stream
final messageStreamProvider = StreamProvider<Message>((ref) {
  return ChatService.instance.messageStream;
});

/// Provider for chat actions
final chatActionsProvider = Provider((ref) => ChatActions(ref));

class ChatActions {
  final Ref _ref;

  ChatActions(this._ref);

  Future<Message> sendMessage({
    required String conversationId,
    required String content,
    String? replyToId,
  }) async {
    final message = await ChatService.instance.sendMessage(
      conversationId: conversationId,
      content: content,
      replyToId: replyToId,
    );
    _ref.invalidate(messagesProvider(conversationId));
    _ref.invalidate(conversationsProvider);
    return message;
  }

  Future<Conversation> startConversation(String peerId) async {
    final conversation =
        await ChatService.instance.getOrCreateDirectConversation(peerId);
    _ref.invalidate(conversationsProvider);

    // Trigger connection + key exchange with the peer immediately
    final connProvider = _ref.read(connectionNotifierProvider);
    if (connProvider.initialized && !connProvider.hasPeerKey(peerId)) {
      await connProvider.connect(peerId);
    }

    return conversation;
  }

  Future<void> markAsRead(String conversationId) async {
    await ChatService.instance.markAsRead(conversationId);
    _ref.invalidate(conversationsProvider);
  }

  Future<void> deleteMessage(String messageId, String conversationId) async {
    await ChatService.instance.deleteMessage(messageId);
    _ref.invalidate(messagesProvider(conversationId));
  }

  Future<void> editMessage(
      String messageId, String conversationId, String newContent) async {
    await ChatService.instance.editMessage(messageId, newContent);
    _ref.invalidate(messagesProvider(conversationId));
  }

  /// Send a file message to a conversation
  Future<Message> sendFileMessage({
    required String conversationId,
    required String filename,
    required String fileSize,
    String? fileId,
    String? localPath,
  }) async {
    final content = jsonEncode({
      'filename': filename,
      'size': fileSize,
      if (fileId != null) 'fileId': fileId,
      if (localPath != null) 'localPath': localPath,
    });
    final message = await ChatService.instance.sendMessage(
      conversationId: conversationId,
      content: content,
      type: MessageType.file,
    );
    _ref.invalidate(messagesProvider(conversationId));
    _ref.invalidate(conversationsProvider);
    return message;
  }

  /// Send an audio (voice) message to a conversation
  Future<Message> sendAudioMessage({
    required String conversationId,
    required String fileId,
    required int duration,
    required String filename,
    String? localPath,
  }) async {
    final content = jsonEncode({
      'fileId': fileId,
      'duration': duration,
      'filename': filename,
      if (localPath != null) 'localPath': localPath,
    });
    final message = await ChatService.instance.sendMessage(
      conversationId: conversationId,
      content: content,
      type: MessageType.audio,
    );
    _ref.invalidate(messagesProvider(conversationId));
    _ref.invalidate(conversationsProvider);
    return message;
  }

  Future<void> togglePin(String conversationId) async {
    await ChatService.instance.togglePin(conversationId);
    _ref.invalidate(conversationsProvider);
  }

  Future<void> toggleMute(String conversationId) async {
    await ChatService.instance.toggleMute(conversationId);
    _ref.invalidate(conversationsProvider);
  }

  Future<void> deleteConversation(String conversationId) async {
    await ChatService.instance.deleteConversation(conversationId);
    _ref.invalidate(conversationsProvider);
  }

  /// Update conversation display name (alias)
  Future<void> updateConversationDisplayName(
      String conversationId, String displayName) async {
    await ChatService.instance
        .updateConversationDisplayName(conversationId, displayName);
    _ref.invalidate(conversationProvider(conversationId));
    _ref.invalidate(conversationsProvider);
  }

  /// Retry sending a failed message
  Future<bool> retryMessage(String messageId, String conversationId) async {
    final success =
        await ChatService.instance.retryMessage(messageId, conversationId);
    _ref.invalidate(messagesProvider(conversationId));
    return success;
  }
}
