import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:provider/provider.dart' as provider;
import 'package:qr_flutter/qr_flutter.dart';
import '../providers/identity_provider.dart';
import '../providers/dns_provider.dart';

class AddContactScreen extends ConsumerStatefulWidget {
  const AddContactScreen({super.key});

  @override
  ConsumerState<AddContactScreen> createState() => _AddContactScreenState();
}

class _AddContactScreenState extends ConsumerState<AddContactScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _nodeIdController = TextEditingController();
  final _usernameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nodeIdController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabs: const [
            Tab(icon: Icon(Icons.alternate_email), text: 'Username'),
            Tab(icon: Icon(Icons.qr_code), text: 'My QR'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Scan'),
            Tab(icon: Icon(Icons.key), text: 'Node ID'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _UsernameTab(controller: _usernameController),
          _MyQrTab(),
          const _ScanTab(),
          _ManualTab(controller: _nodeIdController),
        ],
      ),
    );
  }
}

class _MyQrTab extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final qrData = ref.read(identityActionsProvider).generateQrData();
    final identityAsync = ref.watch(identityProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Show this QR code to add you',
            style: Theme.of(context).textTheme.titleMedium,
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
          const SizedBox(height: 24),
          identityAsync.when(
            data: (identity) => Column(
              children: [
                Text(
                  identity?.displayText ?? 'Anonymous',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  identity?.shortId ?? '',
                  style: TextStyle(
                    fontFamily: 'monospace',
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
            loading: () => const CircularProgressIndicator(),
            error: (_, __) => const Text('Error'),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () {
              // TODO: Share QR code
            },
            icon: const Icon(Icons.share),
            label: const Text('Share'),
          ),
        ],
      ),
    );
  }
}

class _ScanTab extends StatelessWidget {
  const _ScanTab();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.qr_code_scanner,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Text(
            'Scan a QR code',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Point your camera at a CyxChat QR code',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // TODO: Open camera scanner
              // Use mobile_scanner package
            },
            icon: const Icon(Icons.camera_alt),
            label: const Text('Open Camera'),
          ),
        ],
      ),
    );
  }
}

class _ManualTab extends StatelessWidget {
  final TextEditingController controller;

  const _ManualTab({required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Enter Node ID',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Ask your contact for their 64-character node ID',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'Node ID',
              hintText: 'Enter 64 hex characters',
            ),
            maxLength: 64,
            style: const TextStyle(fontFamily: 'monospace'),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Display name (optional)',
              hintText: 'How you want to call them',
            ),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // TODO: Add contact
              final nodeId = controller.text.trim();
              if (nodeId.length != 64) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Invalid node ID')),
                );
                return;
              }
              // Add contact logic
              Navigator.pop(context);
            },
            child: const Text('Add Contact'),
          ),
        ],
      ),
    );
  }
}

/// Username lookup tab
class _UsernameTab extends StatefulWidget {
  final TextEditingController controller;

  const _UsernameTab({required this.controller});

  @override
  State<_UsernameTab> createState() => _UsernameTabState();
}

class _UsernameTabState extends State<_UsernameTab> {
  bool _isLookingUp = false;
  String? _lookupError;
  DnsRecord? _resolvedRecord;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Find by Username',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter a username to find a contact on the network',
            style: TextStyle(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: widget.controller,
            decoration: InputDecoration(
              labelText: 'Username',
              hintText: 'e.g., alice or alice.cyx',
              prefixIcon: const Icon(Icons.alternate_email),
              suffixText: '.cyx',
              errorText: _lookupError,
            ),
            textInputAction: TextInputAction.search,
            onSubmitted: (_) => _lookupUsername(),
            onChanged: (_) {
              if (_lookupError != null) {
                setState(() {
                  _lookupError = null;
                  _resolvedRecord = null;
                });
              }
            },
          ),
          const SizedBox(height: 16),
          if (_isLookingUp)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 8),
                    Text('Looking up username...'),
                  ],
                ),
              ),
            )
          else if (_resolvedRecord != null)
            _buildResolvedContact(_resolvedRecord!)
          else
            ElevatedButton.icon(
              onPressed: _lookupUsername,
              icon: const Icon(Icons.search),
              label: const Text('Look Up'),
            ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text(
            'Username tips:',
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          _buildTip(Icons.check_circle_outline, 'Usernames are 3-63 characters'),
          _buildTip(Icons.check_circle_outline, 'Can contain letters, numbers, and underscores'),
          _buildTip(Icons.check_circle_outline, 'Must start with a letter'),
          _buildTip(Icons.lock_outline, 'Crypto-names (like k5xq3v7b.cyx) resolve instantly'),
        ],
      ),
    );
  }

  Widget _buildTip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey[600], fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResolvedContact(DnsRecord record) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                  child: Text(
                    record.name[0].toUpperCase(),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.fullName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        'Node: ${record.nodeId.substring(0, 16)}...',
                        style: TextStyle(
                          color: Colors.grey[600],
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.check_circle, color: Colors.green),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _resolvedRecord = null;
                        widget.controller.clear();
                      });
                    },
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _addContact(record),
                    child: const Text('Add Contact'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _lookupUsername() async {
    final username = widget.controller.text.trim();
    if (username.isEmpty) {
      setState(() {
        _lookupError = 'Please enter a username';
      });
      return;
    }

    final dnsProvider = provider.Provider.of<DnsProvider>(context, listen: false);

    // Validate name format
    if (!dnsProvider.validateName(username)) {
      setState(() {
        _lookupError = 'Invalid username format';
      });
      return;
    }

    setState(() {
      _isLookingUp = true;
      _lookupError = null;
      _resolvedRecord = null;
    });

    try {
      final record = await dnsProvider.lookup(username);

      if (!mounted) return;

      if (record != null) {
        setState(() {
          _isLookingUp = false;
          _resolvedRecord = record;
        });
      } else {
        setState(() {
          _isLookingUp = false;
          _lookupError = 'Username not found on the network';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLookingUp = false;
          _lookupError = 'Lookup failed: $e';
        });
      }
    }
  }

  void _addContact(DnsRecord record) {
    // TODO: Actually add the contact to the contact list
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Added ${record.fullName}')),
    );
    Navigator.pop(context);
  }
}
