/**
 * CyxChat Core API
 * Main chat functionality
 */

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
    cyxchat_msg_id_t reply_to;                  /* Zero if not a reply */
} cyxchat_text_msg_t;

/* ACK message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t ack_msg_id;                /* Message being acknowledged */
    uint8_t status;                              /* cyxchat_msg_status_t */
} cyxchat_ack_msg_t;

/* Typing indicator */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t is_typing;                           /* 1 = typing, 0 = stopped */
} cyxchat_typing_msg_t;

/* Reaction message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t target_msg_id;             /* Message being reacted to */
    uint8_t reaction_len;
    char reaction[8];                            /* Emoji (UTF-8) */
    uint8_t remove;                              /* 1 = remove reaction */
} cyxchat_reaction_msg_t;

/* Delete message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t target_msg_id;             /* Message to delete */
} cyxchat_delete_msg_t;

/* Edit message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_msg_id_t target_msg_id;             /* Message to edit */
    uint16_t new_text_len;
    char new_text[CYXCHAT_MAX_TEXT_LEN];
} cyxchat_edit_msg_t;

/* ============================================================
 * Callback Types
 * ============================================================ */

typedef void (*cyxchat_on_message_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_text_msg_t *msg,
    void *user_data
);

typedef void (*cyxchat_on_ack_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    cyxchat_msg_status_t status,
    void *user_data
);

typedef void (*cyxchat_on_typing_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    int is_typing,
    void *user_data
);

typedef void (*cyxchat_on_reaction_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    const char *reaction,
    int remove,
    void *user_data
);

typedef void (*cyxchat_on_delete_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    void *user_data
);

typedef void (*cyxchat_on_edit_t)(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    const char *new_text,
    size_t new_text_len,
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
CYXCHAT_API cyxchat_error_t cyxchat_create(
    cyxchat_ctx_t **ctx,
    cyxwiz_onion_ctx_t *onion,
    const cyxwiz_node_id_t *local_id
);

/**
 * Destroy chat context
 */
CYXCHAT_API void cyxchat_destroy(cyxchat_ctx_t *ctx);

/**
 * Process events (call from main loop)
 *
 * @param ctx           Chat context
 * @param now_ms        Current timestamp in milliseconds
 * @return              Number of events processed
 */
CYXCHAT_API int cyxchat_poll(cyxchat_ctx_t *ctx, uint64_t now_ms);

/**
 * Get next received message (for FFI polling)
 *
 * Retrieves the next message from the receive queue.
 * Call this in a loop after cyxchat_poll() until it returns 0.
 *
 * @param ctx           Chat context
 * @param from_out      Output: sender node ID
 * @param type_out      Output: message type (CYXCHAT_MSG_*)
 * @param data_out      Output buffer for message data
 * @param data_len      Input: buffer size, Output: actual data length
 * @return              1 if message retrieved, 0 if queue empty
 */
CYXCHAT_API int cyxchat_recv_next(
    cyxchat_ctx_t *ctx,
    cyxwiz_node_id_t *from_out,
    uint8_t *type_out,
    uint8_t *data_out,
    size_t *data_len
);

/**
 * Get local node ID
 */
CYXCHAT_API const cyxwiz_node_id_t* cyxchat_get_local_id(cyxchat_ctx_t *ctx);

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
CYXCHAT_API cyxchat_error_t cyxchat_send_text(
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
CYXCHAT_API cyxchat_error_t cyxchat_send_ack(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    cyxchat_msg_status_t status
);

/**
 * Send typing indicator
 */
CYXCHAT_API cyxchat_error_t cyxchat_send_typing(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    int is_typing
);

/**
 * Send reaction
 */
CYXCHAT_API cyxchat_error_t cyxchat_send_reaction(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    const char *reaction,
    int remove
);

/**
 * Request message deletion
 */
CYXCHAT_API cyxchat_error_t cyxchat_send_delete(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id
);

/**
 * Send edited message
 */
CYXCHAT_API cyxchat_error_t cyxchat_send_edit(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    const char *new_text,
    size_t new_text_len
);

/* ============================================================
 * Callbacks
 * ============================================================ */

CYXCHAT_API void cyxchat_set_on_message(
    cyxchat_ctx_t *ctx,
    cyxchat_on_message_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_set_on_ack(
    cyxchat_ctx_t *ctx,
    cyxchat_on_ack_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_set_on_typing(
    cyxchat_ctx_t *ctx,
    cyxchat_on_typing_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_set_on_reaction(
    cyxchat_ctx_t *ctx,
    cyxchat_on_reaction_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_set_on_delete(
    cyxchat_ctx_t *ctx,
    cyxchat_on_delete_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_set_on_edit(
    cyxchat_ctx_t *ctx,
    cyxchat_on_edit_t callback,
    void *user_data
);

/* ============================================================
 * Utilities
 * ============================================================ */

/**
 * Generate random message ID
 */
CYXCHAT_API void cyxchat_generate_msg_id(cyxchat_msg_id_t *msg_id);

/**
 * Get current timestamp in milliseconds
 */
CYXCHAT_API uint64_t cyxchat_timestamp_ms(void);

/**
 * Compare message IDs
 * @return 0 if equal, non-zero otherwise
 */
CYXCHAT_API int cyxchat_msg_id_cmp(
    const cyxchat_msg_id_t *a,
    const cyxchat_msg_id_t *b
);

/**
 * Check if message ID is zero (null)
 */
CYXCHAT_API int cyxchat_msg_id_is_zero(const cyxchat_msg_id_t *id);

/**
 * Convert message ID to hex string
 * @param hex_out Buffer of at least 17 bytes (16 + null)
 */
CYXCHAT_API void cyxchat_msg_id_to_hex(
    const cyxchat_msg_id_t *id,
    char *hex_out
);

/**
 * Parse message ID from hex string
 */
CYXCHAT_API cyxchat_error_t cyxchat_msg_id_from_hex(
    const char *hex,
    cyxchat_msg_id_t *id_out
);

/**
 * Convert node ID to hex string
 * @param hex_out Buffer of at least 65 bytes (64 + null)
 */
CYXCHAT_API void cyxchat_node_id_to_hex(
    const cyxwiz_node_id_t *id,
    char *hex_out
);

/**
 * Parse node ID from hex string
 */
CYXCHAT_API cyxchat_error_t cyxchat_node_id_from_hex(
    const char *hex,
    cyxwiz_node_id_t *id_out
);

/**
 * Send raw data via onion routing (for internal use by file/other modules)
 *
 * @param ctx           Chat context
 * @param to            Recipient node ID
 * @param data          Data to send
 * @param data_len      Data length
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_send_raw(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const uint8_t *data,
    size_t data_len
);

/* Forward declaration for file context */
struct cyxchat_file_ctx;
typedef struct cyxchat_file_ctx cyxchat_file_ctx_t;

/**
 * Register file context for automatic message routing
 * File messages (FILE_META, FILE_CHUNK, FILE_ACK) will be forwarded
 */
CYXCHAT_API void cyxchat_set_file_ctx(
    cyxchat_ctx_t *ctx,
    cyxchat_file_ctx_t *file_ctx
);

/**
 * Get the onion context (for modules that need direct access)
 */
CYXCHAT_API cyxwiz_onion_ctx_t* cyxchat_get_onion(cyxchat_ctx_t *ctx);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_CHAT_H */
