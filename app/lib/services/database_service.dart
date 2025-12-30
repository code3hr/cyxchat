import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

/// Database service for local storage
class DatabaseService {
  static final DatabaseService instance = DatabaseService._();
  static Database? _database;

  DatabaseService._();

  Future<Database> get database async {
    _database ??= await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'cyxchat.db');

    return await openDatabase(
      path,
      version: 2,
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
        FOREIGN KEY (message_id) REFERENCES messages(id)
      )
    ''');

    // Create email tables
    await _createEmailTables(db);
  }

  /// Create email/mail tables
  Future<void> _createEmailTables(Database db) async {
    // Email folders (Inbox, Sent, Drafts, Archive, Trash, Spam, Custom)
    await db.execute('''
      CREATE TABLE email_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        folder_type INTEGER NOT NULL,
        parent_id INTEGER,
        unread_count INTEGER DEFAULT 0,
        total_count INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL,
        FOREIGN KEY (parent_id) REFERENCES email_folders(id)
      )
    ''');

    // Email messages
    await db.execute('''
      CREATE TABLE email_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mail_id TEXT UNIQUE NOT NULL,
        folder_id INTEGER NOT NULL,
        from_node_id TEXT NOT NULL,
        from_name TEXT,
        to_addrs TEXT NOT NULL,
        cc_addrs TEXT,
        subject TEXT,
        body TEXT,
        timestamp INTEGER NOT NULL,
        in_reply_to TEXT,
        thread_id TEXT,
        flags INTEGER DEFAULT 0,
        status INTEGER DEFAULT 0,
        signature_valid INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        FOREIGN KEY (folder_id) REFERENCES email_folders(id)
      )
    ''');

    // Email attachments
    await db.execute('''
      CREATE TABLE email_attachments (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        mail_id TEXT NOT NULL,
        file_id TEXT NOT NULL,
        filename TEXT NOT NULL,
        mime_type TEXT,
        file_size INTEGER NOT NULL,
        file_hash TEXT,
        disposition INTEGER DEFAULT 0,
        storage_type INTEGER DEFAULT 0,
        content_id TEXT,
        inline_data BLOB,
        download_state INTEGER DEFAULT 0,
        local_path TEXT,
        FOREIGN KEY (mail_id) REFERENCES email_messages(mail_id)
      )
    ''');

    // Indexes for email
    await db.execute(
      'CREATE INDEX idx_email_folder ON email_messages(folder_id, timestamp DESC)',
    );
    await db.execute(
      'CREATE INDEX idx_email_thread ON email_messages(thread_id)',
    );
    await db.execute(
      'CREATE INDEX idx_email_from ON email_messages(from_node_id)',
    );
    await db.execute(
      'CREATE INDEX idx_email_attachments ON email_attachments(mail_id)',
    );

    // Insert default folders
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultFolders = [
      {'name': 'Inbox', 'type': 0},
      {'name': 'Sent', 'type': 1},
      {'name': 'Drafts', 'type': 2},
      {'name': 'Archive', 'type': 3},
      {'name': 'Trash', 'type': 4},
      {'name': 'Spam', 'type': 5},
    ];

    for (final folder in defaultFolders) {
      await db.insert('email_folders', {
        'name': folder['name'],
        'folder_type': folder['type'],
        'unread_count': 0,
        'total_count': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
  }

  Future<void> _upgradeDatabase(Database db, int oldVersion, int newVersion) async {
    // Handle migrations
    if (oldVersion < 2) {
      // Add email tables in version 2
      await _createEmailTables(db);
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
    await db.delete('email_attachments');
    await db.delete('email_messages');
    await db.delete('email_folders');
    await db.delete('offline_queue');
    await db.delete('group_members');
    await db.delete('groups');
    await db.delete('messages');
    await db.delete('conversations');
    await db.delete('contacts');
    await db.delete('identity');
    await db.delete('settings');

    // Re-create default email folders
    await _insertDefaultEmailFolders(db);
  }

  /// Insert default email folders
  Future<void> _insertDefaultEmailFolders(Database db) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final defaultFolders = [
      {'name': 'Inbox', 'type': 0},
      {'name': 'Sent', 'type': 1},
      {'name': 'Drafts', 'type': 2},
      {'name': 'Archive', 'type': 3},
      {'name': 'Trash', 'type': 4},
      {'name': 'Spam', 'type': 5},
    ];

    for (final folder in defaultFolders) {
      await db.insert('email_folders', {
        'name': folder['name'],
        'folder_type': folder['type'],
        'unread_count': 0,
        'total_count': 0,
        'created_at': now,
        'updated_at': now,
      });
    }
  }
}
