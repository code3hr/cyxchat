import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import '../models/models.dart';
import '../services/group_service.dart';

/// Provider for invite links of a specific group
final inviteLinksProvider = FutureProvider.family<List<InviteLink>, String>(
    (ref, groupId) async {
  return GroupService.instance.getInviteLinks(groupId);
});

/// Screen to manage invite links for a group
class InviteLinksScreen extends ConsumerStatefulWidget {
  final String groupId;
  final String groupName;

  const InviteLinksScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  ConsumerState<InviteLinksScreen> createState() => _InviteLinksScreenState();
}

class _InviteLinksScreenState extends ConsumerState<InviteLinksScreen> {
  @override
  Widget build(BuildContext context) {
    final linksAsync = ref.watch(inviteLinksProvider(widget.groupId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Invite Links'),
      ),
      body: linksAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text('Error: $error'),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(inviteLinksProvider(widget.groupId)),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (links) {
          if (links.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.link_off, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'No invite links yet',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Create a link to invite people to this group',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: () => _showCreateLinkDialog(),
                    icon: const Icon(Icons.add_link),
                    label: const Text('Create Link'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: links.length,
            itemBuilder: (context, index) {
              final link = links[index];
              return _InviteLinkCard(
                link: link,
                onCopy: () => _copyLink(link),
                onShare: () => _shareLink(link),
                onRevoke: () => _revokeLink(link),
                onDelete: () => _deleteLink(link),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateLinkDialog(),
        icon: const Icon(Icons.add_link),
        label: const Text('Create Link'),
      ),
    );
  }

  void _showCreateLinkDialog() {
    showDialog(
      context: context,
      builder: (context) => _CreateLinkDialog(
        groupId: widget.groupId,
        groupName: widget.groupName,
        onCreated: (link) {
          ref.invalidate(inviteLinksProvider(widget.groupId));
          _copyLink(link);
        },
      ),
    );
  }

  void _copyLink(InviteLink link) {
    final url = link.toUrl();
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Link copied to clipboard'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _shareLink(InviteLink link) {
    final url = link.toUrl();
    Share.share(
      'Join ${widget.groupName} on CyxChat:\n$url',
      subject: 'Invite to ${widget.groupName}',
    );
  }

  Future<void> _revokeLink(InviteLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Link?'),
        content: Text(
          'This will disable "${link.name ?? 'Invite link'}" and anyone '
          'with this link will no longer be able to join.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await GroupService.instance.revokeInviteLink(
        groupId: widget.groupId,
        linkId: link.id,
      );
      if (success && mounted) {
        ref.invalidate(inviteLinksProvider(widget.groupId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link revoked')),
        );
      }
    }
  }

  Future<void> _deleteLink(InviteLink link) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Link?'),
        content: Text(
          'This will permanently delete "${link.name ?? 'Invite link'}". '
          'This action cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final success = await GroupService.instance.deleteInviteLink(
        groupId: widget.groupId,
        linkId: link.id,
      );
      if (success && mounted) {
        ref.invalidate(inviteLinksProvider(widget.groupId));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link deleted')),
        );
      }
    }
  }
}

/// Card widget for displaying an invite link
class _InviteLinkCard extends StatelessWidget {
  final InviteLink link;
  final VoidCallback onCopy;
  final VoidCallback onShare;
  final VoidCallback onRevoke;
  final VoidCallback onDelete;

  const _InviteLinkCard({
    required this.link,
    required this.onCopy,
    required this.onShare,
    required this.onRevoke,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final isActive = link.isValid;
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Icon(
                  isActive ? Icons.link : Icons.link_off,
                  color: isActive ? theme.colorScheme.primary : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        link.name ?? 'Invite Link',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        link.statusText,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isActive ? Colors.green : Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'copy':
                        onCopy();
                        break;
                      case 'share':
                        onShare();
                        break;
                      case 'revoke':
                        onRevoke();
                        break;
                      case 'delete':
                        onDelete();
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    if (isActive) ...[
                      const PopupMenuItem(
                        value: 'copy',
                        child: Row(
                          children: [
                            Icon(Icons.copy),
                            SizedBox(width: 12),
                            Text('Copy Link'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'share',
                        child: Row(
                          children: [
                            Icon(Icons.share),
                            SizedBox(width: 12),
                            Text('Share'),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'revoke',
                        child: Row(
                          children: [
                            Icon(Icons.block, color: Colors.orange),
                            SizedBox(width: 12),
                            Text('Revoke'),
                          ],
                        ),
                      ),
                    ],
                    const PopupMenuItem(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete, color: Colors.red),
                          SizedBox(width: 12),
                          Text('Delete'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),

            const Divider(height: 24),

            // Info rows
            _InfoRow(
              icon: Icons.people,
              label: 'Uses',
              value: link.usesText,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.schedule,
              label: 'Expires',
              value: link.expiryText,
            ),
            const SizedBox(height: 8),
            _InfoRow(
              icon: Icons.access_time,
              label: 'Created',
              value: _formatDate(link.createdAt),
            ),

            // Quick action buttons for active links
            if (isActive) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onShare,
                      icon: const Icon(Icons.share, size: 18),
                      label: const Text('Share'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inDays == 0) {
      return 'Today';
    } else if (diff.inDays == 1) {
      return 'Yesterday';
    } else if (diff.inDays < 7) {
      return '${diff.inDays} days ago';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}

/// Simple info row widget
class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey),
        const SizedBox(width: 8),
        Text(
          '$label: ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey[600],
              ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

/// Dialog for creating a new invite link
class _CreateLinkDialog extends StatefulWidget {
  final String groupId;
  final String groupName;
  final void Function(InviteLink) onCreated;

  const _CreateLinkDialog({
    required this.groupId,
    required this.groupName,
    required this.onCreated,
  });

  @override
  State<_CreateLinkDialog> createState() => _CreateLinkDialogState();
}

class _CreateLinkDialogState extends State<_CreateLinkDialog> {
  final _nameController = TextEditingController();
  int? _expiryDays;
  int? _maxUses;
  bool _isCreating = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create Invite Link'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Link Name (optional)',
                hintText: 'e.g., "Friend Invite"',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Expires after',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _ExpiryChip(
                  label: 'Never',
                  selected: _expiryDays == null,
                  onSelected: () => setState(() => _expiryDays = null),
                ),
                _ExpiryChip(
                  label: '1 day',
                  selected: _expiryDays == 1,
                  onSelected: () => setState(() => _expiryDays = 1),
                ),
                _ExpiryChip(
                  label: '7 days',
                  selected: _expiryDays == 7,
                  onSelected: () => setState(() => _expiryDays = 7),
                ),
                _ExpiryChip(
                  label: '30 days',
                  selected: _expiryDays == 30,
                  onSelected: () => setState(() => _expiryDays = 30),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              'Max uses',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _ExpiryChip(
                  label: 'Unlimited',
                  selected: _maxUses == null,
                  onSelected: () => setState(() => _maxUses = null),
                ),
                _ExpiryChip(
                  label: '1',
                  selected: _maxUses == 1,
                  onSelected: () => setState(() => _maxUses = 1),
                ),
                _ExpiryChip(
                  label: '10',
                  selected: _maxUses == 10,
                  onSelected: () => setState(() => _maxUses = 10),
                ),
                _ExpiryChip(
                  label: '100',
                  selected: _maxUses == 100,
                  onSelected: () => setState(() => _maxUses = 100),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isCreating ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isCreating ? null : _createLink,
          child: _isCreating
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  Future<void> _createLink() async {
    setState(() => _isCreating = true);

    final expiresAt = _expiryDays != null
        ? DateTime.now().add(Duration(days: _expiryDays!))
        : null;

    final link = await GroupService.instance.createInviteLink(
      groupId: widget.groupId,
      name: _nameController.text.isEmpty ? null : _nameController.text,
      expiresAt: expiresAt,
      maxUses: _maxUses,
    );

    if (mounted) {
      Navigator.pop(context);
      if (link != null) {
        widget.onCreated(link);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Link created and copied!')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to create link')),
        );
      }
    }
  }
}

/// Chip for selecting expiry option
class _ExpiryChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _ExpiryChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
    );
  }
}
