import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/group_service.dart';

/// Screen for viewing admin action log for a group
class AdminLogScreen extends StatefulWidget {
  final String groupId;
  final String groupName;

  const AdminLogScreen({
    super.key,
    required this.groupId,
    required this.groupName,
  });

  @override
  State<AdminLogScreen> createState() => _AdminLogScreenState();
}

class _AdminLogScreenState extends State<AdminLogScreen> {
  List<AdminAction> _actions = [];
  bool _isLoading = true;
  String? _filterAdminId;
  AdminActionType? _filterType;
  final _groupService = GroupService.instance;

  @override
  void initState() {
    super.initState();
    _loadActions();
  }

  Future<void> _loadActions() async {
    setState(() => _isLoading = true);

    try {
      List<AdminAction> actions;

      if (_filterAdminId != null) {
        actions = await _groupService.getAdminActionsByAdmin(
          widget.groupId,
          _filterAdminId!,
        );
      } else if (_filterType != null) {
        actions = await _groupService.getAdminActionsByType(
          widget.groupId,
          _filterType!,
        );
      } else {
        actions = await _groupService.getAdminActions(widget.groupId);
      }

      setState(() {
        _actions = actions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load actions: $e')),
        );
      }
    }
  }

  void _showFilterDialog() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _FilterSheet(
        currentType: _filterType,
        onTypeSelected: (type) {
          Navigator.pop(context);
          setState(() {
            _filterType = type;
            _filterAdminId = null;
          });
          _loadActions();
        },
        onClear: () {
          Navigator.pop(context);
          setState(() {
            _filterType = null;
            _filterAdminId = null;
          });
          _loadActions();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Admin Log'),
            Text(
              widget.groupName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Badge(
              isLabelVisible: _filterType != null || _filterAdminId != null,
              child: const Icon(Icons.filter_list),
            ),
            onPressed: _showFilterDialog,
            tooltip: 'Filter',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadActions,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _actions.isEmpty
              ? _buildEmptyState()
              : _buildActionList(),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.history,
            size: 64,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            'No admin actions',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
                ),
          ),
          if (_filterType != null || _filterAdminId != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                setState(() {
                  _filterType = null;
                  _filterAdminId = null;
                });
                _loadActions();
              },
              child: const Text('Clear filters'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionList() {
    // Group actions by date
    final groupedActions = <String, List<AdminAction>>{};
    for (final action in _actions) {
      final date = DateFormat.yMMMd().format(action.timestamp);
      groupedActions.putIfAbsent(date, () => []).add(action);
    }

    return ListView.builder(
      itemCount: groupedActions.length,
      itemBuilder: (context, index) {
        final date = groupedActions.keys.elementAt(index);
        final actions = groupedActions[date]!;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                date,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ),
            ...actions.map((action) => _AdminActionTile(
                  action: action,
                  onAdminTap: () {
                    setState(() {
                      _filterAdminId = action.adminId;
                      _filterType = null;
                    });
                    _loadActions();
                  },
                )),
          ],
        );
      },
    );
  }
}

class _AdminActionTile extends StatelessWidget {
  final AdminAction action;
  final VoidCallback onAdminTap;

  const _AdminActionTile({
    required this.action,
    required this.onAdminTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final time = DateFormat.Hm().format(action.timestamp);
    final shortAdminId = action.adminId.substring(0, 8);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _getActionColor(action.actionType, theme),
          child: Text(
            action.actionType.icon,
            style: const TextStyle(fontSize: 18),
          ),
        ),
        title: Text(
          action.getDescription(adminName: shortAdminId),
          style: theme.textTheme.bodyMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 4),
                Text(
                  time,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 12),
                GestureDetector(
                  onTap: onAdminTap,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person,
                        size: 14,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        shortAdminId,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (action.oldValue != null || action.newValue != null) ...[
              const SizedBox(height: 4),
              if (action.oldValue != null)
                Text(
                  'From: ${action.oldValue}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (action.newValue != null)
                Text(
                  'To: ${action.newValue}',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.green,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ],
        ),
        isThreeLine: action.oldValue != null || action.newValue != null,
      ),
    );
  }

  Color _getActionColor(AdminActionType type, ThemeData theme) {
    switch (type) {
      case AdminActionType.kick:
      case AdminActionType.ban:
      case AdminActionType.messageDeleted:
      case AdminActionType.linkRevoked:
        return theme.colorScheme.error.withValues(alpha: 0.2);
      case AdminActionType.promote:
      case AdminActionType.unban:
      case AdminActionType.memberInvited:
        return Colors.green.withValues(alpha: 0.2);
      case AdminActionType.demote:
      case AdminActionType.restrictionsChanged:
        return Colors.orange.withValues(alpha: 0.2);
      default:
        return theme.colorScheme.primary.withValues(alpha: 0.2);
    }
  }
}

class _FilterSheet extends StatelessWidget {
  final AdminActionType? currentType;
  final ValueChanged<AdminActionType?> onTypeSelected;
  final VoidCallback onClear;

  const _FilterSheet({
    required this.currentType,
    required this.onTypeSelected,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Filter by action type',
                style: theme.textTheme.titleMedium,
              ),
              if (currentType != null)
                TextButton(
                  onPressed: onClear,
                  child: const Text('Clear'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: AdminActionType.values.map((type) {
              final isSelected = currentType == type;
              return FilterChip(
                label: Text('${type.icon} ${type.description}'),
                selected: isSelected,
                onSelected: (_) => onTypeSelected(type),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
