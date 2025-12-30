import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/email_folder.dart';
import '../models/email_message.dart';
import '../models/email_attachment.dart';
import '../providers/mail_provider.dart';
import 'mail_compose_screen.dart';

/// Screen for reading an email
class MailReadScreen extends ConsumerWidget {
  final String mailId;

  const MailReadScreen({
    super.key,
    required this.mailId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final messageAsync = ref.watch(emailMessageProvider(mailId));

    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.archive),
            onPressed: () => _archive(context, ref),
            tooltip: 'Archive',
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () => _delete(context, ref),
            tooltip: 'Delete',
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showMoreOptions(context, ref),
          ),
        ],
      ),
      body: messageAsync.when(
        data: (message) {
          if (message == null) {
            return const Center(child: Text('Message not found'));
          }
          return _buildMessageView(context, ref, message);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, s) => Center(child: Text('Error: $e')),
      ),
      floatingActionButton: messageAsync.when(
        data: (message) => message != null
            ? FloatingActionButton(
                onPressed: () => _reply(context, message),
                child: const Icon(Icons.reply),
              )
            : null,
        loading: () => null,
        error: (_, __) => null,
      ),
    );
  }

  Widget _buildMessageView(
    BuildContext context,
    WidgetRef ref,
    EmailMessage message,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Subject
          Text(
            message.subject ?? '(no subject)',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),

          // From
          _buildHeaderRow(
            context,
            'From',
            _buildSenderInfo(context, message),
          ),

          // To
          _buildHeaderRow(
            context,
            'To',
            Text(message.to.map((a) => a.display).join(', ')),
          ),

          // CC (if any)
          if (message.cc.isNotEmpty)
            _buildHeaderRow(
              context,
              'Cc',
              Text(message.cc.map((a) => a.display).join(', ')),
            ),

          // Date
          _buildHeaderRow(
            context,
            'Date',
            Text(message.dateString),
          ),

          const Divider(height: 32),

          // Attachments
          if (message.attachments.isNotEmpty) ...[
            Text(
              'Attachments (${message.attachments.length})',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: message.attachments.map((a) => _buildAttachmentCard(context, a)).toList(),
            ),
            const Divider(height: 32),
          ],

          // Signature status
          if (message.signatureValid)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, size: 16, color: Colors.green),
                  const SizedBox(width: 8),
                  Text(
                    'Signature verified',
                    style: TextStyle(color: Colors.green.shade700, fontSize: 12),
                  ),
                ],
              ),
            ),
          if (message.signatureValid) const SizedBox(height: 16),

          // Body
          SelectableText(
            message.body ?? '',
            style: Theme.of(context).textTheme.bodyLarge,
          ),

          const SizedBox(height: 32),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildActionButton(
                context,
                Icons.reply,
                'Reply',
                () => _reply(context, message),
              ),
              _buildActionButton(
                context,
                Icons.reply_all,
                'Reply All',
                () => _replyAll(context, message),
              ),
              _buildActionButton(
                context,
                Icons.forward,
                'Forward',
                () => _forward(context, message),
              ),
            ],
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildHeaderRow(BuildContext context, String label, Widget value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 60,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          ),
          Expanded(child: value),
        ],
      ),
    );
  }

  Widget _buildSenderInfo(BuildContext context, EmailMessage message) {
    return Row(
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          child: Text(
            message.from.display[0].toUpperCase(),
            style: TextStyle(
              color: Theme.of(context).colorScheme.onPrimaryContainer,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                message.from.display,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
              Text(
                message.from.nodeId,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAttachmentCard(BuildContext context, EmailAttachment attachment) {
    return Card(
      child: InkWell(
        onTap: () => _downloadAttachment(context, attachment),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_getAttachmentIcon(attachment.mimeType)),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    attachment.filename,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    attachment.fileSizeString,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(width: 8),
              Icon(
                attachment.downloadState == DownloadState.completed
                    ? Icons.check_circle
                    : Icons.download,
                size: 20,
                color: attachment.downloadState == DownloadState.completed
                    ? Colors.green
                    : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getAttachmentIcon(String? mimeType) {
    if (mimeType == null) return Icons.attach_file;
    if (mimeType.startsWith('image/')) return Icons.image;
    if (mimeType.startsWith('video/')) return Icons.video_file;
    if (mimeType.startsWith('audio/')) return Icons.audio_file;
    if (mimeType.contains('pdf')) return Icons.picture_as_pdf;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description;
    }
    if (mimeType.contains('excel') || mimeType.contains('spreadsheet')) {
      return Icons.table_chart;
    }
    if (mimeType.contains('zip') || mimeType.contains('rar')) {
      return Icons.folder_zip;
    }
    return Icons.attach_file;
  }

  Widget _buildActionButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }

  void _reply(BuildContext context, EmailMessage message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MailComposeScreen(replyTo: message),
      ),
    );
  }

  void _replyAll(BuildContext context, EmailMessage message) {
    // For reply all, we need to set replyTo and include all recipients
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MailComposeScreen(replyTo: message),
      ),
    );
  }

  void _forward(BuildContext context, EmailMessage message) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MailComposeScreen(forwardOf: message),
      ),
    );
  }

  void _archive(BuildContext context, WidgetRef ref) async {
    await ref.read(mailActionsProvider).archive(mailId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message archived')),
      );
      Navigator.pop(context);
    }
  }

  void _delete(BuildContext context, WidgetRef ref) async {
    await ref.read(mailActionsProvider).delete(mailId);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Message deleted')),
      );
      Navigator.pop(context);
    }
  }

  void _showMoreOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.markunread),
            title: const Text('Mark as unread'),
            onTap: () {
              Navigator.pop(context);
              ref.read(mailActionsProvider).markAsUnread(mailId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.star),
            title: const Text('Toggle star'),
            onTap: () {
              Navigator.pop(context);
              ref.read(mailActionsProvider).toggleFlagged(mailId);
            },
          ),
          ListTile(
            leading: const Icon(Icons.report),
            title: const Text('Mark as spam'),
            onTap: () async {
              Navigator.pop(context);
              final folders = await ref.read(emailFoldersProvider.future);
              final spamFolder = folders.firstWhere(
                (f) => f.type == EmailFolderType.spam,
              );
              ref.read(mailActionsProvider).moveToFolder(mailId, spamFolder.id);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_forever),
            title: const Text('Delete permanently'),
            onTap: () {
              Navigator.pop(context);
              _confirmPermanentDelete(context, ref);
            },
          ),
        ],
      ),
    );
  }

  void _confirmPermanentDelete(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete permanently?'),
        content: const Text('This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(mailActionsProvider).deletePermanently(mailId);
              if (context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _downloadAttachment(BuildContext context, EmailAttachment attachment) {
    // TODO: Implement attachment download
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Downloading ${attachment.filename}...')),
    );
  }
}
