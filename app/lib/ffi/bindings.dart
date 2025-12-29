import 'dart:ffi';
import 'dart:io';
import 'package:ffi/ffi.dart';

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
}
