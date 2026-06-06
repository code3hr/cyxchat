import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connection_provider.dart';
import 'dns_provider.dart';
import 'chat_provider.dart';
import 'call_provider.dart';
import 'contact_provider.dart';
import 'dht_provider.dart';
import 'file_provider.dart';
import 'group_ffi_provider.dart';
import 'queue_provider.dart';
import 'settings_provider.dart';
import '../services/identity_service.dart';
import '../services/chat_service.dart';
import '../services/group_service.dart';
import '../services/log_service.dart';
import '../services/network_monitor_service.dart';
import '../utils/node_id_utils.dart';
import '../ffi/bindings.dart';

/// Connection retry configuration
class RetryConfig {
  final Duration initialDelay;
  final Duration maxDelay;
  final int maxAttempts;
  final double backoffMultiplier;

  const RetryConfig({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxAttempts = 5,
    this.backoffMultiplier = 2.0,
  });
}

/// Connection retry state
class RetryState {
  final int attempt;
  final bool isRetrying;
  final Duration? nextRetryIn;
  final String? lastError;

  const RetryState({
    this.attempt = 0,
    this.isRetrying = false,
    this.nextRetryIn,
    this.lastError,
  });

  RetryState copyWith({
    int? attempt,
    bool? isRetrying,
    Duration? nextRetryIn,
    String? lastError,
  }) {
    return RetryState(
      attempt: attempt ?? this.attempt,
      isRetrying: isRetrying ?? this.isRetrying,
      nextRetryIn: nextRetryIn ?? this.nextRetryIn,
      lastError: lastError ?? this.lastError,
    );
  }
}

class _CallSignalFragmentBuffer {
  final int total;
  final DateTime createdAt;
  final List<List<int>?> chunks;

  _CallSignalFragmentBuffer(this.total)
      : createdAt = DateTime.now(),
        chunks = List<List<int>?>.filled(total, null);

  bool add(int index, List<int> data) {
    if (index < 0 || index >= total) return false;
    chunks[index] = List<int>.from(data);
    return true;
  }

  bool get isComplete => chunks.every((chunk) => chunk != null);

  List<int> assemble() {
    final out = <int>[];
    for (final chunk in chunks) {
      out.addAll(chunk!);
    }
    return out;
  }
}

/// Global connection provider instance
final connectionNotifierProvider =
    ChangeNotifierProvider<ConnectionProvider>((ref) {
  return ConnectionProvider();
});

/// Retry state provider
final retryStateProvider =
    StateProvider<RetryState>((ref) => const RetryState());

/// Provider for connection actions
final connectionActionsProvider = Provider((ref) => ConnectionActions(ref));

@visibleForTesting
String resolveBootstrapServer({
  String? override,
  required AppSettings settings,
}) {
  if (override != null && override.isNotEmpty) return override;
  if (settings.bootstrapServer.isNotEmpty) return settings.bootstrapServer;
  return SettingsDefaults.bootstrapServer;
}

/// Connection actions helper class
class ConnectionActions {
  final Ref _ref;
  Timer? _retryTimer;
  StreamSubscription? _callSignalSubscription;
  final Map<String, _CallSignalFragmentBuffer> _callSignalFragments = {};
  static const RetryConfig _defaultConfig = RetryConfig();
  static const int _callSignalFragmentMagic = 0xC7;
  static const int _callSignalFragmentVersion = 1;
  static const int _callSignalFragmentHeaderSize = 12;
  static const Duration _callSignalFragmentTtl = Duration(seconds: 60);
  final NetworkMonitorService _networkMonitor = NetworkMonitorService.instance;
  bool _autoReconnectEnabled = false;

  ConnectionActions(this._ref);

  RetryState get retryState => _ref.read(retryStateProvider);

  /// Connect with automatic retry on failure
  Future<bool> connectWithRetry({
    String? bootstrapServer,
    RetryConfig config = _defaultConfig,
  }) async {
    _cancelRetry();

    for (int attempt = 1; attempt <= config.maxAttempts; attempt++) {
      _ref.read(retryStateProvider.notifier).state = RetryState(
        attempt: attempt,
        isRetrying: attempt > 1,
      );

      debugPrint('Connection attempt $attempt/${config.maxAttempts}');

      final success = await connect(bootstrapServer: bootstrapServer);
      if (success) {
        _ref.read(retryStateProvider.notifier).state = const RetryState();
        return true;
      }

      // Don't retry on last attempt
      if (attempt >= config.maxAttempts) {
        _ref.read(retryStateProvider.notifier).state = RetryState(
          attempt: attempt,
          isRetrying: false,
          lastError: 'Connection failed after $attempt attempts',
        );
        return false;
      }

      // Calculate backoff delay with jitter
      final baseDelay = config.initialDelay.inMilliseconds *
          pow(config.backoffMultiplier, attempt - 1);
      final jitter = Random().nextDouble() * 0.3; // 0-30% jitter
      final delayMs = min(
        (baseDelay * (1 + jitter)).toInt(),
        config.maxDelay.inMilliseconds,
      );
      final delay = Duration(milliseconds: delayMs);

      debugPrint('Retrying in ${delay.inSeconds}s...');

      _ref.read(retryStateProvider.notifier).state = RetryState(
        attempt: attempt,
        isRetrying: true,
        nextRetryIn: delay,
        lastError: 'Connection failed, retrying...',
      );

      // Wait before next attempt
      await Future.delayed(delay);
    }

    return false;
  }

  /// Cancel any pending retry
  void _cancelRetry() {
    _retryTimer?.cancel();
    _retryTimer = null;
  }

  Future<bool> connect({String? bootstrapServer}) async {
    final log = LogService.instance;
    final connectionProvider = _ref.read(connectionNotifierProvider);
    final dnsProvider = _ref.read(dnsNotifierProvider);
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      log.error('Cannot connect: no identity loaded', source: 'Network');
      return false;
    }
    final settings = _ref.read(settingsProvider);
    final bootstrap = resolveBootstrapServer(
      override: bootstrapServer,
      settings: settings,
    );
    final nodeIdBytes = NodeIdUtils.toBytesAsList(identity.nodeId);

    log.info('Connecting to network...', source: 'Network');
    if (bootstrap.isNotEmpty) {
      log.info('Bootstrap server: $bootstrap', source: 'Network');
    } else {
      log.warning('No bootstrap server configured', source: 'Network');
    }

    // Initialize connection first
    final connResult = await connectionProvider.initialize(
      bootstrap: bootstrap,
      localId: nodeIdBytes,
    );

    if (!connResult) {
      log.error('Connection initialization failed', source: 'Network');
      return false;
    }
    log.info('Connection initialized - STUN discovery starting',
        source: 'Network');

    // Configure relay server (same as bootstrap) for NAT fallback
    if (bootstrap.isNotEmpty) {
      connectionProvider.addRelayServer(bootstrap);
      log.info('Relay server configured: $bootstrap', source: 'Network');
    }

    // Yield to let UI render before continuing initialization
    await Future.delayed(Duration.zero);

    // Initialize DNS with the same identity
    // Note: DNS will use node ID for identification without signing for now
    // Full signing key support can be added when identity includes Ed25519 keys
    final dnsResult = await dnsProvider.initialize(
      localId: nodeIdBytes,
      signingKey: null, // TODO: Add Ed25519 signing key to Identity
    );

    if (!dnsResult) {
      log.warning('DNS initialization failed (usernames unavailable)',
          source: 'Network');
      // Don't fail - DNS is optional for basic messaging
    } else {
      log.info('DNS initialized for username resolution', source: 'Network');
    }

    // Initialize Chat provider for P2P messaging
    final chatProvider = _ref.read(chatNotifierProvider);
    final chatResult = await chatProvider.initialize(localId: nodeIdBytes);

    if (!chatResult) {
      log.error('Chat initialization failed', source: 'Network');
      // Don't fail - chat can be retried
    } else {
      // Connect ChatService to ChatProvider for message handling
      ChatService.instance.connectProvider(chatProvider);
      log.info('Chat service ready for messaging', source: 'Network');

      // Wire call signaling to chat layer
      final callProvider = _ref.read(callNotifierProvider);
      callProvider.onSendSignal = (peerId, type, payload) {
        chatProvider.sendCallSignal(
          toPeerId: peerId,
          type: type,
          payload: payload,
        );
      };
      _callSignalSubscription?.cancel();
      _callSignalSubscription =
          chatProvider.callSignalStream.listen(_handleCallSignal);

      // Initialize offline message queue
      final queueProvider = _ref.read(queueNotifierProvider);
      await queueProvider.initialize();

      // Set up retry callback for queue
      queueProvider.setRetrySendCallback((messageId, recipientId, data) async {
        return await ChatService.instance.retrySendFromQueue(
          messageId,
          recipientId,
          data,
        );
      });

      // Notify queue that we're connected
      queueProvider.onConnected();
      log.info('Offline message queue ready', source: 'Network');
    }

    // Yield before group init (heaviest part)
    await Future.delayed(Duration.zero);

    // Initialize Group FFI provider for group chat (requires chat context)
    print('GroupFFI: Starting initialization...');
    final groupProvider = _ref.read(groupFFINotifierProvider);
    final groupResult = await groupProvider.initialize(localId: nodeIdBytes);
    print('GroupFFI: Initialize result = $groupResult');

    if (!groupResult) {
      print('GroupFFI: Initialization FAILED');
      log.warning('Group chat initialization failed', source: 'Network');
      // Don't fail - group chat is optional
    } else {
      // Connect GroupService to GroupFFIProvider for group message handling
      GroupService.instance.connectProvider(groupProvider);
      print('GroupFFI: GroupService connected');
      log.info('Group chat service ready', source: 'Network');
    }

    // Initialize DHT for decentralized peer discovery
    // DHT is created automatically with the connection, just initialize the provider
    final dhtProvider = _ref.read(dhtNotifierProvider);
    dhtProvider.initialize();

    if (dhtProvider.isReady) {
      log.info('DHT ready for peer discovery', source: 'Network');
    } else {
      log.info('DHT initialized (waiting for peers)', source: 'Network');
    }

    await Future.delayed(Duration.zero);

    // Initialize File provider for file transfers
    final fileProvider = _ref.read(fileNotifierProvider);
    final fileResult = await fileProvider.initialize();

    if (!fileResult) {
      log.warning('File transfer unavailable', source: 'Network');
      // Don't fail - file transfer is optional
    } else {
      log.info('File transfer ready', source: 'Network');
      // Wire up file receive callback to create messages
      fileProvider.onFileRequest = (request) {
        ChatService.instance.handleFileRequest(request);
      };
      fileProvider.onFileReceived = (fromPeerId, filename, fileSize, fileId) {
        ChatService.instance.handleReceivedFile(
          fromPeerId: fromPeerId,
          filename: filename,
          fileSize: fileSize,
          fileId: fileId,
          localPath: fileProvider.getStoredFilePath(fileId),
        );
      };
      fileProvider.onTransferComplete = (fileId) {
        ChatService.instance.handleFileTransferCompleted(
          fileId,
          localPath: fileProvider.getStoredFilePath(fileId),
        );
      };
      fileProvider.onTransferError = (fileId) {
        ChatService.instance.handleFileTransferFailed(fileId);
      };
      // Apply direct file transfer setting
      fileProvider.setDirectMode(settings.directFileTransfer);

      // Apply hop count setting
      chatProvider.setHopCount(settings.onionHopCount);

      // Wire up file context to connection for direct mode file routing
      // This allows direct P2P file messages to bypass onion and reach file module
      CyxChatBindings.instance.connSetFileCtx();

      // Set transport on file context for direct P2P transfers
      // This bypasses the router's is_direct_peer check for 32KB chunks
      final transport = CyxChatBindings.instance.connGetTransport();
      if (transport != null) {
        CyxChatBindings.instance.fileSetTransport(transport);
      }

      // Set connection context on file context for peer address exchange
      // This allows file module to get our public IP:port and add peer addresses
      CyxChatBindings.instance.fileSetConnCtx();
    }

    // Initialize presence sync if enabled
    if (settings.presenceSyncEnabled) {
      try {
        // Initialize presence sync provider (sets up callback)
        final presenceSync = _ref.read(presenceSyncProvider);
        log.info('Presence sync initialized', source: 'Network');

        // Wait for server to be ready before querying presence
        // Server verification takes ~3-5 seconds
        _queryPresenceWhenServerReady();
      } catch (e) {
        log.warning('Presence sync failed: $e', source: 'Network');
      }
    }

    log.info('Network connection complete', source: 'Network');

    // Start network monitoring for auto-reconnect
    _setupNetworkMonitor();

    return true;
  }

  void _handleCallSignal(ReceivedMessage msg) {
    final log = LogService.instance;
    final callProvider = _ref.read(callNotifierProvider);
    final payload = _decodeOrBufferCallSignal(msg, log);
    if (payload == null) return;

    Map<String, dynamic>? data;

    switch (msg.type) {
      case CyxChatMsgType.callOffer:
        data = _decodeCallPayload(payload, log, msg.type);
        if (data == null) return;
        final sdp = data['sdp'] as String?;
        final type = data['type'] as String?;
        final video = data['video'] == true;
        final peerName = data['peerName'] as String?;
        if (sdp == null || type == null) {
          log.warning('Call offer missing SDP/type', source: 'Call');
          return;
        }
        callProvider.handleOffer(
          peerId: msg.fromNodeId,
          peerName: peerName,
          sdp: sdp,
          type: type,
          video: video,
        );
        break;

      case CyxChatMsgType.callAnswer:
        data = _decodeCallPayload(payload, log, msg.type);
        if (data == null) return;
        final sdp = data['sdp'] as String?;
        final type = data['type'] as String?;
        if (sdp == null || type == null) {
          log.warning('Call answer missing SDP/type', source: 'Call');
          return;
        }
        callProvider.handleAnswer(
          peerId: msg.fromNodeId,
          sdp: sdp,
          type: type,
        );
        break;

      case CyxChatMsgType.callIce:
        data = _decodeCallPayload(payload, log, msg.type);
        if (data == null) return;
        final candidate = data['candidate'] as String?;
        final sdpMid = data['sdpMid'] as String?;
        final mLine = data['sdpMLineIndex'];
        final sdpMLineIndex =
            mLine is int ? mLine : (mLine is num ? mLine.toInt() : null);
        if (candidate == null || sdpMid == null || sdpMLineIndex == null) {
          log.warning('ICE signal missing fields', source: 'Call');
          return;
        }
        callProvider.handleIceCandidate(
          peerId: msg.fromNodeId,
          candidate: candidate,
          sdpMid: sdpMid,
          sdpMLineIndex: sdpMLineIndex,
        );
        break;

      case CyxChatMsgType.callEnd:
        callProvider.handleCallEnd(peerId: msg.fromNodeId);
        break;

      case CyxChatMsgType.callReject:
        callProvider.handleReject(peerId: msg.fromNodeId);
        break;

      case CyxChatMsgType.callBusy:
        callProvider.handleBusy(peerId: msg.fromNodeId);
        break;

      default:
        break;
    }
  }

  Map<String, dynamic>? _decodeCallPayload(
      String payload, LogService log, int type) {
    if (payload.isEmpty) {
      log.warning(
          'Call signal payload empty (type 0x${type.toRadixString(16)})',
          source: 'Call');
      return null;
    }
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      log.warning('Call signal payload not a JSON object', source: 'Call');
    } catch (e) {
      log.warning('Call signal JSON decode failed: $e', source: 'Call');
    }
    return null;
  }

  String? _decodeOrBufferCallSignal(ReceivedMessage msg, LogService log) {
    final raw = msg.rawData;
    if (raw.isEmpty || raw[0] != _callSignalFragmentMagic) {
      return raw.isNotEmpty ? utf8.decode(raw, allowMalformed: true) : '';
    }

    if (raw.length < _callSignalFragmentHeaderSize) {
      log.warning('Call signal fragment too short', source: 'Call');
      return null;
    }

    final version = raw[1];
    final index = raw[2];
    final total = raw[3];
    if (version != _callSignalFragmentVersion || total == 0 || index >= total) {
      log.warning('Invalid call signal fragment header', source: 'Call');
      return null;
    }

    _expireCallSignalFragments();

    final callId = _hex(raw.sublist(4, 12));
    final key = '${msg.fromNodeId}:${msg.type}:$callId';
    final buffer = _callSignalFragments.putIfAbsent(
      key,
      () => _CallSignalFragmentBuffer(total),
    );

    if (buffer.total != total) {
      log.warning('Call signal fragment total changed for $key',
          source: 'Call');
      _callSignalFragments.remove(key);
      return null;
    }

    buffer.add(index, raw.sublist(_callSignalFragmentHeaderSize));
    log.debug('Buffered call signal fragment ${index + 1}/$total',
        source: 'Call');

    if (!buffer.isComplete) return null;

    _callSignalFragments.remove(key);
    final assembled = buffer.assemble();
    return utf8.decode(assembled, allowMalformed: true);
  }

  void _expireCallSignalFragments() {
    final now = DateTime.now();
    _callSignalFragments.removeWhere(
      (_, buffer) => now.difference(buffer.createdAt) > _callSignalFragmentTtl,
    );
  }

  String _hex(List<int> bytes) {
    final buffer = StringBuffer();
    for (final byte in bytes) {
      buffer.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    return buffer.toString();
  }

  /// Query presence for all contacts once server is ready
  void _queryPresenceWhenServerReady() async {
    final log = LogService.instance;
    final connectionProvider = _ref.read(connectionNotifierProvider);

    // Wait up to 10 seconds for server to become available
    for (int i = 0; i < 20; i++) {
      await Future.delayed(const Duration(milliseconds: 500));

      // Check if we have at least one healthy/verified server
      final serverCount = connectionProvider.serverCount;
      final healthyCount = connectionProvider.healthyServerCount;

      if (healthyCount > 0) {
        log.info(
            'Server ready ($healthyCount/$serverCount healthy), querying presence',
            source: 'Network');
        await _ref.read(contactActionsProvider).queryAllPresence();
        log.info('Queried presence for all contacts', source: 'Network');
        return;
      }

      // Also check if server is at least responding (even if not fully verified)
      if (i == 10 && serverCount > 0) {
        log.warning('Server verification slow, querying presence anyway',
            source: 'Network');
        await _ref.read(contactActionsProvider).queryAllPresence();
        return;
      }
    }

    log.warning('No server available for presence queries after 10s',
        source: 'Network');
  }

  /// Setup network monitor for auto-reconnect on network restoration
  void _setupNetworkMonitor() {
    if (_autoReconnectEnabled) return;
    _autoReconnectEnabled = true;

    final log = LogService.instance;

    _networkMonitor.onNetworkRestored = () {
      final connectionProvider = _ref.read(connectionNotifierProvider);
      if (!connectionProvider.initialized) {
        log.info('Network restored - triggering reconnection',
            source: 'Network');
        // Use retry logic for robust reconnection
        connectWithRetry();
      } else if (!connectionProvider.networkStatus.bootstrapConnected) {
        log.info('Network restored - re-registering with bootstrap',
            source: 'Network');
        // Already initialized but lost bootstrap connection
        connectWithRetry();
      } else {
        log.debug('Network restored but already connected', source: 'Network');
      }
    };

    _networkMonitor.startMonitoring();
    log.info('Network monitor enabled for auto-reconnect', source: 'Network');
  }

  /// Stop network monitoring
  void _stopNetworkMonitor() {
    _networkMonitor.onNetworkRestored = null;
    _networkMonitor.stopMonitoring();
    _autoReconnectEnabled = false;
  }

  void disconnect() {
    // Stop network monitor
    _stopNetworkMonitor();

    // Notify queue we're disconnecting
    _ref.read(queueNotifierProvider).onDisconnected();

    // Cancel ACK timeout subscription
    _callSignalSubscription?.cancel();
    _callSignalSubscription = null;
    _callSignalFragments.clear();
    _ref.read(callNotifierProvider).onSendSignal = null;

    ChatService.instance.disconnectProvider();
    GroupService.instance.disconnectProvider();
    final fileProvider = _ref.read(fileNotifierProvider);
    fileProvider.onFileReceived = null; // Clear callback before shutdown
    fileProvider.onFileRequest = null;
    fileProvider.onTransferComplete = null;
    fileProvider.onTransferError = null;
    fileProvider.shutdown();
    _ref.read(groupFFINotifierProvider).shutdown();
    _ref.read(chatNotifierProvider).shutdown();
    _ref.read(dnsNotifierProvider).shutdown();
    _ref.read(connectionNotifierProvider).shutdown();
  }
}
