import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/models.dart';
import '../services/chat_service.dart';

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

  Future<void> togglePin(String conversationId) async {
    await ChatService.instance.togglePin(conversationId);
    _ref.invalidate(conversationsProvider);
  }

  Future<void> toggleMute(String conversationId) async {
    await ChatService.instance.toggleMute(conversationId);
    _ref.invalidate(conversationsProvider);
  }
}
