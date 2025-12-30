import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../main.dart';
import '../models/email_folder.dart';
import '../models/email_message.dart';
import '../providers/mail_provider.dart';
import 'mail_compose_screen.dart';
import 'mail_read_screen.dart';

/// Mail inbox screen with folder navigation and message list
class MailInboxScreen extends ConsumerStatefulWidget {
  const MailInboxScreen({super.key});

  @override
  ConsumerState<MailInboxScreen> createState() => _MailInboxScreenState();
}

class _MailInboxScreenState extends ConsumerState<MailInboxScreen> {
  int _selectedFolderId = 1; // Default to inbox (id=1)
  final Set<String> _selectedMessages = {};
  bool _isSelectionMode = false;

  @override
  Widget build(BuildContext context) {
    final foldersAsync = ref.watch(emailFoldersProvider);
    final messagesAsync = ref.watch(folderMessagesProvider(_selectedFolderId));

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
                      colors: [AppColors.accent, AppColors.accentGreen],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(
                    Icons.mail_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  _isSelectionMode
                      ? '${_selectedMessages.length} selected'
                      : 'CyxMail',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                  ),
                ),
              ],
            ),
            actions: _buildAppBarActions(),
          ),
          // Folder chips
          SliverToBoxAdapter(
            child: foldersAsync.when(
              data: (folders) => _FolderChips(
                folders: folders,
                selectedFolderId: _selectedFolderId,
                onFolderSelected: (id) => setState(() => _selectedFolderId = id),
              ),
              loading: () => const SizedBox(height: 60),
              error: (_, __) => const SizedBox(),
            ),
          ),
          // Messages
          messagesAsync.when(
            data: (messages) => messages.isEmpty
                ? const SliverFillRemaining(child: _EmptyInbox())
                : SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _MailCard(
                            message: messages[index],
                            isSelectionMode: _isSelectionMode,
                            isSelected: _selectedMessages.contains(messages[index].mailId),
                            onTap: () => _openMessage(messages[index]),
                            onLongPress: () => _startSelection(messages[index].mailId),
                            onSelectionToggle: () => _toggleSelection(messages[index].mailId),
                            onArchive: () => ref.read(mailActionsProvider).archive(messages[index].mailId),
                            onDelete: () => ref.read(mailActionsProvider).delete(messages[index].mailId),
                          ),
                        ),
                        childCount: messages.length,
                      ),
                    ),
                  ),
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
                          AppColors.accent.withOpacity(0.8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Loading emails...',
                      style: TextStyle(
                        color: AppColors.textDarkSecondary.withOpacity(0.6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            error: (e, s) => SliverFillRemaining(
              child: _ErrorState(error: e.toString()),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'mail_fab',
        onPressed: _composeMail,
        backgroundColor: AppColors.accent,
        child: const Icon(Icons.edit_rounded, color: Colors.black),
      ),
    );
  }

  List<Widget> _buildAppBarActions() {
    if (_isSelectionMode) {
      return [
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bgDarkSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.mark_email_read_rounded, size: 20),
          ),
          onPressed: _markSelectedAsRead,
          tooltip: 'Mark as read',
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bgDarkSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.delete_outline_rounded, size: 20),
          ),
          onPressed: _deleteSelected,
          tooltip: 'Delete',
        ),
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.bgDarkSecondary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.close_rounded, size: 20),
          ),
          onPressed: () => setState(() {
            _isSelectionMode = false;
            _selectedMessages.clear();
          }),
          tooltip: 'Cancel',
        ),
        const SizedBox(width: 8),
      ];
    }
    return [
      IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.bgDarkSecondary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.search_rounded, size: 20),
        ),
        onPressed: _openSearch,
        tooltip: 'Search',
      ),
      IconButton(
        icon: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.bgDarkSecondary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.refresh_rounded, size: 20),
        ),
        onPressed: () => ref.refresh(folderMessagesProvider(_selectedFolderId)),
        tooltip: 'Refresh',
      ),
      const SizedBox(width: 8),
    ];
  }

  void _toggleSelection(String mailId) {
    setState(() {
      if (_selectedMessages.contains(mailId)) {
        _selectedMessages.remove(mailId);
        if (_selectedMessages.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedMessages.add(mailId);
      }
    });
  }

  void _startSelection(String mailId) {
    setState(() {
      _isSelectionMode = true;
      _selectedMessages.add(mailId);
    });
  }

  void _openMessage(EmailMessage message) {
    if (!message.isRead) {
      ref.read(mailActionsProvider).markAsRead(message.mailId);
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => MailReadScreen(mailId: message.mailId),
      ),
    );
  }

  void _composeMail() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const MailComposeScreen(),
      ),
    );
  }

  void _openSearch() {
    showSearch(
      context: context,
      delegate: _MailSearchDelegate(),
    );
  }

  void _markSelectedAsRead() {
    for (final mailId in _selectedMessages) {
      ref.read(mailActionsProvider).markAsRead(mailId);
    }
    setState(() {
      _isSelectionMode = false;
      _selectedMessages.clear();
    });
  }

  void _deleteSelected() {
    for (final mailId in _selectedMessages) {
      ref.read(mailActionsProvider).delete(mailId);
    }
    setState(() {
      _isSelectionMode = false;
      _selectedMessages.clear();
    });
  }
}

/// Folder chips for horizontal scrolling
class _FolderChips extends StatelessWidget {
  final List<EmailFolder> folders;
  final int selectedFolderId;
  final Function(int) onFolderSelected;

  const _FolderChips({
    required this.folders,
    required this.selectedFolderId,
    required this.onFolderSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: folders.length,
        itemBuilder: (context, index) {
          final folder = folders[index];
          final isSelected = folder.id == selectedFolderId;

          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: GestureDetector(
              onTap: () => onFolderSelected(folder.id),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  gradient: isSelected
                      ? const LinearGradient(
                          colors: [AppColors.accent, AppColors.accentGreen],
                        )
                      : null,
                  color: isSelected ? null : AppColors.bgDarkSecondary,
                  borderRadius: BorderRadius.circular(20),
                  border: isSelected
                      ? null
                      : Border.all(color: AppColors.bgDarkTertiary),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _getFolderIcon(folder.type),
                      size: 18,
                      color: isSelected ? Colors.black : AppColors.textDarkSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      folder.name,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                        color: isSelected ? Colors.black : AppColors.textDarkSecondary,
                      ),
                    ),
                    if (folder.unreadCount > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? Colors.black.withOpacity(0.2)
                              : AppColors.accent.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${folder.unreadCount}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.black : AppColors.accent,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  IconData _getFolderIcon(EmailFolderType type) {
    switch (type) {
      case EmailFolderType.inbox:
        return Icons.inbox_rounded;
      case EmailFolderType.sent:
        return Icons.send_rounded;
      case EmailFolderType.drafts:
        return Icons.drafts_rounded;
      case EmailFolderType.archive:
        return Icons.archive_rounded;
      case EmailFolderType.trash:
        return Icons.delete_rounded;
      case EmailFolderType.spam:
        return Icons.report_rounded;
      case EmailFolderType.custom:
        return Icons.folder_rounded;
    }
  }
}

/// Empty inbox state
class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

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
                    AppColors.accent.withOpacity(0.15),
                    AppColors.accentGreen.withOpacity(0.15),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Icon(
                Icons.inbox_rounded,
                size: 40,
                color: AppColors.accent.withOpacity(0.7),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No emails yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Compose a new email to get started\nwith decentralized messaging',
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
                    Icons.cloud_off_rounded,
                    size: 14,
                    color: AppColors.accent.withOpacity(0.8),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'No servers required',
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

/// Error state widget
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
              'Failed to load emails',
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

/// Mail card widget
class _MailCard extends StatelessWidget {
  final EmailMessage message;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onSelectionToggle;
  final VoidCallback onArchive;
  final VoidCallback onDelete;

  const _MailCard({
    required this.message,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onTap,
    required this.onLongPress,
    required this.onSelectionToggle,
    required this.onArchive,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(message.mailId),
      background: Container(
        decoration: BoxDecoration(
          color: AppColors.accentGreen.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: const Icon(Icons.archive_rounded, color: AppColors.accentGreen),
      ),
      secondaryBackground: Container(
        decoration: BoxDecoration(
          color: AppColors.error.withOpacity(0.2),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: const Icon(Icons.delete_rounded, color: AppColors.error),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onArchive();
        } else {
          onDelete();
        }
        return true;
      },
      child: Material(
        color: isSelected
            ? AppColors.primary.withOpacity(0.15)
            : AppColors.bgDarkSecondary,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: isSelectionMode ? onSelectionToggle : onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar or checkbox
                if (isSelectionMode)
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary
                          : AppColors.bgDarkTertiary,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      isSelected ? Icons.check_rounded : Icons.circle_outlined,
                      color: isSelected ? Colors.white : AppColors.textDarkSecondary,
                    ),
                  )
                else
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      gradient: message.isRead
                          ? null
                          : const LinearGradient(
                              colors: [AppColors.accent, AppColors.accentGreen],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                      color: message.isRead ? AppColors.bgDarkTertiary : null,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Center(
                      child: Text(
                        message.from.display.isNotEmpty
                            ? message.from.display[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: message.isRead
                              ? AppColors.textDarkSecondary
                              : Colors.black,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 14),
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              message.from.display,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight:
                                    message.isRead ? FontWeight.w500 : FontWeight.w600,
                                color: AppColors.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            message.dateString,
                            style: TextStyle(
                              fontSize: 12,
                              color: message.isRead
                                  ? AppColors.textDarkSecondary.withOpacity(0.6)
                                  : AppColors.accent,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Subject
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              message.subject ?? '(no subject)',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight:
                                    message.isRead ? FontWeight.normal : FontWeight.w500,
                                color: AppColors.textDark,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (message.isFlagged)
                            Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.star_rounded,
                                size: 18,
                                color: AppColors.accentOrange,
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Preview
                      Row(
                        children: [
                          if (message.hasAttachments)
                            Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: Icon(
                                Icons.attach_file_rounded,
                                size: 14,
                                color: AppColors.textDarkSecondary.withOpacity(0.6),
                              ),
                            ),
                          Expanded(
                            child: Text(
                              message.preview,
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.textDarkSecondary.withOpacity(0.7),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Search delegate for email
class _MailSearchDelegate extends SearchDelegate<EmailMessage?> {
  _MailSearchDelegate() : super(
    searchFieldStyle: const TextStyle(
      color: AppColors.textDark,
      fontSize: 16,
    ),
  );

  @override
  ThemeData appBarTheme(BuildContext context) {
    return Theme.of(context).copyWith(
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.bgDark,
        foregroundColor: AppColors.textDark,
      ),
      inputDecorationTheme: const InputDecorationTheme(
        hintStyle: TextStyle(color: AppColors.textDarkSecondary),
        border: InputBorder.none,
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(
          icon: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.bgDarkSecondary,
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.close_rounded, size: 18),
          ),
          onPressed: () => query = '',
        ),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back_rounded),
      onPressed: () => close(context, null),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return Consumer(
      builder: (context, ref, child) {
        final results = ref.watch(emailSearchProvider(query));
        return Container(
          color: AppColors.bgDark,
          child: results.when(
            data: (messages) => messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.search_off_rounded,
                          size: 48,
                          color: AppColors.textDarkSecondary.withOpacity(0.5),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No results found',
                          style: TextStyle(
                            color: AppColors.textDarkSecondary.withOpacity(0.7),
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Material(
                          color: AppColors.bgDarkSecondary,
                          borderRadius: BorderRadius.circular(12),
                          child: ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: AppColors.bgDarkTertiary,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Center(
                                child: Text(
                                  message.from.display.isNotEmpty
                                      ? message.from.display[0].toUpperCase()
                                      : '?',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.textDarkSecondary,
                                  ),
                                ),
                              ),
                            ),
                            title: Text(
                              message.from.display,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                            subtitle: Text(
                              message.subject ?? '(no subject)',
                              style: TextStyle(
                                color: AppColors.textDarkSecondary.withOpacity(0.7),
                              ),
                            ),
                            onTap: () => close(context, message),
                          ),
                        ),
                      );
                    },
                  ),
            loading: () => Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(
                  AppColors.accent.withOpacity(0.8),
                ),
              ),
            ),
            error: (e, s) => Center(
              child: Text(
                'Error: $e',
                style: const TextStyle(color: AppColors.error),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return Container(
        color: AppColors.bgDark,
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search_rounded,
                size: 48,
                color: AppColors.textDarkSecondary.withOpacity(0.5),
              ),
              const SizedBox(height: 16),
              Text(
                'Search emails',
                style: TextStyle(
                  color: AppColors.textDarkSecondary.withOpacity(0.7),
                ),
              ),
            ],
          ),
        ),
      );
    }
    return buildResults(context);
  }
}
