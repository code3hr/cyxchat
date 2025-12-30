import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../providers/conversation_provider.dart';
import '../providers/mail_provider.dart';
import '../models/models.dart';
import 'chat_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';
import 'mail_inbox_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final totalUnreadAsync = ref.watch(totalUnreadProvider);
    final unreadCount = totalUnreadAsync.valueOrNull ?? 0;

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: const [
          _ChatsTab(),
          MailInboxScreen(),
          ContactsScreen(),
          SettingsScreen(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppColors.bgDarkSecondary,
          border: Border(
            top: BorderSide(
              color: AppColors.bgDarkTertiary,
              width: 1,
            ),
          ),
        ),
        child: NavigationBar(
          selectedIndex: _selectedIndex,
          onDestinationSelected: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unreadCount > 0,
                backgroundColor: AppColors.accent,
                label: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                child: const Icon(Icons.mail_outline_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: unreadCount > 0,
                backgroundColor: AppColors.accent,
                label: Text(
                  unreadCount > 99 ? '99+' : unreadCount.toString(),
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
                child: const Icon(Icons.mail_rounded),
              ),
              label: 'Mail',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Contacts',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_outlined),
              selectedIcon: Icon(Icons.settings_rounded),
              label: 'Settings',
            ),
          ],
        ),
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
      body: CustomScrollView(
        slivers: [
          // Custom app bar with gradient
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: AppColors.bgDark,
            toolbarHeight: 60,
            title: Row(
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Image.asset(
                    'assets/logo.png',
                    fit: BoxFit.contain,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'CyxChat',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            actions: [
              const _NetworkStatusChip(),
              const SizedBox(width: 4),
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.bgDarkSecondary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.search_rounded, size: 18),
                ),
                onPressed: () {
                  // TODO: Search
                },
              ),
              const SizedBox(width: 8),
            ],
          ),
          // Content
          conversationsAsync.when(
            data: (conversations) {
              if (conversations.isEmpty) {
                return const SliverFillRemaining(
                  child: _EmptyChats(),
                );
              }
              return SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _ConversationCard(conversation: conversations[index]),
                      );
                    },
                    childCount: conversations.length,
                  ),
                ),
              );
            },
            loading: () => SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 40,
                      height: 40,
                      child: CircularProgressIndicator(
                        strokeWidth: 3,
                        valueColor: AlwaysStoppedAnimation(
                          AppColors.primary.withOpacity(0.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading conversations...',
                      style: TextStyle(
                        color: AppColors.textDarkSecondary.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            error: (error, stack) => SliverFillRemaining(
              child: _ErrorState(error: error.toString()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'chats_fab',
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ContactsScreen(selectMode: true),
            ),
          );
        },
        child: const Icon(Icons.edit_rounded),
      ),
    );
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.15),
                    AppColors.accent.withOpacity(0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: AppColors.primary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap the compose button to start\na secure conversation',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.4,
                color: AppColors.textDarkSecondary.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.bgDarkSecondary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: AppColors.bgDarkTertiary,
                  width: 1,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 14,
                    color: AppColors.accentGreen.withOpacity(0.8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'End-to-end encrypted',
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.textDarkSecondary.withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;

  const _ErrorState({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: AppColors.error.withOpacity(0.15),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.error_outline_rounded,
                size: 32,
                color: AppColors.error,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Failed to load chats',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textDarkSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationCard extends ConsumerWidget {
  final Conversation conversation;

  const _ConversationCard({required this.conversation});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasUnread = conversation.unreadCount > 0;

    return Material(
      color: AppColors.bgDarkSecondary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => ChatScreen(conversationId: conversation.id),
            ),
          );
        },
        onLongPress: () => _showConversationOptions(context, ref),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Avatar
              _ConversationAvatar(
                title: conversation.title,
                hasUnread: hasUnread,
              ),
              const SizedBox(width: 14),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row
                    Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  conversation.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                                    color: AppColors.textDark,
                                  ),
                                ),
                              ),
                              if (conversation.isPinned) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.push_pin_rounded,
                                  size: 14,
                                  color: AppColors.primary.withOpacity(0.7),
                                ),
                              ],
                              if (conversation.isMuted) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.volume_off_rounded,
                                  size: 14,
                                  color: AppColors.textDarkSecondary.withOpacity(0.5),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          conversation.lastActivityString,
                          style: TextStyle(
                            fontSize: 12,
                            color: hasUnread
                                ? AppColors.accent
                                : AppColors.textDarkSecondary.withOpacity(0.6),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    // Subtitle row
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              color: hasUnread
                                  ? AppColors.textDarkSecondary
                                  : AppColors.textDarkSecondary.withOpacity(0.6),
                            ),
                          ),
                        ),
                        if (hasUnread) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [AppColors.primary, AppColors.primaryLight],
                              ),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              conversation.unreadCount > 99
                                  ? '99+'
                                  : conversation.unreadCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConversationOptions(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.bgDarkSecondary,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: AppColors.bgDarkTertiary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              _BottomSheetOption(
                icon: conversation.isPinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
                label: conversation.isPinned ? 'Unpin' : 'Pin',
                onTap: () {
                  ref.read(chatActionsProvider).togglePin(conversation.id);
                  Navigator.pop(context);
                },
              ),
              _BottomSheetOption(
                icon: conversation.isMuted
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
                label: conversation.isMuted ? 'Unmute' : 'Mute',
                onTap: () {
                  ref.read(chatActionsProvider).toggleMute(conversation.id);
                  Navigator.pop(context);
                },
              ),
              _BottomSheetOption(
                icon: Icons.archive_outlined,
                label: 'Archive',
                onTap: () {
                  Navigator.pop(context);
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: AppColors.bgDarkTertiary),
              ),
              _BottomSheetOption(
                icon: Icons.delete_outline_rounded,
                label: 'Delete',
                isDestructive: true,
                onTap: () {
                  Navigator.pop(context);
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

class _ConversationAvatar extends StatelessWidget {
  final String title;
  final bool hasUnread;

  const _ConversationAvatar({
    required this.title,
    required this.hasUnread,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: hasUnread
                  ? [AppColors.primary, AppColors.primaryLight]
                  : [AppColors.bgDarkTertiary, AppColors.bgDarkTertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: Text(
              title.isNotEmpty ? title[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: hasUnread ? Colors.white : AppColors.textDarkSecondary,
              ),
            ),
          ),
        ),
        // Online indicator
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: AppColors.accentGreen,
              shape: BoxShape.circle,
              border: Border.all(
                color: AppColors.bgDarkSecondary,
                width: 2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BottomSheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDestructive;

  const _BottomSheetOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? AppColors.error : AppColors.textDark;

    return ListTile(
      leading: Icon(icon, color: color),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

/// Network status chip widget
class _NetworkStatusChip extends StatelessWidget {
  const _NetworkStatusChip();

  @override
  Widget build(BuildContext context) {
    // Placeholder - will connect to actual network status
    const isConnected = false;
    const statusColor = AppColors.textDarkSecondary;
    const statusText = 'Offline';

    return GestureDetector(
      onTap: () => _showNetworkDetails(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.bgDarkSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: AppColors.bgDarkTertiary,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: isConnected ? AppColors.accentGreen : statusColor,
                shape: BoxShape.circle,
                boxShadow: isConnected
                    ? [
                        BoxShadow(
                          color: AppColors.accentGreen.withOpacity(0.5),
                          blurRadius: 6,
                          spreadRadius: 1,
                        ),
                      ]
                    : null,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              statusText,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: statusColor.withOpacity(0.8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showNetworkDetails(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.bgDarkTertiary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.wifi_off_rounded,
                size: 24,
                color: AppColors.textDarkSecondary,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Text('Network Status'),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _NetworkInfoRow(
              label: 'Status',
              value: 'Disconnected',
              valueColor: AppColors.textDarkSecondary,
            ),
            const SizedBox(height: 12),
            _NetworkInfoRow(
              label: 'Peers',
              value: '0 connected',
            ),
            const SizedBox(height: 12),
            _NetworkInfoRow(
              label: 'Relay',
              value: 'Not available',
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgDarkTertiary.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.accent.withOpacity(0.8),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Connect to the mesh network to start chatting securely.',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.textDarkSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
  }
}

class _NetworkInfoRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _NetworkInfoRow({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textDarkSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: valueColor ?? AppColors.textDark,
          ),
        ),
      ],
    );
  }
}
