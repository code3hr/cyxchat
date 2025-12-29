/**
 * CyxChat Group Chat Implementation
 */

#include <cyxchat/group.h>
#include <cyxchat/chat.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/memory.h>
#include <string.h>
#include <stdlib.h>

/* ============================================================
 * Constants
 * ============================================================ */

#define CYXCHAT_MAX_GROUPS 32

/* ============================================================
 * Internal Structures
 * ============================================================ */

struct cyxchat_group_ctx {
    cyxchat_ctx_t *chat_ctx;
    cyxwiz_node_id_t local_id;

    /* Groups */
    cyxchat_group_t groups[CYXCHAT_MAX_GROUPS];
    size_t group_count;

    /* Callbacks */
    cyxchat_on_group_message_t on_message;
    void *on_message_data;

    cyxchat_on_group_invite_t on_invite;
    void *on_invite_data;

    cyxchat_on_member_join_t on_member_join;
    void *on_member_join_data;

    cyxchat_on_member_leave_t on_member_leave;
    void *on_member_leave_data;

    cyxchat_on_group_key_update_t on_key_update;
    void *on_key_update_data;
};

/* ============================================================
 * Helper Functions
 * ============================================================ */

static cyxchat_group_t* find_group(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    for (size_t i = 0; i < ctx->group_count; i++) {
        if (memcmp(ctx->groups[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            return &ctx->groups[i];
        }
    }
    return NULL;
}

static cyxchat_group_member_t* find_member(
    cyxchat_group_t *group,
    const cyxwiz_node_id_t *node_id
) {
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, node_id->bytes, 32) == 0) {
            return &group->members[i];
        }
    }
    return NULL;
}

static int is_member(
    cyxchat_group_t *group,
    const cyxwiz_node_id_t *node_id
) {
    return find_member(group, node_id) != NULL;
}

static cyxchat_group_role_t get_role(
    cyxchat_group_t *group,
    const cyxwiz_node_id_t *node_id
) {
    cyxchat_group_member_t *member = find_member(group, node_id);
    return member ? member->role : CYXCHAT_ROLE_MEMBER;
}

/* ============================================================
 * Initialization
 * ============================================================ */

cyxchat_error_t cyxchat_group_ctx_create(
    cyxchat_group_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
) {
    if (!ctx || !chat_ctx) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_ctx_t *c = calloc(1, sizeof(cyxchat_group_ctx_t));
    if (!c) {
        return CYXCHAT_ERR_MEMORY;
    }

    c->chat_ctx = chat_ctx;

    const cyxwiz_node_id_t *local = cyxchat_get_local_id(chat_ctx);
    if (local) {
        memcpy(&c->local_id, local, sizeof(cyxwiz_node_id_t));
    }

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_group_ctx_destroy(cyxchat_group_ctx_t *ctx) {
    if (ctx) {
        /* Securely clear group keys */
        for (size_t i = 0; i < ctx->group_count; i++) {
            cyxwiz_secure_zero(ctx->groups[i].group_key, 32);
        }
        cyxwiz_secure_zero(ctx, sizeof(cyxchat_group_ctx_t));
        free(ctx);
    }
}

int cyxchat_group_poll(cyxchat_group_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;
    (void)now_ms;
    /* TODO: Process incoming group messages */
    return 0;
}

/* ============================================================
 * Group Management
 * ============================================================ */

cyxchat_error_t cyxchat_group_create(
    cyxchat_group_ctx_t *ctx,
    const char *name,
    cyxchat_group_id_t *group_id_out
) {
    if (!ctx || !name) {
        return CYXCHAT_ERR_NULL;
    }

    if (ctx->group_count >= CYXCHAT_MAX_GROUPS) {
        return CYXCHAT_ERR_FULL;
    }

    cyxchat_group_t *group = &ctx->groups[ctx->group_count];
    memset(group, 0, sizeof(cyxchat_group_t));

    /* Generate random group ID */
    cyxwiz_crypto_random(group->group_id.bytes, CYXCHAT_GROUP_ID_SIZE);

    /* Set name */
    strncpy(group->name, name, CYXCHAT_MAX_DISPLAY_NAME - 1);

    /* Set creator */
    memcpy(&group->creator, &ctx->local_id, sizeof(cyxwiz_node_id_t));

    /* Generate group key */
    cyxwiz_crypto_random(group->group_key, 32);
    group->key_version = 1;

    /* Add ourselves as owner */
    cyxchat_group_member_t *self = &group->members[0];
    memcpy(&self->node_id, &ctx->local_id, sizeof(cyxwiz_node_id_t));
    self->role = CYXCHAT_ROLE_OWNER;
    self->joined_at = cyxchat_timestamp_ms();
    group->member_count = 1;

    /* Timestamps */
    group->created_at = cyxchat_timestamp_ms();
    group->key_updated_at = group->created_at;

    ctx->group_count++;

    if (group_id_out) {
        memcpy(group_id_out, &group->group_id, sizeof(cyxchat_group_id_t));
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_set_description(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *description
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check admin permission */
    cyxchat_group_role_t role = get_role(group, &ctx->local_id);
    if (role < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    memset(group->description, 0, CYXCHAT_MAX_STATUS_LEN);
    if (description) {
        strncpy(group->description, description, CYXCHAT_MAX_STATUS_LEN - 1);
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_set_name(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *name
) {
    if (!ctx || !group_id || !name) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check admin permission */
    cyxchat_group_role_t role = get_role(group, &ctx->local_id);
    if (role < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    memset(group->name, 0, CYXCHAT_MAX_DISPLAY_NAME);
    strncpy(group->name, name, CYXCHAT_MAX_DISPLAY_NAME - 1);

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member,
    const uint8_t *member_pubkey
) {
    if (!ctx || !group_id || !member || !member_pubkey) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check we are member */
    if (!is_member(group, &ctx->local_id)) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Check not already member */
    if (is_member(group, member)) {
        return CYXCHAT_ERR_EXISTS;
    }

    if (group->member_count >= CYXCHAT_MAX_GROUP_MEMBERS) {
        return CYXCHAT_ERR_FULL;
    }

    /* Build invitation message */
    cyxchat_group_invite_t invite;
    memset(&invite, 0, sizeof(invite));

    invite.header.version = CYXCHAT_PROTOCOL_VERSION;
    invite.header.type = CYXCHAT_MSG_GROUP_INVITE;
    invite.header.timestamp = cyxchat_timestamp_ms();
    cyxchat_generate_msg_id(&invite.header.msg_id);

    memcpy(&invite.group_id, group_id, sizeof(cyxchat_group_id_t));
    memcpy(invite.group_name, group->name, CYXCHAT_MAX_DISPLAY_NAME);
    memcpy(&invite.inviter, &ctx->local_id, sizeof(cyxwiz_node_id_t));

    /* Encrypt group key for recipient */
    /* TODO: Use X25519 + XChaCha20-Poly1305 with member_pubkey */

    /* TODO: Send invite via onion */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_accept_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_invite_t *invite
) {
    if (!ctx || !invite) {
        return CYXCHAT_ERR_NULL;
    }

    if (ctx->group_count >= CYXCHAT_MAX_GROUPS) {
        return CYXCHAT_ERR_FULL;
    }

    /* Create new group entry */
    cyxchat_group_t *group = &ctx->groups[ctx->group_count];
    memset(group, 0, sizeof(cyxchat_group_t));

    memcpy(&group->group_id, &invite->group_id, sizeof(cyxchat_group_id_t));
    memcpy(group->name, invite->group_name, CYXCHAT_MAX_DISPLAY_NAME);

    /* Decrypt group key from invite */
    /* TODO: Decrypt invite->encrypted_key into group->group_key */

    group->key_version = 1;
    group->created_at = cyxchat_timestamp_ms();
    group->key_updated_at = group->created_at;

    /* Add ourselves as member */
    cyxchat_group_member_t *self = &group->members[0];
    memcpy(&self->node_id, &ctx->local_id, sizeof(cyxwiz_node_id_t));
    self->role = CYXCHAT_ROLE_MEMBER;
    self->joined_at = cyxchat_timestamp_ms();
    group->member_count = 1;

    ctx->group_count++;

    /* TODO: Send join notification */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_decline_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_invite_t *invite
) {
    (void)ctx;
    (void)invite;
    /* No action needed - just don't accept */
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_leave(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* TODO: Send leave notification to group */

    /* Mark as left */
    group->left = 1;

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_remove_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
) {
    if (!ctx || !group_id || !member) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check admin permission */
    cyxchat_group_role_t our_role = get_role(group, &ctx->local_id);
    if (our_role < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Find and remove member */
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, member->bytes, 32) == 0) {
            /* Can't remove owner */
            if (group->members[i].role == CYXCHAT_ROLE_OWNER) {
                return CYXCHAT_ERR_INVALID;
            }

            /* Admin can only remove members, not other admins */
            if (our_role == CYXCHAT_ROLE_ADMIN &&
                group->members[i].role == CYXCHAT_ROLE_ADMIN) {
                return CYXCHAT_ERR_NOT_ADMIN;
            }

            /* Move last member to this slot */
            if (i < group->member_count - 1) {
                memcpy(&group->members[i],
                       &group->members[group->member_count - 1],
                       sizeof(cyxchat_group_member_t));
            }
            group->member_count--;

            /* Rotate key after removal */
            cyxchat_group_rotate_key(ctx, group_id);

            /* TODO: Send kick notification */

            return CYXCHAT_OK;
        }
    }

    return CYXCHAT_ERR_NOT_FOUND;
}

cyxchat_error_t cyxchat_group_add_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
) {
    if (!ctx || !group_id || !member) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only owner can promote */
    if (get_role(group, &ctx->local_id) != CYXCHAT_ROLE_OWNER) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    cyxchat_group_member_t *mem = find_member(group, member);
    if (!mem) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    mem->role = CYXCHAT_ROLE_ADMIN;

    /* TODO: Broadcast admin change */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_remove_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
) {
    if (!ctx || !group_id || !member) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only owner can demote */
    if (get_role(group, &ctx->local_id) != CYXCHAT_ROLE_OWNER) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    cyxchat_group_member_t *mem = find_member(group, member);
    if (!mem) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Can't demote owner */
    if (mem->role == CYXCHAT_ROLE_OWNER) {
        return CYXCHAT_ERR_INVALID;
    }

    mem->role = CYXCHAT_ROLE_MEMBER;

    /* TODO: Broadcast admin change */

    return CYXCHAT_OK;
}

/* ============================================================
 * Group Messaging
 * ============================================================ */

cyxchat_error_t cyxchat_group_send_text(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *text,
    size_t text_len,
    const cyxchat_msg_id_t *reply_to,
    cyxchat_msg_id_t *msg_id_out
) {
    if (!ctx || !group_id || !text) {
        return CYXCHAT_ERR_NULL;
    }

    if (text_len > CYXCHAT_MAX_TEXT_LEN) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    if (!is_member(group, &ctx->local_id) || group->left) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Build group message */
    cyxchat_group_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_GROUP_TEXT;
    msg.header.flags = CYXCHAT_FLAG_ENCRYPTED;
    msg.header.timestamp = cyxchat_timestamp_ms();

    cyxchat_generate_msg_id(&msg.header.msg_id);

    memcpy(&msg.group_id, group_id, sizeof(cyxchat_group_id_t));
    msg.key_version = group->key_version;
    msg.text_len = (uint16_t)text_len;
    memcpy(msg.text, text, text_len);

    if (reply_to && !cyxchat_msg_id_is_zero(reply_to)) {
        msg.header.flags |= CYXCHAT_FLAG_REPLY;
        memcpy(&msg.reply_to, reply_to, sizeof(cyxchat_msg_id_t));
    }

    /* Encrypt with group key */
    /* TODO: Encrypt msg.text with group->group_key */

    /* Send to each member (flat routing) */
    /* TODO: Send via onion to each member */

    if (msg_id_out) {
        memcpy(msg_id_out, &msg.header.msg_id, sizeof(cyxchat_msg_id_t));
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Key Management
 * ============================================================ */

cyxchat_error_t cyxchat_group_rotate_key(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check admin permission */
    if (get_role(group, &ctx->local_id) < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Generate new key */
    cyxwiz_crypto_random(group->group_key, 32);
    group->key_version++;
    group->key_updated_at = cyxchat_timestamp_ms();

    /* TODO: Distribute new key to all members (encrypted per-member) */

    /* Notify callback */
    if (ctx->on_key_update) {
        ctx->on_key_update(ctx, group_id, group->key_version,
                          ctx->on_key_update_data);
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Queries
 * ============================================================ */

cyxchat_group_t* cyxchat_group_find(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return NULL;
    }
    return find_group(ctx, group_id);
}

int cyxchat_group_is_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return 0;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group || group->left) {
        return 0;
    }

    return is_member(group, &ctx->local_id);
}

int cyxchat_group_is_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return 0;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group || group->left) {
        return 0;
    }

    return get_role(group, &ctx->local_id) >= CYXCHAT_ROLE_ADMIN;
}

int cyxchat_group_is_owner(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return 0;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group || group->left) {
        return 0;
    }

    return get_role(group, &ctx->local_id) == CYXCHAT_ROLE_OWNER;
}

cyxchat_group_role_t cyxchat_group_get_role(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ROLE_MEMBER;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ROLE_MEMBER;
    }

    return get_role(group, &ctx->local_id);
}

size_t cyxchat_group_count(cyxchat_group_ctx_t *ctx) {
    return ctx ? ctx->group_count : 0;
}

cyxchat_group_t* cyxchat_group_get(
    cyxchat_group_ctx_t *ctx,
    size_t index
) {
    if (!ctx || index >= ctx->group_count) {
        return NULL;
    }
    return &ctx->groups[index];
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_group_set_on_message(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_message_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_message = callback;
        ctx->on_message_data = user_data;
    }
}

void cyxchat_group_set_on_invite(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_invite_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_invite = callback;
        ctx->on_invite_data = user_data;
    }
}

void cyxchat_group_set_on_member_join(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_member_join_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_member_join = callback;
        ctx->on_member_join_data = user_data;
    }
}

void cyxchat_group_set_on_member_leave(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_member_leave_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_member_leave = callback;
        ctx->on_member_leave_data = user_data;
    }
}

void cyxchat_group_set_on_key_update(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_key_update_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_key_update = callback;
        ctx->on_key_update_data = user_data;
    }
}

/* ============================================================
 * Utilities
 * ============================================================ */

static const char hex_table[] = "0123456789abcdef";

void cyxchat_group_id_to_hex(
    const cyxchat_group_id_t *id,
    char *hex_out
) {
    if (!id || !hex_out) return;

    for (size_t i = 0; i < CYXCHAT_GROUP_ID_SIZE; i++) {
        hex_out[i * 2] = hex_table[(id->bytes[i] >> 4) & 0x0F];
        hex_out[i * 2 + 1] = hex_table[id->bytes[i] & 0x0F];
    }
    hex_out[CYXCHAT_GROUP_ID_SIZE * 2] = '\0';
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

cyxchat_error_t cyxchat_group_id_from_hex(
    const char *hex,
    cyxchat_group_id_t *id_out
) {
    if (!hex || !id_out) {
        return CYXCHAT_ERR_NULL;
    }

    size_t len = strlen(hex);
    if (len != CYXCHAT_GROUP_ID_SIZE * 2) {
        return CYXCHAT_ERR_INVALID;
    }

    for (size_t i = 0; i < CYXCHAT_GROUP_ID_SIZE; i++) {
        int hi = hex_nibble(hex[i * 2]);
        int lo = hex_nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            return CYXCHAT_ERR_INVALID;
        }
        id_out->bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    return CYXCHAT_OK;
}

