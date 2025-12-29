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
#define CYXCHAT_MAX_CONTACTS        256     /* Max contacts */

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
#define CYXCHAT_MSG_GROUP_KEY       0x25    /* Key update */
#define CYXCHAT_MSG_GROUP_INFO      0x26    /* Group info update */
#define CYXCHAT_MSG_GROUP_ADMIN     0x27    /* Admin change */

/* Presence (0x30-0x3F) */
#define CYXCHAT_MSG_PRESENCE        0x30    /* Presence update */
#define CYXCHAT_MSG_PRESENCE_REQ    0x31    /* Request presence */

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
    CYXCHAT_ERR_TRANSFER       = -14    /* File transfer error */
} cyxchat_error_t;

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

/* ============================================================
 * Protocol Version
 * ============================================================ */

#define CYXCHAT_PROTOCOL_VERSION   1

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_TYPES_H */
