import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';

/// Native callback type for file request
typedef _FileRequestCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> from,
    Pointer<_FileMetaNative> meta,
    Pointer<Void> userData);

/// Native callback type for file complete
typedef _FileCompleteCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> fileId,
    Pointer<Uint8> data,
    Size dataLen,
    Pointer<Void> userData);

/// Native callback type for file progress
typedef _FileProgressCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> fileId,
    Uint16 chunksDone,
    Uint16 chunksTotal,
    Pointer<Void> userData);

/// Native callback type for file error
typedef _FileErrorCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> fileId,
    Int32 error,
    Pointer<Void> userData);

/// Native callback type for group message
/// msg_payload is a C string: "<16-hex-msg-id>:<text>"
typedef _GroupMessageCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> from,
    Pointer<Void> msg,
    Pointer<Void> userData);

/// Native callback type for group media metadata/content
typedef _GroupMediaCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<_GroupMediaNative> media,
    Pointer<Uint8> data,
    Size dataLen,
    Pointer<Void> userData);

/// Native callback type for group invite
typedef _GroupInviteCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Void> invite,
    Pointer<Void> userData);

/// Native callback type for member join
typedef _MemberJoinCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> member,
    Pointer<Void> userData);

/// Native callback type for member leave
typedef _MemberLeaveCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> member,
    Int32 wasKicked,
    Pointer<Void> userData);

/// Native callback type for key update
typedef _KeyUpdateCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Uint32 newVersion,
    Pointer<Void> userData);

/// Native callback type for key distribution complete
typedef _KeyDistCompleteCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Uint32 newVersion,
    Int32 success,
    Size failedCount,
    Pointer<Void> userData);

/// Native callback type for group delivery success
typedef _GroupDeliveryCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> msgId,
    Size ackedCount,
    Size totalCount,
    Pointer<Void> userData);

/// Native callback type for group delivery failure
typedef _GroupDeliveryFailedCallback = Void Function(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> msgId,
    Pointer<Uint8> failedMembers,
    Size failedCount,
    Pointer<Void> userData);

/// Native callback type for connection progress
typedef _ConnProgressCallback = Void Function(
    Pointer<Uint8> peerId,
    Int32 event,
    Uint8 retryNum,
    Uint8 retryMax,
    Int32 failReason,
    Pointer<Void> userData);

/// Native callback type for presence query response
typedef _PresenceCallback = Void Function(
    Pointer<Uint8> peerId,
    Int32 online,
    Pointer<Void> userData);

/// Connection progress event types (matches cyxchat_conn_event_t)
class CyxChatConnEvent {
  static const int lookupStarted = 0;
  static const int peerFound = 1;
  static const int announceSent = 2;
  static const int announceRetry = 3;
  static const int keyReceived = 4;
  static const int holePunchStart = 5;
  static const int connectedP2p = 6;
  static const int relayFallback = 7;
  static const int connectedRelay = 8;
  static const int disconnected = 9;
  static const int failed = 10;
}

/// Connection failure reasons (matches cyxchat_conn_fail_t)
class CyxChatConnFail {
  static const int none = 0;
  static const int lookupTimeout = 1;
  static const int keyTimeout = 2;
  static const int peerUnreachable = 3;
  static const int natBlocked = 4;
  static const int relayUnavailable = 5;

  static String message(int code) {
    switch (code) {
      case lookupTimeout:
        return 'Network lookup timed out';
      case keyTimeout:
        return 'Key exchange timed out';
      case peerUnreachable:
        return 'Peer appears offline';
      case natBlocked:
        return 'NAT blocked, relay unavailable';
      case relayUnavailable:
        return 'Relay server unavailable';
      default:
        return 'Connection failed';
    }
  }
}

/// Native file metadata structure
final class _FileMetaNative extends Struct {
  @Array(8)
  external Array<Uint8> fileId;

  @Array(128)
  external Array<Int8> filename;

  @Array(64)
  external Array<Int8> mimeType;

  @Uint32()
  external int size;

  @Uint16()
  external int chunkCount;

  @Array(32)
  external Array<Uint8> fileKey;

  @Array(32)
  external Array<Uint8> fileHash;
}

/// Native group media metadata structure (matches cyxchat_group_media_t)
final class _GroupMediaNative extends Struct {
  @Array(8)
  external Array<Uint8> msgId;

  @Array(8)
  external Array<Uint8> groupId;

  @Array(32)
  external Array<Uint8> senderId;

  @Array(8)
  external Array<Uint8> fileId;

  @Int32()
  external int mediaType;

  @Uint64()
  external int fileSize;

  @Uint32()
  external int durationMs;

  @Uint16()
  external int width;

  @Uint16()
  external int height;

  @Array(128)
  external Array<Int8> filename;

  @Array(64)
  external Array<Int8> mimeType;

  @Uint32()
  external int thumbnailSize;

  @Uint64()
  external int timestamp;
}

class GroupMediaMetadata {
  final String groupId;
  final String fromNodeId;
  final String msgId;
  final String fileId;
  final int mediaType;
  final int fileSize;
  final int durationMs;
  final int width;
  final int height;
  final String filename;
  final String mimeType;
  final int thumbnailSize;
  final int timestampMs;
  final Uint8List? data;

  const GroupMediaMetadata({
    required this.groupId,
    required this.fromNodeId,
    required this.msgId,
    required this.fileId,
    required this.mediaType,
    required this.fileSize,
    required this.durationMs,
    required this.width,
    required this.height,
    required this.filename,
    required this.mimeType,
    required this.thumbnailSize,
    required this.timestampMs,
    this.data,
  });
}

/// Native invite link structure (matches cyxchat_invite_link_t)
final class _InviteLinkNative extends Struct {
  @Array(16)
  external Array<Uint8> linkId;

  @Array(8)
  external Array<Uint8> groupId;

  @Array(32)
  external Array<Uint8> creatorId;

  @Uint64()
  external int createdAt;

  @Uint64()
  external int expiresAt;

  @Uint32()
  external int maxUses;

  @Uint32()
  external int useCount;

  @Uint8()
  external int isRevoked;

  @Array(64)
  external Array<Int8> name;
}

/// Native admin action structure (matches cyxchat_admin_action_t)
final class _AdminActionNative extends Struct {
  @Array(16)
  external Array<Uint8> actionId;

  @Array(8)
  external Array<Uint8> groupId;

  @Array(32)
  external Array<Uint8> adminId;

  @Int32()
  external int actionType;

  @Array(32)
  external Array<Uint8> targetId;

  @Array(8)
  external Array<Uint8> targetMsgId;

  @Uint64()
  external int timestamp;

  @Array(256)
  external Array<Int8> oldValue;

  @Array(256)
  external Array<Int8> newValue;
}

/// FFI bindings for libcyxchat
class CyxChatBindings {
  static CyxChatBindings? _instance;
  static CyxChatBindings get instance => _instance ??= CyxChatBindings._();

  late final DynamicLibrary _lib;
  late final CyxChatNative _native;

  CyxChatBindings._() {
    _lib = _loadLibrary();
    _native = CyxChatNative(_lib);
  }

  DynamicLibrary _loadLibrary() {
    if (Platform.isWindows) {
      return DynamicLibrary.open('cyxchat.dll');
    } else if (Platform.isMacOS) {
      return DynamicLibrary.open('libcyxchat.dylib');
    } else if (Platform.isLinux) {
      return DynamicLibrary.open('libcyxchat.so');
    } else if (Platform.isAndroid) {
      return DynamicLibrary.open('libcyxchat.so');
    } else if (Platform.isIOS) {
      return DynamicLibrary.process();
    }
    throw UnsupportedError('Platform not supported');
  }

  /// Initialize the library
  int init() => _native.cyxchat_init();

  /// Shutdown the library
  void shutdown() => _native.cyxchat_shutdown();

  /// Check if initialized
  bool isInitialized() => _native.cyxchat_is_initialized() != 0;

  /// Get version string
  String version() {
    final ptr = _native.cyxchat_version();
    return ptr.cast<Utf8>().toDartString();
  }

  /// Get error string
  String errorString(int error) {
    final ptr = _native.cyxchat_error_string(error);
    return ptr.cast<Utf8>().toDartString();
  }

  /// Generate message ID
  void generateMsgId(Pointer<Uint8> msgIdOut) {
    _native.cyxchat_generate_msg_id(msgIdOut);
  }

  /// Get current timestamp in milliseconds
  int timestampMs() => _native.cyxchat_timestamp_ms();

  /// Compare message IDs
  int msgIdCmp(Pointer<Uint8> a, Pointer<Uint8> b) {
    return _native.cyxchat_msg_id_cmp(a, b);
  }

  /// Check if message ID is zero
  bool msgIdIsZero(Pointer<Uint8> id) {
    return _native.cyxchat_msg_id_is_zero(id) != 0;
  }

  // ============================================================
  // Chat Core
  // ============================================================

  /// Chat context pointer (opaque)
  Pointer<Void>? _chatCtx;

  /// Get chat context (for modules that depend on it)
  Pointer<Void>? get chatCtx => _chatCtx;

  /// Create chat context
  /// Requires onion context from connection
  int chatCreate(Pointer<Uint8> localId) {
    if (_connCtx == null) return CyxChatError.errNull;
    final ctxPtr = calloc<Pointer<Void>>();
    try {
      // Get onion context from connection
      final onion = _native.cyxchat_conn_get_onion(_connCtx!);
      if (onion == nullptr) return CyxChatError.errNull;

      final result = _native.cyxchat_create(ctxPtr, onion, localId);
      if (result == 0) {
        _chatCtx = ctxPtr.value;
      }
      return result;
    } finally {
      calloc.free(ctxPtr);
    }
  }

  /// Destroy chat context
  void chatDestroy() {
    if (_chatCtx != null) {
      _native.cyxchat_destroy(_chatCtx!);
      _chatCtx = null;
    }
  }

  /// Poll chat events
  int chatPoll(int nowMs) {
    if (_chatCtx == null) return 0;
    return _native.cyxchat_poll(_chatCtx!, nowMs);
  }

  /// Set preferred onion routing hop count (1-8, or 0 for auto)
  void setHopCount(int hopCount) {
    if (_chatCtx == null) return;
    _native.cyxchat_set_hop_count(_chatCtx!, hopCount);
  }

  /// Get current onion routing hop count (0 = auto)
  int getHopCount() {
    if (_chatCtx == null) return 0;
    return _native.cyxchat_get_hop_count(_chatCtx!);
  }

  /// Get the onion secret key for persistence
  /// Returns 32-byte key or null on error
  List<int>? getOnionSecret() {
    if (_chatCtx == null) return null;

    final secretPtr = calloc<Uint8>(32);
    try {
      final result = _native.cyxchat_get_onion_secret(_chatCtx!, secretPtr);
      if (result == CyxChatError.ok) {
        return List<int>.generate(32, (i) => secretPtr[i]);
      }
      return null;
    } finally {
      calloc.free(secretPtr);
    }
  }

  /// Set the onion keypair from a saved secret key
  /// Call after create() but before connecting to restore the keypair
  bool setOnionKeypair(List<int> secretKey) {
    if (_chatCtx == null || secretKey.length != 32) return false;

    final secretPtr = calloc<Uint8>(32);
    try {
      for (int i = 0; i < 32; i++) {
        secretPtr[i] = secretKey[i];
      }
      final result = _native.cyxchat_set_onion_keypair(_chatCtx!, secretPtr);
      return result == CyxChatError.ok;
    } finally {
      calloc.free(secretPtr);
    }
  }

  /// Get next received message
  /// Returns map with 'from', 'type', 'msgId', 'data' keys, or null if queue empty
  Map<String, dynamic>? chatRecvNext() {
    if (_chatCtx == null) return null;

    final fromPtr = calloc<Uint8>(32);
    final typePtr = calloc<Uint8>(1);
    final msgIdPtr = calloc<Uint8>(8);
    final dataPtr = calloc<Uint8>(4096);
    final lenPtr = calloc<Size>(1);
    lenPtr.value = 4096;

    try {
      final result = _native.cyxchat_recv_next(
        _chatCtx!,
        fromPtr,
        typePtr,
        msgIdPtr,
        dataPtr,
        lenPtr,
      );

      if (result != 0) {
        // Copy data before freeing
        final fromBytes = List<int>.generate(32, (i) => fromPtr[i]);
        final type = typePtr[0];
        final msgId = List<int>.generate(8, (i) => msgIdPtr[i]);
        final dataLen = lenPtr.value;
        final data = List<int>.generate(dataLen, (i) => dataPtr[i]);

        return {
          'from': fromBytes,
          'type': type,
          'msgId': msgId,
          'data': data,
        };
      }
      return null;
    } finally {
      calloc.free(fromPtr);
      calloc.free(typePtr);
      calloc.free(msgIdPtr);
      calloc.free(dataPtr);
      calloc.free(lenPtr);
    }
  }

  /// Generate a random message ID (8 bytes)
  Uint8List? chatGenerateMsgId() {
    if (_chatCtx == null) return null;
    final msgIdPtr = calloc<Uint8>(8);
    try {
      _native.cyxchat_generate_msg_id(msgIdPtr);
      final msgId = Uint8List(8);
      for (int i = 0; i < 8; i++) {
        msgId[i] = msgIdPtr[i];
      }
      return msgId;
    } finally {
      calloc.free(msgIdPtr);
    }
  }

  /// Send raw message bytes (must include wire header)
  int chatSendRaw(Pointer<Uint8> to, Uint8List data) {
    if (_chatCtx == null) return CyxChatError.errNull;
    if (data.isEmpty) return CyxChatError.errInvalid;
    final dataPtr = calloc<Uint8>(data.length);
    try {
      for (int i = 0; i < data.length; i++) {
        dataPtr[i] = data[i];
      }
      return _native.cyxchat_send_raw(_chatCtx!, to, dataPtr, data.length);
    } finally {
      calloc.free(dataPtr);
    }
  }

  /// Send text message
  /// Returns message ID hex string on success, null on failure
  String? chatSendText(
    Pointer<Uint8> to,
    String text, {
    String? replyToHex,
  }) {
    if (_chatCtx == null) return null;

    final textPtr = text.toNativeUtf8();
    final replyToPtr = calloc<Uint8>(8);
    final msgIdOutPtr = calloc<Uint8>(8);

    try {
      if (replyToHex != null) {
        final replyHexPtr = replyToHex.toNativeUtf8();
        final parseResult = _native.cyxchat_msg_id_from_hex(
          replyHexPtr.cast(),
          replyToPtr,
        );
        calloc.free(replyHexPtr);
        if (parseResult != 0) return null;
      }

      final result = _native.cyxchat_send_text(
        _chatCtx!,
        to,
        textPtr.cast(),
        text.length,
        replyToHex != null ? replyToPtr : nullptr,
        msgIdOutPtr,
      );

      if (result == 0) {
        final hexOut = calloc<Int8>(17);
        _native.cyxchat_msg_id_to_hex(msgIdOutPtr, hexOut);
        final hex = hexOut.cast<Utf8>().toDartString();
        calloc.free(hexOut);
        return hex;
      }
      return null;
    } finally {
      calloc.free(textPtr);
      calloc.free(replyToPtr);
      calloc.free(msgIdOutPtr);
    }
  }

  /// Set message ID to use for next send (for retries with same msg_id)
  /// Call this immediately before chatSendText() when retrying
  void chatSetNextMsgId(String? msgIdHex) {
    if (_chatCtx == null) return;

    if (msgIdHex == null || msgIdHex.isEmpty) {
      // Clear override
      _native.cyxchat_set_next_msg_id(_chatCtx!, nullptr);
      return;
    }

    final msgIdPtr = calloc<Uint8>(8);
    final hexPtr = msgIdHex.toNativeUtf8();
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        hexPtr.cast(),
        msgIdPtr,
      );
      if (parseResult != 0) {
        print('[FFI] Failed to parse msg_id hex for retry: $msgIdHex');
        return;
      }
      _native.cyxchat_set_next_msg_id(_chatCtx!, msgIdPtr);
    } finally {
      calloc.free(hexPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Send ACK for received message
  int chatSendAck(Pointer<Uint8> to, String msgIdHex, int status) {
    if (_chatCtx == null) return CyxChatError.errNull;

    final msgIdPtr = calloc<Uint8>(8);
    final hexPtr = msgIdHex.toNativeUtf8();
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        hexPtr.cast(),
        msgIdPtr,
      );
      if (parseResult != 0) return parseResult;

      return _native.cyxchat_send_ack(_chatCtx!, to, msgIdPtr, status);
    } finally {
      calloc.free(hexPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Send typing indicator
  int chatSendTyping(Pointer<Uint8> to, bool isTyping) {
    if (_chatCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_send_typing(_chatCtx!, to, isTyping ? 1 : 0);
  }

  /// Send reaction to message
  int chatSendReaction(
    Pointer<Uint8> to,
    String msgIdHex,
    String reaction, {
    bool remove = false,
  }) {
    if (_chatCtx == null) return CyxChatError.errNull;

    final msgIdPtr = calloc<Uint8>(8);
    final reactionPtr = reaction.toNativeUtf8();
    final hexPtr = msgIdHex.toNativeUtf8();
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        hexPtr.cast(),
        msgIdPtr,
      );
      if (parseResult != 0) return parseResult;

      return _native.cyxchat_send_reaction(
        _chatCtx!,
        to,
        msgIdPtr,
        reactionPtr.cast(),
        remove ? 1 : 0,
      );
    } finally {
      calloc.free(hexPtr);
      calloc.free(msgIdPtr);
      calloc.free(reactionPtr);
    }
  }

  /// Request message deletion
  int chatSendDelete(Pointer<Uint8> to, String msgIdHex) {
    if (_chatCtx == null) return CyxChatError.errNull;

    final msgIdPtr = calloc<Uint8>(8);
    final hexPtr = msgIdHex.toNativeUtf8();
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        hexPtr.cast(),
        msgIdPtr,
      );
      if (parseResult != 0) return parseResult;

      return _native.cyxchat_send_delete(_chatCtx!, to, msgIdPtr);
    } finally {
      calloc.free(hexPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Send edited message
  int chatSendEdit(Pointer<Uint8> to, String msgIdHex, String newText) {
    if (_chatCtx == null) return CyxChatError.errNull;

    final msgIdPtr = calloc<Uint8>(8);
    final textPtr = newText.toNativeUtf8();
    final hexPtr = msgIdHex.toNativeUtf8();
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        hexPtr.cast(),
        msgIdPtr,
      );
      if (parseResult != 0) return parseResult;

      return _native.cyxchat_send_edit(
        _chatCtx!,
        to,
        msgIdPtr,
        textPtr.cast(),
        newText.length,
      );
    } finally {
      calloc.free(hexPtr);
      calloc.free(msgIdPtr);
      calloc.free(textPtr);
    }
  }

  // ============================================================
  // Connection Management
  // ============================================================

  /// Connection context pointer (opaque)
  Pointer<Void>? _connCtx;

  /// Progress callback
  NativeCallable<_ConnProgressCallback>? _onConnProgress;
  void Function(String peerId, int event, int retry, int max, int fail)?
      onConnProgress;

  /// Presence callback
  NativeCallable<_PresenceCallback>? _onPresence;
  void Function(String peerId, bool online)? onPresence;

  /// Create connection context
  /// Returns error code (0 = success)
  int connCreate(String bootstrap, Pointer<Uint8> localId) {
    final bootstrapPtr = bootstrap.toNativeUtf8();
    final ctxPtr = calloc<Pointer<Void>>();
    try {
      final result = _native.cyxchat_conn_create(ctxPtr, bootstrapPtr.cast(), localId);
      if (result == 0) {
        _connCtx = ctxPtr.value;
      }
      return result;
    } finally {
      calloc.free(bootstrapPtr);
      calloc.free(ctxPtr);
    }
  }

  /// Destroy connection context
  void connDestroy() {
    if (_connCtx != null) {
      _onConnProgress?.close();
      _onConnProgress = null;
      _onPresence?.close();
      _onPresence = null;
      _native.cyxchat_conn_destroy(_connCtx!);
      _connCtx = null;
    }
  }

  /// Setup connection progress callback for real-time UI feedback
  void connSetupProgressCallback() {
    if (_connCtx == null) {
      print('FFI: connSetupProgressCallback - no conn ctx!');
      return;
    }

    // Close previous callback if exists to prevent memory leak on re-init
    _onConnProgress?.close();

    _onConnProgress = NativeCallable<_ConnProgressCallback>.listener(
      _handleConnProgress,
    );
    _native.cyxchat_conn_set_on_progress(
      _connCtx!,
      _onConnProgress!.nativeFunction,
      nullptr,
    );
    print('FFI: Progress callback registered with C library');
  }

  /// Handle connection progress events from C library
  void _handleConnProgress(
    Pointer<Uint8> peerId,
    int event,
    int retryNum,
    int retryMax,
    int failReason,
    Pointer<Void> userData,
  ) {
    // Debug: C library called this callback
    print('FFI: _handleConnProgress event=$event retry=$retryNum');
    if (onConnProgress == null) return;

    // Convert peer ID to node ID format (UUID if applicable)
    // This must match the format used by conversations for progress lookup
    final bytes = <int>[];
    for (int i = 0; i < 32; i++) {
      bytes.add(peerId[i]);
    }
    // Check if bytes 16-31 are all zeros (UUID-style node ID)
    bool isUuid = true;
    for (int i = 16; i < 32; i++) {
      if (bytes[i] != 0) { isUuid = false; break; }
    }
    String nodeId;
    if (isUuid) {
      // Format first 16 bytes as UUID: 8-4-4-4-12
      final hex = bytes.sublist(0, 16)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      nodeId = '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
          '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
          '${hex.substring(20, 32)}';
    } else {
      nodeId = _ptrToHex(peerId, 32);
    }

    // Invoke the Dart callback
    onConnProgress!(nodeId, event, retryNum, retryMax, failReason);
  }

  /// Setup presence query callback
  void connSetupPresenceCallback() {
    if (_connCtx == null) {
      print('FFI: connSetupPresenceCallback - no conn ctx!');
      return;
    }

    // Close previous callback if exists
    _onPresence?.close();

    _onPresence = NativeCallable<_PresenceCallback>.listener(
      _handlePresence,
    );
    _native.cyxchat_conn_set_presence_callback(
      _connCtx!,
      _onPresence!.nativeFunction,
      nullptr,
    );
    print('FFI: Presence callback registered with C library');
  }

  /// Handle presence query response from C library
  void _handlePresence(
    Pointer<Uint8> peerId,
    int online,
    Pointer<Void> userData,
  ) {
    print('FFI: _handlePresence online=$online');
    if (onPresence == null) return;

    // Convert peer ID to hex string
    final hexId = _ptrToHex(peerId, 32);

    // Invoke the Dart callback
    onPresence!(hexId, online != 0);
  }

  /// Query presence of a peer from server
  int connQueryPresence(Pointer<Uint8> peerId) {
    if (_connCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_conn_query_presence(_connCtx!, peerId);
  }

  /// Poll connection events
  int connPoll(int nowMs) {
    if (_connCtx == null) return 0;
    return _native.cyxchat_conn_poll(_connCtx!, nowMs);
  }

  /// Initiate connection to peer
  int connConnect(Pointer<Uint8> peerId) {
    if (_connCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_conn_connect(_connCtx!, peerId, nullptr, nullptr);
  }

  /// Disconnect from peer
  int connDisconnect(Pointer<Uint8> peerId) {
    if (_connCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_conn_disconnect(_connCtx!, peerId);
  }

  /// Get connection state for peer
  /// Returns: 0=Disconnected, 1=Discovering, 2=Connecting, 3=Relaying, 4=Connected
  int connGetState(Pointer<Uint8> peerId) {
    if (_connCtx == null) return 0;
    return _native.cyxchat_conn_get_state(_connCtx!, peerId);
  }

  /// Check if connection is relayed
  bool connIsRelayed(Pointer<Uint8> peerId) {
    if (_connCtx == null) return false;
    return _native.cyxchat_conn_is_relayed(_connCtx!, peerId) != 0;
  }

  /// Send data to peer
  int connSend(Pointer<Uint8> peerId, Pointer<Uint8> data, int len) {
    if (_connCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_conn_send(_connCtx!, peerId, data, len);
  }

  /// Get public address as string (after STUN discovery)
  String? connGetPublicAddr() {
    if (_connCtx == null) return null;
    final buf = calloc<Int8>(32);
    try {
      final result = _native.cyxchat_conn_get_public_addr(_connCtx!, buf, 32);
      if (result == 0) {
        return buf.cast<Utf8>().toDartString();
      }
      return null;
    } finally {
      calloc.free(buf);
    }
  }

  /// Check if connected to bootstrap server (received register ACK)
  bool connIsBootstrapConnected() {
    if (_connCtx == null) return false;
    return _native.cyxchat_conn_is_bootstrap_connected(_connCtx!) != 0;
  }

  /// Check if UPnP/NAT-PMP gateway was discovered
  bool connIsUpnpAvailable() {
    if (_connCtx == null) return false;
    return _native.cyxchat_conn_is_upnp_available(_connCtx!) != 0;
  }

  /// Check if UPnP/NAT-PMP port mapping is active
  bool connIsUpnpMappingActive() {
    if (_connCtx == null) return false;
    return _native.cyxchat_conn_is_upnp_mapping_active(_connCtx!) != 0;
  }

  /// Get UPnP/NAT-PMP external port (0 if no mapping)
  int connGetUpnpExternalPort() {
    if (_connCtx == null) return 0;
    return _native.cyxchat_conn_get_upnp_external_port(_connCtx!);
  }

  /// Get UPnP/NAT-PMP lease remaining time in seconds (0 if no active mapping)
  int connGetUpnpLeaseRemainingSec() {
    if (_connCtx == null) return 0;
    return _native.cyxchat_conn_get_upnp_lease_remaining_sec(_connCtx!);
  }

  /// Check if we have established a secure key with a peer
  /// Key exchange must complete before messages can be sent
  bool connHasPeerKey(Pointer<Uint8> peerId) {
    if (_connCtx == null) return false;
    return _native.cyxchat_conn_has_peer_key(_connCtx!, peerId) != 0;
  }

  /// Get peer's X25519 public key by hex node ID
  /// Returns the 32-byte public key or null if not found
  List<int>? connGetPeerPubkeyHex(String peerIdHex) {
    if (_connCtx == null) return null;

    final peerIdBytes = _hexToBytes(peerIdHex);
    final peerIdPtr = calloc<Uint8>(32);
    final pubkeyOut = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerIdBytes.length; i++) {
        peerIdPtr[i] = peerIdBytes[i];
      }

      final result = _native.cyxchat_conn_get_peer_pubkey(_connCtx!, peerIdPtr, pubkeyOut);
      if (result == 0) {
        return List<int>.generate(32, (i) => pubkeyOut[i]);
      }
      return null;
    } finally {
      calloc.free(peerIdPtr);
      calloc.free(pubkeyOut);
    }
  }

  /// Get full 32-byte node ID from a prefix (first 8 bytes)
  /// Useful when the onion layer needs the full ID for key lookup
  List<int>? connGetFullNodeIdHex(String prefixIdHex) {
    if (_connCtx == null) return null;

    final prefixBytes = _hexToBytes(prefixIdHex);
    final prefixPtr = calloc<Uint8>(32);
    final fullIdOut = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < prefixBytes.length; i++) {
        prefixPtr[i] = prefixBytes[i];
      }

      final result = _native.cyxchat_conn_get_full_node_id(_connCtx!, prefixPtr, fullIdOut);
      if (result == 0) {
        return List<int>.generate(32, (i) => fullIdOut[i]);
      }
      return null;
    } finally {
      calloc.free(prefixPtr);
      calloc.free(fullIdOut);
    }
  }

  /// Get connection state name
  String connStateName(int state) {
    final ptr = _native.cyxchat_conn_state_name(state);
    return ptr.cast<Utf8>().toDartString();
  }

  /// Get NAT type name
  String connNatTypeName(int natType) {
    final ptr = _native.cyxchat_conn_nat_type_name(natType);
    return ptr.cast<Utf8>().toDartString();
  }

  /// Add relay server
  int connAddRelay(String addr) {
    if (_connCtx == null) return CyxChatError.errNull;
    final addrPtr = addr.toNativeUtf8();
    try {
      return _native.cyxchat_conn_add_relay(_connCtx!, addrPtr.cast());
    } finally {
      calloc.free(addrPtr);
    }
  }

  /// Add a server to the registry
  int connAddServer(String addr) {
    if (_connCtx == null) return CyxChatError.errNull;
    final addrPtr = addr.toNativeUtf8();
    try {
      return _native.cyxchat_conn_add_server(
          _connCtx!, addrPtr.cast(), nullptr.cast());
    } finally {
      calloc.free(addrPtr);
    }
  }

  /// Get number of servers in registry
  int connServerCount() {
    if (_connCtx == null) return 0;
    return _native.cyxchat_conn_server_count(_connCtx!);
  }

  /// Get number of healthy servers
  int connHealthyServerCount() {
    if (_connCtx == null) return 0;
    return _native.cyxchat_conn_healthy_server_count(_connCtx!);
  }

  /// Get all server info as a list of maps
  /// Each entry: {addr, state, latency_ms, avg_latency_ms, is_seed, is_healthy}
  List<Map<String, dynamic>> connGetServersInfo() {
    if (_connCtx == null) return [];
    final buf = calloc<Uint8>(4096);
    try {
      final written = _native.cyxchat_conn_get_servers_info(
          _connCtx!, buf.cast(), 4096);
      if (written <= 0) return [];

      final str = buf.cast<Utf8>().toDartString(length: written);
      final lines = str.split('\n').where((l) => l.isNotEmpty);
      return lines.map((line) {
        final parts = line.split('|');
        return {
          'addr': parts.isNotEmpty ? parts[0] : '',
          'state': parts.length > 1 ? parts[1] : 'unknown',
          'latency_ms': parts.length > 2 ? int.tryParse(parts[2]) ?? 0 : 0,
          'avg_latency_ms': parts.length > 3 ? int.tryParse(parts[3]) ?? 0 : 0,
          'is_seed': parts.length > 4 ? parts[4] == '1' : false,
          'is_healthy': parts.length > 5 ? parts[5] == '1' : false,
        };
      }).toList();
    } finally {
      calloc.free(buf);
    }
  }

  /// Get number of relay connections
  int connRelayCount() {
    if (_connCtx == null) return 0;
    return _native.cyxchat_conn_relay_count(_connCtx!);
  }

  /// Force relay for peer
  int connForceRelay(Pointer<Uint8> peerId) {
    if (_connCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_conn_force_relay(_connCtx!, peerId);
  }

  /// Add peer by address (for manual peer discovery)
  /// [nodeId] - Peer's 32-byte node ID
  /// [addr] - IP:port string (e.g., "127.0.0.1:55151")
  int connAddPeerAddr(Pointer<Uint8> nodeId, String addr) {
    if (_connCtx == null) return CyxChatError.errNull;
    final addrPtr = addr.toNativeUtf8();
    try {
      return _native.cyxchat_conn_add_peer_addr(_connCtx!, nodeId, addrPtr.cast());
    } finally {
      calloc.free(addrPtr);
    }
  }

  // ============================================================
  // DHT (Distributed Hash Table) for Peer Discovery
  // ============================================================

  /// Bootstrap DHT with seed nodes
  /// [seedNodes] - Flat array of node IDs (32 bytes each)
  /// [count] - Number of seed nodes
  int dhtBootstrap(Pointer<Uint8> seedNodes, int count) {
    if (_connCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_conn_dht_bootstrap(_connCtx!, seedNodes, count);
  }

  /// Add a known node to DHT routing table
  int dhtAddNode(Pointer<Uint8> nodeId) {
    if (_connCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_conn_dht_add_node(_connCtx!, nodeId);
  }

  /// Find a node via DHT (fire-and-forget, no callback)
  int dhtFindNode(Pointer<Uint8> targetId) {
    if (_connCtx == null) return CyxChatError.errNull;
    // Pass null for callback - fire-and-forget mode
    return _native.cyxchat_conn_dht_find_node(
        _connCtx!, targetId, nullptr, nullptr);
  }

  /// Get closest known nodes to target (synchronous)
  /// Returns list of node ID byte arrays
  List<List<int>> dhtGetClosest(Pointer<Uint8> targetId, {int maxNodes = 8}) {
    if (_connCtx == null) return [];

    // Allocate buffer for output nodes (32 bytes each)
    final outNodes = calloc<Uint8>(32 * maxNodes);
    try {
      final count =
          _native.cyxchat_conn_dht_get_closest(_connCtx!, targetId, outNodes, maxNodes);

      final result = <List<int>>[];
      for (int i = 0; i < count; i++) {
        final nodeBytes = <int>[];
        for (int j = 0; j < 32; j++) {
          nodeBytes.add(outNodes[i * 32 + j]);
        }
        result.add(nodeBytes);
      }
      return result;
    } finally {
      calloc.free(outNodes);
    }
  }

  /// Check if DHT is ready (has nodes)
  bool dhtIsReady() {
    if (_connCtx == null) return false;
    return _native.cyxchat_conn_dht_is_ready(_connCtx!) != 0;
  }

  // ============================================================
  // DNS Module
  // ============================================================

  /// DNS context pointer (opaque)
  Pointer<Void>? _dnsCtx;

  /// Create DNS context
  int dnsCreate(Pointer<Uint8> localId, Pointer<Uint8>? signingKey) {
    final ctxPtr = calloc<Pointer<Void>>();
    try {
      final result = _native.cyxchat_dns_create(
        ctxPtr,
        nullptr, // router - transport will be set up after connection
        localId,
        signingKey ?? nullptr,
      );
      if (result == 0) {
        _dnsCtx = ctxPtr.value;
        // Connect DNS to connection's transport for message broadcasting
        _connectDnsToTransport();
      }
      return result;
    } finally {
      calloc.free(ctxPtr);
    }
  }

  /// Connect DNS to connection transport (internal)
  void _connectDnsToTransport() {
    if (_dnsCtx == null || _connCtx == null) return;

    final transport = _native.cyxchat_conn_get_transport(_connCtx!);
    final peerTable = _native.cyxchat_conn_get_peer_table(_connCtx!);

    if (transport != nullptr && peerTable != nullptr) {
      _native.cyxchat_dns_set_transport(_dnsCtx!, transport, peerTable);
    }
  }

  /// Manually set DNS transport (call after connection is ready)
  int dnsSetTransport() {
    if (_dnsCtx == null || _connCtx == null) return CyxChatError.errNull;

    final transport = _native.cyxchat_conn_get_transport(_connCtx!);
    final peerTable = _native.cyxchat_conn_get_peer_table(_connCtx!);

    if (transport == nullptr || peerTable == nullptr) {
      return CyxChatError.errNull;
    }

    return _native.cyxchat_dns_set_transport(_dnsCtx!, transport, peerTable);
  }

  /// Destroy DNS context
  void dnsDestroy() {
    if (_dnsCtx != null) {
      _native.cyxchat_dns_destroy(_dnsCtx!);
      _dnsCtx = null;
    }
  }

  /// Poll DNS (call regularly from main loop)
  int dnsPoll(int nowMs) {
    if (_dnsCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_dns_poll(_dnsCtx!, nowMs);
  }

  /// Register a name
  int dnsRegister(String name) {
    if (_dnsCtx == null) return CyxChatError.errNull;
    final namePtr = name.toNativeUtf8();
    try {
      return _native.cyxchat_dns_register(_dnsCtx!, namePtr.cast(), nullptr, nullptr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Refresh registration
  int dnsRefresh() {
    if (_dnsCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_dns_refresh(_dnsCtx!);
  }

  /// Unregister name
  int dnsUnregister() {
    if (_dnsCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_dns_unregister(_dnsCtx!);
  }

  /// Get registered name
  String? dnsGetRegisteredName() {
    if (_dnsCtx == null) return null;
    final ptr = _native.cyxchat_dns_get_registered_name(_dnsCtx!);
    if (ptr == nullptr) return null;
    return ptr.cast<Utf8>().toDartString();
  }

  /// Lookup a name (async - checks cache, sends query)
  int dnsLookup(String name) {
    if (_dnsCtx == null) return CyxChatError.errNull;
    final namePtr = name.toNativeUtf8();
    try {
      return _native.cyxchat_dns_lookup(_dnsCtx!, namePtr.cast(), nullptr, nullptr);
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Resolve name from cache (sync)
  /// Returns node ID bytes or null if not found
  Pointer<Uint8>? dnsResolve(String name) {
    if (_dnsCtx == null) return null;
    final namePtr = name.toNativeUtf8();
    final recordPtr = calloc<Uint8>(4096); // DNS record is ~180 bytes
    try {
      final result = _native.cyxchat_dns_resolve(_dnsCtx!, namePtr.cast(), recordPtr);
      if (result == 0) {
        // Record starts with name (64 bytes), then node_id (32 bytes)
        // Skip name to get node_id
        final nodeIdPtr = calloc<Uint8>(32);
        for (int i = 0; i < 32; i++) {
          nodeIdPtr[i] = recordPtr[64 + i];
        }
        calloc.free(recordPtr);
        return nodeIdPtr;
      }
      return null;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Check if name is cached
  bool dnsIsCached(String name) {
    if (_dnsCtx == null) return false;
    final namePtr = name.toNativeUtf8();
    try {
      return _native.cyxchat_dns_is_cached(_dnsCtx!, namePtr.cast()) != 0;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Invalidate cached name
  void dnsInvalidate(String name) {
    if (_dnsCtx == null) return;
    final namePtr = name.toNativeUtf8();
    try {
      _native.cyxchat_dns_invalidate(_dnsCtx!, namePtr.cast());
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Set petname for a node
  int dnsSetPetname(Pointer<Uint8> nodeId, String petname) {
    if (_dnsCtx == null) return CyxChatError.errNull;
    final petnamePtr = petname.toNativeUtf8();
    try {
      return _native.cyxchat_dns_set_petname(_dnsCtx!, nodeId, petnamePtr.cast());
    } finally {
      calloc.free(petnamePtr);
    }
  }

  /// Get petname for a node
  String? dnsGetPetname(Pointer<Uint8> nodeId) {
    if (_dnsCtx == null) return null;
    final ptr = _native.cyxchat_dns_get_petname(_dnsCtx!, nodeId);
    if (ptr == nullptr) return null;
    return ptr.cast<Utf8>().toDartString();
  }

  /// Generate crypto-name from pubkey
  String dnsCryptoName(Pointer<Uint8> pubkey) {
    final nameOut = calloc<Int8>(20);
    try {
      _native.cyxchat_dns_crypto_name(pubkey, nameOut);
      return nameOut.cast<Utf8>().toDartString();
    } finally {
      calloc.free(nameOut);
    }
  }

  /// Check if name is a crypto-name
  bool dnsIsCryptoName(String name) {
    final namePtr = name.toNativeUtf8();
    try {
      return _native.cyxchat_dns_is_crypto_name(namePtr.cast()) != 0;
    } finally {
      calloc.free(namePtr);
    }
  }

  /// Validate name format
  bool dnsValidateName(String name) {
    final namePtr = name.toNativeUtf8();
    try {
      return _native.cyxchat_dns_validate_name(namePtr.cast()) != 0;
    } finally {
      calloc.free(namePtr);
    }
  }

  // ============================================================
  // Group Module
  // ============================================================

  /// Group context pointer (opaque)
  Pointer<Void>? _groupCtx;

  /// Create group context
  int groupCtxCreate(Pointer<Void> chatCtx) {
    final ctxPtr = calloc<Pointer<Void>>();
    try {
      final result = _native.cyxchat_group_ctx_create(ctxPtr, chatCtx);
      if (result == 0) {
        _groupCtx = ctxPtr.value;
        // Link group context to chat context for message routing
        _native.cyxchat_set_group_ctx(chatCtx, _groupCtx!);
        print("DEBUG: Linked group context to chat context");
      }
      return result;
    } finally {
      calloc.free(ctxPtr);
    }
  }

  /// Destroy group context
  void groupCtxDestroy() {
    if (_groupCtx != null) {
      _native.cyxchat_group_ctx_destroy(_groupCtx!);
      _groupCtx = null;
    }
  }

  /// Poll group events
  int groupPoll(int nowMs) {
    if (_groupCtx == null) return 0;
    return _native.cyxchat_group_poll(_groupCtx!, nowMs);
  }

  /// Create new group
  /// Returns group ID hex string or null on failure
  String? groupCreate(String name) {
    if (_groupCtx == null) return null;
    final namePtr = name.toNativeUtf8();
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final result = _native.cyxchat_group_create(
        _groupCtx!,
        namePtr.cast(),
        groupIdPtr,
      );
      if (result == 0) {
        return groupIdToHex(groupIdPtr);
      }
      return null;
    } finally {
      calloc.free(namePtr);
      calloc.free(groupIdPtr);
    }
  }

  /// Restore a group from saved data (for app restart)
  /// Returns 0 on success, error code otherwise
  int groupRestore({
    required String groupIdHex,
    required String name,
    required Uint8List groupKey,
    required int keyVersion,
    required String creatorIdHex,
    required int myRole,
  }) {
    if (_groupCtx == null) return CyxChatError.errNull;
    if (groupKey.length != 32) return CyxChatError.errInvalid;

    final groupIdPtr = calloc<Uint8>(8);
    final namePtr = name.toNativeUtf8();
    final groupKeyPtr = calloc<Uint8>(32);
    final creatorIdPtr = calloc<Uint8>(32);

    try {
      // Parse group ID from hex
      final parseGroupId = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseGroupId != 0) return parseGroupId;

      // Parse creator ID from hex (with validation)
      final cleanCreatorHex = creatorIdHex.replaceAll('-', '');
      if (cleanCreatorHex.length < 32 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleanCreatorHex)) {
        return CyxChatError.errInvalid; // Invalid creator ID hex format
      }
      for (int i = 0; i < 16; i++) {
        creatorIdPtr[i] = int.parse(cleanCreatorHex.substring(i * 2, i * 2 + 2), radix: 16);
      }

      // Copy group key
      for (int i = 0; i < 32; i++) {
        groupKeyPtr[i] = groupKey[i];
      }

      return _native.cyxchat_group_restore(
        _groupCtx!,
        groupIdPtr,
        namePtr.cast(),
        groupKeyPtr,
        keyVersion,
        creatorIdPtr,
        myRole,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(namePtr);
      calloc.free(groupKeyPtr);
      calloc.free(creatorIdPtr);
    }
  }

  /// Restore a member to a restored group (call after groupRestore)
  /// Returns 0 on success, error code otherwise
  int groupRestoreMember({
    required String groupIdHex,
    required String memberIdHex,
    required int role,
  }) {
    if (_groupCtx == null) return CyxChatError.errNull;

    final groupIdPtr = calloc<Uint8>(8);
    final memberIdPtr = calloc<Uint8>(32);

    try {
      // Parse group ID from hex
      final parseGroupId = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseGroupId != 0) return parseGroupId;

      // Parse member ID from hex
      final cleanMemberHex = memberIdHex.replaceAll('-', '');
      if (cleanMemberHex.length < 32 || !RegExp(r'^[0-9a-fA-F]+$').hasMatch(cleanMemberHex)) {
        return CyxChatError.errInvalid;
      }
      for (int i = 0; i < 16; i++) {
        memberIdPtr[i] = int.parse(cleanMemberHex.substring(i * 2, i * 2 + 2), radix: 16);
      }

      return _native.cyxchat_group_restore_member(
        _groupCtx!,
        groupIdPtr,
        memberIdPtr,
        role,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(memberIdPtr);
    }
  }


  /// Set group description
  int groupSetDescription(String groupIdHex, String description) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final descPtr = description.toNativeUtf8();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_set_description(
        _groupCtx!,
        groupIdPtr,
        descPtr.cast(),
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(descPtr);
    }
  }

  /// Set group name
  int groupSetName(String groupIdHex, String name) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final namePtr = name.toNativeUtf8();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_set_name(
        _groupCtx!,
        groupIdPtr,
        namePtr.cast(),
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(namePtr);
    }
  }

  /// Invite member to group
  int groupInvite(String groupIdHex, Pointer<Uint8> memberId, Pointer<Uint8> memberPubkey) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_invite(
        _groupCtx!,
        groupIdPtr,
        memberId,
        memberPubkey,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Leave group
  int groupLeave(String groupIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_leave(_groupCtx!, groupIdPtr);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Remove member from group (admin only)
  int groupRemoveMember(String groupIdHex, Pointer<Uint8> memberId) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_remove_member(_groupCtx!, groupIdPtr, memberId);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Promote member to admin (owner only)
  int groupAddAdmin(String groupIdHex, Pointer<Uint8> memberId) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_add_admin(_groupCtx!, groupIdPtr, memberId);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Demote admin to member (owner only)
  int groupRemoveAdmin(String groupIdHex, Pointer<Uint8> memberId) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_remove_admin(_groupCtx!, groupIdPtr, memberId);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Send text message to group
  /// Returns message ID hex string or null on failure
  String? groupSendText(String groupIdHex, String text, {String? replyToHex}) {
    if (_groupCtx == null) return null;
    final groupIdPtr = calloc<Uint8>(8);
    final textPtr = text.toNativeUtf8();
    final replyToPtr = calloc<Uint8>(8);
    final msgIdOutPtr = calloc<Uint8>(8);
    try {
      var parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return null;

      if (replyToHex != null) {
        final replyHexPtr = replyToHex.toNativeUtf8();
        parseResult = _native.cyxchat_msg_id_from_hex(
          replyHexPtr.cast(),
          replyToPtr,
        );
        calloc.free(replyHexPtr);
        if (parseResult != 0) return null;
      }

      final result = _native.cyxchat_group_send_text(
        _groupCtx!,
        groupIdPtr,
        textPtr.cast(),
        text.length,
        replyToHex != null ? replyToPtr : nullptr,
        msgIdOutPtr,
      );
      if (result == 0) {
        final hexOut = calloc<Int8>(17);
        _native.cyxchat_msg_id_to_hex(msgIdOutPtr, hexOut);
        final hex = hexOut.cast<Utf8>().toDartString();
        calloc.free(hexOut);
        return hex;
      }
      return null;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(textPtr);
      calloc.free(replyToPtr);
      calloc.free(msgIdOutPtr);
    }
  }

  /// Rotate group key (admin only)
  int groupRotateKey(String groupIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_rotate_key(_groupCtx!, groupIdPtr);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get number of groups
  int groupCount() {
    if (_groupCtx == null) return 0;
    return _native.cyxchat_group_count(_groupCtx!);
  }

  /// Check if we are member of group
  bool groupIsMember(String groupIdHex) {
    if (_groupCtx == null) return false;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return false;
      return _native.cyxchat_group_is_member(_groupCtx!, groupIdPtr) != 0;
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get group key (for persistence)
  /// Returns null if group not found, otherwise (key, version)
  (Uint8List, int)? groupGetKey(String groupIdHex) {
    if (_groupCtx == null) return null;
    final groupIdPtr = calloc<Uint8>(8);
    final keyPtr = calloc<Uint8>(32);
    final versionPtr = calloc<Uint32>();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return null;
      final result = _native.cyxchat_group_get_key(
        _groupCtx!,
        groupIdPtr,
        keyPtr,
        versionPtr,
      );
      if (result != 0) return null;
      final key = Uint8List(32);
      for (int i = 0; i < 32; i++) {
        key[i] = keyPtr[i];
      }
      return (key, versionPtr.value);
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(keyPtr);
      calloc.free(versionPtr);
    }
  }


  /// Check if we are admin of group
  bool groupIsAdmin(String groupIdHex) {
    if (_groupCtx == null) return false;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return false;
      return _native.cyxchat_group_is_admin(_groupCtx!, groupIdPtr) != 0;
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Check if we are owner of group
  bool groupIsOwner(String groupIdHex) {
    if (_groupCtx == null) return false;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return false;
      return _native.cyxchat_group_is_owner(_groupCtx!, groupIdPtr) != 0;
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get our role in group (0=member, 1=admin, 2=owner)
  int groupGetRole(String groupIdHex) {
    if (_groupCtx == null) return 0;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;
      return _native.cyxchat_group_get_role(_groupCtx!, groupIdPtr);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Convert group ID to hex string
  String groupIdToHex(Pointer<Uint8> id) {
    final hexOut = calloc<Int8>(17);
    try {
      _native.cyxchat_group_id_to_hex(id, hexOut);
      return hexOut.cast<Utf8>().toDartString();
    } finally {
      calloc.free(hexOut);
    }
  }

  /// Parse group ID from hex string (also handles UUID format with hyphens)
  int groupIdFromHex(String hex, Pointer<Uint8> idOut) {
    // Strip hyphens if UUID format
    final cleanHex = hex.replaceAll('-', '');
    final hexPtr = cleanHex.toNativeUtf8();
    try {
      return _native.cyxchat_group_id_from_hex(hexPtr.cast(), idOut);
    } finally {
      calloc.free(hexPtr);
    }
  }

  /// Get key distribution progress for a group
  /// Returns map with 'sent', 'acked', 'total' keys, or null if no distribution in progress
  Map<String, int>? groupKeyDistProgress(String groupIdHex) {
    if (_groupCtx == null) return null;
    final groupIdPtr = calloc<Uint8>(8);
    final sentPtr = calloc<Size>(1);
    final ackedPtr = calloc<Size>(1);
    final totalPtr = calloc<Size>(1);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return null;
      final inProgress = _native.cyxchat_group_key_dist_progress(
        _groupCtx!,
        groupIdPtr,
        sentPtr,
        ackedPtr,
        totalPtr,
      );
      if (inProgress != 0) {
        return {
          'sent': sentPtr.value,
          'acked': ackedPtr.value,
          'total': totalPtr.value,
        };
      }
      return null;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(sentPtr);
      calloc.free(ackedPtr);
      calloc.free(totalPtr);
    }
  }

  /// Set auto-rotation on member leave
  void groupSetAutoRotateOnLeave(bool enable) {
    if (_groupCtx == null) return;
    _native.cyxchat_group_set_auto_rotate_on_leave(_groupCtx!, enable ? 1 : 0);
  }

  /// Set auto-rotation on kick notification
  void groupSetAutoRotateOnKick(bool enable) {
    if (_groupCtx == null) return;
    _native.cyxchat_group_set_auto_rotate_on_kick(_groupCtx!, enable ? 1 : 0);
  }

  /// Get auto-rotation settings
  /// Returns map with 'onLeave' and 'onKick' boolean values
  Map<String, bool> groupGetAutoRotateSettings() {
    if (_groupCtx == null) return {'onLeave': true, 'onKick': false};
    final onLeavePtr = calloc<Int32>(1);
    final onKickPtr = calloc<Int32>(1);
    try {
      _native.cyxchat_group_get_auto_rotate_settings(
        _groupCtx!,
        onLeavePtr,
        onKickPtr,
      );
      return {
        'onLeave': onLeavePtr.value != 0,
        'onKick': onKickPtr.value != 0,
      };
    } finally {
      calloc.free(onLeavePtr);
      calloc.free(onKickPtr);
    }
  }

  /// Group callback storage (prevent GC)
  NativeCallable<_GroupMessageCallback>? _onGroupMessage;
  NativeCallable<_GroupMediaCallback>? _onGroupMedia;
  NativeCallable<_GroupInviteCallback>? _onGroupInvite;
  NativeCallable<_MemberJoinCallback>? _onMemberJoin;
  NativeCallable<_MemberLeaveCallback>? _onMemberLeave;
  NativeCallable<_KeyUpdateCallback>? _onKeyUpdate;
  NativeCallable<_KeyDistCompleteCallback>? _onKeyDistComplete;
  NativeCallable<_GroupDeliveryCallback>? _onGroupDelivery;
  NativeCallable<_GroupDeliveryFailedCallback>? _onGroupDeliveryFailed;

  /// Dart callbacks for group events
  void Function(String groupId, String from, String msgId, String text)? onGroupMessage;
  void Function(GroupMediaMetadata media)? onGroupMedia;
  void Function(String groupId, String groupName, String inviter)? onGroupInvite;
  void Function(String groupId, String memberId)? onMemberJoin;
  void Function(String groupId, String memberId, bool wasKicked)? onMemberLeave;
  void Function(String groupId, int newVersion)? onKeyUpdate;
  void Function(String groupId, int newVersion, bool success, int failedCount)? onKeyDistComplete;
  void Function(String groupId, String msgId, int ackedCount, int totalCount)?
      onGroupDelivery;
  void Function(String groupId, String msgId, int failedCount)?
      onGroupDeliveryFailed;

  /// Pending invites storage (by group ID hex)
  final Map<String, Pointer<Void>> _pendingInvites = {};

  /// Set up group callbacks
  void groupSetupCallbacks() {
    if (_groupCtx == null) return;

    // Group message callback
    _onGroupMessage = NativeCallable<_GroupMessageCallback>.isolateLocal(
      _handleGroupMessage,
    );
    _native.cyxchat_group_set_on_message(
      _groupCtx!,
      _onGroupMessage!.nativeFunction,
      nullptr,
    );

    // Group media callback. Native passes stack metadata, so copy it
    // synchronously before returning to C.
    _onGroupMedia = NativeCallable<_GroupMediaCallback>.isolateLocal(
      _handleGroupMedia,
    );
    _native.cyxchat_group_set_on_media(
      _groupCtx!,
      _onGroupMedia!.nativeFunction,
      nullptr,
    );

    // Group invite callback
    _onGroupInvite = NativeCallable<_GroupInviteCallback>.listener(
      _handleGroupInvite,
    );
    _native.cyxchat_group_set_on_invite(
      _groupCtx!,
      _onGroupInvite!.nativeFunction,
      nullptr,
    );

    // Member join callback
    _onMemberJoin = NativeCallable<_MemberJoinCallback>.listener(
      _handleMemberJoin,
    );
    _native.cyxchat_group_set_on_member_join(
      _groupCtx!,
      _onMemberJoin!.nativeFunction,
      nullptr,
    );

    // Member leave callback
    _onMemberLeave = NativeCallable<_MemberLeaveCallback>.listener(
      _handleMemberLeave,
    );
    _native.cyxchat_group_set_on_member_leave(
      _groupCtx!,
      _onMemberLeave!.nativeFunction,
      nullptr,
    );

    // Key update callback
    _onKeyUpdate = NativeCallable<_KeyUpdateCallback>.listener(
      _handleKeyUpdate,
    );
    _native.cyxchat_group_set_on_key_update(
      _groupCtx!,
      _onKeyUpdate!.nativeFunction,
      nullptr,
    );

    // Key distribution complete callback
    _onKeyDistComplete = NativeCallable<_KeyDistCompleteCallback>.listener(
      _handleKeyDistComplete,
    );
    _native.cyxchat_group_set_on_key_dist_complete(
      _groupCtx!,
      _onKeyDistComplete!.nativeFunction,
      nullptr,
    );

    // Group delivery callbacks
    _onGroupDelivery = NativeCallable<_GroupDeliveryCallback>.listener(
      _handleGroupDelivery,
    );
    _native.cyxchat_group_set_on_delivery(
      _groupCtx!,
      _onGroupDelivery!.nativeFunction,
      nullptr,
    );

    _onGroupDeliveryFailed =
        NativeCallable<_GroupDeliveryFailedCallback>.listener(
      _handleGroupDeliveryFailed,
    );
    _native.cyxchat_group_set_on_delivery_failed(
      _groupCtx!,
      _onGroupDeliveryFailed!.nativeFunction,
      nullptr,
    );
  }

  /// Clean up group callbacks
  void groupCleanupCallbacks() {
    _onGroupMessage?.close();
    _onGroupMedia?.close();
    _onGroupInvite?.close();
    _onMemberJoin?.close();
    _onMemberLeave?.close();
    _onKeyUpdate?.close();
    _onKeyDistComplete?.close();
    _onGroupDelivery?.close();
    _onGroupDeliveryFailed?.close();
    _onGroupMessage = null;
    _onGroupMedia = null;
    _onGroupInvite = null;
    _onMemberJoin = null;
    _onMemberLeave = null;
    _onKeyUpdate = null;
    _onKeyDistComplete = null;
    _onGroupDelivery = null;
    _onGroupDeliveryFailed = null;
    _pendingInvites.clear();
  }

  /// Handle incoming group message
  /// Payload is ALL-in-one heap string: "<16-hex-groupid>:<64-hex-senderid>:<16-hex-msgid>:<text>"
  /// All data encoded in payload to avoid stale pointer issues with .listener()
  void _handleGroupMessage(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> from,
    Pointer<Void> msgPayload,
    Pointer<Void> userData,
  ) {
    try { File('D:/Dev/conspiracy/cyxchat/dart_debug.log').writeAsStringSync('\${DateTime.now()}: callback fired\n', mode: FileMode.append); } catch (_) {}
    print("DEBUG FFI: _handleGroupMessage called");
    if (onGroupMessage == null) { print("DEBUG FFI: onGroupMessage callback is NULL!"); return; }

    // Parse ALL-in-one payload (don't read groupId/from pointers - they may be stale)
    // Format: "<16-hex-groupid>:<64-hex-senderid>:<16-hex-msgid>:<text>"
    final payload = msgPayload.cast<Utf8>().toDartString();
    print("DEBUG FFI: payload='\${payload.substring(0, payload.length.clamp(0, 120))}'");

    if (payload.length < 99) {
      print("DEBUG FFI: payload too short: \${payload.length}");
      return;
    }

    final groupIdHex = payload.substring(0, 16);
    // payload[16] == ':'
    final fromHex = payload.substring(17, 81);
    // payload[81] == ':'
    final msgIdHex = payload.substring(82, 98);
    // payload[98] == ':'
    final textStr = payload.length > 99 ? payload.substring(99) : '';

    try { File('D:/Dev/conspiracy/cyxchat/dart_debug.log').writeAsStringSync('\${DateTime.now()}: group=$groupIdHex from=\${fromHex.substring(0,16)} msgId=$msgIdHex text=$textStr\n', mode: FileMode.append); } catch (_) {}
    print("DEBUG FFI: group=$groupIdHex from=\${fromHex.substring(0,16)} msgId=$msgIdHex text=$textStr");
    onGroupMessage!(groupIdHex, fromHex, msgIdHex, textStr);
  }

  /// Handle incoming group media metadata/content
  void _handleGroupMedia(
    Pointer<Void> ctx,
    Pointer<_GroupMediaNative> media,
    Pointer<Uint8> data,
    int dataLen,
    Pointer<Void> userData,
  ) {
    if (onGroupMedia == null || media == nullptr) return;

    final value = media.ref;
    final payload =
        data != nullptr && dataLen > 0 ? data.asTypedList(dataLen) : null;

    onGroupMedia!(GroupMediaMetadata(
      groupId: _arrayToHex(value.groupId, 8),
      fromNodeId: _arrayToHex(value.senderId, 32),
      msgId: _arrayToHex(value.msgId, 8),
      fileId: _arrayToHex(value.fileId, 8),
      mediaType: value.mediaType,
      fileSize: value.fileSize,
      durationMs: value.durationMs,
      width: value.width,
      height: value.height,
      filename: _charArrayToString(value.filename, 128),
      mimeType: _charArrayToString(value.mimeType, 64),
      thumbnailSize: value.thumbnailSize,
      timestampMs: value.timestamp,
      data: payload == null ? null : Uint8List.fromList(payload),
    ));
  }

  /// Handle incoming group invite
  void _handleGroupInvite(
    Pointer<Void> ctx,
    Pointer<Void> invite,
    Pointer<Void> userData,
  ) {
    print("DEBUG: _handleGroupInvite called");
    if (onGroupInvite == null) {
      print("DEBUG: onGroupInvite is NULL");
      return;
    }
    print("DEBUG: onGroupInvite callback is SET, parsing invite...");

    // Parse invite structure
    final inviteBytes = invite.cast<Uint8>();

    // Header: version(1) + type(1) + flags(2) + PADDING(4) + timestamp(8) + msg_id(8) = 24 bytes
    // (64-bit alignment adds 4 bytes padding before timestamp)
    // Then: group_id(8) + group_name(64) + key_version(4) + encrypted_key(72) + inviter(32) + inviter_pubkey(32)

    // Group ID at offset 24 (header is 24 bytes with padding)
    final groupIdHex = _ptrToHex(inviteBytes.elementAt(24), 8);
    print("DEBUG: Parsed groupId: $groupIdHex");

    // Group name at offset 32 (24 + 8)
    final nameBytes = <int>[];
    for (int i = 0; i < 64; i++) {
      final c = inviteBytes[32 + i];
      if (c == 0) break;
      nameBytes.add(c);
    }
    final groupName = String.fromCharCodes(nameBytes);
    print("DEBUG: Parsed groupName: $groupName");

    // Inviter at offset 32 + 64 + 4 + 72 = 172
    final inviterHex = _ptrToHex(inviteBytes.elementAt(172), 32);
    print("DEBUG: Parsed inviter: $inviterHex");

    // Store the invite pointer for accept/decline (we need to copy it since the original may be freed)
    // For now, we'll store the pointer - caller must accept/decline before it's freed
    _pendingInvites[groupIdHex] = invite;
    print("DEBUG: Stored invite in _pendingInvites, calling onGroupInvite callback...");

    try {
      onGroupInvite!(groupIdHex, groupName, inviterHex);
      print("DEBUG: onGroupInvite callback completed successfully");
    } catch (e, st) {
      print("DEBUG: onGroupInvite callback threw exception: $e");
      print("DEBUG: Stack trace: $st");
    }
  }

  /// Accept a pending group invite
  int groupAcceptInvite(String groupIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final invite = _pendingInvites.remove(groupIdHex);
    if (invite == null) return CyxChatError.errNotFound;
    final result = _native.cyxchat_group_accept_invite(_groupCtx!, invite);
    // Free the heap-allocated invite
    _native.cyxchat_group_free_invite(invite);
    return result;
  }

  /// Decline a pending group invite
  int groupDeclineInvite(String groupIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final invite = _pendingInvites.remove(groupIdHex);
    if (invite == null) return CyxChatError.errNotFound;
    final result = _native.cyxchat_group_decline_invite(_groupCtx!, invite);
    // Free the heap-allocated invite
    _native.cyxchat_group_free_invite(invite);
    return result;
  }

  /// Handle member join
  void _handleMemberJoin(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> member,
    Pointer<Void> userData,
  ) {
    if (onMemberJoin == null) return;
    final groupIdHex = _ptrToHex(groupId, 8);
    final memberHex = _ptrToHex(member, 32);
    onMemberJoin!(groupIdHex, memberHex);
  }

  /// Handle member leave
  void _handleMemberLeave(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> member,
    int wasKicked,
    Pointer<Void> userData,
  ) {
    if (onMemberLeave == null) return;
    final groupIdHex = _ptrToHex(groupId, 8);
    final memberHex = _ptrToHex(member, 32);
    onMemberLeave!(groupIdHex, memberHex, wasKicked != 0);
  }

  /// Handle key update
  void _handleKeyUpdate(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    int newVersion,
    Pointer<Void> userData,
  ) {
    if (onKeyUpdate == null) return;
    final groupIdHex = _ptrToHex(groupId, 8);
    onKeyUpdate!(groupIdHex, newVersion);
  }

  /// Handle key distribution complete
  void _handleKeyDistComplete(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    int newVersion,
    int success,
    int failedCount,
    Pointer<Void> userData,
  ) {
    if (onKeyDistComplete == null) return;
    final groupIdHex = _ptrToHex(groupId, 8);
    onKeyDistComplete!(groupIdHex, newVersion, success != 0, failedCount);
  }

  /// Handle group message delivery success
  void _handleGroupDelivery(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> msgId,
    int ackedCount,
    int totalCount,
    Pointer<Void> userData,
  ) {
    if (onGroupDelivery == null) return;
    onGroupDelivery!(
      _ptrToHex(groupId, 8),
      _ptrToHex(msgId, 8),
      ackedCount,
      totalCount,
    );
  }

  /// Handle group message delivery failure
  void _handleGroupDeliveryFailed(
    Pointer<Void> ctx,
    Pointer<Uint8> groupId,
    Pointer<Uint8> msgId,
    Pointer<Uint8> failedMembers,
    int failedCount,
    Pointer<Void> userData,
  ) {
    if (onGroupDeliveryFailed == null) return;
    onGroupDeliveryFailed!(
      _ptrToHex(groupId, 8),
      _ptrToHex(msgId, 8),
      failedCount,
    );
  }

  // ============================================================
  // Group Admin Permissions & Restrictions (Phase 1)
  // ============================================================

  /// Set admin permissions for a group member
  int groupSetAdminPermissions(String groupIdHex, Pointer<Uint8> adminId, int permissions) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_set_admin_permissions(
        _groupCtx!,
        groupIdPtr,
        adminId,
        permissions,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get admin permissions for a group member
  int groupGetAdminPermissions(String groupIdHex, Pointer<Uint8> adminId) {
    if (_groupCtx == null) return 0;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;
      return _native.cyxchat_group_get_admin_permissions(
        _groupCtx!,
        groupIdPtr,
        adminId,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Check if admin has a specific permission
  bool groupHasPermission(String groupIdHex, String adminIdHex, int permission) {
    if (_groupCtx == null) return false;
    final groupIdPtr = calloc<Uint8>(8);
    final adminIdPtr = calloc<Uint8>(32);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return false;

      final adminBytes = _hexToBytes(adminIdHex);
      for (int i = 0; i < 32 && i < adminBytes.length; i++) {
        adminIdPtr[i] = adminBytes[i];
      }

      return _native.cyxchat_group_has_permission(
        _groupCtx!,
        groupIdPtr,
        adminIdPtr,
        permission,
      ) != 0;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(adminIdPtr);
    }
  }

  /// Apply restrictions to a member
  int groupRestrictMember(String groupIdHex, Pointer<Uint8> memberId, int restrictions, int untilMs) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_restrict_member(
        _groupCtx!,
        groupIdPtr,
        memberId,
        restrictions,
        untilMs,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Remove all restrictions from a member
  int groupUnrestrictMember(String groupIdHex, Pointer<Uint8> memberId) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_unrestrict_member(
        _groupCtx!,
        groupIdPtr,
        memberId,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get restrictions for a member
  /// Returns (restrictions, untilMs) tuple
  (int, int) groupGetMemberRestrictions(String groupIdHex, Pointer<Uint8> memberId) {
    if (_groupCtx == null) return (0, 0);
    final groupIdPtr = calloc<Uint8>(8);
    final untilPtr = calloc<Uint64>(1);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return (0, 0);
      final restrictions = _native.cyxchat_group_get_member_restrictions(
        _groupCtx!,
        groupIdPtr,
        memberId,
        untilPtr,
      );
      return (restrictions, untilPtr.value);
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(untilPtr);
    }
  }

  /// Check if a member is currently muted
  bool groupIsMemberMuted(String groupIdHex, Pointer<Uint8> memberId) {
    if (_groupCtx == null) return false;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return false;
      return _native.cyxchat_group_is_member_muted(
        _groupCtx!,
        groupIdPtr,
        memberId,
      ) != 0;
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Set slow mode for the group (seconds between messages)
  int groupSetSlowMode(String groupIdHex, int seconds) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_set_slow_mode(
        _groupCtx!,
        groupIdPtr,
        seconds,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get slow mode setting for the group
  int groupGetSlowMode(String groupIdHex) {
    if (_groupCtx == null) return 0;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;
      return _native.cyxchat_group_get_slow_mode(
        _groupCtx!,
        groupIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Set who can add members to the group
  int groupSetWhoCanAdd(String groupIdHex, int setting) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_set_who_can_add(
        _groupCtx!,
        groupIdPtr,
        setting,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Set who can edit group info
  int groupSetWhoCanEdit(String groupIdHex, int setting) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_set_who_can_edit(
        _groupCtx!,
        groupIdPtr,
        setting,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Set who can send messages (0=all, 1=admins, 2=selected)
  int groupSetWhoCanSend(String groupIdHex, int setting) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_set_who_can_send(
        _groupCtx!,
        groupIdPtr,
        setting,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get who can send messages setting
  int groupGetWhoCanSend(String groupIdHex) {
    if (_groupCtx == null) return 0;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;
      return _native.cyxchat_group_get_who_can_send(
        _groupCtx!,
        groupIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Add member to selected senders list
  int groupAddSelectedSender(String groupIdHex, String memberIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final memberIdPtr = calloc<Uint8>(32);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      final memberBytes = _hexToBytes(memberIdHex);
      for (int i = 0; i < 32 && i < memberBytes.length; i++) {
        memberIdPtr[i] = memberBytes[i];
      }
      return _native.cyxchat_group_add_selected_sender(
        _groupCtx!,
        groupIdPtr,
        memberIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(memberIdPtr);
    }
  }

  /// Remove member from selected senders list
  int groupRemoveSelectedSender(String groupIdHex, String memberIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final memberIdPtr = calloc<Uint8>(32);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      final memberBytes = _hexToBytes(memberIdHex);
      for (int i = 0; i < 32 && i < memberBytes.length; i++) {
        memberIdPtr[i] = memberBytes[i];
      }
      return _native.cyxchat_group_remove_selected_sender(
        _groupCtx!,
        groupIdPtr,
        memberIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(memberIdPtr);
    }
  }

  /// Check if member can send messages
  bool groupCanSend(String groupIdHex, String memberIdHex) {
    if (_groupCtx == null) return false;
    final groupIdPtr = calloc<Uint8>(8);
    final memberIdPtr = calloc<Uint8>(32);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return false;
      final memberBytes = _hexToBytes(memberIdHex);
      for (int i = 0; i < 32 && i < memberBytes.length; i++) {
        memberIdPtr[i] = memberBytes[i];
      }
      return _native.cyxchat_group_can_send(
        _groupCtx!,
        groupIdPtr,
        memberIdPtr,
      ) != 0;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(memberIdPtr);
    }
  }

  /// Get group type (basic or supergroup)
  int groupGetType(String groupIdHex) {
    if (_groupCtx == null) return 0;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;
      return _native.cyxchat_group_get_type(
        _groupCtx!,
        groupIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Upgrade a basic group to supergroup
  int groupUpgradeToSupergroup(String groupIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_upgrade_to_supergroup(
        _groupCtx!,
        groupIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  // ============================================================
  // Phase 2: Message Actions (Edit, Delete, Pin, Forward)
  // ============================================================

  /// Edit a group message
  int groupEditMessage(String groupIdHex, String msgIdHex, String newText) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final msgIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;

      // Parse message ID from hex
      final msgIdBytes = _hexToBytes(msgIdHex);
      if (msgIdBytes.length != 8) return CyxChatError.errInvalid;
      for (int i = 0; i < 8; i++) {
        msgIdPtr[i] = msgIdBytes[i];
      }

      final textBytes = utf8.encode(newText);
      final textPtr = calloc<Uint8>(textBytes.length);
      try {
        for (int i = 0; i < textBytes.length; i++) {
          textPtr[i] = textBytes[i];
        }
        return _native.cyxchat_group_edit_message(
          _groupCtx!,
          groupIdPtr,
          msgIdPtr,
          textPtr.cast(),
          textBytes.length,
        );
      } finally {
        calloc.free(textPtr);
      }
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Delete a group message
  int groupDeleteMessage(String groupIdHex, String msgIdHex, bool deleteForAll) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final msgIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;

      final msgIdBytes = _hexToBytes(msgIdHex);
      if (msgIdBytes.length != 8) return CyxChatError.errInvalid;
      for (int i = 0; i < 8; i++) {
        msgIdPtr[i] = msgIdBytes[i];
      }

      return _native.cyxchat_group_delete_message(
        _groupCtx!,
        groupIdPtr,
        msgIdPtr,
        deleteForAll ? 1 : 0,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Pin a message in group
  int groupPinMessage(String groupIdHex, String msgIdHex, {bool notify = true}) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final msgIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;

      final msgIdBytes = _hexToBytes(msgIdHex);
      if (msgIdBytes.length != 8) return CyxChatError.errInvalid;
      for (int i = 0; i < 8; i++) {
        msgIdPtr[i] = msgIdBytes[i];
      }

      return _native.cyxchat_group_pin_message(
        _groupCtx!,
        groupIdPtr,
        msgIdPtr,
        notify ? 1 : 0,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Unpin a message from group
  int groupUnpinMessage(String groupIdHex, String msgIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final msgIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;

      final msgIdBytes = _hexToBytes(msgIdHex);
      if (msgIdBytes.length != 8) return CyxChatError.errInvalid;
      for (int i = 0; i < 8; i++) {
        msgIdPtr[i] = msgIdBytes[i];
      }

      return _native.cyxchat_group_unpin_message(
        _groupCtx!,
        groupIdPtr,
        msgIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Unpin all messages in group
  int groupUnpinAll(String groupIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_group_unpin_all(_groupCtx!, groupIdPtr);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get count of pinned messages in group
  int groupGetPinnedCount(String groupIdHex) {
    if (_groupCtx == null) return 0;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;
      return _native.cyxchat_group_get_pinned_count(_groupCtx!, groupIdPtr);
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Get list of pinned message IDs in group
  List<String> groupGetPinnedMessages(String groupIdHex, {int maxCount = 50}) {
    if (_groupCtx == null) return [];
    final groupIdPtr = calloc<Uint8>(8);
    final msgIdsPtr = calloc<Uint8>(8 * maxCount);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return [];

      final count = _native.cyxchat_group_get_pinned_messages(
        _groupCtx!,
        groupIdPtr,
        msgIdsPtr,
        maxCount,
      );

      final result = <String>[];
      for (int i = 0; i < count; i++) {
        final msgIdBytes = <int>[];
        for (int j = 0; j < 8; j++) {
          msgIdBytes.add(msgIdsPtr[i * 8 + j]);
        }
        result.add(_bytesToHex(msgIdBytes));
      }
      return result;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(msgIdsPtr);
    }
  }

  /// Check if a message is pinned
  bool groupIsMessagePinned(String groupIdHex, String msgIdHex) {
    if (_groupCtx == null) return false;
    final groupIdPtr = calloc<Uint8>(8);
    final msgIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return false;

      final msgIdBytes = _hexToBytes(msgIdHex);
      if (msgIdBytes.length != 8) return false;
      for (int i = 0; i < 8; i++) {
        msgIdPtr[i] = msgIdBytes[i];
      }

      return _native.cyxchat_group_is_message_pinned(
        _groupCtx!,
        groupIdPtr,
        msgIdPtr,
      ) != 0;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(msgIdPtr);
    }
  }

  /// Forward a message to another group
  /// Returns [error, newMsgIdHex] tuple
  (int, String?) groupForwardMessage(
    String fromGroupIdHex,
    String toGroupIdHex,
    String msgIdHex,
  ) {
    if (_groupCtx == null) return (CyxChatError.errNull, null);
    final fromGroupIdPtr = calloc<Uint8>(8);
    final toGroupIdPtr = calloc<Uint8>(8);
    final msgIdPtr = calloc<Uint8>(8);
    final newMsgIdPtr = calloc<Uint8>(8);
    try {
      var parseResult = groupIdFromHex(fromGroupIdHex, fromGroupIdPtr);
      if (parseResult != 0) return (parseResult, null);

      parseResult = groupIdFromHex(toGroupIdHex, toGroupIdPtr);
      if (parseResult != 0) return (parseResult, null);

      final msgIdBytes = _hexToBytes(msgIdHex);
      if (msgIdBytes.length != 8) return (CyxChatError.errInvalid, null);
      for (int i = 0; i < 8; i++) {
        msgIdPtr[i] = msgIdBytes[i];
      }

      final result = _native.cyxchat_group_forward_message(
        _groupCtx!,
        fromGroupIdPtr,
        toGroupIdPtr,
        msgIdPtr,
        newMsgIdPtr,
      );

      if (result == 0) {
        final newMsgIdBytes = <int>[];
        for (int i = 0; i < 8; i++) {
          newMsgIdBytes.add(newMsgIdPtr[i]);
        }
        return (0, _bytesToHex(newMsgIdBytes));
      }
      return (result, null);
    } finally {
      calloc.free(fromGroupIdPtr);
      calloc.free(toGroupIdPtr);
      calloc.free(msgIdPtr);
      calloc.free(newMsgIdPtr);
    }
  }

  /// Helper to convert hex string to bytes (also handles UUID format with hyphens)
  List<int> _hexToBytes(String hex) {
    // Strip hyphens if UUID format
    final cleanHex = hex.replaceAll('-', '');
    final result = <int>[];
    for (int i = 0; i < cleanHex.length; i += 2) {
      result.add(int.parse(cleanHex.substring(i, i + 2), radix: 16));
    }
    return result;
  }

  /// Helper to convert bytes to hex string
  String _bytesToHex(List<int> bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Helper to convert pointer bytes to hex string
  String _ptrToHex(Pointer<Uint8> ptr, int len) {
    final bytes = <int>[];
    for (int i = 0; i < len; i++) {
      bytes.add(ptr[i]);
    }
    return _bytesToHex(bytes);
  }

  String _arrayToHex(Array<Uint8> array, int len) {
    final bytes = <int>[];
    for (int i = 0; i < len; i++) {
      bytes.add(array[i]);
    }
    return _bytesToHex(bytes);
  }

  String _charArrayToString(Array<Int8> array, int maxLen) {
    final bytes = <int>[];
    for (int i = 0; i < maxLen; i++) {
      final value = array[i];
      if (value == 0) break;
      bytes.add(value & 0xff);
    }
    return utf8.decode(bytes, allowMalformed: true);
  }

  // ============================================================
  // Invite Links Module (Phase 3)
  // ============================================================

  /// Create an invite link for a group
  /// Returns (error, linkIdHex) tuple
  (int, String?) groupCreateInviteLink(
    String groupIdHex, {
    String? name,
    int? expiresAtMs,
    int? maxUses,
  }) {
    if (_groupCtx == null) return (CyxChatError.errNull, null);
    final groupIdPtr = calloc<Uint8>(8);
    final namePtr = name != null ? name.toNativeUtf8() : nullptr;
    final linkOut = calloc<_InviteLinkNative>();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return (parseResult, null);

      final result = _native.cyxchat_group_create_invite_link(
        _groupCtx!,
        groupIdPtr,
        namePtr.cast(),
        expiresAtMs ?? 0,
        maxUses ?? 0,
        linkOut.cast(),
      );

      if (result == 0) {
        final linkIdBytes = <int>[];
        for (int i = 0; i < 16; i++) {
          linkIdBytes.add(linkOut.ref.linkId[i]);
        }
        return (0, _bytesToHex(linkIdBytes));
      }
      return (result, null);
    } finally {
      calloc.free(groupIdPtr);
      if (namePtr != nullptr) calloc.free(namePtr);
      calloc.free(linkOut);
    }
  }

  /// Revoke an invite link
  int groupRevokeInviteLink(String groupIdHex, String linkIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final linkIdPtr = calloc<Uint8>(16);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;

      final linkIdBytes = _hexToBytes(linkIdHex);
      if (linkIdBytes.length != 16) return CyxChatError.errInvalid;
      for (int i = 0; i < 16; i++) {
        linkIdPtr[i] = linkIdBytes[i];
      }

      return _native.cyxchat_group_revoke_invite_link(
        _groupCtx!,
        groupIdPtr,
        linkIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(linkIdPtr);
    }
  }

  /// Join a group via invite link
  int groupJoinViaLink(String groupIdHex, String linkIdHex) {
    if (_groupCtx == null) return CyxChatError.errNull;
    final groupIdPtr = calloc<Uint8>(8);
    final linkIdPtr = calloc<Uint8>(16);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return parseResult;

      final linkIdBytes = _hexToBytes(linkIdHex);
      if (linkIdBytes.length != 16) return CyxChatError.errInvalid;
      for (int i = 0; i < 16; i++) {
        linkIdPtr[i] = linkIdBytes[i];
      }

      return _native.cyxchat_group_join_via_link(
        _groupCtx!,
        groupIdPtr,
        linkIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(linkIdPtr);
    }
  }

  /// Get all invite links for a group
  /// Returns list of (linkIdHex, creatorIdHex, createdAt, expiresAt, maxUses, useCount, isRevoked, name)
  List<Map<String, dynamic>> groupGetInviteLinks(String groupIdHex, {int maxLinks = 20}) {
    if (_groupCtx == null) return [];
    final groupIdPtr = calloc<Uint8>(8);
    final linksOut = calloc<_InviteLinkNative>(maxLinks);
    final countOut = calloc<Size>();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return [];

      final result = _native.cyxchat_group_get_invite_links(
        _groupCtx!,
        groupIdPtr,
        linksOut.cast(),
        maxLinks,
        countOut,
      );

      if (result != 0) return [];

      final links = <Map<String, dynamic>>[];
      final count = countOut.value;
      for (int i = 0; i < count; i++) {
        final link = linksOut[i];

        // Extract link ID
        final linkIdBytes = <int>[];
        for (int j = 0; j < 16; j++) {
          linkIdBytes.add(link.linkId[j]);
        }

        // Extract creator ID
        final creatorIdBytes = <int>[];
        for (int j = 0; j < 32; j++) {
          creatorIdBytes.add(link.creatorId[j]);
        }

        // Extract name
        final nameBytes = <int>[];
        for (int j = 0; j < 64 && link.name[j] != 0; j++) {
          nameBytes.add(link.name[j]);
        }
        final name = nameBytes.isEmpty ? null : String.fromCharCodes(nameBytes);

        links.add({
          'id': _bytesToHex(linkIdBytes),
          'groupId': groupIdHex,
          'createdBy': _bytesToHex(creatorIdBytes),
          'createdAt': link.createdAt,
          'expiresAt': link.expiresAt,
          'maxUses': link.maxUses,
          'useCount': link.useCount,
          'isRevoked': link.isRevoked != 0,
          'name': name,
        });
      }
      return links;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(linksOut);
      calloc.free(countOut);
    }
  }

  /// Get a specific invite link
  /// Returns link data map or null if not found
  Map<String, dynamic>? groupGetInviteLink(String groupIdHex, String linkIdHex) {
    if (_groupCtx == null) return null;
    final groupIdPtr = calloc<Uint8>(8);
    final linkIdPtr = calloc<Uint8>(16);
    final linkOut = calloc<_InviteLinkNative>();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return null;

      final linkIdBytes = _hexToBytes(linkIdHex);
      if (linkIdBytes.length != 16) return null;
      for (int i = 0; i < 16; i++) {
        linkIdPtr[i] = linkIdBytes[i];
      }

      final result = _native.cyxchat_group_get_invite_link(
        _groupCtx!,
        groupIdPtr,
        linkIdPtr,
        linkOut.cast(),
      );

      if (result != 0) return null;

      // Extract creator ID
      final creatorIdBytes = <int>[];
      for (int j = 0; j < 32; j++) {
        creatorIdBytes.add(linkOut.ref.creatorId[j]);
      }

      // Extract name
      final nameBytes = <int>[];
      for (int j = 0; j < 64 && linkOut.ref.name[j] != 0; j++) {
        nameBytes.add(linkOut.ref.name[j]);
      }
      final name = nameBytes.isEmpty ? null : String.fromCharCodes(nameBytes);

      return {
        'id': linkIdHex,
        'groupId': groupIdHex,
        'createdBy': _bytesToHex(creatorIdBytes),
        'createdAt': linkOut.ref.createdAt,
        'expiresAt': linkOut.ref.expiresAt,
        'maxUses': linkOut.ref.maxUses,
        'useCount': linkOut.ref.useCount,
        'isRevoked': linkOut.ref.isRevoked != 0,
        'name': name,
      };
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(linkIdPtr);
      calloc.free(linkOut);
    }
  }

  /// Generate URL for an invite link (static helper)
  String groupInviteLinkToUrl(String groupIdHex, String linkIdHex) {
    return 'cyxchat://join/$groupIdHex/$linkIdHex';
  }

  /// Parse an invite URL into group ID and link ID
  /// Returns (groupIdHex, linkIdHex) or null if invalid
  (String, String)? groupParseInviteUrl(String url) {
    // Supported formats:
    // cyxchat://join/<group_id>/<link_id>
    // https://cyxchat.app/join/<group_id>/<link_id>
    final patterns = [
      RegExp(r'^cyxchat://join/([a-fA-F0-9]+)/([a-fA-F0-9]+)$'),
      RegExp(r'^https?://cyxchat\.app/join/([a-fA-F0-9]+)/([a-fA-F0-9]+)$'),
    ];

    for (final pattern in patterns) {
      final match = pattern.firstMatch(url);
      if (match != null) {
        final groupId = match.group(1)!;
        final linkId = match.group(2)!;
        // Validate lengths
        if (groupId.length == 16 && linkId.length == 32) {
          return (groupId, linkId);
        }
      }
    }
    return null;
  }

  // ============================================================
  // Admin Action Log Module (Phase 4)
  // ============================================================

  /// Log an admin action
  /// Returns (error, actionIdHex) tuple
  (int, String?) groupLogAdminAction(
    String groupIdHex,
    int actionType, {
    String? targetIdHex,
    String? targetMsgIdHex,
    String? oldValue,
    String? newValue,
  }) {
    if (_groupCtx == null) return (CyxChatError.errNull, null);
    final groupIdPtr = calloc<Uint8>(8);
    final targetIdPtr = targetIdHex != null ? calloc<Uint8>(32) : nullptr;
    final msgIdPtr = targetMsgIdHex != null ? calloc<Uint8>(8) : nullptr;
    final oldValuePtr = oldValue != null ? oldValue.toNativeUtf8() : nullptr;
    final newValuePtr = newValue != null ? newValue.toNativeUtf8() : nullptr;
    final actionOut = calloc<_AdminActionNative>();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return (parseResult, null);

      if (targetIdHex != null) {
        final targetBytes = _hexToBytes(targetIdHex);
        for (int i = 0; i < 32 && i < targetBytes.length; i++) {
          targetIdPtr[i] = targetBytes[i];
        }
      }

      if (targetMsgIdHex != null) {
        final msgBytes = _hexToBytes(targetMsgIdHex);
        for (int i = 0; i < 8 && i < msgBytes.length; i++) {
          msgIdPtr[i] = msgBytes[i];
        }
      }

      final result = _native.cyxchat_group_log_admin_action(
        _groupCtx!,
        groupIdPtr,
        actionType,
        targetIdPtr,
        msgIdPtr,
        oldValuePtr.cast(),
        newValuePtr.cast(),
        actionOut.cast(),
      );

      if (result == 0) {
        final actionIdBytes = <int>[];
        for (int i = 0; i < 16; i++) {
          actionIdBytes.add(actionOut.ref.actionId[i]);
        }
        return (0, _bytesToHex(actionIdBytes));
      }
      return (result, null);
    } finally {
      calloc.free(groupIdPtr);
      if (targetIdPtr != nullptr) calloc.free(targetIdPtr);
      if (msgIdPtr != nullptr) calloc.free(msgIdPtr);
      if (oldValuePtr != nullptr) calloc.free(oldValuePtr);
      if (newValuePtr != nullptr) calloc.free(newValuePtr);
      calloc.free(actionOut);
    }
  }

  /// Get admin actions for a group
  /// Returns list of action data maps
  List<Map<String, dynamic>> groupGetAdminActions(
    String groupIdHex, {
    int maxActions = 50,
    int offset = 0,
  }) {
    if (_groupCtx == null) return [];
    final groupIdPtr = calloc<Uint8>(8);
    final actionsOut = calloc<_AdminActionNative>(maxActions);
    final countOut = calloc<Size>();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return [];

      final result = _native.cyxchat_group_get_admin_actions(
        _groupCtx!,
        groupIdPtr,
        actionsOut.cast(),
        maxActions,
        offset,
        countOut,
      );

      if (result != 0) return [];

      final count = countOut.value;
      final actions = <Map<String, dynamic>>[];
      for (int i = 0; i < count; i++) {
        final action = actionsOut[i];
        actions.add(_adminActionToMap(action));
      }
      return actions;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(actionsOut);
      calloc.free(countOut);
    }
  }

  /// Get admin actions by a specific admin
  List<Map<String, dynamic>> groupGetAdminActionsByAdmin(
    String groupIdHex,
    String adminIdHex, {
    int maxActions = 50,
  }) {
    if (_groupCtx == null) return [];
    final groupIdPtr = calloc<Uint8>(8);
    final adminIdPtr = calloc<Uint8>(32);
    final actionsOut = calloc<_AdminActionNative>(maxActions);
    final countOut = calloc<Size>();
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return [];

      final adminBytes = _hexToBytes(adminIdHex);
      for (int i = 0; i < 32 && i < adminBytes.length; i++) {
        adminIdPtr[i] = adminBytes[i];
      }

      final result = _native.cyxchat_group_get_admin_actions_by_admin(
        _groupCtx!,
        groupIdPtr,
        adminIdPtr,
        actionsOut.cast(),
        maxActions,
        countOut,
      );

      if (result != 0) return [];

      final count = countOut.value;
      final actions = <Map<String, dynamic>>[];
      for (int i = 0; i < count; i++) {
        final action = actionsOut[i];
        actions.add(_adminActionToMap(action));
      }
      return actions;
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(adminIdPtr);
      calloc.free(actionsOut);
      calloc.free(countOut);
    }
  }

  /// Get count of admin actions for a group
  int groupGetAdminActionCount(String groupIdHex) {
    if (_groupCtx == null) return 0;
    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;

      return _native.cyxchat_group_get_admin_action_count(
        _groupCtx!,
        groupIdPtr,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  /// Helper to convert native admin action to map
  Map<String, dynamic> _adminActionToMap(_AdminActionNative action) {
    // Extract action ID
    final actionIdBytes = <int>[];
    for (int i = 0; i < 16; i++) {
      actionIdBytes.add(action.actionId[i]);
    }

    // Extract group ID
    final groupIdBytes = <int>[];
    for (int i = 0; i < 8; i++) {
      groupIdBytes.add(action.groupId[i]);
    }

    // Extract admin ID
    final adminIdBytes = <int>[];
    for (int i = 0; i < 32; i++) {
      adminIdBytes.add(action.adminId[i]);
    }

    // Extract target ID
    final targetIdBytes = <int>[];
    bool hasTarget = false;
    for (int i = 0; i < 32; i++) {
      targetIdBytes.add(action.targetId[i]);
      if (action.targetId[i] != 0) hasTarget = true;
    }

    // Extract target message ID
    final targetMsgBytes = <int>[];
    bool hasTargetMsg = false;
    for (int i = 0; i < 8; i++) {
      targetMsgBytes.add(action.targetMsgId[i]);
      if (action.targetMsgId[i] != 0) hasTargetMsg = true;
    }

    // Extract old value
    final oldValueBytes = <int>[];
    for (int i = 0; i < 256 && action.oldValue[i] != 0; i++) {
      oldValueBytes.add(action.oldValue[i]);
    }
    final oldValue = oldValueBytes.isEmpty ? null : String.fromCharCodes(oldValueBytes);

    // Extract new value
    final newValueBytes = <int>[];
    for (int i = 0; i < 256 && action.newValue[i] != 0; i++) {
      newValueBytes.add(action.newValue[i]);
    }
    final newValue = newValueBytes.isEmpty ? null : String.fromCharCodes(newValueBytes);

    return {
      'id': _bytesToHex(actionIdBytes),
      'group_id': _bytesToHex(groupIdBytes),
      'admin_id': _bytesToHex(adminIdBytes),
      'action_type': action.actionType,
      'target_id': hasTarget ? _bytesToHex(targetIdBytes) : null,
      'target_message_id': hasTargetMsg ? _bytesToHex(targetMsgBytes) : null,
      'old_value': oldValue,
      'new_value': newValue,
      'timestamp': action.timestamp,
    };
  }

  // ============================================================
  // Group Media Module (Phase 5)
  // ============================================================

  /// Send a file to a group
  /// Returns (error code, message ID hex, file ID hex) or null on error
  ({int error, String? msgId, String? fileId}) groupSendFile(
    String groupIdHex,
    String filename,
    String mimeType,
    List<int> fileData,
    List<int>? thumbnailData,
  ) {
    if (_groupCtx == null) {
      return (error: CyxChatError.errNull, msgId: null, fileId: null);
    }

    final groupIdPtr = calloc<Uint8>(8);
    final filenamePtr = filename.toNativeUtf8();
    final mimeTypePtr = mimeType.toNativeUtf8();
    final dataPtr = calloc<Uint8>(fileData.length);
    final thumbnailPtr = thumbnailData != null
        ? calloc<Uint8>(thumbnailData.length)
        : nullptr;
    final msgIdOut = calloc<Uint8>(8);
    final fileIdOut = calloc<Uint8>(8);

    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) {
        return (error: CyxChatError.errInvalid, msgId: null, fileId: null);
      }

      // Copy file data
      for (int i = 0; i < fileData.length; i++) {
        dataPtr[i] = fileData[i];
      }

      // Copy thumbnail data if present
      if (thumbnailData != null && thumbnailPtr != nullptr) {
        for (int i = 0; i < thumbnailData.length; i++) {
          thumbnailPtr[i] = thumbnailData[i];
        }
      }

      final result = _native.cyxchat_group_send_file(
        _groupCtx!,
        groupIdPtr,
        filenamePtr.cast(),
        mimeTypePtr.cast(),
        dataPtr,
        fileData.length,
        thumbnailPtr,
        thumbnailData?.length ?? 0,
        fileIdOut,
        msgIdOut,
      );

      if (result != 0) {
        return (error: result, msgId: null, fileId: null);
      }

      // Extract IDs
      final msgIdBytes = <int>[];
      final fileIdBytes = <int>[];
      for (int i = 0; i < 8; i++) {
        msgIdBytes.add(msgIdOut[i]);
        fileIdBytes.add(fileIdOut[i]);
      }

      return (
        error: 0,
        msgId: _bytesToHex(msgIdBytes),
        fileId: _bytesToHex(fileIdBytes),
      );
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(filenamePtr);
      calloc.free(mimeTypePtr);
      calloc.free(dataPtr);
      if (thumbnailPtr != nullptr) calloc.free(thumbnailPtr);
      calloc.free(msgIdOut);
      calloc.free(fileIdOut);
    }
  }

  /// Send a voice message to a group
  /// Returns (error code, message ID hex) or null on error
  ({int error, String? msgId}) groupSendVoice(
    String groupIdHex,
    List<int> audioData,
    int durationMs,
  ) {
    if (_groupCtx == null) {
      return (error: CyxChatError.errNull, msgId: null);
    }

    final groupIdPtr = calloc<Uint8>(8);
    final audioPtr = calloc<Uint8>(audioData.length);
    final msgIdOut = calloc<Uint8>(8);

    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) {
        return (error: CyxChatError.errInvalid, msgId: null);
      }

      // Copy audio data
      for (int i = 0; i < audioData.length; i++) {
        audioPtr[i] = audioData[i];
      }

      final result = _native.cyxchat_group_send_voice(
        _groupCtx!,
        groupIdPtr,
        audioPtr,
        audioData.length,
        durationMs,
        msgIdOut,
      );

      if (result != 0) {
        return (error: result, msgId: null);
      }

      // Extract message ID
      final msgIdBytes = <int>[];
      for (int i = 0; i < 8; i++) {
        msgIdBytes.add(msgIdOut[i]);
      }

      return (error: 0, msgId: _bytesToHex(msgIdBytes));
    } finally {
      calloc.free(groupIdPtr);
      calloc.free(audioPtr);
      calloc.free(msgIdOut);
    }
  }

  /// Send an image to a group
  /// Returns (error code, message ID hex) or null on error
  ({int error, String? msgId}) groupSendImage(
    String groupIdHex,
    String? filename,
    List<int> imageData,
    int width,
    int height,
  ) {
    if (_groupCtx == null) {
      return (error: CyxChatError.errNull, msgId: null);
    }

    final groupIdPtr = calloc<Uint8>(8);
    final filenamePtr = filename?.toNativeUtf8() ?? nullptr;
    final imagePtr = calloc<Uint8>(imageData.length);
    final msgIdOut = calloc<Uint8>(8);

    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) {
        return (error: CyxChatError.errInvalid, msgId: null);
      }

      // Copy image data
      for (int i = 0; i < imageData.length; i++) {
        imagePtr[i] = imageData[i];
      }

      final result = _native.cyxchat_group_send_image(
        _groupCtx!,
        groupIdPtr,
        filenamePtr.cast(),
        imagePtr,
        imageData.length,
        width,
        height,
        msgIdOut,
      );

      if (result != 0) {
        return (error: result, msgId: null);
      }

      // Extract message ID
      final msgIdBytes = <int>[];
      for (int i = 0; i < 8; i++) {
        msgIdBytes.add(msgIdOut[i]);
      }

      return (error: 0, msgId: _bytesToHex(msgIdBytes));
    } finally {
      calloc.free(groupIdPtr);
      if (filenamePtr != nullptr) calloc.free(filenamePtr);
      calloc.free(imagePtr);
      calloc.free(msgIdOut);
    }
  }

  /// Get count of media items in a group
  /// mediaType: -1 for all, or specific cyxchat_media_type_t value
  int groupGetMediaCount(String groupIdHex, {int mediaType = -1}) {
    if (_groupCtx == null) return 0;

    final groupIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = groupIdFromHex(groupIdHex, groupIdPtr);
      if (parseResult != 0) return 0;

      return _native.cyxchat_group_get_media_count(
        _groupCtx!,
        groupIdPtr,
        mediaType,
      );
    } finally {
      calloc.free(groupIdPtr);
    }
  }

  // ============================================================
  // File Transfer Module
  // ============================================================

  /// File context pointer (opaque)
  Pointer<Void>? _fileCtx;

  /// File callback storage (prevent GC)
  NativeCallable<_FileRequestCallback>? _onFileRequest;
  NativeCallable<_FileCompleteCallback>? _onFileComplete;
  NativeCallable<_FileProgressCallback>? _onFileProgress;
  NativeCallable<_FileErrorCallback>? _onFileError;

  /// Dart callbacks for file events
  void Function(String fromPeerId, String fileId, String filename, String mimeType, int size)? onFileRequest;
  void Function(String fileId, List<int> data)? onFileComplete;
  void Function(String fileId, int chunksDone, int chunksTotal)? onFileProgress;
  void Function(String fileId, int error)? onFileError;

  /// Create file transfer context
  int fileCtxCreate() {
    if (_chatCtx == null) return CyxChatError.errNull;
    final ctxPtr = calloc<Pointer<Void>>();
    try {
      final result = _native.cyxchat_file_ctx_create(ctxPtr, _chatCtx!);
      if (result == 0) {
        _fileCtx = ctxPtr.value;
        // Register file context with chat layer for message routing
        _native.cyxchat_set_file_ctx(_chatCtx!, _fileCtx!);
      }
      return result;
    } finally {
      calloc.free(ctxPtr);
    }
  }

  /// Destroy file transfer context
  void fileCtxDestroy() {
    // Clean up callbacks
    _onFileRequest?.close();
    _onFileComplete?.close();
    _onFileProgress?.close();
    _onFileError?.close();
    _onFileRequest = null;
    _onFileComplete = null;
    _onFileProgress = null;
    _onFileError = null;

    if (_fileCtx != null) {
      _native.cyxchat_file_ctx_destroy(_fileCtx!);
      _fileCtx = null;
    }
  }

  /// Set up file transfer callbacks
  void fileSetupCallbacks() {
    if (_fileCtx == null) return;

    // Create native callback for file request
    _onFileRequest = NativeCallable<_FileRequestCallback>.listener(
      _handleFileRequest,
    );
    _native.cyxchat_file_set_on_request(
      _fileCtx!,
      _onFileRequest!.nativeFunction,
      nullptr,
    );

    // Create native callback for file complete
    _onFileComplete = NativeCallable<_FileCompleteCallback>.listener(
      _handleFileComplete,
    );
    _native.cyxchat_file_set_on_complete(
      _fileCtx!,
      _onFileComplete!.nativeFunction,
      nullptr,
    );

    // Create native callback for file progress
    _onFileProgress = NativeCallable<_FileProgressCallback>.listener(
      _handleFileProgress,
    );
    _native.cyxchat_file_set_on_progress(
      _fileCtx!,
      _onFileProgress!.nativeFunction,
      nullptr,
    );

    // Create native callback for file error
    _onFileError = NativeCallable<_FileErrorCallback>.listener(
      _handleFileError,
    );
    _native.cyxchat_file_set_on_error(
      _fileCtx!,
      _onFileError!.nativeFunction,
      nullptr,
    );
  }

  /// Handle incoming file request from C callback
  void _handleFileRequest(
    Pointer<Void> ctx,
    Pointer<Uint8> from,
    Pointer<_FileMetaNative> meta,
    Pointer<Void> userData,
  ) {
    if (onFileRequest == null) return;

    // Convert from node ID to hex string
    final fromHex = _ptrToHex(from, 32);

    // Extract file ID (8 bytes)
    final fileIdBytes = <int>[];
    for (int i = 0; i < 8; i++) {
      fileIdBytes.add(meta.ref.fileId[i]);
    }
    final fileIdHex = fileIdBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

    // Extract filename (null-terminated string from array)
    final filenameChars = <int>[];
    for (int i = 0; i < 128; i++) {
      final c = meta.ref.filename[i];
      if (c == 0) break;
      filenameChars.add(c);
    }
    final filename = String.fromCharCodes(filenameChars);

    // Extract mime type (null-terminated string from array)
    final mimeChars = <int>[];
    for (int i = 0; i < 64; i++) {
      final c = meta.ref.mimeType[i];
      if (c == 0) break;
      mimeChars.add(c);
    }
    final mimeType = String.fromCharCodes(mimeChars);

    final size = meta.ref.size;

    onFileRequest!(fromHex, fileIdHex, filename, mimeType, size);
  }

  /// Handle file transfer complete from C callback
  void _handleFileComplete(
    Pointer<Void> ctx,
    Pointer<Uint8> fileId,
    Pointer<Uint8> data,
    int dataLen,
    Pointer<Void> userData,
  ) {
    if (onFileComplete == null) return;

    // Copy file ID bytes immediately (pointer may be stale by async callback time)
    final fileIdHex = _ptrToHex(fileId, 8);

    // Copy data to Dart list
    final dataList = <int>[];
    for (int i = 0; i < dataLen; i++) {
      dataList.add(data[i]);
    }

    onFileComplete!(fileIdHex, dataList);
  }

  /// Handle file progress from C callback
  void _handleFileProgress(
    Pointer<Void> ctx,
    Pointer<Uint8> fileId,
    int chunksDone,
    int chunksTotal,
    Pointer<Void> userData,
  ) {
    if (onFileProgress == null) return;

    // Copy file ID bytes immediately (pointer may be stale by async callback time)
    final fileIdHex = _ptrToHex(fileId, 8);
    onFileProgress!(fileIdHex, chunksDone, chunksTotal);
  }

  /// Handle file error from C callback
  void _handleFileError(
    Pointer<Void> ctx,
    Pointer<Uint8> fileId,
    int error,
    Pointer<Void> userData,
  ) {
    if (onFileError == null) return;

    // Copy file ID bytes immediately (pointer may be stale by async callback time)
    final fileIdHex = _ptrToHex(fileId, 8);
    onFileError!(fileIdHex, error);
  }

  /// Poll file transfer events
  int filePoll(int nowMs) {
    if (_fileCtx == null) return 0;
    return _native.cyxchat_file_poll(_fileCtx!, nowMs);
  }

  /// Send file to peer
  /// Returns file ID hex string or null on failure
  String? fileSend({
    required Pointer<Uint8> to,
    required String filename,
    required String mimeType,
    required List<int> data,
  }) {
    if (_fileCtx == null) return null;

    final filenamePtr = filename.toNativeUtf8();
    final mimePtr = mimeType.toNativeUtf8();
    final dataPtr = calloc<Uint8>(data.length);
    final fileIdOutPtr = calloc<Uint8>(8);

    try {
      // Copy data to native memory
      for (int i = 0; i < data.length; i++) {
        dataPtr[i] = data[i];
      }

      final result = _native.cyxchat_file_send(
        _fileCtx!,
        to,
        filenamePtr.cast(),
        mimePtr.cast(),
        dataPtr,
        data.length,
        fileIdOutPtr,
      );

      if (result == 0) {
        return fileIdToHex(fileIdOutPtr);
      }
      return null;
    } finally {
      calloc.free(filenamePtr);
      calloc.free(mimePtr);
      calloc.free(dataPtr);
      calloc.free(fileIdOutPtr);
    }
  }

  /// Accept incoming file transfer
  int fileAccept(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_accept(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Reject incoming file transfer
  int fileReject(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_reject(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Cancel ongoing file transfer
  int fileCancel(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_cancel(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Pause file transfer
  int filePause(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_pause(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Resume paused file transfer
  int fileResume(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_resume(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Get number of active file transfers
  int fileActiveCount() {
    if (_fileCtx == null) return 0;
    return _native.cyxchat_file_active_count(_fileCtx!);
  }

  /// Convert file ID to hex string
  String fileIdToHex(Pointer<Uint8> id) {
    final hexOut = calloc<Int8>(17); // 16 hex chars + null
    try {
      _native.cyxchat_file_id_to_hex(id, hexOut);
      return hexOut.cast<Utf8>().toDartString();
    } finally {
      calloc.free(hexOut);
    }
  }

  /// Parse file ID from hex string
  int fileIdFromHex(String hex, Pointer<Uint8> idOut) {
    final hexPtr = hex.toNativeUtf8();
    try {
      return _native.cyxchat_file_id_from_hex(hexPtr.cast(), idOut);
    } finally {
      calloc.free(hexPtr);
    }
  }

  /// Detect MIME type from filename
  String fileDetectMime(String filename) {
    final filenamePtr = filename.toNativeUtf8();
    try {
      final ptr = _native.cyxchat_file_detect_mime(filenamePtr.cast());
      if (ptr == nullptr) return 'application/octet-stream';
      return ptr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(filenamePtr);
    }
  }

  /// Format file size as human-readable string
  String fileFormatSize(int sizeBytes) {
    final outPtr = calloc<Int8>(32);
    try {
      _native.cyxchat_file_format_size(sizeBytes, outPtr, 32);
      return outPtr.cast<Utf8>().toDartString();
    } finally {
      calloc.free(outPtr);
    }
  }

  // ============================================================
  // DHT-Based File Transfer
  // ============================================================

  /// Store file offer in DHT for offline recipient
  int fileStoreOffer(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_store_offer(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Store small file chunks in DHT (for files <= 1680 bytes)
  int fileStoreDhtChunks(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_store_dht_chunks(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Retrieve file chunks from DHT
  int fileRetrieveDhtChunks(String fileIdHex) {
    if (_fileCtx == null) return CyxChatError.errNull;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return parseResult;
      return _native.cyxchat_file_retrieve_dht_chunks(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Check DHT for pending file offers addressed to us
  int fileCheckDhtOffers() {
    if (_fileCtx == null) return -1;
    return _native.cyxchat_file_check_dht_offers(_fileCtx!);
  }

  /// Get the transfer mode for a file transfer
  /// Returns: 1=DIRECT, 2=RELAY, 3=DHT_MICRO, 4=DHT_SIGNAL, or -1 on error
  int fileGetTransferMode(String fileIdHex) {
    if (_fileCtx == null) return -1;
    final fileIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = fileIdFromHex(fileIdHex, fileIdPtr);
      if (parseResult != 0) return -1;
      return _native.cyxchat_file_get_transfer_mode(_fileCtx!, fileIdPtr);
    } finally {
      calloc.free(fileIdPtr);
    }
  }

  /// Set direct mode for file transfers
  /// direct: 1 = use direct P2P (faster, less anonymous), 0 = use onion routing (default)
  int fileSetDirectMode(int direct) {
    if (_fileCtx == null) return -1;
    return _native.cyxchat_file_set_direct_mode(_fileCtx!, direct);
  }

  /// Get current direct mode setting
  /// Returns: 1 if direct mode enabled, 0 if using onion routing, -1 on error
  int fileGetDirectMode() {
    if (_fileCtx == null) return -1;
    return _native.cyxchat_file_get_direct_mode(_fileCtx!);
  }

  /// Set router for direct P2P file transfers
  void fileSetRouter(Pointer<Void> router) {
    if (_fileCtx == null) return;
    _native.cyxchat_file_set_router(_fileCtx!, router);
  }

  /// Set transport for direct P2P file transfers (bypasses router peer check)
  void fileSetTransport(Pointer<Void> transport) {
    if (_fileCtx == null) return;
    _native.cyxchat_file_set_transport(_fileCtx!, transport);
  }

  /// Get router from connection context for direct file transfers
  Pointer<Void>? connGetRouter() {
    if (_connCtx == null) return null;
    return _native.cyxchat_conn_get_router(_connCtx!);
  }

  /// Get transport from connection context for direct file transfers
  Pointer<Void>? connGetTransport() {
    if (_connCtx == null) return null;
    return _native.cyxchat_conn_get_transport(_connCtx!);
  }

  /// Set file context on connection for direct file message routing
  void connSetFileCtx() {
    if (_connCtx == null || _fileCtx == null) return;
    _native.cyxchat_conn_set_file_ctx(_connCtx!, _fileCtx!);
  }

  /// Set connection context on file context for peer address exchange in direct mode
  void fileSetConnCtx() {
    if (_fileCtx == null || _connCtx == null) return;
    _native.cyxchat_file_set_conn_ctx(_fileCtx!, _connCtx!);
  }
}

/// Native function signatures
class CyxChatNative {
  final DynamicLibrary _lib;

  CyxChatNative(this._lib);

  // Library functions
  late final cyxchat_init = _lib
      .lookupFunction<Int32 Function(), int Function()>('cyxchat_init');

  late final cyxchat_shutdown = _lib
      .lookupFunction<Void Function(), void Function()>('cyxchat_shutdown');

  late final cyxchat_is_initialized = _lib
      .lookupFunction<Int32 Function(), int Function()>('cyxchat_is_initialized');

  late final cyxchat_version = _lib
      .lookupFunction<Pointer<Int8> Function(), Pointer<Int8> Function()>(
          'cyxchat_version');

  late final cyxchat_error_string = _lib.lookupFunction<
      Pointer<Int8> Function(Int32),
      Pointer<Int8> Function(int)>('cyxchat_error_string');

  // Utility functions
  late final cyxchat_generate_msg_id = _lib.lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)>('cyxchat_generate_msg_id');

  late final cyxchat_timestamp_ms = _lib
      .lookupFunction<Uint64 Function(), int Function()>('cyxchat_timestamp_ms');

  late final cyxchat_msg_id_cmp = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Uint8>, Pointer<Uint8>)>('cyxchat_msg_id_cmp');

  late final cyxchat_msg_id_is_zero = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>),
      int Function(Pointer<Uint8>)>('cyxchat_msg_id_is_zero');

  // Connection management functions
  late final cyxchat_conn_create = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Pointer<Void>>, Pointer<Int8>, Pointer<Uint8>)>(
      'cyxchat_conn_create');

  late final cyxchat_conn_destroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_conn_destroy');

  late final cyxchat_conn_poll = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('cyxchat_conn_poll');

  late final cyxchat_conn_connect = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Pointer<Void>)>(
      'cyxchat_conn_connect');

  late final cyxchat_conn_disconnect = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_conn_disconnect');

  late final cyxchat_conn_get_state = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_conn_get_state');

  late final cyxchat_conn_is_relayed = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_conn_is_relayed');

  late final cyxchat_conn_send = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Size),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_conn_send');

  late final cyxchat_conn_get_public_addr = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>, Size),
      int Function(Pointer<Void>, Pointer<Int8>, int)>(
      'cyxchat_conn_get_public_addr');

  late final cyxchat_conn_is_bootstrap_connected = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_is_bootstrap_connected');

  late final cyxchat_conn_is_upnp_available = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_is_upnp_available');

  late final cyxchat_conn_is_upnp_mapping_active = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_is_upnp_mapping_active');

  late final cyxchat_conn_get_upnp_external_port = _lib.lookupFunction<
      Uint16 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_get_upnp_external_port');

  late final cyxchat_conn_get_upnp_lease_remaining_sec = _lib.lookupFunction<
      Uint32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_get_upnp_lease_remaining_sec');

  late final cyxchat_conn_has_peer_key = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_conn_has_peer_key');
late final cyxchat_conn_get_peer_pubkey = _lib.lookupFunction<      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>('cyxchat_conn_get_peer_pubkey');

  late final cyxchat_conn_get_full_node_id = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>('cyxchat_conn_get_full_node_id');

  late final cyxchat_conn_state_name = _lib.lookupFunction<
      Pointer<Int8> Function(Int32),
      Pointer<Int8> Function(int)>('cyxchat_conn_state_name');

  late final cyxchat_conn_nat_type_name = _lib.lookupFunction<
      Pointer<Int8> Function(Int32),
      Pointer<Int8> Function(int)>('cyxchat_conn_nat_type_name');

  late final cyxchat_conn_add_relay = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>),
      int Function(Pointer<Void>, Pointer<Int8>)>('cyxchat_conn_add_relay');

  late final cyxchat_conn_relay_count = _lib.lookupFunction<
      Size Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_relay_count');

  late final cyxchat_conn_force_relay = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_conn_force_relay');

  late final cyxchat_conn_add_peer_addr = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>)>('cyxchat_conn_add_peer_addr');

  // DNS functions
  late final cyxchat_dns_create = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Pointer<Void>>, Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_dns_create');

  late final cyxchat_dns_destroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_dns_destroy');

  late final cyxchat_dns_poll = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('cyxchat_dns_poll');

  late final cyxchat_dns_register = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Int8>, Pointer<Void>, Pointer<Void>)>(
      'cyxchat_dns_register');

  late final cyxchat_dns_refresh = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_dns_refresh');

  late final cyxchat_dns_unregister = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_dns_unregister');

  late final cyxchat_dns_get_registered_name = _lib.lookupFunction<
      Pointer<Int8> Function(Pointer<Void>),
      Pointer<Int8> Function(Pointer<Void>)>('cyxchat_dns_get_registered_name');

  late final cyxchat_dns_lookup = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Int8>, Pointer<Void>, Pointer<Void>)>(
      'cyxchat_dns_lookup');

  late final cyxchat_dns_resolve = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Int8>, Pointer<Uint8>)>(
      'cyxchat_dns_resolve');

  late final cyxchat_dns_is_cached = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>),
      int Function(Pointer<Void>, Pointer<Int8>)>('cyxchat_dns_is_cached');

  late final cyxchat_dns_invalidate = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Int8>),
      void Function(Pointer<Void>, Pointer<Int8>)>('cyxchat_dns_invalidate');

  late final cyxchat_dns_set_petname = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>)>(
      'cyxchat_dns_set_petname');

  late final cyxchat_dns_get_petname = _lib.lookupFunction<
      Pointer<Int8> Function(Pointer<Void>, Pointer<Uint8>),
      Pointer<Int8> Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_dns_get_petname');

  late final cyxchat_dns_crypto_name = _lib.lookupFunction<
      Void Function(Pointer<Uint8>, Pointer<Int8>),
      void Function(Pointer<Uint8>, Pointer<Int8>)>('cyxchat_dns_crypto_name');

  late final cyxchat_dns_is_crypto_name = _lib.lookupFunction<
      Int32 Function(Pointer<Int8>),
      int Function(Pointer<Int8>)>('cyxchat_dns_is_crypto_name');

  late final cyxchat_dns_validate_name = _lib.lookupFunction<
      Int32 Function(Pointer<Int8>),
      int Function(Pointer<Int8>)>('cyxchat_dns_validate_name');

  late final cyxchat_dns_set_transport = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>, Pointer<Void>)>(
      'cyxchat_dns_set_transport');

  late final cyxchat_conn_get_transport = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('cyxchat_conn_get_transport');

  late final cyxchat_conn_get_peer_table = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('cyxchat_conn_get_peer_table');

  late final cyxchat_conn_get_onion = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('cyxchat_conn_get_onion');

  late final cyxchat_conn_get_dht = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('cyxchat_conn_get_dht');

  late final cyxchat_conn_get_router = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('cyxchat_conn_get_router');

  late final cyxchat_conn_set_file_ctx = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('cyxchat_conn_set_file_ctx');

  late final cyxchat_conn_set_on_progress = _lib.lookupFunction<
      Void Function(
          Pointer<Void>,
          Pointer<NativeFunction<_ConnProgressCallback>>,
          Pointer<Void>),
      void Function(
          Pointer<Void>,
          Pointer<NativeFunction<_ConnProgressCallback>>,
          Pointer<Void>)>('cyxchat_conn_set_on_progress');

  late final cyxchat_conn_set_presence_callback = _lib.lookupFunction<
      Void Function(
          Pointer<Void>,
          Pointer<NativeFunction<_PresenceCallback>>,
          Pointer<Void>),
      void Function(
          Pointer<Void>,
          Pointer<NativeFunction<_PresenceCallback>>,
          Pointer<Void>)>('cyxchat_conn_set_presence_callback');

  late final cyxchat_conn_query_presence = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_conn_query_presence');

  // Server registry functions
  late final cyxchat_conn_get_server_registry = _lib.lookupFunction<
      Pointer<Void> Function(Pointer<Void>),
      Pointer<Void> Function(Pointer<Void>)>('cyxchat_conn_get_server_registry');

  late final cyxchat_conn_add_server = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Utf8>, Pointer<Uint8>)>('cyxchat_conn_add_server');

  late final cyxchat_server_registry_count = _lib.lookupFunction<
      Size Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_server_registry_count');

  late final cyxchat_server_registry_healthy_count = _lib.lookupFunction<
      Size Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_server_registry_healthy_count');

  late final cyxchat_server_registry_get_all = _lib.lookupFunction<
      Size Function(Pointer<Void>, Pointer<Void>, Size),
      int Function(Pointer<Void>, Pointer<Void>, int)>('cyxchat_server_registry_get_all');

  late final cyxchat_server_state_name = _lib.lookupFunction<
      Pointer<Utf8> Function(Int32),
      Pointer<Utf8> Function(int)>('cyxchat_server_state_name');

  late final cyxchat_conn_server_count = _lib.lookupFunction<
      Size Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_server_count');

  late final cyxchat_conn_healthy_server_count = _lib.lookupFunction<
      Size Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_healthy_server_count');

  late final cyxchat_conn_get_servers_info = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Utf8>, Size),
      int Function(Pointer<Void>, Pointer<Utf8>, int)>('cyxchat_conn_get_servers_info');

  // DHT functions
  late final cyxchat_conn_dht_bootstrap = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Size),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_conn_dht_bootstrap');

  late final cyxchat_conn_dht_add_node = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_conn_dht_add_node');

  late final cyxchat_conn_dht_find_node = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Pointer<Void>)>(
      'cyxchat_conn_dht_find_node');

  late final cyxchat_conn_dht_get_closest = _lib.lookupFunction<
      Size Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Size),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_conn_dht_get_closest');

  late final cyxchat_conn_dht_is_ready = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_conn_dht_is_ready');

  // Chat core functions
  late final cyxchat_create = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Pointer<Void>>, Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_create');

  late final cyxchat_destroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_destroy');

  late final cyxchat_poll = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('cyxchat_poll');

  late final cyxchat_recv_next = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>, Pointer<Uint8>, Pointer<Size>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>, Pointer<Uint8>, Pointer<Size>)>('cyxchat_recv_next');

  late final cyxchat_send_text = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, Size,
          Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, int,
          Pointer<Uint8>, Pointer<Uint8>)>('cyxchat_send_text');

  late final cyxchat_send_raw = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Size),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_send_raw');

  late final cyxchat_set_next_msg_id = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Uint8>),
      void Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_set_next_msg_id');

  late final cyxchat_send_ack = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_send_ack');

  late final cyxchat_send_typing = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>('cyxchat_send_typing');

  late final cyxchat_send_reaction = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Int8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Int8>, int)>('cyxchat_send_reaction');

  late final cyxchat_send_delete = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_send_delete');

  late final cyxchat_send_edit = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Int8>, Size),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Int8>, int)>('cyxchat_send_edit');

  // Group functions
  late final cyxchat_group_ctx_create = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, Pointer<Void>),
      int Function(Pointer<Pointer<Void>>, Pointer<Void>)>(
      'cyxchat_group_ctx_create');

  late final cyxchat_group_ctx_destroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_group_ctx_destroy');

  late final cyxchat_set_group_ctx = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('cyxchat_set_group_ctx');

  late final cyxchat_group_poll = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('cyxchat_group_poll');

  late final cyxchat_group_create = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Int8>, Pointer<Uint8>)>(
      'cyxchat_group_create');

  late final cyxchat_group_restore = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, Pointer<Uint8>, Uint32, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, Pointer<Uint8>, int, Pointer<Uint8>, int)>(
      'cyxchat_group_restore');

  late final cyxchat_group_restore_member = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>('cyxchat_group_restore_member');


  late final cyxchat_group_set_description = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>)>(
      'cyxchat_group_set_description');

  late final cyxchat_group_set_name = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>)>(
      'cyxchat_group_set_name');

  late final cyxchat_group_invite = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_invite');

  late final cyxchat_group_leave = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_group_leave');

  late final cyxchat_group_remove_member = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_remove_member');

  late final cyxchat_group_add_admin = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_add_admin');

  late final cyxchat_group_remove_admin = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_remove_admin');

  late final cyxchat_group_send_text = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, Size,
          Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, int,
          Pointer<Uint8>, Pointer<Uint8>)>('cyxchat_group_send_text');

  late final cyxchat_group_rotate_key = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_group_rotate_key');

  late final cyxchat_group_count = _lib.lookupFunction<
      Size Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_group_count');

  late final cyxchat_group_get_key = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint32>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint32>)>(
      'cyxchat_group_get_key');


  late final cyxchat_group_is_member = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_group_is_member');

  late final cyxchat_group_is_admin = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_group_is_admin');

  late final cyxchat_group_is_owner = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_group_is_owner');

  late final cyxchat_group_get_role = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_group_get_role');

  late final cyxchat_group_id_to_hex = _lib.lookupFunction<
      Void Function(Pointer<Uint8>, Pointer<Int8>),
      void Function(Pointer<Uint8>, Pointer<Int8>)>('cyxchat_group_id_to_hex');

  late final cyxchat_group_id_from_hex = _lib.lookupFunction<
      Int32 Function(Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Int8>, Pointer<Uint8>)>('cyxchat_group_id_from_hex');

  late final cyxchat_group_accept_invite = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('cyxchat_group_accept_invite');

  late final cyxchat_group_decline_invite = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Void>)>('cyxchat_group_decline_invite');

  late final cyxchat_group_free_invite = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_group_free_invite');

  late final cyxchat_group_key_dist_progress = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Size>, Pointer<Size>, Pointer<Size>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Size>, Pointer<Size>, Pointer<Size>)>(
      'cyxchat_group_key_dist_progress');

  late final cyxchat_group_set_auto_rotate_on_leave = _lib.lookupFunction<
      Void Function(Pointer<Void>, Int32),
      void Function(Pointer<Void>, int)>('cyxchat_group_set_auto_rotate_on_leave');

  late final cyxchat_group_set_auto_rotate_on_kick = _lib.lookupFunction<
      Void Function(Pointer<Void>, Int32),
      void Function(Pointer<Void>, int)>('cyxchat_group_set_auto_rotate_on_kick');

  late final cyxchat_group_get_auto_rotate_settings = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>),
      void Function(Pointer<Void>, Pointer<Int32>, Pointer<Int32>)>(
      'cyxchat_group_get_auto_rotate_settings');

  // Group callback setters
  late final cyxchat_group_set_on_message = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_GroupMessageCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_GroupMessageCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_message');

  late final cyxchat_group_set_on_media = _lib.lookupFunction<
      Void Function(Pointer<Void>,
          Pointer<NativeFunction<_GroupMediaCallback>>, Pointer<Void>),
      void Function(
          Pointer<Void>,
          Pointer<NativeFunction<_GroupMediaCallback>>,
          Pointer<Void>)>('cyxchat_group_set_on_media');

  late final cyxchat_group_set_on_invite = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_GroupInviteCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_GroupInviteCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_invite');

  late final cyxchat_group_set_on_member_join = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_MemberJoinCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_MemberJoinCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_member_join');

  late final cyxchat_group_set_on_member_leave = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_MemberLeaveCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_MemberLeaveCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_member_leave');

  late final cyxchat_group_set_on_key_update = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_KeyUpdateCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_KeyUpdateCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_key_update');

  late final cyxchat_group_set_on_key_dist_complete = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_KeyDistCompleteCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_KeyDistCompleteCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_key_dist_complete');

  late final cyxchat_group_set_on_delivery = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_GroupDeliveryCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_GroupDeliveryCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_delivery');

  late final cyxchat_group_set_on_delivery_failed = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_GroupDeliveryFailedCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_GroupDeliveryFailedCallback>>, Pointer<Void>)>(
      'cyxchat_group_set_on_delivery_failed');

  // Group admin permissions and restrictions (Phase 1)
  late final cyxchat_group_set_admin_permissions = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Uint8),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_group_set_admin_permissions');

  late final cyxchat_group_get_admin_permissions = _lib.lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_get_admin_permissions');

  late final cyxchat_group_has_permission = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Uint8),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_group_has_permission');

  late final cyxchat_group_restrict_member = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Uint8, Uint64),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int, int)>(
      'cyxchat_group_restrict_member');

  late final cyxchat_group_unrestrict_member = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_unrestrict_member');

  late final cyxchat_group_get_member_restrictions = _lib.lookupFunction<
      Uint8 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint64>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Uint64>)>(
      'cyxchat_group_get_member_restrictions');

  late final cyxchat_group_is_member_muted = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_is_member_muted');

  late final cyxchat_group_set_slow_mode = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Uint16),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_group_set_slow_mode');

  late final cyxchat_group_get_slow_mode = _lib.lookupFunction<
      Uint16 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_group_get_slow_mode');

  late final cyxchat_group_set_who_can_add = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_group_set_who_can_add');

  late final cyxchat_group_set_who_can_edit = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_group_set_who_can_edit');

  late final cyxchat_group_set_who_can_send = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_group_set_who_can_send');

  late final cyxchat_group_get_who_can_send = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_group_get_who_can_send');

  late final cyxchat_group_add_selected_sender = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_add_selected_sender');

  late final cyxchat_group_remove_selected_sender = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_remove_selected_sender');

  late final cyxchat_group_can_send = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_can_send');

  late final cyxchat_group_get_type = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_group_get_type');

  late final cyxchat_group_upgrade_to_supergroup = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_group_upgrade_to_supergroup');

  // Phase 2: Message action functions
  late final cyxchat_group_edit_message = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Int8>, Size),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Int8>, int)>('cyxchat_group_edit_message');

  late final cyxchat_group_delete_message = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_group_delete_message');

  late final cyxchat_group_pin_message = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_group_pin_message');

  late final cyxchat_group_unpin_message = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_unpin_message');

  late final cyxchat_group_unpin_all = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_group_unpin_all');

  late final cyxchat_group_get_pinned_count = _lib.lookupFunction<
      Size Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_group_get_pinned_count');

  late final cyxchat_group_get_pinned_messages = _lib.lookupFunction<
      Size Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Size),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int)>(
      'cyxchat_group_get_pinned_messages');

  late final cyxchat_group_is_message_pinned = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_is_message_pinned');

  late final cyxchat_group_forward_message = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>, Pointer<Uint8>)>('cyxchat_group_forward_message');

  // Invite link functions
  late final cyxchat_group_create_invite_link = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, Uint64, Uint32, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, int, int, Pointer<Void>)>(
      'cyxchat_group_create_invite_link');

  late final cyxchat_group_revoke_invite_link = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_revoke_invite_link');

  late final cyxchat_group_join_via_link = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_group_join_via_link');

  late final cyxchat_group_get_invite_links = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Size, Pointer<Size>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, int, Pointer<Size>)>(
      'cyxchat_group_get_invite_links');

  late final cyxchat_group_get_invite_link = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Void>)>(
      'cyxchat_group_get_invite_link');

  // Admin action log functions
  late final cyxchat_group_log_admin_action = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Uint8>,
          Pointer<Uint8>, Pointer<Int8>, Pointer<Int8>, Pointer<Void>),
      int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Uint8>,
          Pointer<Uint8>, Pointer<Int8>, Pointer<Int8>, Pointer<Void>)>(
      'cyxchat_group_log_admin_action');

  late final cyxchat_group_get_admin_actions = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, Size, Size, Pointer<Size>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Void>, int, int, Pointer<Size>)>(
      'cyxchat_group_get_admin_actions');

  late final cyxchat_group_get_admin_actions_by_admin = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Void>, Size, Pointer<Size>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Pointer<Void>, int, Pointer<Size>)>(
      'cyxchat_group_get_admin_actions_by_admin');

  late final cyxchat_group_get_admin_action_count = _lib.lookupFunction<
      Size Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_group_get_admin_action_count');

  // Group Media functions
  late final cyxchat_group_send_file = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>,
          Pointer<Int8>, Pointer<Uint8>, Size, Pointer<Uint8>, Size,
          Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, Pointer<Int8>,
          Pointer<Uint8>, int, Pointer<Uint8>, int, Pointer<Uint8>,
          Pointer<Uint8>)>('cyxchat_group_send_file');

  late final cyxchat_group_send_voice = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, Size,
          Uint32, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>, int,
          int, Pointer<Uint8>)>('cyxchat_group_send_voice');

  late final cyxchat_group_send_image = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>,
          Pointer<Uint8>, Size, Uint16, Uint16, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>,
          Pointer<Uint8>, int, int, int, Pointer<Uint8>)>(
      'cyxchat_group_send_image');

  late final cyxchat_group_get_media = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32, Pointer<Void>,
          Size, Size, Pointer<Size>),
      int Function(Pointer<Void>, Pointer<Uint8>, int, Pointer<Void>,
          int, int, Pointer<Size>)>('cyxchat_group_get_media');

  late final cyxchat_group_get_media_count = _lib.lookupFunction<
      Size Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_group_get_media_count');

  late final cyxchat_msg_id_to_hex = _lib.lookupFunction<
      Void Function(Pointer<Uint8>, Pointer<Int8>),
      void Function(Pointer<Uint8>, Pointer<Int8>)>('cyxchat_msg_id_to_hex');

  late final cyxchat_msg_id_from_hex = _lib.lookupFunction<
      Int32 Function(Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Int8>, Pointer<Uint8>)>('cyxchat_msg_id_from_hex');

  // File transfer functions
  late final cyxchat_file_ctx_create = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, Pointer<Void>),
      int Function(Pointer<Pointer<Void>>, Pointer<Void>)>(
      'cyxchat_file_ctx_create');

  late final cyxchat_file_ctx_destroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_file_ctx_destroy');

  late final cyxchat_set_file_ctx = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('cyxchat_set_file_ctx');

  late final cyxchat_file_poll = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('cyxchat_file_poll');

  late final cyxchat_file_send = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>,
          Pointer<Int8>, Pointer<Uint8>, Size, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>,
          Pointer<Int8>, Pointer<Uint8>, int, Pointer<Uint8>)>(
      'cyxchat_file_send');

  late final cyxchat_file_accept = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_accept');

  late final cyxchat_file_reject = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_reject');

  late final cyxchat_file_cancel = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_cancel');

  late final cyxchat_file_pause = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_pause');

  late final cyxchat_file_resume = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_resume');

  late final cyxchat_file_active_count = _lib.lookupFunction<
      Size Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_file_active_count');

  late final cyxchat_file_id_to_hex = _lib.lookupFunction<
      Void Function(Pointer<Uint8>, Pointer<Int8>),
      void Function(Pointer<Uint8>, Pointer<Int8>)>('cyxchat_file_id_to_hex');

  late final cyxchat_file_id_from_hex = _lib.lookupFunction<
      Int32 Function(Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Int8>, Pointer<Uint8>)>('cyxchat_file_id_from_hex');

  late final cyxchat_file_detect_mime = _lib.lookupFunction<
      Pointer<Int8> Function(Pointer<Int8>),
      Pointer<Int8> Function(Pointer<Int8>)>('cyxchat_file_detect_mime');

  late final cyxchat_file_format_size = _lib.lookupFunction<
      Void Function(Uint32, Pointer<Int8>, Size),
      void Function(int, Pointer<Int8>, int)>('cyxchat_file_format_size');

  // File callback setters
  late final cyxchat_file_set_on_request = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_FileRequestCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_FileRequestCallback>>, Pointer<Void>)>(
      'cyxchat_file_set_on_request');

  late final cyxchat_file_set_on_complete = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_FileCompleteCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_FileCompleteCallback>>, Pointer<Void>)>(
      'cyxchat_file_set_on_complete');

  late final cyxchat_file_set_on_progress = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_FileProgressCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_FileProgressCallback>>, Pointer<Void>)>(
      'cyxchat_file_set_on_progress');

  late final cyxchat_file_set_on_error = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<NativeFunction<_FileErrorCallback>>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<NativeFunction<_FileErrorCallback>>, Pointer<Void>)>(
      'cyxchat_file_set_on_error');

  // DHT-based file transfer functions
  late final cyxchat_file_store_offer = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_store_offer');

  late final cyxchat_file_store_dht_chunks = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_store_dht_chunks');

  late final cyxchat_file_retrieve_dht_chunks = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_retrieve_dht_chunks');

  late final cyxchat_file_check_dht_offers = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_file_check_dht_offers');

  late final cyxchat_file_get_transfer_mode = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_file_get_transfer_mode');

  late final cyxchat_file_set_direct_mode = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)>('cyxchat_file_set_direct_mode');

  late final cyxchat_file_get_direct_mode = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_file_get_direct_mode');

  late final cyxchat_file_set_router = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('cyxchat_file_set_router');

  late final cyxchat_file_set_transport = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('cyxchat_file_set_transport');

  late final cyxchat_file_set_conn_ctx = _lib.lookupFunction<
      Void Function(Pointer<Void>, Pointer<Void>),
      void Function(Pointer<Void>, Pointer<Void>)>('cyxchat_file_set_conn_ctx');

  // Hop count functions
  late final cyxchat_set_hop_count = _lib.lookupFunction<
      Void Function(Pointer<Void>, Uint8),
      void Function(Pointer<Void>, int)>('cyxchat_set_hop_count');

  late final cyxchat_get_hop_count = _lib.lookupFunction<
      Uint8 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_get_hop_count');

  // Onion keypair persistence functions
  late final cyxchat_get_onion_secret = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_get_onion_secret');

  late final cyxchat_set_onion_keypair = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_set_onion_keypair');
}

// Error codes
class CyxChatError {
  static const ok = 0;
  static const errNull = -1;
  static const errMemory = -2;
  static const errInvalid = -3;
  static const errNotFound = -4;
  static const errExists = -5;
  static const errFull = -6;
  static const errCrypto = -7;
  static const errNetwork = -8;
  static const errTimeout = -9;
  static const errBlocked = -10;
  static const errNotMember = -11;
  static const errNotAdmin = -12;
  static const errFileTooLarge = -13;
  static const errTransfer = -14;
  static const errNoPermission = -15;
  static const errRestricted = -16;
  static const errMuted = -17;
  static const errSlowMode = -18;
  static const errEditExpired = -19;
  static const errNotOwner = -20;
  static const errAlreadyPinned = -21;
  static const errNotPinned = -22;
  static const errPinLimit = -23;
  static const errNoKey = -24;  // No shared key with peer (key exchange not complete)
}

// Connection states
class CyxChatConnState {
  static const disconnected = 0;
  static const discovering = 1;
  static const connecting = 2;
  static const relaying = 3;
  static const connected = 4;

  static String name(int state) {
    switch (state) {
      case disconnected: return 'Disconnected';
      case discovering: return 'Discovering';
      case connecting: return 'Connecting';
      case relaying: return 'Relaying';
      case connected: return 'Connected';
      default: return 'Unknown';
    }
  }

  static bool isActive(int state) {
    return state == connected || state == relaying;
  }
}

// NAT types
class CyxChatNatType {
  static const unknown = 0;
  static const open = 1;
  static const cone = 2;
  static const symmetric = 3;
  static const blocked = 4;

  static String name(int type) {
    switch (type) {
      case unknown: return 'Unknown';
      case open: return 'Open/Public';
      case cone: return 'Cone NAT';
      case symmetric: return 'Symmetric NAT';
      case blocked: return 'Blocked';
      default: return 'Unknown';
    }
  }
}

// Message types
class CyxChatMsgType {
  static const text = 0x10;
  static const ack = 0x11;
  static const read = 0x12;
  static const typing = 0x13;
  static const fileMeta = 0x14;
  static const fileChunk = 0x15;
  static const fileAck = 0x16;
  static const reaction = 0x17;
  static const delete = 0x18;
  static const edit = 0x19;
  static const groupText = 0x20;
  static const groupInvite = 0x21;
  static const groupJoin = 0x22;
  static const groupLeave = 0x23;
  static const groupKick = 0x24;
  static const groupKey = 0x25;
  static const groupInfo = 0x26;
  static const groupAdmin = 0x27;
  static const groupKeyAck = 0x28;
  static const presence = 0x30;
  static const presenceReq = 0x31;
  // File transfer protocol v2 (hybrid with DHT support)
  static const fileOffer = 0x40;
  static const fileAccept = 0x41;
  static const fileReject = 0x42;
  static const fileComplete = 0x43;
  static const fileCancel = 0x44;
  static const fileDhtReady = 0x45;
  // Call signaling
  static const callOffer = 0x50;
  static const callAnswer = 0x51;
  static const callIce = 0x52;
  static const callEnd = 0x53;
  static const callReject = 0x54;
  static const callBusy = 0x55;
}

// File transfer states
class CyxChatFileState {
  static const pending = 0;
  static const sending = 1;
  static const receiving = 2;
  static const paused = 3;
  static const completed = 4;
  static const failed = 5;
  static const cancelled = 6;

  static String name(int state) {
    switch (state) {
      case pending: return 'Pending';
      case sending: return 'Sending';
      case receiving: return 'Receiving';
      case paused: return 'Paused';
      case completed: return 'Completed';
      case failed: return 'Failed';
      case cancelled: return 'Cancelled';
      default: return 'Unknown';
    }
  }

  static bool isActive(int state) {
    return state == sending || state == receiving;
  }

  static bool isComplete(int state) {
    return state == completed || state == failed || state == cancelled;
  }
}

// File transfer constants
class CyxChatFileConst {
  static const maxFilename = 128;
  static const chunkSize = 90;  // Onion routing chunk size (LoRa compatible)
  static const maxFileSize = 64 * 1024; // 64KB limit for onion routing

  // Direct P2P mode constants - bypass onion/LoRa constraints
  static const directChunkSize = 32768;  // 32KB chunks for direct P2P
  static const directMaxFileSize = 1024 * 1024 * 1024; // 1GB max in direct mode

  // DHT-based file transfer constants
  static const dhtChunkSize = 120;      // 160 - 40 bytes crypto overhead
  static const dhtMaxChunks = 14;
  static const dhtMaxFileSize = 1680;   // Max file size for full DHT storage
  static const dhtTtlSeconds = 86400;   // 24 hour TTL
  static const offerTimeoutMs = 30000;  // 30 second offer timeout
}

// File transfer mode (hybrid protocol)
class CyxChatFileTransferMode {
  /// Direct P2P transfer (online peer)
  static const direct = 0x01;

  /// Via relay server
  static const relay = 0x02;

  /// Small file stored entirely in DHT
  static const dhtMicro = 0x03;

  /// Offer stored in DHT, transfer when online
  static const dhtSignal = 0x04;

  static String name(int mode) {
    switch (mode) {
      case direct: return 'Direct';
      case relay: return 'Relay';
      case dhtMicro: return 'DHT (micro)';
      case dhtSignal: return 'DHT (signal)';
      default: return 'Unknown';
    }
  }

  static bool isDht(int mode) {
    return mode == dhtMicro || mode == dhtSignal;
  }
}

// File rejection reasons
class CyxChatFileRejectReason {
  static const declined = 0;   // User declined
  static const tooLarge = 1;   // File too large
  static const busy = 2;       // Too many transfers
  static const blocked = 3;    // Sender is blocked

  static String name(int reason) {
    switch (reason) {
      case declined: return 'Declined';
      case tooLarge: return 'File too large';
      case busy: return 'Busy';
      case blocked: return 'Blocked';
      default: return 'Unknown';
    }
  }
}

// Group roles
class CyxChatGroupRole {
  static const member = 0;
  static const admin = 1;
  static const owner = 2;

  static String name(int role) {
    switch (role) {
      case member: return 'Member';
      case admin: return 'Admin';
      case owner: return 'Owner';
      default: return 'Unknown';
    }
  }

  static bool canInvite(int role) {
    return role >= admin;
  }

  static bool canKick(int role) {
    return role >= admin;
  }

  static bool canRotateKey(int role) {
    return role >= admin;
  }

  static bool canPromote(int role) {
    return role == owner;
  }
}

/// Group send permission settings (matches cyxchat_group_send_setting_t)
class CyxChatGroupSendSetting {
  static const all = 0;      // Everyone can send (default)
  static const admins = 1;   // Only admins can send (broadcast/channel mode)
  static const selected = 2; // Only selected members can send

  static String name(int setting) {
    switch (setting) {
      case all: return 'Everyone';
      case admins: return 'Admins Only';
      case selected: return 'Selected Members';
      default: return 'Unknown';
    }
  }

  static String description(int setting) {
    switch (setting) {
      case all: return 'All members can send messages';
      case admins: return 'Only admins can send messages (broadcast mode)';
      case selected: return 'Only selected members can send messages';
      default: return '';
    }
  }
}

// Group constants
class CyxChatGroupConst {
  static const maxGroupMembers = 50;
  static const maxGroupAdmins = 5;
  static const maxDisplayName = 64;
  static const maxStatusLen = 128;
  static const groupIdSize = 8;
}
