import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../models/connection_progress.dart';
import '../ffi/bindings.dart';
import '../services/database_service.dart';
import '../utils/node_id_utils.dart';
import 'conversation_provider.dart';
import 'network_provider.dart';

/// Provider for all contacts
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  return ContactService.instance.getContacts();
});

/// Provider for one contact by node ID
final contactProvider = FutureProvider.family<Contact?, String>((ref, nodeId) {
  return ContactService.instance.getContact(nodeId);
});

/// Provider for contact actions
final contactActionsProvider = Provider((ref) => ContactActions(ref));

/// Contact service for database operations
class ContactService {
  static final ContactService instance = ContactService._();

  ContactService._();

  /// Get all contacts
  Future<List<Contact>> getContacts() async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'contacts',
      orderBy: 'display_name ASC, node_id ASC',
    );
    return rows.map((row) => Contact.fromMap(row)).toList();
  }

  /// Get contact by node ID
  Future<Contact?> getContact(String nodeId) async {
    final db = await DatabaseService.instance.database;
    final rows = await db.query(
      'contacts',
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
    if (rows.isEmpty) return null;
    return Contact.fromMap(rows.first);
  }

  /// Add a new contact by node ID
  Future<Contact> addContact({
    required String nodeId,
    String? displayName,
    Uint8List? publicKey,
  }) async {
    final db = await DatabaseService.instance.database;

    // Check if already exists
    final existing = await getContact(nodeId);
    if (existing != null) {
      return existing;
    }

    // Create contact with placeholder public key if not provided
    // In real usage, public key would come from key exchange
    final contact = Contact(
      nodeId: nodeId,
      publicKey: publicKey ?? Uint8List(32), // Placeholder
      displayName: displayName,
      addedAt: DateTime.now(),
    );

    await db.insert('contacts', contact.toMap());
    return contact;
  }

  /// Update contact display name
  Future<void> updateDisplayName(String nodeId, String? displayName) async {
    final db = await DatabaseService.instance.database;
    await db.update(
      'contacts',
      {'display_name': displayName},
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );

    // Also update any existing conversation with this peer
    await db.update(
      'conversations',
      {'display_name': displayName},
      where: 'peer_id = ?',
      whereArgs: [nodeId],
    );
  }

  /// Persist a peer public key learned during native key exchange.
  Future<bool> updatePublicKey(String nodeId, List<int> publicKey) async {
    if (publicKey.length != 32 || _isAllZero(publicKey)) return false;

    final db = await DatabaseService.instance.database;
    final keyBytes = Uint8List.fromList(publicKey);
    final candidates = <String>{
      nodeId,
      nodeId.replaceAll('-', '').toLowerCase(),
      NodeIdUtils.toDisplayFormat(nodeId),
    };

    var updated = 0;
    for (final candidate in candidates) {
      updated += await db.update(
        'contacts',
        {'public_key': keyBytes},
        where: 'node_id = ?',
        whereArgs: [candidate],
      );
    }

    return updated > 0;
  }

  bool _isAllZero(List<int> bytes) {
    for (final byte in bytes) {
      if (byte != 0) return false;
    }
    return true;
  }

  /// Toggle contact verified status
  Future<void> toggleVerified(String nodeId) async {
    final db = await DatabaseService.instance.database;
    final contact = await getContact(nodeId);
    if (contact == null) return;

    await db.update(
      'contacts',
      {'verified': contact.verified ? 0 : 1},
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
  }

  /// Toggle contact blocked status
  Future<void> toggleBlocked(String nodeId) async {
    final db = await DatabaseService.instance.database;
    final contact = await getContact(nodeId);
    if (contact == null) return;

    await db.update(
      'contacts',
      {'blocked': contact.blocked ? 0 : 1},
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
  }

  /// Delete contact
  Future<void> deleteContact(String nodeId) async {
    final db = await DatabaseService.instance.database;
    await db.delete(
      'contacts',
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
  }

  /// Update contact presence
  Future<void> updatePresence(
    String nodeId,
    PresenceStatus presence, {
    String? statusText,
  }) async {
    final db = await DatabaseService.instance.database;
    final values = {
      'presence': presence.index,
      'last_seen': DateTime.now().millisecondsSinceEpoch,
      if (statusText != null) 'status_text': statusText,
    };

    final updated = await db.update(
      'contacts',
      values,
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );

    if (updated == 0) {
      final displayId = NodeIdUtils.toDisplayFormat(nodeId);
      if (displayId != nodeId) {
        await db.update(
          'contacts',
          values,
          where: 'node_id = ?',
          whereArgs: [displayId],
        );
      }
    }
  }
}

/// Contact actions helper class
class ContactActions {
  final Ref _ref;

  ContactActions(this._ref);

  /// Add a new contact by node ID
  Future<Contact> addContact({
    required String nodeId,
    String? displayName,
  }) async {
    final contact = await ContactService.instance.addContact(
      nodeId: nodeId,
      displayName: displayName,
    );
    _ref.invalidate(contactsProvider);
    return contact;
  }

  /// Update contact display name
  Future<void> updateDisplayName(String nodeId, String? displayName) async {
    await ContactService.instance.updateDisplayName(nodeId, displayName);
    _ref.invalidate(contactsProvider);
    _ref.invalidate(
        conversationsProvider); // Refresh conversations with new name
  }

  /// Toggle verified status
  Future<void> toggleVerified(String nodeId) async {
    await ContactService.instance.toggleVerified(nodeId);
    _ref.invalidate(contactsProvider);
  }

  /// Toggle blocked status
  Future<void> toggleBlocked(String nodeId) async {
    await ContactService.instance.toggleBlocked(nodeId);
    _ref.invalidate(contactsProvider);
  }

  /// Delete contact
  Future<void> deleteContact(String nodeId) async {
    await ContactService.instance.deleteContact(nodeId);
    _ref.invalidate(contactsProvider);
  }

  /// Update contact presence
  Future<void> updatePresence(
    String nodeId,
    PresenceStatus presence, {
    String? statusText,
  }) async {
    await ContactService.instance.updatePresence(
      nodeId,
      presence,
      statusText: statusText,
    );
    _ref.invalidate(contactsProvider);
    _ref.invalidate(contactProvider(nodeId));
  }

  /// Query presence for a single contact
  void queryPresence(String nodeId) {
    final connProvider = _ref.read(connectionNotifierProvider);
    connProvider.queryPresence(nodeId);
    debugPrint(
        'ContactActions: Querying presence for ${nodeId.substring(0, 16)}...');
  }

  /// Query presence for all contacts
  Future<void> queryAllPresence() async {
    final contacts = await ContactService.instance.getContacts();
    final connProvider = _ref.read(connectionNotifierProvider);

    debugPrint(
        'ContactActions: Querying presence for ${contacts.length} contacts');
    for (final contact in contacts) {
      connProvider.queryPresence(contact.nodeId);
      // Small delay to avoid flooding the server
      await Future.delayed(const Duration(milliseconds: 50));
    }
  }
}

/// Provider for presence sync - listens to connection provider for presence updates
final presenceSyncProvider = Provider<PresenceSync>((ref) {
  final sync = PresenceSync(ref);
  ref.onDispose(() => sync.dispose());
  return sync;
});

/// Provider for restoring and persisting peer public keys for known contacts.
final contactKeySyncProvider = Provider<ContactKeySync>((ref) {
  final sync = ContactKeySync(ref);
  ref.onDispose(() => sync.dispose());
  return sync;
});

class ContactKeySync {
  final Ref _ref;
  StreamSubscription? _subscription;

  ContactKeySync(this._ref) {
    final connProvider = _ref.read(connectionNotifierProvider);
    _subscription = connProvider.progressStream.listen(_handleProgress);
  }

  Future<void> restoreKnownPeerKeys({List<Contact>? contacts}) async {
    final connProvider = _ref.read(connectionNotifierProvider);
    if (!connProvider.initialized) return;

    final targetContacts =
        contacts ?? await ContactService.instance.getContacts();
    var restored = 0;
    for (final contact in targetContacts) {
      if (contact.blocked || _isAllZero(contact.publicKey)) continue;
      final result = connProvider.restorePeerPublicKey(
        contact.nodeId,
        contact.publicKey,
      );
      if (result == CyxChatError.ok) {
        restored++;
      }
    }
    if (restored > 0) {
      debugPrint('ContactKeySync: Restored $restored peer keys');
    }
  }

  Future<void> _handleProgress(PeerConnectionProgress progress) async {
    if (progress.phase != ConnectionPhase.keyExchanged) return;

    final connProvider = _ref.read(connectionNotifierProvider);
    final pubkey = connProvider.getPeerPublicKey(progress.peerId);
    if (pubkey == null) return;

    final updated = await ContactService.instance.updatePublicKey(
      progress.peerId,
      pubkey,
    );
    if (updated) {
      _ref.invalidate(contactsProvider);
      _ref.invalidate(contactProvider(progress.peerId));
      final displayId = NodeIdUtils.toDisplayFormat(progress.peerId);
      if (displayId != progress.peerId) {
        _ref.invalidate(contactProvider(displayId));
      }
      debugPrint(
          'ContactKeySync: Saved peer key for ${progress.peerId.substring(0, 16)}...');
    }
  }

  bool _isAllZero(List<int> bytes) {
    for (final byte in bytes) {
      if (byte != 0) return false;
    }
    return true;
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
  }
}

/// Presence synchronization handler
class PresenceSync {
  final Ref _ref;
  StreamSubscription? _subscription;
  Timer? _refreshTimer;
  bool _enabled = true;
  final Map<String, DateTime> _lastWarmConnectAttempt = {};

  /// Refresh interval for periodic presence queries (30 seconds)
  static const Duration _refreshInterval = Duration(seconds: 30);
  static const Duration _warmConnectCooldown = Duration(minutes: 2);

  PresenceSync(this._ref) {
    _setupListener();
    _startPeriodicRefresh();
    unawaited(warmOnlineContacts());
  }

  void _setupListener() {
    final connProvider = _ref.read(connectionNotifierProvider);
    _subscription = connProvider.presenceStream.listen(_handlePresenceUpdate);
    debugPrint('PresenceSync: Listening for presence updates');
  }

  void _startPeriodicRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_refreshInterval, (_) {
      if (_enabled) {
        _queryAllPresence();
      }
    });
    debugPrint(
        'PresenceSync: Started periodic refresh (every ${_refreshInterval.inSeconds}s)');
  }

  Future<void> _queryAllPresence() async {
    try {
      final contacts = await ContactService.instance.getContacts();
      if (contacts.isEmpty) return;

      final connProvider = _ref.read(connectionNotifierProvider);
      debugPrint(
          'PresenceSync: Refreshing presence for ${contacts.length} contacts');

      for (final contact in contacts) {
        connProvider.queryPresence(contact.nodeId);
        // Small delay to avoid flooding the server
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await warmOnlineContacts(contacts: contacts);
    } catch (e) {
      debugPrint('PresenceSync: Error querying presence: $e');
    }
  }

  void _handlePresenceUpdate(MapEntry<String, bool> update) async {
    if (!_enabled) return;

    final peerId = update.key;
    final online = update.value;

    debugPrint(
        'PresenceSync: Received presence for ${peerId.substring(0, 16)}... online=$online');

    // Update contact in database
    final presence = online ? PresenceStatus.online : PresenceStatus.offline;
    await ContactService.instance.updatePresence(peerId, presence);

    // Invalidate provider to refresh UI
    _ref.invalidate(contactsProvider);
    _ref.invalidate(contactProvider(peerId));
    final displayId = NodeIdUtils.toDisplayFormat(peerId);
    if (displayId != peerId) {
      _ref.invalidate(contactProvider(displayId));
    }

    if (online) {
      unawaited(_warmConnect(peerId));
    }
  }

  Future<void> _warmConnect(String peerId) async {
    final connProvider = _ref.read(connectionNotifierProvider);
    if (!connProvider.isOnline) return;
    if (connProvider.hasPeerKey(peerId) && connProvider.isConnected(peerId)) {
      return;
    }

    final progress = connProvider.getProgress(peerId);
    if (progress != null && progress.isConnecting) return;

    final now = DateTime.now();
    final lastAttempt = _lastWarmConnectAttempt[peerId];
    if (lastAttempt != null &&
        now.difference(lastAttempt) < _warmConnectCooldown) {
      return;
    }

    _lastWarmConnectAttempt[peerId] = now;
    final result = await connProvider.connect(peerId);
    debugPrint(
        'PresenceSync: Warm connect to ${peerId.substring(0, 16)}... result=$result');
  }

  Future<void> warmOnlineContacts({List<Contact>? contacts}) async {
    final connProvider = _ref.read(connectionNotifierProvider);
    if (!connProvider.isOnline) return;

    final targetContacts =
        contacts ?? await ContactService.instance.getContacts();
    final onlineContacts = targetContacts.where(
      (contact) => contact.isOnline && !contact.blocked,
    );

    for (final contact in onlineContacts) {
      await _warmConnect(contact.nodeId);
      await Future.delayed(const Duration(milliseconds: 100));
    }
  }

  /// Enable or disable presence sync
  set enabled(bool value) {
    _enabled = value;
    debugPrint('PresenceSync: enabled=$value');
    if (value) {
      _startPeriodicRefresh();
    } else {
      _refreshTimer?.cancel();
      _refreshTimer = null;
    }
  }

  bool get enabled => _enabled;

  /// Manually trigger a presence refresh
  Future<void> refresh() async {
    if (_enabled) {
      await _queryAllPresence();
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
  }
}
