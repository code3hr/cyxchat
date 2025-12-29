# CyxChat Database Schema

## Overview

CyxChat uses SQLite with SQLCipher encryption for local storage. All data is encrypted at rest using a key derived from the user's device credentials.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Database Architecture                               │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                     SQLCipher Encrypted                          │   │
│  │  ┌───────────────────────────────────────────────────────────┐  │   │
│  │  │                                                            │  │   │
│  │  │   identity ◄──────┐                                       │  │   │
│  │  │                    │                                       │  │   │
│  │  │   contacts ◄───────┼───► conversations ◄───► messages     │  │   │
│  │  │       │            │           │                           │  │   │
│  │  │       │            │           │                           │  │   │
│  │  │       ▼            │           ▼                           │  │   │
│  │  │   blocked_users    │      attachments                      │  │   │
│  │  │                    │                                       │  │   │
│  │  │   groups ◄─────────┘                                       │  │   │
│  │  │       │                                                    │  │   │
│  │  │       ▼                                                    │  │   │
│  │  │   group_members                                            │  │   │
│  │  │                                                            │  │   │
│  │  │   offline_queue    pending_acks    key_exchange           │  │   │
│  │  │                                                            │  │   │
│  │  └───────────────────────────────────────────────────────────┘  │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Database Configuration

### Encryption Setup

```sql
-- Open database with encryption
PRAGMA key = 'user-derived-encryption-key';

-- Verify encryption is working
PRAGMA cipher_version;

-- Performance settings
PRAGMA journal_mode = WAL;
PRAGMA synchronous = NORMAL;
PRAGMA foreign_keys = ON;
PRAGMA auto_vacuum = INCREMENTAL;
```

### Database File Location

| Platform | Path |
|----------|------|
| Windows | `%APPDATA%\CyxChat\cyxchat.db` |
| macOS | `~/Library/Application Support/CyxChat/cyxchat.db` |
| Linux | `~/.local/share/cyxchat/cyxchat.db` |
| Android | `/data/data/com.cyxwiz.cyxchat/databases/cyxchat.db` |
| iOS | `Documents/cyxchat.db` |

---

## Schema Definition

### 1. Identity Table

Stores the user's own identity (single row).

```sql
CREATE TABLE identity (
    id                    INTEGER PRIMARY KEY CHECK (id = 1),
    node_id               BLOB NOT NULL UNIQUE,           -- 32 bytes, our node ID
    public_key            BLOB NOT NULL,                  -- 32 bytes, X25519 public
    private_key_encrypted BLOB NOT NULL,                  -- Encrypted private key
    display_name          TEXT,                           -- Optional display name
    avatar_blob           BLOB,                           -- Avatar image data
    avatar_hash           TEXT,                           -- Avatar hash for sync
    status_text           TEXT,                           -- Custom status message
    created_at            INTEGER NOT NULL,               -- Unix timestamp (ms)
    updated_at            INTEGER NOT NULL,               -- Last update timestamp
    key_version           INTEGER DEFAULT 1,              -- Key rotation version
    key_rotated_at        INTEGER,                        -- Last key rotation time
    backup_enabled        INTEGER DEFAULT 0,              -- Recovery phrase backed up
    settings_json         TEXT                            -- JSON settings blob
);

-- Example insert
INSERT INTO identity (
    id, node_id, public_key, private_key_encrypted,
    display_name, created_at, updated_at
) VALUES (
    1,
    X'a1b2c3d4...', -- 32 bytes
    X'e5f6g7h8...', -- 32 bytes
    X'encrypted...',
    'Alice',
    1703980800000,
    1703980800000
);
```

### 2. Contacts Table

Stores known contacts.

```sql
CREATE TABLE contacts (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    node_id         BLOB NOT NULL UNIQUE,               -- 32 bytes, contact's node ID
    public_key      BLOB NOT NULL,                      -- 32 bytes, their X25519 public
    display_name    TEXT,                               -- Name we gave them
    their_name      TEXT,                               -- Name they shared with us
    avatar_blob     BLOB,                               -- Cached avatar
    avatar_hash     TEXT,                               -- Avatar hash
    verified        INTEGER DEFAULT 0,                  -- Key verified (safety number)
    verified_at     INTEGER,                            -- When verified
    trust_level     INTEGER DEFAULT 0,                  -- 0=unknown, 1=low, 2=medium, 3=high
    added_at        INTEGER NOT NULL,                   -- When added
    last_seen       INTEGER,                            -- Last online timestamp
    last_message_at INTEGER,                            -- Last message timestamp
    presence        INTEGER DEFAULT 0,                  -- 0=offline, 1=online, 2=away, 3=busy
    presence_text   TEXT,                               -- Custom presence status
    notes           TEXT,                               -- Private notes about contact
    favorite        INTEGER DEFAULT 0,                  -- Pinned/favorite contact
    notification    INTEGER DEFAULT 1                   -- Notifications enabled
);

CREATE INDEX idx_contacts_node_id ON contacts(node_id);
CREATE INDEX idx_contacts_last_message ON contacts(last_message_at DESC);
CREATE INDEX idx_contacts_favorite ON contacts(favorite DESC, display_name);
```

### 3. Blocked Users Table

Separate table for blocked users (for quick lookup).

```sql
CREATE TABLE blocked_users (
    node_id     BLOB PRIMARY KEY,                       -- 32 bytes
    blocked_at  INTEGER NOT NULL,                       -- When blocked
    reason      TEXT                                    -- Optional reason
);
```

### 4. Conversations Table

Represents a chat thread (1:1 or group).

```sql
CREATE TABLE conversations (
    id                INTEGER PRIMARY KEY AUTOINCREMENT,
    type              INTEGER NOT NULL,                 -- 0=direct, 1=group
    peer_id           BLOB,                             -- For direct: contact's node_id
    group_id          BLOB,                             -- For group: group identifier
    title             TEXT,                             -- Display title (group name or contact name)
    avatar_blob       BLOB,                             -- Conversation avatar
    created_at        INTEGER NOT NULL,                 -- Creation timestamp
    updated_at        INTEGER NOT NULL,                 -- Last activity timestamp
    last_message_id   INTEGER,                          -- FK to last message
    last_message_text TEXT,                             -- Preview text
    last_message_at   INTEGER,                          -- Last message timestamp
    unread_count      INTEGER DEFAULT 0,                -- Unread message count
    muted             INTEGER DEFAULT 0,                -- Mute notifications
    muted_until       INTEGER,                          -- Mute until timestamp (0=forever)
    pinned            INTEGER DEFAULT 0,                -- Pinned to top
    pinned_at         INTEGER,                          -- When pinned
    archived          INTEGER DEFAULT 0,                -- Archived conversation
    draft_text        TEXT,                             -- Unsent draft message
    draft_updated_at  INTEGER,                          -- Draft timestamp

    FOREIGN KEY (peer_id) REFERENCES contacts(node_id) ON DELETE SET NULL,
    FOREIGN KEY (group_id) REFERENCES groups(group_id) ON DELETE CASCADE
);

CREATE INDEX idx_conversations_updated ON conversations(updated_at DESC);
CREATE INDEX idx_conversations_pinned ON conversations(pinned DESC, updated_at DESC);
CREATE INDEX idx_conversations_peer ON conversations(peer_id);
CREATE INDEX idx_conversations_group ON conversations(group_id);
CREATE INDEX idx_conversations_unread ON conversations(unread_count) WHERE unread_count > 0;
```

### 5. Messages Table

Stores all messages.

```sql
CREATE TABLE messages (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    conversation_id INTEGER NOT NULL,                   -- FK to conversations
    msg_id          BLOB NOT NULL UNIQUE,               -- 8 bytes, unique message ID
    sender_id       BLOB NOT NULL,                      -- 32 bytes, sender's node_id
    type            INTEGER NOT NULL,                   -- Message type (text, file, etc.)

    -- Content
    content_text    TEXT,                               -- Text content (for text messages)
    content_blob    BLOB,                               -- Binary content (for files)
    content_json    TEXT,                               -- JSON metadata

    -- Status tracking
    status          INTEGER DEFAULT 0,                  -- 0=sending, 1=sent, 2=delivered, 3=read, 4=failed
    status_updated  INTEGER,                            -- Status change timestamp

    -- Timestamps
    created_at      INTEGER NOT NULL,                   -- When created locally
    sent_at         INTEGER,                            -- When sent to network
    delivered_at    INTEGER,                            -- When ACK received
    read_at         INTEGER,                            -- When read receipt received

    -- Threading
    reply_to_id     INTEGER,                            -- FK to parent message (for replies)
    thread_id       INTEGER,                            -- Thread root message ID

    -- Edit/Delete
    edited          INTEGER DEFAULT 0,                  -- Has been edited
    edited_at       INTEGER,                            -- Edit timestamp
    original_text   TEXT,                               -- Original text before edit
    deleted         INTEGER DEFAULT 0,                  -- Soft deleted
    deleted_at      INTEGER,                            -- Delete timestamp

    -- Reactions
    reactions_json  TEXT,                               -- JSON: {"emoji": ["node_id", ...]}

    -- Expiry (disappearing messages)
    expires_at      INTEGER,                            -- Auto-delete timestamp
    expire_seconds  INTEGER,                            -- TTL in seconds (0=never)

    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
    FOREIGN KEY (reply_to_id) REFERENCES messages(id) ON DELETE SET NULL
);

CREATE INDEX idx_messages_conversation ON messages(conversation_id, created_at DESC);
CREATE INDEX idx_messages_msg_id ON messages(msg_id);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_status ON messages(status) WHERE status < 3;
CREATE INDEX idx_messages_reply ON messages(reply_to_id) WHERE reply_to_id IS NOT NULL;
CREATE INDEX idx_messages_expires ON messages(expires_at) WHERE expires_at IS NOT NULL;
```

### Message Types

```sql
-- Message type constants
-- 0x00-0x0F: System messages
-- 0x10-0x1F: Chat messages (matching C protocol)

CREATE TABLE message_types (
    type_id     INTEGER PRIMARY KEY,
    name        TEXT NOT NULL,
    description TEXT
);

INSERT INTO message_types VALUES
    (0x00, 'SYSTEM_INFO', 'System information message'),
    (0x01, 'SYSTEM_ERROR', 'System error message'),
    (0x10, 'CHAT_TEXT', 'Text message'),
    (0x11, 'CHAT_ACK', 'Delivery acknowledgment'),
    (0x12, 'CHAT_READ', 'Read receipt'),
    (0x13, 'CHAT_TYPING', 'Typing indicator'),
    (0x14, 'CHAT_FILE', 'File attachment'),
    (0x15, 'CHAT_FILE_CHUNK', 'File chunk'),
    (0x16, 'CHAT_GROUP', 'Group message'),
    (0x17, 'CHAT_GROUP_INVITE', 'Group invitation'),
    (0x18, 'CHAT_GROUP_JOIN', 'Join notification'),
    (0x19, 'CHAT_GROUP_LEAVE', 'Leave notification'),
    (0x1A, 'CHAT_PRESENCE', 'Presence update'),
    (0x1B, 'CHAT_KEY_UPDATE', 'Key rotation'),
    (0x1C, 'CHAT_REACTION', 'Message reaction'),
    (0x1D, 'CHAT_DELETE', 'Delete request'),
    (0x1E, 'CHAT_EDIT', 'Edit message'),
    (0x20, 'CHAT_VOICE', 'Voice message'),
    (0x21, 'CHAT_IMAGE', 'Image message'),
    (0x22, 'CHAT_VIDEO', 'Video message'),
    (0x23, 'CHAT_LOCATION', 'Location share'),
    (0x24, 'CHAT_CONTACT', 'Contact share');
```

### 6. Attachments Table

Stores file attachments separately for efficient queries.

```sql
CREATE TABLE attachments (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id      INTEGER NOT NULL,                   -- FK to messages
    attachment_id   BLOB NOT NULL,                      -- 8 bytes, unique attachment ID
    type            INTEGER NOT NULL,                   -- 0=file, 1=image, 2=video, 3=audio, 4=voice

    -- File info
    filename        TEXT NOT NULL,                      -- Original filename
    mime_type       TEXT,                               -- MIME type
    file_size       INTEGER NOT NULL,                   -- Size in bytes
    file_hash       BLOB,                               -- BLAKE2b hash

    -- Storage
    storage_type    INTEGER NOT NULL,                   -- 0=local, 1=cyxcloud
    local_path      TEXT,                               -- Local file path
    storage_id      BLOB,                               -- CyxCloud storage ID
    encryption_key  BLOB,                               -- File encryption key

    -- Transfer state
    transfer_state  INTEGER DEFAULT 0,                  -- 0=pending, 1=uploading, 2=complete, 3=failed
    progress        INTEGER DEFAULT 0,                  -- 0-100 percent
    chunks_total    INTEGER,                            -- Total chunks
    chunks_done     INTEGER DEFAULT 0,                  -- Completed chunks

    -- Thumbnail (for images/videos)
    thumbnail_blob  BLOB,                               -- Thumbnail data
    thumbnail_w     INTEGER,                            -- Thumbnail width
    thumbnail_h     INTEGER,                            -- Thumbnail height

    -- Media metadata
    width           INTEGER,                            -- Original width (images/videos)
    height          INTEGER,                            -- Original height
    duration_ms     INTEGER,                            -- Duration (audio/video)
    waveform_json   TEXT,                               -- Audio waveform data

    created_at      INTEGER NOT NULL,

    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE INDEX idx_attachments_message ON attachments(message_id);
CREATE INDEX idx_attachments_transfer ON attachments(transfer_state) WHERE transfer_state < 2;
```

### 7. Groups Table

Stores group chat metadata.

```sql
CREATE TABLE groups (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id        BLOB NOT NULL UNIQUE,               -- 8 bytes, group identifier
    name            TEXT NOT NULL,                      -- Group name
    description     TEXT,                               -- Group description
    avatar_blob     BLOB,                               -- Group avatar
    avatar_hash     TEXT,                               -- Avatar hash

    -- Keys
    master_secret   BLOB NOT NULL,                      -- Encrypted master secret
    current_key     BLOB NOT NULL,                      -- Current derived group key
    key_version     INTEGER DEFAULT 1,                  -- Key version number
    key_updated_at  INTEGER,                            -- Last key rotation

    -- Ownership
    creator_id      BLOB NOT NULL,                      -- 32 bytes, creator's node_id
    created_at      INTEGER NOT NULL,                   -- Creation timestamp

    -- Settings
    settings_json   TEXT,                               -- JSON settings blob
    join_approval   INTEGER DEFAULT 0,                  -- Require admin approval to join
    invite_only     INTEGER DEFAULT 1,                  -- Only admins can invite

    -- State
    left            INTEGER DEFAULT 0,                  -- We left this group
    left_at         INTEGER                             -- When we left
);

CREATE INDEX idx_groups_group_id ON groups(group_id);
```

### 8. Group Members Table

Tracks group membership.

```sql
CREATE TABLE group_members (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    group_id    BLOB NOT NULL,                          -- FK to groups.group_id
    member_id   BLOB NOT NULL,                          -- 32 bytes, member's node_id

    -- Role
    role        INTEGER DEFAULT 0,                      -- 0=member, 1=admin, 2=owner

    -- Member info (cached)
    display_name TEXT,                                  -- Cached display name
    public_key  BLOB,                                   -- 32 bytes, member's public key

    -- Status
    joined_at   INTEGER NOT NULL,                       -- When joined
    invited_by  BLOB,                                   -- Who invited them
    left_at     INTEGER,                                -- When left (NULL if still member)
    removed_by  BLOB,                                   -- Who removed them (if kicked)

    UNIQUE(group_id, member_id),
    FOREIGN KEY (group_id) REFERENCES groups(group_id) ON DELETE CASCADE
);

CREATE INDEX idx_group_members_group ON group_members(group_id);
CREATE INDEX idx_group_members_member ON group_members(member_id);
```

### 9. Offline Queue Table

Messages waiting to be sent or stored offline.

```sql
CREATE TABLE offline_queue (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    queue_type      INTEGER NOT NULL,                   -- 0=send, 1=store_offline

    -- Target
    recipient_id    BLOB NOT NULL,                      -- 32 bytes, recipient node_id
    group_id        BLOB,                               -- For group messages

    -- Message data
    message_id      INTEGER,                            -- FK to messages table
    msg_id          BLOB NOT NULL,                      -- 8 bytes, message ID
    encrypted_data  BLOB NOT NULL,                      -- Encrypted message payload

    -- Retry tracking
    attempts        INTEGER DEFAULT 0,                  -- Send attempts
    max_attempts    INTEGER DEFAULT 4,                  -- Max retry attempts
    next_retry_at   INTEGER,                            -- Next retry timestamp
    last_error      TEXT,                               -- Last error message

    -- Timestamps
    created_at      INTEGER NOT NULL,
    expires_at      INTEGER,                            -- Give up after this time

    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE INDEX idx_offline_queue_retry ON offline_queue(next_retry_at) WHERE attempts < max_attempts;
CREATE INDEX idx_offline_queue_recipient ON offline_queue(recipient_id);
```

### 10. Pending ACKs Table

Track messages awaiting acknowledgment.

```sql
CREATE TABLE pending_acks (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    msg_id          BLOB NOT NULL UNIQUE,               -- 8 bytes, message ID
    message_id      INTEGER NOT NULL,                   -- FK to messages table
    recipient_id    BLOB NOT NULL,                      -- 32 bytes, recipient

    -- ACK type expected
    ack_type        INTEGER NOT NULL,                   -- 0=delivery, 1=read

    -- Timing
    sent_at         INTEGER NOT NULL,                   -- When message was sent
    timeout_at      INTEGER NOT NULL,                   -- When to timeout

    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE
);

CREATE INDEX idx_pending_acks_timeout ON pending_acks(timeout_at);
CREATE INDEX idx_pending_acks_msg_id ON pending_acks(msg_id);
```

### 11. Key Exchange Table

Track key exchange state with peers.

```sql
CREATE TABLE key_exchange (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    peer_id         BLOB NOT NULL UNIQUE,               -- 32 bytes, peer's node_id

    -- Their keys
    their_public    BLOB NOT NULL,                      -- 32 bytes, their X25519 public
    their_key_ver   INTEGER DEFAULT 1,                  -- Their key version

    -- Shared secret
    shared_secret   BLOB NOT NULL,                      -- Derived shared secret

    -- Our ephemeral (for forward secrecy)
    our_ephemeral_pub  BLOB,                            -- Our ephemeral public
    our_ephemeral_priv BLOB,                            -- Our ephemeral private (encrypted)

    -- Session keys
    send_key        BLOB,                               -- Key for sending
    recv_key        BLOB,                               -- Key for receiving
    send_counter    INTEGER DEFAULT 0,                  -- Message counter (send)
    recv_counter    INTEGER DEFAULT 0,                  -- Message counter (receive)

    -- State
    established_at  INTEGER NOT NULL,                   -- When established
    refreshed_at    INTEGER,                            -- Last key refresh

    FOREIGN KEY (peer_id) REFERENCES contacts(node_id) ON DELETE CASCADE
);

CREATE INDEX idx_key_exchange_peer ON key_exchange(peer_id);
```

### 12. Notifications Table

Track notification state for messages.

```sql
CREATE TABLE notifications (
    id              INTEGER PRIMARY KEY AUTOINCREMENT,
    message_id      INTEGER NOT NULL UNIQUE,            -- FK to messages
    conversation_id INTEGER NOT NULL,                   -- FK to conversations

    -- Notification state
    shown           INTEGER DEFAULT 0,                  -- Notification displayed
    shown_at        INTEGER,                            -- When shown
    dismissed       INTEGER DEFAULT 0,                  -- User dismissed
    dismissed_at    INTEGER,                            -- When dismissed
    clicked         INTEGER DEFAULT 0,                  -- User clicked
    clicked_at      INTEGER,                            -- When clicked

    -- Platform notification ID
    platform_id     TEXT,                               -- Platform notification identifier

    created_at      INTEGER NOT NULL,

    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

CREATE INDEX idx_notifications_pending ON notifications(shown) WHERE shown = 0;
```

### 13. Settings Table

Key-value store for app settings.

```sql
CREATE TABLE settings (
    key         TEXT PRIMARY KEY,
    value       TEXT,                                   -- JSON or simple value
    updated_at  INTEGER NOT NULL
);

-- Default settings
INSERT INTO settings (key, value, updated_at) VALUES
    ('theme', '"system"', 0),
    ('language', '"en"', 0),
    ('notifications_enabled', 'true', 0),
    ('notification_sound', 'true', 0),
    ('notification_vibrate', 'true', 0),
    ('notification_preview', 'true', 0),
    ('read_receipts', 'true', 0),
    ('typing_indicators', 'true', 0),
    ('online_status', 'true', 0),
    ('auto_download_images', 'true', 0),
    ('auto_download_files', 'false', 0),
    ('auto_download_size_limit', '10485760', 0),
    ('message_retention_days', '0', 0),
    ('backup_frequency', '"weekly"', 0),
    ('last_backup_at', '0', 0);
```

---

## Common Queries

### Get Conversation List (Home Screen)

```sql
SELECT
    c.id,
    c.type,
    c.title,
    c.avatar_blob,
    c.last_message_text,
    c.last_message_at,
    c.unread_count,
    c.pinned,
    c.muted,
    CASE
        WHEN c.type = 0 THEN ct.presence
        ELSE NULL
    END as peer_presence
FROM conversations c
LEFT JOIN contacts ct ON c.peer_id = ct.node_id
WHERE c.archived = 0
ORDER BY c.pinned DESC, c.updated_at DESC
LIMIT 50 OFFSET ?;
```

### Get Messages for Conversation

```sql
SELECT
    m.id,
    m.msg_id,
    m.sender_id,
    m.type,
    m.content_text,
    m.content_json,
    m.status,
    m.created_at,
    m.delivered_at,
    m.read_at,
    m.edited,
    m.reply_to_id,
    m.reactions_json,
    r.content_text as reply_text,
    r.sender_id as reply_sender
FROM messages m
LEFT JOIN messages r ON m.reply_to_id = r.id
WHERE m.conversation_id = ?
    AND m.deleted = 0
ORDER BY m.created_at DESC
LIMIT 50 OFFSET ?;
```

### Get Unread Count Total

```sql
SELECT COALESCE(SUM(unread_count), 0) as total_unread
FROM conversations
WHERE muted = 0 AND archived = 0;
```

### Search Messages

```sql
SELECT
    m.id,
    m.conversation_id,
    m.content_text,
    m.created_at,
    c.title as conversation_title
FROM messages m
JOIN conversations c ON m.conversation_id = c.id
WHERE m.content_text LIKE '%' || ? || '%'
    AND m.deleted = 0
ORDER BY m.created_at DESC
LIMIT 50;
```

### Get Pending Messages to Send

```sql
SELECT
    oq.id,
    oq.recipient_id,
    oq.msg_id,
    oq.encrypted_data,
    oq.attempts
FROM offline_queue oq
WHERE oq.queue_type = 0
    AND oq.attempts < oq.max_attempts
    AND (oq.next_retry_at IS NULL OR oq.next_retry_at <= ?)
ORDER BY oq.created_at ASC
LIMIT 10;
```

### Mark Messages as Read

```sql
-- Update messages
UPDATE messages
SET status = 3, read_at = ?
WHERE conversation_id = ?
    AND sender_id != ?
    AND status < 3;

-- Update conversation unread count
UPDATE conversations
SET unread_count = 0
WHERE id = ?;
```

### Get Group Members

```sql
SELECT
    gm.member_id,
    gm.role,
    gm.display_name,
    gm.joined_at,
    c.display_name as contact_name,
    c.presence
FROM group_members gm
LEFT JOIN contacts c ON gm.member_id = c.node_id
WHERE gm.group_id = ?
    AND gm.left_at IS NULL
ORDER BY gm.role DESC, gm.joined_at ASC;
```

---

## Migration Strategy

### Version Tracking

```sql
CREATE TABLE schema_version (
    version     INTEGER PRIMARY KEY,
    applied_at  INTEGER NOT NULL,
    description TEXT
);

INSERT INTO schema_version (version, applied_at, description)
VALUES (1, strftime('%s', 'now') * 1000, 'Initial schema');
```

### Migration Template

```dart
// lib/core/database/migrations.dart

abstract class Migration {
  int get version;
  String get description;
  Future<void> up(Database db);
  Future<void> down(Database db);
}

class Migration001 extends Migration {
  @override
  int get version => 1;

  @override
  String get description => 'Initial schema';

  @override
  Future<void> up(Database db) async {
    await db.execute('''
      CREATE TABLE identity (...)
    ''');
    // ... rest of schema
  }

  @override
  Future<void> down(Database db) async {
    await db.execute('DROP TABLE identity');
    // ... rest of rollback
  }
}

class MigrationRunner {
  final Database db;
  final List<Migration> migrations = [
    Migration001(),
    // Add new migrations here
  ];

  Future<void> migrate() async {
    final currentVersion = await _getCurrentVersion();

    for (final migration in migrations) {
      if (migration.version > currentVersion) {
        await migration.up(db);
        await _setVersion(migration.version, migration.description);
      }
    }
  }
}
```

---

## Data Retention

### Auto-Delete Expired Messages

```sql
-- Delete expired messages
DELETE FROM messages
WHERE expires_at IS NOT NULL
    AND expires_at < ?;

-- Delete old messages (if retention policy set)
DELETE FROM messages
WHERE created_at < ?
    AND conversation_id IN (
        SELECT id FROM conversations
        WHERE type = 0  -- Only direct messages
    );
```

### Cleanup Orphaned Data

```sql
-- Delete attachments for deleted messages
DELETE FROM attachments
WHERE message_id NOT IN (SELECT id FROM messages);

-- Delete notifications for deleted messages
DELETE FROM notifications
WHERE message_id NOT IN (SELECT id FROM messages);

-- Delete offline queue for deleted messages
DELETE FROM offline_queue
WHERE message_id NOT IN (SELECT id FROM messages);
```

---

## Performance Indexes Summary

| Table | Index | Purpose |
|-------|-------|---------|
| contacts | node_id | Quick contact lookup |
| contacts | last_message_at | Sort by recent |
| conversations | updated_at | Sort conversation list |
| conversations | pinned, updated_at | Pinned conversations first |
| messages | conversation_id, created_at | Message pagination |
| messages | msg_id | ACK lookup |
| messages | status | Pending messages |
| attachments | message_id | Get attachments for message |
| attachments | transfer_state | Pending transfers |
| group_members | group_id | Get group members |
| offline_queue | next_retry_at | Retry scheduling |
| pending_acks | timeout_at | Timeout checking |

---

## Dart Model Example

```dart
// lib/core/models/message.dart

import 'package:freezed_annotation/freezed_annotation.dart';

part 'message.freezed.dart';
part 'message.g.dart';

@freezed
class Message with _$Message {
  const factory Message({
    required int id,
    required int conversationId,
    required String msgId,         // Hex string of 8 bytes
    required String senderId,      // Hex string of 32 bytes
    required int type,
    String? contentText,
    Map<String, dynamic>? contentJson,
    required int status,
    required int createdAt,
    int? sentAt,
    int? deliveredAt,
    int? readAt,
    int? replyToId,
    bool? edited,
    Map<String, List<String>>? reactions,
  }) = _Message;

  factory Message.fromJson(Map<String, dynamic> json) =>
      _$MessageFromJson(json);

  factory Message.fromDb(Map<String, dynamic> row) {
    return Message(
      id: row['id'] as int,
      conversationId: row['conversation_id'] as int,
      msgId: _bytesToHex(row['msg_id'] as Uint8List),
      senderId: _bytesToHex(row['sender_id'] as Uint8List),
      type: row['type'] as int,
      contentText: row['content_text'] as String?,
      contentJson: row['content_json'] != null
          ? jsonDecode(row['content_json'] as String)
          : null,
      status: row['status'] as int,
      createdAt: row['created_at'] as int,
      sentAt: row['sent_at'] as int?,
      deliveredAt: row['delivered_at'] as int?,
      readAt: row['read_at'] as int?,
      replyToId: row['reply_to_id'] as int?,
      edited: (row['edited'] as int?) == 1,
      reactions: row['reactions_json'] != null
          ? _parseReactions(row['reactions_json'] as String)
          : null,
    );
  }
}
```

---

## Checklist

### Schema Implementation
- [ ] Create all tables
- [ ] Create all indexes
- [ ] Insert default settings
- [ ] Set up encryption (SQLCipher)

### Dart Layer
- [ ] Database helper class
- [ ] Model classes with freezed
- [ ] Repository classes for each table
- [ ] Migration runner

### Testing
- [ ] Unit tests for each repository
- [ ] Migration tests
- [ ] Performance tests with large datasets
