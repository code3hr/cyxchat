import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/contact.dart';
import '../providers/group_provider.dart';
import 'group_chat_screen.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final Set<String> _selectedContactIds = {};
  bool _isCreating = false;

  // TODO: Replace with actual contacts provider
  final List<Contact> _contacts = [];

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('New Group'),
        actions: [
          TextButton(
            onPressed: _canCreate ? _createGroup : null,
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Create',
                    style: TextStyle(
                      color: _canCreate ? AppColors.primary : Colors.grey,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Group info section
          Container(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Group avatar placeholder
                Center(
                  child: Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppColors.primary, AppColors.primaryLight],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Icon(
                          Icons.group,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: AppColors.bgDarkSecondary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: AppColors.bgDark,
                              width: 2,
                            ),
                          ),
                          child: const Icon(
                            Icons.camera_alt,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                // Group name
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    hintText: 'Group name',
                    prefixIcon: Icon(Icons.group),
                  ),
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.words,
                ),
                const SizedBox(height: 12),

                // Description (optional)
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    hintText: 'Description (optional)',
                    prefixIcon: Icon(Icons.description_outlined),
                  ),
                  maxLines: 2,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Members section header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Text(
                  'Add Members',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (_selectedContactIds.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_selectedContactIds.length} selected',
                      style: TextStyle(
                        color: AppColors.primary,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Contacts list
          Expanded(
            child: _contacts.isEmpty
                ? _buildEmptyContacts()
                : ListView.builder(
                    itemCount: _contacts.length,
                    itemBuilder: (context, index) {
                      final contact = _contacts[index];
                      final isSelected =
                          _selectedContactIds.contains(contact.nodeId);
                      return _ContactSelectTile(
                        contact: contact,
                        isSelected: isSelected,
                        onToggle: () => _toggleContact(contact.nodeId),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyContacts() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 48,
            color: AppColors.textDarkSecondary,
          ),
          const SizedBox(height: 12),
          Text(
            'No contacts to add',
            style: TextStyle(
              color: AppColors.textDarkSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'You can add members later',
            style: TextStyle(
              color: AppColors.textDarkSecondary.withOpacity(0.7),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  bool get _canCreate => _nameController.text.trim().isNotEmpty && !_isCreating;

  void _toggleContact(String nodeId) {
    setState(() {
      if (_selectedContactIds.contains(nodeId)) {
        _selectedContactIds.remove(nodeId);
      } else {
        _selectedContactIds.add(nodeId);
      }
    });
  }

  Future<void> _createGroup() async {
    if (!_canCreate) return;

    setState(() => _isCreating = true);

    try {
      final group = await ref.read(groupActionsProvider).createGroup(
            _nameController.text.trim(),
            description: _descriptionController.text.trim().isEmpty
                ? null
                : _descriptionController.text.trim(),
          );

      // Invite selected members
      for (final nodeId in _selectedContactIds) {
        await ref.read(groupActionsProvider).inviteMember(group.id, nodeId);
      }

      if (mounted) {
        // Navigate to group chat
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => GroupChatScreen(groupId: group.id),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }
}

class _ContactSelectTile extends StatelessWidget {
  final Contact contact;
  final bool isSelected;
  final VoidCallback onToggle;

  const _ContactSelectTile({
    required this.contact,
    required this.isSelected,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: isSelected
                ? AppColors.primary
                : AppColors.bgDarkTertiary,
            child: Text(
              contact.displayText[0].toUpperCase(),
              style: const TextStyle(color: Colors.white),
            ),
          ),
          if (isSelected)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: AppColors.success,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: AppColors.bgDark,
                    width: 2,
                  ),
                ),
                child: const Icon(
                  Icons.check,
                  size: 10,
                  color: Colors.black,
                ),
              ),
            ),
        ],
      ),
      title: Text(contact.displayText),
      subtitle: Text(
        contact.statusText ?? contact.presence.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: AppColors.textDarkSecondary),
      ),
      trailing: Checkbox(
        value: isSelected,
        onChanged: (_) => onToggle(),
        activeColor: AppColors.primary,
      ),
      onTap: onToggle,
    );
  }
}
