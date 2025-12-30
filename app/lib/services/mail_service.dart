import 'dart:convert';
import '../ffi/bindings.dart';
import '../models/email_folder.dart';
import '../models/email_message.dart';
import '../models/email_attachment.dart';
import '../providers/mail_provider.dart';
import 'database_service.dart';

/// Service for email/mail operations
class MailService {
  static final MailService instance = MailService._();
  final _db = DatabaseService.instance;
  final _bindings = CyxChatBindings.instance;

  MailService._();

  // ============================================================
  // Folders
  // ============================================================

  /// Get all folders
  Future<List<EmailFolder>> getFolders() async {
    final db = await _db.database;
    final results = await db.query(
      'email_folders',
      orderBy: 'folder_type ASC, name ASC',
    );
    return results.map((r) => EmailFolder.fromMap(r)).toList();
  }

  /// Get folder by ID
  Future<EmailFolder?> getFolder(int folderId) async {
    final db = await _db.database;
    final results = await db.query(
      'email_folders',
      where: 'id = ?',
      whereArgs: [folderId],
    );
    if (results.isEmpty) return null;
    return EmailFolder.fromMap(results.first);
  }

  /// Get folder by type
  Future<EmailFolder?> getFolderByType(EmailFolderType type) async {
    final db = await _db.database;
    final results = await db.query(
      'email_folders',
      where: 'folder_type = ?',
      whereArgs: [type.index],
    );
    if (results.isEmpty) return null;
    return EmailFolder.fromMap(results.first);
  }

  /// Update folder counts
  Future<void> _updateFolderCounts(int folderId) async {
    final db = await _db.database;
    await db.rawUpdate('''
      UPDATE email_folders
      SET
        total_count = (SELECT COUNT(*) FROM email_messages WHERE folder_id = ?),
        unread_count = (SELECT COUNT(*) FROM email_messages WHERE folder_id = ? AND (flags & 1) = 0),
        updated_at = ?
      WHERE id = ?
    ''', [folderId, folderId, DateTime.now().millisecondsSinceEpoch, folderId]);
  }

  // ============================================================
  // Messages
  // ============================================================

  /// Get messages in folder
  Future<List<EmailMessage>> getMessages(
    int folderId, {
    int offset = 0,
    int limit = 50,
  }) async {
    final db = await _db.database;
    final results = await db.query(
      'email_messages',
      where: 'folder_id = ?',
      whereArgs: [folderId],
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((r) => EmailMessage.fromMap(r)).toList();
  }

  /// Get message by mail ID
  Future<EmailMessage?> getMessage(String mailId) async {
    final db = await _db.database;
    final results = await db.query(
      'email_messages',
      where: 'mail_id = ?',
      whereArgs: [mailId],
    );
    if (results.isEmpty) return null;

    final message = EmailMessage.fromMap(results.first);

    // Load attachments
    final attachments = await getAttachments(mailId);
    return message.copyWith(attachments: attachments);
  }

  /// Get messages in thread
  Future<List<EmailMessage>> getThread(String threadId) async {
    final db = await _db.database;
    final results = await db.query(
      'email_messages',
      where: 'thread_id = ? OR mail_id = ?',
      whereArgs: [threadId, threadId],
      orderBy: 'timestamp ASC',
    );
    return results.map((r) => EmailMessage.fromMap(r)).toList();
  }

  /// Search messages
  Future<List<EmailMessage>> search(String query) async {
    final db = await _db.database;
    final results = await db.query(
      'email_messages',
      where: 'subject LIKE ? OR body LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'timestamp DESC',
      limit: 100,
    );
    return results.map((r) => EmailMessage.fromMap(r)).toList();
  }

  /// Get unread count for folder
  Future<int> getUnreadCount(int folderId) async {
    final db = await _db.database;
    final result = await db.rawQuery(
      'SELECT COUNT(*) as count FROM email_messages WHERE folder_id = ? AND (flags & 1) = 0',
      [folderId],
    );
    return result.first['count'] as int? ?? 0;
  }

  /// Get total unread count
  Future<int> getTotalUnreadCount() async {
    final db = await _db.database;
    // Exclude trash and spam from total
    final result = await db.rawQuery('''
      SELECT COUNT(*) as count
      FROM email_messages em
      INNER JOIN email_folders ef ON em.folder_id = ef.id
      WHERE (em.flags & 1) = 0
        AND ef.folder_type NOT IN (4, 5)
    ''');
    return result.first['count'] as int? ?? 0;
  }

  // ============================================================
  // Attachments
  // ============================================================

  /// Get attachments for message
  Future<List<EmailAttachment>> getAttachments(String mailId) async {
    final db = await _db.database;
    final results = await db.query(
      'email_attachments',
      where: 'mail_id = ?',
      whereArgs: [mailId],
    );
    return results.map((r) => EmailAttachment.fromMap(r)).toList();
  }

  // ============================================================
  // Send / Save
  // ============================================================

  /// Send email
  Future<EmailMessage> sendEmail({
    required String toNodeId,
    String? toName,
    required String subject,
    required String body,
    String? inReplyTo,
    List<EmailAttachmentData>? attachments,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final mailId = _generateMailId();

    // Get sent folder
    final sentFolder = await getFolderByType(EmailFolderType.sent);
    if (sentFolder == null) throw Exception('Sent folder not found');

    // Determine thread ID
    String? threadId;
    if (inReplyTo != null) {
      final originalMsg = await getMessage(inReplyTo);
      threadId = originalMsg?.threadId ?? inReplyTo;
    }

    // Create message
    final message = EmailMessage(
      mailId: mailId,
      folderId: sentFolder.id,
      folderType: EmailFolderType.sent,
      from: EmailAddress(nodeId: 'local'), // TODO: Get local node ID
      to: [EmailAddress(nodeId: toNodeId, displayName: toName)],
      subject: subject,
      body: body,
      timestamp: now,
      inReplyTo: inReplyTo,
      threadId: threadId ?? mailId,
      flags: EmailFlags.seen, // Sent messages are read
      status: EmailStatus.sent,
      signatureValid: true,
      createdAt: now,
    );

    // Insert into database
    await db.insert('email_messages', message.toMap());

    // Handle attachments
    if (attachments != null) {
      for (final attach in attachments) {
        await db.insert('email_attachments', {
          'mail_id': mailId,
          'file_id': _generateFileId(),
          'filename': attach.filename,
          'mime_type': attach.mimeType,
          'file_size': attach.data.length,
          'disposition': 0,
          'storage_type': attach.data.length <= 65536 ? 0 : 1,
          'inline_data': attach.data.length <= 65536 ? attach.data : null,
          'download_state': 2,
        });
      }
    }

    // Update folder counts
    await _updateFolderCounts(sentFolder.id);

    // TODO: Send via C library / onion routing

    return message;
  }

  /// Save draft
  Future<EmailMessage> saveDraft({
    String? mailId,
    required String toNodeId,
    String? toName,
    required String subject,
    required String body,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final draftsFolder = await getFolderByType(EmailFolderType.drafts);
    if (draftsFolder == null) throw Exception('Drafts folder not found');

    final id = mailId ?? _generateMailId();

    final message = EmailMessage(
      mailId: id,
      folderId: draftsFolder.id,
      folderType: EmailFolderType.drafts,
      from: EmailAddress(nodeId: 'local'),
      to: [EmailAddress(nodeId: toNodeId, displayName: toName)],
      subject: subject,
      body: body,
      timestamp: now,
      flags: EmailFlags.draft,
      status: EmailStatus.draft,
      createdAt: now,
    );

    if (mailId != null) {
      // Update existing draft
      await db.update(
        'email_messages',
        message.toMap(),
        where: 'mail_id = ?',
        whereArgs: [mailId],
      );
    } else {
      // Insert new draft
      await db.insert('email_messages', message.toMap());
    }

    await _updateFolderCounts(draftsFolder.id);
    return message;
  }

  // ============================================================
  // Actions
  // ============================================================

  /// Mark as read
  Future<void> markAsRead(String mailId, {bool sendReceipt = true}) async {
    final db = await _db.database;
    final message = await getMessage(mailId);
    if (message == null) return;

    await db.rawUpdate(
      'UPDATE email_messages SET flags = flags | 1 WHERE mail_id = ?',
      [mailId],
    );
    await _updateFolderCounts(message.folderId);

    // TODO: Send read receipt via C library if sendReceipt
  }

  /// Mark as unread
  Future<void> markAsUnread(String mailId) async {
    final db = await _db.database;
    final message = await getMessage(mailId);
    if (message == null) return;

    await db.rawUpdate(
      'UPDATE email_messages SET flags = flags & ~1 WHERE mail_id = ?',
      [mailId],
    );
    await _updateFolderCounts(message.folderId);
  }

  /// Toggle flagged
  Future<void> toggleFlagged(String mailId) async {
    final db = await _db.database;
    await db.rawUpdate(
      'UPDATE email_messages SET flags = flags ^ 2 WHERE mail_id = ?',
      [mailId],
    );
  }

  /// Move to folder
  Future<void> moveToFolder(String mailId, int folderId) async {
    final db = await _db.database;
    final message = await getMessage(mailId);
    if (message == null) return;

    final oldFolderId = message.folderId;
    await db.update(
      'email_messages',
      {'folder_id': folderId},
      where: 'mail_id = ?',
      whereArgs: [mailId],
    );
    await _updateFolderCounts(oldFolderId);
    await _updateFolderCounts(folderId);
  }

  /// Delete (move to trash)
  Future<void> delete(String mailId) async {
    final trashFolder = await getFolderByType(EmailFolderType.trash);
    if (trashFolder == null) return;
    await moveToFolder(mailId, trashFolder.id);
  }

  /// Permanently delete
  Future<void> deletePermanently(String mailId) async {
    final db = await _db.database;
    final message = await getMessage(mailId);
    if (message == null) return;

    // Delete attachments first
    await db.delete(
      'email_attachments',
      where: 'mail_id = ?',
      whereArgs: [mailId],
    );

    // Delete message
    await db.delete(
      'email_messages',
      where: 'mail_id = ?',
      whereArgs: [mailId],
    );

    await _updateFolderCounts(message.folderId);
  }

  /// Empty trash
  Future<void> emptyTrash() async {
    final db = await _db.database;
    final trashFolder = await getFolderByType(EmailFolderType.trash);
    if (trashFolder == null) return;

    // Delete all attachments in trash
    await db.rawDelete('''
      DELETE FROM email_attachments
      WHERE mail_id IN (SELECT mail_id FROM email_messages WHERE folder_id = ?)
    ''', [trashFolder.id]);

    // Delete all messages in trash
    await db.delete(
      'email_messages',
      where: 'folder_id = ?',
      whereArgs: [trashFolder.id],
    );

    await _updateFolderCounts(trashFolder.id);
  }

  /// Reply to message
  Future<EmailMessage> reply({
    required EmailMessage original,
    required String body,
    bool replyAll = false,
  }) async {
    final recipients = replyAll
        ? [original.from, ...original.to, ...original.cc]
        : [original.from];

    return sendEmail(
      toNodeId: recipients.first.nodeId,
      toName: recipients.first.displayName,
      subject: original.subject?.startsWith('Re:') == true
          ? original.subject!
          : 'Re: ${original.subject ?? ''}',
      body: body,
      inReplyTo: original.mailId,
    );
  }

  /// Forward message
  Future<EmailMessage> forward({
    required EmailMessage original,
    required String toNodeId,
    String? toName,
    String? additionalBody,
  }) async {
    final forwardBody = '''
${additionalBody ?? ''}

---------- Forwarded message ----------
From: ${original.from.display}
Date: ${original.dateString}
Subject: ${original.subject ?? '(no subject)'}

${original.body ?? ''}
''';

    return sendEmail(
      toNodeId: toNodeId,
      toName: toName,
      subject: original.subject?.startsWith('Fwd:') == true
          ? original.subject!
          : 'Fwd: ${original.subject ?? ''}',
      body: forwardBody,
    );
  }

  // ============================================================
  // Helpers
  // ============================================================

  String _generateMailId() {
    // Generate 8 random bytes as hex string
    final bytes = List<int>.generate(8, (i) => DateTime.now().microsecond % 256);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _generateFileId() {
    final bytes = List<int>.generate(8, (i) => DateTime.now().microsecond % 256);
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
