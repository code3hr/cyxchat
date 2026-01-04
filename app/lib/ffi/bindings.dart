import 'dart:ffi';
import 'dart:io';
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

  /// Get next received message
  /// Returns map with 'from', 'type', 'data' keys, or null if queue empty
  Map<String, dynamic>? chatRecvNext() {
    if (_chatCtx == null) return null;

    final fromPtr = calloc<Uint8>(32);
    final typePtr = calloc<Uint8>(1);
    final dataPtr = calloc<Uint8>(4096);
    final lenPtr = calloc<Size>(1);
    lenPtr.value = 4096;

    try {
      final result = _native.cyxchat_recv_next(
        _chatCtx!,
        fromPtr,
        typePtr,
        dataPtr,
        lenPtr,
      );

      if (result != 0) {
        // Copy data before freeing
        final fromBytes = List<int>.generate(32, (i) => fromPtr[i]);
        final type = typePtr[0];
        final dataLen = lenPtr.value;
        final data = List<int>.generate(dataLen, (i) => dataPtr[i]);

        return {
          'from': fromBytes,
          'type': type,
          'data': data,
        };
      }
      return null;
    } finally {
      calloc.free(fromPtr);
      calloc.free(typePtr);
      calloc.free(dataPtr);
      calloc.free(lenPtr);
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
        final parseResult = _native.cyxchat_msg_id_from_hex(
          replyToHex.toNativeUtf8().cast(),
          replyToPtr,
        );
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

  /// Send ACK for received message
  int chatSendAck(Pointer<Uint8> to, String msgIdHex, int status) {
    if (_chatCtx == null) return CyxChatError.errNull;

    final msgIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        msgIdHex.toNativeUtf8().cast(),
        msgIdPtr,
      );
      if (parseResult != 0) return parseResult;

      return _native.cyxchat_send_ack(_chatCtx!, to, msgIdPtr, status);
    } finally {
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
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        msgIdHex.toNativeUtf8().cast(),
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
      calloc.free(msgIdPtr);
      calloc.free(reactionPtr);
    }
  }

  /// Request message deletion
  int chatSendDelete(Pointer<Uint8> to, String msgIdHex) {
    if (_chatCtx == null) return CyxChatError.errNull;

    final msgIdPtr = calloc<Uint8>(8);
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        msgIdHex.toNativeUtf8().cast(),
        msgIdPtr,
      );
      if (parseResult != 0) return parseResult;

      return _native.cyxchat_send_delete(_chatCtx!, to, msgIdPtr);
    } finally {
      calloc.free(msgIdPtr);
    }
  }

  /// Send edited message
  int chatSendEdit(Pointer<Uint8> to, String msgIdHex, String newText) {
    if (_chatCtx == null) return CyxChatError.errNull;

    final msgIdPtr = calloc<Uint8>(8);
    final textPtr = newText.toNativeUtf8();
    try {
      final parseResult = _native.cyxchat_msg_id_from_hex(
        msgIdHex.toNativeUtf8().cast(),
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
      calloc.free(msgIdPtr);
      calloc.free(textPtr);
    }
  }

  // ============================================================
  // Connection Management
  // ============================================================

  /// Connection context pointer (opaque)
  Pointer<Void>? _connCtx;

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
      _native.cyxchat_conn_destroy(_connCtx!);
      _connCtx = null;
    }
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
  // Mail Module (CyxMail)
  // ============================================================

  /// Mail context pointer (opaque)
  Pointer<Void>? _mailCtx;

  /// Create mail context
  int mailCreate(Pointer<Void> chatCtx) {
    final ctxPtr = calloc<Pointer<Void>>();
    try {
      final result = _native.cyxchat_mail_ctx_create(ctxPtr, chatCtx);
      if (result == 0) {
        _mailCtx = ctxPtr.value;
      }
      return result;
    } finally {
      calloc.free(ctxPtr);
    }
  }

  /// Destroy mail context
  void mailDestroy() {
    if (_mailCtx != null) {
      _native.cyxchat_mail_ctx_destroy(_mailCtx!);
      _mailCtx = null;
    }
  }

  /// Poll mail events
  int mailPoll(int nowMs) {
    if (_mailCtx == null) return 0;
    return _native.cyxchat_mail_poll(_mailCtx!, nowMs);
  }

  /// Generate mail ID
  void mailGenerateId(Pointer<Uint8> idOut) {
    _native.cyxchat_mail_generate_id(idOut);
  }

  /// Mail ID to hex string
  String mailIdToHex(Pointer<Uint8> id) {
    final hexOut = calloc<Int8>(17); // 16 hex chars + null
    try {
      _native.cyxchat_mail_id_to_hex(id, hexOut);
      return hexOut.cast<Utf8>().toDartString();
    } finally {
      calloc.free(hexOut);
    }
  }

  /// Parse mail ID from hex
  int mailIdFromHex(String hex, Pointer<Uint8> idOut) {
    final hexPtr = hex.toNativeUtf8();
    try {
      return _native.cyxchat_mail_id_from_hex(hexPtr.cast(), idOut);
    } finally {
      calloc.free(hexPtr);
    }
  }

  /// Check if mail ID is null
  bool mailIdIsNull(Pointer<Uint8> id) {
    return _native.cyxchat_mail_id_is_null(id) != 0;
  }

  /// Get folder name
  String mailFolderName(int folder) {
    final ptr = _native.cyxchat_mail_folder_name(folder);
    return ptr.cast<Utf8>().toDartString();
  }

  /// Get status name
  String mailStatusName(int status) {
    final ptr = _native.cyxchat_mail_status_name(status);
    return ptr.cast<Utf8>().toDartString();
  }

  /// Get mail count in folder
  int mailCount(int folder) {
    if (_mailCtx == null) return 0;
    return _native.cyxchat_mail_count(_mailCtx!, folder);
  }

  /// Get unread mail count in folder
  int mailUnreadCount(int folder) {
    if (_mailCtx == null) return 0;
    return _native.cyxchat_mail_unread_count(_mailCtx!, folder);
  }

  /// Send simple mail
  int mailSendSimple(
    Pointer<Uint8> to,
    String subject,
    String body,
    Pointer<Uint8>? inReplyTo,
    Pointer<Uint8> mailIdOut,
  ) {
    if (_mailCtx == null) return CyxChatError.errNull;
    final subjectPtr = subject.toNativeUtf8();
    final bodyPtr = body.toNativeUtf8();
    try {
      return _native.cyxchat_mail_send_simple(
        _mailCtx!,
        to,
        subjectPtr.cast(),
        bodyPtr.cast(),
        inReplyTo ?? nullptr,
        mailIdOut,
      );
    } finally {
      calloc.free(subjectPtr);
      calloc.free(bodyPtr);
    }
  }

  /// Mark mail as read
  int mailMarkRead(Pointer<Uint8> mailId, bool sendReceipt) {
    if (_mailCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_mail_mark_read(_mailCtx!, mailId, sendReceipt ? 1 : 0);
  }

  /// Mark mail as unread
  int mailMarkUnread(Pointer<Uint8> mailId) {
    if (_mailCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_mail_mark_unread(_mailCtx!, mailId);
  }

  /// Set mail flagged status
  int mailSetFlagged(Pointer<Uint8> mailId, bool flagged) {
    if (_mailCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_mail_set_flagged(_mailCtx!, mailId, flagged ? 1 : 0);
  }

  /// Move mail to folder
  int mailMove(Pointer<Uint8> mailId, int folder) {
    if (_mailCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_mail_move(_mailCtx!, mailId, folder);
  }

  /// Delete mail (to trash)
  int mailDelete(Pointer<Uint8> mailId) {
    if (_mailCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_mail_delete(_mailCtx!, mailId);
  }

  /// Permanently delete mail
  int mailDeletePermanent(Pointer<Uint8> mailId) {
    if (_mailCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_mail_delete_permanent(_mailCtx!, mailId);
  }

  /// Empty trash folder
  int mailEmptyTrash() {
    if (_mailCtx == null) return CyxChatError.errNull;
    return _native.cyxchat_mail_empty_trash(_mailCtx!);
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
        parseResult = _native.cyxchat_msg_id_from_hex(
          replyToHex.toNativeUtf8().cast(),
          replyToPtr,
        );
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

  /// Parse group ID from hex string
  int groupIdFromHex(String hex, Pointer<Uint8> idOut) {
    final hexPtr = hex.toNativeUtf8();
    try {
      return _native.cyxchat_group_id_from_hex(hexPtr.cast(), idOut);
    } finally {
      calloc.free(hexPtr);
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
    final fromHex = _bytesToHex(from, 32);

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

    final fileIdHex = fileIdToHex(fileId);

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

    final fileIdHex = fileIdToHex(fileId);
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

    final fileIdHex = fileIdToHex(fileId);
    onFileError!(fileIdHex, error);
  }

  /// Helper to convert bytes to hex string
  String _bytesToHex(Pointer<Uint8> bytes, int len) {
    final buffer = StringBuffer();
    for (int i = 0; i < len; i++) {
      buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
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
          Pointer<Uint8>, Pointer<Size>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Uint8>,
          Pointer<Uint8>, Pointer<Size>)>('cyxchat_recv_next');

  late final cyxchat_send_text = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, Size,
          Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>, int,
          Pointer<Uint8>, Pointer<Uint8>)>('cyxchat_send_text');

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

  // Mail functions
  late final cyxchat_mail_ctx_create = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, Pointer<Void>),
      int Function(Pointer<Pointer<Void>>, Pointer<Void>)>(
      'cyxchat_mail_ctx_create');

  late final cyxchat_mail_ctx_destroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_mail_ctx_destroy');

  late final cyxchat_mail_poll = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('cyxchat_mail_poll');

  late final cyxchat_mail_generate_id = _lib.lookupFunction<
      Void Function(Pointer<Uint8>),
      void Function(Pointer<Uint8>)>('cyxchat_mail_generate_id');

  late final cyxchat_mail_id_to_hex = _lib.lookupFunction<
      Void Function(Pointer<Uint8>, Pointer<Int8>),
      void Function(Pointer<Uint8>, Pointer<Int8>)>('cyxchat_mail_id_to_hex');

  late final cyxchat_mail_id_from_hex = _lib.lookupFunction<
      Int32 Function(Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Int8>, Pointer<Uint8>)>('cyxchat_mail_id_from_hex');

  late final cyxchat_mail_id_is_null = _lib.lookupFunction<
      Int32 Function(Pointer<Uint8>),
      int Function(Pointer<Uint8>)>('cyxchat_mail_id_is_null');

  late final cyxchat_mail_folder_name = _lib.lookupFunction<
      Pointer<Int8> Function(Int32),
      Pointer<Int8> Function(int)>('cyxchat_mail_folder_name');

  late final cyxchat_mail_status_name = _lib.lookupFunction<
      Pointer<Int8> Function(Int32),
      Pointer<Int8> Function(int)>('cyxchat_mail_status_name');

  late final cyxchat_mail_count = _lib.lookupFunction<
      Size Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)>('cyxchat_mail_count');

  late final cyxchat_mail_unread_count = _lib.lookupFunction<
      Size Function(Pointer<Void>, Int32),
      int Function(Pointer<Void>, int)>('cyxchat_mail_unread_count');

  late final cyxchat_mail_send_simple = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>,
          Pointer<Int8>, Pointer<Uint8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>, Pointer<Int8>,
          Pointer<Int8>, Pointer<Uint8>, Pointer<Uint8>)>(
      'cyxchat_mail_send_simple');

  late final cyxchat_mail_mark_read = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_mail_mark_read');

  late final cyxchat_mail_mark_unread = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_mail_mark_unread');

  late final cyxchat_mail_set_flagged = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>(
      'cyxchat_mail_set_flagged');

  late final cyxchat_mail_move = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>, Int32),
      int Function(Pointer<Void>, Pointer<Uint8>, int)>('cyxchat_mail_move');

  late final cyxchat_mail_delete = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>('cyxchat_mail_delete');

  late final cyxchat_mail_delete_permanent = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Uint8>)>(
      'cyxchat_mail_delete_permanent');

  late final cyxchat_mail_empty_trash = _lib.lookupFunction<
      Int32 Function(Pointer<Void>),
      int Function(Pointer<Void>)>('cyxchat_mail_empty_trash');

  // Group functions
  late final cyxchat_group_ctx_create = _lib.lookupFunction<
      Int32 Function(Pointer<Pointer<Void>>, Pointer<Void>),
      int Function(Pointer<Pointer<Void>>, Pointer<Void>)>(
      'cyxchat_group_ctx_create');

  late final cyxchat_group_ctx_destroy = _lib.lookupFunction<
      Void Function(Pointer<Void>),
      void Function(Pointer<Void>)>('cyxchat_group_ctx_destroy');

  late final cyxchat_group_poll = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Uint64),
      int Function(Pointer<Void>, int)>('cyxchat_group_poll');

  late final cyxchat_group_create = _lib.lookupFunction<
      Int32 Function(Pointer<Void>, Pointer<Int8>, Pointer<Uint8>),
      int Function(Pointer<Void>, Pointer<Int8>, Pointer<Uint8>)>(
      'cyxchat_group_create');

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
  static const presence = 0x30;
  static const presenceReq = 0x31;
  // File transfer protocol v2 (hybrid with DHT support)
  static const fileOffer = 0x40;
  static const fileAccept = 0x41;
  static const fileReject = 0x42;
  static const fileComplete = 0x43;
  static const fileCancel = 0x44;
  static const fileDhtReady = 0x45;
  // Mail message types
  static const mailSend = 0xE0;
  static const mailAck = 0xE1;
  static const mailList = 0xE2;
  static const mailListResp = 0xE3;
  static const mailFetch = 0xE4;
  static const mailFetchResp = 0xE5;
  static const mailDelete = 0xE6;
  static const mailDeleteAck = 0xE7;
  static const mailNotify = 0xE8;
  static const mailReadReceipt = 0xE9;
  static const mailBounce = 0xEA;
}

// Mail folder types
class CyxChatMailFolder {
  static const inbox = 0;
  static const sent = 1;
  static const drafts = 2;
  static const archive = 3;
  static const trash = 4;
  static const spam = 5;
  static const custom = 6;

  static String name(int folder) {
    switch (folder) {
      case inbox: return 'Inbox';
      case sent: return 'Sent';
      case drafts: return 'Drafts';
      case archive: return 'Archive';
      case trash: return 'Trash';
      case spam: return 'Spam';
      case custom: return 'Custom';
      default: return 'Unknown';
    }
  }
}

// Mail flags (bitfield)
class CyxChatMailFlag {
  static const seen = 1 << 0;
  static const flagged = 1 << 1;
  static const answered = 1 << 2;
  static const draft = 1 << 3;
  static const deleted = 1 << 4;
  static const attachment = 1 << 5;

  static bool isSeen(int flags) => (flags & seen) != 0;
  static bool isFlagged(int flags) => (flags & flagged) != 0;
  static bool isAnswered(int flags) => (flags & answered) != 0;
  static bool isDraft(int flags) => (flags & draft) != 0;
  static bool isDeleted(int flags) => (flags & deleted) != 0;
  static bool hasAttachment(int flags) => (flags & attachment) != 0;
}

// Mail status
class CyxChatMailStatus {
  static const draft = 0;
  static const queued = 1;
  static const sent = 2;
  static const delivered = 3;
  static const failed = 4;

  static String name(int status) {
    switch (status) {
      case draft: return 'Draft';
      case queued: return 'Queued';
      case sent: return 'Sent';
      case delivered: return 'Delivered';
      case failed: return 'Failed';
      default: return 'Unknown';
    }
  }
}

// Mail bounce reasons
class CyxChatMailBounce {
  static const noRoute = 0;
  static const rejected = 1;
  static const timeout = 2;
  static const quota = 3;

  static String reason(int bounce) {
    switch (bounce) {
      case noRoute: return 'Destination unreachable';
      case rejected: return 'Recipient rejected';
      case timeout: return 'Delivery timeout';
      case quota: return 'Mailbox full';
      default: return 'Unknown';
    }
  }
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
  static const chunkSize = 1024;
  static const maxFileSize = 64 * 1024; // 64KB limit

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
