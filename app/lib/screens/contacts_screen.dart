import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/contact.dart';
import '../providers/conversation_provider.dart';
import '../providers/contact_provider.dart';
import 'chat_screen.dart';
import 'add_contact_screen.dart';
import 'mail_compose_screen.dart';

class ContactsScreen extends ConsumerWidget {
  final bool selectMode;

  const ContactsScreen({super.key, this.selectMode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(contactsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(selectMode ? 'Select Contact' : 'Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddContactScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: contactsAsync.when(
        data: (contacts) => contacts.isEmpty
            ? const _EmptyContacts()
            : ListView.builder(
                itemCount: contacts.length,
                itemBuilder: (context, index) {
                  return _ContactTile(
                    contact: contacts[index],
                    onTap: () => _onContactTap(context, ref, contacts[index]),
                  );
                },
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text('Error: $error')),
      ),
    );
  }

  void _onContactTap(BuildContext context, WidgetRef ref, Contact contact) async {
    final conversation = await ref.read(chatActionsProvider)
        .startConversation(contact.nodeId);

    if (context.mounted) {
      if (selectMode) {
        Navigator.pop(context);
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatScreen(conversationId: conversation.id),
        ),
      );
    }
  }
}

class _EmptyContacts extends StatelessWidget {
  const _EmptyContacts();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.people_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No contacts yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add a contact using the + button',
            style: TextStyle(
              color: Colors.grey[500],
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const AddContactScreen(),
                ),
              );
            },
            icon: const Icon(Icons.person_add),
            label: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }
}

class _ContactTile extends ConsumerWidget {
  final Contact contact;
  final VoidCallback onTap;

  const _ContactTile({
    required this.contact,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              contact.displayText[0].toUpperCase(),
              style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          if (contact.isOnline)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(contact.displayText),
          ),
          if (contact.verified)
            Icon(
              Icons.verified,
              size: 16,
              color: Theme.of(context).colorScheme.primary,
            ),
        ],
      ),
      subtitle: Text(
        contact.statusText ?? contact.presence.displayName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: Colors.grey[600]),
      ),
      onTap: onTap,
      onLongPress: () => _showContactOptions(context, ref),
    );
  }

  void _showContactOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.mail_outline),
                title: const Text('Send Email'),
                onTap: () {
                  Navigator.pop(sheetContext);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => MailComposeScreen(
                        toNodeId: contact.nodeId,
                        toName: contact.displayText,
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: Text(contact.verified ? 'Unverify' : 'Verify'),
                onTap: () {
                  ref.read(contactActionsProvider).toggleVerified(contact.nodeId);
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: Icon(
                  contact.blocked ? Icons.person : Icons.block,
                ),
                title: Text(contact.blocked ? 'Unblock' : 'Block'),
                onTap: () {
                  ref.read(contactActionsProvider).toggleBlocked(contact.nodeId);
                  Navigator.pop(sheetContext);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  ref.read(contactActionsProvider).deleteContact(contact.nodeId);
                  Navigator.pop(sheetContext);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
