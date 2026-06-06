import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';
import '../models/group_invite.dart';
import '../services/log_service.dart';
import '../utils/node_id_utils.dart';

/// Received group message from FFI layer
class GroupMessageReceived {
  final String groupId;
  final String fromNodeId;
  final String msgId;
  final String text;
  final DateTime receivedAt;

  GroupMessageReceived({
    required this.groupId,
    required this.fromNodeId,
    required this.msgId,
    required this.text,
    DateTime? receivedAt,
  }) : receivedAt = receivedAt ?? DateTime.now();
}

/// Member event (join or leave)
class MemberEvent {
  final String groupId;
  final String memberId;
  final bool isJoin;
  final bool wasKicked;
  final DateTime timestamp;

  MemberEvent({
    required this.groupId,
    required this.memberId,
    required this.isJoin,
    this.wasKicked = false,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  bool get isLeave => !isJoin;
}

/// Key update event
class KeyUpdateEvent {
  final String groupId;
  final int newVersion;
  final DateTime timestamp;

  KeyUpdateEvent({
    required this.groupId,
    required this.newVersion,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Key distribution progress
class KeyDistProgress {
  final String groupId;
  final int sent;
  final int acked;
  final int total;
  final bool complete;
  final bool success;
  final int failedCount;

  KeyDistProgress({
    required this.groupId,
    required this.sent,
    required this.acked,
    required this.total,
    this.complete = false,
    this.success = false,
    this.failedCount = 0,
  });

  double get progress => total > 0 ? acked / total : 0.0;
  bool get inProgress => !complete && total > 0;
}

/// Result of FFI group operations
class GroupFFIResult {
  final bool success;
  final String? groupId;
  final String? msgId;
  final String? fileId;
  final String? error;

  GroupFFIResult.success({this.groupId, this.msgId, this.fileId})
      : success = true,
        error = null;
  GroupFFIResult.failure(this.error)
      : success = false,
        groupId = null,
        msgId = null,
        fileId = null;
}

/// Low-level FFI provider for group chat operations
/// This handles the C library interaction; GroupService handles database operations
class GroupFFIProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  // State
  bool _initialized = false;
  String? _localNodeId;

  // Polling timer
  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 200);

  // Pending invites (groupId -> invite)
  final Map<String, GroupInvite> _pendingInvites = {};

  // Key distribution progress tracking
  final Map<String, KeyDistProgress> _keyDistProgress = {};

  // Stream controllers
  final _messageController = StreamController<GroupMessageReceived>.broadcast();
  final _inviteController = StreamController<GroupInvite>.broadcast();
  final _memberEventController = StreamController<MemberEvent>.broadcast();
  final _keyUpdateController = StreamController<KeyUpdateEvent>.broadcast();
  final _keyDistCompleteController =
      StreamController<KeyDistProgress>.broadcast();

  // Getters
  bool get initialized => _initialized;
  String? get localNodeId => _localNodeId;
  CyxChatBindings get bindings => _bindings;

  /// Stream of incoming group messages
  Stream<GroupMessageReceived> get messageStream => _messageController.stream;

  /// Stream of group invitations
  Stream<GroupInvite> get inviteStream => _inviteController.stream;

  /// Stream of member join/leave events
  Stream<MemberEvent> get memberEventStream => _memberEventController.stream;

  /// Stream of key update events
  Stream<KeyUpdateEvent> get keyUpdateStream => _keyUpdateController.stream;

  /// Stream of key distribution completion events
  Stream<KeyDistProgress> get keyDistCompleteStream =>
      _keyDistCompleteController.stream;

  /// Get pending invites
  List<GroupInvite> get pendingInvites => _pendingInvites.values.toList();

  /// Get key distribution progress for a group
  KeyDistProgress? getKeyDistProgress(String groupId) =>
      _keyDistProgress[groupId];

  /// Initialize group FFI provider
  Future<bool> initialize({required List<int> localId}) async {
    if (_initialized) return true;

    final log = LogService.instance;
    _localNodeId = NodeIdUtils.bytesToNodeId(localId, localId.length);

    try {
      // Check if chat context exists (group module depends on it)
      print('GroupFFI: Checking chat context...');
      if (_bindings.chatCtx == null) {
        print('GroupFFI: ERROR - chat context is null!');
        log.error('Cannot initialize groups: chat context not created',
            source: 'GroupFFI');
        return false;
      }
      print('GroupFFI: Chat context OK, creating group context...');

      // Create group context using chat context
      final result = _bindings.groupCtxCreate(_bindings.chatCtx!);
      print('GroupFFI: groupCtxCreate result = $result');
      if (result != CyxChatError.ok) {
        print('GroupFFI: ERROR - groupCtxCreate failed: ${_bindings.errorString(result)}');
        log.error(
            'Failed to create group context: ${_bindings.errorString(result)}',
            source: 'GroupFFI');
        return false;
      }

      // Set up callbacks
      print('GroupFFI: Setting up callbacks...');
      _setupCallbacks();
      print('GroupFFI: Callbacks set up');

      _initialized = true;
      print('GroupFFI: Starting polling...');
      _startPolling();
      print('GroupFFI: Polling started');
      notifyListeners();

      log.info('Group FFI provider initialized', source: 'GroupFFI');
      print('GroupFFI: Initialization complete!');
      return true;
    } catch (e, st) {
      print('GroupFFI: EXCEPTION during init: $e');
      print('GroupFFI: Stack trace: $st');
      log.error('Failed to initialize group FFI provider: $e',
          source: 'GroupFFI');
      return false;
    }
  }

  /// Shutdown group FFI provider
  void shutdown() {
    _stopPolling();

    if (_initialized) {
      _bindings.groupCleanupCallbacks();
      _bindings.groupCtxDestroy();
      _initialized = false;
      _localNodeId = null;
      _pendingInvites.clear();
      _keyDistProgress.clear();
      notifyListeners();
    }
  }

  // ============================================================
  // Group Management (FFI)
  // ============================================================

  /// Create a new group via FFI
  Future<GroupFFIResult> createGroup(String name) async {
    final log = LogService.instance;
    if (!_initialized) {
      return GroupFFIResult.failure('Group FFI not initialized');
    }

    final groupId = _bindings.groupCreate(name);
    if (groupId != null) {
      log.info('Created group "$name" (${groupId.substring(0, 8)}...)',
          source: 'GroupFFI');
      notifyListeners();
      return GroupFFIResult.success(groupId: groupId);
    } else {
      log.error('Failed to create group "$name"', source: 'GroupFFI');
      return GroupFFIResult.failure('Failed to create group');
    }
  }

  /// Leave a group via FFI
  Future<bool> leaveGroup(String groupId) async {
    final log = LogService.instance;
    if (!_initialized) return false;

    final result = _bindings.groupLeave(groupId);
    if (result == CyxChatError.ok) {
      log.info('Left group ${groupId.substring(0, 8)}...', source: 'GroupFFI');
      notifyListeners();
      return true;
    } else {
      log.error('Failed to leave group: ${_bindings.errorString(result)}',
          source: 'GroupFFI');
      return false;
    }
  }

  /// Set group name via FFI (admin only)
  Future<bool> setGroupName(String groupId, String name) async {
    if (!_initialized) return false;
    final result = _bindings.groupSetName(groupId, name);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set group description via FFI
  Future<bool> setGroupDescription(String groupId, String description) async {
    if (!_initialized) return false;
    final result = _bindings.groupSetDescription(groupId, description);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  // ============================================================
  // Member Management (FFI)
  // ============================================================

  /// Invite a member to group via FFI
  Future<bool> inviteMember({
    required String groupId,
    required String memberId,
    required List<int> memberPubkey,
  }) async {
    final log = LogService.instance;
    if (!_initialized) return false;

    // Try to resolve the full 32-byte node ID from the connection context
    // This is needed because the onion layer uses exact 32-byte node ID matching
    List<int>? fullNodeId = _bindings.connGetFullNodeIdHex(memberId);
    final memberIdBytes = fullNodeId ?? NodeIdUtils.toBytesAsList(memberId);
    
    if (fullNodeId != null) {
      log.debug('Resolved full node ID for ${memberId.substring(0, 8)}...', 
          source: 'GroupFFI');
    } else {
      log.debug('Using padded node ID for ${memberId.substring(0, 8)}... (no full ID found)',
          source: 'GroupFFI');
    }
    
    final memberIdPtr = calloc<Uint8>(32);
    final pubkeyPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }
      for (int i = 0; i < 32 && i < memberPubkey.length; i++) {
        pubkeyPtr[i] = memberPubkey[i];
      }

      final result = _bindings.groupInvite(groupId, memberIdPtr, pubkeyPtr);
      if (result == CyxChatError.ok) {
        log.info('Invited ${memberId.substring(0, 8)}... to group',
            source: 'GroupFFI');
        return true;
      } else {
        log.error('Failed to invite member: ${_bindings.errorString(result)}',
            source: 'GroupFFI');
        return false;
      }
    } finally {
      calloc.free(memberIdPtr);
      calloc.free(pubkeyPtr);
    }
  }

  /// Remove member from group via FFI (admin only)
  Future<bool> removeMember({
    required String groupId,
    required String memberId,
  }) async {
    final log = LogService.instance;
    if (!_initialized) return false;

    final memberIdBytes = NodeIdUtils.toBytesAsList(memberId);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }

      final result = _bindings.groupRemoveMember(groupId, memberIdPtr);
      if (result == CyxChatError.ok) {
        log.info('Removed ${memberId.substring(0, 8)}... from group',
            source: 'GroupFFI');
        notifyListeners();
        return true;
      } else {
        log.error('Failed to remove member: ${_bindings.errorString(result)}',
            source: 'GroupFFI');
        return false;
      }
    } finally {
      calloc.free(memberIdPtr);
    }
  }

  /// Promote member to admin via FFI (owner only)
  Future<bool> addAdmin({
    required String groupId,
    required String memberId,
  }) async {
    if (!_initialized) return false;

    final memberIdBytes = NodeIdUtils.toBytesAsList(memberId);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }

      final result = _bindings.groupAddAdmin(groupId, memberIdPtr);
      if (result == CyxChatError.ok) {
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(memberIdPtr);
    }
  }

  /// Demote admin to member via FFI (owner only)
  Future<bool> removeAdmin({
    required String groupId,
    required String memberId,
  }) async {
    if (!_initialized) return false;

    final memberIdBytes = NodeIdUtils.toBytesAsList(memberId);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }

      final result = _bindings.groupRemoveAdmin(groupId, memberIdPtr);
      if (result == CyxChatError.ok) {
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(memberIdPtr);
    }
  }

  // ============================================================
  // Invitations (FFI)
  // ============================================================

  /// Accept a pending group invite via FFI
  Future<bool> acceptInvite(String groupId) async {
    final log = LogService.instance;
    if (!_initialized) return false;

    final result = _bindings.groupAcceptInvite(groupId);
    if (result == CyxChatError.ok) {
      _pendingInvites.remove(groupId);
      log.info('Accepted invite to group ${groupId.substring(0, 8)}...',
          source: 'GroupFFI');
      notifyListeners();
      return true;
    } else {
      log.error('Failed to accept invite: ${_bindings.errorString(result)}',
          source: 'GroupFFI');
      return false;
    }
  }

  /// Decline a pending group invite via FFI
  Future<bool> declineInvite(String groupId) async {
    final log = LogService.instance;
    if (!_initialized) return false;

    final result = _bindings.groupDeclineInvite(groupId);
    if (result == CyxChatError.ok) {
      _pendingInvites.remove(groupId);
      log.info('Declined invite to group ${groupId.substring(0, 8)}...',
          source: 'GroupFFI');
      notifyListeners();
      return true;
    } else {
      log.error('Failed to decline invite: ${_bindings.errorString(result)}',
          source: 'GroupFFI');
      return false;
    }
  }

  // ============================================================
  // Messaging (FFI)
  // ============================================================

  /// Send text message to group via FFI
  Future<GroupFFIResult> sendText({
    required String groupId,
    required String text,
    String? replyToMsgId,
  }) async {
    final log = LogService.instance;
    if (!_initialized) {
      return GroupFFIResult.failure('Group FFI not initialized');
    }

    final msgId = _bindings.groupSendText(
      groupId,
      text,
      replyToHex: replyToMsgId,
    );

    if (msgId != null) {
      log.info('Sent group message (${text.length} chars)', source: 'GroupFFI');
      return GroupFFIResult.success(msgId: msgId);
    } else {
      log.error('Failed to send group message', source: 'GroupFFI');
      return GroupFFIResult.failure('Failed to send message');
    }
  }

  // ============================================================
  // Key Management (FFI)
  // ============================================================

  /// Rotate group key via FFI (admin only)
  Future<bool> rotateKey(String groupId) async {
    final log = LogService.instance;
    if (!_initialized) return false;

    final result = _bindings.groupRotateKey(groupId);
    if (result == CyxChatError.ok) {
      log.info('Started key rotation for group ${groupId.substring(0, 8)}...',
          source: 'GroupFFI');
      return true;
    } else {
      log.error('Failed to rotate key: ${_bindings.errorString(result)}',
          source: 'GroupFFI');
      return false;
    }
  }

  /// Set auto-rotation on member leave
  void setAutoRotateOnLeave(bool enable) {
    if (!_initialized) return;
    _bindings.groupSetAutoRotateOnLeave(enable);
  }

  /// Set auto-rotation on kick notification
  void setAutoRotateOnKick(bool enable) {
    if (!_initialized) return;
    _bindings.groupSetAutoRotateOnKick(enable);
  }

  /// Get auto-rotation settings
  Map<String, bool> getAutoRotateSettings() {
    if (!_initialized) return {'onLeave': true, 'onKick': false};
    return _bindings.groupGetAutoRotateSettings();
  }

  // ============================================================
  // Admin Permissions (FFI) - Phase 1
  // ============================================================

  /// Set granular permissions for an admin
  Future<bool> setAdminPermissions({
    required String groupId,
    required String adminId,
    required int permissions,
  }) async {
    if (!_initialized) return false;

    final adminIdBytes = NodeIdUtils.toBytesAsList(adminId);
    final adminIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < adminIdBytes.length; i++) {
        adminIdPtr[i] = adminIdBytes[i];
      }

      final result = _bindings.groupSetAdminPermissions(groupId, adminIdPtr, permissions);
      if (result == CyxChatError.ok) {
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(adminIdPtr);
    }
  }

  /// Get permissions bitmask for an admin
  int getAdminPermissions({
    required String groupId,
    required String adminId,
  }) {
    if (!_initialized) return 0;

    final adminIdBytes = NodeIdUtils.toBytesAsList(adminId);
    final adminIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < adminIdBytes.length; i++) {
        adminIdPtr[i] = adminIdBytes[i];
      }

      return _bindings.groupGetAdminPermissions(groupId, adminIdPtr);
    } finally {
      calloc.free(adminIdPtr);
    }
  }

  /// Check if admin has specific permission
  bool hasPermission({
    required String groupId,
    required String adminId,
    required int permission,
  }) {
    if (!_initialized) return false;
    return _bindings.groupHasPermission(groupId, adminId, permission);
  }

  // ============================================================
  // Member Restrictions (FFI) - Phase 1
  // ============================================================

  /// Restrict a member (mute, no media, etc.)
  Future<bool> restrictMember({
    required String groupId,
    required String memberId,
    required int restrictions,
    int? untilMs,
  }) async {
    if (!_initialized) return false;

    final memberIdBytes = NodeIdUtils.toBytesAsList(memberId);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }

      final result = _bindings.groupRestrictMember(
        groupId,
        memberIdPtr,
        restrictions,
        untilMs ?? 0,
      );
      if (result == CyxChatError.ok) {
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(memberIdPtr);
    }
  }

  /// Remove all restrictions from a member
  Future<bool> unrestrictMember({
    required String groupId,
    required String memberId,
  }) async {
    if (!_initialized) return false;

    final memberIdBytes = NodeIdUtils.toBytesAsList(memberId);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }

      final result = _bindings.groupUnrestrictMember(groupId, memberIdPtr);
      if (result == CyxChatError.ok) {
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(memberIdPtr);
    }
  }

  /// Get member restrictions (returns bitmask and until timestamp)
  ({int restrictions, int untilMs}) getMemberRestrictions({
    required String groupId,
    required String memberId,
  }) {
    if (!_initialized) return (restrictions: 0, untilMs: 0);

    final memberIdBytes = NodeIdUtils.toBytesAsList(memberId);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }

      final result = _bindings.groupGetMemberRestrictions(groupId, memberIdPtr);
      return (restrictions: result.$1, untilMs: result.$2);
    } finally {
      calloc.free(memberIdPtr);
    }
  }

  /// Check if member is currently muted
  bool isMemberMuted({
    required String groupId,
    required String memberId,
  }) {
    if (!_initialized) return false;

    final memberIdBytes = NodeIdUtils.toBytesAsList(memberId);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < memberIdBytes.length; i++) {
        memberIdPtr[i] = memberIdBytes[i];
      }

      return _bindings.groupIsMemberMuted(groupId, memberIdPtr);
    } finally {
      calloc.free(memberIdPtr);
    }
  }

  // ============================================================
  // Group Settings (FFI) - Phase 1
  // ============================================================

  /// Set slow mode (seconds between messages)
  Future<bool> setSlowMode({
    required String groupId,
    required int seconds,
  }) async {
    if (!_initialized) return false;

    final result = _bindings.groupSetSlowMode(groupId, seconds);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Get slow mode setting
  int getSlowMode(String groupId) {
    if (!_initialized) return 0;
    return _bindings.groupGetSlowMode(groupId);
  }

  /// Set who can add members (0 = everyone, 1 = admins only)
  Future<bool> setWhoCanAdd({
    required String groupId,
    required int setting,
  }) async {
    if (!_initialized) return false;

    final result = _bindings.groupSetWhoCanAdd(groupId, setting);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set who can edit group info (0 = everyone, 1 = admins only)
  Future<bool> setWhoCanEdit({
    required String groupId,
    required int setting,
  }) async {
    if (!_initialized) return false;

    final result = _bindings.groupSetWhoCanEdit(groupId, setting);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Set who can send messages (see CyxChatGroupSendSetting)
  /// 0 = everyone, 1 = admins only, 2 = selected members
  Future<bool> setWhoCanSend({
    required String groupId,
    required int setting,
  }) async {
    if (!_initialized) return false;

    final result = _bindings.groupSetWhoCanSend(groupId, setting);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Get who can send messages setting
  int getWhoCanSend(String groupId) {
    if (!_initialized) return CyxChatGroupSendSetting.all;
    return _bindings.groupGetWhoCanSend(groupId);
  }

  /// Add a member to selected senders list
  Future<bool> addSelectedSender({
    required String groupId,
    required String memberId,
  }) async {
    if (!_initialized) return false;

    final result = _bindings.groupAddSelectedSender(groupId, memberId);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Remove a member from selected senders list
  Future<bool> removeSelectedSender({
    required String groupId,
    required String memberId,
  }) async {
    if (!_initialized) return false;

    final result = _bindings.groupRemoveSelectedSender(groupId, memberId);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Check if a member can send messages in this group
  bool canMemberSend({
    required String groupId,
    required String memberId,
  }) {
    if (!_initialized) return false;
    return _bindings.groupCanSend(groupId, memberId);
  }

  /// Get group type (0 = basic, 1 = supergroup)
  int getGroupType(String groupId) {
    if (!_initialized) return 0;
    return _bindings.groupGetType(groupId);
  }

  /// Upgrade group to supergroup
  Future<bool> upgradeToSupergroup(String groupId) async {
    if (!_initialized) return false;

    final result = _bindings.groupUpgradeToSupergroup(groupId);
    if (result == CyxChatError.ok) {
      notifyListeners();
      return true;
    }
    return false;
  }

  // ============================================================
  // Queries (FFI)
  // ============================================================

  /// Get number of groups in FFI context
  int get groupCount => _initialized ? _bindings.groupCount() : 0;

  /// Check if we are member of group (FFI)
  bool isMember(String groupId) {
    if (!_initialized) return false;
    return _bindings.groupIsMember(groupId);
  }

  /// Check if we are admin of group (FFI)
  bool isAdmin(String groupId) {
    if (!_initialized) return false;
    return _bindings.groupIsAdmin(groupId);
  }

  /// Check if we are owner of group (FFI)
  bool isOwner(String groupId) {
    if (!_initialized) return false;
    return _bindings.groupIsOwner(groupId);
  }

  /// Get our role in group (FFI)
  int getRole(String groupId) {
    if (!_initialized) return CyxChatGroupRole.member;
    return _bindings.groupGetRole(groupId);
  }

  // ============================================================
  // Media Sharing (Phase 5)
  // ============================================================

  /// Send a file to a group
  Future<GroupFFIResult> sendFile({
    required String groupId,
    required String filename,
    required List<int> fileData,
    List<int>? thumbnailData,
  }) async {
    final log = LogService.instance;
    if (!_initialized) {
      return GroupFFIResult.failure('Group FFI not initialized');
    }

    final result = _bindings.groupSendFile(
      groupId,
      filename,
      fileData,
      thumbnailData,
    );

    if (result.error == CyxChatError.ok && result.msgId != null) {
      log.info('Sent file "$filename" (${fileData.length} bytes) to group',
          source: 'GroupFFI');
      return GroupFFIResult.success(
        msgId: result.msgId,
        fileId: result.fileId,
      );
    } else {
      final errorStr = _bindings.errorString(result.error);
      log.error('Failed to send file: $errorStr', source: 'GroupFFI');
      return GroupFFIResult.failure('Failed to send file: $errorStr');
    }
  }

  /// Send a voice message to a group
  Future<GroupFFIResult> sendVoice({
    required String groupId,
    required List<int> audioData,
    required int durationMs,
  }) async {
    final log = LogService.instance;
    if (!_initialized) {
      return GroupFFIResult.failure('Group FFI not initialized');
    }

    final result = _bindings.groupSendVoice(
      groupId,
      audioData,
      durationMs,
    );

    if (result.error == CyxChatError.ok && result.msgId != null) {
      final seconds = (durationMs / 1000).toStringAsFixed(1);
      log.info('Sent voice message (${seconds}s) to group', source: 'GroupFFI');
      return GroupFFIResult.success(msgId: result.msgId);
    } else {
      final errorStr = _bindings.errorString(result.error);
      log.error('Failed to send voice message: $errorStr', source: 'GroupFFI');
      return GroupFFIResult.failure('Failed to send voice message: $errorStr');
    }
  }

  /// Send an image to a group
  Future<GroupFFIResult> sendImage({
    required String groupId,
    String? filename,
    required List<int> imageData,
    required int width,
    required int height,
  }) async {
    final log = LogService.instance;
    if (!_initialized) {
      return GroupFFIResult.failure('Group FFI not initialized');
    }

    final result = _bindings.groupSendImage(
      groupId,
      filename,
      imageData,
      width,
      height,
    );

    if (result.error == CyxChatError.ok && result.msgId != null) {
      log.info('Sent image (${width}x$height) to group', source: 'GroupFFI');
      return GroupFFIResult.success(msgId: result.msgId);
    } else {
      final errorStr = _bindings.errorString(result.error);
      log.error('Failed to send image: $errorStr', source: 'GroupFFI');
      return GroupFFIResult.failure('Failed to send image: $errorStr');
    }
  }

  /// Get the count of media items in a group
  /// mediaType: -1 for all types, or specific media type
  int getMediaCount(String groupId, {int mediaType = -1}) {
    if (!_initialized) return 0;
    return _bindings.groupGetMediaCount(groupId, mediaType: mediaType);
  }

  // ============================================================
  // Private Methods
  // ============================================================

  void _setupCallbacks() {
    // Set up Dart callbacks that will be invoked from FFI
    _bindings.onGroupMessage = _onGroupMessage;
    _bindings.onGroupInvite = _onGroupInvite;
    _bindings.onMemberJoin = _onMemberJoin;
    _bindings.onMemberLeave = _onMemberLeave;
    _bindings.onKeyUpdate = _onKeyUpdate;
    _bindings.onKeyDistComplete = _onKeyDistComplete;

    // Register native callbacks
    _bindings.groupSetupCallbacks();
  }

  void _onGroupMessage(String groupId, String from, String msgId, String text) {
    final log = LogService.instance;
    final shortFrom = from.length > 8 ? from.substring(0, 8) : from;
    final preview = text.length > 20 ? '${text.substring(0, 20)}...' : text;
    log.info('Group message from $shortFrom...: "$preview"',
        source: 'GroupFFI');

    _messageController.add(GroupMessageReceived(
      groupId: groupId,
      fromNodeId: from,
      msgId: msgId,
      text: text,
    ));
  }

  void _onGroupInvite(String groupId, String groupName, String inviter) {
    final log = LogService.instance;
    log.info('Received invite to "$groupName" from ${inviter.substring(0, 8)}...',
        source: 'GroupFFI');

    final invite = GroupInvite(
      groupId: groupId,
      groupName: groupName,
      inviterId: inviter,
      receivedAt: DateTime.now(),
    );

    _pendingInvites[groupId] = invite;
    _inviteController.add(invite);
    notifyListeners();
  }

  void _onMemberJoin(String groupId, String memberId) {
    final log = LogService.instance;
    log.info('Member ${memberId.substring(0, 8)}... joined group',
        source: 'GroupFFI');

    _memberEventController.add(MemberEvent(
      groupId: groupId,
      memberId: memberId,
      isJoin: true,
    ));
    notifyListeners();
  }

  void _onMemberLeave(String groupId, String memberId, bool wasKicked) {
    final log = LogService.instance;
    final action = wasKicked ? 'kicked from' : 'left';
    log.info('Member ${memberId.substring(0, 8)}... $action group',
        source: 'GroupFFI');

    _memberEventController.add(MemberEvent(
      groupId: groupId,
      memberId: memberId,
      isJoin: false,
      wasKicked: wasKicked,
    ));
    notifyListeners();
  }

  void _onKeyUpdate(String groupId, int newVersion) {
    final log = LogService.instance;
    log.info('Group key updated to version $newVersion', source: 'GroupFFI');

    _keyUpdateController.add(KeyUpdateEvent(
      groupId: groupId,
      newVersion: newVersion,
    ));
    notifyListeners();
  }

  void _onKeyDistComplete(
      String groupId, int newVersion, bool success, int failedCount) {
    final log = LogService.instance;
    if (success) {
      log.info('Key distribution complete for version $newVersion',
          source: 'GroupFFI');
    } else {
      log.warning('Key distribution incomplete: $failedCount members failed',
          source: 'GroupFFI');
    }

    final progress = KeyDistProgress(
      groupId: groupId,
      sent: 0,
      acked: 0,
      total: 0,
      complete: true,
      success: success,
      failedCount: failedCount,
    );

    _keyDistProgress[groupId] = progress;
    _keyDistCompleteController.add(progress);
    notifyListeners();
  }

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
    _bindings.groupPoll(now);

    // Update key distribution progress for active distributions
    _updateKeyDistProgress();
  }

  void _updateKeyDistProgress() {
    // Query progress for all groups that might have active distributions
    for (final groupId in _keyDistProgress.keys.toList()) {
      final progress = _bindings.groupKeyDistProgress(groupId);
      if (progress != null) {
        _keyDistProgress[groupId] = KeyDistProgress(
          groupId: groupId,
          sent: progress['sent']!,
          acked: progress['acked']!,
          total: progress['total']!,
        );
      }
    }
  }

  @override
  void dispose() {
    shutdown();
    _messageController.close();
    _inviteController.close();
    _memberEventController.close();
    _keyUpdateController.close();
    _keyDistCompleteController.close();
    super.dispose();
  }
}

/// Riverpod provider for GroupFFIProvider
final groupFFINotifierProvider =
    ChangeNotifierProvider<GroupFFIProvider>((ref) {
  return GroupFFIProvider();
});

/// Provider for pending group invites from FFI
final pendingGroupInvitesProvider = Provider<List<GroupInvite>>((ref) {
  return ref.watch(groupFFINotifierProvider).pendingInvites;
});

/// Provider for group FFI message stream
final groupFFIMessageStreamProvider =
    StreamProvider<GroupMessageReceived>((ref) {
  return ref.watch(groupFFINotifierProvider).messageStream;
});

/// Provider for group invite stream from FFI
final groupFFIInviteStreamProvider = StreamProvider<GroupInvite>((ref) {
  return ref.watch(groupFFINotifierProvider).inviteStream;
});

/// Provider for member event stream from FFI
final groupFFIMemberEventStreamProvider = StreamProvider<MemberEvent>((ref) {
  return ref.watch(groupFFINotifierProvider).memberEventStream;
});

/// Provider for key update stream from FFI
final groupFFIKeyUpdateStreamProvider = StreamProvider<KeyUpdateEvent>((ref) {
  return ref.watch(groupFFINotifierProvider).keyUpdateStream;
});

/// Provider for key distribution complete stream from FFI
final groupFFIKeyDistCompleteStreamProvider =
    StreamProvider<KeyDistProgress>((ref) {
  return ref.watch(groupFFINotifierProvider).keyDistCompleteStream;
});
