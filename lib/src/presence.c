/**
 * CyxChat Presence Implementation
 */

#include <cyxchat/presence.h>
#include <cyxchat/chat.h>
#include <cyxwiz/memory.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ============================================================
 * Constants
 * ============================================================ */

#define CYXCHAT_MAX_PRESENCE_CACHE 128
#define CYXCHAT_PRESENCE_STALE_MS  300000    /* 5 minutes */

/* ============================================================
 * Internal Structures
 * ============================================================ */

struct cyxchat_presence_ctx {
    cyxchat_ctx_t *chat_ctx;

    /* Our status */
    cyxchat_presence_t our_status;
    char our_status_text[CYXCHAT_MAX_STATUS_LEN];

    /* Auto-away */
    uint64_t auto_away_timeout;
    uint64_t last_activity;
    int auto_away_active;
    cyxchat_presence_t status_before_away;

    /* Cached presence */
    cyxchat_presence_info_t cache[CYXCHAT_MAX_PRESENCE_CACHE];
    size_t cache_count;

    /* Callbacks */
    cyxchat_on_presence_update_t on_update;
    void *on_update_data;

    cyxchat_on_presence_request_t on_request;
    void *on_request_data;
};

/* ============================================================
 * Helper Functions
 * ============================================================ */

static cyxchat_presence_info_t* find_presence(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
) {
    for (size_t i = 0; i < ctx->cache_count; i++) {
        if (memcmp(ctx->cache[i].node_id.bytes, node_id->bytes, 32) == 0) {
            return &ctx->cache[i];
        }
    }
    return NULL;
}

CYXWIZ_MAYBE_UNUSED
static cyxchat_presence_info_t* add_presence(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
) {
    /* Check if already exists */
    cyxchat_presence_info_t *existing = find_presence(ctx, node_id);
    if (existing) return existing;

    /* Find slot */
    if (ctx->cache_count < CYXCHAT_MAX_PRESENCE_CACHE) {
        cyxchat_presence_info_t *info = &ctx->cache[ctx->cache_count];
        memset(info, 0, sizeof(cyxchat_presence_info_t));
        memcpy(&info->node_id, node_id, sizeof(cyxwiz_node_id_t));
        ctx->cache_count++;
        return info;
    }

    /* Cache full - find oldest entry */
    uint64_t oldest_time = ~0ULL;
    size_t oldest_idx = 0;
    for (size_t i = 0; i < ctx->cache_count; i++) {
        if (ctx->cache[i].updated_at < oldest_time) {
            oldest_time = ctx->cache[i].updated_at;
            oldest_idx = i;
        }
    }

    cyxchat_presence_info_t *info = &ctx->cache[oldest_idx];
    memset(info, 0, sizeof(cyxchat_presence_info_t));
    memcpy(&info->node_id, node_id, sizeof(cyxwiz_node_id_t));
    return info;
}

/* ============================================================
 * Initialization
 * ============================================================ */

cyxchat_error_t cyxchat_presence_ctx_create(
    cyxchat_presence_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
) {
    if (!ctx || !chat_ctx) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_presence_ctx_t *c = calloc(1, sizeof(cyxchat_presence_ctx_t));
    if (!c) {
        return CYXCHAT_ERR_MEMORY;
    }

    c->chat_ctx = chat_ctx;
    c->our_status = CYXCHAT_PRESENCE_ONLINE;
    c->last_activity = cyxchat_timestamp_ms();

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_presence_ctx_destroy(cyxchat_presence_ctx_t *ctx) {
    if (ctx) {
        free(ctx);
    }
}

int cyxchat_presence_poll(cyxchat_presence_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;

    int events = 0;

    /* Check auto-away */
    if (ctx->auto_away_timeout > 0 && !ctx->auto_away_active) {
        if (now_ms - ctx->last_activity > ctx->auto_away_timeout) {
            ctx->status_before_away = ctx->our_status;
            ctx->our_status = CYXCHAT_PRESENCE_AWAY;
            ctx->auto_away_active = 1;

            /* Broadcast away status */
            cyxchat_presence_broadcast(ctx);
            events++;
        }
    }

    /* Expire stale presence entries */
    for (size_t i = 0; i < ctx->cache_count; i++) {
        if (ctx->cache[i].status != CYXCHAT_PRESENCE_OFFLINE) {
            if (now_ms - ctx->cache[i].updated_at > CYXCHAT_PRESENCE_STALE_MS) {
                ctx->cache[i].status = CYXCHAT_PRESENCE_OFFLINE;
                ctx->cache[i].last_seen = ctx->cache[i].updated_at;
                events++;
            }
        }
    }

    return events;
}

/* ============================================================
 * Status Management
 * ============================================================ */

cyxchat_error_t cyxchat_presence_set_status(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_presence_t status,
    const char *status_text
) {
    if (!ctx) {
        return CYXCHAT_ERR_NULL;
    }

    ctx->our_status = status;
    ctx->auto_away_active = 0;

    memset(ctx->our_status_text, 0, CYXCHAT_MAX_STATUS_LEN);
    if (status_text) {
        strncpy(ctx->our_status_text, status_text, CYXCHAT_MAX_STATUS_LEN - 1);
    }

    /* Broadcast new status */
    return cyxchat_presence_broadcast(ctx);
}

cyxchat_presence_t cyxchat_presence_get_status(cyxchat_presence_ctx_t *ctx) {
    return ctx ? ctx->our_status : CYXCHAT_PRESENCE_OFFLINE;
}

const char* cyxchat_presence_get_status_text(cyxchat_presence_ctx_t *ctx) {
    return ctx ? ctx->our_status_text : "";
}

/* ============================================================
 * Presence Broadcasting
 * ============================================================ */

cyxchat_error_t cyxchat_presence_broadcast(cyxchat_presence_ctx_t *ctx) {
    if (!ctx) {
        return CYXCHAT_ERR_NULL;
    }

    /* Build presence message */
    cyxchat_presence_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_PRESENCE;
    msg.header.timestamp = cyxchat_timestamp_ms();
    cyxchat_generate_msg_id(&msg.header.msg_id);

    msg.status = (uint8_t)ctx->our_status;
    size_t len = strlen(ctx->our_status_text);
    if (len > CYXCHAT_MAX_STATUS_LEN - 1) {
        len = CYXCHAT_MAX_STATUS_LEN - 1;
    }
    msg.status_len = (uint8_t)len;
    memcpy(msg.status_text, ctx->our_status_text, len);

    /* TODO: Send to all contacts via onion */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_presence_send_to(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *to
) {
    if (!ctx || !to) {
        return CYXCHAT_ERR_NULL;
    }

    /* Build presence message */
    cyxchat_presence_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_PRESENCE;
    msg.header.timestamp = cyxchat_timestamp_ms();
    cyxchat_generate_msg_id(&msg.header.msg_id);

    msg.status = (uint8_t)ctx->our_status;
    size_t len = strlen(ctx->our_status_text);
    if (len > CYXCHAT_MAX_STATUS_LEN - 1) {
        len = CYXCHAT_MAX_STATUS_LEN - 1;
    }
    msg.status_len = (uint8_t)len;
    memcpy(msg.status_text, ctx->our_status_text, len);

    /* TODO: Send via onion to specific peer */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_presence_request(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *from
) {
    if (!ctx || !from) {
        return CYXCHAT_ERR_NULL;
    }

    /* Build presence request message */
    cyxchat_presence_req_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_PRESENCE_REQ;
    msg.header.timestamp = cyxchat_timestamp_ms();
    cyxchat_generate_msg_id(&msg.header.msg_id);

    /* TODO: Send via onion */

    return CYXCHAT_OK;
}

/* ============================================================
 * Presence Queries
 * ============================================================ */

cyxchat_presence_info_t* cyxchat_presence_find(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
) {
    if (!ctx || !node_id) {
        return NULL;
    }
    return find_presence(ctx, node_id);
}

cyxchat_presence_t cyxchat_presence_get(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
) {
    cyxchat_presence_info_t *info = cyxchat_presence_find(ctx, node_id);
    return info ? info->status : CYXCHAT_PRESENCE_OFFLINE;
}

int cyxchat_presence_is_online(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
) {
    cyxchat_presence_t status = cyxchat_presence_get(ctx, node_id);
    return status != CYXCHAT_PRESENCE_OFFLINE;
}

uint64_t cyxchat_presence_last_seen(
    cyxchat_presence_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
) {
    cyxchat_presence_info_t *info = cyxchat_presence_find(ctx, node_id);
    return info ? info->last_seen : 0;
}

/* ============================================================
 * Auto-Away
 * ============================================================ */

void cyxchat_presence_set_auto_away(
    cyxchat_presence_ctx_t *ctx,
    uint64_t timeout_ms
) {
    if (ctx) {
        ctx->auto_away_timeout = timeout_ms;
        ctx->last_activity = cyxchat_timestamp_ms();
        ctx->auto_away_active = 0;
    }
}

void cyxchat_presence_activity(cyxchat_presence_ctx_t *ctx) {
    if (ctx) {
        ctx->last_activity = cyxchat_timestamp_ms();

        /* Return from auto-away */
        if (ctx->auto_away_active) {
            ctx->auto_away_active = 0;
            ctx->our_status = ctx->status_before_away;
            cyxchat_presence_broadcast(ctx);
        }
    }
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_presence_set_on_update(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_on_presence_update_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_update = callback;
        ctx->on_update_data = user_data;
    }
}

void cyxchat_presence_set_on_request(
    cyxchat_presence_ctx_t *ctx,
    cyxchat_on_presence_request_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_request = callback;
        ctx->on_request_data = user_data;
    }
}

/* ============================================================
 * Utilities
 * ============================================================ */

const char* cyxchat_presence_status_name(cyxchat_presence_t status) {
    switch (status) {
        case CYXCHAT_PRESENCE_OFFLINE:   return "Offline";
        case CYXCHAT_PRESENCE_ONLINE:    return "Online";
        case CYXCHAT_PRESENCE_AWAY:      return "Away";
        case CYXCHAT_PRESENCE_BUSY:      return "Busy";
        case CYXCHAT_PRESENCE_INVISIBLE: return "Invisible";
        default:                          return "Unknown";
    }
}

void cyxchat_presence_format_last_seen(
    uint64_t last_seen_ms,
    uint64_t now_ms,
    char *out,
    size_t out_len
) {
    if (!out || out_len < 32) return;

    if (last_seen_ms == 0) {
        snprintf(out, out_len, "Never");
        return;
    }

    uint64_t diff = now_ms - last_seen_ms;
    uint64_t seconds = diff / 1000;
    uint64_t minutes = seconds / 60;
    uint64_t hours = minutes / 60;
    uint64_t days = hours / 24;

    if (seconds < 60) {
        snprintf(out, out_len, "Just now");
    } else if (minutes < 60) {
        snprintf(out, out_len, "%llu min ago", (unsigned long long)minutes);
    } else if (hours < 24) {
        snprintf(out, out_len, "%llu hr ago", (unsigned long long)hours);
    } else if (days < 7) {
        snprintf(out, out_len, "%llu days ago", (unsigned long long)days);
    } else {
        snprintf(out, out_len, "Long time ago");
    }
}

