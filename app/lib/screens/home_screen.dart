import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../providers/conversation_provider.dart';
import '../providers/network_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/group_ffi_provider.dart';
import '../services/group_service.dart';
import '../models/models.dart';
import '../models/invite_link.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'create_group_screen.dart';
import 'contacts_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;
  bool _autoConnectAttempted = false;

  @override
  void initState() {
    super.initState();
    // Auto-connect on startup after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoConnect();
    });
  }

  Future<void> _autoConnect() async {
    if (_autoConnectAttempted) return;
    _autoConnectAttempted = true;

    // Wait for settings to load from SharedPreferences
    await Future.delayed(const Duration(milliseconds: 500));

    final connectionState = ref.read(connectionNotifierProvider);
    if (!connectionState.initialized) {
      final settings = ref.read(settingsProvider);
      debugPrint('CyxChat: Bootstrap server = "${settings.bootstrapServer}"');

      // Auto-connect to network
      final success = await ref.read(connectionActionsProvider).connect();
      if (mounted && success) {
        debugPrint('CyxChat: Auto-connected to network');
      }
    }
  }


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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.chat_bubble_outline_rounded),
              selectedIcon: Icon(Icons.chat_bubble_rounded),
              label: 'Chats',
            ),
            NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Contacts',
            ),
            NavigationDestination(
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
    // Listen for incoming messages to refresh conversation list
    ref.listen<AsyncValue<Message>>(messageStreamProvider, (previous, next) {
      next.whenData((message) {
        ref.invalidate(conversationsProvider);
      });
    });

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
        onPressed: () => _showNewChatOptions(context, ref),
        child: const Icon(Icons.add_rounded),
      ),
    );
  }

  void _showNewChatOptions(BuildContext context, WidgetRef ref) {
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
              const SizedBox(height: 16),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.person_add_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                title: const Text(
                  'New Chat',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Start a direct conversation',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDarkSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ContactsScreen(selectMode: true),
                    ),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: AppColors.bgDarkTertiary),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.group_add_rounded,
                    color: AppColors.accent,
                    size: 22,
                  ),
                ),
                title: const Text(
                  'New Group',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Create a group chat',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDarkSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const CreateGroupScreen(),
                    ),
                  );
                },
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: Divider(color: AppColors.bgDarkTertiary),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accentGreen.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.login_rounded,
                    color: AppColors.accentGreen,
                    size: 22,
                  ),
                ),
                title: const Text(
                  'Join Group',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                subtitle: Text(
                  'Join with group ID',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textDarkSecondary,
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showJoinGroupDialog(context, ref);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showJoinGroupDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    // Capture navigator and scaffold BEFORE showing dialog
    final navigator = Navigator.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Join Group'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Paste an invite link or group ID:',
              style: TextStyle(
                color: AppColors.textDarkSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'cyxchat://join/... or group ID',
                suffixIcon: IconButton(
                  icon: const Icon(Icons.paste),
                  onPressed: () async {
                    final data = await Clipboard.getData('text/plain');
                    if (data?.text != null) {
                      controller.text = data!.text!;
                    }
                  },
                ),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              final groupId = controller.text.trim();
              if (groupId.isEmpty) {
                scaffoldMessenger.showSnackBar(
                  const SnackBar(content: Text('Please enter a group ID or invite link')),
                );
                return;
              }
              Navigator.pop(dialogContext);
              await _joinGroup(navigator, scaffoldMessenger, ref, groupId);
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }

  Future<void> _joinGroup(NavigatorState navigator, ScaffoldMessengerState scaffoldMessenger, WidgetRef ref, String input) async {
    try {
      // Check if input is an invite link URL
      final linkParsed = InviteLink.parseUrl(input);

      if (linkParsed != null) {
        // It's an invite link URL - join via link
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Joining group...')),
        );

        final success = await GroupService.instance.joinViaLink(
          groupId: linkParsed.groupId,
          linkId: linkParsed.linkId,
        );

        if (success) {
          ref.invalidate(conversationsProvider);
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Joined group successfully!')),
          );
          // Navigate to the group chat
          navigator.push(
            MaterialPageRoute(
              builder: (context) => GroupChatScreen(groupId: linkParsed.groupId),
            ),
          );
        } else {
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Failed to join group. Link may be expired or invalid.')),
          );
        }
        return;
      }

      // Not a URL - treat as group ID and check for pending invite
      final groupId = input.trim();
      final pendingInvites = GroupService.instance.pendingInvites;
      final invite = pendingInvites.where((i) => i.groupId == groupId).firstOrNull;

      if (invite != null) {
        // We have an invite, accept it
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Accepting invite...')),
        );

        final success = await GroupService.instance.acceptInvite(groupId);
        if (success) {
          ref.invalidate(conversationsProvider);
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            SnackBar(content: Text('Joined "${invite.groupName}"!')),
          );
          // Navigate to the group chat
          navigator.push(
            MaterialPageRoute(
              builder: (context) => GroupChatScreen(groupId: groupId),
            ),
          );
        } else {
          scaffoldMessenger.hideCurrentSnackBar();
          scaffoldMessenger.showSnackBar(
            const SnackBar(content: Text('Failed to join group')),
          );
        }
      } else {
        // No pending invite - show feedback via SnackBar
        scaffoldMessenger.showSnackBar(
          SnackBar(
            content: const Text('No invite found. Ask the admin to add you or share an invite link.'),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'OK',
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text('Error joining group: $e')),
      );
    }
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
    final isGroup = conversation.isGroup;

    return Material(
      color: AppColors.bgDarkSecondary,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          if (isGroup) {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => GroupChatScreen(groupId: conversation.id),
              ),
            );
          } else {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ChatScreen(conversationId: conversation.id),
              ),
            );
          }
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
                isGroup: isGroup,
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
                              if (isGroup) ...[
                                Icon(
                                  Icons.group_rounded,
                                  size: 14,
                                  color: AppColors.accent.withOpacity(0.8),
                                ),
                                const SizedBox(width: 6),
                              ],
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
                  ref.read(chatActionsProvider).deleteConversation(conversation.id);
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
  final bool isGroup;

  const _ConversationAvatar({
    required this.title,
    required this.hasUnread,
    this.isGroup = false,
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
                  ? (isGroup
                      ? [AppColors.accent, AppColors.accent.withOpacity(0.7)]
                      : [AppColors.primary, AppColors.primaryLight])
                  : [AppColors.bgDarkTertiary, AppColors.bgDarkTertiary],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Center(
            child: isGroup
                ? Icon(
                    Icons.group_rounded,
                    size: 24,
                    color: hasUnread ? Colors.white : AppColors.textDarkSecondary,
                  )
                : Text(
                    title.isNotEmpty ? title[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: hasUnread ? Colors.white : AppColors.textDarkSecondary,
                    ),
                  ),
          ),
        ),
        // Online/Group indicator
        if (!isGroup)
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
class _NetworkStatusChip extends ConsumerWidget {
  const _NetworkStatusChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connectionState = ref.watch(connectionNotifierProvider);
    final isInitialized = connectionState.initialized;
    final isBootstrapConnected = connectionState.networkStatus.bootstrapConnected;

    // Three states: Offline, Connecting, Online
    final Color statusColor;
    final String statusText;
    if (!isInitialized) {
      statusColor = AppColors.textDarkSecondary;
      statusText = 'Offline';
    } else if (!isBootstrapConnected) {
      statusColor = AppColors.warning;
      statusText = 'Connecting';
    } else {
      statusColor = AppColors.accentGreen;
      statusText = 'Online';
    }

    final isConnected = isInitialized && isBootstrapConnected;

    return GestureDetector(
      onTap: () => _showNetworkDetails(context, ref),
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

  void _showNetworkDetails(BuildContext context, WidgetRef ref) {
    final connectionState = ref.read(connectionNotifierProvider);
    final isInitialized = connectionState.initialized;
    final isBootstrapConnected = connectionState.networkStatus.bootstrapConnected;
    final networkStatus = connectionState.networkStatus;

    // Determine status display
    final String statusText;
    final Color statusColor;
    final IconData statusIcon;
    if (!isInitialized) {
      statusText = 'Disconnected';
      statusColor = AppColors.textDarkSecondary;
      statusIcon = Icons.wifi_off_rounded;
    } else if (!isBootstrapConnected) {
      statusText = 'Connecting...';
      statusColor = AppColors.warning;
      statusIcon = Icons.wifi_rounded;
    } else {
      statusText = 'Connected';
      statusColor = AppColors.accentGreen;
      statusIcon = Icons.wifi_rounded;
    }

    final isConnected = isInitialized && isBootstrapConnected;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: statusColor.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                statusIcon,
                size: 24,
                color: statusColor,
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
              value: statusText,
              valueColor: statusColor,
            ),
            const SizedBox(height: 12),
            _NetworkInfoRow(
              label: 'Peers',
              value: '${networkStatus.activeConnections} connected',
            ),
            const SizedBox(height: 12),
            _NetworkInfoRow(
              label: 'Public IP',
              value: networkStatus.publicAddress ?? 'Unknown',
            ),
            if (!isConnected) ...[
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
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              if (isConnected) {
                ref.read(connectionActionsProvider).disconnect();
              } else {
                final success = await ref.read(connectionActionsProvider).connect();
                if (context.mounted && !success) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to connect to network')),
                  );
                }
              }
            },
            child: Text(isConnected ? 'Disconnect' : 'Connect'),
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
