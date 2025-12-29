/**
 * CyxChat Core Implementation
 * Direct messaging functionality
 */

#include <cyxchat/chat.h>
#include <cyxwiz/onion.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/memory.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <sys/time.h>
#endif

/* ============================================================
 * Internal Structures
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

    cyxchat_on_delete_t on_delete;
    void *on_delete_data;

    cyxchat_on_edit_t on_edit;
    void *on_edit_data;
};

/* ============================================================
 * Initialization
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

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_destroy(cyxchat_ctx_t *ctx) {
    if (ctx) {
        cyxwiz_secure_zero(ctx, sizeof(cyxchat_ctx_t));
        free(ctx);
    }
}

int cyxchat_poll(cyxchat_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;

    /* TODO: Process incoming messages from onion context */
    (void)now_ms;

    return 0;
}

const cyxwiz_node_id_t* cyxchat_get_local_id(cyxchat_ctx_t *ctx) {
    if (!ctx) return NULL;
    return &ctx->local_id;
}

/* ============================================================
 * Sending Messages
 * ============================================================ */

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
    cyxchat_text_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_TEXT;
    msg.header.flags = CYXCHAT_FLAG_ENCRYPTED;
    msg.header.timestamp = cyxchat_timestamp_ms();

    /* Generate message ID */
    cyxchat_generate_msg_id(&msg.header.msg_id);

    if (reply_to && !cyxchat_msg_id_is_zero(reply_to)) {
        msg.header.flags |= CYXCHAT_FLAG_REPLY;
        memcpy(&msg.reply_to, reply_to, sizeof(cyxchat_msg_id_t));
    }

    msg.text_len = (uint16_t)text_len;
    memcpy(msg.text, text, text_len);

    /* Send via onion routing */
    /* TODO: Build circuit to destination and send */

    if (msg_id_out) {
        memcpy(msg_id_out, &msg.header.msg_id, sizeof(cyxchat_msg_id_t));
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_send_ack(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    cyxchat_msg_status_t status
) {
    if (!ctx || !to || !msg_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_ack_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_ACK;
    msg.header.timestamp = cyxchat_timestamp_ms();

    cyxchat_generate_msg_id(&msg.header.msg_id);
    memcpy(&msg.ack_msg_id, msg_id, sizeof(cyxchat_msg_id_t));
    msg.status = (uint8_t)status;

    /* TODO: Send via onion */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_send_typing(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    int is_typing
) {
    if (!ctx || !to) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_typing_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_TYPING;
    msg.header.timestamp = cyxchat_timestamp_ms();

    cyxchat_generate_msg_id(&msg.header.msg_id);
    msg.is_typing = is_typing ? 1 : 0;

    /* TODO: Send via onion */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_send_reaction(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    const char *reaction,
    int remove
) {
    if (!ctx || !to || !msg_id || !reaction) {
        return CYXCHAT_ERR_NULL;
    }

    size_t reaction_len = strlen(reaction);
    if (reaction_len > 8) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxchat_reaction_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_REACTION;
    msg.header.timestamp = cyxchat_timestamp_ms();

    cyxchat_generate_msg_id(&msg.header.msg_id);
    memcpy(&msg.target_msg_id, msg_id, sizeof(cyxchat_msg_id_t));
    msg.reaction_len = (uint8_t)reaction_len;
    memcpy(msg.reaction, reaction, reaction_len);
    msg.remove = remove ? 1 : 0;

    /* TODO: Send via onion */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_send_delete(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id
) {
    if (!ctx || !to || !msg_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_delete_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_DELETE;
    msg.header.timestamp = cyxchat_timestamp_ms();

    cyxchat_generate_msg_id(&msg.header.msg_id);
    memcpy(&msg.target_msg_id, msg_id, sizeof(cyxchat_msg_id_t));

    /* TODO: Send via onion */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_send_edit(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id,
    const char *new_text,
    size_t new_text_len
) {
    if (!ctx || !to || !msg_id || !new_text) {
        return CYXCHAT_ERR_NULL;
    }

    if (new_text_len > CYXCHAT_MAX_TEXT_LEN) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxchat_edit_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_EDIT;
    msg.header.timestamp = cyxchat_timestamp_ms();

    cyxchat_generate_msg_id(&msg.header.msg_id);
    memcpy(&msg.target_msg_id, msg_id, sizeof(cyxchat_msg_id_t));
    msg.new_text_len = (uint16_t)new_text_len;
    memcpy(msg.new_text, new_text, new_text_len);

    /* TODO: Send via onion */

    return CYXCHAT_OK;
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_set_on_message(
    cyxchat_ctx_t *ctx,
    cyxchat_on_message_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_message = callback;
        ctx->on_message_data = user_data;
    }
}

void cyxchat_set_on_ack(
    cyxchat_ctx_t *ctx,
    cyxchat_on_ack_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_ack = callback;
        ctx->on_ack_data = user_data;
    }
}

void cyxchat_set_on_typing(
    cyxchat_ctx_t *ctx,
    cyxchat_on_typing_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_typing = callback;
        ctx->on_typing_data = user_data;
    }
}

void cyxchat_set_on_reaction(
    cyxchat_ctx_t *ctx,
    cyxchat_on_reaction_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_reaction = callback;
        ctx->on_reaction_data = user_data;
    }
}

void cyxchat_set_on_delete(
    cyxchat_ctx_t *ctx,
    cyxchat_on_delete_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_delete = callback;
        ctx->on_delete_data = user_data;
    }
}

void cyxchat_set_on_edit(
    cyxchat_ctx_t *ctx,
    cyxchat_on_edit_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_edit = callback;
        ctx->on_edit_data = user_data;
    }
}

/* ============================================================
 * Utilities
 * ============================================================ */

void cyxchat_generate_msg_id(cyxchat_msg_id_t *msg_id) {
    if (msg_id) {
        cyxwiz_crypto_random(msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    }
}

uint64_t cyxchat_timestamp_ms(void) {
#ifdef _WIN32
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    return (t - 116444736000000000ULL) / 10000;
#else
    struct timeval tv;
    gettimeofday(&tv, NULL);
    return (uint64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
#endif
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
    for (size_t i = 0; i < CYXCHAT_MSG_ID_SIZE; i++) {
        if (id->bytes[i] != 0) return 0;
    }
    return 1;
}

static const char hex_chars[] = "0123456789abcdef";

void cyxchat_msg_id_to_hex(
    const cyxchat_msg_id_t *id,
    char *hex_out
) {
    if (!id || !hex_out) return;

    for (size_t i = 0; i < CYXCHAT_MSG_ID_SIZE; i++) {
        hex_out[i * 2] = hex_chars[(id->bytes[i] >> 4) & 0x0F];
        hex_out[i * 2 + 1] = hex_chars[id->bytes[i] & 0x0F];
    }
    hex_out[CYXCHAT_MSG_ID_SIZE * 2] = '\0';
}

static int hex_to_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

cyxchat_error_t cyxchat_msg_id_from_hex(
    const char *hex,
    cyxchat_msg_id_t *id_out
) {
    if (!hex || !id_out) {
        return CYXCHAT_ERR_NULL;
    }

    size_t len = strlen(hex);
    if (len != CYXCHAT_MSG_ID_SIZE * 2) {
        return CYXCHAT_ERR_INVALID;
    }

    for (size_t i = 0; i < CYXCHAT_MSG_ID_SIZE; i++) {
        int hi = hex_to_nibble(hex[i * 2]);
        int lo = hex_to_nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            return CYXCHAT_ERR_INVALID;
        }
        id_out->bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    return CYXCHAT_OK;
}

void cyxchat_node_id_to_hex(
    const cyxwiz_node_id_t *id,
    char *hex_out
) {
    if (!id || !hex_out) return;

    for (size_t i = 0; i < 32; i++) {
        hex_out[i * 2] = hex_chars[(id->bytes[i] >> 4) & 0x0F];
        hex_out[i * 2 + 1] = hex_chars[id->bytes[i] & 0x0F];
    }
    hex_out[64] = '\0';
}

cyxchat_error_t cyxchat_node_id_from_hex(
    const char *hex,
    cyxwiz_node_id_t *id_out
) {
    if (!hex || !id_out) {
        return CYXCHAT_ERR_NULL;
    }

    size_t len = strlen(hex);
    if (len != 64) {
        return CYXCHAT_ERR_INVALID;
    }

    for (size_t i = 0; i < 32; i++) {
        int hi = hex_to_nibble(hex[i * 2]);
        int lo = hex_to_nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            return CYXCHAT_ERR_INVALID;
        }
        id_out->bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    return CYXCHAT_OK;
}
