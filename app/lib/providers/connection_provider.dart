import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/identity_service.dart';
import '../services/log_service.dart';
import '../utils/node_id_utils.dart';
import '../models/connection_progress.dart';
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
  // UPnP/NAT-PMP status
  final bool upnpAvailable;
  final bool upnpMappingActive;
  final int upnpExternalPort;
  final int upnpLeaseRemainingSec;

  NetworkStatus({
    this.publicAddress,
    this.natType = CyxChatNatType.unknown,
    this.stunComplete = false,
    this.bootstrapConnected = false,
    this.activeConnections = 0,
    this.relayConnections = 0,
    this.upnpAvailable = false,
    this.upnpMappingActive = false,
    this.upnpExternalPort = 0,
    this.upnpLeaseRemainingSec = 0,
  });

  String get natTypeName => CyxChatNatType.name(natType);
  int get directConnections => activeConnections - relayConnections;

  String get upnpStatusText {
    if (upnpMappingActive) {
      final mins = upnpLeaseRemainingSec ~/ 60;
      return 'Port $upnpExternalPort mapped (${mins}min remaining)';
    } else if (upnpAvailable) {
      return 'Available but not mapped';
    }
    return 'Not available';
  }

  @override
  String toString() => 'NetworkStatus(addr: $publicAddress, nat: $natTypeName, '
      'active: $activeConnections, relay: $relayConnections, upnp: $upnpStatusText)';
}

/// Connection provider for managing P2P connections
class ConnectionProvider extends ChangeNotifier {
  final CyxChatBindings _bindings = CyxChatBindings.instance;

  // State
  bool _initialized = false;
  NetworkStatus _networkStatus = NetworkStatus();
  final Map<String, PeerConnectionState> _peerStates = {};

  // Progress tracking for real-time UI feedback
  final Map<String, PeerConnectionProgress> _progress = {};
  final _progressStream = StreamController<PeerConnectionProgress>.broadcast();

  // Polling timer
  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 500);

  // Getters
  bool get initialized => _initialized;
  NetworkStatus get networkStatus => _networkStatus;
  Map<String, PeerConnectionState> get peerStates => Map.unmodifiable(_peerStates);

  /// Stream of connection progress events for real-time UI updates
  Stream<PeerConnectionProgress> get progressStream => _progressStream.stream;

  /// Get current progress for a specific peer
  PeerConnectionProgress? getProgress(String peerIdHex) => _progress[peerIdHex];

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

      // Setup progress callback for real-time UI feedback
      _setupProgressCallback();

      // Start polling
      _startPolling();

      notifyListeners();
      return true;
    } finally {
      calloc.free(localIdPtr);
    }
  }

  /// Setup progress callback for real-time connection feedback
  void _setupProgressCallback() {
    _bindings.onConnProgress = _handleProgressEvent;
    _bindings.connSetupProgressCallback();
  }

  /// Handle progress events from C library
  void _handleProgressEvent(
    String peerId,
    int event,
    int retry,
    int maxRetry,
    int failReason,
  ) {
    // Guard against callbacks after provider is disposed
    if (!_initialized) return;

    final phase = PeerConnectionProgress.eventToPhase(event);
    final progress = PeerConnectionProgress(
      peerId: peerId,
      phase: phase,
      retryCount: retry,
      maxRetries: maxRetry,
      failReason: failReason != CyxChatConnFail.none
          ? CyxChatConnFail.message(failReason)
          : null,
    );

    _progress[peerId] = progress;

    // Wrap stream add in try-catch to handle closed stream gracefully
    try {
      _progressStream.add(progress);
    } on StateError {
      // Stream closed, ignore - this can happen during shutdown
      return;
    }

    notifyListeners();

    // Log significant events
    final log = LogService.instance;
    switch (event) {
      case CyxChatConnEvent.peerFound:
        log.info('Peer found: ${peerId.substring(0, 16)}...', source: 'Connection');
        break;
      case CyxChatConnEvent.keyReceived:
        log.info('Key exchange complete: ${peerId.substring(0, 16)}...', source: 'Connection');
        break;
      case CyxChatConnEvent.connectedP2p:
        log.info('Connected P2P: ${peerId.substring(0, 16)}...', source: 'Connection');
        break;
      case CyxChatConnEvent.connectedRelay:
        log.info('Connected via relay: ${peerId.substring(0, 16)}...', source: 'Connection');
        break;
      case CyxChatConnEvent.failed:
        log.warning('Connection failed: ${peerId.substring(0, 16)}... - ${CyxChatConnFail.message(failReason)}', source: 'Connection');
        break;
      case CyxChatConnEvent.disconnected:
        log.info('Disconnected: ${peerId.substring(0, 16)}...', source: 'Connection');
        break;
    }
  }

  /// Shutdown connection manager
  void shutdown() {
    _stopPolling();

    // CRITICAL: Disable callback BEFORE closing stream to prevent
    // race condition where callback fires after stream is closed
    _bindings.onConnProgress = null;
    _initialized = false;  // Guard against callbacks in flight

    // Now safe to close the stream
    _progressStream.close();

    _bindings.connDestroy();
    _peerStates.clear();
    _progress.clear();
    _networkStatus = NetworkStatus();
    notifyListeners();
  }

  /// Connect to a peer
  Future<int> connect(String peerIdHex) async {
    if (!_initialized) return CyxChatError.errNull;

    final peerId = NodeIdUtils.toBytesAsList(peerIdHex);
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

    final peerId = NodeIdUtils.toBytesAsList(peerIdHex);
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

  /// Check if we have established secure key with peer
  /// Key exchange must complete before messages can be sent
  bool hasPeerKey(String peerIdHex) {
    if (!_initialized) return false;

    final peerId = NodeIdUtils.toBytesAsList(peerIdHex);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerId.length; i++) {
        peerIdPtr[i] = peerId[i];
      }
      return _bindings.connHasPeerKey(peerIdPtr);
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Add relay server
  int addRelayServer(String address) {
    if (!_initialized) return CyxChatError.errNull;
    return _bindings.connAddRelay(address);
  }

  /// Force relay for a peer
  Future<int> forceRelay(String peerIdHex) async {
    if (!_initialized) return CyxChatError.errNull;

    final peerId = NodeIdUtils.toBytesAsList(peerIdHex);
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
    final log = LogService.instance;
    final publicAddr = _bindings.connGetPublicAddr();
    final bootstrapConnected = _bindings.connIsBootstrapConnected();

    // Get UPnP/NAT-PMP status
    final upnpAvailable = _bindings.connIsUpnpAvailable();
    final upnpMappingActive = _bindings.connIsUpnpMappingActive();
    final upnpExternalPort = _bindings.connGetUpnpExternalPort();
    final upnpLeaseRemainingSec = _bindings.connGetUpnpLeaseRemainingSec();

    final newStatus = NetworkStatus(
      publicAddress: publicAddr,
      stunComplete: publicAddr != null,
      bootstrapConnected: bootstrapConnected,
      activeConnections: _peerStates.values
          .where((p) => p.isConnected)
          .length,
      relayConnections: _peerStates.values
          .where((p) => p.isConnected && p.isRelayed)
          .length,
      upnpAvailable: upnpAvailable,
      upnpMappingActive: upnpMappingActive,
      upnpExternalPort: upnpExternalPort,
      upnpLeaseRemainingSec: upnpLeaseRemainingSec,
    );

    // Log significant changes
    if (newStatus.publicAddress != _networkStatus.publicAddress && newStatus.publicAddress != null) {
      log.info('Public address discovered: ${newStatus.publicAddress}', source: 'Network');
    }

    if (newStatus.activeConnections != _networkStatus.activeConnections) {
      final direct = newStatus.directConnections;
      final relay = newStatus.relayConnections;
      if (newStatus.activeConnections > 0) {
        log.info('Connected peers: ${newStatus.activeConnections} ($direct direct, $relay relay)', source: 'Network');
      }
    }

    if (newStatus.publicAddress != _networkStatus.publicAddress ||
        newStatus.activeConnections != _networkStatus.activeConnections ||
        newStatus.relayConnections != _networkStatus.relayConnections ||
        newStatus.bootstrapConnected != _networkStatus.bootstrapConnected) {
      _networkStatus = newStatus;
      notifyListeners();
    }
  }

  void _updatePeerStates() {
    bool changed = false;

    for (final peerIdHex in _peerStates.keys.toList()) {
      final peerId = NodeIdUtils.toBytesAsList(peerIdHex);
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

  /// Get all server info from registry
  List<Map<String, dynamic>> getServersInfo() {
    return _bindings.connGetServersInfo();
  }

  /// Get server counts
  int get serverCount => _bindings.connServerCount();
  int get healthyServerCount => _bindings.connHealthyServerCount();

  /// Add a server to the registry
  int addServer(String addr) => _bindings.connAddServer(addr);

  @override
  void dispose() {
    shutdown();
    super.dispose();
  }
}
