import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../main.dart';
import '../providers/identity_provider.dart';
import '../providers/dns_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/network_provider.dart';
import '../providers/connection_provider.dart';
import '../providers/file_provider.dart';
import '../providers/chat_provider.dart';
import '../services/identity_service.dart';
import '../services/log_service.dart';
import '../models/identity.dart';
import '../utils/node_id_utils.dart';
import 'onboarding_screen.dart';
import 'log_viewer_screen.dart';
import 'user_guide_screen.dart';
import 'appearance_settings_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Custom app bar
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: theme.scaffoldBackgroundColor,
            toolbarHeight: 60,
            title: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [colorScheme.secondary, colorScheme.primary],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.settings_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                const Text(
                  'Settings',
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
                // Profile section
                identityAsync.when(
                  data: (identity) => _ProfileCard(identity: identity),
                  loading: () => _ProfileCardLoading(),
                  error: (_, __) => const SizedBox(),
                ),

                const SizedBox(height: 24),

                // Username section
                _SettingsSection(
                  title: 'Username',
                  icon: Icons.alternate_email_rounded,
                  iconGradient: [colorScheme.secondary, colorScheme.primary],
                  children: const [
                    _UsernameSection(),
                  ],
                ),

                const SizedBox(height: 16),

                // Appearance section
                _SettingsSection(
                  title: 'Appearance',
                  icon: Icons.palette_rounded,
                  iconGradient: [colorScheme.error, colorScheme.primary],
                  children: [
                    _SettingsTile(
                      icon: Icons.color_lens_rounded,
                      title: 'Theme & Display',
                      subtitle: 'Colors, fonts, and chat appearance',
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AppearanceSettingsScreen()),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Privacy section
                _SettingsSection(
                  title: 'Privacy',
                  icon: Icons.shield_rounded,
                  iconGradient: [colorScheme.primary, colorScheme.primary.withAlpha(180)],
                  children: [
                    // Onion routing hop count selector
                    const _OnionHopSelector(),
                    // Fast file transfer toggle
                    const _FastFileTransferTile(),
                    // Video calls toggle
                    const _VideoCallsTile(),
                    _SettingsSwitch(
                      icon: Icons.lock_outline_rounded,
                      title: 'Screen Lock',
                      subtitle: 'Require authentication to open',
                      value: false,
                      onChanged: (value) {},
                    ),
                    _SettingsSwitch(
                      icon: Icons.visibility_off_rounded,
                      title: 'Read Receipts',
                      subtitle: 'Let others know when you\'ve read',
                      value: true,
                      onChanged: (value) {},
                    ),
                    _SettingsSwitch(
                      icon: Icons.keyboard_rounded,
                      title: 'Typing Indicators',
                      subtitle: 'Show when you\'re typing',
                      value: true,
                      onChanged: (value) {},
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Network section
                _SettingsSection(
                  title: 'Network',
                  icon: Icons.hub_rounded,
                  iconGradient: [colorScheme.secondary, colorScheme.primary],
                  children: [
                    const _NetworkStatusTile(),
                    const _ServerConfigTile(),
                  ],
                ),

                const SizedBox(height: 16),

                // Storage section
                _SettingsSection(
                  title: 'Storage',
                  icon: Icons.storage_rounded,
                  iconGradient: [colorScheme.tertiary ?? colorScheme.secondary, colorScheme.error],
                  children: [
                    _SettingsTile(
                      icon: Icons.folder_rounded,
                      title: 'Storage Usage',
                      subtitle: '12.5 MB used',
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurface.withAlpha(128),
                      ),
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.cleaning_services_rounded,
                      title: 'Clear Cache',
                      subtitle: 'Free up space',
                      onTap: () {},
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Debug section
                _SettingsSection(
                  title: 'Debug',
                  icon: Icons.bug_report_rounded,
                  iconGradient: [colorScheme.secondary, colorScheme.primary],
                  children: [
                    _SettingsTile(
                      icon: Icons.article_outlined,
                      title: 'View Logs',
                      subtitle: 'See app activity and errors',
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurface.withAlpha(128),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const LogViewerScreen()),
                      ),
                    ),
                    const _LogCountTile(),
                  ],
                ),

                const SizedBox(height: 16),

                // About section
                _SettingsSection(
                  title: 'About',
                  icon: Icons.info_outline_rounded,
                  iconGradient: [colorScheme.onSurface.withAlpha(128), colorScheme.surfaceContainerHighest],
                  children: [
                    _SettingsTile(
                      icon: Icons.menu_book_rounded,
                      title: 'User Guide',
                      subtitle: 'Learn how to use CyxChat',
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurface.withAlpha(128),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const UserGuideScreen()),
                      ),
                    ),
                    _SettingsTile(
                      icon: Icons.tag_rounded,
                      title: 'Version',
                      subtitle: '0.1.0 (Beta)',
                      onTap: null,
                    ),
                    _SettingsTile(
                      icon: Icons.code_rounded,
                      title: 'Open Source Licenses',
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: colorScheme.onSurface.withAlpha(128),
                      ),
                      onTap: () => showLicensePage(context: context),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Danger zone
                _SettingsSection(
                  title: 'Danger Zone',
                  icon: Icons.warning_rounded,
                  iconGradient: [colorScheme.error, colorScheme.error.withAlpha(180)],
                  isDestructive: true,
                  children: [
                    _SettingsTile(
                      icon: Icons.logout_rounded,
                      title: 'Reset Identity',
                      subtitle: 'Delete all data and start fresh',
                      isDestructive: true,
                      onTap: () => _showResetDialog(context, ref),
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

  void _showResetDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.warning_rounded,
                  size: 24,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text('Reset Identity?'),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'This will permanently delete:',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
              ),
              const SizedBox(height: 12),
              _ResetWarningItem(text: 'All your messages'),
              _ResetWarningItem(text: 'All your contacts'),
              _ResetWarningItem(text: 'Your identity and keys'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This action cannot be undone.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w500,
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
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await ref.read(identityActionsProvider).deleteIdentity();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(
                      builder: (_) => const OnboardingScreen(),
                    ),
                    (route) => false,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reset Everything'),
            ),
          ],
        );
      },
    );
  }
}

class _ResetWarningItem extends StatelessWidget {
  final String text;

  const _ResetWarningItem({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends ConsumerWidget {
  final dynamic identity;

  const _ProfileCard({required this.identity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary.withOpacity(0.15),
            Theme.of(context).colorScheme.secondary.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Center(
              child: Text(
                (identity?.displayText ?? 'A')[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  identity?.displayText ?? 'Anonymous',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showNodeIdDialog(context, identity),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          identity?.shortId ?? 'Loading...',
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.copy_rounded, size: 10, color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            onPressed: () => _showQrDialog(context, ref),
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.qr_code_rounded, size: 18),
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.edit_rounded, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  void _showNodeIdDialog(BuildContext context, Identity? identity) {
    if (identity == null) return;

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
              'Your Node ID',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this ID with others to let them message you',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                NodeIdUtils.toDisplayFormat(identity.nodeId),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: NodeIdUtils.toDisplayFormat(identity.nodeId)));
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Node ID copied to clipboard'),
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy Node ID'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _showQrDialog(BuildContext context, WidgetRef ref) {
    final qrData = ref.read(identityActionsProvider).generateQrData();
    if (qrData.isEmpty) return;

    final identityVal = identity as Identity?;

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
          children: [
            Text(
              'Your QR Code',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Others can scan this to add you as a contact',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
              ),
              child: QrImageView(
                data: qrData,
                size: 200,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              identityVal?.shortId ?? '',
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _ProfileCardLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(18),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 120,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 16,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Color> iconGradient;
  final List<Widget> children;
  final bool isDestructive;

  const _SettingsSection({
    required this.title,
    required this.icon,
    required this.iconGradient,
    required this.children,
    this.isDestructive = false,
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
                    color: isDestructive
                        ? colorScheme.error.withAlpha(200)
                        : colorScheme.onSurface.withAlpha(153),
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

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool isDestructive;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = isDestructive ? colorScheme.error : colorScheme.onSurface;

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
                  color: isDestructive
                      ? colorScheme.error.withAlpha(38)
                      : colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 20, color: color),
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
                        color: color,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDestructive
                              ? colorScheme.error.withAlpha(153)
                              : colorScheme.onSurface.withAlpha(128),
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

class _SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsSwitch({
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

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isActive;

  const _StatusChip({
    required this.label,
    required this.isActive,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: isActive
            ? Theme.of(context).colorScheme.secondary.withOpacity(0.15)
            : Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurface.withAlpha(153),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isActive ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurface.withAlpha(153),
            ),
          ),
        ],
      ),
    );
  }
}

/// Username registration section
class _UsernameSection extends ConsumerStatefulWidget {
  const _UsernameSection();

  @override
  ConsumerState<_UsernameSection> createState() => _UsernameSectionState();
}

class _UsernameSectionState extends ConsumerState<_UsernameSection> {
  final _usernameController = TextEditingController();
  bool _isRegistering = false;
  bool _isCheckingName = false;
  String? _error;
  String? _registeredName;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_registeredName != null) {
      return _buildRegisteredView(_registeredName!);
    }
    return _buildRegisterView();
  }

  Widget _buildRegisteredView(String name) {
    return Column(
      children: [
        _SettingsTile(
          icon: Icons.check_circle_rounded,
          title: '$name.cyx',
          subtitle: 'Your registered username',
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'Active',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ),
        _SettingsTile(
          icon: Icons.refresh_rounded,
          title: 'Refresh Registration',
          subtitle: 'Keep your name active on the network',
          onTap: () {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('DNS not connected yet'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          },
        ),
        _SettingsTile(
          icon: Icons.delete_outline_rounded,
          title: 'Release Username',
          subtitle: 'Allow others to claim this name',
          onTap: () => setState(() => _registeredName = null),
        ),
      ],
    );
  }

  Widget _buildRegisterView() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Register a username so others can find you easily',
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              border: _error != null
                  ? Border.all(color: Theme.of(context).colorScheme.error, width: 1)
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.alternate_email_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.6),
                ),
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      hintText: 'username',
                      hintStyle: TextStyle(
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontSize: 15,
                    ),
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _registerUsername(),
                    onChanged: (_) {
                      if (_error != null) {
                        setState(() => _error = null);
                      }
                    },
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '.cyx',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.secondary,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_isRegistering)
            Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
                ),
              ),
            )
          else
            ElevatedButton(
              onPressed: _registerUsername,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.how_to_reg_rounded, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Register Username',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          Text(
            'Usernames are 3-63 characters, must start with a letter, and can contain letters, numbers, and underscores.',
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.5),
            ),
          ),
        ],
      ),
    );
  }


  Future<void> _registerUsername() async {
    final username = _usernameController.text.trim().toLowerCase();

    if (username.isEmpty) {
      setState(() => _error = 'Please enter a username');
      return;
    }

    final validPattern = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{2,62}$');
    if (!validPattern.hasMatch(username)) {
      setState(() => _error = 'Invalid username format');
      return;
    }

    setState(() {
      _isCheckingName = true;
      _isRegistering = true;
      _error = null;
    });

    try {
      // Get current identity to compare node IDs
      final identity = IdentityService.instance.currentIdentity;
      if (identity == null) {
        setState(() {
          _isCheckingName = false;
          _isRegistering = false;
          _error = 'Identity not available';
        });
        return;
      }

      // Check if username is already taken via DNS lookup
      final dnsProvider = ref.read(dnsNotifierProvider);
      final existingRecord = await dnsProvider.lookup(username);

      if (!mounted) return;

      // If name exists and belongs to someone else, reject
      if (existingRecord != null && existingRecord.nodeId != identity.nodeId) {
        setState(() {
          _isCheckingName = false;
          _isRegistering = false;
          _error = 'Username "$username" is already taken';
        });
        return;
      }

      setState(() => _isCheckingName = false);

      // Proceed with registration
      final success = await dnsProvider.register(username);

      if (!mounted) return;

      if (success) {
        setState(() {
          _isRegistering = false;
          _registeredName = username;
        });

        _usernameController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Registered as $username.cyx'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      } else {
        setState(() {
          _isRegistering = false;
          _error = 'Failed to register username';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isCheckingName = false;
        _isRegistering = false;
        _error = 'Error: ${e.toString()}';
      });
    }
  }
}

/// Network status tile showing real-time connection info
class _NetworkStatusTile extends ConsumerWidget {
  const _NetworkStatusTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connection = ref.watch(connectionNotifierProvider);
    final networkStatus = connection.networkStatus;
    final peerCount = networkStatus.activeConnections;
    final directCount = networkStatus.directConnections;
    final relayCount = networkStatus.relayConnections;
    final isConnected = connection.initialized;

    String subtitle;
    if (!isConnected) {
      subtitle = 'Not connected';
    } else if (peerCount == 0) {
      subtitle = 'Waiting for peers...';
    } else {
      subtitle = directCount > 0 && relayCount > 0
          ? '$directCount direct, $relayCount relay'
          : directCount > 0
              ? '$directCount direct connection${directCount > 1 ? 's' : ''}'
              : '$relayCount relay connection${relayCount > 1 ? 's' : ''}';
    }

    return _SettingsTile(
      icon: Icons.cell_tower_rounded,
      title: 'P2P Network',
      subtitle: subtitle,
      trailing: _StatusChip(
        label: peerCount > 0 ? '$peerCount Peer${peerCount > 1 ? 's' : ''}' : 'Offline',
        isActive: peerCount > 0,
      ),
      onTap: () {
        // Show network details dialog
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: const Text('Network Status'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _NetworkInfoRow(
                  label: 'Public Address',
                  value: networkStatus.publicAddress ?? 'Discovering...',
                ),
                _NetworkInfoRow(
                  label: 'NAT Type',
                  value: networkStatus.natTypeName,
                ),
                _NetworkInfoRow(
                  label: 'Connected Peers',
                  value: '$peerCount',
                ),
                _NetworkInfoRow(
                  label: 'Direct Connections',
                  value: '$directCount',
                ),
                _NetworkInfoRow(
                  label: 'Relay Connections',
                  value: '$relayCount',
                ),
                const Divider(height: 16),
                _NetworkInfoRow(
                  label: 'UPnP/NAT-PMP',
                  value: networkStatus.upnpStatusText,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NetworkInfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _NetworkInfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
          ),
          Text(
            value,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Server configuration tile
class _ServerConfigTile extends ConsumerStatefulWidget {
  const _ServerConfigTile();

  @override
  ConsumerState<_ServerConfigTile> createState() => _ServerConfigTileState();
}

class _ServerConfigTileState extends ConsumerState<_ServerConfigTile> {
  bool _isConnecting = false;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final connection = ref.watch(connectionNotifierProvider);
    final hasServer = settings.bootstrapServer.isNotEmpty;
    final isConnected = connection.initialized;

    return Column(
      children: [
        _SettingsTile(
          icon: Icons.dns_rounded,
          title: 'Bootstrap Server',
          subtitle: hasServer ? settings.bootstrapServer : 'Not configured',
          trailing: _StatusChip(
            label: isConnected ? 'Connected' : (hasServer ? 'Offline' : 'Not set'),
            isActive: isConnected,
          ),
          onTap: () => _showServerDialog(context),
        ),
        // Connect/Disconnect button
        if (hasServer)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: _isConnecting
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor: AlwaysStoppedAnimation(Theme.of(context).colorScheme.secondary),
                          ),
                        ),
                      ),
                    )
                  : ElevatedButton.icon(
                      onPressed: () => isConnected ? _disconnect() : _connect(),
                      icon: Icon(
                        isConnected ? Icons.link_off_rounded : Icons.link_rounded,
                        size: 18,
                      ),
                      label: Text(isConnected ? 'Disconnect' : 'Connect'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isConnected
                            ? Theme.of(context).colorScheme.surfaceContainerHighest
                            : Theme.of(context).colorScheme.secondary,
                        foregroundColor: isConnected
                            ? Theme.of(context).colorScheme.onSurface
                            : Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
            ),
          ),
        // Network info when connected
        if (isConnected && connection.networkStatus.publicAddress != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.public_rounded,
                    size: 16,
                    color: Theme.of(context).colorScheme.secondary.withOpacity(0.8),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Public: ${connection.networkStatus.publicAddress}',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                    ),
                  ),
                ],
              ),
            ),
          ),
        // Server registry status
        if (isConnected)
          _ServerRegistryStatus(),
      ],
    );
  }

  Future<void> _connect() async {
    setState(() => _isConnecting = true);

    try {
      final success = await ref.read(connectionActionsProvider).connect();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success
                ? 'Connected to server'
                : 'Failed to connect'),
            behavior: SnackBarBehavior.floating,
            backgroundColor: success ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.error,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isConnecting = false);
      }
    }
  }

  void _disconnect() {
    ref.read(connectionActionsProvider).disconnect();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Disconnected from server'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  void _showServerDialog(BuildContext context) {
    final settings = ref.read(settingsProvider);
    final controller = TextEditingController(text: settings.bootstrapServer);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.dns_rounded,
                size: 24,
                color: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(width: 14),
            const Expanded(child: Text('Bootstrap Server')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the address of your CyxChat server for P2P discovery and relay.',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                hintText: 'e.g., 123.45.67.89:7777',
                prefixIcon: const Icon(Icons.link_rounded),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Format: IP:PORT (e.g., 192.168.1.100:7777)',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.7),
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
            onPressed: () {
              controller.text = '';
              ref.read(settingsProvider.notifier).setServer('');
              // Disconnect if connected
              if (ref.read(connectionNotifierProvider).initialized) {
                ref.read(connectionActionsProvider).disconnect();
              }
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Server cleared'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: const Text('Clear'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final server = controller.text.trim();
              // Disconnect first if connected with different server
              if (ref.read(connectionNotifierProvider).initialized) {
                ref.read(connectionActionsProvider).disconnect();
              }
              ref.read(settingsProvider.notifier).setServer(server);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(server.isEmpty
                      ? 'Server cleared'
                      : 'Server set to $server. Tap Connect to join.'),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}

/// Server registry health status display
class _ServerRegistryStatus extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final connProvider = ref.watch(connectionNotifierProvider);
    final servers = connProvider.getServersInfo();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.dns_rounded, size: 14, color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    servers.isEmpty
                        ? 'Servers'
                        : 'Servers (${connProvider.healthyServerCount}/${connProvider.serverCount} healthy)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                    ),
                  ),
                ),
                InkWell(
                  onTap: () => _showAddServerDialog(context, ref),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 12, color: Theme.of(context).colorScheme.secondary),
                        const SizedBox(width: 2),
                        Text(
                          'Add',
                          style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            if (servers.isNotEmpty) ...[
              const SizedBox(height: 8),
              ...servers.map((s) {
                final isHealthy = s['is_healthy'] as bool;
                final state = s['state'] as String;
                final latency = s['avg_latency_ms'] as int;
                final isSeed = s['is_seed'] as bool;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                        isHealthy ? Icons.check_circle : Icons.radio_button_unchecked,
                        size: 12,
                        color: isHealthy ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurface.withAlpha(153),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          s['addr'] as String,
                          style: TextStyle(
                            fontSize: 11,
                            fontFamily: 'monospace',
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ),
                      if (isSeed)
                        Container(
                          margin: const EdgeInsets.only(right: 6),
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.secondary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'SEED',
                            style: TextStyle(fontSize: 8, color: Theme.of(context).colorScheme.secondary, fontWeight: FontWeight.w600),
                          ),
                        ),
                      Text(
                        latency > 0 ? '${latency}ms' : state,
                        style: TextStyle(
                          fontSize: 10,
                          color: isHealthy ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.onSurface.withAlpha(153),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ] else
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'No servers registered',
                  style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showAddServerDialog(BuildContext context, WidgetRef ref) {
    final controller = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.secondary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add_circle_outline, color: Theme.of(context).colorScheme.secondary, size: 20),
            ),
            const SizedBox(width: 12),
            const Expanded(child: Text('Add Server')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter the address of a CyxChat server (ip:port).',
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withAlpha(153)),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                hintText: '192.168.1.100:7777',
                hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.5)),
                filled: true,
                fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(Icons.dns_rounded, size: 18),
              ),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final addr = controller.text.trim();
              if (addr.isEmpty || !addr.contains(':')) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('Enter a valid address (ip:port)'),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
                return;
              }
              final result = ref.read(connectionNotifierProvider).addServer(addr);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(result == 0 ? 'Server added: $addr' : 'Failed to add server'),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: result == 0 ? Theme.of(context).colorScheme.secondary : Theme.of(context).colorScheme.error,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}

/// Fast file transfer toggle tile
class _FastFileTransferTile extends ConsumerWidget {
  const _FastFileTransferTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final isEnabled = settings.directFileTransfer;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? Colors.orange.withOpacity(0.15)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.bolt_rounded,
                  size: 20,
                  color: isEnabled ? Colors.orange : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fast File Transfer',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Bypass onion for file transfers',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(110),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).setDirectFileTransfer(value);
                  // Apply to file provider immediately
                  ref.read(fileActionsProvider).setDirectMode(value);
                },
                activeColor: Colors.orange,
                activeTrackColor: Colors.orange.withOpacity(0.3),
                inactiveThumbColor: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
        // Warning when enabled
        if (isEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Colors.orange.withOpacity(0.9),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Direct P2P - peer can see your IP during file transfers',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Video calls settings widget with privacy warning
class _VideoCallsTile extends ConsumerWidget {
  const _VideoCallsTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final isEnabled = settings.videoCallsEnabled;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isEnabled
                      ? Colors.orange.withOpacity(0.15)
                      : Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.videocam_rounded,
                  size: 20,
                  color: isEnabled ? Colors.orange : Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Video Calls',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Enable video call functionality',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(110),
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: isEnabled,
                onChanged: (value) {
                  ref.read(settingsProvider.notifier).setVideoCallsEnabled(value);
                },
                activeColor: Colors.orange,
                activeTrackColor: Colors.orange.withOpacity(0.3),
                inactiveThumbColor: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                inactiveTrackColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ],
          ),
        ),
        // Warning when enabled
        if (isEnabled)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.withOpacity(0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 16,
                        color: Colors.orange.withOpacity(0.9),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Direct P2P Connection Required',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.orange.withOpacity(0.9),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Video calls are end-to-end encrypted but the peer can see your IP address. This is necessary for real-time communication.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Log count tile showing number of captured logs
class _LogCountTile extends StatelessWidget {
  const _LogCountTile();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: LogService.instance,
      builder: (context, _) {
        final logCount = LogService.instance.logs.length;
        final errorCount = LogService.instance.logs
            .where((log) => log.level == 'ERROR')
            .length;
        final warnCount = LogService.instance.logs
            .where((log) => log.level == 'WARN')
            .length;

        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                _LogStat(
                  label: 'Total',
                  count: logCount,
                  color: Theme.of(context).colorScheme.secondary,
                ),
                const SizedBox(width: 16),
                _LogStat(
                  label: 'Errors',
                  count: errorCount,
                  color: errorCount > 0 ? Theme.of(context).colorScheme.error : Theme.of(context).colorScheme.onSurface.withAlpha(153),
                ),
                const SizedBox(width: 16),
                _LogStat(
                  label: 'Warnings',
                  count: warnCount,
                  color: warnCount > 0 ? Colors.orange : Theme.of(context).colorScheme.onSurface.withAlpha(153),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () {
                    LogService.instance.clear();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('Logs cleared'),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    );
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface.withAlpha(153),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _LogStat extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _LogStat({
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$count',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.7),
          ),
        ),
      ],
    );
  }
}

/// Onion hop count selector
class _OnionHopSelector extends ConsumerWidget {
  const _OnionHopSelector();

  static const _hopOptions = [
    (hops: 1, label: 'Direct', payload: '1.6 KB', desc: 'Best reliability'),
    (hops: 2, label: 'Standard', payload: '1.2 KB', desc: 'Good balance'),
    (hops: 5, label: 'High', payload: '873 B', desc: 'Better anonymity'),
    (hops: 8, label: 'Maximum', payload: '561 B', desc: 'Best anonymity'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final currentHops = settings.onionHopCount;

    return Column(
      children: [
        // Header tile
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.security_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Onion Routing',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$currentHops hops · ${settings.hopPayloadCapacity} max payload',
                      style: TextStyle(
                        fontSize: 13,
                        color: Theme.of(context).colorScheme.onSurface.withAlpha(110),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondary.withAlpha(38),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Always On',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Theme.of(context).colorScheme.secondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Hop selector buttons
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: _hopOptions.map((option) {
                final isSelected = currentHops == option.hops;
                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      ref.read(settingsProvider.notifier).setOnionHopCount(option.hops);
                      // Apply to C library immediately
                      ref.read(chatActionsProvider).setHopCount(option.hops);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary.withOpacity(0.2)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected
                            ? Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.5))
                            : null,
                      ),
                      child: Column(
                        children: [
                          Text(
                            option.label,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface.withAlpha(153),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${option.hops} hops',
                            style: TextStyle(
                              fontSize: 10,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.8)
                                  : Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.6),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            option.payload,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary.withOpacity(0.7)
                                  : Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
        // Info text
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 16,
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.8),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'More hops = better anonymity but smaller message size',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurface.withAlpha(153).withOpacity(0.8),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
