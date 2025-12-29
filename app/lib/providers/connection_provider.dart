import 'dart:async';
import 'dart:ffi';
import 'package:flutter/foundation.dart';
import 'package:ffi/ffi.dart';
import '../ffi/bindings.dart';

/// Connection state for a specific peer
class PeerConnectionState {
  final String peerId;
  final int state;
  final bool isRelayed;
  final DateTime? connectedAt;

  PeerConnectionState({
    required this.peerId,
    required this.state,
    required this.isRelayed,
    this.connectedAt,
  });

  String get stateName => CyxChatConnState.name(state);
  bool get isConnected => CyxChatConnState.isActive(state);

  @override
  String toString() => 'PeerConnectionState($peerId: $stateName, relayed: $isRelayed)';
}

/// Network status information
class NetworkStatus {
  final String? publicAddress;
  final int natType;
  final bool stunComplete;
  final bool bootstrapConnected;
  final int activeConnections;
  final int relayConnections;

  NetworkStatus({
    this.publicAddress,
    this.natType = CyxChatNatType.unknown,
    this.stunComplete = false,
    this.bootstrapConnected = false,
    this.activeConnections = 0,
    this.relayConnections = 0,
  });

  String get natTypeName => CyxChatNatType.name(natType);
  int get directConnections => activeConnections - relayConnections;

  @override
  String toString() => 'NetworkStatus(addr: $publicAddress, nat: $natTypeName, '
      'active: $activeConnections, relay: $relayConnections)';
}

/// Connection provider for managing P2P connections
class ConnectionProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  // State
  bool _initialized = false;
  NetworkStatus _networkStatus = NetworkStatus();
  final Map<String, PeerConnectionState> _peerStates = {};

  // Polling timer
  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 100);

  // Getters
  bool get initialized => _initialized;
  NetworkStatus get networkStatus => _networkStatus;
  Map<String, PeerConnectionState> get peerStates => Map.unmodifiable(_peerStates);

  /// Initialize connection manager
  Future<bool> initialize({
    required String bootstrap,
    required List<int> localId,
  }) async {
    if (_initialized) return true;

    // Convert local ID to native pointer
    final localIdPtr = calloc<Uint8>(32);
    for (int i = 0; i < 32 && i < localId.length; i++) {
      localIdPtr[i] = localId[i];
    }

    try {
      final result = _bindings.connCreate(bootstrap, localIdPtr);
      if (result != CyxChatError.ok) {
        debugPrint('Failed to create connection: ${_bindings.errorString(result)}');
        return false;
      }

      _initialized = true;

      // Start polling
      _startPolling();

      notifyListeners();
      return true;
    } finally {
      calloc.free(localIdPtr);
    }
  }

  /// Shutdown connection manager
  void shutdown() {
    _stopPolling();

    if (_initialized) {
      _bindings.connDestroy();
      _initialized = false;
      _peerStates.clear();
      _networkStatus = NetworkStatus();
      notifyListeners();
    }
  }

  /// Connect to a peer
  Future<int> connect(String peerIdHex) async {
    if (!_initialized) return CyxChatError.errNull;

    final peerId = _hexToBytes(peerIdHex);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerId.length; i++) {
        peerIdPtr[i] = peerId[i];
      }

      final result = _bindings.connConnect(peerIdPtr);

      if (result == CyxChatError.ok) {
        _peerStates[peerIdHex] = PeerConnectionState(
          peerId: peerIdHex,
          state: CyxChatConnState.connecting,
          isRelayed: false,
        );
        notifyListeners();
      }

      return result;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Disconnect from a peer
  Future<int> disconnect(String peerIdHex) async {
    if (!_initialized) return CyxChatError.errNull;

    final peerId = _hexToBytes(peerIdHex);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerId.length; i++) {
        peerIdPtr[i] = peerId[i];
      }

      final result = _bindings.connDisconnect(peerIdPtr);

      if (result == CyxChatError.ok) {
        _peerStates.remove(peerIdHex);
        notifyListeners();
      }

      return result;
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Get connection state for a peer
  PeerConnectionState? getState(String peerIdHex) {
    return _peerStates[peerIdHex];
  }

  /// Check if peer is connected (direct or relay)
  bool isConnected(String peerIdHex) {
    final state = _peerStates[peerIdHex];
    return state?.isConnected ?? false;
  }

  /// Check if connection is via relay
  bool isRelayed(String peerIdHex) {
    return _peerStates[peerIdHex]?.isRelayed ?? false;
  }

  /// Add relay server
  int addRelayServer(String address) {
    if (!_initialized) return CyxChatError.errNull;
    return _bindings.connAddRelay(address);
  }

  /// Force relay for a peer
  Future<int> forceRelay(String peerIdHex) async {
    if (!_initialized) return CyxChatError.errNull;

    final peerId = _hexToBytes(peerIdHex);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerId.length; i++) {
        peerIdPtr[i] = peerId[i];
      }

      return _bindings.connForceRelay(peerIdPtr);
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
    _bindings.connPoll(now);

    // Update network status
    _updateNetworkStatus();

    // Update peer states
    _updatePeerStates();
  }

  void _updateNetworkStatus() {
    final publicAddr = _bindings.connGetPublicAddr();

    final newStatus = NetworkStatus(
      publicAddress: publicAddr,
      stunComplete: publicAddr != null,
      activeConnections: _peerStates.values
          .where((p) => p.isConnected)
          .length,
      relayConnections: _peerStates.values
          .where((p) => p.isConnected && p.isRelayed)
          .length,
    );

    if (newStatus.publicAddress != _networkStatus.publicAddress ||
        newStatus.activeConnections != _networkStatus.activeConnections ||
        newStatus.relayConnections != _networkStatus.relayConnections) {
      _networkStatus = newStatus;
      notifyListeners();
    }
  }

  void _updatePeerStates() {
    bool changed = false;

    for (final peerIdHex in _peerStates.keys.toList()) {
      final peerId = _hexToBytes(peerIdHex);
      final peerIdPtr = calloc<Uint8>(32);

      try {
        for (int i = 0; i < 32 && i < peerId.length; i++) {
          peerIdPtr[i] = peerId[i];
        }

        final state = _bindings.connGetState(peerIdPtr);
        final isRelayed = _bindings.connIsRelayed(peerIdPtr);
        final current = _peerStates[peerIdHex]!;

        if (current.state != state || current.isRelayed != isRelayed) {
          _peerStates[peerIdHex] = PeerConnectionState(
            peerId: peerIdHex,
            state: state,
            isRelayed: isRelayed,
            connectedAt: CyxChatConnState.isActive(state)
                ? (current.connectedAt ?? DateTime.now())
                : null,
          );
          changed = true;
        }
      } finally {
        calloc.free(peerIdPtr);
      }
    }

    if (changed) {
      notifyListeners();
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

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}
