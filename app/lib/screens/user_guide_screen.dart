import 'package:flutter/material.dart';
import '../main.dart';

/// Comprehensive user guide for CyxChat
class UserGuideScreen extends StatelessWidget {
  const UserGuideScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            pinned: true,
            backgroundColor: AppColors.bgDark,
            expandedHeight: 120,
            flexibleSpace: FlexibleSpaceBar(
              title: const Text(
                'User Guide',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.3),
                      AppColors.bgDark,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // What is CyxChat
                  _GuideSection(
                    icon: Icons.chat_bubble_outline,
                    title: 'What is CyxChat?',
                    gradient: [AppColors.primary, AppColors.accent],
                    content: '''
CyxChat is a decentralized, privacy-first messaging application built on the CyxWiz protocol.

Think of it as "WhatsApp without servers" - your messages travel directly between devices without passing through any central server that could spy on you.

Key features:
• No central servers - true peer-to-peer
• End-to-end encrypted with X25519 + XChaCha20-Poly1305
• Onion routing for metadata protection
• Works behind NAT and firewalls
• Cross-platform (mobile + desktop)
''',
                  ),

                  const SizedBox(height: 16),

                  // What problem does it solve
                  _GuideSection(
                    icon: Icons.lightbulb_outline,
                    title: 'What Problem Does It Solve?',
                    gradient: [AppColors.accentOrange, AppColors.accentPink],
                    content: '''
Traditional messaging apps have serious privacy issues:

❌ Central servers see all your messages
❌ Metadata reveals who you talk to and when
❌ Companies can be forced to hand over data
❌ Single point of failure and censorship

CyxChat solves these by:

✅ No central server to hack or subpoena
✅ Onion routing hides who talks to whom
✅ Your data stays on YOUR device
✅ Decentralized = no single point of failure
✅ Works even if blocked (mesh routing)
''',
                  ),

                  const SizedBox(height: 16),

                  // Getting Started
                  _GuideSection(
                    icon: Icons.play_arrow,
                    title: 'Getting Started',
                    gradient: [AppColors.accentGreen, AppColors.accent],
                    content: '''
1. IDENTITY CREATION
When you first open CyxChat, an identity is automatically created for you. This generates:
• A unique Node ID (your address on the network)
• Encryption keys (X25519 for key exchange)
• No email, phone, or personal info required!

2. CONNECT TO NETWORK
Go to Settings → Network → Bootstrap Server and enter a server address. Then tap Connect.

The bootstrap server only helps you find other peers - it never sees your messages.

3. ADD CONTACTS
• Tap Contacts → Add Contact
• Enter someone's Node ID or scan their QR code
• You can find your Node ID in Settings (tap your profile)

4. START CHATTING
Tap a contact to open a chat and send messages!
''',
                  ),

                  const SizedBox(height: 16),

                  // Node ID & Username
                  _GuideSection(
                    icon: Icons.fingerprint,
                    title: 'Node ID & Username',
                    gradient: [AppColors.primary, AppColors.primaryLight],
                    content: '''
NODE ID
Your Node ID is a 64-character hex string that uniquely identifies you on the network. It's derived from your public key.

Example: a1b2c3d4e5f6...

Share this with others so they can add you as a contact.

USERNAME (.cyx)
Optionally register a human-readable username like "alice.cyx" to make it easier for others to find you.

Go to Settings → Username to register.

Username rules:
• 3-63 characters
• Must start with a letter
• Can contain letters, numbers, underscores
''',
                  ),

                  const SizedBox(height: 16),

                  // Sending Messages
                  _GuideSection(
                    icon: Icons.send,
                    title: 'Sending Messages',
                    gradient: [AppColors.accent, AppColors.accentGreen],
                    content: '''
DIRECT MESSAGES
1. Open a contact's chat
2. Type your message
3. Tap send

Messages are encrypted and sent through onion routing by default, so the path is hidden.

MESSAGE STATUS
• ✓ Sent to network
• ✓✓ Delivered to recipient
• Blue ✓✓ Read by recipient

REPLY TO MESSAGES
Long-press a message and tap "Reply" to quote it in your response.
''',
                  ),

                  const SizedBox(height: 16),

                  // File Transfer
                  _GuideSection(
                    icon: Icons.attach_file,
                    title: 'Sending Files',
                    gradient: [AppColors.accentOrange, AppColors.accent],
                    content: '''
STANDARD FILE TRANSFER
Tap the attachment icon 📎 in chat to send files.
• Files are encrypted end-to-end
• Sent through onion routing for privacy
• Works with any file type
• Max size: 64KB per file (onion limit)

FAST FILE TRANSFER
For larger files, enable "Fast File Transfer" in Settings → Privacy.

Benefits:
• No size limit (up to 1GB)
• Much faster (direct P2P, 32KB chunks)
• Still end-to-end encrypted

⚠️ Privacy tradeoff: The peer can see your IP address during fast transfers. Only use with trusted contacts.
''',
                  ),

                  const SizedBox(height: 16),

                  // Groups
                  _GuideSection(
                    icon: Icons.group,
                    title: 'Group Chats',
                    gradient: [AppColors.primary, AppColors.accent],
                    content: '''
CREATE A GROUP
1. Go to the Groups tab
2. Tap the + button
3. Enter a group name
4. Invite contacts from your list

GROUP FEATURES
• End-to-end encrypted with rotating keys
• Automatic key rotation when members leave
• Admin controls (kick, promote, mute)
• Message pinning and editing

ROLES
• Owner - Full control, created the group
• Admin - Can manage members and messages
• Member - Can send messages
''',
                  ),

                  const SizedBox(height: 16),

                  // Supergroups
                  _GuideSection(
                    icon: Icons.verified,
                    title: 'Supergroups',
                    gradient: [AppColors.accentPink, AppColors.primary],
                    content: '''
Supergroups are enhanced groups for larger communities.

UPGRADE TO SUPERGROUP
Owner can upgrade in Group Info → Settings → Upgrade to Supergroup

BASIC GROUP vs SUPERGROUP:

Basic Group:
• Max 200 members
• Simple admin controls
• Basic invite links

Supergroup:
• Up to 100,000 members
• Granular admin permissions
• Advanced invite links (expiry, usage limits)
• Admin action log

⚠️ Upgrade is permanent and cannot be undone.
''',
                  ),

                  const SizedBox(height: 16),

                  // Group Admin Features
                  _GuideSection(
                    icon: Icons.admin_panel_settings,
                    title: 'Group Admin Features',
                    gradient: [AppColors.accentGreen, AppColors.accent],
                    content: '''
MEMBER MANAGEMENT
• Promote to Admin / Demote
• Kick members
• Mute members (1 hour to forever)

PERMISSIONS (Supergroup)
Granular control over what admins can do:
• Add/remove members
• Delete messages
• Pin messages
• Change group info
• Ban users
• Manage other admins

SLOW MODE
Limit how often members can send messages:
Off, 10s, 30s, 1m, 5m, 15m, or 1 hour

INVITE LINKS
Create shareable links with:
• Custom names
• Expiration dates
• Usage limits
• QR codes

ADMIN LOG (Supergroup)
Track all admin actions - who did what and when.
''',
                  ),

                  const SizedBox(height: 16),

                  // QR Codes
                  _GuideSection(
                    icon: Icons.qr_code,
                    title: 'QR Codes',
                    gradient: [AppColors.accent, AppColors.primary],
                    content: '''
SHARING YOUR QR CODE
1. Go to Settings
2. Tap the QR icon next to your profile
3. Show the QR code to others to scan

Others can scan your QR to instantly add you as a contact.

SCANNING QR CODES
1. Go to Contacts → Add Contact
2. Tap "Scan QR Code"
3. Point camera at the QR code
4. Contact is added automatically

GROUP INVITE QR CODES
Admins can create invite links with QR codes:
1. Open Group Info
2. Go to Invite Links
3. Create a new link
4. Tap "Show QR" to display

Share the QR code in person for secure group invites.
''',
                  ),

                  const SizedBox(height: 16),

                  // Voice Messages
                  _GuideSection(
                    icon: Icons.mic,
                    title: 'Voice Messages',
                    gradient: [AppColors.accentPink, AppColors.accentOrange],
                    content: '''
RECORDING A VOICE MESSAGE
1. Open a chat
2. Press and hold the microphone button
3. Speak your message
4. Release to send

CANCEL RECORDING
While holding the mic button, slide left to cancel.

PLAYBACK
Tap on a received voice message to play it. The waveform shows audio levels.

DURATION
• Maximum recording: 60 seconds
• Minimum to send: 0.5 seconds

Voice messages are encrypted just like text messages.
''',
                  ),

                  const SizedBox(height: 16),

                  // Video Calls
                  _GuideSection(
                    icon: Icons.videocam,
                    title: 'Video Calls',
                    gradient: [AppColors.accentOrange, AppColors.error],
                    content: '''
ENABLING VIDEO CALLS
Go to Settings → Privacy → Video Calls and toggle ON.

⚠️ PRIVACY WARNING
Video calls require direct P2P connection. The peer CAN see your IP address during calls. This is necessary for real-time streaming.

MAKING A CALL
1. Open a contact's chat
2. Tap the video camera icon in the top bar
3. Wait for them to answer

RECEIVING A CALL
When someone calls you:
• Accept to join the call
• Decline to reject
• You can also ignore and call back later

DURING A CALL
• Tap screen to show controls
• Toggle camera on/off
• Toggle microphone on/off
• Switch front/back camera
• End call

All video/audio is end-to-end encrypted.
''',
                  ),

                  const SizedBox(height: 16),

                  // Message Actions
                  _GuideSection(
                    icon: Icons.touch_app,
                    title: 'Message Actions',
                    gradient: [AppColors.primary, AppColors.accentGreen],
                    content: '''
Long-press any message to see available actions:

REPLY
Quote a message in your response. Shows the original message above your reply.

COPY
Copy message text to clipboard.

FORWARD
Send a message to another chat or group. Shows "Forwarded" label.

EDIT (Your messages only)
Change the text of a sent message. Shows "(edited)" indicator.

DELETE
• Delete for me - removes from your device
• Delete for everyone - removes for all (within time limit)

PIN (Groups - Admin only)
Pin important messages to the top of the chat. All members can see pinned messages.

UNPIN
Remove a pinned message from the pinned section.
''',
                  ),

                  const SizedBox(height: 16),

                  // Media Gallery
                  _GuideSection(
                    icon: Icons.photo_library,
                    title: 'Media Gallery',
                    gradient: [AppColors.accentGreen, AppColors.accent],
                    content: '''
VIEW SHARED MEDIA
In group chats, access all shared media in one place:

1. Open Group Info
2. Tap "Media Gallery" or the media section

TABS
• All - Everything shared in the group
• Images - Photos and pictures
• Videos - Video files
• Files - Documents, archives, other files

FEATURES
• Grid view for images/videos
• List view for files with icons
• Tap to view full-screen
• Pinch to zoom images
• Download files to device

Media is sorted by date (newest first).
''',
                  ),

                  const SizedBox(height: 16),

                  // Blocking
                  _GuideSection(
                    icon: Icons.block,
                    title: 'Blocking Contacts',
                    gradient: [AppColors.error, AppColors.accentOrange],
                    content: '''
BLOCK A CONTACT
1. Open the contact's chat
2. Tap their name at the top
3. Scroll down and tap "Block"
4. Confirm

WHAT HAPPENS WHEN BLOCKED
• They cannot send you messages
• They cannot see your online status
• They cannot add you to groups
• Existing messages remain visible

UNBLOCK
1. Go to the blocked contact's profile
2. Tap "Unblock"

Or go to Settings to manage all blocked contacts.

BLOCKING IN GROUPS
Admins can ban members from groups, which prevents them from rejoining via invite links.
''',
                  ),

                  const SizedBox(height: 16),

                  // Privacy Settings
                  _GuideSection(
                    icon: Icons.visibility_off,
                    title: 'Privacy Settings',
                    gradient: [AppColors.primary, AppColors.primaryLight],
                    content: '''
Go to Settings → Privacy to configure:

READ RECEIPTS
When enabled, others see blue checkmarks when you read their messages. Disable to hide your read status.

TYPING INDICATORS
When enabled, others see "typing..." when you're composing a message. Disable for more privacy.

SCREEN LOCK
Require authentication (PIN, fingerprint, face) to open CyxChat.

ONION ROUTING
Configure the number of hops for message routing:
• 2 hops - Faster, good privacy
• 5 hops - Slower, better anonymity
• 8 hops - Slowest, maximum anonymity

FAST FILE TRANSFER
Enable for larger files, but peer sees your IP.

VIDEO CALLS
Enable to allow video calling (requires direct P2P).
''',
                  ),

                  const SizedBox(height: 16),

                  // Privacy & Security
                  _GuideSection(
                    icon: Icons.security,
                    title: 'Privacy & Security',
                    gradient: [AppColors.primary, AppColors.primaryLight],
                    content: '''
ONION ROUTING
Every message is wrapped in multiple layers of encryption and routed through several nodes. Each node only knows the previous and next hop - not the full path.

Configure hop count in Settings → Privacy:
• 2 hops - Standard (1.2 KB payload)
• 5 hops - High anonymity (873 B payload)
• 8 hops - Maximum anonymity (561 B payload)

More hops = better anonymity but smaller message size.

ENCRYPTION
• X25519 for key exchange
• XChaCha20-Poly1305 for messages
• Automatic key refresh for forward secrecy

LOCAL STORAGE
All data stays on your device:
• Messages stored in SQLite
• Keys in secure storage
• Nothing synced to cloud
''',
                  ),

                  const SizedBox(height: 16),

                  // CyxWiz Protocol
                  _GuideSection(
                    icon: Icons.hub,
                    title: 'About CyxWiz Protocol',
                    gradient: [AppColors.accent, AppColors.accentGreen],
                    content: '''
CyxWiz is the underlying mesh network protocol that powers CyxChat.

DESIGN PHILOSOPHY
"Own Nothing. Access Everything. Leave No Trace."

CORE FEATURES
• UDP transport with NAT traversal
• Kademlia DHT for peer discovery
• SPDZ-based MPC cryptography
• Onion routing (like Tor, but P2P)
• Mesh routing for multi-hop delivery

WHY UDP?
• Works behind NAT/firewalls
• UDP hole punching for direct P2P
• Lower latency than TCP

BOOTSTRAP SERVER
The only "server" in CyxChat helps peers find each other initially. It:
• Provides STUN for NAT traversal
• Maintains a peer registry
• Relays messages if direct P2P fails

The bootstrap server NEVER sees message content - everything is end-to-end encrypted before it leaves your device.
''',
                  ),

                  const SizedBox(height: 16),

                  // Troubleshooting
                  _GuideSection(
                    icon: Icons.build,
                    title: 'Troubleshooting',
                    gradient: [AppColors.accentOrange, AppColors.error],
                    content: '''
CAN'T CONNECT TO PEERS
1. Check bootstrap server is configured
2. Verify you're connected (green indicator)
3. Check firewall isn't blocking UDP
4. Try a different network

MESSAGES NOT DELIVERING
• Peer may be offline
• Check your connection status
• Try sending again later
• Messages queue until peer comes online

FILE TRANSFER FAILING
• Check file size (64KB limit for onion)
• Enable Fast Transfer for larger files
• Ensure peer is online and connected

SLOW PERFORMANCE
• Reduce onion hop count
• Enable fast file transfer
• Check network quality

VIEW LOGS
Settings → Debug → View Logs to see detailed activity and errors.
''',
                  ),

                  const SizedBox(height: 16),

                  // FAQ
                  _GuideSection(
                    icon: Icons.help_outline,
                    title: 'FAQ',
                    gradient: [AppColors.primary, AppColors.accent],
                    content: '''
Q: Is CyxChat free?
A: Yes, completely free and open source.

Q: Can anyone see my messages?
A: No. Messages are end-to-end encrypted. Only you and the recipient can read them.

Q: What if I lose my device?
A: You'll lose your identity and messages. There's no cloud backup by design - this is for your privacy.

Q: Can I use CyxChat on multiple devices?
A: Currently, each device has its own identity. Multi-device sync is planned for the future.

Q: Is metadata protected?
A: Yes! Onion routing hides who talks to whom. The bootstrap server only sees encrypted blobs.

Q: What's the difference vs Signal/WhatsApp?
A: No central servers. No phone number required. True peer-to-peer with onion routing.

Q: How do I report bugs?
A: Visit github.com/code3hr/cyxchat/issues
''',
                  ),

                  const SizedBox(height: 32),

                  // Footer
                  Center(
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [AppColors.primary, AppColors.accent],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.lock,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'CyxChat v1.2.1',
                          style: TextStyle(
                            color: AppColors.textDarkSecondary,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Privacy by design. Security by default.',
                          style: TextStyle(
                            color: AppColors.textDarkSecondary.withOpacity(0.7),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A styled section in the user guide
class _GuideSection extends StatefulWidget {
  final IconData icon;
  final String title;
  final List<Color> gradient;
  final String content;

  const _GuideSection({
    required this.icon,
    required this.title,
    required this.gradient,
    required this.content,
  });

  @override
  State<_GuideSection> createState() => _GuideSectionState();
}

class _GuideSectionState extends State<_GuideSection> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.bgDarkSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.gradient[0].withOpacity(0.2),
          width: 1,
        ),
      ),
      child: Column(
        children: [
          // Header (always visible)
          InkWell(
            onTap: () => setState(() => _isExpanded = !_isExpanded),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: widget.gradient),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      widget.icon,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      Icons.keyboard_arrow_down,
                      color: AppColors.textDarkSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Content (expandable)
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bgDarkTertiary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  widget.content.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textDarkSecondary,
                    height: 1.5,
                  ),
                ),
              ),
            ),
            crossFadeState: _isExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 200),
          ),
        ],
      ),
    );
  }
}
