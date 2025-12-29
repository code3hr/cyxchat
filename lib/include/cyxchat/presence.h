/**
 * CyxChat Presence API
 * Online status and presence management
 */

#ifndef CYXCHAT_PRESENCE_H
#define CYXCHAT_PRESENCE_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declaration */
typedef struct cyxchat_ctx cyxchat_ctx_t;

/* ============================================================
 * Presence Info
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t node_id;
    cyxchat_presence_t status;
    char status_text[CYXCHAT_MAX_STATUS_LEN];
    uint64_t last_seen;
    uint64_t updated_at;
} cyxchat_presence_info_t;

/* ============================================================
 * Presence Messages
 * ============================================================ */

/* Presence update message */
typedef struct {
    cyxchat_msg_header_t header;
    uint8_t status;                         /* cyxchat_presence_t */
    uint8_t status_len;
    char status_text[CYXCHAT_MAX_STATUS_LEN];
} cyxchat_presence_msg_t;

/* Presence request message */
typedef struct {
    cyxchat_msg_header_t header;
    /* No additional fields - just requesting presence */
} cyxchat_presence_req_msg_t;

/* ============================================================
 * Presence Context
 * ============================================================ */

typedef struct cyxchat_presence_ctx cyxchat_presence_ctx_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

typedef void (*cyxchat_on_presence_update_t)(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    cyxchat_presence_t status,
    const char *status_text,
    void *user_data
);

typedef void (*cyxchat_on_presence_request_t)(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    void *user_data
);

/* ============================================================
 * Initialization
 * ============================================================ */

CYXCHAT_API cyxchat_error_t cyxchat_presence_ctx_create(
    cyxchat_presence_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
);

CYXCHAT_API void cyxchat_presence_ctx_destroy(cyxchat_presence_ctx_t *ctx);

CYXCHAT_API int cyxchat_presence_poll(cyxchat_presence_ctx_t *ctx, uint64_t now_ms);

/* ============================================================
 * Status Management
 * ============================================================ */

/**
 * Set our presence status
 *
 * @param ctx           Presence context
 * @param status        New status
 * @param status_text   Custom status text (can be NULL)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_presence_set_status(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_presence_t status,
    const char *status_text
);

/**
 * Get our current status
 */
CYXCHAT_API cyxchat_presence_t cyxchat_presence_get_status(
    cyxchat_presence_ctx_t *ctx
);

/**
 * Get our status text
 */
CYXCHAT_API const char* cyxchat_presence_get_status_text(
    cyxchat_presence_ctx_t *ctx
);

/* ============================================================
 * Presence Broadcasting
 * ============================================================ */

/**
 * Broadcast presence to all contacts
 */
CYXCHAT_API cyxchat_error_t cyxchat_presence_broadcast(
    cyxchat_presence_ctx_t *ctx
);

/**
 * Send presence to specific peer
 */
CYXCHAT_API cyxchat_error_t cyxchat_presence_send_to(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *to
);

/**
 * Request presence from peer
 */
CYXCHAT_API cyxchat_error_t cyxchat_presence_request(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *from
);

/* ============================================================
 * Presence Queries
 * ============================================================ */

/**
 * Get cached presence for peer
 *
 * @return Presence info or NULL if not cached
 */
CYXCHAT_API cyxchat_presence_info_t* cyxchat_presence_find(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
);

/**
 * Get presence status for peer
 *
 * @return Cached status or OFFLINE if not known
 */
CYXCHAT_API cyxchat_presence_t cyxchat_presence_get(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
);

/**
 * Check if peer is online
 */
CYXCHAT_API int cyxchat_presence_is_online(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
);

/**
 * Get last seen timestamp for peer
 *
 * @return Timestamp in ms or 0 if never seen
 */
CYXCHAT_API uint64_t cyxchat_presence_last_seen(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
);

/* ============================================================
 * Auto-Away
 * ============================================================ */

/**
 * Enable auto-away after inactivity
 *
 * @param ctx           Presence context
 * @param timeout_ms    Inactivity timeout (0 to disable)
 */
CYXCHAT_API void cyxchat_presence_set_auto_away(
    cyxchat_presence_ctx_t *ctx,
    uint64_t timeout_ms
);

/**
 * Report user activity (resets auto-away timer)
 */
CYXCHAT_API void cyxchat_presence_activity(
    cyxchat_presence_ctx_t *ctx
);

/* ============================================================
 * Callbacks
 * ============================================================ */

CYXCHAT_API void cyxchat_presence_set_on_update(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_on_presence_update_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_presence_set_on_request(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_on_presence_request_t callback,
    void *user_data
);

/* ============================================================
 * Utilities
 * ============================================================ */

/**
 * Get presence status name
 */
CYXCHAT_API const char* cyxchat_presence_status_name(cyxchat_presence_t status);

/**
 * Format last seen as human-readable string
 * e.g., "just now", "5 minutes ago", "yesterday"
 */
CYXCHAT_API void cyxchat_presence_format_last_seen(
    uint64_t last_seen_ms,
    uint64_t now_ms,
    char *out,
    size_t out_len
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_PRESENCE_H */
