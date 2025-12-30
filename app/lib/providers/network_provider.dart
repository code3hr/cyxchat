import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'connection_provider.dart';
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
    final provider = _ref.read(connectionNotifierProvider);
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) {
      debugPrint('Cannot connect: no identity');
      return false;
    }
    final bootstrap = bootstrapServer ?? 'stun.l.google.com:19302';
    final nodeIdBytes = _hexToBytes(identity.nodeId);
    return await provider.initialize(bootstrap: bootstrap, localId: nodeIdBytes);
  }

  void disconnect() {
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
