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
