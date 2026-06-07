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
  String toString() =>
      'PeerConnectionState($peerId: $stateName, relayed: $isRelayed)';
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
  int get directConnections => activeConnections > relayConnections
      ? activeConnections - relayConnections
      : 0;

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
  String? _bootstrapServer;
  NetworkStatus _networkStatus = NetworkStatus();
  final Map<String, PeerConnectionState> _peerStates = {};

  // Progress tracking for real-time UI feedback
  final Map<String, PeerConnectionProgress> _progress = {};
  final _progressStream = StreamController<PeerConnectionProgress>.broadcast();

  // Presence tracking
  final Map<String, bool> _onlineStatus = {};
  final _presenceStream = StreamController<MapEntry<String, bool>>.broadcast();

  // Polling timer
  Timer? _pollTimer;
  static const _pollInterval = Duration(milliseconds: 500);

  // Getters
  bool get initialized => _initialized;
  String? get bootstrapServer => _bootstrapServer;
  bool get isOnline => _initialized;
  bool get isConnectingToBootstrap =>
      _initialized && !_networkStatus.bootstrapConnected;
  NetworkStatus get networkStatus => _networkStatus;
  Map<String, PeerConnectionState> get peerStates =>
      Map.unmodifiable(_peerStates);

  /// Stream of connection progress events for real-time UI updates
  Stream<PeerConnectionProgress> get progressStream => _progressStream.stream;

  /// Get current progress for a specific peer
  /// Normalizes peer ID by removing dashes and padding to 64 chars
  /// to match the 32-byte node ID format used by the C callback
  PeerConnectionProgress? getProgress(String peerIdHex) {
    var normalized = peerIdHex.replaceAll('-', '').toLowerCase();
    // Pad UUID-style IDs (32 hex chars) to full node ID length (64 hex chars)
    if (normalized.length < 64) {
      normalized = normalized.padRight(64, '0');
    }
    return _progress[normalized];
  }

  /// Stream of presence updates (peer ID, online status)
  Stream<MapEntry<String, bool>> get presenceStream => _presenceStream.stream;

  /// Get online status for a peer
  bool? getOnlineStatus(String peerIdHex) {
    final normalized = peerIdHex.replaceAll('-', '').toLowerCase();
    return _onlineStatus[normalized];
  }

  /// Initialize connection manager
  Future<bool> initialize({
    required String bootstrap,
    required List<int> localId,
  }) async {
    if (_initialized) {
      if (_bootstrapServer == bootstrap) return true;
      debugPrint(
        'ConnectionProvider: bootstrap changed from $_bootstrapServer to $bootstrap, recreating connection',
      );
      shutdown();
    }

    // Convert local ID to native pointer
    final localIdPtr = calloc<Uint8>(32);
    for (int i = 0; i < 32 && i < localId.length; i++) {
      localIdPtr[i] = localId[i];
    }

    try {
      final result = _bindings.connCreate(bootstrap, localIdPtr);
      if (result != CyxChatError.ok) {
        debugPrint(
            'Failed to create connection: ${_bindings.errorString(result)}');
        return false;
      }

      _initialized = true;
      _bootstrapServer = bootstrap;

      // Setup progress callback for real-time UI feedback
      _setupProgressCallback();

      // Setup presence callback for online status
      _setupPresenceCallback();

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

  /// Setup presence callback for online status updates
  void _setupPresenceCallback() {
    _bindings.onPresence = _handlePresenceEvent;
    _bindings.connSetupPresenceCallback();
  }

  /// Handle presence events from C library
  void _handlePresenceEvent(String peerId, bool online) {
    debugPrint(
        'PRESENCE-CALLBACK: peer=${peerId.substring(0, 16)}... online=$online');

    // Guard against callbacks after provider is disposed
    if (!_initialized) return;

    // Normalize peer ID
    final normalizedId = peerId.replaceAll('-', '').toLowerCase();
    _onlineStatus[normalizedId] = online;

    // Notify listeners via stream
    try {
      _presenceStream.add(MapEntry(normalizedId, online));
    } on StateError {
      // Stream closed, ignore
      return;
    }

    notifyListeners();
  }

  /// Query presence for a specific peer from server
  int queryPresence(String peerIdHex) {
    if (!_initialized) return CyxChatError.errNull;

    final peerId = NodeIdUtils.toBytesAsList(peerIdHex);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerId.length; i++) {
        peerIdPtr[i] = peerId[i];
      }
      return _bindings.connQueryPresence(peerIdPtr);
    } finally {
      calloc.free(peerIdPtr);
    }
  }

  /// Handle progress events from C library
  void _handleProgressEvent(
    String peerId,
    int event,
    int retry,
    int maxRetry,
    int failReason,
  ) {
    // Debug: confirm callback is firing
    debugPrint('CONN-CALLBACK: event=$event for ${peerId.substring(0, 16)}...');

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

    // Normalize peer ID to ensure consistent key format
    // Pad to 64 chars to match the lookup normalization
    var normalizedId = peerId.replaceAll('-', '').toLowerCase();
    if (normalizedId.length < 64) {
      normalizedId = normalizedId.padRight(64, '0');
    }
    _progress[normalizedId] = progress;

    // Wrap stream add in try-catch to handle closed stream gracefully
    try {
      _progressStream.add(progress);
    } on StateError {
      // Stream closed, ignore - this can happen during shutdown
      return;
    }

    // Defer to microtask to avoid setState during build if callback fires
    // during widget tree construction. Microtask triggers markNeedsBuild
    // which schedules a new frame (unlike addPostFrameCallback which waits).
    Future.microtask(() => notifyListeners());

    // Log significant events with detailed path info
    final log = LogService.instance;
    final shortId = peerId.length > 16 ? peerId.substring(0, 16) : peerId;
    switch (event) {
      case CyxChatConnEvent.peerFound:
        log.info('CONN: Peer discovered $shortId...', source: 'Connection');
        break;
      case CyxChatConnEvent.announceSent:
        log.info(
            'CONN: ANNOUNCE sent to $shortId... (key exchange attempt ${retry + 1}/$maxRetry)',
            source: 'Connection');
        break;
      case CyxChatConnEvent.announceRetry:
        log.warning(
            'CONN: ANNOUNCE retry $retry/$maxRetry to $shortId... (waiting for key)',
            source: 'Connection');
        break;
      case CyxChatConnEvent.keyReceived:
        log.info(
            'CONN: KEY RECEIVED from $shortId... - can now send encrypted messages',
            source: 'Connection');
        break;
      case CyxChatConnEvent.holePunchStart:
        log.info(
            'CONN: HOLE PUNCH starting to $shortId... (attempting direct P2P)',
            source: 'Connection');
        break;
      case CyxChatConnEvent.connectedP2p:
        log.info('CONN: ✓ DIRECT P2P to $shortId... - hole punch succeeded!',
            source: 'Connection');
        break;
      case CyxChatConnEvent.relayFallback:
        log.warning(
            'CONN: RELAY FALLBACK for $shortId... - hole punch failed, using relay',
            source: 'Connection');
        break;
      case CyxChatConnEvent.connectedRelay:
        log.info(
            'CONN: ✓ VIA RELAY to $shortId... - messages will go through bootstrap server',
            source: 'Connection');
        break;
      case CyxChatConnEvent.failed:
        log.error(
            'CONN: FAILED to $shortId... - ${CyxChatConnFail.message(failReason)}',
            source: 'Connection');
        break;
      case CyxChatConnEvent.disconnected:
        log.info('CONN: DISCONNECTED from $shortId...', source: 'Connection');
        break;
      default:
        log.debug('CONN: Event $event for $shortId... (retry $retry/$maxRetry)',
            source: 'Connection');
    }
  }

  /// Shutdown connection manager
  void shutdown() {
    if (!_initialized) return;

    _stopPolling();

    // CRITICAL: Disable callbacks BEFORE closing streams to prevent
    // race condition where callback fires after stream is closed
    _bindings.onConnProgress = null;
    _bindings.onPresence = null;
    _initialized = false; // Guard against callbacks in flight

    _bindings.connDestroy();
    _peerStates.clear();
    _progress.clear();
    _onlineStatus.clear();
    _networkStatus = NetworkStatus();
    _bootstrapServer = null;
    notifyListeners();
  }

  /// Connect to a peer
  Future<int> connect(String peerIdHex) async {
    if (!_initialized) return CyxChatError.errNull;

    if (hasPeerKey(peerIdHex) && isConnected(peerIdHex)) {
      return CyxChatError.ok;
    }

    final progress = getProgress(peerIdHex);
    if (progress != null && progress.isConnecting) return CyxChatError.ok;

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
    if (!_initialized) return false;

    final peerId = NodeIdUtils.toBytesAsList(peerIdHex);
    final peerIdPtr = calloc<Uint8>(32);

    try {
      for (int i = 0; i < 32 && i < peerId.length; i++) {
        peerIdPtr[i] = peerId[i];
      }
      return _bindings.connIsRelayed(peerIdPtr);
    } finally {
      calloc.free(peerIdPtr);
    }
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

  /// Return the peer key learned by native key exchange, if available.
  List<int>? getPeerPublicKey(String peerIdHex) {
    if (!_initialized) return null;
    final pubkey = _bindings.connGetPeerPubkeyHex(peerIdHex);
    if (pubkey == null || pubkey.length != 32 || _isAllZero(pubkey)) {
      return null;
    }
    return pubkey;
  }

  /// Restore a previously learned peer key into the native onion context.
  int restorePeerPublicKey(String peerIdHex, List<int> pubkey) {
    if (!_initialized) return CyxChatError.errNull;
    if (pubkey.length != 32 || _isAllZero(pubkey)) {
      return CyxChatError.errInvalid;
    }
    return _bindings.connAddPeerPubkeyHex(peerIdHex, pubkey);
  }

  bool _isAllZero(List<int> bytes) {
    for (final byte in bytes) {
      if (byte != 0) return false;
    }
    return true;
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
      activeConnections: _peerStates.values.where((p) => p.isConnected).length,
      relayConnections:
          _peerStates.values.where((p) => p.isConnected && p.isRelayed).length,
      upnpAvailable: upnpAvailable,
      upnpMappingActive: upnpMappingActive,
      upnpExternalPort: upnpExternalPort,
      upnpLeaseRemainingSec: upnpLeaseRemainingSec,
    );

    // Log significant changes
    if (newStatus.publicAddress != _networkStatus.publicAddress &&
        newStatus.publicAddress != null) {
      log.info('Public address discovered: ${newStatus.publicAddress}',
          source: 'Network');
    }

    if (newStatus.activeConnections != _networkStatus.activeConnections) {
      final direct = newStatus.directConnections;
      final relay = newStatus.relayConnections;
      if (newStatus.activeConnections > 0) {
        log.info(
            'Connected peers: ${newStatus.activeConnections} ($direct direct, $relay relay)',
            source: 'Network');
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
    _progressStream.close();
    _presenceStream.close();
    super.dispose();
  }
}
