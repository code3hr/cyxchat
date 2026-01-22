/**
 * CyxChat Types
 * Shared type definitions for libcyxchat
 */

#ifndef CYXCHAT_TYPES_H
#define CYXCHAT_TYPES_H

#include <cyxwiz/types.h>
#include <stdint.h>
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Export Macros
 * ============================================================ */

#ifdef _WIN32
    #ifdef CYXCHAT_STATIC
        #define CYXCHAT_API
    #elif defined(CYXCHAT_EXPORTS)
        #define CYXCHAT_API __declspec(dllexport)
    #else
        #define CYXCHAT_API __declspec(dllimport)
    #endif
#else
    #define CYXCHAT_API __attribute__((visibility("default")))
#endif

/* ============================================================
 * Size Constants
 * ============================================================ */

#define CYXCHAT_NODE_ID_SIZE        32      /* Node ID size (same as cyxwiz) */
#define CYXCHAT_MSG_ID_SIZE         8       /* Message ID size */
#define CYXCHAT_GROUP_ID_SIZE       8       /* Group ID size */
#define CYXCHAT_FILE_ID_SIZE        8       /* File ID size */
#define CYXCHAT_MAX_TEXT_LEN        4096     /* Max text per message */
#define CYXCHAT_MAX_DISPLAY_NAME    64      /* Max display name */
#define CYXCHAT_MAX_STATUS_LEN      128     /* Max status text */
#define CYXCHAT_MAX_FILENAME        128     /* Max filename */
/* File chunk size - must fit within onion routing payload limit
 * 1-hop onion allows ~100 bytes effective payload due to crypto overhead
 * Wire format: 1 byte type + 8 bytes file_id + 2 bytes idx + 2 bytes len + data = 13 bytes overhead
 * Testing shows 93 bytes works, 113 fails - use 90 bytes (tested safe limit) */
#define CYXCHAT_CHUNK_SIZE          90

/* Direct P2P mode constants - bypass onion/LoRa constraints for fast transfers
 * Direct mode sends via UDP directly, no rate limiting, much larger chunks */
#define CYXCHAT_DIRECT_CHUNK_SIZE   32768       /* 32KB chunks for direct P2P */
#define CYXCHAT_DIRECT_MAX_FILE     1073741824  /* 1GB max file size in direct mode */
#define CYXCHAT_MAX_GROUP_MEMBERS   50      /* Max group size */
#define CYXCHAT_MAX_GROUP_ADMINS    5       /* Max admins per group */
#define CYXCHAT_MAX_CONTACTS        256     /* Max contacts */

/* DHT-based file transfer constants
 * DHT max value is 160 bytes, minus 40 bytes crypto overhead = 120 bytes effective */
#define CYXCHAT_DHT_CHUNK_SIZE      120     /* Max data per DHT entry */
#define CYXCHAT_DHT_MAX_CHUNKS      14      /* Max micro-chunks for DHT storage */
#define CYXCHAT_DHT_MAX_FILE_SIZE   1680    /* Max file size for full DHT storage */
#define CYXCHAT_DHT_TTL_SECONDS     86400   /* 24 hour TTL for DHT entries */
#define CYXCHAT_FILE_OFFER_TIMEOUT_MS 30000 /* 30 second offer timeout */

/* ============================================================
 * Message Types (0x10-0x3F range)
 * ============================================================ */

/* Direct messaging (0x10-0x1F) */
#define CYXCHAT_MSG_TEXT            0x10    /* Text message */
#define CYXCHAT_MSG_ACK             0x11    /* Delivery ACK */
#define CYXCHAT_MSG_READ            0x12    /* Read receipt */
#define CYXCHAT_MSG_TYPING          0x13    /* Typing indicator */
#define CYXCHAT_MSG_FILE_META       0x14    /* File metadata */
#define CYXCHAT_MSG_FILE_CHUNK      0x15    /* File chunk */
#define CYXCHAT_MSG_FILE_ACK        0x16    /* File chunk ACK */
#define CYXCHAT_MSG_REACTION        0x17    /* Message reaction */
#define CYXCHAT_MSG_DELETE          0x18    /* Delete request */
#define CYXCHAT_MSG_EDIT            0x19    /* Edit message */

/* Group messaging (0x20-0x2F) */
#define CYXCHAT_MSG_GROUP_TEXT      0x20    /* Group text message */
#define CYXCHAT_MSG_GROUP_INVITE    0x21    /* Group invitation */
#define CYXCHAT_MSG_GROUP_JOIN      0x22    /* Join notification */
#define CYXCHAT_MSG_GROUP_LEAVE     0x23    /* Leave notification */
#define CYXCHAT_MSG_GROUP_KICK      0x24    /* Kick notification */
#define CYXCHAT_MSG_GROUP_KEY       0x25    /* Key distribution */
#define CYXCHAT_MSG_GROUP_INFO      0x26    /* Group info update */
#define CYXCHAT_MSG_GROUP_ADMIN     0x27    /* Admin change */
#define CYXCHAT_MSG_GROUP_KEY_ACK   0x28    /* Key distribution ACK */
#define CYXCHAT_MSG_GROUP_RESTRICT  0x29    /* Member restriction update */
#define CYXCHAT_MSG_GROUP_PERM      0x2A    /* Admin permission update */
#define CYXCHAT_MSG_GROUP_EDIT      0x2B    /* Edit group message */
#define CYXCHAT_MSG_GROUP_DELETE    0x2C    /* Delete group message */
#define CYXCHAT_MSG_GROUP_PIN       0x2D    /* Pin message */
#define CYXCHAT_MSG_GROUP_UNPIN     0x2E    /* Unpin message */
#define CYXCHAT_MSG_GROUP_FORWARD   0x2F    /* Forward message */

/* Presence (0x30-0x37) */
#define CYXCHAT_MSG_PRESENCE        0x30    /* Presence update */
#define CYXCHAT_MSG_PRESENCE_REQ    0x31    /* Request presence */

/* Invite Links (0x38-0x3F) */
#define CYXCHAT_MSG_INVITE_LINK     0x38    /* Invite link created/shared */
#define CYXCHAT_MSG_INVITE_JOIN     0x39    /* Join via invite link */
#define CYXCHAT_MSG_INVITE_REVOKE   0x3A    /* Revoke invite link */
#define CYXCHAT_MSG_INVITE_ACK      0x3B    /* Invite link acknowledgment */

/* File Transfer Protocol v2 (0x40-0x4F) - Hybrid transfer with DHT support */
#define CYXCHAT_MSG_FILE_OFFER      0x40    /* File offer with crypto info */
#define CYXCHAT_MSG_FILE_ACCEPT     0x41    /* Accept with transfer mode */
#define CYXCHAT_MSG_FILE_REJECT     0x42    /* Reject transfer */
#define CYXCHAT_MSG_FILE_COMPLETE   0x43    /* Transfer complete notification */
#define CYXCHAT_MSG_FILE_CANCEL     0x44    /* Cancel in-progress transfer */
#define CYXCHAT_MSG_FILE_DHT_READY  0x45    /* DHT chunks stored notification */

/* Video/Voice Call Signaling (0x50-0x5F) - WebRTC via onion routing */
#define CYXCHAT_MSG_CALL_OFFER      0x50    /* SDP offer (call initiation) */
#define CYXCHAT_MSG_CALL_ANSWER     0x51    /* SDP answer (call accepted) */
#define CYXCHAT_MSG_CALL_ICE        0x52    /* ICE candidate */
#define CYXCHAT_MSG_CALL_END        0x53    /* End call */
#define CYXCHAT_MSG_CALL_REJECT     0x54    /* Reject incoming call */
#define CYXCHAT_MSG_CALL_BUSY       0x55    /* Busy signal */

/* Peer Address Exchange (0x60-0x6F) - For direct P2P mode */
#define CYXCHAT_MSG_PEER_ADDR       0x60    /* Exchange public IP:port for direct mode */
#define CYXCHAT_MSG_PEER_ADDR_ACK   0x61    /* Acknowledge address received */

/* Group Media Messages (0x70-0x7F) - File/voice sharing in groups */
#define CYXCHAT_MSG_GROUP_FILE        0x70    /* Group file message */
#define CYXCHAT_MSG_GROUP_FILE_CHUNK  0x71    /* Group file chunk */
#define CYXCHAT_MSG_GROUP_FILE_ACK    0x72    /* Group file chunk ACK */
#define CYXCHAT_MSG_GROUP_VOICE       0x73    /* Group voice message */
#define CYXCHAT_MSG_GROUP_IMAGE       0x74    /* Group image (compressed) */
#define CYXCHAT_MSG_GROUP_VIDEO       0x75    /* Group video thumbnail + metadata */

/* DNS Messages (0xD0-0xD9) - CyxChat internal DNS */
#define CYXCHAT_MSG_DNS_REGISTER      0xD0  /* Register name with signature */
#define CYXCHAT_MSG_DNS_REGISTER_ACK  0xD1  /* Registration confirmed */
#define CYXCHAT_MSG_DNS_LOOKUP        0xD2  /* Query name */
#define CYXCHAT_MSG_DNS_RESPONSE      0xD3  /* Query response */
#define CYXCHAT_MSG_DNS_UPDATE        0xD4  /* Update record (refresh TTL) */
#define CYXCHAT_MSG_DNS_UPDATE_ACK    0xD5  /* Update confirmed */
#define CYXCHAT_MSG_DNS_ANNOUNCE      0xD6  /* Gossip announcement */

/* ============================================================
 * ID Types
 * ============================================================ */

typedef struct {
    uint8_t bytes[CYXCHAT_MSG_ID_SIZE];
} cyxchat_msg_id_t;

typedef struct {
    uint8_t bytes[CYXCHAT_GROUP_ID_SIZE];
} cyxchat_group_id_t;

typedef struct {
    uint8_t bytes[CYXCHAT_FILE_ID_SIZE];
} cyxchat_file_id_t;

/* ============================================================
 * Message Status
 * ============================================================ */

typedef enum {
    CYXCHAT_STATUS_PENDING     = 0,     /* Not yet sent */
    CYXCHAT_STATUS_SENDING     = 1,     /* Being sent */
    CYXCHAT_STATUS_SENT        = 2,     /* Sent to network */
    CYXCHAT_STATUS_DELIVERED   = 3,     /* ACK received */
    CYXCHAT_STATUS_READ        = 4,     /* Read receipt received */
    CYXCHAT_STATUS_FAILED      = 5      /* Send failed */
} cyxchat_msg_status_t;

/* ============================================================
 * Presence Status
 * ============================================================ */

typedef enum {
    CYXCHAT_PRESENCE_OFFLINE   = 0,
    CYXCHAT_PRESENCE_ONLINE    = 1,
    CYXCHAT_PRESENCE_AWAY      = 2,
    CYXCHAT_PRESENCE_BUSY      = 3,
    CYXCHAT_PRESENCE_INVISIBLE = 4      /* Online but hidden */
} cyxchat_presence_t;

/* ============================================================
 * File Transfer Mode
 * ============================================================ */

typedef enum {
    CYXCHAT_FILE_MODE_DIRECT     = 0x01,  /* Direct P2P transfer (online peer) */
    CYXCHAT_FILE_MODE_RELAY      = 0x02,  /* Via relay server */
    CYXCHAT_FILE_MODE_DHT_MICRO  = 0x03,  /* Small file stored entirely in DHT */
    CYXCHAT_FILE_MODE_DHT_SIGNAL = 0x04   /* Offer in DHT, transfer when online */
} cyxchat_file_transfer_mode_t;

/* File rejection reasons */
typedef enum {
    CYXCHAT_FILE_REJECT_DECLINED  = 0,    /* User declined */
    CYXCHAT_FILE_REJECT_TOO_LARGE = 1,    /* File too large */
    CYXCHAT_FILE_REJECT_BUSY      = 2,    /* Too many transfers */
    CYXCHAT_FILE_REJECT_BLOCKED   = 3     /* Sender is blocked */
} cyxchat_file_reject_reason_t;

/* ============================================================
 * Error Codes
 * ============================================================ */

typedef enum {
    CYXCHAT_OK                 = 0,
    CYXCHAT_ERR_NULL           = -1,    /* Null pointer */
    CYXCHAT_ERR_MEMORY         = -2,    /* Memory allocation */
    CYXCHAT_ERR_INVALID        = -3,    /* Invalid parameter */
    CYXCHAT_ERR_NOT_FOUND      = -4,    /* Item not found */
    CYXCHAT_ERR_EXISTS         = -5,    /* Item already exists */
    CYXCHAT_ERR_FULL           = -6,    /* Container full */
    CYXCHAT_ERR_CRYPTO         = -7,    /* Crypto operation failed */
    CYXCHAT_ERR_NETWORK        = -8,    /* Network error */
    CYXCHAT_ERR_TIMEOUT        = -9,    /* Operation timeout */
    CYXCHAT_ERR_BLOCKED        = -10,   /* User is blocked */
    CYXCHAT_ERR_NOT_MEMBER     = -11,   /* Not a group member */
    CYXCHAT_ERR_NOT_ADMIN      = -12,   /* Not a group admin */
    CYXCHAT_ERR_FILE_TOO_LARGE = -13,   /* File exceeds limit */
    CYXCHAT_ERR_TRANSFER       = -14,   /* File transfer error */
    CYXCHAT_ERR_NO_PERMISSION  = -15,   /* Missing required permission */
    CYXCHAT_ERR_RESTRICTED     = -16,   /* Member is restricted */
    CYXCHAT_ERR_MUTED          = -17,   /* Member is muted */
    CYXCHAT_ERR_SLOW_MODE      = -18,   /* Slow mode rate limit */
    CYXCHAT_ERR_EDIT_EXPIRED   = -19,   /* Edit time limit exceeded */
    CYXCHAT_ERR_NOT_OWNER      = -20,   /* Only message owner can edit */
    CYXCHAT_ERR_ALREADY_PINNED = -21,   /* Message already pinned */
    CYXCHAT_ERR_NOT_PINNED     = -22,   /* Message not pinned */
    CYXCHAT_ERR_PIN_LIMIT      = -23,   /* Max pinned messages reached */
    CYXCHAT_ERR_NO_KEY         = -24    /* No shared key with peer (key exchange not complete) */
} cyxchat_error_t;

/* ============================================================
 * Group Types
 * ============================================================ */

typedef enum {
    CYXCHAT_GROUP_TYPE_BASIC      = 0,  /* Basic group: 200 members max, simpler features */
    CYXCHAT_GROUP_TYPE_SUPERGROUP = 1   /* Supergroup: unlimited members, full admin features */
} cyxchat_group_type_t;

/* ============================================================
 * Admin Permission Flags (bitmask)
 * ============================================================ */

#define CYXCHAT_PERM_ADD_MEMBERS     (1 << 0)  /* Can add/invite members */
#define CYXCHAT_PERM_REMOVE_MEMBERS  (1 << 1)  /* Can remove/kick members */
#define CYXCHAT_PERM_DELETE_MESSAGES (1 << 2)  /* Can delete any message */
#define CYXCHAT_PERM_PIN_MESSAGES    (1 << 3)  /* Can pin/unpin messages */
#define CYXCHAT_PERM_CHANGE_INFO     (1 << 4)  /* Can change group name/description */
#define CYXCHAT_PERM_BAN_USERS       (1 << 5)  /* Can ban/unban users */
#define CYXCHAT_PERM_MANAGE_ADMINS   (1 << 6)  /* Can promote/demote admins */
#define CYXCHAT_PERM_ALL             0x7F      /* All permissions */

/* Default permissions for new admins */
#define CYXCHAT_PERM_DEFAULT_ADMIN   (CYXCHAT_PERM_ADD_MEMBERS | \
                                      CYXCHAT_PERM_REMOVE_MEMBERS | \
                                      CYXCHAT_PERM_DELETE_MESSAGES | \
                                      CYXCHAT_PERM_CHANGE_INFO)

/* ============================================================
 * Member Restriction Flags (bitmask)
 * ============================================================ */

#define CYXCHAT_RESTRICT_MUTED       (1 << 0)  /* Cannot send any messages */
#define CYXCHAT_RESTRICT_NO_MEDIA    (1 << 1)  /* Cannot send media/files */
#define CYXCHAT_RESTRICT_NO_LINKS    (1 << 2)  /* Cannot send links */
#define CYXCHAT_RESTRICT_NO_MESSAGES (1 << 3)  /* Completely silenced */

/* ============================================================
 * Group Settings Flags
 * ============================================================ */

typedef enum {
    CYXCHAT_GROUP_SETTING_ALL_CAN_ADD    = 0,  /* All members can add members */
    CYXCHAT_GROUP_SETTING_ADMINS_CAN_ADD = 1   /* Only admins can add members */
} cyxchat_group_add_setting_t;

typedef enum {
    CYXCHAT_GROUP_SETTING_ALL_CAN_EDIT    = 0,  /* All can edit group info */
    CYXCHAT_GROUP_SETTING_ADMINS_CAN_EDIT = 1   /* Only admins can edit info */
} cyxchat_group_edit_setting_t;

/* ============================================================
 * Message Header (common to all messages)
 * ============================================================ */

typedef struct {
    uint8_t  version;                           /* Protocol version */
    uint8_t  type;                              /* Message type */
    uint16_t flags;                             /* Message flags */
    uint64_t timestamp;                         /* Unix timestamp (ms) */
    cyxchat_msg_id_t msg_id;                    /* Unique message ID */
} cyxchat_msg_header_t;

/* Header flags */
#define CYXCHAT_FLAG_ENCRYPTED     (1 << 0)     /* Message is encrypted */
#define CYXCHAT_FLAG_COMPRESSED    (1 << 1)     /* Message is compressed */
#define CYXCHAT_FLAG_FRAGMENTED    (1 << 2)     /* Message is fragmented */
#define CYXCHAT_FLAG_REPLY         (1 << 3)     /* Is a reply */
#define CYXCHAT_FLAG_FORWARD       (1 << 4)     /* Is forwarded */
#define CYXCHAT_FLAG_EPHEMERAL     (1 << 5)     /* Disappearing message */
#define CYXCHAT_FLAG_EDITED        (1 << 6)     /* Message was edited */
#define CYXCHAT_FLAG_DELETED       (1 << 7)     /* Message was deleted */

/* ============================================================
 * Message Action Constants
 * ============================================================ */

#define CYXCHAT_MAX_PINNED_MESSAGES     50      /* Max pinned messages per group */
#define CYXCHAT_EDIT_TIME_LIMIT_MS      172800000 /* 48 hours to edit message */
#define CYXCHAT_DELETE_FOR_ALL_LIMIT_MS 172800000 /* 48 hours to delete for all */

/* Invite Link Constants */
#define CYXCHAT_INVITE_LINK_ID_SIZE     16      /* 16 bytes = 32 hex chars */
#define CYXCHAT_MAX_INVITE_LINKS        20      /* Max invite links per group */
#define CYXCHAT_INVITE_LINK_NAME_LEN    64      /* Max link name length */
#define CYXCHAT_INVITE_LINK_DEFAULT_EXPIRY_MS  604800000  /* 7 days default */
#define CYXCHAT_INVITE_LINK_MAX_EXPIRY_MS      2592000000 /* 30 days max */

/* Invite Link Structure */
typedef struct {
    uint8_t  link_id[CYXCHAT_INVITE_LINK_ID_SIZE]; /* Unique link ID */
    uint8_t  group_id[CYXCHAT_GROUP_ID_SIZE];      /* Group this link is for */
    uint8_t  creator_id[CYXCHAT_NODE_ID_SIZE];     /* Who created the link */
    uint64_t created_at;                           /* Creation timestamp (ms) */
    uint64_t expires_at;                           /* Expiry timestamp (ms), 0=never */
    uint32_t max_uses;                             /* Max uses, 0=unlimited */
    uint32_t use_count;                            /* Current use count */
    uint8_t  is_revoked;                           /* 1 if revoked */
    char     name[CYXCHAT_INVITE_LINK_NAME_LEN];   /* Optional link name */
} cyxchat_invite_link_t;

/* ============================================================
 * Admin Action Types (for audit log)
 * ============================================================ */

typedef enum {
    CYXCHAT_ADMIN_ACTION_KICK                = 0,   /* Member was kicked */
    CYXCHAT_ADMIN_ACTION_BAN                 = 1,   /* Member was banned */
    CYXCHAT_ADMIN_ACTION_UNBAN               = 2,   /* Member was unbanned */
    CYXCHAT_ADMIN_ACTION_PROMOTE             = 3,   /* Member promoted to admin */
    CYXCHAT_ADMIN_ACTION_DEMOTE              = 4,   /* Admin demoted to member */
    CYXCHAT_ADMIN_ACTION_PERMISSIONS_CHANGED = 5,   /* Admin permissions changed */
    CYXCHAT_ADMIN_ACTION_RESTRICTIONS_CHANGED= 6,   /* Member restrictions changed */
    CYXCHAT_ADMIN_ACTION_MESSAGE_DELETED     = 7,   /* Message deleted by admin */
    CYXCHAT_ADMIN_ACTION_MESSAGE_PINNED      = 8,   /* Message pinned */
    CYXCHAT_ADMIN_ACTION_MESSAGE_UNPINNED    = 9,   /* Message unpinned */
    CYXCHAT_ADMIN_ACTION_INFO_CHANGED        = 10,  /* Group info changed */
    CYXCHAT_ADMIN_ACTION_SLOW_MODE_CHANGED   = 11,  /* Slow mode setting changed */
    CYXCHAT_ADMIN_ACTION_LINK_CREATED        = 12,  /* Invite link created */
    CYXCHAT_ADMIN_ACTION_LINK_REVOKED        = 13,  /* Invite link revoked */
    CYXCHAT_ADMIN_ACTION_MEMBER_INVITED      = 14   /* Member invited via link */
} cyxchat_admin_action_type_t;

/* Admin Action Log Constants */
#define CYXCHAT_ADMIN_ACTION_ID_SIZE        16      /* Action ID size */
#define CYXCHAT_MAX_ADMIN_ACTIONS           1000    /* Max cached actions in memory */
#define CYXCHAT_ADMIN_ACTION_VALUE_LEN      256     /* Max old/new value length */

/* Admin Action Log Entry */
typedef struct {
    uint8_t  action_id[CYXCHAT_ADMIN_ACTION_ID_SIZE]; /* Unique action ID */
    uint8_t  group_id[CYXCHAT_GROUP_ID_SIZE];         /* Group this action belongs to */
    uint8_t  admin_id[CYXCHAT_NODE_ID_SIZE];          /* Admin who performed action */
    cyxchat_admin_action_type_t action_type;          /* Type of action */
    uint8_t  target_id[CYXCHAT_NODE_ID_SIZE];         /* Target user (if applicable) */
    uint8_t  target_msg_id[CYXCHAT_MSG_ID_SIZE];      /* Target message (if applicable) */
    uint64_t timestamp;                               /* When action occurred (ms) */
    char     old_value[CYXCHAT_ADMIN_ACTION_VALUE_LEN]; /* Previous value */
    char     new_value[CYXCHAT_ADMIN_ACTION_VALUE_LEN]; /* New value */
} cyxchat_admin_action_t;

/* ============================================================
 * Media Types (Phase 5)
 * ============================================================ */

/* Media type enumeration */
typedef enum {
    CYXCHAT_MEDIA_TYPE_IMAGE     = 0,   /* Image (JPEG, PNG, GIF, WebP) */
    CYXCHAT_MEDIA_TYPE_VIDEO     = 1,   /* Video (MP4, WebM) */
    CYXCHAT_MEDIA_TYPE_AUDIO     = 2,   /* Audio (MP3, OGG, AAC) */
    CYXCHAT_MEDIA_TYPE_VOICE     = 3,   /* Voice message (OGG Opus) */
    CYXCHAT_MEDIA_TYPE_DOCUMENT  = 4,   /* Document (PDF, DOC, etc.) */
    CYXCHAT_MEDIA_TYPE_ARCHIVE   = 5,   /* Archive (ZIP, RAR, etc.) */
    CYXCHAT_MEDIA_TYPE_OTHER     = 6    /* Other file types */
} cyxchat_media_type_t;

/* Media message constants */
#define CYXCHAT_MAX_MEDIA_SIZE        (10 * 1024 * 1024)  /* 10MB max media */
#define CYXCHAT_MAX_THUMBNAIL_SIZE    (64 * 1024)         /* 64KB max thumbnail */
#define CYXCHAT_VOICE_MAX_DURATION_MS (300 * 1000)        /* 5 minute max voice */
#define CYXCHAT_MEDIA_CHUNK_SIZE      4096                /* 4KB chunks */
#define CYXCHAT_MAX_MIME_TYPE         64                  /* Max MIME type length */

/* Group media message structure */
typedef struct {
    uint8_t  msg_id[CYXCHAT_MSG_ID_SIZE];        /* Message ID */
    uint8_t  group_id[CYXCHAT_GROUP_ID_SIZE];    /* Group this media belongs to */
    uint8_t  sender_id[CYXCHAT_NODE_ID_SIZE];    /* Sender node ID */
    uint8_t  file_id[CYXCHAT_FILE_ID_SIZE];      /* File ID for chunked transfer */
    cyxchat_media_type_t media_type;             /* Type of media */
    uint64_t file_size;                          /* Total file size in bytes */
    uint32_t duration_ms;                        /* Duration for audio/video (0 for others) */
    uint16_t width;                              /* Width for images/video (0 for audio) */
    uint16_t height;                             /* Height for images/video (0 for audio) */
    char     filename[CYXCHAT_MAX_FILENAME];     /* Original filename */
    char     mime_type[CYXCHAT_MAX_MIME_TYPE];   /* MIME type */
    uint32_t thumbnail_size;                     /* Size of thumbnail data */
    uint64_t timestamp;                          /* When message was sent */
} cyxchat_group_media_t;

/* ============================================================
 * Protocol Version
 * ============================================================ */

#define CYXCHAT_PROTOCOL_VERSION   1

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_TYPES_H */
