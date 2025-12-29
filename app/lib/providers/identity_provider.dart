import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/identity.dart';
import '../services/identity_service.dart';

/// Provider for current identity
final identityProvider = FutureProvider<Identity?>((ref) async {
  await IdentityService.instance.initialize();
  return IdentityService.instance.currentIdentity;
});

/// Provider for identity actions
final identityActionsProvider = Provider((ref) => IdentityActions(ref));

class IdentityActions {
  final Ref _ref;

  IdentityActions(this._ref);

  Future<Identity> createIdentity({String? displayName}) async {
    final identity = await IdentityService.instance.createIdentity(
      displayName: displayName,
    );
    _ref.invalidate(identityProvider);
    return identity;
  }

  Future<void> updateDisplayName(String? name) async {
    await IdentityService.instance.updateDisplayName(name);
    _ref.invalidate(identityProvider);
  }

  Future<void> deleteIdentity() async {
    await IdentityService.instance.deleteIdentity();
    _ref.invalidate(identityProvider);
  }

  String generateQrData() {
    return IdentityService.instance.generateQrData();
  }
}
