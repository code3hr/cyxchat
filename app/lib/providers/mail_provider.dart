import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/email_folder.dart';
import '../models/email_message.dart';
import '../models/email_attachment.dart';
import '../services/mail_service.dart';

/// Provider for all email folders
final emailFoldersProvider = FutureProvider<List<EmailFolder>>((ref) async {
  return MailService.instance.getFolders();
});

/// Provider for a specific folder
final emailFolderProvider =
    FutureProvider.family<EmailFolder?, int>((ref, folderId) async {
  return MailService.instance.getFolder(folderId);
});

/// Provider for messages in a folder
final folderMessagesProvider =
    FutureProvider.family<List<EmailMessage>, int>((ref, folderId) async {
  return MailService.instance.getMessages(folderId);
});

/// Provider for a specific email message
final emailMessageProvider =
    FutureProvider.family<EmailMessage?, String>((ref, mailId) async {
  return MailService.instance.getMessage(mailId);
});

/// Provider for email thread
final emailThreadProvider =
    FutureProvider.family<List<EmailMessage>, String>((ref, threadId) async {
  return MailService.instance.getThread(threadId);
});

/// Provider for attachments of a message
final emailAttachmentsProvider =
    FutureProvider.family<List<EmailAttachment>, String>((ref, mailId) async {
  return MailService.instance.getAttachments(mailId);
});

/// Provider for total unread count across all folders
final totalUnreadProvider = FutureProvider<int>((ref) async {
  return MailService.instance.getTotalUnreadCount();
});

/// Provider for unread count per folder
final folderUnreadProvider =
    FutureProvider.family<int, int>((ref, folderId) async {
  return MailService.instance.getUnreadCount(folderId);
});

/// Provider for email search results
final emailSearchProvider =
    FutureProvider.family<List<EmailMessage>, String>((ref, query) async {
  if (query.isEmpty) return [];
  return MailService.instance.search(query);
});

/// Provider for mail actions
final mailActionsProvider = Provider((ref) => MailActions(ref));

/// Mail action handler
class MailActions {
  final Ref _ref;

  MailActions(this._ref);

  /// Send a new email
  Future<EmailMessage> sendEmail({
    required String toNodeId,
    String? toName,
    required String subject,
    required String body,
    String? inReplyTo,
    List<EmailAttachmentData>? attachments,
  }) async {
    final message = await MailService.instance.sendEmail(
      toNodeId: toNodeId,
      toName: toName,
      subject: subject,
      body: body,
      inReplyTo: inReplyTo,
      attachments: attachments,
    );
    _invalidateAll();
    return message;
  }

  /// Save email as draft
  Future<EmailMessage> saveDraft({
    String? mailId,
    required String toNodeId,
    String? toName,
    required String subject,
    required String body,
  }) async {
    final message = await MailService.instance.saveDraft(
      mailId: mailId,
      toNodeId: toNodeId,
      toName: toName,
      subject: subject,
      body: body,
    );
    _ref.invalidate(emailFoldersProvider);
    _ref.invalidate(folderMessagesProvider(EmailFolderType.drafts.index + 1));
    return message;
  }

  /// Mark message as read
  Future<void> markAsRead(String mailId, {bool sendReceipt = true}) async {
    await MailService.instance.markAsRead(mailId, sendReceipt: sendReceipt);
    _ref.invalidate(emailMessageProvider(mailId));
    _ref.invalidate(emailFoldersProvider);
    _ref.invalidate(totalUnreadProvider);
  }

  /// Mark message as unread
  Future<void> markAsUnread(String mailId) async {
    await MailService.instance.markAsUnread(mailId);
    _ref.invalidate(emailMessageProvider(mailId));
    _ref.invalidate(emailFoldersProvider);
    _ref.invalidate(totalUnreadProvider);
  }

  /// Toggle flagged status
  Future<void> toggleFlagged(String mailId) async {
    await MailService.instance.toggleFlagged(mailId);
    _ref.invalidate(emailMessageProvider(mailId));
  }

  /// Move message to folder
  Future<void> moveToFolder(String mailId, int folderId) async {
    final message = await MailService.instance.getMessage(mailId);
    if (message != null) {
      await MailService.instance.moveToFolder(mailId, folderId);
      _ref.invalidate(folderMessagesProvider(message.folderId));
      _ref.invalidate(folderMessagesProvider(folderId));
      _ref.invalidate(emailFoldersProvider);
    }
  }

  /// Archive message
  Future<void> archive(String mailId) async {
    final folders = await MailService.instance.getFolders();
    final archiveFolder = folders.firstWhere(
      (f) => f.type == EmailFolderType.archive,
    );
    await moveToFolder(mailId, archiveFolder.id);
  }

  /// Delete message (move to trash)
  Future<void> delete(String mailId) async {
    final message = await MailService.instance.getMessage(mailId);
    if (message != null) {
      await MailService.instance.delete(mailId);
      _ref.invalidate(folderMessagesProvider(message.folderId));
      _ref.invalidate(emailFoldersProvider);
    }
  }

  /// Permanently delete message
  Future<void> deletePermanently(String mailId) async {
    final message = await MailService.instance.getMessage(mailId);
    if (message != null) {
      await MailService.instance.deletePermanently(mailId);
      _ref.invalidate(folderMessagesProvider(message.folderId));
      _ref.invalidate(emailFoldersProvider);
    }
  }

  /// Empty trash folder
  Future<void> emptyTrash() async {
    await MailService.instance.emptyTrash();
    final folders = await MailService.instance.getFolders();
    final trashFolder = folders.firstWhere(
      (f) => f.type == EmailFolderType.trash,
    );
    _ref.invalidate(folderMessagesProvider(trashFolder.id));
    _ref.invalidate(emailFoldersProvider);
  }

  /// Reply to message
  Future<EmailMessage> reply({
    required EmailMessage original,
    required String body,
    bool replyAll = false,
  }) async {
    final message = await MailService.instance.reply(
      original: original,
      body: body,
      replyAll: replyAll,
    );
    _invalidateAll();
    return message;
  }

  /// Forward message
  Future<EmailMessage> forward({
    required EmailMessage original,
    required String toNodeId,
    String? toName,
    String? additionalBody,
  }) async {
    final message = await MailService.instance.forward(
      original: original,
      toNodeId: toNodeId,
      toName: toName,
      additionalBody: additionalBody,
    );
    _invalidateAll();
    return message;
  }

  void _invalidateAll() {
    _ref.invalidate(emailFoldersProvider);
    _ref.invalidate(totalUnreadProvider);
    // Note: Individual folder messages will be invalidated on next access
  }
}

/// Attachment data for sending
class EmailAttachmentData {
  final String filename;
  final String mimeType;
  final List<int> data;

  EmailAttachmentData({
    required this.filename,
    required this.mimeType,
    required this.data,
  });
}
