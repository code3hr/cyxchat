import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connection_provider.dart';
import 'dns_provider.dart';
import '../services/identity_service.dart';

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
    final bootstrap = bootstrapServer ?? 'stun.l.google.com:19302';
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

    return true;
  }

  void disconnect() {
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
