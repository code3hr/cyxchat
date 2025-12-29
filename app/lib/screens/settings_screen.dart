import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/identity_provider.dart';
import 'onboarding_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identityAsync = ref.watch(identityProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          // Profile section
          identityAsync.when(
            data: (identity) => _ProfileSection(identity: identity),
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const SizedBox(),
          ),

          const Divider(),

          // Privacy section
          _SectionHeader(title: 'Privacy'),
          ListTile(
            leading: const Icon(Icons.lock_outline),
            title: const Text('Screen Lock'),
            subtitle: const Text('Require authentication to open'),
            trailing: Switch(
              value: false,
              onChanged: (value) {
                // TODO: Toggle screen lock
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.visibility_off),
            title: const Text('Read Receipts'),
            subtitle: const Text('Let others know when you\'ve read'),
            trailing: Switch(
              value: true,
              onChanged: (value) {
                // TODO: Toggle read receipts
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.keyboard),
            title: const Text('Typing Indicators'),
            subtitle: const Text('Show when you\'re typing'),
            trailing: Switch(
              value: true,
              onChanged: (value) {
                // TODO: Toggle typing indicators
              },
            ),
          ),

          const Divider(),

          // Network section
          _SectionHeader(title: 'Network'),
          ListTile(
            leading: const Icon(Icons.wifi),
            title: const Text('WiFi Direct'),
            subtitle: const Text('Enabled'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: WiFi Direct settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.bluetooth),
            title: const Text('Bluetooth'),
            subtitle: const Text('Enabled'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Bluetooth settings
            },
          ),
          ListTile(
            leading: const Icon(Icons.cell_tower),
            title: const Text('Internet Relay'),
            subtitle: const Text('Connected to 3 relays'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Relay settings
            },
          ),

          const Divider(),

          // Storage section
          _SectionHeader(title: 'Storage'),
          ListTile(
            leading: const Icon(Icons.storage),
            title: const Text('Storage Usage'),
            subtitle: const Text('12.5 MB'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              // TODO: Storage details
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep),
            title: const Text('Clear Cache'),
            onTap: () {
              // TODO: Clear cache
            },
          ),

          const Divider(),

          // About section
          _SectionHeader(title: 'About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: const Text('0.1.0'),
          ),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Open Source Licenses'),
            onTap: () {
              showLicensePage(context: context);
            },
          ),

          const Divider(),

          // Danger zone
          _SectionHeader(title: 'Danger Zone', isDestructive: true),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text('Reset Identity', style: TextStyle(color: Colors.red)),
            subtitle: const Text('Delete all data and start fresh'),
            onTap: () => _showResetDialog(context, ref),
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
          title: const Text('Reset Identity?'),
          content: const Text(
            'This will delete all your messages, contacts, and identity. '
            'This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
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
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Reset'),
            ),
          ],
        );
      },
    );
  }
}

class _ProfileSection extends StatelessWidget {
  final dynamic identity;

  const _ProfileSection({required this.identity});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: Text(
              (identity?.displayText ?? 'A')[0].toUpperCase(),
              style: TextStyle(
                fontSize: 32,
                color: Theme.of(context).colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  identity?.displayText ?? 'Anonymous',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  identity?.shortId ?? '',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.qr_code),
            onPressed: () {
              // TODO: Show QR code
            },
          ),
          IconButton(
            icon: const Icon(Icons.edit),
            onPressed: () {
              // TODO: Edit profile
            },
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final bool isDestructive;

  const _SectionHeader({
    required this.title,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: isDestructive ? Colors.red : Colors.grey[600],
          letterSpacing: 1,
        ),
      ),
    );
  }
}
