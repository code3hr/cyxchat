import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connection_provider.dart';
import 'dns_provider.dart';
import 'chat_provider.dart';
import 'dht_provider.dart';
import 'file_provider.dart';
import 'settings_provider.dart';
import '../services/identity_service.dart';
import '../services/chat_service.dart';
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

/// Global connection provider instance
final connectionNotifierProvider = ChangeNotifierProvider<ConnectionProvider>((ref) {
  return ConnectionProvider();
});

/// Retry state provider
final retryStateProvider = StateProvider<RetryState>((ref) => const RetryState());

/// Provider for connection actions
final connectionActionsProvider = Provider((ref) => ConnectionActions(ref));

/// Connection actions helper class
class ConnectionActions {
  final Ref _ref;
  Timer? _retryTimer;
  static const RetryConfig _defaultConfig = RetryConfig();

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
    final connectionProvider = _ref.read(connectionNotifierProvider);
    final dnsProvider = _ref.read(dnsNotifierProvider);
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      debugPrint('Cannot connect: no identity');
      return false;
    }
    final settings = _ref.read(settingsProvider);
    final bootstrap = bootstrapServer ?? (settings.bootstrapServer.isNotEmpty ? settings.bootstrapServer : '');
    final nodeIdBytes = NodeIdUtils.toBytesAsList(identity.nodeId);

    // Initialize connection first
    final connResult = await connectionProvider.initialize(
      bootstrap: bootstrap,
      localId: nodeIdBytes,
    );

    if (!connResult) {
      debugPrint('Connection initialization failed');
      return false;
    }

    // Initialize DNS with the same identity
    // Note: DNS will use node ID for identification without signing for now
    // Full signing key support can be added when identity includes Ed25519 keys
    final dnsResult = await dnsProvider.initialize(
      localId: nodeIdBytes,
      signingKey: null, // TODO: Add Ed25519 signing key to Identity
    );

    if (!dnsResult) {
      debugPrint('DNS initialization failed (continuing anyway)');
      // Don't fail - DNS is optional for basic messaging
    }

    // Initialize Chat provider for P2P messaging
    final chatProvider = _ref.read(chatNotifierProvider);
    final chatResult = await chatProvider.initialize(localId: nodeIdBytes);

    if (!chatResult) {
      debugPrint('Chat initialization failed (continuing anyway)');
      // Don't fail - chat can be retried
    } else {
      // Connect ChatService to ChatProvider for message handling
      ChatService.instance.connectProvider(chatProvider);
    }

    // Initialize DHT for decentralized peer discovery
    // DHT is created automatically with the connection, just initialize the provider
    final dhtProvider = _ref.read(dhtNotifierProvider);
    dhtProvider.initialize();

    if (dhtProvider.isReady) {
      debugPrint('DHT initialized and ready');
    } else {
      debugPrint('DHT initialized (no seed nodes yet)');
    }

    // Initialize File provider for file transfers
    final fileProvider = _ref.read(fileNotifierProvider);
    final fileResult = await fileProvider.initialize();

    if (!fileResult) {
      debugPrint('File provider initialization failed (continuing anyway)');
      // Don't fail - file transfer is optional
    } else {
      debugPrint('File provider initialized');
      // Wire up file receive callback to create messages
      fileProvider.onFileReceived = (fromPeerId, filename, fileSize, fileId) {
        ChatService.instance.handleReceivedFile(
          fromPeerId: fromPeerId,
          filename: filename,
          fileSize: fileSize,
          fileId: fileId,
        );
      };
      // Apply direct file transfer setting
      fileProvider.setDirectMode(settings.directFileTransfer);

      // Wire up file context to connection for direct mode file routing
      // This allows direct P2P file messages to bypass onion and reach file module
      CyxChatBindings.instance.connSetFileCtx();

      // Set transport on file context for direct P2P transfers
      // This bypasses the router's is_direct_peer check for 32KB chunks
      final transport = CyxChatBindings.instance.connGetTransport();
      if (transport != null) {
        CyxChatBindings.instance.fileSetTransport(transport);
        debugPrint('File transport set for direct P2P transfers');
      }
    }

    return true;
  }

  void disconnect() {
    ChatService.instance.disconnectProvider();
    final fileProvider = _ref.read(fileNotifierProvider);
    fileProvider.onFileReceived = null;  // Clear callback before shutdown
    fileProvider.shutdown();
    _ref.read(chatNotifierProvider).shutdown();
    _ref.read(dnsNotifierProvider).shutdown();
    _ref.read(connectionNotifierProvider).shutdown();
  }
}
