import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/settings_provider.dart';
import '../services/database_service.dart';
import 'blocked_contacts_screen.dart';

/// Provider for blocked contact count
final blockedContactCountProvider = FutureProvider<int>((ref) async {
  return await DatabaseService.instance.getBlockedContactCount();
});

/// Security Settings Screen
/// Provides controls for app lock, screen security, message privacy, etc.
class SecuritySettingsScreen extends ConsumerWidget {
  const SecuritySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // App bar
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            toolbarHeight: 60,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.primary, colorScheme.secondary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.security_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Security',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
          ),
          // Content
          SliverToBoxAdapter(
            child: Column(
              children: [
                const SizedBox(height: 8),

                // App Lock section
                _SecuritySection(
                  title: 'App Lock',
                  icon: Icons.lock_rounded,
                  iconGradient: [colorScheme.primary, colorScheme.secondary],
                  children: [
                    _SecuritySwitch(
                      icon: Icons.fingerprint_rounded,
                      title: 'App Lock',
                      subtitle: 'Require authentication to open app',
                      value: settings.appLockEnabled,
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .setAppLockEnabled(value);
                      },
                    ),
                    if (settings.appLockEnabled) ...[
                      _SecurityTile(
                        icon: Icons.lock_clock_rounded,
                        title: 'Auto-Lock Timeout',
                        subtitle: _formatTimeout(settings.appLockTimeout),
                        trailing: Icon(
                          Icons.chevron_right_rounded,
                          color: colorScheme.onSurface.withAlpha(128),
                        ),
                        onTap: () => _showTimeoutPicker(
                            context, ref, settings.appLockTimeout),
                      ),
                    ],
                  ],
                ),

                const SizedBox(height: 16),

                // Screen Security section
                _SecuritySection(
                  title: 'Screen Security',
                  icon: Icons.screenshot_monitor_rounded,
                  iconGradient: [colorScheme.error, colorScheme.primary],
                  children: [
                    _SecuritySwitch(
                      icon: Icons.no_photography_rounded,
                      title: 'Block Screenshots',
                      subtitle: 'Prevent screenshots and screen recording',
                      value: settings.screenSecurityEnabled,
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .setScreenSecurityEnabled(value);
                        if (value) {
                          _showRestartRequiredSnackbar(context);
                        }
                      },
                    ),
                    _SecuritySwitch(
                      icon: Icons.visibility_off_rounded,
                      title: 'Hide in App Switcher',
                      subtitle: 'Show blank screen in recent apps',
                      value: settings.hideInAppSwitcher,
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .setHideInAppSwitcher(value);
                        if (value) {
                          _showRestartRequiredSnackbar(context);
                        }
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Message Privacy section
                _SecuritySection(
                  title: 'Message Privacy',
                  icon: Icons.chat_bubble_outline_rounded,
                  iconGradient: [colorScheme.secondary, colorScheme.primary],
                  children: [
                    _SecurityTile(
                      icon: Icons.timer_rounded,
                      title: 'Disappearing Messages',
                      subtitle: settings.disappearingMessagesDefault == null
                          ? 'Off'
                          : _formatDuration(
                              settings.disappearingMessagesDefault!),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurface.withAlpha(128),
                      ),
                      onTap: () => _showDisappearingMessagesPicker(
                          context, ref, settings.disappearingMessagesDefault),
                    ),
                    _SecuritySwitch(
                      icon: Icons.done_all_rounded,
                      title: 'Read Receipts',
                      subtitle: 'Let others know when you\'ve read messages',
                      value: settings.sendReadReceipts,
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .setSendReadReceipts(value);
                      },
                    ),
                    _SecuritySwitch(
                      icon: Icons.keyboard_rounded,
                      title: 'Typing Indicators',
                      subtitle: 'Show when you\'re typing a message',
                      value: settings.sendTypingIndicators,
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .setSendTypingIndicators(value);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Contacts section
                _SecuritySection(
                  title: 'Contacts',
                  icon: Icons.people_outline_rounded,
                  iconGradient: [colorScheme.tertiary, colorScheme.primary],
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final blockedCountAsync =
                            ref.watch(blockedContactCountProvider);
                        final blockedCount = blockedCountAsync.valueOrNull ?? 0;
                        return _SecurityTile(
                          icon: Icons.block_rounded,
                          title: 'Blocked Contacts',
                          subtitle: 'Manage blocked users',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  '$blockedCount',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface.withAlpha(153),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                Icons.chevron_right_rounded,
                                color: colorScheme.onSurface.withAlpha(128),
                              ),
                            ],
                          ),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) =>
                                      const BlockedContactsScreen()),
                            ).then((_) {
                              // Refresh count when returning
                              ref.invalidate(blockedContactCountProvider);
                            });
                          },
                        );
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Notifications section
                _SecuritySection(
                  title: 'Notifications',
                  icon: Icons.notifications_outlined,
                  iconGradient: [Colors.orange, colorScheme.error],
                  children: [
                    _SecurityTile(
                      icon: Icons.preview_rounded,
                      title: 'Notification Preview',
                      subtitle: _formatNotificationPreview(
                          settings.notificationPreview),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurface.withAlpha(128),
                      ),
                      onTap: () => _showNotificationPreviewPicker(
                          context, ref, settings.notificationPreview),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Advanced section
                _SecuritySection(
                  title: 'Advanced',
                  icon: Icons.tune_rounded,
                  iconGradient: [
                    colorScheme.onSurface.withAlpha(128),
                    colorScheme.surfaceContainerHighest
                  ],
                  children: [
                    _SecuritySwitch(
                      icon: Icons.keyboard_hide_rounded,
                      title: 'Incognito Keyboard',
                      subtitle: 'Request keyboard to not learn from typing',
                      value: settings.incognitoKeyboard,
                      onChanged: (value) {
                        ref
                            .read(settingsProvider.notifier)
                            .setIncognitoKeyboard(value);
                      },
                    ),
                  ],
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatTimeout(int seconds) {
    if (seconds == 0) return 'Immediately';
    if (seconds < 60) return '$seconds seconds';
    final minutes = seconds ~/ 60;
    if (minutes == 1) return '1 minute';
    if (minutes < 60) return '$minutes minutes';
    final hours = minutes ~/ 60;
    if (hours == 1) return '1 hour';
    return '$hours hours';
  }

  String _formatDuration(int seconds) {
    if (seconds < 60) return '$seconds seconds';
    if (seconds < 3600) return '${seconds ~/ 60} minutes';
    if (seconds < 86400) return '${seconds ~/ 3600} hours';
    return '${seconds ~/ 86400} days';
  }

  String _formatNotificationPreview(NotificationPreview preview) {
    switch (preview) {
      case NotificationPreview.full:
        return 'Show sender and message';
      case NotificationPreview.senderOnly:
        return 'Show sender only';
      case NotificationPreview.none:
        return 'Hide all content';
    }
  }

  void _showRestartRequiredSnackbar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Restart app to apply changes'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showTimeoutPicker(
      BuildContext context, WidgetRef ref, int currentTimeout) {
    final options = [
      (0, 'Immediately'),
      (30, '30 seconds'),
      (60, '1 minute'),
      (300, '5 minutes'),
      (900, '15 minutes'),
      (3600, '1 hour'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auto-Lock Timeout',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Lock the app after this time of inactivity',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 16),
            ...options.map((option) {
              final isSelected = currentTimeout == option.$1;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withAlpha(128),
                ),
                title: Text(option.$2),
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .setAppLockTimeout(option.$1);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showDisappearingMessagesPicker(
      BuildContext context, WidgetRef ref, int? currentDuration) {
    final options = [
      (null, 'Off'),
      (300, '5 minutes'),
      (3600, '1 hour'),
      (86400, '1 day'),
      (604800, '7 days'),
      (2592000, '30 days'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Disappearing Messages',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Default timer for new conversations',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 16),
            ...options.map((option) {
              final isSelected = currentDuration == option.$1;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withAlpha(128),
                ),
                title: Text(option.$2),
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .setDisappearingMessagesDefault(option.$1);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showNotificationPreviewPicker(
      BuildContext context, WidgetRef ref, NotificationPreview current) {
    final options = [
      (
        NotificationPreview.full,
        'Show sender and message',
        'Full preview of notifications'
      ),
      (
        NotificationPreview.senderOnly,
        'Show sender only',
        'Hide message content'
      ),
      (NotificationPreview.none, 'Hide all content', 'Show "New Message" only'),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Notification Preview',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Control what\'s shown in notifications',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 16),
            ...options.map((option) {
              final isSelected = current == option.$1;
              return ListTile(
                leading: Icon(
                  isSelected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).colorScheme.onSurface.withAlpha(128),
                ),
                title: Text(option.$2),
                subtitle: Text(
                  option.$3,
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        Theme.of(context).colorScheme.onSurface.withAlpha(128),
                  ),
                ),
                onTap: () {
                  ref
                      .read(settingsProvider.notifier)
                      .setNotificationPreview(option.$1);
                  Navigator.pop(context);
                },
              );
            }),
          ],
        ),
      ),
    );
  }
}

/// Section container
class _SecuritySection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> iconGradient;
  final List<Widget> children;

  const _SecuritySection({
    required this.title,
    required this.icon,
    required this.iconGradient,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: iconGradient),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 16, color: Colors.white),
                ),
                const SizedBox(width: 10),
                Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                    color: colorScheme.onSurface.withAlpha(153),
                  ),
                ),
              ],
            ),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// Setting tile
class _SecurityTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SecurityTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: colorScheme.onSurface),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface.withAlpha(128),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

/// Switch tile
class _SecuritySwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SecuritySwitch({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: colorScheme.onSurface),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurface.withAlpha(128),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
