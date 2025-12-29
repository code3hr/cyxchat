# CyxChat C Extension (libcyxchat)

## Overview

libcyxchat is the C library that extends libcyxwiz with chat-specific functionality. It provides the messaging protocol, contact management, group chat, and file transfer capabilities.

```
┌─────────────────────────────────────────────────────────────────────────┐
│                      Library Architecture                                │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │                      libcyxchat                                  │   │
│  │  ┌───────────┐ ┌───────────┐ ┌───────────┐ ┌───────────────┐   │   │
│  │  │   chat    │ │  contact  │ │   group   │ │     file      │   │   │
│  │  │  (core)   │ │(management│ │  (group   │ │  (transfer)   │   │   │
│  │  │           │ │           │ │   chat)   │ │               │   │   │
│  │  └─────┬─────┘ └─────┬─────┘ └─────┬─────┘ └───────┬───────┘   │   │
│  │        │             │             │               │           │   │
│  │        └─────────────┴──────┬──────┴───────────────┘           │   │
│  │                             │                                   │   │
│  │  ┌──────────────────────────┴──────────────────────────────┐   │   │
│  │  │                     presence / offline                   │   │   │
│  │  └──────────────────────────┬──────────────────────────────┘   │   │
│  └─────────────────────────────┼───────────────────────────────────┘   │
│                                │                                        │
│  ┌─────────────────────────────┴───────────────────────────────────┐   │
│  │                        libcyxwiz                                 │   │
│  │  ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐ ┌─────────┐   │   │
│  │  │  onion  │ │  router │ │  peer   │ │ crypto  │ │ storage │   │   │
│  │  └─────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘   │   │
│  └──────────────────────────────────────────────────────────────────┘   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

---

## Directory Structure

```
cyxchat/lib/
├── include/
│   └── cyxchat/
│       ├── chat.h          # Core chat API
│       ├── contact.h       # Contact management
│       ├── group.h         # Group chat
│       ├── file.h          # File transfer
│       ├── presence.h      # Presence/status
│       ├── offline.h       # Offline messaging
│       └── types.h         # Shared types
│
├── src/
│   ├── chat.c              # Core chat implementation
│   ├── contact.c           # Contact management
│   ├── group.c             # Group chat
│   ├── file.c              # File transfer
│   ├── presence.c          # Presence handling
│   ├── offline.c           # Offline queue
│   └── internal.h          # Internal helpers
│
├── tests/
│   ├── test_chat.c
│   ├── test_contact.c
│   ├── test_group.c
│   ├── test_file.c
│   └── test_main.c
│
└── CMakeLists.txt
```

---

## Message Types

### Protocol Message Range: 0x10-0x2F

```c
/* ============================================================
 * Message Type Constants
 * ============================================================ */

/* Direct messaging (0x10-0x1F) */
#define CYXCHAT_MSG_TEXT            0x10  /* Text message */
#define CYXCHAT_MSG_ACK             0x11  /* Delivery ACK */
#define CYXCHAT_MSG_READ            0x12  /* Read receipt */
#define CYXCHAT_MSG_TYPING          0x13  /* Typing indicator */
#define CYXCHAT_MSG_FILE_META       0x14  /* File metadata */
#define CYXCHAT_MSG_FILE_CHUNK      0x15  /* File chunk */
#define CYXCHAT_MSG_FILE_ACK        0x16  /* File chunk ACK */
#define CYXCHAT_MSG_REACTION        0x17  /* Message reaction */
#define CYXCHAT_MSG_DELETE          0x18  /* Delete request */
#define CYXCHAT_MSG_EDIT            0x19  /* Edit message */

/* Group messaging (0x20-0x2F) */
#define CYXCHAT_MSG_GROUP_TEXT      0x20  /* Group text message */
#define CYXCHAT_MSG_GROUP_INVITE    0x21  /* Group invitation */
#define CYXCHAT_MSG_GROUP_JOIN      0x22  /* Join notification */
#define CYXCHAT_MSG_GROUP_LEAVE     0x23  /* Leave notification */
#define CYXCHAT_MSG_GROUP_KICK      0x24  /* Kick notification */
#define CYXCHAT_MSG_GROUP_KEY       0x25  /* Key update */
#define CYXCHAT_MSG_GROUP_INFO      0x26  /* Group info update */
#define CYXCHAT_MSG_GROUP_ADMIN     0x27  /* Admin change */

/* Presence (0x30-0x3F) */
#define CYXCHAT_MSG_PRESENCE        0x30  /* Presence update */
#define CYXCHAT_MSG_PRESENCE_REQ    0x31  /* Request presence */
```

---

## Core Structures

### include/cyxchat/types.h

```c
#ifndef CYXCHAT_TYPES_H
#define CYXCHAT_TYPES_H

#include <cyxwiz/types.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Size Constants
 * ============================================================ */

#define CYXCHAT_MSG_ID_SIZE         8       /* Message ID size */
#define CYXCHAT_GROUP_ID_SIZE       8       /* Group ID size */
#define CYXCHAT_FILE_ID_SIZE        8       /* File ID size */
#define CYXCHAT_MAX_TEXT_LEN        256     /* Max text per message */
#define CYXCHAT_MAX_DISPLAY_NAME    64      /* Max display name */
#define CYXCHAT_MAX_STATUS_LEN      128     /* Max status text */
#define CYXCHAT_MAX_FILENAME        128     /* Max filename */
#define CYXCHAT_CHUNK_SIZE          1024    /* File chunk size */
#define CYXCHAT_MAX_GROUP_MEMBERS   50      /* Max group size */
#define CYXCHAT_MAX_GROUP_ADMINS    5       /* Max admins per group */

/* ============================================================
 * Message ID Type
 * ============================================================ */

typedef struct {
    uint8_t bytes[CYXCHAT_MSG_ID_SIZE];
} cyxchat_msg_id_t;

/* ============================================================
 * Group ID Type
 * ============================================================ */

typedef struct {
    uint8_t bytes[CYXCHAT_GROUP_ID_SIZE];
} cyxchat_group_id_t;

/* ============================================================
 * File ID Type
 * ============================================================ */

typedef struct {
    uint8_t bytes[CYXCHAT_FILE_ID_SIZE];
} cyxchat_file_id_t;

/* ============================================================
 * Message Status
 * ============================================================ */

typedef enum {
    CYXCHAT_STATUS_PENDING     = 0,   /* Not yet sent */
    CYXCHAT_STATUS_SENDING     = 1,   /* Being sent */
    CYXCHAT_STATUS_SENT        = 2,   /* Sent to network */
    CYXCHAT_STATUS_DELIVERED   = 3,   /* ACK received */
    CYXCHAT_STATUS_READ        = 4,   /* Read receipt received */
    CYXCHAT_STATUS_FAILED      = 5    /* Send failed */
} cyxchat_msg_status_t;

/* ============================================================
 * Presence Status
 * ============================================================ */

typedef enum {
    CYXCHAT_PRESENCE_OFFLINE   = 0,
    CYXCHAT_PRESENCE_ONLINE    = 1,
    CYXCHAT_PRESENCE_AWAY      = 2,
    CYXCHAT_PRESENCE_BUSY      = 3,
    CYXCHAT_PRESENCE_INVISIBLE = 4    /* Online but hidden */
} cyxchat_presence_t;

/* ============================================================
 * Error Codes
 * ============================================================ */

typedef enum {
    CYXCHAT_OK                 = 0,
    CYXCHAT_ERR_NULL           = -1,   /* Null pointer */
    CYXCHAT_ERR_MEMORY         = -2,   /* Memory allocation */
    CYXCHAT_ERR_INVALID        = -3,   /* Invalid parameter */
    CYXCHAT_ERR_NOT_FOUND      = -4,   /* Item not found */
    CYXCHAT_ERR_EXISTS         = -5,   /* Item already exists */
    CYXCHAT_ERR_FULL           = -6,   /* Container full */
    CYXCHAT_ERR_CRYPTO         = -7,   /* Crypto operation failed */
    CYXCHAT_ERR_NETWORK        = -8,   /* Network error */
    CYXCHAT_ERR_TIMEOUT        = -9,   /* Operation timeout */
    CYXCHAT_ERR_BLOCKED        = -10,  /* User is blocked */
    CYXCHAT_ERR_NOT_MEMBER     = -11,  /* Not a group member */
    CYXCHAT_ERR_NOT_ADMIN      = -12,  /* Not a group admin */
    CYXCHAT_ERR_FILE_TOO_LARGE = -13,  /* File exceeds limit */
    CYXCHAT_ERR_TRANSFER       = -14   /* File transfer error */
} cyxchat_error_t;

/* ============================================================
 * Message Header (common to all messages)
 * ============================================================ */

typedef struct {
    uint8_t  version;                         /* Protocol version */
    uint8_t  type;                            /* Message type */
    uint16_t flags;                           /* Message flags */
    uint64_t timestamp;                       /* Unix timestamp (ms) */
    cyxchat_msg_id_t msg_id;                  /* Unique message ID */
} cyxchat_msg_header_t;

/* Header flags */
#define CYXCHAT_FLAG_ENCRYPTED     (1 << 0)   /* Message is encrypted */
#define CYXCHAT_FLAG_COMPRESSED    (1 << 1)   /* Message is compressed */
#define CYXCHAT_FLAG_FRAGMENTED    (1 << 2)   /* Message is fragmented */
#define CYXCHAT_FLAG_REPLY         (1 << 3)   /* Is a reply */
#define CYXCHAT_FLAG_FORWARD       (1 << 4)   /* Is forwarded */
#define CYXCHAT_FLAG_EPHEMERAL     (1 << 5)   /* Disappearing message */

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_TYPES_H */
```

---

## Chat Module

### include/cyxchat/chat.h

```c
#ifndef CYXCHAT_CHAT_H
#define CYXCHAT_CHAT_H

#include "types.h"
#include <cyxwiz/onion.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Chat Context
 * ============================================================ */

typedef struct cyxchat_ctx cyxchat_ctx_t;

/* ============================================================
 * Message Structures
 * ============================================================ */

/* Text message */
typedef struct {
    cyxchat_msg_header_t header;
    uint16_t text_len;
    char text[CYXCHAT_MAX_TEXT_LEN];
    cyxchat_msg_id_t reply_to;                /* Zero if not a reply */
} cyxchat_text_msg_t;

/* ACK message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t ack_msg_id;              /* Message being acknowledged */
    uint8_t status;                            /* cyxchat_msg_status_t */
} cyxchat_ack_msg_t;

/* Typing indicator */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t is_typing;                         /* 1 = typing, 0 = stopped */
} cyxchat_typing_msg_t;

/* Reaction message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t target_msg_id;           /* Message being reacted to */
    uint8_t reaction_len;
    char reaction[8];                          /* Emoji (UTF-8) */
    uint8_t remove;                            /* 1 = remove reaction */
} cyxchat_reaction_msg_t;

/* Delete message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t target_msg_id;           /* Message to delete */
} cyxchat_delete_msg_t;

/* Edit message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t target_msg_id;           /* Message to edit */
    uint16_t new_text_len;
    char new_text[CYXCHAT_MAX_TEXT_LEN];
} cyxchat_edit_msg_t;

/* ============================================================
 * Callback Types
 * ============================================================ */

/* Called when text message received */
typedef void (*cyxchat_on_message_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_text_msg_t *msg,
    void *user_data
);

/* Called when ACK received */
typedef void (*cyxchat_on_ack_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    cyxchat_msg_status_t status,
    void *user_data
);

/* Called when typing indicator received */
typedef void (*cyxchat_on_typing_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    int is_typing,
    void *user_data
);

/* Called when reaction received */
typedef void (*cyxchat_on_reaction_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    const char *reaction,
    int remove,
    void *user_data
);

/* ============================================================
 * Initialization
 * ============================================================ */

/**
 * Create chat context
 *
 * @param ctx           Output: created context
 * @param onion         Onion routing context (from libcyxwiz)
 * @param local_id      Our node ID
 * @return              CYXCHAT_OK on success
 */
cyxchat_error_t cyxchat_create(
    cyxchat_ctx_t **ctx,
    cyxwiz_onion_ctx_t *onion,
    const cyxwiz_node_id_t *local_id
);

/**
 * Destroy chat context
 */
void cyxchat_destroy(cyxchat_ctx_t *ctx);

/**
 * Process events (call from main loop)
 *
 * @param ctx           Chat context
 * @param now_ms        Current timestamp in milliseconds
 * @return              Number of events processed
 */
int cyxchat_poll(cyxchat_ctx_t *ctx, uint64_t now_ms);

/* ============================================================
 * Sending Messages
 * ============================================================ */

/**
 * Send text message
 *
 * @param ctx           Chat context
 * @param to            Recipient node ID
 * @param text          Message text (UTF-8)
 * @param text_len      Text length in bytes
 * @param reply_to      Message ID to reply to (NULL if not a reply)
 * @param msg_id_out    Output: generated message ID
 * @return              CYXCHAT_OK on success
 */
cyxchat_error_t cyxchat_send_text(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *text,
    size_t text_len,
    const cyxchat_msg_id_t *reply_to,
    cyxchat_msg_id_t *msg_id_out
);

/**
 * Send delivery acknowledgment
 */
cyxchat_error_t cyxchat_send_ack(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    cyxchat_msg_status_t status
);

/**
 * Send typing indicator
 */
cyxchat_error_t cyxchat_send_typing(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    int is_typing
);

/**
 * Send reaction
 */
cyxchat_error_t cyxchat_send_reaction(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    const char *reaction,
    int remove
);

/**
 * Request message deletion
 */
cyxchat_error_t cyxchat_send_delete(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id
);

/**
 * Send edited message
 */
cyxchat_error_t cyxchat_send_edit(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    const char *new_text,
    size_t new_text_len
);

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_set_on_message(
    cyxchat_ctx_t *ctx,
    cyxchat_on_message_t callback,
    void *user_data
);

void cyxchat_set_on_ack(
    cyxchat_ctx_t *ctx,
    cyxchat_on_ack_t callback,
    void *user_data
);

void cyxchat_set_on_typing(
    cyxchat_ctx_t *ctx,
    cyxchat_on_typing_t callback,
    void *user_data
);

void cyxchat_set_on_reaction(
    cyxchat_ctx_t *ctx,
    cyxchat_on_reaction_t callback,
    void *user_data
);

/* ============================================================
 * Utilities
 * ============================================================ */

/**
 * Generate random message ID
 */
void cyxchat_generate_msg_id(cyxchat_msg_id_t *msg_id);

/**
 * Get current timestamp in milliseconds
 */
uint64_t cyxchat_timestamp_ms(void);

/**
 * Compare message IDs
 * @return 0 if equal, non-zero otherwise
 */
int cyxchat_msg_id_cmp(
    const cyxchat_msg_id_t *a,
    const cyxchat_msg_id_t *b
);

/**
 * Check if message ID is zero (null)
 */
int cyxchat_msg_id_is_zero(const cyxchat_msg_id_t *id);

/**
 * Convert message ID to hex string
 * @param hex_out Buffer of at least 17 bytes (16 + null)
 */
void cyxchat_msg_id_to_hex(
    const cyxchat_msg_id_t *id,
    char *hex_out
);

/**
 * Parse message ID from hex string
 */
cyxchat_error_t cyxchat_msg_id_from_hex(
    const char *hex,
    cyxchat_msg_id_t *id_out
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_CHAT_H */
```

---

## Contact Module

### include/cyxchat/contact.h

```c
#ifndef CYXCHAT_CONTACT_H
#define CYXCHAT_CONTACT_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Contact Structure
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t node_id;                 /* Contact's node ID */
    uint8_t public_key[32];                   /* X25519 public key */
    char display_name[CYXCHAT_MAX_DISPLAY_NAME];
    int verified;                              /* Key verified */
    int blocked;                               /* Contact blocked */
    uint64_t added_at;                         /* When added */
    uint64_t last_seen;                        /* Last activity */
    cyxchat_presence_t presence;              /* Current presence */
    char status_text[CYXCHAT_MAX_STATUS_LEN]; /* Custom status */
} cyxchat_contact_t;

/* ============================================================
 * Contact List
 * ============================================================ */

typedef struct cyxchat_contact_list cyxchat_contact_list_t;

/**
 * Create contact list
 */
cyxchat_error_t cyxchat_contact_list_create(
    cyxchat_contact_list_t **list
);

/**
 * Destroy contact list
 */
void cyxchat_contact_list_destroy(cyxchat_contact_list_t *list);

/**
 * Add contact
 *
 * @param list          Contact list
 * @param node_id       Contact's node ID
 * @param public_key    Contact's public key (32 bytes)
 * @param display_name  Display name (can be NULL)
 * @return              CYXCHAT_OK or error
 */
cyxchat_error_t cyxchat_contact_add(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    const uint8_t *public_key,
    const char *display_name
);

/**
 * Remove contact
 */
cyxchat_error_t cyxchat_contact_remove(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

/**
 * Find contact by node ID
 *
 * @return Contact pointer or NULL if not found
 */
cyxchat_contact_t* cyxchat_contact_find(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

/**
 * Update contact display name
 */
cyxchat_error_t cyxchat_contact_set_name(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    const char *display_name
);

/**
 * Set contact blocked status
 */
cyxchat_error_t cyxchat_contact_set_blocked(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int blocked
);

/**
 * Set contact verified status
 */
cyxchat_error_t cyxchat_contact_set_verified(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int verified
);

/**
 * Update contact presence
 */
cyxchat_error_t cyxchat_contact_set_presence(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    cyxchat_presence_t presence,
    const char *status_text
);

/**
 * Check if contact is blocked
 */
int cyxchat_contact_is_blocked(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

/**
 * Get contact count
 */
size_t cyxchat_contact_count(cyxchat_contact_list_t *list);

/**
 * Get contact by index
 */
cyxchat_contact_t* cyxchat_contact_get(
    cyxchat_contact_list_t *list,
    size_t index
);

/* ============================================================
 * Safety Numbers
 * ============================================================ */

/**
 * Compute safety number for key verification
 *
 * @param our_pubkey    Our public key (32 bytes)
 * @param their_pubkey  Their public key (32 bytes)
 * @param out           Output buffer (at least 60 bytes)
 * @param out_len       Output buffer length
 *
 * Output format: "12345 67890 12345 67890 12345 67890"
 */
void cyxchat_compute_safety_number(
    const uint8_t *our_pubkey,
    const uint8_t *their_pubkey,
    char *out,
    size_t out_len
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_CONTACT_H */
```

---

## Group Module

### include/cyxchat/group.h

```c
#ifndef CYXCHAT_GROUP_H
#define CYXCHAT_GROUP_H

#include "types.h"
#include "chat.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Group Structure
 * ============================================================ */

typedef struct {
    cyxchat_group_id_t group_id;
    char name[CYXCHAT_MAX_DISPLAY_NAME];
    char description[CYXCHAT_MAX_STATUS_LEN];

    /* Membership */
    cyxwiz_node_id_t creator;
    cyxwiz_node_id_t members[CYXCHAT_MAX_GROUP_MEMBERS];
    uint8_t member_count;
    cyxwiz_node_id_t admins[CYXCHAT_MAX_GROUP_ADMINS];
    uint8_t admin_count;

    /* Keys */
    uint8_t master_secret[32];                /* Encrypted */
    uint8_t current_key[32];                  /* Derived group key */
    uint32_t key_version;

    /* Timestamps */
    uint64_t created_at;
    uint64_t key_updated_at;
} cyxchat_group_t;

/* ============================================================
 * Group Message
 * ============================================================ */

typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_group_id_t group_id;
    uint32_t key_version;                     /* Key version used */
    uint16_t text_len;
    char text[CYXCHAT_MAX_TEXT_LEN];
    cyxchat_msg_id_t reply_to;
} cyxchat_group_msg_t;

/* ============================================================
 * Group Invitation
 * ============================================================ */

typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_group_id_t group_id;
    char group_name[CYXCHAT_MAX_DISPLAY_NAME];
    uint8_t encrypted_key[48];                /* Encrypted master secret */
    cyxwiz_node_id_t inviter;
} cyxchat_group_invite_t;

/* ============================================================
 * Group Context
 * ============================================================ */

typedef struct cyxchat_group_ctx cyxchat_group_ctx_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

typedef void (*cyxchat_on_group_message_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *from,
    const cyxchat_group_msg_t *msg,
    void *user_data
);

typedef void (*cyxchat_on_group_invite_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_invite_t *invite,
    void *user_data
);

typedef void (*cyxchat_on_member_change_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member,
    int joined,                               /* 1 = joined, 0 = left */
    void *user_data
);

/* ============================================================
 * Initialization
 * ============================================================ */

cyxchat_error_t cyxchat_group_ctx_create(
    cyxchat_group_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
);

void cyxchat_group_ctx_destroy(cyxchat_group_ctx_t *ctx);

/* ============================================================
 * Group Management
 * ============================================================ */

/**
 * Create new group
 *
 * @param ctx           Group context
 * @param name          Group name
 * @param group_id_out  Output: created group ID
 * @return              CYXCHAT_OK on success
 */
cyxchat_error_t cyxchat_group_create(
    cyxchat_group_ctx_t *ctx,
    const char *name,
    cyxchat_group_id_t *group_id_out
);

/**
 * Invite member to group
 */
cyxchat_error_t cyxchat_group_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Accept group invitation
 */
cyxchat_error_t cyxchat_group_accept_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_invite_t *invite
);

/**
 * Decline group invitation
 */
cyxchat_error_t cyxchat_group_decline_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_invite_t *invite
);

/**
 * Leave group
 */
cyxchat_error_t cyxchat_group_leave(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Remove member (admin only)
 */
cyxchat_error_t cyxchat_group_remove_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Promote member to admin (owner only)
 */
cyxchat_error_t cyxchat_group_add_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Update group name (admin only)
 */
cyxchat_error_t cyxchat_group_set_name(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *name
);

/* ============================================================
 * Group Messaging
 * ============================================================ */

/**
 * Send message to group
 */
cyxchat_error_t cyxchat_group_send_text(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *text,
    size_t text_len,
    const cyxchat_msg_id_t *reply_to,
    cyxchat_msg_id_t *msg_id_out
);

/* ============================================================
 * Key Management
 * ============================================================ */

/**
 * Rotate group key (admin only)
 * Should be called when member leaves or periodically
 */
cyxchat_error_t cyxchat_group_rotate_key(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/* ============================================================
 * Queries
 * ============================================================ */

/**
 * Get group by ID
 */
cyxchat_group_t* cyxchat_group_find(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Check if we are admin of group
 */
int cyxchat_group_is_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Check if we are owner of group
 */
int cyxchat_group_is_owner(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Get group count
 */
size_t cyxchat_group_count(cyxchat_group_ctx_t *ctx);

/**
 * Get group by index
 */
cyxchat_group_t* cyxchat_group_get(
    cyxchat_group_ctx_t *ctx,
    size_t index
);

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_group_set_on_message(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_message_t callback,
    void *user_data
);

void cyxchat_group_set_on_invite(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_invite_t callback,
    void *user_data
);

void cyxchat_group_set_on_member_change(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_member_change_t callback,
    void *user_data
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_GROUP_H */
```

---

## File Transfer Module

### include/cyxchat/file.h

```c
#ifndef CYXCHAT_FILE_H
#define CYXCHAT_FILE_H

#include "types.h"
#include "chat.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * File Transfer State
 * ============================================================ */

typedef enum {
    CYXCHAT_TRANSFER_PENDING    = 0,
    CYXCHAT_TRANSFER_SENDING    = 1,
    CYXCHAT_TRANSFER_RECEIVING  = 2,
    CYXCHAT_TRANSFER_COMPLETE   = 3,
    CYXCHAT_TRANSFER_FAILED     = 4,
    CYXCHAT_TRANSFER_CANCELLED  = 5
} cyxchat_transfer_state_t;

/* ============================================================
 * File Metadata Message
 * ============================================================ */

typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_file_id_t file_id;
    char filename[CYXCHAT_MAX_FILENAME];
    char mime_type[64];
    uint64_t file_size;
    uint32_t chunk_count;
    uint8_t file_hash[32];                    /* BLAKE2b hash */
    uint8_t encryption_key[32];               /* File encryption key */

    /* For CyxCloud storage */
    uint8_t storage_id[8];                    /* CyxCloud storage ID */
    int use_cloud;                            /* 1 = stored in CyxCloud */

    /* Thumbnail (for images/videos) */
    uint16_t thumbnail_len;
    uint8_t thumbnail[512];                   /* Small preview */
} cyxchat_file_meta_t;

/* ============================================================
 * File Chunk Message
 * ============================================================ */

typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_file_id_t file_id;
    uint32_t chunk_index;
    uint32_t chunk_size;
    uint8_t data[CYXCHAT_CHUNK_SIZE];
} cyxchat_file_chunk_t;

/* ============================================================
 * File Transfer Info
 * ============================================================ */

typedef struct {
    cyxchat_file_id_t file_id;
    cyxwiz_node_id_t peer;                    /* Other party */
    int is_sender;                            /* 1 = sending, 0 = receiving */
    cyxchat_transfer_state_t state;
    char filename[CYXCHAT_MAX_FILENAME];
    uint64_t file_size;
    uint32_t total_chunks;
    uint32_t completed_chunks;
    uint64_t started_at;
    uint64_t updated_at;
} cyxchat_transfer_t;

/* ============================================================
 * File Context
 * ============================================================ */

typedef struct cyxchat_file_ctx cyxchat_file_ctx_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

typedef void (*cyxchat_on_file_offer_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_file_meta_t *meta,
    void *user_data
);

typedef void (*cyxchat_on_file_progress_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id,
    uint32_t completed_chunks,
    uint32_t total_chunks,
    void *user_data
);

typedef void (*cyxchat_on_file_complete_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id,
    const char *local_path,                   /* Where file was saved */
    void *user_data
);

typedef void (*cyxchat_on_file_error_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id,
    cyxchat_error_t error,
    void *user_data
);

/* ============================================================
 * Initialization
 * ============================================================ */

cyxchat_error_t cyxchat_file_ctx_create(
    cyxchat_file_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx,
    const char *download_dir                  /* Where to save files */
);

void cyxchat_file_ctx_destroy(cyxchat_file_ctx_t *ctx);

int cyxchat_file_poll(cyxchat_file_ctx_t *ctx, uint64_t now_ms);

/* ============================================================
 * Sending Files
 * ============================================================ */

/**
 * Send file to peer
 *
 * @param ctx           File context
 * @param to            Recipient
 * @param file_path     Path to file on disk
 * @param file_id_out   Output: file transfer ID
 * @return              CYXCHAT_OK on success
 */
cyxchat_error_t cyxchat_file_send(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *file_path,
    cyxchat_file_id_t *file_id_out
);

/**
 * Send file to group
 */
cyxchat_error_t cyxchat_file_send_group(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *file_path,
    cyxchat_file_id_t *file_id_out
);

/* ============================================================
 * Receiving Files
 * ============================================================ */

/**
 * Accept incoming file
 */
cyxchat_error_t cyxchat_file_accept(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id,
    const char *save_path                     /* NULL = use default dir */
);

/**
 * Reject incoming file
 */
cyxchat_error_t cyxchat_file_reject(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/* ============================================================
 * Transfer Control
 * ============================================================ */

/**
 * Cancel transfer (send or receive)
 */
cyxchat_error_t cyxchat_file_cancel(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Get transfer status
 */
cyxchat_transfer_t* cyxchat_file_get_transfer(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Get all active transfers
 */
size_t cyxchat_file_get_transfers(
    cyxchat_file_ctx_t *ctx,
    cyxchat_transfer_t *out,
    size_t max_count
);

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_file_set_on_offer(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_offer_t callback,
    void *user_data
);

void cyxchat_file_set_on_progress(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_progress_t callback,
    void *user_data
);

void cyxchat_file_set_on_complete(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_complete_t callback,
    void *user_data
);

void cyxchat_file_set_on_error(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_error_t callback,
    void *user_data
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_FILE_H */
```

---

## Presence Module

### include/cyxchat/presence.h

```c
#ifndef CYXCHAT_PRESENCE_H
#define CYXCHAT_PRESENCE_H

#include "types.h"
#include "chat.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Presence Message
 * ============================================================ */

typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_presence_t status;
    uint8_t status_text_len;
    char status_text[CYXCHAT_MAX_STATUS_LEN];
} cyxchat_presence_msg_t;

/* ============================================================
 * Presence Context
 * ============================================================ */

typedef struct cyxchat_presence_ctx cyxchat_presence_ctx_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

typedef void (*cyxchat_on_presence_t)(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    cyxchat_presence_t status,
    const char *status_text,
    void *user_data
);

/* ============================================================
 * API
 * ============================================================ */

cyxchat_error_t cyxchat_presence_ctx_create(
    cyxchat_presence_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
);

void cyxchat_presence_ctx_destroy(cyxchat_presence_ctx_t *ctx);

int cyxchat_presence_poll(cyxchat_presence_ctx_t *ctx, uint64_t now_ms);

/**
 * Set our presence status
 */
cyxchat_error_t cyxchat_presence_set(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_presence_t status,
    const char *status_text
);

/**
 * Request presence from peer
 */
cyxchat_error_t cyxchat_presence_request(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *peer
);

/**
 * Get last known presence for peer
 */
cyxchat_presence_t cyxchat_presence_get(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *peer
);

void cyxchat_presence_set_on_update(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_on_presence_t callback,
    void *user_data
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_PRESENCE_H */
```

---

## Implementation Example

### src/chat.c (Partial)

```c
#include "cyxchat/chat.h"
#include "internal.h"
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* ============================================================
 * Internal Structure
 * ============================================================ */

struct cyxchat_ctx {
    cyxwiz_onion_ctx_t *onion;
    cyxwiz_node_id_t local_id;

    /* Callbacks */
    cyxchat_on_message_t on_message;
    void *on_message_data;

    cyxchat_on_ack_t on_ack;
    void *on_ack_data;

    cyxchat_on_typing_t on_typing;
    void *on_typing_data;

    cyxchat_on_reaction_t on_reaction;
    void *on_reaction_data;

    /* Pending ACKs */
    struct {
        cyxchat_msg_id_t msg_id;
        cyxwiz_node_id_t to;
        uint64_t sent_at;
        int active;
    } pending_acks[64];
    int pending_ack_count;
};

/* ============================================================
 * Implementation
 * ============================================================ */

cyxchat_error_t cyxchat_create(
    cyxchat_ctx_t **ctx,
    cyxwiz_onion_ctx_t *onion,
    const cyxwiz_node_id_t *local_id
) {
    if (!ctx || !onion || !local_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_ctx_t *c = calloc(1, sizeof(cyxchat_ctx_t));
    if (!c) {
        return CYXCHAT_ERR_MEMORY;
    }

    c->onion = onion;
    memcpy(&c->local_id, local_id, sizeof(cyxwiz_node_id_t));

    /* Register with onion for incoming messages */
    cyxwiz_onion_set_callback(onion, cyxchat_handle_incoming, c);

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_destroy(cyxchat_ctx_t *ctx) {
    if (ctx) {
        free(ctx);
    }
}

cyxchat_error_t cyxchat_send_text(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *text,
    size_t text_len,
    const cyxchat_msg_id_t *reply_to,
    cyxchat_msg_id_t *msg_id_out
) {
    if (!ctx || !to || !text) {
        return CYXCHAT_ERR_NULL;
    }

    if (text_len > CYXCHAT_MAX_TEXT_LEN) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Build message */
    cyxchat_text_msg_t msg = {0};
    msg.header.version = 1;
    msg.header.type = CYXCHAT_MSG_TEXT;
    msg.header.flags = CYXCHAT_FLAG_ENCRYPTED;
    msg.header.timestamp = cyxchat_timestamp_ms();
    cyxchat_generate_msg_id(&msg.header.msg_id);

    msg.text_len = (uint16_t)text_len;
    memcpy(msg.text, text, text_len);

    if (reply_to && !cyxchat_msg_id_is_zero(reply_to)) {
        msg.header.flags |= CYXCHAT_FLAG_REPLY;
        memcpy(&msg.reply_to, reply_to, sizeof(cyxchat_msg_id_t));
    }

    /* Send via onion routing */
    int result = cyxwiz_onion_send(
        ctx->onion,
        to,
        &msg,
        sizeof(cyxchat_msg_header_t) + 2 + text_len
    );

    if (result != 0) {
        return CYXCHAT_ERR_NETWORK;
    }

    /* Track pending ACK */
    cyxchat_add_pending_ack(ctx, &msg.header.msg_id, to);

    if (msg_id_out) {
        memcpy(msg_id_out, &msg.header.msg_id, sizeof(cyxchat_msg_id_t));
    }

    return CYXCHAT_OK;
}

int cyxchat_poll(cyxchat_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;

    int events = 0;

    /* Check for ACK timeouts */
    for (int i = 0; i < 64; i++) {
        if (ctx->pending_acks[i].active) {
            if (now_ms - ctx->pending_acks[i].sent_at > 30000) {
                /* Timeout - notify failure */
                if (ctx->on_ack) {
                    ctx->on_ack(
                        ctx,
                        &ctx->pending_acks[i].to,
                        &ctx->pending_acks[i].msg_id,
                        CYXCHAT_STATUS_FAILED,
                        ctx->on_ack_data
                    );
                }
                ctx->pending_acks[i].active = 0;
                events++;
            }
        }
    }

    return events;
}

/* ============================================================
 * Utilities
 * ============================================================ */

void cyxchat_generate_msg_id(cyxchat_msg_id_t *msg_id) {
    if (msg_id) {
        randombytes_buf(msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    }
}

uint64_t cyxchat_timestamp_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

int cyxchat_msg_id_cmp(
    const cyxchat_msg_id_t *a,
    const cyxchat_msg_id_t *b
) {
    if (!a || !b) return -1;
    return memcmp(a->bytes, b->bytes, CYXCHAT_MSG_ID_SIZE);
}

int cyxchat_msg_id_is_zero(const cyxchat_msg_id_t *id) {
    if (!id) return 1;
    for (int i = 0; i < CYXCHAT_MSG_ID_SIZE; i++) {
        if (id->bytes[i] != 0) return 0;
    }
    return 1;
}
```

---

## CMakeLists.txt

```cmake
cmake_minimum_required(VERSION 3.16)
project(cyxchat VERSION 1.0.0 LANGUAGES C)

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Options
option(CYXCHAT_BUILD_TESTS "Build tests" ON)
option(CYXCHAT_BUILD_SHARED "Build shared library" ON)

# Find dependencies
find_package(PkgConfig REQUIRED)
pkg_check_modules(SODIUM REQUIRED libsodium)

# Find libcyxwiz
find_library(CYXWIZ_LIB cyxwiz
    HINTS ${CMAKE_SOURCE_DIR}/../../build
)
find_path(CYXWIZ_INCLUDE cyxwiz/types.h
    HINTS ${CMAKE_SOURCE_DIR}/../../include
)

# Sources
set(CYXCHAT_SOURCES
    src/chat.c
    src/contact.c
    src/group.c
    src/file.c
    src/presence.c
    src/offline.c
)

# Library
if(CYXCHAT_BUILD_SHARED)
    add_library(cyxchat SHARED ${CYXCHAT_SOURCES})
else()
    add_library(cyxchat STATIC ${CYXCHAT_SOURCES})
endif()

target_include_directories(cyxchat PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CYXWIZ_INCLUDE}
    ${SODIUM_INCLUDE_DIRS}
)

target_link_libraries(cyxchat
    ${CYXWIZ_LIB}
    ${SODIUM_LIBRARIES}
)

# Export symbols (Windows)
if(WIN32)
    target_compile_definitions(cyxchat PRIVATE CYXCHAT_EXPORTS)
endif()

# Tests
if(CYXCHAT_BUILD_TESTS)
    enable_testing()

    add_executable(test_chat tests/test_chat.c tests/test_main.c)
    target_link_libraries(test_chat cyxchat)
    add_test(NAME test_chat COMMAND test_chat)

    add_executable(test_contact tests/test_contact.c tests/test_main.c)
    target_link_libraries(test_contact cyxchat)
    add_test(NAME test_contact COMMAND test_contact)

    add_executable(test_group tests/test_group.c tests/test_main.c)
    target_link_libraries(test_group cyxchat)
    add_test(NAME test_group COMMAND test_group)

    add_executable(test_file tests/test_file.c tests/test_main.c)
    target_link_libraries(test_file cyxchat)
    add_test(NAME test_file COMMAND test_file)
endif()

# Install
install(TARGETS cyxchat
    LIBRARY DESTINATION lib
    ARCHIVE DESTINATION lib
    RUNTIME DESTINATION bin
)

install(DIRECTORY include/cyxchat DESTINATION include)
```

---

## Checklist

### Headers to Create
- [ ] `include/cyxchat/types.h` - Shared types
- [ ] `include/cyxchat/chat.h` - Core chat API
- [ ] `include/cyxchat/contact.h` - Contact management
- [ ] `include/cyxchat/group.h` - Group chat
- [ ] `include/cyxchat/file.h` - File transfer
- [ ] `include/cyxchat/presence.h` - Presence
- [ ] `include/cyxchat/offline.h` - Offline queue

### Implementation Files
- [ ] `src/chat.c` - Core messaging
- [ ] `src/contact.c` - Contact list
- [ ] `src/group.c` - Group management
- [ ] `src/file.c` - File transfers
- [ ] `src/presence.c` - Presence tracking
- [ ] `src/offline.c` - Offline message queue
- [ ] `src/internal.h` - Internal helpers

### Tests
- [ ] `tests/test_chat.c`
- [ ] `tests/test_contact.c`
- [ ] `tests/test_group.c`
- [ ] `tests/test_file.c`
- [ ] `tests/test_main.c`

### Build
- [ ] `CMakeLists.txt`
- [ ] Windows build working
- [ ] Linux build working
- [ ] macOS build working
