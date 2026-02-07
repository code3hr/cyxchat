import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/models.dart';
import '../providers/group_provider.dart';
import '../providers/contact_provider.dart';
import '../services/group_service.dart';
import '../services/identity_service.dart';
import '../utils/node_id_utils.dart';
import 'invite_links_screen.dart';
import 'admin_log_screen.dart';

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

              // Group Settings section (admins only)
              if (canManageMembers)
                _GroupSettingsSection(
                  group: group,
                  isOwner: group.isOwner(myNodeId),
                  onSlowModeChanged: (seconds) => _setSlowMode(seconds),
                  onWhoCanAddChanged: (setting) => _setWhoCanAdd(setting),
                  onWhoCanEditChanged: (setting) => _setWhoCanEdit(setting),
                  onWhoCanSendChanged: (setting) => _setWhoCanSend(setting),
                  onHistoryVisibleChanged: (visible) => _setHistoryVisible(visible),
                  onUpgradeToSupergroup: () => _upgradeToSupergroup(),
                  onManageSelectedSenders: () => _showManageSelectedSenders(group),
                ),

              if (canManageMembers) const SizedBox(height: 24),

              // Invite Links section (admins only)
              // Basic groups get simple invite links, supergroups get advanced features
              if (canManageMembers)
                _InviteLinksSection(
                  group: group,
                  onManageLinks: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => InviteLinksScreen(
                        groupId: group.id,
                        groupName: group.name,
                      ),
                    ),
                  ),
                ),

              if (canManageMembers) const SizedBox(height: 24),

              // Admin Log section (supergroups only)
              if (canManageMembers && group.hasAdminLog)
                _AdminLogSection(
                  group: group,
                  onViewLog: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AdminLogScreen(
                        groupId: group.id,
                        groupName: group.name,
                      ),
                    ),
                  ),
                ),

              if (canManageMembers) const SizedBox(height: 24),

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
    final groupAsync = ref.read(groupProvider(widget.groupId));
    final group = groupAsync.valueOrNull;
    if (group == null) return;

    // Get existing member IDs to filter them out
    final existingMemberIds = group.members.map((m) => m.nodeId).toSet();

    showDialog(
      context: context,
      builder: (context) => _AddMemberDialog(
        existingMemberIds: existingMemberIds,
        onSelectContact: (contact) async {
          Navigator.pop(context);
          await _inviteMember(contact);
        },
        onEnterNodeId: (nodeId) async {
          Navigator.pop(context);
          await _inviteMemberByNodeId(nodeId);
        },
      ),
    );
  }

  Future<void> _inviteMemberByNodeId(String nodeId) async {
    // Normalize the node ID
    final normalizedId = NodeIdUtils.normalize(nodeId.trim());

    // Validate format
    if (!NodeIdUtils.isValid(normalizedId)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid Node ID format. Use UUID (xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) or 64-char hex.'),
          ),
        );
      }
      return;
    }

    try {
      await ref.read(groupActionsProvider).inviteMember(
        widget.groupId,
        normalizedId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invited ${NodeIdUtils.shortId(normalizedId)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to invite: $e')),
        );
      }
    }
  }

  Future<void> _inviteMember(Contact contact) async {
    try {
      await ref.read(groupActionsProvider).inviteMember(
        widget.groupId,
        contact.nodeId,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invited ${contact.displayName ?? contact.shortId}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to invite: $e')),
        );
      }
    }
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

    // Check if member is currently muted
    final isMuted = GroupService.instance.isMemberMuted(
      groupId: widget.groupId,
      memberId: member.nodeId,
    );

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

              // Mute/Unmute
              if (isMuted)
                ListTile(
                  leading: const Icon(Icons.volume_up),
                  title: const Text('Unmute'),
                  onTap: () {
                    Navigator.pop(context);
                    _unmuteMember(member);
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.volume_off),
                  title: const Text('Mute'),
                  onTap: () {
                    Navigator.pop(context);
                    _showMuteOptions(member);
                  },
                ),

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

  // ============================================================
  // Group Settings Methods
  // ============================================================

  Future<void> _setSlowMode(int seconds) async {
    try {
      await GroupService.instance.setSlowMode(
        groupId: widget.groupId,
        seconds: seconds,
      );
      ref.invalidate(groupProvider(widget.groupId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(seconds == 0
                ? 'Slow mode disabled'
                : 'Slow mode set to ${_formatSlowMode(seconds)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update slow mode: $e')),
        );
      }
    }
  }

  Future<void> _setWhoCanAdd(WhoCanAddMembers setting) async {
    try {
      await GroupService.instance.setWhoCanAddMembers(
        groupId: widget.groupId,
        setting: setting,
      );
      ref.invalidate(groupProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  Future<void> _setWhoCanEdit(WhoCanChangeInfo setting) async {
    try {
      await GroupService.instance.setWhoCanChangeInfo(
        groupId: widget.groupId,
        setting: setting,
      );
      ref.invalidate(groupProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  Future<void> _setWhoCanSend(WhoCanSendMessages setting) async {
    try {
      await GroupService.instance.setWhoCanSend(
        groupId: widget.groupId,
        setting: setting,
      );
      ref.invalidate(groupProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  void _showManageSelectedSenders(Group group) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.bgDarkSecondary,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return _SelectedSendersSheet(
              group: group,
              scrollController: scrollController,
              onToggleSender: (memberId, isSelected) async {
                if (isSelected) {
                  await GroupService.instance.addSelectedSender(
                    groupId: group.id,
                    memberId: memberId,
                  );
                } else {
                  await GroupService.instance.removeSelectedSender(
                    groupId: group.id,
                    memberId: memberId,
                  );
                }
                ref.invalidate(groupProvider(widget.groupId));
              },
            );
          },
        );
      },
    );
  }

  Future<void> _setHistoryVisible(bool visible) async {
    try {
      await GroupService.instance.setMessageHistoryVisible(
        groupId: widget.groupId,
        visible: visible,
      );
      ref.invalidate(groupProvider(widget.groupId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update setting: $e')),
        );
      }
    }
  }

  Future<void> _upgradeToSupergroup() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgDarkSecondary,
        title: const Text('Upgrade to Supergroup?'),
        content: const Text(
          'Supergroups have unlimited members and advanced admin features. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Upgrade',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await GroupService.instance.upgradeToSupergroup(widget.groupId);
        ref.invalidate(groupProvider(widget.groupId));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Upgraded to supergroup')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upgrade: $e')),
          );
        }
      }
    }
  }

  String _formatSlowMode(int seconds) {
    if (seconds < 60) return '${seconds}s';
    if (seconds < 3600) return '${seconds ~/ 60}m';
    return '${seconds ~/ 3600}h';
  }

  // ============================================================
  // Member Restriction Methods
  // ============================================================

  Future<void> _muteMember(GroupMember member, Duration? duration) async {
    final identity = IdentityService.instance.currentIdentity;
    if (identity == null) return;

    try {
      await GroupService.instance.muteMember(
        groupId: widget.groupId,
        memberId: member.nodeId,
        restrictedBy: identity.nodeId,
        duration: duration,
      );
      ref.invalidate(groupProvider(widget.groupId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(duration == null
                ? 'Muted ${member.displayText} permanently'
                : 'Muted ${member.displayText} for ${_formatDuration(duration)}'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to mute: $e')),
        );
      }
    }
  }

  Future<void> _unmuteMember(GroupMember member) async {
    try {
      await GroupService.instance.unrestrictMember(
        groupId: widget.groupId,
        memberId: member.nodeId,
      );
      ref.invalidate(groupProvider(widget.groupId));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unmuted ${member.displayText}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to unmute: $e')),
        );
      }
    }
  }

  String _formatDuration(Duration duration) {
    if (duration.inDays > 0) return '${duration.inDays} days';
    if (duration.inHours > 0) return '${duration.inHours} hours';
    if (duration.inMinutes > 0) return '${duration.inMinutes} minutes';
    return '${duration.inSeconds} seconds';
  }

  void _showMuteOptions(GroupMember member) {
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
              const Text(
                'Mute Duration',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('1 hour'),
                onTap: () {
                  Navigator.pop(context);
                  _muteMember(member, const Duration(hours: 1));
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('8 hours'),
                onTap: () {
                  Navigator.pop(context);
                  _muteMember(member, const Duration(hours: 8));
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('1 day'),
                onTap: () {
                  Navigator.pop(context);
                  _muteMember(member, const Duration(days: 1));
                },
              ),
              ListTile(
                leading: const Icon(Icons.timer),
                title: const Text('1 week'),
                onTap: () {
                  Navigator.pop(context);
                  _muteMember(member, const Duration(days: 7));
                },
              ),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('Forever'),
                onTap: () {
                  Navigator.pop(context);
                  _muteMember(member, null);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
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

          // Group type badge
          if (group.isSupergroup)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [AppColors.primary, AppColors.primaryLight],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.verified, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  const Text(
                    'Supergroup',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

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
                '${group.memberCount}/${group.effectiveMaxMembers} members',
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

          const SizedBox(height: 12),

          // Group ID with copy button
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.bgDarkSecondary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.tag,
                  size: 14,
                  color: AppColors.textDarkSecondary,
                ),
                const SizedBox(width: 6),
                Text(
                  group.shortId,
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                ),
                const SizedBox(width: 8),
                InkWell(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: group.id));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Group ID copied to clipboard'),
                        duration: Duration(seconds: 2),
                      ),
                    );
                  },
                  child: Icon(
                    Icons.copy,
                    size: 16,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
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

/// Group settings section for admin controls
class _GroupSettingsSection extends StatelessWidget {
  final Group group;
  final bool isOwner;
  final void Function(int seconds) onSlowModeChanged;
  final void Function(WhoCanAddMembers) onWhoCanAddChanged;
  final void Function(WhoCanChangeInfo) onWhoCanEditChanged;
  final void Function(WhoCanSendMessages) onWhoCanSendChanged;
  final void Function(bool visible) onHistoryVisibleChanged;
  final VoidCallback onUpgradeToSupergroup;
  final VoidCallback? onManageSelectedSenders;

  const _GroupSettingsSection({
    required this.group,
    required this.isOwner,
    required this.onSlowModeChanged,
    required this.onWhoCanAddChanged,
    required this.onWhoCanEditChanged,
    required this.onWhoCanSendChanged,
    required this.onHistoryVisibleChanged,
    required this.onUpgradeToSupergroup,
    this.onManageSelectedSenders,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Group Settings',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textDarkSecondary,
                ),
              ),
              if (group.isSupergroup) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Supergroup',
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
        ),
        const SizedBox(height: 8),

        // Group type / Upgrade option (owner only, basic groups only)
        if (isOwner && !group.isSupergroup)
          ListTile(
            leading: const Icon(Icons.upgrade),
            title: const Text('Upgrade to Supergroup'),
            subtitle: Text(
              'Unlimited members, advanced features',
              style: TextStyle(
                color: AppColors.textDarkSecondary,
                fontSize: 12,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: AppColors.textDarkSecondary),
            onTap: onUpgradeToSupergroup,
          ),

        // Slow mode
        ListTile(
          leading: const Icon(Icons.slow_motion_video),
          title: const Text('Slow Mode'),
          subtitle: Text(
            group.slowModeDisplay,
            style: TextStyle(
              color: AppColors.textDarkSecondary,
              fontSize: 12,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.textDarkSecondary),
          onTap: () => _showSlowModeDialog(context),
        ),

        // Who can add members
        ListTile(
          leading: const Icon(Icons.person_add),
          title: const Text('Who Can Add Members'),
          subtitle: Text(
            group.whoCanAddMembers.displayName,
            style: TextStyle(
              color: AppColors.textDarkSecondary,
              fontSize: 12,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.textDarkSecondary),
          onTap: () => _showWhoCanAddDialog(context),
        ),

        // Who can edit info
        ListTile(
          leading: const Icon(Icons.edit),
          title: const Text('Who Can Change Info'),
          subtitle: Text(
            group.whoCanChangeInfo.displayName,
            style: TextStyle(
              color: AppColors.textDarkSecondary,
              fontSize: 12,
            ),
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.textDarkSecondary),
          onTap: () => _showWhoCanEditDialog(context),
        ),

        // Who can send messages
        ListTile(
          leading: const Icon(Icons.message),
          title: const Text('Who Can Send Messages'),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.whoCanSend.displayName,
                style: TextStyle(
                  color: AppColors.textDarkSecondary,
                  fontSize: 12,
                ),
              ),
              if (group.whoCanSend == WhoCanSendMessages.selectedOnly &&
                  group.selectedSenders.isNotEmpty)
                Text(
                  '${group.selectedSenders.length} member(s) can send',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
          trailing: Icon(Icons.chevron_right, color: AppColors.textDarkSecondary),
          onTap: () => _showWhoCanSendDialog(context),
        ),

        // Message history visible
        SwitchListTile(
          secondary: const Icon(Icons.history),
          title: const Text('Message History'),
          subtitle: Text(
            'Show history to new members',
            style: TextStyle(
              color: AppColors.textDarkSecondary,
              fontSize: 12,
            ),
          ),
          value: group.messageHistoryVisible,
          onChanged: onHistoryVisibleChanged,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }

  void _showSlowModeDialog(BuildContext context) {
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
              const Text(
                'Slow Mode',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Set the minimum time between messages',
                style: TextStyle(
                  color: AppColors.textDarkSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              _SlowModeOption(
                label: 'Off',
                seconds: 0,
                isSelected: group.slowModeSeconds == 0,
                onTap: () {
                  Navigator.pop(context);
                  onSlowModeChanged(0);
                },
              ),
              _SlowModeOption(
                label: '10 seconds',
                seconds: 10,
                isSelected: group.slowModeSeconds == 10,
                onTap: () {
                  Navigator.pop(context);
                  onSlowModeChanged(10);
                },
              ),
              _SlowModeOption(
                label: '30 seconds',
                seconds: 30,
                isSelected: group.slowModeSeconds == 30,
                onTap: () {
                  Navigator.pop(context);
                  onSlowModeChanged(30);
                },
              ),
              _SlowModeOption(
                label: '1 minute',
                seconds: 60,
                isSelected: group.slowModeSeconds == 60,
                onTap: () {
                  Navigator.pop(context);
                  onSlowModeChanged(60);
                },
              ),
              _SlowModeOption(
                label: '5 minutes',
                seconds: 300,
                isSelected: group.slowModeSeconds == 300,
                onTap: () {
                  Navigator.pop(context);
                  onSlowModeChanged(300);
                },
              ),
              _SlowModeOption(
                label: '15 minutes',
                seconds: 900,
                isSelected: group.slowModeSeconds == 900,
                onTap: () {
                  Navigator.pop(context);
                  onSlowModeChanged(900);
                },
              ),
              _SlowModeOption(
                label: '1 hour',
                seconds: 3600,
                isSelected: group.slowModeSeconds == 3600,
                onTap: () {
                  Navigator.pop(context);
                  onSlowModeChanged(3600);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showWhoCanAddDialog(BuildContext context) {
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
              const Text(
                'Who Can Add Members',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: group.whoCanAddMembers == WhoCanAddMembers.everyone
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                title: const Text('Everyone'),
                subtitle: Text(
                  'All members can add new members',
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onWhoCanAddChanged(WhoCanAddMembers.everyone);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: group.whoCanAddMembers == WhoCanAddMembers.adminsOnly
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                title: const Text('Admins Only'),
                subtitle: Text(
                  'Only admins and owner can add members',
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onWhoCanAddChanged(WhoCanAddMembers.adminsOnly);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showWhoCanEditDialog(BuildContext context) {
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
              const Text(
                'Who Can Change Info',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: group.whoCanChangeInfo == WhoCanChangeInfo.everyone
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                title: const Text('Everyone'),
                subtitle: Text(
                  'All members can change name and description',
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onWhoCanEditChanged(WhoCanChangeInfo.everyone);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: group.whoCanChangeInfo == WhoCanChangeInfo.adminsOnly
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                title: const Text('Admins Only'),
                subtitle: Text(
                  'Only admins and owner can change info',
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onWhoCanEditChanged(WhoCanChangeInfo.adminsOnly);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  void _showWhoCanSendDialog(BuildContext context) {
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
              const Text(
                'Who Can Send Messages',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Control who can send messages in this group',
                style: TextStyle(
                  color: AppColors.textDarkSecondary,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: group.whoCanSend == WhoCanSendMessages.everyone
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                title: const Text('Everyone'),
                subtitle: Text(
                  'All members can send messages',
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onWhoCanSendChanged(WhoCanSendMessages.everyone);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: group.whoCanSend == WhoCanSendMessages.adminsOnly
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                title: const Text('Admins Only'),
                subtitle: Text(
                  'Only admins can send (broadcast mode)',
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  onWhoCanSendChanged(WhoCanSendMessages.adminsOnly);
                },
              ),
              ListTile(
                leading: Icon(
                  Icons.check,
                  color: group.whoCanSend == WhoCanSendMessages.selectedOnly
                      ? AppColors.primary
                      : Colors.transparent,
                ),
                title: const Text('Selected Members'),
                subtitle: Text(
                  'Only selected members can send',
                  style: TextStyle(
                    color: AppColors.textDarkSecondary,
                    fontSize: 12,
                  ),
                ),
                trailing: group.whoCanSend == WhoCanSendMessages.selectedOnly &&
                        onManageSelectedSenders != null
                    ? TextButton(
                        onPressed: () {
                          Navigator.pop(context);
                          onManageSelectedSenders!();
                        },
                        child: const Text('Manage'),
                      )
                    : null,
                onTap: () {
                  Navigator.pop(context);
                  onWhoCanSendChanged(WhoCanSendMessages.selectedOnly);
                  // If switching to selected mode, offer to manage senders
                  if (group.whoCanSend != WhoCanSendMessages.selectedOnly &&
                      onManageSelectedSenders != null) {
                    Future.delayed(const Duration(milliseconds: 300), () {
                      onManageSelectedSenders!();
                    });
                  }
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }
}

/// Slow mode option tile
class _SlowModeOption extends StatelessWidget {
  final String label;
  final int seconds;
  final bool isSelected;
  final VoidCallback onTap;

  const _SlowModeOption({
    required this.label,
    required this.seconds,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        Icons.check,
        color: isSelected ? AppColors.primary : Colors.transparent,
      ),
      title: Text(label),
      onTap: onTap,
    );
  }
}

/// Section for invite link management
class _InviteLinksSection extends StatelessWidget {
  final Group group;
  final VoidCallback onManageLinks;

  const _InviteLinksSection({
    required this.group,
    required this.onManageLinks,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.link, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Invite Links',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                if (group.hasAdvancedInviteLinks) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'Advanced',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('Manage Invite Links'),
            subtitle: Text(
              group.hasAdvancedInviteLinks
                  ? 'Create links with expiry and usage limits'
                  : 'Create and share invite links',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: onManageLinks,
          ),
        ],
      ),
    );
  }
}

/// Section for admin action log
class _AdminLogSection extends StatelessWidget {
  final Group group;
  final VoidCallback onViewLog;

  const _AdminLogSection({
    required this.group,
    required this.onViewLog,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Icon(Icons.history, size: 20, color: AppColors.primary),
                const SizedBox(width: 8),
                Text(
                  'Admin Log',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.history),
            title: const Text('View Admin Actions'),
            subtitle: const Text('See all administrative actions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: onViewLog,
          ),
        ],
      ),
    );
  }
}

/// Dialog for adding a member by contact or node ID
class _AddMemberDialog extends ConsumerStatefulWidget {
  final Set<String> existingMemberIds;
  final Future<void> Function(Contact contact) onSelectContact;
  final Future<void> Function(String nodeId) onEnterNodeId;

  const _AddMemberDialog({
    required this.existingMemberIds,
    required this.onSelectContact,
    required this.onEnterNodeId,
  });

  @override
  ConsumerState<_AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends ConsumerState<_AddMemberDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nodeIdController = TextEditingController();
  String? _nodeIdError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nodeIdController.dispose();
    super.dispose();
  }

  void _validateAndSubmitNodeId() {
    final nodeId = _nodeIdController.text.trim();
    if (nodeId.isEmpty) {
      setState(() => _nodeIdError = 'Please enter a Node ID');
      return;
    }

    final normalizedId = NodeIdUtils.normalize(nodeId);
    if (!NodeIdUtils.isValid(normalizedId)) {
      setState(() => _nodeIdError = 'Invalid format. Use UUID or 64-char hex.');
      return;
    }

    if (widget.existingMemberIds.contains(normalizedId)) {
      setState(() => _nodeIdError = 'This user is already a member');
      return;
    }

    widget.onEnterNodeId(normalizedId);
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(contactsProvider);

    return AlertDialog(
      title: const Text('Add Member'),
      contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
      content: SizedBox(
        width: double.maxFinite,
        height: 350,
        child: Column(
          children: [
            TabBar(
              controller: _tabController,
              labelColor: AppColors.primary,
              unselectedLabelColor: AppColors.textDarkSecondary,
              indicatorColor: AppColors.primary,
              tabs: const [
                Tab(text: 'Contacts'),
                Tab(text: 'Node ID'),
              ],
            ),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // Contacts tab
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: contactsAsync.when(
                      loading: () =>
                          const Center(child: CircularProgressIndicator()),
                      error: (e, _) => Center(child: Text('Error: $e')),
                      data: (contacts) {
                        final availableContacts = contacts
                            .where((c) =>
                                !widget.existingMemberIds.contains(c.nodeId))
                            .toList();

                        if (availableContacts.isEmpty) {
                          return const Center(
                            child: Text(
                              'No contacts available.\nUse Node ID tab to add by ID.',
                              textAlign: TextAlign.center,
                            ),
                          );
                        }

                        return ListView.builder(
                          shrinkWrap: true,
                          itemCount: availableContacts.length,
                          itemBuilder: (context, index) {
                            final contact = availableContacts[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  (contact.displayName ?? contact.shortId)[0]
                                      .toUpperCase(),
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                              title:
                                  Text(contact.displayName ?? contact.shortId),
                              subtitle: Text(
                                contact.shortId,
                                style: TextStyle(
                                  color: Colors.grey[400],
                                  fontSize: 12,
                                ),
                              ),
                              onTap: () => widget.onSelectContact(contact),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  // Node ID tab
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Enter the Node ID of the person you want to invite:',
                          style: TextStyle(fontSize: 14),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _nodeIdController,
                          decoration: InputDecoration(
                            labelText: 'Node ID',
                            hintText: 'xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx',
                            errorText: _nodeIdError,
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.paste),
                              onPressed: () async {
                                final data =
                                    await Clipboard.getData('text/plain');
                                if (data?.text != null) {
                                  _nodeIdController.text = data!.text!;
                                  setState(() => _nodeIdError = null);
                                }
                              },
                            ),
                          ),
                          onChanged: (_) =>
                              setState(() => _nodeIdError = null),
                          maxLines: 2,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Accepts UUID format or 64-character hex',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textDarkSecondary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _validateAndSubmitNodeId,
                            icon: const Icon(Icons.person_add),
                            label: const Text('Invite'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
      ],
    );
  }
}

/// Sheet for managing selected senders
class _SelectedSendersSheet extends StatelessWidget {
  final Group group;
  final ScrollController scrollController;
  final Future<void> Function(String memberId, bool isSelected) onToggleSender;

  const _SelectedSendersSheet({
    required this.group,
    required this.scrollController,
    required this.onToggleSender,
  });

  @override
  Widget build(BuildContext context) {
    // Filter out admins and owner (they can always send)
    final selectableMembers = group.members.where((m) =>
        m.role == GroupRole.member && m.nodeId != group.creatorId).toList();

    return Column(
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
        const Text(
          'Manage Selected Senders',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Select members who can send messages',
          style: TextStyle(
            color: AppColors.textDarkSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 16, color: AppColors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Admins and owner can always send messages',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: selectableMembers.isEmpty
              ? Center(
                  child: Text(
                    'No regular members to select',
                    style: TextStyle(
                      color: AppColors.textDarkSecondary,
                      fontSize: 14,
                    ),
                  ),
                )
              : ListView.builder(
                  controller: scrollController,
                  itemCount: selectableMembers.length,
                  itemBuilder: (context, index) {
                    final member = selectableMembers[index];
                    final isSelected =
                        group.selectedSenders.contains(member.nodeId);
                    final shortId = member.nodeId.length >= 8
                        ? member.nodeId.substring(0, 8)
                        : member.nodeId;

                    return CheckboxListTile(
                      value: isSelected,
                      onChanged: (value) {
                        onToggleSender(member.nodeId, value ?? false);
                      },
                      title: Text(
                        member.displayName ?? shortId,
                        style: const TextStyle(fontSize: 15),
                      ),
                      subtitle: Text(
                        '$shortId...',
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppColors.textDarkSecondary,
                        ),
                      ),
                      secondary: CircleAvatar(
                        backgroundColor: AppColors.primary.withOpacity(0.2),
                        child: Text(
                          (member.displayName ?? shortId)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                      activeColor: AppColors.primary,
                    );
                  },
                ),
        ),
      ],
    );
  }
}
