import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Instance ID for running multiple test instances
/// Set via --dart-define=INSTANCE_ID=2
const String _instanceId = String.fromEnvironment('INSTANCE_ID', defaultValue: '');

/// Database service for local storage
class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  static Database? _database;

  DatabaseService._();

  /// Get instance suffix for display
  static String get instanceSuffix => _instanceId.isEmpty ? '' : ' (Instance $_instanceId)';

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final dbName = _instanceId.isEmpty ? 'cyxchat.db' : 'cyxchat_$_instanceId.db';
    final path = join(dbPath, dbName);

    return await openDatabase(
      path,
      version: 10,
      onCreate: _createDatabase,
      onUpgrade: _upgradeDatabase,
    );
  }

  Future<void> _createDatabase(Database db, int version) async {
    // Identity table
    await db.execute('''
      CREATE TABLE identity (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        node_id TEXT UNIQUE NOT NULL,
        display_name TEXT,
        public_key BLOB NOT NULL,
        private_key_encrypted BLOB NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    // Contacts table
    await db.execute('''
      CREATE TABLE contacts (
        node_id TEXT PRIMARY KEY,
        public_key BLOB NOT NULL,
        display_name TEXT,
        verified INTEGER DEFAULT 0,
        blocked INTEGER DEFAULT 0,
        added_at INTEGER NOT NULL,
        last_seen INTEGER,
        presence INTEGER DEFAULT 0,
        status_text TEXT
      )
    ''');

    // Conversations table
    await db.execute('''
      CREATE TABLE conversations (
        id TEXT PRIMARY KEY,
        type INTEGER NOT NULL,
        peer_id TEXT,
        group_id TEXT,
        display_name TEXT,
        avatar_url TEXT,
        unread_count INTEGER DEFAULT 0,
        is_pinned INTEGER DEFAULT 0,
        is_archived INTEGER DEFAULT 0,
        is_muted INTEGER DEFAULT 0,
        last_activity_at INTEGER,
        FOREIGN KEY (peer_id) REFERENCES contacts(node_id)
      )
    ''');

    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        conversation_id TEXT NOT NULL,
        sender_id TEXT NOT NULL,
        type INTEGER DEFAULT 0,
        content TEXT NOT NULL,
        timestamp INTEGER NOT NULL,
        status INTEGER DEFAULT 0,
        reply_to_id TEXT,
        is_outgoing INTEGER NOT NULL,
        is_edited INTEGER DEFAULT 0,
        is_deleted INTEGER DEFAULT 0,
        original_content TEXT,
        edited_at INTEGER,
        deleted_by TEXT,
        deleted_at INTEGER,
        forwarded_from TEXT,
        media_type TEXT,
        media_metadata TEXT,
        thumbnail_path TEXT,
        FOREIGN KEY (conversation_id) REFERENCES conversations(id)
      )
    ''');

    // Create indexes
    await db.execute(
      'CREATE INDEX idx_messages_conversation ON messages(conversation_id, timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_conversations_activity ON conversations(last_activity_at DESC)',
    );

    // Groups table
    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        description TEXT,
        creator_id TEXT NOT NULL,
        group_key_encrypted BLOB,
        key_version INTEGER DEFAULT 1,
        group_type INTEGER DEFAULT 0,
        who_can_add_members INTEGER DEFAULT 0,
        who_can_change_info INTEGER DEFAULT 1,
        message_history_visible INTEGER DEFAULT 1,
        slow_mode_seconds INTEGER DEFAULT 0,
        max_members INTEGER DEFAULT 200,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Group members table
    await db.execute('''
      CREATE TABLE group_members (
        group_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        role INTEGER DEFAULT 0,
        display_name TEXT,
        public_key BLOB,
        joined_at INTEGER NOT NULL,
        PRIMARY KEY (group_id, node_id),
        FOREIGN KEY (group_id) REFERENCES groups(id)
      )
    ''');

    // Admin permissions table (granular per-admin control)
    await db.execute('''
      CREATE TABLE admin_permissions (
        group_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        can_add_members INTEGER DEFAULT 1,
        can_remove_members INTEGER DEFAULT 1,
        can_delete_messages INTEGER DEFAULT 1,
        can_pin_messages INTEGER DEFAULT 0,
        can_change_info INTEGER DEFAULT 1,
        can_ban_users INTEGER DEFAULT 0,
        can_manage_admins INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (group_id, node_id),
        FOREIGN KEY (group_id) REFERENCES groups(id)
      )
    ''');

    // Member restrictions table (mute, media/link restrictions, slow mode)
    await db.execute('''
      CREATE TABLE member_restrictions (
        group_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        is_muted INTEGER DEFAULT 0,
        muted_until INTEGER,
        can_send_media INTEGER DEFAULT 1,
        can_send_links INTEGER DEFAULT 1,
        can_send_messages INTEGER DEFAULT 1,
        slow_mode_seconds INTEGER DEFAULT 0,
        last_message_at INTEGER,
        restricted_by TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        PRIMARY KEY (group_id, node_id),
        FOREIGN KEY (group_id) REFERENCES groups(id)
      )
    ''');

    // Pinned messages table
    await db.execute('''
      CREATE TABLE pinned_messages (
        group_id TEXT NOT NULL,
        message_id TEXT NOT NULL,
        pinned_by TEXT NOT NULL,
        pinned_at INTEGER NOT NULL,
        PRIMARY KEY (group_id, message_id),
        FOREIGN KEY (group_id) REFERENCES groups(id),
        FOREIGN KEY (message_id) REFERENCES messages(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_pinned_messages_group ON pinned_messages(group_id, pinned_at DESC)'
    );

    // Invite links table
    await db.execute('''
      CREATE TABLE group_invite_links (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        created_by TEXT NOT NULL,
        created_at INTEGER NOT NULL,
        expires_at INTEGER,
        max_uses INTEGER,
        use_count INTEGER DEFAULT 0,
        is_revoked INTEGER DEFAULT 0,
        link_name TEXT,
        FOREIGN KEY (group_id) REFERENCES groups(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_invite_links_group ON group_invite_links(group_id, created_at DESC)'
    );

    // Invite link usage table (tracks who joined via which link)
    await db.execute('''
      CREATE TABLE invite_link_usage (
        link_id TEXT NOT NULL,
        node_id TEXT NOT NULL,
        joined_at INTEGER NOT NULL,
        PRIMARY KEY (link_id, node_id),
        FOREIGN KEY (link_id) REFERENCES group_invite_links(id)
      )
    ''');

    // Admin actions log table (Phase 4)
    await db.execute('''
      CREATE TABLE admin_actions (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        admin_id TEXT NOT NULL,
        action_type INTEGER NOT NULL,
        target_id TEXT,
        target_message_id TEXT,
        old_value TEXT,
        new_value TEXT,
        timestamp INTEGER NOT NULL,
        FOREIGN KEY (group_id) REFERENCES groups(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX idx_admin_actions_group ON admin_actions(group_id, timestamp DESC)'
    );
    await db.execute(
      'CREATE INDEX idx_admin_actions_admin ON admin_actions(admin_id, timestamp DESC)'
    );

    // Settings table
    await db.execute('''
      CREATE TABLE settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    // Offline message queue
    await db.execute('''
      CREATE TABLE offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        message_id TEXT NOT NULL,
        recipient_id TEXT NOT NULL,
        data BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_attempt_at INTEGER,
        next_retry_at INTEGER NOT NULL DEFAULT 0,
        last_error TEXT,
        FOREIGN KEY (message_id) REFERENCES messages(id)
      )
    ''');

    // Index for efficient queue processing
    await db.execute(
      'CREATE INDEX idx_offline_queue_retry ON offline_queue(next_retry_at ASC)'
    );
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    // Handle migrations
    if (oldVersion < 3) {
      // Version 3: Remove email tables (email feature removed)
      // Drop email tables if they exist from previous versions
      await db.execute('DROP TABLE IF EXISTS email_attachments');
      await db.execute('DROP TABLE IF EXISTS email_messages');
      await db.execute('DROP TABLE IF EXISTS email_folders');
    }

    if (oldVersion < 4) {
      // Version 4: Add Telegram-like group features

      // Add new columns to groups table
      await db.execute('ALTER TABLE groups ADD COLUMN group_type INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE groups ADD COLUMN who_can_add_members INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE groups ADD COLUMN who_can_change_info INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE groups ADD COLUMN message_history_visible INTEGER DEFAULT 1');
      await db.execute('ALTER TABLE groups ADD COLUMN slow_mode_seconds INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE groups ADD COLUMN max_members INTEGER DEFAULT 200');

      // Create admin permissions table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS admin_permissions (
          group_id TEXT NOT NULL,
          node_id TEXT NOT NULL,
          can_add_members INTEGER DEFAULT 1,
          can_remove_members INTEGER DEFAULT 1,
          can_delete_messages INTEGER DEFAULT 1,
          can_pin_messages INTEGER DEFAULT 0,
          can_change_info INTEGER DEFAULT 1,
          can_ban_users INTEGER DEFAULT 0,
          can_manage_admins INTEGER DEFAULT 0,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (group_id, node_id),
          FOREIGN KEY (group_id) REFERENCES groups(id)
        )
      ''');

      // Create member restrictions table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS member_restrictions (
          group_id TEXT NOT NULL,
          node_id TEXT NOT NULL,
          is_muted INTEGER DEFAULT 0,
          muted_until INTEGER,
          can_send_media INTEGER DEFAULT 1,
          can_send_links INTEGER DEFAULT 1,
          can_send_messages INTEGER DEFAULT 1,
          slow_mode_seconds INTEGER DEFAULT 0,
          last_message_at INTEGER,
          restricted_by TEXT,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL,
          PRIMARY KEY (group_id, node_id),
          FOREIGN KEY (group_id) REFERENCES groups(id)
        )
      ''');
    }

    if (oldVersion < 5) {
      // Version 5: Add message actions support (Phase 2)

      // Add message action columns to messages table
      await db.execute('ALTER TABLE messages ADD COLUMN original_content TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN edited_at INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN deleted_by TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN deleted_at INTEGER');
      await db.execute('ALTER TABLE messages ADD COLUMN forwarded_from TEXT');

      // Create pinned messages table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS pinned_messages (
          group_id TEXT NOT NULL,
          message_id TEXT NOT NULL,
          pinned_by TEXT NOT NULL,
          pinned_at INTEGER NOT NULL,
          PRIMARY KEY (group_id, message_id),
          FOREIGN KEY (group_id) REFERENCES groups(id),
          FOREIGN KEY (message_id) REFERENCES messages(id)
        )
      ''');

      // Create index for pinned messages
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_pinned_messages_group ON pinned_messages(group_id, pinned_at DESC)'
      );
    }

    if (oldVersion < 6) {
      // Version 6: Add invite links support (Phase 3)

      // Create invite links table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS group_invite_links (
          id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          created_by TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          expires_at INTEGER,
          max_uses INTEGER,
          use_count INTEGER DEFAULT 0,
          is_revoked INTEGER DEFAULT 0,
          link_name TEXT,
          FOREIGN KEY (group_id) REFERENCES groups(id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_invite_links_group ON group_invite_links(group_id, created_at DESC)'
      );

      // Create invite link usage table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS invite_link_usage (
          link_id TEXT NOT NULL,
          node_id TEXT NOT NULL,
          joined_at INTEGER NOT NULL,
          PRIMARY KEY (link_id, node_id),
          FOREIGN KEY (link_id) REFERENCES group_invite_links(id)
        )
      ''');
    }

    if (oldVersion < 7) {
      // Version 7: Add admin actions log (Phase 4)

      // Create admin actions table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS admin_actions (
          id TEXT PRIMARY KEY,
          group_id TEXT NOT NULL,
          admin_id TEXT NOT NULL,
          action_type INTEGER NOT NULL,
          target_id TEXT,
          target_message_id TEXT,
          old_value TEXT,
          new_value TEXT,
          timestamp INTEGER NOT NULL,
          FOREIGN KEY (group_id) REFERENCES groups(id)
        )
      ''');
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_admin_actions_group ON admin_actions(group_id, timestamp DESC)'
      );
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_admin_actions_admin ON admin_actions(admin_id, timestamp DESC)'
      );
    }

    if (oldVersion < 8) {
      // Version 8: Add media columns for group file sharing (Phase 5)

      // Add media columns to messages table
      await db.execute('ALTER TABLE messages ADD COLUMN media_type TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN media_metadata TEXT');
      await db.execute('ALTER TABLE messages ADD COLUMN thumbnail_path TEXT');

      // Create media index for gallery queries
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_messages_media ON messages(conversation_id, media_type) WHERE media_type IS NOT NULL'
      );
    }

    if (oldVersion < 9) {
      // Version 9: Add is_archived column to conversations table
      await db.execute('ALTER TABLE conversations ADD COLUMN is_archived INTEGER DEFAULT 0');
    }

    if (oldVersion < 10) {
      // Version 10: Enhanced offline message queue for retry logic
      await db.execute('ALTER TABLE offline_queue ADD COLUMN last_attempt_at INTEGER');
      await db.execute('ALTER TABLE offline_queue ADD COLUMN next_retry_at INTEGER NOT NULL DEFAULT 0');
      await db.execute('ALTER TABLE offline_queue ADD COLUMN last_error TEXT');

      // Index for efficient queue processing
      await db.execute(
        'CREATE INDEX IF NOT EXISTS idx_offline_queue_retry ON offline_queue(next_retry_at ASC)'
      );
    }
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// Clear all data (for logout)
  Future<void> clearAllData() async {
    final db = await database;
    await db.delete('offline_queue');
    await db.delete('admin_actions');
    await db.delete('invite_link_usage');
    await db.delete('group_invite_links');
    await db.delete('pinned_messages');
    await db.delete('member_restrictions');
    await db.delete('admin_permissions');
    await db.delete('group_members');
    await db.delete('groups');
    await db.delete('messages');
    await db.delete('conversations');
    await db.delete('contacts');
    await db.delete('identity');
    await db.delete('settings');
  }
}
