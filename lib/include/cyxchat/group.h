/**
 * CyxChat Group API
 * Group chat functionality
 */

#ifndef CYXCHAT_GROUP_H
#define CYXCHAT_GROUP_H

#include "types.h"
#include "chat.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Group Role
 * ============================================================ */

typedef enum {
    CYXCHAT_ROLE_MEMBER = 0,
    CYXCHAT_ROLE_ADMIN  = 1,
    CYXCHAT_ROLE_OWNER  = 2
} cyxchat_group_role_t;

/* ============================================================
 * Group Member
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t node_id;
    cyxchat_group_role_t role;
    char display_name[CYXCHAT_MAX_DISPLAY_NAME];
    uint8_t public_key[32];
    uint64_t joined_at;
} cyxchat_group_member_t;

/* ============================================================
 * Group Structure
 * ============================================================ */

typedef struct {
    cyxchat_group_id_t group_id;
    char name[CYXCHAT_MAX_DISPLAY_NAME];
    char description[CYXCHAT_MAX_STATUS_LEN];

    /* Membership */
    cyxwiz_node_id_t creator;
    cyxchat_group_member_t members[CYXCHAT_MAX_GROUP_MEMBERS];
    uint8_t member_count;

    /* Keys */
    uint8_t group_key[32];                      /* Current group key */
    uint32_t key_version;

    /* Timestamps */
    uint64_t created_at;
    uint64_t key_updated_at;

    /* State */
    int left;                                   /* We left this group */
} cyxchat_group_t;

/* ============================================================
 * Group Message
 * ============================================================ */

typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_group_id_t group_id;
    uint32_t key_version;                       /* Key version used */
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
    uint8_t encrypted_key[48];                  /* Encrypted group key */
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

typedef void (*cyxchat_on_member_join_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member,
    void *user_data
);

typedef void (*cyxchat_on_member_leave_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member,
    int was_kicked,
    void *user_data
);

typedef void (*cyxchat_on_group_key_update_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint32_t new_version,
    void *user_data
);

/* ============================================================
 * Initialization
 * ============================================================ */

CYXCHAT_API cyxchat_error_t cyxchat_group_ctx_create(
    cyxchat_group_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
);

CYXCHAT_API void cyxchat_group_ctx_destroy(cyxchat_group_ctx_t *ctx);

CYXCHAT_API int cyxchat_group_poll(cyxchat_group_ctx_t *ctx, uint64_t now_ms);

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
CYXCHAT_API cyxchat_error_t cyxchat_group_create(
    cyxchat_group_ctx_t *ctx,
    const char *name,
    cyxchat_group_id_t *group_id_out
);

/**
 * Set group description
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_set_description(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *description
);

/**
 * Update group name (admin only)
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_set_name(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *name
);

/**
 * Invite member to group
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member,
    const uint8_t *member_pubkey
);

/**
 * Accept group invitation
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_accept_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_invite_t *invite
);

/**
 * Decline group invitation
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_decline_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_invite_t *invite
);

/**
 * Leave group
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_leave(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Remove member (admin only)
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_remove_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Promote member to admin (owner only)
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_add_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Demote admin to member (owner only)
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_remove_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/* ============================================================
 * Group Messaging
 * ============================================================ */

/**
 * Send message to group
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_send_text(
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
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_rotate_key(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/* ============================================================
 * Queries
 * ============================================================ */

/**
 * Get group by ID
 */
CYXCHAT_API cyxchat_group_t* cyxchat_group_find(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Check if we are member of group
 */
CYXCHAT_API int cyxchat_group_is_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Check if we are admin of group
 */
CYXCHAT_API int cyxchat_group_is_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Check if we are owner of group
 */
CYXCHAT_API int cyxchat_group_is_owner(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Get our role in group
 */
CYXCHAT_API cyxchat_group_role_t cyxchat_group_get_role(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Get group count
 */
CYXCHAT_API size_t cyxchat_group_count(cyxchat_group_ctx_t *ctx);

/**
 * Get group by index
 */
CYXCHAT_API cyxchat_group_t* cyxchat_group_get(
    cyxchat_group_ctx_t *ctx,
    size_t index
);

/* ============================================================
 * Callbacks
 * ============================================================ */

CYXCHAT_API void cyxchat_group_set_on_message(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_message_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_invite(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_invite_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_member_join(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_member_join_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_member_leave(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_member_leave_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_key_update(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_key_update_t callback,
    void *user_data
);

/* ============================================================
 * Utilities
 * ============================================================ */

CYXCHAT_API void cyxchat_group_id_to_hex(
    const cyxchat_group_id_t *id,
    char *hex_out
);

CYXCHAT_API cyxchat_error_t cyxchat_group_id_from_hex(
    const char *hex,
    cyxchat_group_id_t *id_out
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_GROUP_H */
