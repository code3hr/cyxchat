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

/// Global connection provider instance
final connectionNotifierProvider = ChangeNotifierProvider<ConnectionProvider>((ref) {
  return ConnectionProvider();
});

/// Provider for connection actions
final connectionActionsProvider = Provider((ref) => ConnectionActions(ref));

/// Connection actions helper class
class ConnectionActions {
  final Ref _ref;

  ConnectionActions(this._ref);

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
    final nodeIdBytes = _hexToBytes(identity.nodeId);

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

  List<int> _hexToBytes(String hex) {
    final result = <int>[];
    for (int i = 0; i < hex.length; i += 2) {
      if (i + 2 <= hex.length) {
        result.add(int.parse(hex.substring(i, i + 2), radix: 16));
      }
    }
    return result;
  }
}
