/**
 * CyxChat Mail API
 * Decentralized email functionality (CyxMail)
 */

#ifndef CYXCHAT_MAIL_H
#define CYXCHAT_MAIL_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declaration */
typedef struct cyxchat_ctx cyxchat_ctx_t;

/* ============================================================
 * Mail ID
 * ============================================================ */

typedef struct {
    uint8_t bytes[CYXCHAT_MAIL_ID_SIZE];
} cyxchat_mail_id_t;

/* ============================================================
 * Folder Types
 * ============================================================ */

typedef enum {
    CYXCHAT_FOLDER_INBOX   = 0,
    CYXCHAT_FOLDER_SENT    = 1,
    CYXCHAT_FOLDER_DRAFTS  = 2,
    CYXCHAT_FOLDER_ARCHIVE = 3,
    CYXCHAT_FOLDER_TRASH   = 4,
    CYXCHAT_FOLDER_SPAM    = 5,
    CYXCHAT_FOLDER_CUSTOM  = 6
} cyxchat_folder_type_t;

/* ============================================================
 * Attachment Info
 * ============================================================ */

typedef struct {
    cyxchat_file_id_t file_id;              /* File transfer ID */
    char filename[CYXCHAT_MAX_FILENAME];
    char mime_type[64];
    uint32_t size;                           /* Size in bytes */
    uint8_t file_hash[32];                   /* BLAKE2b hash */
    uint8_t disposition;                     /* cyxchat_attach_disposition_t */
    uint8_t storage_type;                    /* cyxchat_attach_storage_t */
    char content_id[128];                    /* For inline images (cid:xxx) */
    uint8_t *inline_data;                    /* For inline storage (<64KB) */
    size_t inline_len;
} cyxchat_mail_attachment_t;

/* ============================================================
 * Mail Address (Node ID + Display Name)
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t node_id;
    char display_name[CYXCHAT_MAX_DISPLAY_NAME];
} cyxchat_mail_addr_t;

/* ============================================================
 * Mail Message (Local Storage)
 * ============================================================ */

typedef struct {
    cyxchat_mail_id_t mail_id;
    cyxchat_mail_addr_t from;
    cyxchat_mail_addr_t to[CYXCHAT_MAX_RECIPIENTS];
    uint8_t to_count;
    cyxchat_mail_addr_t cc[CYXCHAT_MAX_RECIPIENTS];
    uint8_t cc_count;
    char subject[CYXCHAT_MAX_SUBJECT_LEN];
    char *body;                              /* Dynamically allocated */
    size_t body_len;
    cyxchat_mail_id_t in_reply_to;           /* Thread reference */
    cyxchat_mail_id_t thread_id;             /* Thread root ID */
    uint64_t timestamp;                      /* Send/receive time */
    uint8_t flags;                           /* CYXCHAT_MAIL_FLAG_* */
    cyxchat_mail_status_t status;            /* DRAFT/QUEUED/SENT/etc */
    uint8_t folder_type;                     /* cyxchat_folder_type_t */
    cyxchat_mail_attachment_t *attachments;
    uint8_t attachment_count;
    uint8_t signature[64];                   /* Ed25519 signature */
    uint8_t signature_valid;                 /* 1 = verified */
} cyxchat_mail_t;

/* ============================================================
 * Wire Protocol Messages
 * ============================================================ */

/* Mail send message (0xE0) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    cyxwiz_node_id_t from;
    uint8_t to_count;
    cyxwiz_node_id_t to[CYXCHAT_MAX_RECIPIENTS];
    uint8_t cc_count;
    cyxwiz_node_id_t cc[CYXCHAT_MAX_RECIPIENTS];
    uint16_t subject_len;
    char subject[CYXCHAT_MAX_SUBJECT_LEN];
    uint16_t body_len;
    /* Body follows (variable length, may be chunked) */
    uint8_t in_reply_to_set;                 /* 1 if in_reply_to is valid */
    cyxchat_mail_id_t in_reply_to;
    uint8_t attachment_count;
    /* Attachment metadata follows */
    uint8_t signature[64];                   /* Ed25519 signature */
} cyxchat_mail_send_msg_t;

/* Mail ACK (0xE1) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    uint8_t status;                          /* 0=delivered, 1=bounced */
    uint8_t bounce_reason;                   /* If bounced */
} cyxchat_mail_ack_msg_t;

/* Mailbox list request (0xE2) */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t folder_type;
    uint32_t offset;                         /* Pagination offset */
    uint16_t limit;                          /* Max messages to return */
} cyxchat_mail_list_msg_t;

/* Mailbox list response (0xE3) */
typedef struct {
    cyxchat_msg_header_t header;
    uint32_t total_count;                    /* Total messages in folder */
    uint16_t returned_count;                 /* Messages in this response */
    /* Mail headers follow */
} cyxchat_mail_list_resp_msg_t;

/* Fetch message (0xE4) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    uint8_t include_body;                    /* 1 = include full body */
    uint8_t include_attachments;             /* 1 = include attachment data */
} cyxchat_mail_fetch_msg_t;

/* Fetch response (0xE5) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    uint8_t found;                           /* 1 = found, 0 = not found */
    /* Full mail message follows if found */
} cyxchat_mail_fetch_resp_msg_t;

/* Delete message (0xE6) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    uint8_t permanent;                       /* 1 = permanent, 0 = to trash */
} cyxchat_mail_delete_msg_t;

/* Delete ACK (0xE7) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    uint8_t success;
} cyxchat_mail_delete_ack_msg_t;

/* New mail notification (0xE8) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    cyxwiz_node_id_t from;
    uint16_t subject_len;
    char subject[CYXCHAT_MAX_SUBJECT_LEN];
    uint8_t has_attachments;
} cyxchat_mail_notify_msg_t;

/* Read receipt (0xE9) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    uint64_t read_at;                        /* When message was read */
} cyxchat_mail_read_receipt_msg_t;

/* Bounce notification (0xEA) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_mail_id_t mail_id;
    uint8_t reason;                          /* 0=no_route, 1=rejected, 2=timeout */
    char details[128];                       /* Human-readable reason */
} cyxchat_mail_bounce_msg_t;

/* Bounce reasons */
#define CYXCHAT_BOUNCE_NO_ROUTE    0         /* Destination unreachable */
#define CYXCHAT_BOUNCE_REJECTED    1         /* Recipient rejected */
#define CYXCHAT_BOUNCE_TIMEOUT     2         /* Delivery timeout */
#define CYXCHAT_BOUNCE_QUOTA       3         /* Mailbox full */

/* ============================================================
 * Mail Context
 * ============================================================ */

typedef struct cyxchat_mail_ctx cyxchat_mail_ctx_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

/**
 * Called when a new mail is received
 */
typedef void (*cyxchat_on_mail_received_t)(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_t *mail,
    void *user_data
);

/**
 * Called when mail send status changes
 */
typedef void (*cyxchat_on_mail_sent_t)(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    cyxchat_mail_status_t status,
    void *user_data
);

/**
 * Called when a read receipt is received
 */
typedef void (*cyxchat_on_mail_read_t)(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    uint64_t read_at,
    void *user_data
);

/**
 * Called when mail bounces
 */
typedef void (*cyxchat_on_mail_bounce_t)(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    uint8_t reason,
    const char *details,
    void *user_data
);

/* ============================================================
 * Initialization
 * ============================================================ */

/**
 * Create mail context
 *
 * @param ctx           Output: new mail context
 * @param chat_ctx      Parent chat context
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_ctx_create(
    cyxchat_mail_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
);

/**
 * Destroy mail context
 */
CYXCHAT_API void cyxchat_mail_ctx_destroy(cyxchat_mail_ctx_t *ctx);

/**
 * Poll for mail events (call in main loop)
 *
 * @param ctx       Mail context
 * @param now_ms    Current timestamp in milliseconds
 * @return          Number of events processed
 */
CYXCHAT_API int cyxchat_mail_poll(cyxchat_mail_ctx_t *ctx, uint64_t now_ms);

/* ============================================================
 * Composing Mail
 * ============================================================ */

/**
 * Create new mail (draft)
 *
 * @param ctx           Mail context
 * @param mail_out      Output: new mail structure
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_create(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_mail_t **mail_out
);

/**
 * Free mail structure
 */
CYXCHAT_API void cyxchat_mail_free(cyxchat_mail_t *mail);

/**
 * Set mail recipient (To)
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_add_to(
    cyxchat_mail_t *mail,
    const cyxwiz_node_id_t *to,
    const char *display_name
);

/**
 * Set mail CC recipient
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_add_cc(
    cyxchat_mail_t *mail,
    const cyxwiz_node_id_t *cc,
    const char *display_name
);

/**
 * Set mail subject
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_set_subject(
    cyxchat_mail_t *mail,
    const char *subject
);

/**
 * Set mail body
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_set_body(
    cyxchat_mail_t *mail,
    const char *body,
    size_t body_len
);

/**
 * Set in-reply-to (for threading)
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_set_reply_to(
    cyxchat_mail_t *mail,
    const cyxchat_mail_id_t *in_reply_to
);

/**
 * Add attachment
 *
 * @param mail          Mail structure
 * @param filename      Attachment filename
 * @param mime_type     MIME type
 * @param data          File data
 * @param data_len      Data length
 * @param disposition   ATTACHMENT or INLINE
 * @param content_id    Content-ID for inline (can be NULL)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_add_attachment(
    cyxchat_mail_t *mail,
    const char *filename,
    const char *mime_type,
    const uint8_t *data,
    size_t data_len,
    cyxchat_attach_disposition_t disposition,
    const char *content_id
);

/* ============================================================
 * Sending Mail
 * ============================================================ */

/**
 * Send mail
 *
 * @param ctx           Mail context
 * @param mail          Mail to send (takes ownership)
 * @return              CYXCHAT_OK if queued for sending
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_send(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_mail_t *mail
);

/**
 * Quick send (convenience function)
 *
 * @param ctx           Mail context
 * @param to            Recipient node ID
 * @param subject       Subject line
 * @param body          Body text
 * @param in_reply_to   Thread reference (can be NULL)
 * @param mail_id_out   Output: mail ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_send_simple(
    cyxchat_mail_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *subject,
    const char *body,
    const cyxchat_mail_id_t *in_reply_to,
    cyxchat_mail_id_t *mail_id_out
);

/**
 * Save mail as draft
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_save_draft(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_mail_t *mail
);

/* ============================================================
 * Receiving/Querying Mail
 * ============================================================ */

/**
 * Get mail by ID
 *
 * @param ctx           Mail context
 * @param mail_id       Mail ID
 * @param mail_out      Output: mail structure (caller must free)
 * @return              CYXCHAT_OK on success, CYXCHAT_ERR_NOT_FOUND if not found
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_get(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    cyxchat_mail_t **mail_out
);

/**
 * Get mail count in folder
 */
CYXCHAT_API size_t cyxchat_mail_count(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_folder_type_t folder
);

/**
 * Get unread mail count in folder
 */
CYXCHAT_API size_t cyxchat_mail_unread_count(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_folder_type_t folder
);

/**
 * List mail in folder
 *
 * @param ctx           Mail context
 * @param folder        Folder type
 * @param offset        Pagination offset
 * @param limit         Max messages to return
 * @param mail_out      Output: array of mail pointers (caller must free)
 * @param count_out     Output: number of messages returned
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_list(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_folder_type_t folder,
    size_t offset,
    size_t limit,
    cyxchat_mail_t ***mail_out,
    size_t *count_out
);

/**
 * Get thread messages
 *
 * @param ctx           Mail context
 * @param thread_id     Thread root mail ID
 * @param mail_out      Output: array of mail pointers
 * @param count_out     Output: number of messages in thread
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_get_thread(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *thread_id,
    cyxchat_mail_t ***mail_out,
    size_t *count_out
);

/**
 * Search mail
 *
 * @param ctx           Mail context
 * @param query         Search query (searches subject and body)
 * @param mail_out      Output: array of mail pointers
 * @param count_out     Output: number of matches
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_search(
    cyxchat_mail_ctx_t *ctx,
    const char *query,
    cyxchat_mail_t ***mail_out,
    size_t *count_out
);

/* ============================================================
 * Mail Actions
 * ============================================================ */

/**
 * Mark mail as read
 *
 * @param ctx           Mail context
 * @param mail_id       Mail ID
 * @param send_receipt  1 to send read receipt to sender
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_mark_read(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    int send_receipt
);

/**
 * Mark mail as unread
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_mark_unread(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id
);

/**
 * Toggle flagged status
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_set_flagged(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    int flagged
);

/**
 * Move mail to folder
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_move(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    cyxchat_folder_type_t folder
);

/**
 * Delete mail (move to trash)
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_delete(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id
);

/**
 * Permanently delete mail
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_delete_permanent(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id
);

/**
 * Empty trash folder
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_empty_trash(
    cyxchat_mail_ctx_t *ctx
);

/* ============================================================
 * Callbacks
 * ============================================================ */

CYXCHAT_API void cyxchat_mail_set_on_received(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_received_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_mail_set_on_sent(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_sent_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_mail_set_on_read(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_read_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_mail_set_on_bounce(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_bounce_t callback,
    void *user_data
);

/* ============================================================
 * Message Handling
 * ============================================================ */

/**
 * Handle incoming mail message
 * (Called by chat layer when mail message type received)
 *
 * @param ctx       Mail context
 * @param from      Sender node ID
 * @param data      Raw message data
 * @param len       Data length
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_handle_message(
    cyxchat_mail_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
);

/* ============================================================
 * Utilities
 * ============================================================ */

/**
 * Generate random mail ID
 */
CYXCHAT_API void cyxchat_mail_generate_id(cyxchat_mail_id_t *id);

/**
 * Convert mail ID to hex string (17 bytes out: 16 hex + null)
 */
CYXCHAT_API void cyxchat_mail_id_to_hex(
    const cyxchat_mail_id_t *id,
    char *hex_out
);

/**
 * Parse mail ID from hex string
 */
CYXCHAT_API cyxchat_error_t cyxchat_mail_id_from_hex(
    const char *hex,
    cyxchat_mail_id_t *id_out
);

/**
 * Compare two mail IDs
 *
 * @return 0 if equal, non-zero otherwise
 */
CYXCHAT_API int cyxchat_mail_id_cmp(
    const cyxchat_mail_id_t *a,
    const cyxchat_mail_id_t *b
);

/**
 * Check if mail ID is zero (null)
 */
CYXCHAT_API int cyxchat_mail_id_is_null(const cyxchat_mail_id_t *id);

/**
 * Get folder name string
 */
CYXCHAT_API const char* cyxchat_mail_folder_name(cyxchat_folder_type_t folder);

/**
 * Get mail status name string
 */
CYXCHAT_API const char* cyxchat_mail_status_name(cyxchat_mail_status_t status);

/**
 * Format timestamp as date string
 */
CYXCHAT_API void cyxchat_mail_format_date(
    uint64_t timestamp_ms,
    char *out,
    size_t out_len
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_MAIL_H */
