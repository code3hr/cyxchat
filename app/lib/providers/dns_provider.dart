import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';

/// DNS record resolved from the network
class DnsRecord {
  final String name;
  final String nodeId;
  final String? stunAddress;
  final DateTime? expiresAt;

  DnsRecord({
    required this.name,
    required this.nodeId,
    this.stunAddress,
    this.expiresAt,
  });

  /// Full name with .cyx suffix
  String get fullName => name.contains('.') ? name : '$name.cyx';

  @override
  String toString() => 'DnsRecord($fullName -> $nodeId)';
}

/// Pending lookup status
class PendingLookup {
  final String name;
  final DateTime startTime;
  final Completer<DnsRecord?> completer;

  PendingLookup({
    required this.name,
    required this.startTime,
    required this.completer,
  });
}

/// DNS provider for name registration and lookup
class DnsProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  // State
  bool _initialized = false;
  String? _registeredName;
  final Map<String, DnsRecord> _cache = {};
  final Map<String, String> _petnames = {}; // nodeId -> petname
  final Map<String, PendingLookup> _pendingLookups = {};

  // Polling timer
  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 500);

  // Getters
  bool get initialized => _initialized;
  String? get registeredName => _registeredName;
  String get fullRegisteredName =>
      _registeredName != null ? '$_registeredName.cyx' : '';
  Map<String, DnsRecord> get cache => Map.unmodifiable(_cache);
  Map<String, String> get petnames => Map.unmodifiable(_petnames);

  /// Initialize DNS module
  Future<bool> initialize({required List<int> localId, List<int>? signingKey}) async {
    if (_initialized) return true;

    final localIdPtr = calloc<Uint8>(32);
    Pointer<Uint8>? signingKeyPtr;

    try {
      for (int i = 0; i < 32 && i < localId.length; i++) {
        localIdPtr[i] = localId[i];
      }

      if (signingKey != null && signingKey.length >= 64) {
        signingKeyPtr = calloc<Uint8>(64);
        for (int i = 0; i < 64; i++) {
          signingKeyPtr[i] = signingKey[i];
        }
      }

      final result = _bindings.dnsCreate(localIdPtr, signingKeyPtr);
      if (result != CyxChatError.ok) {
        debugPrint('Failed to create DNS: ${_bindings.errorString(result)}');
        return false;
      }

      _initialized = true;
      _startPolling();
      notifyListeners();
      return true;
    } finally {
      calloc.free(localIdPtr);
      if (signingKeyPtr != null) {
        calloc.free(signingKeyPtr);
      }
    }
  }

  /// Shutdown DNS module
  void shutdown() {
    _stopPolling();

    if (_initialized) {
      _bindings.dnsDestroy();
      _initialized = false;
      _registeredName = null;
      _cache.clear();
      _petnames.clear();
      notifyListeners();
    }
  }

  /// Register a username (without .cyx suffix)
  Future<bool> register(String name) async {
    if (!_initialized) return false;

    // Validate name
    if (!_bindings.dnsValidateName(name)) {
      debugPrint('Invalid DNS name: $name');
      return false;
    }

    final result = _bindings.dnsRegister(name);
    if (result == CyxChatError.ok) {
      _registeredName = name.toLowerCase();
      notifyListeners();
      return true;
    }

    debugPrint('DNS register failed: ${_bindings.errorString(result)}');
    return false;
  }

  /// Refresh current registration
  Future<bool> refresh() async {
    if (!_initialized || _registeredName == null) return false;

    final result = _bindings.dnsRefresh();
    return result == CyxChatError.ok;
  }

  /// Unregister current name
  Future<bool> unregister() async {
    if (!_initialized) return false;

    final result = _bindings.dnsUnregister();
    if (result == CyxChatError.ok) {
      _registeredName = null;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Lookup a username (async with cache check)
  Future<DnsRecord?> lookup(String name) async {
    if (!_initialized) return null;

    // Normalize name (strip .cyx suffix)
    final normalizedName = name.toLowerCase().replaceAll('.cyx', '');

    // Check cache first
    if (_cache.containsKey(normalizedName)) {
      final record = _cache[normalizedName]!;
      if (record.expiresAt == null || record.expiresAt!.isAfter(DateTime.now())) {
        return record;
      }
    }

    // Check if already pending
    if (_pendingLookups.containsKey(normalizedName)) {
      return _pendingLookups[normalizedName]!.completer.future;
    }

    // Create pending lookup
    final completer = Completer<DnsRecord?>();
    _pendingLookups[normalizedName] = PendingLookup(
      name: normalizedName,
      startTime: DateTime.now(),
      completer: completer,
    );

    // Send lookup request
    final result = _bindings.dnsLookup(normalizedName);
    if (result != CyxChatError.ok) {
      _pendingLookups.remove(normalizedName);
      return null;
    }

    // Wait for result (with timeout)
    try {
      return await completer.future.timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          _pendingLookups.remove(normalizedName);
          return null;
        },
      );
    } catch (e) {
      _pendingLookups.remove(normalizedName);
      return null;
    }
  }

  /// Resolve from cache only (synchronous)
  DnsRecord? resolve(String name) {
    if (!_initialized) return null;

    final normalizedName = name.toLowerCase().replaceAll('.cyx', '');

    // Check local cache
    if (_cache.containsKey(normalizedName)) {
      return _cache[normalizedName];
    }

    // Try native cache
    final nodeIdPtr = _bindings.dnsResolve(normalizedName);
    if (nodeIdPtr != null) {
      final nodeId = _bytesToHex(nodeIdPtr, 32);
      calloc.free(nodeIdPtr);

      final record = DnsRecord(
        name: normalizedName,
        nodeId: nodeId,
      );
      _cache[normalizedName] = record;
      return record;
    }

    return null;
  }

  /// Check if name is cached
  bool isCached(String name) {
    if (!_initialized) return false;
    final normalizedName = name.toLowerCase().replaceAll('.cyx', '');
    return _bindings.dnsIsCached(normalizedName);
  }

  /// Invalidate cached name
  void invalidate(String name) {
    if (!_initialized) return;
    final normalizedName = name.toLowerCase().replaceAll('.cyx', '');
    _cache.remove(normalizedName);
    _bindings.dnsInvalidate(normalizedName);
    notifyListeners();
  }

  /// Set a local petname for a node
  Future<bool> setPetname(String nodeIdHex, String petname) async {
    if (!_initialized) return false;

    final nodeId = _hexToBytes(nodeIdHex);
    final nodeIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < nodeId.length; i++) {
        nodeIdPtr[i] = nodeId[i];
      }

      final result = _bindings.dnsSetPetname(nodeIdPtr, petname);
      if (result == CyxChatError.ok) {
        _petnames[nodeIdHex] = petname;
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(nodeIdPtr);
    }
  }

  /// Get petname for a node
  String? getPetname(String nodeIdHex) {
    // Check local cache first
    if (_petnames.containsKey(nodeIdHex)) {
      return _petnames[nodeIdHex];
    }

    if (!_initialized) return null;

    final nodeId = _hexToBytes(nodeIdHex);
    final nodeIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < nodeId.length; i++) {
        nodeIdPtr[i] = nodeId[i];
      }

      final petname = _bindings.dnsGetPetname(nodeIdPtr);
      if (petname != null) {
        _petnames[nodeIdHex] = petname;
      }
      return petname;
    } finally {
      calloc.free(nodeIdPtr);
    }
  }

  /// Remove petname for a node
  Future<bool> removePetname(String nodeIdHex) async {
    if (!_initialized) return false;

    final nodeId = _hexToBytes(nodeIdHex);
    final nodeIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < nodeId.length; i++) {
        nodeIdPtr[i] = nodeId[i];
      }

      final result = _bindings.dnsSetPetname(nodeIdPtr, '');
      if (result == CyxChatError.ok) {
        _petnames.remove(nodeIdHex);
        notifyListeners();
        return true;
      }
      return false;
    } finally {
      calloc.free(nodeIdPtr);
    }
  }

  /// Generate crypto-name from public key
  String generateCryptoName(List<int> pubkey) {
    final pubkeyPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < pubkey.length; i++) {
        pubkeyPtr[i] = pubkey[i];
      }

      return _bindings.dnsCryptoName(pubkeyPtr);
    } finally {
      calloc.free(pubkeyPtr);
    }
  }

  /// Check if a name is a crypto-name
  bool isCryptoName(String name) {
    return _bindings.dnsIsCryptoName(name);
  }

  /// Validate name format
  bool validateName(String name) {
    return _bindings.dnsValidateName(name);
  }

  /// Get display name for a node (petname > global name > node ID)
  String getDisplayName(String nodeIdHex, {String? fallback}) {
    // Try petname first
    final petname = getPetname(nodeIdHex);
    if (petname != null && petname.isNotEmpty) {
      return petname;
    }

    // Try global name from cache
    for (final entry in _cache.entries) {
      if (entry.value.nodeId == nodeIdHex) {
        return entry.value.fullName;
      }
    }

    // Return fallback or shortened node ID
    return fallback ?? '${nodeIdHex.substring(0, 8)}...';
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
    _bindings.dnsPoll(now);

    // Check if registered name changed
    final regName = _bindings.dnsGetRegisteredName();
    if (regName != _registeredName) {
      _registeredName = regName;
      notifyListeners();
    }

    // Check pending lookups for completion
    _checkPendingLookups();

    // Clean expired pending lookups
    _cleanExpiredLookups();
  }

  void _checkPendingLookups() {
    for (final name in _pendingLookups.keys.toList()) {
      // Try to resolve from cache
      final nodeIdPtr = _bindings.dnsResolve(name);
      if (nodeIdPtr != null) {
        final nodeId = _bytesToHex(nodeIdPtr, 32);
        calloc.free(nodeIdPtr);

        final record = DnsRecord(
          name: name,
          nodeId: nodeId,
        );

        _cache[name] = record;

        final pending = _pendingLookups.remove(name);
        if (pending != null && !pending.completer.isCompleted) {
          pending.completer.complete(record);
        }

        notifyListeners();
      }
    }
  }

  void _cleanExpiredLookups() {
    final now = DateTime.now();
    final timeout = const Duration(seconds: 5);

    for (final name in _pendingLookups.keys.toList()) {
      final pending = _pendingLookups[name]!;
      if (now.difference(pending.startTime) > timeout) {
        _pendingLookups.remove(name);
        if (!pending.completer.isCompleted) {
          pending.completer.complete(null);
        }
      }
    }
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

  String _bytesToHex(Pointer<Uint8> ptr, int len) {
    final buffer = StringBuffer();
    for (int i = 0; i < len; i++) {
      buffer.write(ptr[i].toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}
