# CyxChat API Reference

## Overview

This document provides the API reference for the CyxChat Flutter application. It covers the Dart services, providers, and models that interface with the C library via FFI.

---

## Architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      API Architecture                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                        UI Layer                                  │   │
│  │   Screens, Widgets, User Interactions                           │   │
│  └────────────────────────────┬────────────────────────────────────┘   │
│                               │                                         │
│                               ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     Providers (Riverpod)                         │   │
│  │   chatProvider, contactsProvider, groupsProvider, etc.          │   │
│  └────────────────────────────┬────────────────────────────────────┘   │
│                               │                                         │
│                               ▼                                         │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                       Services                                   │   │
│  │   ChatService, ContactService, GroupService, FileService        │   │
│  └────────────────────────────┬────────────────────────────────────┘   │
│                               │                                         │
│               ┌───────────────┼───────────────┐                        │
│               ▼               ▼               ▼                        │
│  ┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐          │
│  │   FFI Bridge    │ │    Database     │ │  Platform APIs  │          │
│  │  (libcyxchat)   │ │   (SQLite)      │ │ (Notifications) │          │
│  └─────────────────┘ └─────────────────┘ └─────────────────┘          │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Models

### Message

```dart
// lib/core/models/message.dart

import 'package:freezed_annotation/freezed_annotation.dart';

part 'message.freezed.dart';
part 'message.g.dart';

/// Message status
enum MessageStatus {
  pending,    // Not yet sent
  sending,    // Being sent
  sent,       // Sent to network
  delivered,  // ACK received
  read,       // Read receipt received
  failed,     // Send failed
}

/// Message type
enum MessageType {
  text,       // 0x10
  image,      // 0x21
  video,      // 0x22
  audio,      // 0x20
  file,       // 0x14
  location,   // 0x23
  contact,    // 0x24
  system,     // 0x00
}

@freezed
class Message with _$Message {
  const factory Message({
    required int id,
    required String conversationId,
    required String msgId,           // Hex string (16 chars)
    required String senderId,        // Hex string (64 chars)
    required MessageType type,
    required MessageStatus status,
    required DateTime createdAt,

    // Content
    String? text,
    Map<String, dynamic>? metadata,

    // Timestamps
    DateTime? sentAt,
    DateTime? deliveredAt,
    DateTime? readAt,

    // Threading
    String? replyToId,
    String? replyToText,
    String? replyToSender,

    // Edit/Delete
    @Default(false) bool edited,
    DateTime? editedAt,
    @Default(false) bool deleted,

    // Reactions
    Map<String, List<String>>? reactions,

    // Attachments
    List<Attachment>? attachments,
  }) = _Message;

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);
}

@freezed
class Attachment with _$Attachment {
  const factory Attachment({
    required String id,
    required String filename,
    required int fileSize,
    required AttachmentType type,
    String? mimeType,
    String? localPath,
    String? storageId,
    String? thumbnailPath,
    int? width,
    int? height,
    int? durationMs,
    @Default(0) int progress,
    @Default(TransferState.pending) TransferState state,
  }) = _Attachment;

  factory Attachment.fromJson(Map<String, dynamic> json) =>
      _$AttachmentFromJson(json);
}

enum AttachmentType { file, image, video, audio, voice }
enum TransferState { pending, uploading, downloading, complete, failed }
```

### Contact

```dart
// lib/core/models/contact.dart

@freezed
class Contact with _$Contact {
  const factory Contact({
    required String nodeId,          // Hex string (64 chars)
    required String publicKey,       // Hex string (64 chars)
    String? displayName,
    String? avatarPath,
    @Default(false) bool verified,
    @Default(false) bool blocked,
    required DateTime addedAt,
    DateTime? lastSeen,
    @Default(PresenceStatus.offline) PresenceStatus presence,
    String? statusText,
    @Default(false) bool favorite,
  }) = _Contact;

  factory Contact.fromJson(Map<String, dynamic> json) =>
      _$ContactFromJson(json);
}

enum PresenceStatus { offline, online, away, busy }
```

### Conversation

```dart
// lib/core/models/conversation.dart

@freezed
class Conversation with _$Conversation {
  const factory Conversation({
    required String id,
    required ConversationType type,
    String? peerId,                  // For direct chats
    String? groupId,                 // For groups
    required String title,
    String? avatarPath,
    required DateTime createdAt,
    required DateTime updatedAt,
    String? lastMessageText,
    DateTime? lastMessageAt,
    @Default(0) int unreadCount,
    @Default(false) bool muted,
    @Default(false) bool pinned,
    @Default(false) bool archived,
    String? draftText,

    // For direct chats
    PresenceStatus? peerPresence,
  }) = _Conversation;

  factory Conversation.fromJson(Map<String, dynamic> json) =>
      _$ConversationFromJson(json);
}

enum ConversationType { direct, group }
```

### Group

```dart
// lib/core/models/group.dart

@freezed
class Group with _$Group {
  const factory Group({
    required String groupId,         // Hex string (16 chars)
    required String name,
    String? description,
    String? avatarPath,
    required String creatorId,
    required List<GroupMember> members,
    required DateTime createdAt,
    @Default(false) bool left,
  }) = _Group;

  factory Group.fromJson(Map<String, dynamic> json) =>
      _$GroupFromJson(json);
}

@freezed
class GroupMember with _$GroupMember {
  const factory GroupMember({
    required String nodeId,
    required GroupRole role,
    String? displayName,
    required DateTime joinedAt,
    PresenceStatus? presence,
  }) = _GroupMember;

  factory GroupMember.fromJson(Map<String, dynamic> json) =>
      _$GroupMemberFromJson(json);
}

enum GroupRole { member, admin, owner }
```

---

## Services

### ChatService

```dart
// lib/core/services/chat_service.dart

abstract class ChatService {
  /// Initialize chat service
  Future<void> initialize();

  /// Dispose resources
  Future<void> dispose();

  /// Get all conversations
  Future<List<Conversation>> getConversations();

  /// Get conversation by ID
  Future<Conversation?> getConversation(String id);

  /// Create or get direct conversation with peer
  Future<Conversation> getOrCreateDirectConversation(String peerId);

  /// Get messages for conversation
  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  });

  /// Watch messages (real-time updates)
  Stream<List<Message>> watchMessages(String conversationId);

  /// Send text message
  Future<Message> sendMessage({
    required String conversationId,
    required String text,
    String? replyToId,
  });

  /// Send typing indicator
  Future<void> sendTyping(String conversationId, bool isTyping);

  /// Mark conversation as read
  Future<void> markAsRead(String conversationId);

  /// Delete message (local only)
  Future<void> deleteMessage(String messageId);

  /// Request remote deletion
  Future<void> requestDelete(String conversationId, String messageId);

  /// Edit message
  Future<void> editMessage(String messageId, String newText);

  /// Add reaction
  Future<void> addReaction(String messageId, String emoji);

  /// Remove reaction
  Future<void> removeReaction(String messageId, String emoji);

  /// Archive conversation
  Future<void> archiveConversation(String conversationId);

  /// Mute conversation
  Future<void> muteConversation(String conversationId, Duration? duration);

  /// Pin conversation
  Future<void> pinConversation(String conversationId, bool pinned);

  /// Delete conversation (local only)
  Future<void> deleteConversation(String conversationId);

  /// Search messages
  Future<List<Message>> searchMessages(String query, {int limit = 50});

  /// Get total unread count
  Future<int> getTotalUnreadCount();

  /// Watch total unread count
  Stream<int> watchUnreadCount();
}
```

### ContactService

```dart
// lib/core/services/contact_service.dart

abstract class ContactService {
  /// Get all contacts
  Future<List<Contact>> getContacts();

  /// Watch contacts (real-time updates)
  Stream<List<Contact>> watchContacts();

  /// Get contact by node ID
  Future<Contact?> getContact(String nodeId);

  /// Add contact
  Future<Contact> addContact({
    required String nodeId,
    required String publicKey,
    String? displayName,
  });

  /// Add contact from QR code data
  Future<Contact> addContactFromQr(String qrData);

  /// Update contact display name
  Future<void> updateContactName(String nodeId, String name);

  /// Set contact blocked status
  Future<void> setBlocked(String nodeId, bool blocked);

  /// Set contact verified status
  Future<void> setVerified(String nodeId, bool verified);

  /// Set contact as favorite
  Future<void> setFavorite(String nodeId, bool favorite);

  /// Remove contact
  Future<void> removeContact(String nodeId);

  /// Get blocked contacts
  Future<List<Contact>> getBlockedContacts();

  /// Compute safety number for verification
  Future<String> computeSafetyNumber(String nodeId);

  /// Search contacts
  Future<List<Contact>> searchContacts(String query);
}
```

### GroupService

```dart
// lib/core/services/group_service.dart

abstract class GroupService {
  /// Get all groups
  Future<List<Group>> getGroups();

  /// Watch groups (real-time updates)
  Stream<List<Group>> watchGroups();

  /// Get group by ID
  Future<Group?> getGroup(String groupId);

  /// Create group
  Future<Group> createGroup({
    required String name,
    String? description,
    List<String>? initialMembers,
  });

  /// Update group name
  Future<void> updateGroupName(String groupId, String name);

  /// Update group description
  Future<void> updateGroupDescription(String groupId, String description);

  /// Invite member
  Future<void> inviteMember(String groupId, String nodeId);

  /// Remove member (admin only)
  Future<void> removeMember(String groupId, String nodeId);

  /// Leave group
  Future<void> leaveGroup(String groupId);

  /// Promote to admin (owner only)
  Future<void> promoteToAdmin(String groupId, String nodeId);

  /// Get pending invitations
  Future<List<GroupInvitation>> getPendingInvitations();

  /// Accept invitation
  Future<void> acceptInvitation(String groupId);

  /// Decline invitation
  Future<void> declineInvitation(String groupId);

  /// Send message to group
  Future<Message> sendGroupMessage({
    required String groupId,
    required String text,
    String? replyToId,
  });
}

@freezed
class GroupInvitation with _$GroupInvitation {
  const factory GroupInvitation({
    required String groupId,
    required String groupName,
    required String inviterId,
    String? inviterName,
    required DateTime receivedAt,
  }) = _GroupInvitation;
}
```

### FileService

```dart
// lib/core/services/file_service.dart

abstract class FileService {
  /// Send file to peer
  Future<Attachment> sendFile({
    required String conversationId,
    required String filePath,
  });

  /// Send file to group
  Future<Attachment> sendFileToGroup({
    required String groupId,
    required String filePath,
  });

  /// Accept incoming file
  Future<void> acceptFile(String attachmentId);

  /// Reject incoming file
  Future<void> rejectFile(String attachmentId);

  /// Cancel transfer
  Future<void> cancelTransfer(String attachmentId);

  /// Get active transfers
  Future<List<Transfer>> getActiveTransfers();

  /// Watch transfer progress
  Stream<Transfer> watchTransfer(String attachmentId);

  /// Get download directory
  Future<String> getDownloadDirectory();

  /// Set download directory
  Future<void> setDownloadDirectory(String path);

  /// Open file
  Future<void> openFile(String path);

  /// Share file
  Future<void> shareFile(String path);
}

@freezed
class Transfer with _$Transfer {
  const factory Transfer({
    required String id,
    required String filename,
    required int fileSize,
    required bool isSending,
    required TransferState state,
    required int progress,       // 0-100
    required int completedBytes,
    String? error,
  }) = _Transfer;
}
```

### IdentityService

```dart
// lib/core/services/identity_service.dart

abstract class IdentityService {
  /// Check if identity exists
  Future<bool> hasIdentity();

  /// Create new identity
  Future<Identity> createIdentity({String? displayName});

  /// Get current identity
  Future<Identity?> getIdentity();

  /// Update display name
  Future<void> updateDisplayName(String name);

  /// Update avatar
  Future<void> updateAvatar(String imagePath);

  /// Get our QR code data
  Future<String> getQrCodeData();

  /// Export recovery phrase
  Future<String> exportRecoveryPhrase();

  /// Import identity from recovery phrase
  Future<Identity> importFromRecoveryPhrase(String phrase);

  /// Export encrypted backup
  Future<String> exportBackup(String password);

  /// Import from encrypted backup
  Future<Identity> importBackup(String backupPath, String password);

  /// Rotate keys
  Future<void> rotateKeys();

  /// Delete identity (dangerous!)
  Future<void> deleteIdentity();
}

@freezed
class Identity with _$Identity {
  const factory Identity({
    required String nodeId,
    required String publicKey,
    String? displayName,
    String? avatarPath,
    required DateTime createdAt,
  }) = _Identity;
}
```

### PresenceService

```dart
// lib/core/services/presence_service.dart

abstract class PresenceService {
  /// Set our presence status
  Future<void> setPresence(PresenceStatus status, {String? statusText});

  /// Get presence for peer
  Future<PresenceStatus> getPresence(String nodeId);

  /// Watch presence for peer
  Stream<PresenceStatus> watchPresence(String nodeId);

  /// Request presence update from peer
  Future<void> requestPresence(String nodeId);
}
```

---

## Providers (Riverpod)

### Chat Providers

```dart
// lib/providers/chat_provider.dart

import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'chat_provider.g.dart';

/// All conversations
@riverpod
class ConversationsNotifier extends _$ConversationsNotifier {
  @override
  Future<List<Conversation>> build() async {
    final chatService = ref.watch(chatServiceProvider);
    return chatService.getConversations();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final chatService = ref.read(chatServiceProvider);
      return chatService.getConversations();
    });
  }
}

/// Single conversation
@riverpod
Future<Conversation?> conversation(
  ConversationRef ref,
  String conversationId,
) async {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.getConversation(conversationId);
}

/// Messages for conversation
@riverpod
class MessagesNotifier extends _$MessagesNotifier {
  @override
  Future<List<Message>> build(String conversationId) async {
    final chatService = ref.watch(chatServiceProvider);
    return chatService.getMessages(conversationId);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull ?? [];
    final chatService = ref.read(chatServiceProvider);
    final more = await chatService.getMessages(
      arg, // conversationId
      offset: current.length,
    );
    state = AsyncData([...current, ...more]);
  }

  Future<void> sendMessage(String text, {String? replyToId}) async {
    final chatService = ref.read(chatServiceProvider);
    await chatService.sendMessage(
      conversationId: arg,
      text: text,
      replyToId: replyToId,
    );
    ref.invalidateSelf();
  }
}

/// Typing indicators
@riverpod
class TypingNotifier extends _$TypingNotifier {
  @override
  Map<String, bool> build() => {};

  void setTyping(String conversationId, bool isTyping) {
    state = {...state, conversationId: isTyping};

    // Auto-clear after 5 seconds
    if (isTyping) {
      Future.delayed(const Duration(seconds: 5), () {
        if (state[conversationId] == true) {
          state = {...state, conversationId: false};
        }
      });
    }
  }
}

/// Total unread count
@riverpod
Stream<int> unreadCount(UnreadCountRef ref) {
  final chatService = ref.watch(chatServiceProvider);
  return chatService.watchUnreadCount();
}
```

### Contact Providers

```dart
// lib/providers/contact_provider.dart

@riverpod
class ContactsNotifier extends _$ContactsNotifier {
  @override
  Future<List<Contact>> build() async {
    final contactService = ref.watch(contactServiceProvider);
    return contactService.getContacts();
  }

  Future<void> addContact({
    required String nodeId,
    required String publicKey,
    String? displayName,
  }) async {
    final contactService = ref.read(contactServiceProvider);
    await contactService.addContact(
      nodeId: nodeId,
      publicKey: publicKey,
      displayName: displayName,
    );
    ref.invalidateSelf();
  }

  Future<void> removeContact(String nodeId) async {
    final contactService = ref.read(contactServiceProvider);
    await contactService.removeContact(nodeId);
    ref.invalidateSelf();
  }
}

@riverpod
Future<Contact?> contact(ContactRef ref, String nodeId) async {
  final contactService = ref.watch(contactServiceProvider);
  return contactService.getContact(nodeId);
}

@riverpod
Future<List<Contact>> blockedContacts(BlockedContactsRef ref) async {
  final contactService = ref.watch(contactServiceProvider);
  return contactService.getBlockedContacts();
}
```

### Group Providers

```dart
// lib/providers/group_provider.dart

@riverpod
class GroupsNotifier extends _$GroupsNotifier {
  @override
  Future<List<Group>> build() async {
    final groupService = ref.watch(groupServiceProvider);
    return groupService.getGroups();
  }

  Future<Group> createGroup({
    required String name,
    String? description,
    List<String>? members,
  }) async {
    final groupService = ref.read(groupServiceProvider);
    final group = await groupService.createGroup(
      name: name,
      description: description,
      initialMembers: members,
    );
    ref.invalidateSelf();
    return group;
  }
}

@riverpod
Future<Group?> group(GroupRef ref, String groupId) async {
  final groupService = ref.watch(groupServiceProvider);
  return groupService.getGroup(groupId);
}

@riverpod
Future<List<GroupInvitation>> pendingInvitations(
  PendingInvitationsRef ref,
) async {
  final groupService = ref.watch(groupServiceProvider);
  return groupService.getPendingInvitations();
}
```

### Settings Providers

```dart
// lib/providers/settings_provider.dart

@riverpod
class SettingsNotifier extends _$SettingsNotifier {
  @override
  AppSettings build() {
    return const AppSettings();
  }

  void setTheme(ThemeMode mode) {
    state = state.copyWith(themeMode: mode);
    _save();
  }

  void setNotificationsEnabled(bool enabled) {
    state = state.copyWith(notificationsEnabled: enabled);
    _save();
  }

  void setReadReceipts(bool enabled) {
    state = state.copyWith(readReceipts: enabled);
    _save();
  }

  void setTypingIndicators(bool enabled) {
    state = state.copyWith(typingIndicators: enabled);
    _save();
  }

  Future<void> _save() async {
    // Save to SharedPreferences or database
  }
}

@freezed
class AppSettings with _$AppSettings {
  const factory AppSettings({
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(true) bool notificationsEnabled,
    @Default(true) bool notificationSound,
    @Default(true) bool notificationVibrate,
    @Default(true) bool readReceipts,
    @Default(true) bool typingIndicators,
    @Default(true) bool showOnlineStatus,
    @Default('en') String language,
  }) = _AppSettings;
}
```

---

## FFI Bridge

### Initialization

```dart
// lib/core/ffi/cyxchat_ffi.dart

class CyxchatFFI {
  static CyxchatFFI? _instance;
  late final CyxchatBindings _bindings;
  late final DynamicLibrary _lib;
  Pointer<cyxchat_ctx_t>? _ctx;

  /// Get singleton instance
  static CyxchatFFI get instance {
    _instance ??= CyxchatFFI._();
    return _instance!;
  }

  CyxchatFFI._() {
    _lib = _loadLibrary();
    _bindings = CyxchatBindings(_lib);
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('cyxchat.dll');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libcyxchat.so');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libcyxchat.dylib');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libcyxchat.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Platform not supported');
  }

  /// Initialize the chat context
  Future<void> initialize({
    required Uint8List nodeId,
    required Pointer<Void> onionContext,
  }) async {
    // ... implementation
  }

  /// Send text message
  Future<String> sendMessage({
    required String to,
    required String text,
    String? replyTo,
  }) async {
    // ... implementation
  }

  /// Poll for events
  void poll() {
    if (_ctx != null) {
      final now = DateTime.now().millisecondsSinceEpoch;
      _bindings.cyxchat_poll(_ctx!, now);
    }
  }

  /// Dispose resources
  void dispose() {
    if (_ctx != null) {
      _bindings.cyxchat_destroy(_ctx!);
      _ctx = null;
    }
  }
}
```

### Event Loop

```dart
// lib/core/ffi/event_loop.dart

class CyxchatEventLoop {
  static CyxchatEventLoop? _instance;
  Timer? _pollTimer;
  final _eventController = StreamController<CyxchatEvent>.broadcast();

  static CyxchatEventLoop get instance {
    _instance ??= CyxchatEventLoop._();
    return _instance!;
  }

  CyxchatEventLoop._();

  Stream<CyxchatEvent> get events => _eventController.stream;

  void start() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(
      const Duration(milliseconds: 100),
      (_) => _poll(),
    );
  }

  void stop() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void _poll() {
    CyxchatFFI.instance.poll();
    // Events are dispatched via callbacks
  }

  void dispose() {
    stop();
    _eventController.close();
  }
}

abstract class CyxchatEvent {}

class MessageReceivedEvent extends CyxchatEvent {
  final String from;
  final String msgId;
  final String text;
  final DateTime timestamp;

  MessageReceivedEvent({
    required this.from,
    required this.msgId,
    required this.text,
    required this.timestamp,
  });
}

class AckReceivedEvent extends CyxchatEvent {
  final String from;
  final String msgId;
  final MessageStatus status;

  AckReceivedEvent({
    required this.from,
    required this.msgId,
    required this.status,
  });
}

class TypingEvent extends CyxchatEvent {
  final String from;
  final bool isTyping;

  TypingEvent({required this.from, required this.isTyping});
}
```

---

## Database Queries

### Repository Pattern

```dart
// lib/core/database/repositories/message_repository.dart

class MessageRepository {
  final Database _db;

  MessageRepository(this._db);

  Future<List<Message>> getMessages(
    String conversationId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await _db.rawQuery('''
      SELECT
        m.*,
        r.content_text as reply_text,
        r.sender_id as reply_sender
      FROM messages m
      LEFT JOIN messages r ON m.reply_to_id = r.id
      WHERE m.conversation_id = ?
        AND m.deleted = 0
      ORDER BY m.created_at DESC
      LIMIT ? OFFSET ?
    ''', [conversationId, limit, offset]);

    return rows.map((r) => Message.fromDb(r)).toList();
  }

  Future<Message> insert(Message message) async {
    final id = await _db.insert('messages', message.toDb());
    return message.copyWith(id: id);
  }

  Future<void> updateStatus(String msgId, MessageStatus status) async {
    await _db.update(
      'messages',
      {'status': status.index},
      where: 'msg_id = ?',
      whereArgs: [msgId],
    );
  }

  Future<void> markConversationRead(String conversationId) async {
    await _db.rawUpdate('''
      UPDATE messages
      SET status = ?
      WHERE conversation_id = ?
        AND status < ?
    ''', [MessageStatus.read.index, conversationId, MessageStatus.read.index]);
  }

  Stream<List<Message>> watchMessages(String conversationId) {
    // Implementation depends on your database package
    // Example with drift/moor would use watch queries
    throw UnimplementedError();
  }
}
```

---

## Error Handling

### Custom Exceptions

```dart
// lib/core/errors/exceptions.dart

abstract class CyxchatException implements Exception {
  final String message;
  final String? code;

  CyxchatException(this.message, {this.code});

  @override
  String toString() => 'CyxchatException: $message (code: $code)';
}

class NetworkException extends CyxchatException {
  NetworkException([String message = 'Network error'])
      : super(message, code: 'NETWORK');
}

class CryptoException extends CyxchatException {
  CryptoException([String message = 'Cryptographic error'])
      : super(message, code: 'CRYPTO');
}

class StorageException extends CyxchatException {
  StorageException([String message = 'Storage error'])
      : super(message, code: 'STORAGE');
}

class ContactBlockedException extends CyxchatException {
  ContactBlockedException([String message = 'Contact is blocked'])
      : super(message, code: 'BLOCKED');
}

class NotMemberException extends CyxchatException {
  NotMemberException([String message = 'Not a group member'])
      : super(message, code: 'NOT_MEMBER');
}

class NotAdminException extends CyxchatException {
  NotAdminException([String message = 'Admin privileges required'])
      : super(message, code: 'NOT_ADMIN');
}
```

### Error Mapping

```dart
// lib/core/ffi/error_mapper.dart

CyxchatException mapFFIError(int errorCode) {
  switch (errorCode) {
    case -1: return CyxchatException('Null pointer', code: 'NULL');
    case -2: return CyxchatException('Memory allocation failed', code: 'MEMORY');
    case -3: return CyxchatException('Invalid parameter', code: 'INVALID');
    case -4: return CyxchatException('Not found', code: 'NOT_FOUND');
    case -5: return CyxchatException('Already exists', code: 'EXISTS');
    case -6: return CyxchatException('Container full', code: 'FULL');
    case -7: return CryptoException();
    case -8: return NetworkException();
    case -9: return CyxchatException('Timeout', code: 'TIMEOUT');
    case -10: return ContactBlockedException();
    case -11: return NotMemberException();
    case -12: return NotAdminException();
    default: return CyxchatException('Unknown error: $errorCode');
  }
}
```

---

## Usage Examples

### Send Message

```dart
// In a widget or controller
final chatService = ref.read(chatServiceProvider);

try {
  final message = await chatService.sendMessage(
    conversationId: conversation.id,
    text: 'Hello, world!',
    replyToId: replyingTo?.msgId,
  );
  print('Message sent: ${message.msgId}');
} on NetworkException catch (e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Network error: ${e.message}')),
  );
}
```

### Watch Messages

```dart
// In a widget
@override
Widget build(BuildContext context, WidgetRef ref) {
  final messagesAsync = ref.watch(messagesNotifierProvider(conversationId));

  return messagesAsync.when(
    data: (messages) => ListView.builder(
      itemCount: messages.length,
      itemBuilder: (context, index) => MessageBubble(
        message: messages[index],
      ),
    ),
    loading: () => const CircularProgressIndicator(),
    error: (e, st) => Text('Error: $e'),
  );
}
```

### Add Contact from QR

```dart
Future<void> handleQrScan(String qrData) async {
  final contactService = ref.read(contactServiceProvider);

  try {
    final contact = await contactService.addContactFromQr(qrData);
    context.push('/chat/${contact.nodeId}');
  } on CyxchatException catch (e) {
    showErrorDialog(context, e.message);
  }
}
```

---

## Checklist

### Models
- [ ] Message
- [ ] Contact
- [ ] Conversation
- [ ] Group
- [ ] Attachment
- [ ] Identity
- [ ] Settings

### Services
- [ ] ChatService
- [ ] ContactService
- [ ] GroupService
- [ ] FileService
- [ ] IdentityService
- [ ] PresenceService
- [ ] NotificationService

### Providers
- [ ] ConversationsNotifier
- [ ] MessagesNotifier
- [ ] ContactsNotifier
- [ ] GroupsNotifier
- [ ] SettingsNotifier
- [ ] IdentityProvider

### FFI
- [ ] Library loading
- [ ] Bindings generation
- [ ] Event loop
- [ ] Callback handling
- [ ] Error mapping

### Database
- [ ] Schema creation
- [ ] Migrations
- [ ] Repositories
- [ ] Queries
