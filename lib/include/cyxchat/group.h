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

    /* Admin permissions (only for admins, bitmask of CYXCHAT_PERM_*) */
    uint8_t permissions;

    /* Member restrictions (bitmask of CYXCHAT_RESTRICT_*) */
    uint8_t restrictions;
    uint64_t restricted_until;      /* 0 = permanent */
    uint64_t last_message_at;       /* For slow mode enforcement */
} cyxchat_group_member_t;

/* ============================================================
 * Group Structure
 * ============================================================ */

typedef struct {
    cyxchat_group_id_t group_id;
    char name[CYXCHAT_MAX_DISPLAY_NAME];
    char description[CYXCHAT_MAX_STATUS_LEN];

    /* Group type */
    cyxchat_group_type_t group_type;            /* Basic or Supergroup */

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

    /* Group Settings */
    cyxchat_group_add_setting_t who_can_add;    /* Who can add members */
    cyxchat_group_edit_setting_t who_can_edit;  /* Who can edit group info */
    cyxchat_group_send_setting_t who_can_send;  /* Who can send messages */
    uint16_t slow_mode_seconds;                 /* 0 = disabled */
    int message_history_visible;                /* New members can see history */

    /* Selected senders (when who_can_send = CYXCHAT_GROUP_SEND_SELECTED) */
    cyxwiz_node_id_t selected_senders[CYXCHAT_MAX_GROUP_MEMBERS];
    uint8_t selected_sender_count;

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

/* Encrypted key size: nonce(24) + key(32) + tag(16) = 72 bytes */
#define CYXCHAT_ENCRYPTED_GROUP_KEY_SIZE 72

typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_group_id_t group_id;
    char group_name[CYXCHAT_MAX_DISPLAY_NAME];
    uint32_t key_version;                       /* Group key version */
    uint8_t encrypted_key[CYXCHAT_ENCRYPTED_GROUP_KEY_SIZE]; /* Encrypted group key */
    cyxwiz_node_id_t inviter;
    uint8_t inviter_pubkey[32];                 /* Inviter's X25519 public key */
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
    const char *msg_payload,
    void *user_data
);

/* data is valid only for the duration of the callback; copy it if retained. */
typedef void (*cyxchat_on_group_media_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_media_t *media,
    const uint8_t *data,
    size_t data_len,
    void *user_data
);

typedef void (*cyxchat_on_group_media_progress_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_file_id_t *file_id,
    uint32_t chunks_done,
    uint32_t chunks_total,
    int is_outgoing,
    void *user_data
);

typedef void (*cyxchat_on_group_media_error_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_file_id_t *file_id,
    cyxchat_error_t error,
    int is_outgoing,
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

typedef void (*cyxchat_on_group_delivery_failed_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const cyxwiz_node_id_t *failed_members,
    size_t failed_count,
    void *user_data
);

typedef void (*cyxchat_on_group_delivery_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    size_t acked_count,
    size_t total_count,
    void *user_data
);

typedef void (*cyxchat_on_group_key_update_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint32_t new_version,
    void *user_data
);

typedef void (*cyxchat_on_key_dist_complete_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint32_t new_version,
    int success,           /* 1 = all members ACKed, 0 = some failed */
    size_t failed_count,   /* Number of members who didn't ACK */
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
 * Restore a group from saved data (e.g., from database on app restart)
 *
 * This function recreates the group in memory from previously saved data.
 * Use this on startup to restore groups loaded from persistent storage.
 *
 * @param ctx           Group context
 * @param group_id      Group ID to restore
 * @param name          Group name
 * @param group_key     32-byte group encryption key
 * @param key_version   Current key version
 * @param creator_id    Creator node ID
 * @param my_role       Our role in the group (OWNER, ADMIN, or MEMBER)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_restore(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *name,
    const uint8_t *group_key,
    uint32_t key_version,
    const cyxwiz_node_id_t *creator_id,
    cyxchat_group_role_t my_role
);

/**
 * Add a member to a restored group (used after cyxchat_group_restore)
 *
 * After restoring a group from database, call this function for each
 * member to populate the in-memory member list so messages can be sent.
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param member_id     Member's node ID to add
 * @param role          Member's role (OWNER, ADMIN, or MEMBER)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_restore_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id,
    cyxchat_group_role_t role
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
 * Free a group invite (must be called after accept/decline to avoid memory leak)
 * The invite is heap-allocated for async Dart callbacks.
 */
CYXCHAT_API void cyxchat_group_free_invite(
    cyxchat_group_invite_t *invite
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
 * Get group key and version (for persistence)
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param key_out       Output: 32-byte group key (must be pre-allocated)
 * @param version_out   Output: key version
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_get_key(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint8_t *key_out,
    uint32_t *version_out
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

CYXCHAT_API void cyxchat_group_set_on_media(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_media_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_media_progress(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_media_progress_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_media_error(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_media_error_t callback,
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

CYXCHAT_API void cyxchat_group_set_on_delivery_failed(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_delivery_failed_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_delivery(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_delivery_t callback,
    void *user_data
);

/**
 * Set callback for key distribution completion
 *
 * Called when key distribution to all members finishes (success or failure).
 */
CYXCHAT_API void cyxchat_group_set_on_key_dist_complete(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_key_dist_complete_t callback,
    void *user_data
);

/* ============================================================
 * Key Distribution Progress
 * ============================================================ */

/**
 * Get key distribution progress for a group
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param sent_out      Output: number of members key was sent to
 * @param acked_out     Output: number of members who ACKed
 * @param total_out     Output: total members to distribute to
 * @return              1 if distribution in progress, 0 if not
 */
CYXCHAT_API int cyxchat_group_key_dist_progress(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    size_t *sent_out,
    size_t *acked_out,
    size_t *total_out
);

/* ============================================================
 * Auto-Rotation Configuration
 * ============================================================ */

/**
 * Enable or disable auto-rotation when a member voluntarily leaves
 *
 * When enabled (default), if we are admin and a member leaves,
 * we automatically rotate the group key for forward secrecy.
 */
CYXCHAT_API void cyxchat_group_set_auto_rotate_on_leave(
    cyxchat_group_ctx_t *ctx,
    int enable
);

/**
 * Enable or disable auto-rotation when receiving a kick notification
 *
 * When enabled, if we are admin and receive a kick notification from
 * another admin, we also rotate the key (backup rotation).
 * Disabled by default since the kicking admin already rotates.
 */
CYXCHAT_API void cyxchat_group_set_auto_rotate_on_kick(
    cyxchat_group_ctx_t *ctx,
    int enable
);

/**
 * Get current auto-rotation settings
 */
CYXCHAT_API void cyxchat_group_get_auto_rotate_settings(
    cyxchat_group_ctx_t *ctx,
    int *on_leave_out,
    int *on_kick_out
);

/* ============================================================
 * Admin Permissions (Supergroup only)
 * ============================================================ */

/**
 * Set admin permissions for a specific admin
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param admin         Admin node ID
 * @param permissions   Bitmask of CYXCHAT_PERM_* flags
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_set_admin_permissions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin,
    uint8_t permissions
);

/**
 * Get admin permissions for a specific admin
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param admin         Admin node ID
 * @return              Bitmask of permissions, or 0 if not admin
 */
CYXCHAT_API uint8_t cyxchat_group_get_admin_permissions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin
);

/**
 * Check if admin has specific permission
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param admin         Admin node ID (NULL = check self)
 * @param permission    Single CYXCHAT_PERM_* flag
 * @return              1 if has permission, 0 if not
 */
CYXCHAT_API int cyxchat_group_has_permission(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin,
    uint8_t permission
);

/* ============================================================
 * Member Restrictions
 * ============================================================ */

/**
 * Restrict a member (mute, disable media, etc.)
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param member        Member to restrict
 * @param restrictions  Bitmask of CYXCHAT_RESTRICT_* flags
 * @param until_ms      Restriction end time (0 = permanent)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_restrict_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member,
    uint8_t restrictions,
    uint64_t until_ms
);

/**
 * Remove all restrictions from a member
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param member        Member to unrestrict
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_unrestrict_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Get member restrictions
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param member        Member to check
 * @param until_out     Output: restriction end time (0 = permanent)
 * @return              Bitmask of restrictions, or 0 if none
 */
CYXCHAT_API uint8_t cyxchat_group_get_member_restrictions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member,
    uint64_t *until_out
);

/**
 * Check if member is muted
 */
CYXCHAT_API int cyxchat_group_is_member_muted(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/* ============================================================
 * Group Settings
 * ============================================================ */

/**
 * Set slow mode for group
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param seconds       Seconds between messages per member (0 = disabled)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_set_slow_mode(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint16_t seconds
);

/**
 * Get slow mode setting
 */
CYXCHAT_API uint16_t cyxchat_group_get_slow_mode(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Set who can add members
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param setting       CYXCHAT_GROUP_SETTING_ALL_CAN_ADD or ADMINS_CAN_ADD
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_set_who_can_add(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_group_add_setting_t setting
);

/**
 * Set who can edit group info
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param setting       CYXCHAT_GROUP_SETTING_ALL_CAN_EDIT or ADMINS_CAN_EDIT
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_set_who_can_edit(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_group_edit_setting_t setting
);

/**
 * Set who can send messages
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param setting       CYXCHAT_GROUP_SEND_ALL, ADMINS, or SELECTED
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_set_who_can_send(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_group_send_setting_t setting
);

/**
 * Get who can send messages setting
 */
CYXCHAT_API cyxchat_group_send_setting_t cyxchat_group_get_who_can_send(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Add member to selected senders list
 * Only effective when who_can_send = CYXCHAT_GROUP_SEND_SELECTED
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param member        Member to allow sending
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_add_selected_sender(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Remove member from selected senders list
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_remove_selected_sender(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Check if member can send messages
 * Returns 1 if allowed, 0 if not
 */
CYXCHAT_API int cyxchat_group_can_send(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
);

/**
 * Get group type (basic or supergroup)
 */
CYXCHAT_API cyxchat_group_type_t cyxchat_group_get_type(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Upgrade basic group to supergroup (owner only)
 * Enables: granular permissions, admin log, unlimited members
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_upgrade_to_supergroup(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/* ============================================================
 * Admin Action Callback
 * Note: cyxchat_admin_action_type_t is defined in types.h
 * ============================================================ */

typedef void (*cyxchat_on_admin_action_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin,
    cyxchat_admin_action_type_t action,
    const cyxwiz_node_id_t *target,  /* May be NULL */
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_admin_action(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_admin_action_t callback,
    void *user_data
);

/* ============================================================
 * Message Actions (Edit/Delete/Pin/Forward)
 * ============================================================ */

/**
 * Edit a group message
 * Only the original sender can edit within the time limit
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param msg_id        Message ID to edit
 * @param new_text      New message text
 * @param new_text_len  Length of new text
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_edit_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const char *new_text,
    size_t new_text_len
);

/**
 * Delete a group message
 * Sender can delete their own messages, admins can delete any message
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param msg_id        Message ID to delete
 * @param delete_for_all  1 = delete for everyone, 0 = delete only for self
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_delete_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    int delete_for_all
);

/**
 * Pin a message in group (admin only with PIN_MESSAGES permission)
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param msg_id        Message ID to pin
 * @param notify        1 = notify all members, 0 = silent pin
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_pin_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    int notify
);

/**
 * Unpin a message (admin only with PIN_MESSAGES permission)
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param msg_id        Message ID to unpin
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_unpin_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id
);

/**
 * Unpin all messages in group (admin only)
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_unpin_all(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Get count of pinned messages
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @return              Number of pinned messages
 */
CYXCHAT_API size_t cyxchat_group_get_pinned_count(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Get pinned message IDs
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param msg_ids_out   Output array for message IDs
 * @param max_count     Size of output array
 * @return              Number of pinned messages returned
 */
CYXCHAT_API size_t cyxchat_group_get_pinned_messages(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_msg_id_t *msg_ids_out,
    size_t max_count
);

/**
 * Check if message is pinned
 *
 * @param ctx           Group context
 * @param group_id      Group ID
 * @param msg_id        Message ID to check
 * @return              1 if pinned, 0 if not
 */
CYXCHAT_API int cyxchat_group_is_message_pinned(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id
);

/**
 * Forward a message to another group
 *
 * @param ctx               Group context
 * @param from_group_id     Source group ID
 * @param to_group_id       Destination group ID
 * @param msg_id            Message ID to forward
 * @param new_msg_id_out    Output: new message ID in destination group
 * @return                  CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_forward_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *from_group_id,
    const cyxchat_group_id_t *to_group_id,
    const cyxchat_msg_id_t *msg_id,
    cyxchat_msg_id_t *new_msg_id_out
);

/* ============================================================
 * Message Action Callbacks
 * ============================================================ */

typedef void (*cyxchat_on_message_edit_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const cyxwiz_node_id_t *editor,
    const char *new_text,
    size_t text_len,
    void *user_data
);

typedef void (*cyxchat_on_message_delete_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const cyxwiz_node_id_t *deleter,
    int deleted_for_all,
    void *user_data
);

typedef void (*cyxchat_on_message_pin_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const cyxwiz_node_id_t *pinner,
    int is_pinned,  /* 1 = pinned, 0 = unpinned */
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_message_edit(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_message_edit_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_message_delete(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_message_delete_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_message_pin(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_message_pin_t callback,
    void *user_data
);

/* ============================================================
 * Message Handling (Internal - called by chat module)
 * ============================================================ */

/**
 * Handle incoming group message
 * Called by chat module when group message (0x20-0x2F) is received
 *
 * @param ctx       Group context
 * @param from      Sender node ID
 * @param type      Message type (CYXCHAT_MSG_GROUP_*)
 * @param data      Raw message data
 * @param len       Data length
 */
CYXCHAT_API void cyxchat_group_handle_message(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    uint8_t type,
    const uint8_t *data,
    size_t len
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

/* ============================================================
 * Invite Links
 * ============================================================ */

/**
 * Create an invite link for a group
 *
 * @param ctx           Group context
 * @param group_id      Group to create link for
 * @param name          Optional link name (can be NULL)
 * @param expires_at_ms Expiry timestamp (0 = never expires)
 * @param max_uses      Max number of uses (0 = unlimited)
 * @param link_out      Output: created invite link
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_create_invite_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *name,
    uint64_t expires_at_ms,
    uint32_t max_uses,
    cyxchat_invite_link_t *link_out
);

/**
 * Revoke an invite link
 *
 * @param ctx       Group context
 * @param group_id  Group the link belongs to
 * @param link_id   Link ID to revoke
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_revoke_invite_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *link_id
);

/**
 * Join a group via invite link
 *
 * @param ctx       Group context
 * @param group_id  Group to join
 * @param link_id   Invite link ID
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_join_via_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *link_id
);

/**
 * Get all invite links for a group
 *
 * @param ctx           Group context
 * @param group_id      Group to get links for
 * @param links_out     Output array for links
 * @param max_links     Size of output array
 * @param count_out     Output: number of links returned
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_get_invite_links(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_invite_link_t *links_out,
    size_t max_links,
    size_t *count_out
);

/**
 * Get a specific invite link
 *
 * @param ctx       Group context
 * @param group_id  Group the link belongs to
 * @param link_id   Link ID to get
 * @param link_out  Output: the invite link
 * @return          CYXCHAT_OK on success, CYXCHAT_ERR_NOT_FOUND if not found
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_get_invite_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *link_id,
    cyxchat_invite_link_t *link_out
);

/**
 * Generate URL for an invite link
 *
 * @param link      The invite link
 * @param url_out   Output buffer for URL string
 * @param url_size  Size of output buffer
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_invite_link_to_url(
    const cyxchat_invite_link_t *link,
    char *url_out,
    size_t url_size
);

/**
 * Parse an invite URL into group ID and link ID
 *
 * @param url           Invite URL (cyxchat://join/...)
 * @param group_id_out  Output: group ID
 * @param link_id_out   Output: link ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_parse_invite_url(
    const char *url,
    cyxchat_group_id_t *group_id_out,
    uint8_t *link_id_out
);

/* ============================================================
 * Invite Link Callbacks
 * ============================================================ */

typedef void (*cyxchat_on_invite_link_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_invite_link_t *link,
    int is_revoked,  /* 1 if revoked, 0 if created/updated */
    void *user_data
);

typedef void (*cyxchat_on_join_via_link_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *link_id,
    const cyxwiz_node_id_t *new_member,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_invite_link(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_invite_link_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_group_set_on_join_via_link(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_join_via_link_t callback,
    void *user_data
);

/* ============================================================
 * Admin Action Log
 * ============================================================ */

/**
 * Log an admin action
 *
 * @param ctx           Group context
 * @param group_id      Group where action occurred
 * @param action_type   Type of action performed
 * @param target_id     Target user (can be NULL)
 * @param target_msg_id Target message (can be NULL)
 * @param old_value     Previous value (can be NULL)
 * @param new_value     New value (can be NULL)
 * @param action_out    Output: created action entry
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_log_admin_action(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_admin_action_type_t action_type,
    const cyxwiz_node_id_t *target_id,
    const cyxchat_msg_id_t *target_msg_id,
    const char *old_value,
    const char *new_value,
    cyxchat_admin_action_t *action_out
);

/**
 * Get admin actions for a group
 *
 * @param ctx           Group context
 * @param group_id      Group to get actions for
 * @param actions_out   Output array for actions
 * @param max_actions   Size of output array
 * @param offset        Offset for pagination (0 = most recent)
 * @param count_out     Output: number of actions returned
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_get_admin_actions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_admin_action_t *actions_out,
    size_t max_actions,
    size_t offset,
    size_t *count_out
);

/**
 * Get admin actions by a specific admin
 *
 * @param ctx           Group context
 * @param group_id      Group to get actions for
 * @param admin_id      Admin to filter by
 * @param actions_out   Output array for actions
 * @param max_actions   Size of output array
 * @param count_out     Output: number of actions returned
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_get_admin_actions_by_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin_id,
    cyxchat_admin_action_t *actions_out,
    size_t max_actions,
    size_t *count_out
);

/**
 * Get total count of admin actions
 *
 * @param ctx           Group context
 * @param group_id      Group to count actions for
 * @return              Total number of actions
 */
CYXCHAT_API size_t cyxchat_group_get_admin_action_count(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
);

/**
 * Get a specific admin action by ID
 *
 * @param ctx           Group context
 * @param action_id     Action ID to get
 * @param action_out    Output: the admin action
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_get_admin_action(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *action_id,
    cyxchat_admin_action_t *action_out
);

/**
 * Convert admin action ID to hex string
 */
CYXCHAT_API void cyxchat_admin_action_id_to_hex(
    const uint8_t *action_id,
    char *hex_out
);

/**
 * Parse admin action ID from hex string
 */
CYXCHAT_API cyxchat_error_t cyxchat_admin_action_id_from_hex(
    const char *hex,
    uint8_t *action_id_out
);

/* ============================================================
 * Group Media/File Sharing (Phase 5)
 * ============================================================ */

/**
 * Send a file to a group
 *
 * Initiates chunked file transfer to all group members.
 * Files up to CYXCHAT_MAX_MEDIA_SIZE bytes are supported.
 *
 * @param ctx           Group context
 * @param group_id      Target group
 * @param filename      Original filename
 * @param mime_type     MIME type (e.g., "image/jpeg", "application/pdf")
 * @param data          File data
 * @param data_len      Size of file data
 * @param thumbnail     Optional thumbnail data (for images/videos)
 * @param thumbnail_len Size of thumbnail (0 if no thumbnail)
 * @param file_id_out   Output: generated file ID
 * @param msg_id_out    Output: generated message ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_send_file(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *filename,
    const char *mime_type,
    const uint8_t *data,
    size_t data_len,
    const uint8_t *thumbnail,
    size_t thumbnail_len,
    cyxchat_file_id_t *file_id_out,
    cyxchat_msg_id_t *msg_id_out
);

/**
 * Send a voice message to a group
 *
 * Voice messages are Opus-encoded audio with duration metadata.
 *
 * @param ctx           Group context
 * @param group_id      Target group
 * @param audio_data    Opus-encoded audio data
 * @param audio_len     Size of audio data
 * @param duration_ms   Duration in milliseconds
 * @param msg_id_out    Output: generated message ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_send_voice(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *audio_data,
    size_t audio_len,
    uint32_t duration_ms,
    cyxchat_msg_id_t *msg_id_out
);

/**
 * Send an image to a group
 *
 * Images are automatically compressed and thumbnailed.
 *
 * @param ctx           Group context
 * @param group_id      Target group
 * @param filename      Original filename
 * @param image_data    Image data (JPEG, PNG, WebP)
 * @param image_len     Size of image data
 * @param width         Image width in pixels
 * @param height        Image height in pixels
 * @param msg_id_out    Output: generated message ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_send_image(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *filename,
    const uint8_t *image_data,
    size_t image_len,
    uint16_t width,
    uint16_t height,
    cyxchat_msg_id_t *msg_id_out
);

/**
 * Get media messages for a group (for gallery view)
 *
 * @param ctx           Group context
 * @param group_id      Group to get media from
 * @param media_type    Filter by media type (-1 for all types)
 * @param media_out     Output array for media metadata
 * @param max_media     Size of output array
 * @param offset        Offset for pagination
 * @param count_out     Output: number of media returned
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_group_get_media(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    int media_type,
    cyxchat_group_media_t *media_out,
    size_t max_media,
    size_t offset,
    size_t *count_out
);

/**
 * Get count of media messages in a group
 *
 * @param ctx           Group context
 * @param group_id      Group to count media in
 * @param media_type    Filter by media type (-1 for all types)
 * @return              Count of media messages
 */
CYXCHAT_API size_t cyxchat_group_get_media_count(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    int media_type
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_GROUP_H */
