import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../providers/identity_provider.dart';
import '../providers/dns_provider.dart';
import '../providers/settings_provider.dart';
import '../services/identity_service.dart';
import '../models/identity.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // Custom app bar
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: AppColors.bgDark,
            toolbarHeight: 60,
            title: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [AppColors.accentPink, AppColors.accentOrange],
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
                  iconGradient: const [AppColors.accent, AppColors.accentGreen],
                  children: const [
                    _UsernameSection(),
                  ],
                ),

                const SizedBox(height: 16),

                // Privacy section
                _SettingsSection(
                  title: 'Privacy',
                  icon: Icons.shield_rounded,
                  iconGradient: const [AppColors.primary, AppColors.primaryLight],
                  children: [
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
                  iconGradient: const [AppColors.accentGreen, AppColors.accent],
                  children: [
                    _SettingsTile(
                      icon: Icons.wifi_rounded,
                      title: 'WiFi Direct',
                      subtitle: 'Enabled',
                      trailing: _StatusChip(label: 'Active', isActive: true),
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.bluetooth_rounded,
                      title: 'Bluetooth',
                      subtitle: 'Enabled',
                      trailing: _StatusChip(label: 'Active', isActive: true),
                      onTap: () {},
                    ),
                    _SettingsTile(
                      icon: Icons.cell_tower_rounded,
                      title: 'Internet Relay',
                      subtitle: 'Connected to 3 relays',
                      trailing: _StatusChip(label: '3 Peers', isActive: true),
                      onTap: () {},
                    ),
                    const _ServerConfigTile(),
                  ],
                ),

                const SizedBox(height: 16),

                // Storage section
                _SettingsSection(
                  title: 'Storage',
                  icon: Icons.storage_rounded,
                  iconGradient: const [AppColors.accentOrange, AppColors.accentPink],
                  children: [
                    _SettingsTile(
                      icon: Icons.folder_rounded,
                      title: 'Storage Usage',
                      subtitle: '12.5 MB used',
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textDarkSecondary,
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

                // About section
                _SettingsSection(
                  title: 'About',
                  icon: Icons.info_outline_rounded,
                  iconGradient: const [AppColors.textDarkSecondary, AppColors.bgDarkTertiary],
                  children: [
                    _SettingsTile(
                      icon: Icons.tag_rounded,
                      title: 'Version',
                      subtitle: '0.1.0 (Beta)',
                      onTap: null,
                    ),
                    _SettingsTile(
                      icon: Icons.code_rounded,
                      title: 'Open Source Licenses',
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                        color: AppColors.textDarkSecondary,
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
                  iconGradient: const [AppColors.error, AppColors.accentOrange],
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
                  color: AppColors.error.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.warning_rounded,
                  size: 24,
                  color: AppColors.error,
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
              const Text(
                'This will permanently delete:',
                style: TextStyle(color: AppColors.textDarkSecondary),
              ),
              const SizedBox(height: 12),
              _ResetWarningItem(text: 'All your messages'),
              _ResetWarningItem(text: 'All your contacts'),
              _ResetWarningItem(text: 'Your identity and keys'),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: AppColors.error,
                    ),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'This action cannot be undone.',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.error,
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
                backgroundColor: AppColors.error,
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
            decoration: const BoxDecoration(
              color: AppColors.error,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            text,
            style: const TextStyle(
              color: AppColors.textDark,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  final dynamic identity;

  const _ProfileCard({required this.identity});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.15),
            AppColors.accent.withOpacity(0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppColors.primary.withOpacity(0.2),
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
              gradient: const LinearGradient(
                colors: [AppColors.primary, AppColors.accent],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primary.withOpacity(0.3),
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
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textDark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                GestureDetector(
                  onTap: () => _showNodeIdDialog(context, identity),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.bgDarkTertiary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          identity?.shortId ?? 'Loading...',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 10,
                            color: AppColors.textDarkSecondary,
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.copy_rounded, size: 10, color: AppColors.textDarkSecondary),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Actions
          IconButton(
            onPressed: () {},
            icon: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.bgDarkSecondary,
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
                color: AppColors.bgDarkSecondary,
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
      backgroundColor: AppColors.bgDarkSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your Node ID',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Share this ID with others to let them message you',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.textDarkSecondary,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.bgDarkTertiary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                identity.nodeId,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  color: AppColors.textDark,
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: identity.nodeId));
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
                  backgroundColor: AppColors.primary,
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
}

class _ProfileCardLoading extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.bgDarkSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppColors.bgDarkTertiary,
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
                    color: AppColors.bgDarkTertiary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  width: 80,
                  height: 16,
                  decoration: BoxDecoration(
                    color: AppColors.bgDarkTertiary,
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
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.bgDarkSecondary,
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
                        ? AppColors.error.withOpacity(0.8)
                        : AppColors.textDarkSecondary,
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
    final color = isDestructive ? AppColors.error : AppColors.textDark;

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
                      ? AppColors.error.withOpacity(0.15)
                      : AppColors.bgDarkTertiary,
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
                              ? AppColors.error.withOpacity(0.6)
                              : AppColors.textDarkSecondary.withOpacity(0.7),
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppColors.bgDarkTertiary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: AppColors.textDark),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textDarkSecondary.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeColor: AppColors.primary,
            activeTrackColor: AppColors.primary.withOpacity(0.3),
            inactiveThumbColor: AppColors.textDarkSecondary,
            inactiveTrackColor: AppColors.bgDarkTertiary,
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
            ? AppColors.accentGreen.withOpacity(0.15)
            : AppColors.bgDarkTertiary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: isActive ? AppColors.accentGreen : AppColors.textDarkSecondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isActive ? AppColors.accentGreen : AppColors.textDarkSecondary,
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
              color: AppColors.accentGreen.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Active',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppColors.accentGreen,
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
              color: AppColors.textDarkSecondary.withOpacity(0.7),
            ),
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(
              color: AppColors.bgDarkTertiary,
              borderRadius: BorderRadius.circular(14),
              border: _error != null
                  ? Border.all(color: AppColors.error, width: 1)
                  : null,
            ),
            child: Row(
              children: [
                const SizedBox(width: 14),
                Icon(
                  Icons.alternate_email_rounded,
                  size: 20,
                  color: AppColors.textDarkSecondary.withOpacity(0.6),
                ),
                Expanded(
                  child: TextField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      hintText: 'username',
                      hintStyle: TextStyle(
                        color: AppColors.textDarkSecondary.withOpacity(0.4),
                      ),
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 14,
                      ),
                    ),
                    style: const TextStyle(
                      color: AppColors.textDark,
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
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    '.cyx',
                    style: TextStyle(
                      color: AppColors.accent,
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
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (_isRegistering)
            const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation(AppColors.accent),
                ),
              ),
            )
          else
            ElevatedButton(
              onPressed: _registerUsername,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
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
              color: AppColors.textDarkSecondary.withOpacity(0.5),
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

/// Server configuration tile
class _ServerConfigTile extends ConsumerStatefulWidget {
  const _ServerConfigTile();

  @override
  ConsumerState<_ServerConfigTile> createState() => _ServerConfigTileState();
}

class _ServerConfigTileState extends ConsumerState<_ServerConfigTile> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final hasServer = settings.bootstrapServer.isNotEmpty;

    return _SettingsTile(
      icon: Icons.dns_rounded,
      title: 'Bootstrap Server',
      subtitle: hasServer ? settings.bootstrapServer : 'Not configured',
      trailing: _StatusChip(
        label: hasServer ? 'Connected' : 'Offline',
        isActive: hasServer,
      ),
      onTap: () => _showServerDialog(context),
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
                color: AppColors.accent.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.dns_rounded,
                size: 24,
                color: AppColors.accent,
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
                color: AppColors.textDarkSecondary.withOpacity(0.7),
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
                color: AppColors.bgDarkTertiary,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 18,
                    color: AppColors.textDarkSecondary.withOpacity(0.7),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Format: IP:PORT (e.g., 192.168.1.100:7777)',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textDarkSecondary.withOpacity(0.7),
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
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Server cleared. Restart app to apply.'),
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
              ref.read(settingsProvider.notifier).setServer(server);
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(server.isEmpty
                      ? 'Server cleared. Restart app to apply.'
                      : 'Server set to $server. Restart app to apply.'),
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
