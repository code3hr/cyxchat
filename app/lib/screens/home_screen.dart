import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import '../providers/conversation_provider.dart';
import '../providers/identity_provider.dart';
import '../providers/connection_provider.dart';
import '../ffi/bindings.dart';
import '../models/models.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _ChatsTab(),
          ContactsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_outline),
            selectedIcon: Icon(Icons.people),
            label: 'Contacts',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

class _ChatsTab extends ConsumerWidget {
  const _ChatsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversationsAsync = ref.watch(conversationsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CyxChat'),
        actions: [
          // Network status indicator
          const _NetworkStatusIndicator(),
          IconButton(
            icon: const Icon(Icons.search),
            onPressed: () {
              // TODO: Search
            },
          ),
        ],
      ),
      body: conversationsAsync.when(
        data: (conversations) {
          if (conversations.isEmpty) {
            return const _EmptyChats();
          }
          return ListView.builder(
            itemCount: conversations.length,
            itemBuilder: (context, index) {
              return _ConversationTile(conversation: conversations[index]);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stack) => Center(
          child: Text('Error: $error'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ContactsScreen(selectMode: true),
            ),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'No conversations yet',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Start a new chat with the + button',
            style: TextStyle(
              color: Colors.grey[500],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationTile extends ConsumerWidget {
  final Conversation conversation;

  const _ConversationTile({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        child: Text(
          conversation.title[0].toUpperCase(),
          style: TextStyle(
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ),
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              conversation.title,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (conversation.isPinned)
            const Icon(Icons.push_pin, size: 16),
          if (conversation.isMuted)
            const Icon(Icons.volume_off, size: 16),
        ],
      ),
      subtitle: Text(
        conversation.subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Colors.grey[600],
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            conversation.lastActivityString,
            style: TextStyle(
              fontSize: 12,
              color: conversation.unreadCount > 0
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[500],
            ),
          ),
          if (conversation.unreadCount > 0)
            Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                conversation.unreadCount.toString(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatScreen(conversationId: conversation.id),
          ),
        );
      },
      onLongPress: () {
        _showConversationOptions(context, ref);
      },
    );
  }

  void _showConversationOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: Icon(
                  conversation.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                ),
                title: Text(conversation.isPinned ? 'Unpin' : 'Pin'),
                onTap: () {
                  ref.read(chatActionsProvider).togglePin(conversation.id);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(
                  conversation.isMuted ? Icons.volume_up : Icons.volume_off,
                ),
                title: Text(conversation.isMuted ? 'Unmute' : 'Mute'),
                onTap: () {
                  ref.read(chatActionsProvider).toggleMute(conversation.id);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('Delete', style: TextStyle(color: Colors.red)),
                onTap: () {
                  // TODO: Delete conversation
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Network status indicator widget
class _NetworkStatusIndicator extends StatelessWidget {
  const _NetworkStatusIndicator();

  @override
  Widget build(BuildContext context) {
    return provider.Consumer<ConnectionProvider>(
      builder: (context, connection, child) {
        if (!connection.initialized) {
          return const SizedBox.shrink();
        }

        final status = connection.networkStatus;
        final Color color;
        final IconData icon;
        final String tooltip;

        if (!status.stunComplete) {
          color = Colors.orange;
          icon = Icons.wifi_find;
          tooltip = 'Discovering network...';
        } else if (status.activeConnections == 0) {
          color = Colors.grey;
          icon = Icons.wifi_off;
          tooltip = 'No active connections';
        } else if (status.relayConnections > 0 &&
            status.relayConnections == status.activeConnections) {
          color = Colors.amber;
          icon = Icons.swap_horiz;
          tooltip = '${status.activeConnections} connections (all relayed)';
        } else if (status.relayConnections > 0) {
          color = Colors.lightGreen;
          icon = Icons.wifi;
          tooltip =
              '${status.activeConnections} connections (${status.relayConnections} relayed)';
        } else {
          color = Colors.green;
          icon = Icons.wifi;
          tooltip = '${status.activeConnections} direct connections';
        }

        return Tooltip(
          message: tooltip,
          child: IconButton(
            icon: Icon(icon, color: color),
            onPressed: () => _showNetworkDetails(context, status),
          ),
        );
      },
    );
  }

  void _showNetworkDetails(BuildContext context, NetworkStatus status) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Network Status'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusRow(
              label: 'Public Address',
              value: status.publicAddress ?? 'Discovering...',
            ),
            _StatusRow(
              label: 'NAT Type',
              value: status.natTypeName,
            ),
            _StatusRow(
              label: 'Active Connections',
              value: status.activeConnections.toString(),
            ),
            _StatusRow(
              label: 'Direct',
              value: status.directConnections.toString(),
            ),
            _StatusRow(
              label: 'Relayed',
              value: status.relayConnections.toString(),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String value;

  const _StatusRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 16),
          Flexible(
            child: Text(
              value,
              style: TextStyle(color: Colors.grey[600]),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}
