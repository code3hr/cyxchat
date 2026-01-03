import 'dart:typed_data';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../services/database_service.dart';

/// Provider for all contacts
final contactsProvider = FutureProvider<List<Contact>>((ref) async {
  return ContactService.instance.getContacts();
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
    await db.update(
      'contacts',
      {
        'presence': presence.index,
        'last_seen': DateTime.now().millisecondsSinceEpoch,
        if (statusText != null) 'status_text': statusText,
      },
      where: 'node_id = ?',
      whereArgs: [nodeId],
    );
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
  }
}
