import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/models.dart';
import '../providers/group_provider.dart';
import '../services/identity_service.dart';

class GroupInfoScreen extends ConsumerStatefulWidget {
  final String groupId;

  const GroupInfoScreen({super.key, required this.groupId});

  @override
  ConsumerState<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends ConsumerState<GroupInfoScreen> {
  bool _isEditing = false;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController();
    _descriptionController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupAsync = ref.watch(groupProvider(widget.groupId));
    final identity = IdentityService.instance.currentIdentity;
    final myNodeId = identity?.nodeId ?? '';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Group Info'),
        actions: [
          groupAsync.whenOrNull(
            data: (group) {
              if (group == null) return null;
              final canEdit = group.isOwner(myNodeId) || group.isAdmin(myNodeId);
              if (!canEdit) return null;

              return IconButton(
                icon: Icon(_isEditing ? Icons.check : Icons.edit),
                onPressed: () {
                  if (_isEditing) {
                    _saveChanges(group);
                  } else {
                    setState(() {
                      _isEditing = true;
                      _nameController.text = group.name;
                      _descriptionController.text = group.description ?? '';
                    });
                  }
                },
              );
            },
          ) ?? const SizedBox.shrink(),
        ],
      ),
      body: groupAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
        data: (group) {
          if (group == null) {
            return const Center(child: Text('Group not found'));
          }

          final myRole = group.getRole(myNodeId);
          final canManageMembers =
              myRole == GroupRole.owner || myRole == GroupRole.admin;

          return ListView(
            children: [
              // Group header
              _GroupHeader(
                group: group,
                isEditing: _isEditing,
                nameController: _nameController,
                descriptionController: _descriptionController,
              ),

              const SizedBox(height: 16),

              // Members section
              _MembersSection(
                group: group,
                myNodeId: myNodeId,
                canManageMembers: canManageMembers,
                onAddMember: () => _showAddMemberDialog(context),
                onMemberTap: (member) =>
                    _showMemberOptions(context, group, member, myNodeId),
              ),

              const SizedBox(height: 24),

              // Actions
              _ActionsSection(
                group: group,
                myNodeId: myNodeId,
                onLeave: () => _confirmLeaveGroup(context),
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Future<void> _saveChanges(Group group) async {
    final newName = _nameController.text.trim();
    final newDescription = _descriptionController.text.trim();

    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group name cannot be empty')),
      );
      return;
    }

    try {
      if (newName != group.name) {
        await ref.read(groupActionsProvider).updateName(widget.groupId, newName);
      }
      if (newDescription != (group.description ?? '')) {
        await ref.read(groupActionsProvider).updateDescription(
              widget.groupId,
              newDescription.isEmpty ? null : newDescription,
            );
      }
      setState(() => _isEditing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    }
  }

  void _showAddMemberDialog(BuildContext context) {
    // TODO: Show contact picker to add members
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Add member feature coming soon')),
    );
  }

  void _showMemberOptions(
    BuildContext context,
    Group group,
    GroupMember member,
    String myNodeId,
  ) {
    final myRole = group.getRole(myNodeId);
    final isMe = member.nodeId == myNodeId;
    final isOwner = group.isOwner(myNodeId);
    final canManage = myRole == GroupRole.owner ||
        (myRole == GroupRole.admin && member.role == GroupRole.member);

    if (isMe || !canManage) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDarkSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.textDarkSecondary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  member.displayText,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Promote/Demote admin (owner only)
              if (isOwner) ...[
                if (member.role == GroupRole.member)
                  ListTile(
                    leading: const Icon(Icons.admin_panel_settings),
                    title: const Text('Make Admin'),
                    onTap: () async {
                      Navigator.pop(context);
                      await ref
                          .read(groupActionsProvider)
                          .promoteAdmin(widget.groupId, member.nodeId);
                    },
                  )
                else if (member.role == GroupRole.admin)
                  ListTile(
                    leading: const Icon(Icons.person),
                    title: const Text('Remove Admin'),
                    onTap: () async {
                      Navigator.pop(context);
                      await ref
                          .read(groupActionsProvider)
                          .demoteAdmin(widget.groupId, member.nodeId);
                    },
                  ),
              ],

              // Remove member
              ListTile(
                leading: Icon(Icons.person_remove, color: AppColors.error),
                title: Text(
                  'Remove from Group',
                  style: TextStyle(color: AppColors.error),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await ref
                      .read(groupActionsProvider)
                      .removeMember(widget.groupId, member.nodeId);
                },
              ),

              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _confirmLeaveGroup(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.bgDarkSecondary,
          title: const Text('Leave Group?'),
          content: const Text(
            'You will no longer receive messages from this group.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.pop(context);
                await ref.read(groupActionsProvider).leaveGroup(widget.groupId);
                if (mounted) {
                  Navigator.popUntil(context, (route) => route.isFirst);
                }
              },
              child: Text(
                'Leave',
                style: TextStyle(color: AppColors.error),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _GroupHeader extends StatelessWidget {
  final Group group;
  final bool isEditing;
  final TextEditingController nameController;
  final TextEditingController descriptionController;

  const _GroupHeader({
    required this.group,
    required this.isEditing,
    required this.nameController,
    required this.descriptionController,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.2),
            AppColors.bgDark,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Column(
        children: [
          // Group avatar
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.primary, AppColors.primaryLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(25),
            ),
            child: const Icon(
              Icons.group,
              size: 50,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),

          // Group name
          if (isEditing)
            TextField(
              controller: nameController,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                hintText: 'Group name',
                border: UnderlineInputBorder(),
              ),
            )
          else
            Text(
              group.name,
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),

          // Description
          if (isEditing)
            TextField(
              controller: descriptionController,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: TextStyle(
                color: AppColors.textDarkSecondary,
              ),
              decoration: const InputDecoration(
                hintText: 'Add description',
                border: UnderlineInputBorder(),
              ),
            )
          else if (group.description != null && group.description!.isNotEmpty)
            Text(
              group.description!,
              style: TextStyle(
                color: AppColors.textDarkSecondary,
              ),
              textAlign: TextAlign.center,
            )
          else
            Text(
              'No description',
              style: TextStyle(
                color: AppColors.textDarkSecondary.withOpacity(0.5),
                fontStyle: FontStyle.italic,
              ),
            ),

          const SizedBox(height: 12),

          // Member count and created date
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.people,
                size: 16,
                color: AppColors.textDarkSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                '${group.memberCount} members',
                style: TextStyle(
                  color: AppColors.textDarkSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(width: 16),
              Icon(
                Icons.calendar_today,
                size: 16,
                color: AppColors.textDarkSecondary,
              ),
              const SizedBox(width: 4),
              Text(
                'Created ${_formatDate(group.createdAt)}',
                style: TextStyle(
                  color: AppColors.textDarkSecondary,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}

class _MembersSection extends StatelessWidget {
  final Group group;
  final String myNodeId;
  final bool canManageMembers;
  final VoidCallback onAddMember;
  final void Function(GroupMember) onMemberTap;

  const _MembersSection({
    required this.group,
    required this.myNodeId,
    required this.canManageMembers,
    required this.onAddMember,
    required this.onMemberTap,
  });

  @override
  Widget build(BuildContext context) {
    // Sort members: owner first, then admins, then regular members
    final sortedMembers = List<GroupMember>.from(group.members)
      ..sort((a, b) => b.role.index.compareTo(a.role.index));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Members',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDarkSecondary,
                ),
              ),
              const Spacer(),
              if (canManageMembers)
                TextButton.icon(
                  onPressed: onAddMember,
                  icon: Icon(Icons.person_add, size: 18, color: AppColors.primary),
                  label: Text(
                    'Add',
                    style: TextStyle(color: AppColors.primary),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        ...sortedMembers.map((member) {
          final isMe = member.nodeId == myNodeId;
          return _MemberTile(
            member: member,
            isMe: isMe,
            onTap: () => onMemberTap(member),
          );
        }),
      ],
    );
  }
}

class _MemberTile extends StatelessWidget {
  final GroupMember member;
  final bool isMe;
  final VoidCallback onTap;

  const _MemberTile({
    required this.member,
    required this.isMe,
    required this.onTap,
  });

  Color _getAvatarColor() {
    final hash = member.nodeId.hashCode;
    final colors = [
      Colors.blue,
      Colors.green,
      Colors.orange,
      Colors.purple,
      Colors.teal,
      Colors.pink,
      Colors.indigo,
      Colors.amber,
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: _getAvatarColor().withOpacity(0.2),
        child: Text(
          member.displayText[0].toUpperCase(),
          style: TextStyle(
            color: _getAvatarColor(),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.displayText,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isMe) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'You',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        member.nodeId.length > 16
            ? '${member.nodeId.substring(0, 16)}...'
            : member.nodeId,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.textDarkSecondary,
        ),
      ),
      trailing: _RoleBadge(role: member.role),
    );
  }
}

class _RoleBadge extends StatelessWidget {
  final GroupRole role;

  const _RoleBadge({required this.role});

  @override
  Widget build(BuildContext context) {
    if (role == GroupRole.member) return const SizedBox.shrink();

    final isOwner = role == GroupRole.owner;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isOwner
            ? Colors.amber.withOpacity(0.2)
            : AppColors.primary.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isOwner ? Icons.star : Icons.admin_panel_settings,
            size: 14,
            color: isOwner ? Colors.amber : AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            role.displayName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: isOwner ? Colors.amber : AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionsSection extends StatelessWidget {
  final Group group;
  final String myNodeId;
  final VoidCallback onLeave;

  const _ActionsSection({
    required this.group,
    required this.myNodeId,
    required this.onLeave,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Leave group button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onLeave,
              icon: Icon(Icons.exit_to_app, color: AppColors.error),
              label: Text(
                'Leave Group',
                style: TextStyle(color: AppColors.error),
              ),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: AppColors.error),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
