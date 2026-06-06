/**
 * CyxChat Group Chat Implementation
 */

#include <cyxchat/group.h>
#include <cyxchat/chat.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/memory.h>
#include <cyxwiz/onion.h>
#include <cyxwiz/log.h>
#include <sodium.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <inttypes.h>

/* ============================================================
 * Constants
 * ============================================================ */

#define CYXCHAT_MAX_GROUPS 32

/* Wire format constants for group messages */
#define GROUP_WIRE_MAX_PAYLOAD    200   /* Max payload after encryption overhead */
#define GROUP_MAX_ENCRYPTED_TEXT  120   /* Max text per packet after encryption */
#define GROUP_MEDIA_INLINE_MAX    512   /* Small inline payloads; larger media stays metadata-only */
#define GROUP_MEDIA_CHUNK_DATA_MAX CYXCHAT_CHUNK_SIZE
#define GROUP_MEDIA_MAX_TRANSFERS 4
#define GROUP_MEDIA_CHUNK_INTERVAL_MS 250
#define GROUP_MEDIA_RX_STALL_MS 3000
#define GROUP_MEDIA_RX_REQUEST_INTERVAL_MS 5000
#define GROUP_MEDIA_RX_MAX_REQUESTS 5
#define GROUP_MEDIA_TX_RETAIN_MS 120000
#define GROUP_MEDIA_CHUNK_ACK_WIRE_SIZE 71
#define GROUP_MEDIA_ACK_METADATA 0
#define GROUP_MEDIA_ACK_CHUNK_REQUEST 1
#define GROUP_MEDIA_ACK_COMPLETE 2
#define GROUP_MEDIA_MAX_PLAINTEXT \
    (CYXCHAT_FILE_ID_SIZE + 1 + 8 + 4 + 2 + 2 + 4 + 8 + 1 + 1 + CYXCHAT_MAX_FILENAME + CYXCHAT_MAX_MIME_TYPE + 4 + GROUP_MEDIA_INLINE_MAX)
#define GROUP_MEDIA_CHUNK_WIRE_MAX \
    (72 + GROUP_MEDIA_CHUNK_DATA_MAX + CYXCHAT_CRYPTO_OVERHEAD)

/* Crypto overhead: nonce(24) + auth_tag(16) = 40 bytes */
#define CYXCHAT_CRYPTO_OVERHEAD   40

/* Encrypted group key size: nonce(24) + key(32) + tag(16) = 72 bytes */
#define CYXCHAT_ENCRYPTED_KEY_SIZE  72

/* Key derivation domain separation */
#define CYXCHAT_GROUP_KEY_DOMAIN "CYXCHAT_GROUP_KEY_V1"

/* Key distribution constants */
#define CYXCHAT_MAX_KEY_DIST_JOBS     4       /* Max concurrent key distributions */
#define CYXCHAT_KEY_DIST_TIMEOUT_MS   60000   /* 60 second timeout */
#define CYXCHAT_KEY_SEND_INTERVAL_MS  100     /* 100ms between sends (10/sec rate limit) */
#define CYXCHAT_KEY_ACK_RETRY_MS      5000    /* Retry unacked after 5 seconds */
#define CYXCHAT_KEY_MAX_RETRIES       3       /* Max retries per member */

/* ============================================================
 * Key Distribution State Machine
 * ============================================================ */

typedef enum {
    KEY_DIST_IDLE = 0,
    KEY_DIST_SENDING,       /* Sending encrypted keys to members */
    KEY_DIST_AWAITING_ACKS, /* Waiting for ACKs */
    KEY_DIST_COMPLETE,      /* All members confirmed */
    KEY_DIST_FAILED         /* Timeout/too many failures */
} cyxchat_key_dist_state_t;

/* Tracking per member during distribution */
typedef struct {
    cyxwiz_node_id_t node_id;
    uint8_t public_key[32];
    uint64_t sent_at;           /* When key was sent (0 = not sent) */
    uint8_t ack_received;       /* 1 = ACK received */
    uint8_t retry_count;        /* Number of retries */
} cyxchat_key_dist_member_t;

/* Key distribution job */
typedef struct {
    cyxchat_group_id_t group_id;
    uint32_t key_version;
    uint8_t new_key[32];

    cyxchat_key_dist_state_t state;

    /* Distribution tracking */
    cyxchat_key_dist_member_t *members;   /* Members to distribute to */
    size_t member_count;
    size_t current_index;                  /* Next member to send to */
    size_t acked_count;                    /* Members who ACKed */

    /* Timing */
    uint64_t started_at;
    uint64_t last_send_ms;
    uint64_t last_retry_check_ms;

    int active;  /* 1 = job is active */
} cyxchat_key_dist_job_t;

/* ============================================================
 * Internal Structures
 * ============================================================ */

/* Forward declaration for key distribution completion callback */
typedef void (*cyxchat_on_key_dist_complete_t)(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint32_t new_version,
    int success,
    size_t failed_count,
    void *user_data
);

/* ============================================================
 * Pending Group Message Tracking (Retransmission)
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t member_id;
    uint64_t sent_at_ms;
    uint8_t retry_count;
    int acked;
} cyxchat_group_msg_member_track_t;

typedef struct {
    cyxchat_msg_id_t msg_id;
    cyxchat_group_id_t group_id;
    uint8_t *wire_data;
    size_t wire_len;
    cyxchat_group_msg_member_track_t members[CYXCHAT_MAX_GROUP_MEMBERS];
    size_t member_count;
    int active;
} cyxchat_pending_group_msg_t;

typedef struct {
    cyxchat_group_media_t media;
    uint8_t *data;
    uint8_t *chunk_bitmap;
    uint32_t chunk_count;
    uint32_t chunks_received;
    uint64_t updated_at_ms;
    uint64_t last_request_ms;
    uint8_t request_count;
    int active;
} cyxchat_group_media_rx_t;

typedef struct {
    cyxchat_group_media_t media;
    uint8_t *data;
    size_t data_len;
    uint32_t chunk_count;
    uint32_t next_chunk;
    uint32_t key_version;
    uint8_t group_key[32];
    uint64_t last_send_ms;
    uint64_t completed_at_ms;
    int active;
} cyxchat_group_media_tx_t;

struct cyxchat_group_ctx {
    cyxchat_ctx_t *chat_ctx;
    cyxwiz_node_id_t local_id;

    /* Groups */
    cyxchat_group_t groups[CYXCHAT_MAX_GROUPS];
    size_t group_count;

    /* Key distribution jobs */
    cyxchat_key_dist_job_t key_dist_jobs[CYXCHAT_MAX_KEY_DIST_JOBS];

    /* Auto-rotation settings */
    int auto_rotate_on_leave;    /* Rotate key when member leaves (default: 1) */
    int auto_rotate_on_kick;     /* Rotate key when receiving kick notification (default: 0) */

    /* Callbacks */
    cyxchat_on_group_message_t on_message;
    void *on_message_data;

    cyxchat_on_group_media_t on_media;
    void *on_media_data;

    cyxchat_on_group_invite_t on_invite;
    void *on_invite_data;

    cyxchat_on_member_join_t on_member_join;
    void *on_member_join_data;

    cyxchat_on_member_leave_t on_member_leave;
    void *on_member_leave_data;

    cyxchat_on_group_key_update_t on_key_update;
    void *on_key_update_data;

    cyxchat_on_key_dist_complete_t on_key_dist_complete;
    void *on_key_dist_complete_data;

    /* Admin action callback (Phase 1) */
    cyxchat_on_admin_action_t on_admin_action;
    void *on_admin_action_data;

    /* Message action callbacks (Phase 2) */
    cyxchat_on_message_edit_t on_message_edit;
    void *on_message_edit_data;

    cyxchat_on_message_delete_t on_message_delete;
    void *on_message_delete_data;

    cyxchat_on_message_pin_t on_message_pin;
    void *on_message_pin_data;

    /* Pinned messages storage (per group, up to MAX_PINNED) */
    struct {
        cyxchat_group_id_t group_id;
        cyxchat_msg_id_t msg_ids[CYXCHAT_MAX_PINNED_MESSAGES];
        size_t count;
    } pinned_messages[CYXCHAT_MAX_GROUPS];

    /* Invite link callbacks (Phase 3) */
    cyxchat_on_invite_link_t on_invite_link;
    void *on_invite_link_data;

    cyxchat_on_join_via_link_t on_join_via_link;
    void *on_join_via_link_data;

    /* Invite links storage (per group, up to MAX_INVITE_LINKS) */
    struct {
        cyxchat_group_id_t group_id;
        cyxchat_invite_link_t links[CYXCHAT_MAX_INVITE_LINKS];
        size_t count;
    } invite_links[CYXCHAT_MAX_GROUPS];

    /* Admin action log storage (Phase 4) */
    struct {
        cyxchat_group_id_t group_id;
        cyxchat_admin_action_t actions[CYXCHAT_MAX_ADMIN_ACTIONS];
        size_t count;
        size_t write_index;  /* Circular buffer write position */
    } admin_actions[CYXCHAT_MAX_GROUPS];

    /* Pending group message queue (retransmission) */
    cyxchat_pending_group_msg_t pending_group_msgs[CYXCHAT_MAX_PENDING_GROUP_MSGS];

    /* Group media chunk transfer queues */
    cyxchat_group_media_rx_t media_rx[GROUP_MEDIA_MAX_TRANSFERS];
    cyxchat_group_media_tx_t media_tx[GROUP_MEDIA_MAX_TRANSFERS];

    /* Delivery failure callback */
    cyxchat_on_group_delivery_failed_t on_delivery_failed;
    void *on_delivery_failed_data;

    /* Delivery success callback */
    cyxchat_on_group_delivery_t on_delivery;
    void *on_delivery_data;
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
 * Pending Group Message Helpers (Retransmission)
 * ============================================================ */

static cyxchat_pending_group_msg_t* pending_grp_find_slot(cyxchat_group_ctx_t *ctx) {
    for (int i = 0; i < CYXCHAT_MAX_PENDING_GROUP_MSGS; i++) {
        if (!ctx->pending_group_msgs[i].active) {
            return &ctx->pending_group_msgs[i];
        }
    }
    return NULL;
}

static cyxchat_pending_group_msg_t* pending_grp_find_by_msg_id(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_msg_id_t *msg_id
) {
    for (int i = 0; i < CYXCHAT_MAX_PENDING_GROUP_MSGS; i++) {
        if (ctx->pending_group_msgs[i].active &&
            memcmp(ctx->pending_group_msgs[i].msg_id.bytes, msg_id->bytes,
                   CYXCHAT_MSG_ID_SIZE) == 0) {
            return &ctx->pending_group_msgs[i];
        }
    }
    return NULL;
}

static void pending_grp_free(cyxchat_pending_group_msg_t *slot) {
    if (slot->wire_data) {
        free(slot->wire_data);
        slot->wire_data = NULL;
    }
    slot->active = 0;
}

static void pending_grp_free_all(cyxchat_group_ctx_t *ctx) {
    for (int i = 0; i < CYXCHAT_MAX_PENDING_GROUP_MSGS; i++) {
        if (ctx->pending_group_msgs[i].active) {
            pending_grp_free(&ctx->pending_group_msgs[i]);
        }
    }
}

static void media_rx_free(cyxchat_group_media_rx_t *slot) {
    if (!slot) return;
    free(slot->data);
    free(slot->chunk_bitmap);
    memset(slot, 0, sizeof(*slot));
}

static void media_tx_free(cyxchat_group_media_tx_t *slot) {
    if (!slot) return;
    free(slot->data);
    cyxwiz_secure_zero(slot->group_key, sizeof(slot->group_key));
    memset(slot, 0, sizeof(*slot));
}

static void media_transfer_free_all(cyxchat_group_ctx_t *ctx) {
    for (int i = 0; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        if (ctx->media_rx[i].active) {
            media_rx_free(&ctx->media_rx[i]);
        }
        if (ctx->media_tx[i].active) {
            media_tx_free(&ctx->media_tx[i]);
        }
    }
}

static cyxchat_group_media_rx_t* media_rx_find(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *sender_id,
    const uint8_t file_id[CYXCHAT_FILE_ID_SIZE]
) {
    for (int i = 0; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        cyxchat_group_media_rx_t *slot = &ctx->media_rx[i];
        if (slot->active &&
            memcmp(slot->media.group_id, group_id->bytes, CYXCHAT_GROUP_ID_SIZE) == 0 &&
            memcmp(slot->media.sender_id, sender_id->bytes, CYXCHAT_NODE_ID_SIZE) == 0 &&
            memcmp(slot->media.file_id, file_id, CYXCHAT_FILE_ID_SIZE) == 0) {
            return slot;
        }
    }
    return NULL;
}

static cyxchat_group_media_rx_t* media_rx_alloc(cyxchat_group_ctx_t *ctx) {
    for (int i = 0; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        if (!ctx->media_rx[i].active) {
            return &ctx->media_rx[i];
        }
    }

    size_t oldest = 0;
    for (int i = 1; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        if (ctx->media_rx[i].updated_at_ms < ctx->media_rx[oldest].updated_at_ms) {
            oldest = (size_t)i;
        }
    }
    CYXWIZ_WARN("Group media receive queue full; dropping oldest incomplete transfer");
    media_rx_free(&ctx->media_rx[oldest]);
    return &ctx->media_rx[oldest];
}

static int media_chunk_seen(const cyxchat_group_media_rx_t *slot, uint32_t idx) {
    return (slot->chunk_bitmap[idx / 8] >> (idx % 8)) & 1;
}

static void media_mark_chunk_seen(cyxchat_group_media_rx_t *slot, uint32_t idx) {
    slot->chunk_bitmap[idx / 8] |= (uint8_t)(1U << (idx % 8));
}

static void write_u32_be(uint8_t *out, size_t *offset, uint32_t value);

static uint32_t media_first_missing_chunk(const cyxchat_group_media_rx_t *slot) {
    for (uint32_t i = 0; i < slot->chunk_count; i++) {
        if (!media_chunk_seen(slot, i)) {
            return i;
        }
    }
    return slot->chunk_count;
}

static cyxchat_group_media_tx_t* media_tx_find(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_group_id_t *group_id,
    const uint8_t file_id[CYXCHAT_FILE_ID_SIZE]
) {
    for (int i = 0; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        cyxchat_group_media_tx_t *slot = &ctx->media_tx[i];
        if (slot->active &&
            memcmp(slot->media.msg_id, msg_id->bytes, CYXCHAT_MSG_ID_SIZE) == 0 &&
            memcmp(slot->media.group_id, group_id->bytes, CYXCHAT_GROUP_ID_SIZE) == 0 &&
            memcmp(slot->media.file_id, file_id, CYXCHAT_FILE_ID_SIZE) == 0) {
            return slot;
        }
    }
    return NULL;
}

static void media_rx_send_ack(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_media_rx_t *slot,
    uint8_t status,
    uint32_t chunk_index
) {
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) return;

    cyxwiz_node_id_t sender_id;
    memcpy(sender_id.bytes, slot->media.sender_id, CYXCHAT_NODE_ID_SIZE);

    uint8_t ack_buf[GROUP_MEDIA_CHUNK_ACK_WIRE_SIZE];
    size_t ack_len = 0;
    ack_buf[ack_len++] = CYXCHAT_MSG_GROUP_FILE_ACK;
    ack_buf[ack_len++] = 0;
    memcpy(ack_buf + ack_len, slot->media.msg_id, CYXCHAT_MSG_ID_SIZE);
    ack_len += CYXCHAT_MSG_ID_SIZE;
    memcpy(ack_buf + ack_len, ctx->local_id.bytes, CYXCHAT_NODE_ID_SIZE);
    ack_len += CYXCHAT_NODE_ID_SIZE;
    memcpy(ack_buf + ack_len, slot->media.group_id, CYXCHAT_GROUP_ID_SIZE);
    ack_len += CYXCHAT_GROUP_ID_SIZE;
    memcpy(ack_buf + ack_len, slot->media.file_id, CYXCHAT_FILE_ID_SIZE);
    ack_len += CYXCHAT_FILE_ID_SIZE;
    ack_buf[ack_len++] = status;
    write_u32_be(ack_buf, &ack_len, chunk_index);
    write_u32_be(ack_buf, &ack_len, slot->chunks_received);
    write_u32_be(ack_buf, &ack_len, slot->chunk_count);

    cyxwiz_onion_send_to(onion, &sender_id, ack_buf, ack_len);
}

static cyxchat_error_t media_rx_prepare(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_media_t *media,
    uint64_t now_ms
) {
    if (media->file_size == 0 || media->file_size > CYXCHAT_MAX_MEDIA_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    cyxchat_group_id_t group_id;
    cyxwiz_node_id_t sender_id;
    memcpy(group_id.bytes, media->group_id, CYXCHAT_GROUP_ID_SIZE);
    memcpy(sender_id.bytes, media->sender_id, CYXCHAT_NODE_ID_SIZE);

    uint32_t chunk_count = (uint32_t)(
        (media->file_size + GROUP_MEDIA_CHUNK_DATA_MAX - 1) / GROUP_MEDIA_CHUNK_DATA_MAX
    );
    cyxchat_group_media_rx_t *slot = media_rx_find(ctx, &group_id, &sender_id, media->file_id);
    if (slot) {
        slot->media = *media;
        slot->updated_at_ms = now_ms;
        return CYXCHAT_OK;
    }

    slot = media_rx_alloc(ctx);
    size_t bitmap_size = (chunk_count + 7) / 8;
    slot->data = (uint8_t *)malloc((size_t)media->file_size);
    slot->chunk_bitmap = (uint8_t *)calloc(1, bitmap_size);
    if (!slot->data || !slot->chunk_bitmap) {
        media_rx_free(slot);
        return CYXCHAT_ERR_MEMORY;
    }

    slot->media = *media;
    slot->chunk_count = chunk_count;
    slot->chunks_received = 0;
    slot->updated_at_ms = now_ms;
    slot->active = 1;
    return CYXCHAT_OK;
}

static cyxchat_group_media_tx_t* media_tx_alloc(cyxchat_group_ctx_t *ctx) {
    for (int i = 0; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        if (!ctx->media_tx[i].active) {
            return &ctx->media_tx[i];
        }
    }
    return NULL;
}

static cyxchat_error_t media_tx_start(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_t *group,
    const cyxchat_group_media_t *media,
    const uint8_t *data,
    size_t data_len,
    cyxchat_group_media_tx_t **slot_out
) {
    if (slot_out) *slot_out = NULL;
    if (!data || data_len == 0 || data_len > CYXCHAT_MAX_MEDIA_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    uint32_t chunk_count = (uint32_t)(
        (data_len + GROUP_MEDIA_CHUNK_DATA_MAX - 1) / GROUP_MEDIA_CHUNK_DATA_MAX
    );
    cyxchat_group_media_tx_t *slot = media_tx_alloc(ctx);
    if (!slot) {
        return CYXCHAT_ERR_FULL;
    }

    slot->data = (uint8_t *)malloc(data_len);
    if (!slot->data) {
        media_tx_free(slot);
        return CYXCHAT_ERR_MEMORY;
    }

    memcpy(slot->data, data, data_len);
    slot->media = *media;
    slot->data_len = data_len;
    slot->chunk_count = chunk_count;
    slot->next_chunk = 0;
    slot->key_version = group->key_version;
    memcpy(slot->group_key, group->group_key, sizeof(slot->group_key));
    slot->last_send_ms = 0;
    slot->active = 1;
    if (slot_out) *slot_out = slot;
    return CYXCHAT_OK;
}

static void pending_grp_track(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_group_id_t *group_id,
    const uint8_t *wire_data,
    size_t wire_len,
    const cyxchat_group_t *group,
    uint64_t now_ms
) {
    cyxchat_pending_group_msg_t *slot = pending_grp_find_slot(ctx);
    if (!slot) {
        CYXWIZ_WARN("Pending group message queue full, sent without retry tracking");
        return;
    }

    slot->wire_data = (uint8_t *)malloc(wire_len);
    if (!slot->wire_data) {
        CYXWIZ_WARN("Failed to allocate pending group message buffer");
        slot->active = 0;  /* Ensure slot is not left in active state */
        return;
    }

    memcpy(&slot->msg_id, msg_id, sizeof(cyxchat_msg_id_t));
    memcpy(&slot->group_id, group_id, sizeof(cyxchat_group_id_t));
    memcpy(slot->wire_data, wire_data, wire_len);
    slot->wire_len = wire_len;
    slot->member_count = 0;
    slot->active = 1;

    /* Track each member (skip self) */
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(&group->members[i].node_id, &ctx->local_id, 32) == 0) {
            continue;
        }
        cyxchat_group_msg_member_track_t *mt = &slot->members[slot->member_count++];
        memcpy(&mt->member_id, &group->members[i].node_id, sizeof(cyxwiz_node_id_t));
        mt->sent_at_ms = now_ms;
        mt->retry_count = 0;
        mt->acked = 0;
    }
}

static void pending_grp_check_timeouts(cyxchat_group_ctx_t *ctx, uint64_t now_ms) {
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) return;

    for (int i = 0; i < CYXCHAT_MAX_PENDING_GROUP_MSGS; i++) {
        cyxchat_pending_group_msg_t *slot = &ctx->pending_group_msgs[i];
        if (!slot->active) continue;

        int all_done = 1;
        for (size_t m = 0; m < slot->member_count; m++) {
            cyxchat_group_msg_member_track_t *mt = &slot->members[m];
            if (mt->acked) continue;

            if (now_ms - mt->sent_at_ms < CYXCHAT_GROUP_MSG_ACK_TIMEOUT_MS) {
                all_done = 0;
                continue;
            }

            if (mt->retry_count < CYXCHAT_GROUP_MSG_MAX_RETRIES) {
                mt->retry_count++;
                mt->sent_at_ms = now_ms;
                all_done = 0;

                CYXWIZ_INFO("Retransmitting group message to member (retry %u/%u)",
                            mt->retry_count, CYXCHAT_GROUP_MSG_MAX_RETRIES);

                cyxwiz_onion_send_to(onion, &mt->member_id,
                                     slot->wire_data, slot->wire_len);
            }
            /* else: max retries exhausted for this member, leave acked=0 */
        }

        if (!all_done) continue;

        /* All members either acked or exhausted retries */
        /* Collect failed members */
        cyxwiz_node_id_t failed[CYXCHAT_MAX_GROUP_MEMBERS];
        size_t failed_count = 0;

        for (size_t m = 0; m < slot->member_count; m++) {
            if (!slot->members[m].acked) {
                memcpy(&failed[failed_count++], &slot->members[m].member_id,
                       sizeof(cyxwiz_node_id_t));
            }
        }

        if (failed_count > 0) {
            if (ctx->on_delivery_failed) {
                CYXWIZ_WARN("Group message delivery failed for %zu members", failed_count);
                ctx->on_delivery_failed(ctx, &slot->group_id, &slot->msg_id,
                                        failed, failed_count,
                                        ctx->on_delivery_failed_data);
            }
        } else if (ctx->on_delivery) {
            ctx->on_delivery(ctx, &slot->group_id, &slot->msg_id,
                             slot->member_count, slot->member_count,
                             ctx->on_delivery_data);
        }

        pending_grp_free(slot);
    }
}

static size_t bounded_cstr_len(const char *s, size_t max_len) {
    size_t len = 0;
    if (!s) return 0;
    while (len < max_len && s[len] != '\0') {
        len++;
    }
    return len;
}

static void write_u16_be(uint8_t *out, size_t *offset, uint16_t value) {
    out[(*offset)++] = (uint8_t)((value >> 8) & 0xFF);
    out[(*offset)++] = (uint8_t)(value & 0xFF);
}

static void write_u32_be(uint8_t *out, size_t *offset, uint32_t value) {
    out[(*offset)++] = (uint8_t)((value >> 24) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 16) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 8) & 0xFF);
    out[(*offset)++] = (uint8_t)(value & 0xFF);
}

static void write_u64_be(uint8_t *out, size_t *offset, uint64_t value) {
    out[(*offset)++] = (uint8_t)((value >> 56) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 48) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 40) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 32) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 24) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 16) & 0xFF);
    out[(*offset)++] = (uint8_t)((value >> 8) & 0xFF);
    out[(*offset)++] = (uint8_t)(value & 0xFF);
}

static uint16_t read_u16_be(const uint8_t *in, size_t *offset) {
    uint16_t value = ((uint16_t)in[*offset] << 8) |
                     (uint16_t)in[*offset + 1];
    *offset += 2;
    return value;
}

static uint32_t read_u32_be(const uint8_t *in, size_t *offset) {
    uint32_t value = ((uint32_t)in[*offset] << 24) |
                     ((uint32_t)in[*offset + 1] << 16) |
                     ((uint32_t)in[*offset + 2] << 8) |
                     (uint32_t)in[*offset + 3];
    *offset += 4;
    return value;
}

static uint64_t read_u64_be(const uint8_t *in, size_t *offset) {
    uint64_t value = ((uint64_t)in[*offset] << 56) |
                     ((uint64_t)in[*offset + 1] << 48) |
                     ((uint64_t)in[*offset + 2] << 40) |
                     ((uint64_t)in[*offset + 3] << 32) |
                     ((uint64_t)in[*offset + 4] << 24) |
                     ((uint64_t)in[*offset + 5] << 16) |
                     ((uint64_t)in[*offset + 6] << 8) |
                     (uint64_t)in[*offset + 7];
    *offset += 8;
    return value;
}

/* ============================================================
 * Wire Format Serialization
 * ============================================================
 *
 * GROUP_TEXT wire format:
 *   +0:  type (1 byte) = 0x20
 *   +1:  flags (1 byte)
 *   +2:  msg_id (8 bytes)
 *  +10:  sender_id (32 bytes)
 *  +42:  group_id (8 bytes)
 *  +50:  key_version (4 bytes, big-endian)
 *  +54:  encrypted_len (2 bytes, little-endian)
 *  +56:  encrypted_payload (N bytes)
 *        Encrypted content: text_len(2) + text(N) + [reply_to(8) if flagged]
 */

static size_t serialize_group_text(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    uint16_t flags,
    const cyxchat_group_id_t *group_id,
    uint32_t key_version,
    const uint8_t *encrypted,
    size_t encrypted_len,
    const cyxwiz_node_id_t *sender_id
) {
    size_t required = 56 + encrypted_len;
    if (out_size < required) return 0;

    size_t offset = 0;

    /* Type */
    out[offset++] = CYXCHAT_MSG_GROUP_TEXT;

    /* Flags */
    out[offset++] = (uint8_t)(flags & 0xFF);

    /* Message ID */
    memcpy(out + offset, msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    /* Sender ID */
    memcpy(out + offset, sender_id->bytes, 32);
    offset += 32;

    /* Group ID */
    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Key version (big-endian) */
    out[offset++] = (key_version >> 24) & 0xFF;
    out[offset++] = (key_version >> 16) & 0xFF;
    out[offset++] = (key_version >> 8) & 0xFF;
    out[offset++] = key_version & 0xFF;

    /* Encrypted length (little-endian) */
    out[offset++] = encrypted_len & 0xFF;
    out[offset++] = (encrypted_len >> 8) & 0xFF;

    /* Encrypted payload */
    memcpy(out + offset, encrypted, encrypted_len);
    offset += encrypted_len;

    return offset;
}

static size_t deserialize_group_text(
    const uint8_t *in,
    size_t len,
    uint8_t *type_out,
    uint16_t *flags_out,
    cyxchat_msg_id_t *msg_id_out,
    cyxwiz_node_id_t *sender_id_out,
    cyxchat_group_id_t *group_id_out,
    uint32_t *key_version_out,
    const uint8_t **encrypted_out,
    size_t *encrypted_len_out
) {
    if (len < 56) return 0;  /* Minimum header size */

    size_t offset = 0;

    /* Type */
    *type_out = in[offset++];

    /* Flags */
    *flags_out = in[offset++];

    /* Message ID */
    memcpy(msg_id_out->bytes, in + offset, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    /* Sender ID */
    memcpy(sender_id_out->bytes, in + offset, 32);
    offset += 32;

    /* Group ID */
    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Key version (big-endian) */
    *key_version_out = ((uint32_t)in[offset] << 24) |
                       ((uint32_t)in[offset + 1] << 16) |
                       ((uint32_t)in[offset + 2] << 8) |
                       (uint32_t)in[offset + 3];
    offset += 4;

    /* Encrypted length (little-endian) */
    size_t enc_len = in[offset] | ((size_t)in[offset + 1] << 8);
    offset += 2;

    if (enc_len > CYXCHAT_MAX_TEXT_LEN + 40) return 0;  /* Sanity: text + crypto overhead */
    if (len < offset + enc_len) return 0;  /* Truncated */

    *encrypted_out = in + offset;
    *encrypted_len_out = enc_len;

    return offset + enc_len;
}

static size_t serialize_group_media(
    uint8_t *out,
    size_t out_size,
    uint8_t type,
    const cyxchat_msg_id_t *msg_id,
    uint16_t flags,
    const cyxchat_group_id_t *group_id,
    uint32_t key_version,
    const uint8_t *encrypted,
    size_t encrypted_len,
    const cyxwiz_node_id_t *sender_id
) {
    size_t required = 56 + encrypted_len;
    if (out_size < required) return 0;

    size_t offset = 0;
    out[offset++] = type;
    out[offset++] = (uint8_t)(flags & 0xFF);
    memcpy(out + offset, msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;
    memcpy(out + offset, sender_id->bytes, 32);
    offset += 32;
    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    write_u32_be(out, &offset, key_version);
    out[offset++] = encrypted_len & 0xFF;
    out[offset++] = (encrypted_len >> 8) & 0xFF;
    memcpy(out + offset, encrypted, encrypted_len);
    offset += encrypted_len;

    return offset;
}

static size_t deserialize_group_media(
    const uint8_t *in,
    size_t len,
    uint8_t *type_out,
    uint16_t *flags_out,
    cyxchat_msg_id_t *msg_id_out,
    cyxwiz_node_id_t *sender_id_out,
    cyxchat_group_id_t *group_id_out,
    uint32_t *key_version_out,
    const uint8_t **encrypted_out,
    size_t *encrypted_len_out
) {
    if (len < 56) return 0;

    size_t offset = 0;
    *type_out = in[offset++];
    *flags_out = in[offset++];
    memcpy(msg_id_out->bytes, in + offset, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;
    memcpy(sender_id_out->bytes, in + offset, 32);
    offset += 32;
    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    *key_version_out = read_u32_be(in, &offset);

    size_t enc_len = in[offset] | ((size_t)in[offset + 1] << 8);
    offset += 2;

    if (enc_len > GROUP_MEDIA_MAX_PLAINTEXT + CYXCHAT_CRYPTO_OVERHEAD) return 0;
    if (len < offset + enc_len) return 0;

    *encrypted_out = in + offset;
    *encrypted_len_out = enc_len;

    return offset + enc_len;
}

static size_t serialize_group_media_chunk(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *sender_id,
    uint32_t key_version,
    const uint8_t file_id[CYXCHAT_FILE_ID_SIZE],
    uint32_t chunk_index,
    uint32_t chunk_count,
    const uint8_t *encrypted,
    size_t encrypted_len
) {
    size_t required = 72 + encrypted_len;
    if (out_size < required || encrypted_len > UINT16_MAX) return 0;

    size_t offset = 0;
    out[offset++] = CYXCHAT_MSG_GROUP_FILE_CHUNK;
    out[offset++] = CYXCHAT_FLAG_ENCRYPTED;
    memcpy(out + offset, msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;
    memcpy(out + offset, sender_id->bytes, CYXCHAT_NODE_ID_SIZE);
    offset += CYXCHAT_NODE_ID_SIZE;
    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    write_u32_be(out, &offset, key_version);
    memcpy(out + offset, file_id, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;
    write_u32_be(out, &offset, chunk_index);
    write_u32_be(out, &offset, chunk_count);
    write_u16_be(out, &offset, (uint16_t)encrypted_len);
    memcpy(out + offset, encrypted, encrypted_len);
    offset += encrypted_len;
    return offset;
}

static size_t deserialize_group_media_chunk(
    const uint8_t *in,
    size_t len,
    cyxchat_msg_id_t *msg_id_out,
    cyxwiz_node_id_t *sender_id_out,
    cyxchat_group_id_t *group_id_out,
    uint32_t *key_version_out,
    uint8_t file_id_out[CYXCHAT_FILE_ID_SIZE],
    uint32_t *chunk_index_out,
    uint32_t *chunk_count_out,
    const uint8_t **encrypted_out,
    size_t *encrypted_len_out
) {
    if (len < 72) return 0;

    size_t offset = 0;
    if (in[offset++] != CYXCHAT_MSG_GROUP_FILE_CHUNK) return 0;
    offset++;  /* flags */
    memcpy(msg_id_out->bytes, in + offset, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;
    memcpy(sender_id_out->bytes, in + offset, CYXCHAT_NODE_ID_SIZE);
    offset += CYXCHAT_NODE_ID_SIZE;
    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    *key_version_out = read_u32_be(in, &offset);
    memcpy(file_id_out, in + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;
    *chunk_index_out = read_u32_be(in, &offset);
    *chunk_count_out = read_u32_be(in, &offset);
    size_t encrypted_len = read_u16_be(in, &offset);

    if (encrypted_len > GROUP_MEDIA_CHUNK_DATA_MAX + CYXCHAT_CRYPTO_OVERHEAD) return 0;
    if (len < offset + encrypted_len) return 0;

    *encrypted_out = in + offset;
    *encrypted_len_out = encrypted_len;
    return offset + encrypted_len;
}

static size_t serialize_group_media_plaintext(
    uint8_t *out,
    size_t out_size,
    const cyxchat_group_media_t *media,
    const uint8_t *payload,
    size_t payload_len
) {
    size_t filename_len = bounded_cstr_len(media->filename, CYXCHAT_MAX_FILENAME - 1);
    size_t mime_len = bounded_cstr_len(media->mime_type, CYXCHAT_MAX_MIME_TYPE - 1);
    size_t required = CYXCHAT_FILE_ID_SIZE + 1 + 8 + 4 + 2 + 2 + 4 + 8 + 1 + 1 +
                      filename_len + mime_len + 4 + payload_len;

    if (required > out_size || filename_len > 255 || mime_len > 255) return 0;
    if (payload_len > GROUP_MEDIA_INLINE_MAX) return 0;
    if (payload_len > 0 && !payload) return 0;

    size_t offset = 0;
    memcpy(out + offset, media->file_id, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;
    out[offset++] = (uint8_t)media->media_type;
    write_u64_be(out, &offset, media->file_size);
    write_u32_be(out, &offset, media->duration_ms);
    write_u16_be(out, &offset, media->width);
    write_u16_be(out, &offset, media->height);
    write_u32_be(out, &offset, media->thumbnail_size);
    write_u64_be(out, &offset, media->timestamp);
    out[offset++] = (uint8_t)filename_len;
    out[offset++] = (uint8_t)mime_len;
    memcpy(out + offset, media->filename, filename_len);
    offset += filename_len;
    memcpy(out + offset, media->mime_type, mime_len);
    offset += mime_len;
    write_u32_be(out, &offset, (uint32_t)payload_len);
    if (payload_len > 0) {
        memcpy(out + offset, payload, payload_len);
        offset += payload_len;
    }

    return offset;
}

static int deserialize_group_media_plaintext(
    const uint8_t *in,
    size_t len,
    cyxchat_group_media_t *media,
    const uint8_t **payload_out,
    size_t *payload_len_out
) {
    const size_t fixed_len = CYXCHAT_FILE_ID_SIZE + 1 + 8 + 4 + 2 + 2 + 4 + 8 + 1 + 1;
    if (len < fixed_len) return 0;
    if (payload_out) *payload_out = NULL;
    if (payload_len_out) *payload_len_out = 0;

    size_t offset = 0;
    memcpy(media->file_id, in + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;
    media->media_type = (cyxchat_media_type_t)in[offset++];
    media->file_size = read_u64_be(in, &offset);
    media->duration_ms = read_u32_be(in, &offset);
    media->width = read_u16_be(in, &offset);
    media->height = read_u16_be(in, &offset);
    media->thumbnail_size = read_u32_be(in, &offset);
    media->timestamp = read_u64_be(in, &offset);

    size_t filename_len = in[offset++];
    size_t mime_len = in[offset++];
    if (filename_len >= CYXCHAT_MAX_FILENAME || mime_len >= CYXCHAT_MAX_MIME_TYPE) return 0;
    if (len < offset + filename_len + mime_len) return 0;

    if (filename_len > 0) {
        memcpy(media->filename, in + offset, filename_len);
    }
    media->filename[filename_len] = '\0';
    offset += filename_len;

    if (mime_len > 0) {
        memcpy(media->mime_type, in + offset, mime_len);
    }
    media->mime_type[mime_len] = '\0';
    offset += mime_len;

    if (len == offset) {
        return 1;
    }
    if (len < offset + 4) return 0;

    size_t payload_len = read_u32_be(in, &offset);
    if (payload_len > GROUP_MEDIA_INLINE_MAX) return 0;
    if (len < offset + payload_len) return 0;

    if (payload_len > 0 && payload_out) {
        *payload_out = in + offset;
    }
    if (payload_len_out) {
        *payload_len_out = payload_len;
    }

    return 1;
}

static int media_tx_send_next(
    cyxchat_group_ctx_t *ctx,
    cyxchat_group_media_tx_t *slot,
    uint64_t now_ms,
    const cyxwiz_node_id_t *only_member,
    uint32_t requested_chunk
) {
    if (!slot->active) return 0;
    uint32_t chunk_index = only_member ? requested_chunk : slot->next_chunk;
    if (chunk_index >= slot->chunk_count) return 0;
    if (!only_member && slot->last_send_ms != 0 &&
        now_ms - slot->last_send_ms < GROUP_MEDIA_CHUNK_INTERVAL_MS) {
        return 0;
    }

    cyxchat_group_id_t group_id;
    memcpy(group_id.bytes, slot->media.group_id, CYXCHAT_GROUP_ID_SIZE);
    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group || group->left) {
        CYXWIZ_WARN("Stopping group media transfer for inactive group");
        media_tx_free(slot);
        return 1;
    }

    size_t offset = (size_t)chunk_index * GROUP_MEDIA_CHUNK_DATA_MAX;
    if (offset >= slot->data_len) {
        media_tx_free(slot);
        return 1;
    }
    size_t chunk_len = slot->data_len - offset;
    if (chunk_len > GROUP_MEDIA_CHUNK_DATA_MAX) {
        chunk_len = GROUP_MEDIA_CHUNK_DATA_MAX;
    }

    uint8_t ciphertext[GROUP_MEDIA_CHUNK_DATA_MAX + CYXCHAT_CRYPTO_OVERHEAD];
    size_t ct_len = 0;
    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        slot->data + offset, chunk_len,
        slot->group_key,
        ciphertext, &ct_len
    );
    if (err != CYXWIZ_OK) {
        CYXWIZ_WARN("Failed to encrypt group media chunk: %d", err);
        media_tx_free(slot);
        return 1;
    }

    cyxchat_msg_id_t msg_id;
    memcpy(msg_id.bytes, slot->media.msg_id, CYXCHAT_MSG_ID_SIZE);
    uint8_t wire[GROUP_MEDIA_CHUNK_WIRE_MAX];
    size_t wire_len = serialize_group_media_chunk(
        wire, sizeof(wire),
        &msg_id, &group_id, &ctx->local_id,
        slot->key_version, slot->media.file_id,
        chunk_index, slot->chunk_count,
        ciphertext, ct_len
    );
    if (wire_len == 0) {
        CYXWIZ_WARN("Failed to serialize group media chunk");
        media_tx_free(slot);
        return 1;
    }

    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_WARN("No onion context available for group media chunk");
        media_tx_free(slot);
        return 1;
    }

    int sent_count = 0;
    if (only_member) {
        err = cyxwiz_onion_send_to(onion, only_member, wire, wire_len);
        if (err == CYXWIZ_OK) {
            sent_count++;
        } else {
            CYXWIZ_WARN("Failed to resend group media chunk %u/%u: %d",
                        chunk_index + 1, slot->chunk_count, err);
        }
    } else {
        for (uint8_t i = 0; i < group->member_count; i++) {
            if (memcmp(&group->members[i].node_id, &ctx->local_id, CYXCHAT_NODE_ID_SIZE) == 0) {
                continue;
            }
            err = cyxwiz_onion_send_to(onion, &group->members[i].node_id, wire, wire_len);
            if (err == CYXWIZ_OK) {
                sent_count++;
            } else {
                CYXWIZ_WARN("Failed to send group media chunk %u/%u to member %u: %d",
                            chunk_index + 1, slot->chunk_count, i, err);
            }
        }
    }

    if (only_member) {
        CYXWIZ_INFO("Resent group media chunk %u/%u to requester",
                    chunk_index + 1, slot->chunk_count);
        return sent_count > 0 ? 1 : 0;
    }

    slot->next_chunk++;
    slot->last_send_ms = now_ms;
    if (slot->next_chunk >= slot->chunk_count && slot->completed_at_ms == 0) {
        CYXWIZ_INFO("Queued all group media chunks to %d/%u members",
                    sent_count, group->member_count - 1);
        slot->completed_at_ms = now_ms;
    }
    return 1;
}

static int media_tx_poll(cyxchat_group_ctx_t *ctx, uint64_t now_ms) {
    int events = 0;
    for (int i = 0; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        if (ctx->media_tx[i].active) {
            if (ctx->media_tx[i].completed_at_ms != 0 &&
                now_ms - ctx->media_tx[i].completed_at_ms >= GROUP_MEDIA_TX_RETAIN_MS) {
                media_tx_free(&ctx->media_tx[i]);
                events++;
                continue;
            }
            events += media_tx_send_next(ctx, &ctx->media_tx[i], now_ms, NULL, 0);
        }
    }
    return events;
}

static int media_rx_poll(cyxchat_group_ctx_t *ctx, uint64_t now_ms) {
    int events = 0;
    for (int i = 0; i < GROUP_MEDIA_MAX_TRANSFERS; i++) {
        cyxchat_group_media_rx_t *slot = &ctx->media_rx[i];
        if (!slot->active || slot->chunks_received >= slot->chunk_count) {
            continue;
        }

        uint64_t since_update = now_ms - slot->updated_at_ms;
        uint64_t since_request = now_ms - slot->last_request_ms;
        if (since_update < GROUP_MEDIA_RX_STALL_MS ||
            (slot->last_request_ms != 0 &&
             since_request < GROUP_MEDIA_RX_REQUEST_INTERVAL_MS)) {
            continue;
        }

        uint32_t missing = media_first_missing_chunk(slot);
        if (missing >= slot->chunk_count) {
            continue;
        }

        if (slot->request_count >= GROUP_MEDIA_RX_MAX_REQUESTS) {
            CYXWIZ_WARN("Abandoning stalled group media receive after retries");
            media_rx_free(slot);
            events++;
            continue;
        }

        media_rx_send_ack(ctx, slot, GROUP_MEDIA_ACK_CHUNK_REQUEST, missing);
        slot->last_request_ms = now_ms;
        slot->request_count++;
        CYXWIZ_INFO("Requested missing group media chunk %u/%u (retry %u/%u)",
                    missing + 1, slot->chunk_count,
                    slot->request_count, GROUP_MEDIA_RX_MAX_REQUESTS);
        events++;
    }
    return events;
}

/* ============================================================
 * GROUP_INVITE Wire Format
 * ============================================================
 *
 *   +0: type (1 byte) = 0x21
 *   +1: msg_id (8 bytes)
 *   +9: inviter_id (32 bytes)
 *  +41: group_id (8 bytes)
 *  +49: group_name (64 bytes, null-terminated)
 * +113: key_version (4 bytes, big-endian)
 * +117: encrypted_key (72 bytes) - nonce(24) + ciphertext(32) + tag(16)
 * +189: inviter_pubkey (32 bytes) - for key derivation
 *
 * Total: 221 bytes
 */

#define GROUP_INVITE_WIRE_SIZE 221

static size_t serialize_group_invite(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    const cyxwiz_node_id_t *inviter_id,
    const cyxchat_group_id_t *group_id,
    const char *group_name,
    uint32_t key_version,
    const uint8_t *encrypted_key,  /* 72 bytes */
    const uint8_t *inviter_pubkey  /* 32 bytes */
) {
    if (out_size < GROUP_INVITE_WIRE_SIZE) return 0;

    size_t offset = 0;

    /* Type */
    out[offset++] = CYXCHAT_MSG_GROUP_INVITE;

    /* Message ID */
    memcpy(out + offset, msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    /* Inviter ID */
    memcpy(out + offset, inviter_id->bytes, 32);
    offset += 32;

    /* Group ID */
    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Group name (64 bytes, null-padded) */
    memset(out + offset, 0, CYXCHAT_MAX_DISPLAY_NAME);
    if (group_name) {
        size_t name_len = strlen(group_name);
        if (name_len > CYXCHAT_MAX_DISPLAY_NAME - 1)
            name_len = CYXCHAT_MAX_DISPLAY_NAME - 1;
        memcpy(out + offset, group_name, name_len);
    }
    offset += CYXCHAT_MAX_DISPLAY_NAME;

    /* Key version (big-endian) */
    out[offset++] = (key_version >> 24) & 0xFF;
    out[offset++] = (key_version >> 16) & 0xFF;
    out[offset++] = (key_version >> 8) & 0xFF;
    out[offset++] = key_version & 0xFF;

    /* Encrypted key (72 bytes) */
    memcpy(out + offset, encrypted_key, CYXCHAT_ENCRYPTED_KEY_SIZE);
    offset += CYXCHAT_ENCRYPTED_KEY_SIZE;

    /* Inviter's public key (32 bytes) for key derivation */
    memcpy(out + offset, inviter_pubkey, 32);
    offset += 32;

    return offset;
}

static size_t deserialize_group_invite(
    const uint8_t *in,
    size_t len,
    cyxchat_msg_id_t *msg_id_out,
    cyxwiz_node_id_t *inviter_id_out,
    cyxchat_group_id_t *group_id_out,
    char *group_name_out,  /* must be CYXCHAT_MAX_DISPLAY_NAME */
    uint32_t *key_version_out,
    uint8_t *encrypted_key_out,  /* must be 72 bytes */
    uint8_t *inviter_pubkey_out  /* must be 32 bytes */
) {
    if (len < GROUP_INVITE_WIRE_SIZE) return 0;

    size_t offset = 0;

    /* Type (skip, already checked) */
    offset++;

    /* Message ID */
    memcpy(msg_id_out->bytes, in + offset, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    /* Inviter ID */
    memcpy(inviter_id_out->bytes, in + offset, 32);
    offset += 32;

    /* Group ID */
    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Group name - zero first to ensure null termination */
    memset(group_name_out, 0, CYXCHAT_MAX_DISPLAY_NAME);
    memcpy(group_name_out, in + offset, CYXCHAT_MAX_DISPLAY_NAME - 1);
    offset += CYXCHAT_MAX_DISPLAY_NAME;

    /* Key version (big-endian) */
    *key_version_out = ((uint32_t)in[offset] << 24) |
                       ((uint32_t)in[offset + 1] << 16) |
                       ((uint32_t)in[offset + 2] << 8) |
                       (uint32_t)in[offset + 3];
    offset += 4;

    /* Encrypted key */
    memcpy(encrypted_key_out, in + offset, CYXCHAT_ENCRYPTED_KEY_SIZE);
    offset += CYXCHAT_ENCRYPTED_KEY_SIZE;

    /* Inviter public key */
    memcpy(inviter_pubkey_out, in + offset, 32);
    offset += 32;

    return offset;
}

/* ============================================================
 * GROUP_JOIN Wire Format
 * ============================================================
 *
 *  +0: type (1 byte) = 0x22
 *  +1: group_id (8 bytes)
 *  +9: member_id (32 bytes)
 * +41: member_pubkey (32 bytes) - for key exchange
 * +73: timestamp (8 bytes, big-endian)
 *
 * Total: 81 bytes
 */

#define GROUP_JOIN_WIRE_SIZE 81

static size_t serialize_group_join(
    uint8_t *out,
    size_t out_size,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id,
    const uint8_t *member_pubkey,
    uint64_t timestamp
) {
    if (out_size < GROUP_JOIN_WIRE_SIZE) return 0;

    size_t offset = 0;

    out[offset++] = CYXCHAT_MSG_GROUP_JOIN;

    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    memcpy(out + offset, member_id->bytes, 32);
    offset += 32;

    memcpy(out + offset, member_pubkey, 32);
    offset += 32;

    /* Timestamp (big-endian) */
    out[offset++] = (timestamp >> 56) & 0xFF;
    out[offset++] = (timestamp >> 48) & 0xFF;
    out[offset++] = (timestamp >> 40) & 0xFF;
    out[offset++] = (timestamp >> 32) & 0xFF;
    out[offset++] = (timestamp >> 24) & 0xFF;
    out[offset++] = (timestamp >> 16) & 0xFF;
    out[offset++] = (timestamp >> 8) & 0xFF;
    out[offset++] = timestamp & 0xFF;

    return offset;
}

static size_t deserialize_group_join(
    const uint8_t *in,
    size_t len,
    cyxchat_group_id_t *group_id_out,
    cyxwiz_node_id_t *member_id_out,
    uint8_t *member_pubkey_out,
    uint64_t *timestamp_out
) {
    if (len < GROUP_JOIN_WIRE_SIZE) return 0;

    size_t offset = 1;  /* Skip type */

    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    memcpy(member_id_out->bytes, in + offset, 32);
    offset += 32;

    memcpy(member_pubkey_out, in + offset, 32);
    offset += 32;

    *timestamp_out = ((uint64_t)in[offset] << 56) |
                     ((uint64_t)in[offset + 1] << 48) |
                     ((uint64_t)in[offset + 2] << 40) |
                     ((uint64_t)in[offset + 3] << 32) |
                     ((uint64_t)in[offset + 4] << 24) |
                     ((uint64_t)in[offset + 5] << 16) |
                     ((uint64_t)in[offset + 6] << 8) |
                     (uint64_t)in[offset + 7];
    offset += 8;

    return offset;
}

/* ============================================================
 * GROUP_LEAVE Wire Format
 * ============================================================
 *
 *  +0: type (1 byte) = 0x23
 *  +1: group_id (8 bytes)
 *  +9: member_id (32 bytes)
 * +41: timestamp (8 bytes, big-endian)
 *
 * Total: 49 bytes
 */

#define GROUP_LEAVE_WIRE_SIZE 49

static size_t serialize_group_leave(
    uint8_t *out,
    size_t out_size,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id,
    uint64_t timestamp
) {
    if (out_size < GROUP_LEAVE_WIRE_SIZE) return 0;

    size_t offset = 0;

    out[offset++] = CYXCHAT_MSG_GROUP_LEAVE;

    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    memcpy(out + offset, member_id->bytes, 32);
    offset += 32;

    /* Timestamp (big-endian) */
    out[offset++] = (timestamp >> 56) & 0xFF;
    out[offset++] = (timestamp >> 48) & 0xFF;
    out[offset++] = (timestamp >> 40) & 0xFF;
    out[offset++] = (timestamp >> 32) & 0xFF;
    out[offset++] = (timestamp >> 24) & 0xFF;
    out[offset++] = (timestamp >> 16) & 0xFF;
    out[offset++] = (timestamp >> 8) & 0xFF;
    out[offset++] = timestamp & 0xFF;

    return offset;
}

static size_t deserialize_group_leave(
    const uint8_t *in,
    size_t len,
    cyxchat_group_id_t *group_id_out,
    cyxwiz_node_id_t *member_id_out,
    uint64_t *timestamp_out
) {
    if (len < GROUP_LEAVE_WIRE_SIZE) return 0;

    size_t offset = 1;  /* Skip type */

    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    memcpy(member_id_out->bytes, in + offset, 32);
    offset += 32;

    *timestamp_out = ((uint64_t)in[offset] << 56) |
                     ((uint64_t)in[offset + 1] << 48) |
                     ((uint64_t)in[offset + 2] << 40) |
                     ((uint64_t)in[offset + 3] << 32) |
                     ((uint64_t)in[offset + 4] << 24) |
                     ((uint64_t)in[offset + 5] << 16) |
                     ((uint64_t)in[offset + 6] << 8) |
                     (uint64_t)in[offset + 7];
    offset += 8;

    return offset;
}

/* ============================================================
 * GROUP_MEMBER_LIST Wire Format
 * ============================================================
 *
 * Sent by admin to new member after they join, containing all
 * existing members so the new member can send to everyone.
 *
 *  +0: type (1 byte) = 0x81
 *  +1: group_id (8 bytes)
 *  +9: member_count (1 byte)
 * +10: members (N * 33 bytes each): node_id(32) + role(1)
 *
 * Max: 10 + 32*33 = 1066 bytes (fits in onion with 1-hop)
 */

#define GROUP_MEMBER_LIST_HEADER_SIZE 10
#define GROUP_MEMBER_LIST_ENTRY_SIZE 33
#define GROUP_MEMBER_LIST_MAX_MEMBERS 32

static size_t serialize_group_member_list(
    uint8_t *out,
    size_t out_size,
    const cyxchat_group_id_t *group_id,
    const cyxchat_group_member_t *members,
    uint8_t member_count
) {
    size_t required = GROUP_MEMBER_LIST_HEADER_SIZE +
                      (member_count * GROUP_MEMBER_LIST_ENTRY_SIZE);
    if (out_size < required) return 0;

    size_t offset = 0;

    out[offset++] = CYXCHAT_MSG_GROUP_MEMBER_LIST;

    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    out[offset++] = member_count;

    for (uint8_t i = 0; i < member_count; i++) {
        memcpy(out + offset, members[i].node_id.bytes, 32);
        offset += 32;
        out[offset++] = (uint8_t)members[i].role;
    }

    return offset;
}

static size_t deserialize_group_member_list(
    const uint8_t *in,
    size_t len,
    cyxchat_group_id_t *group_id_out,
    cyxchat_group_member_t *members_out,
    uint8_t *member_count_out
) {
    if (len < GROUP_MEMBER_LIST_HEADER_SIZE) return 0;

    size_t offset = 1;  /* Skip type */

    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    uint8_t count = in[offset++];
    if (count > GROUP_MEMBER_LIST_MAX_MEMBERS) count = GROUP_MEMBER_LIST_MAX_MEMBERS;

    size_t required = GROUP_MEMBER_LIST_HEADER_SIZE +
                      (count * GROUP_MEMBER_LIST_ENTRY_SIZE);
    if (len < required) return 0;

    for (uint8_t i = 0; i < count; i++) {
        memset(&members_out[i], 0, sizeof(cyxchat_group_member_t));
        memcpy(members_out[i].node_id.bytes, in + offset, 32);
        offset += 32;
        members_out[i].role = (cyxchat_group_role_t)in[offset++];
    }

    *member_count_out = count;
    return offset;
}

/* ============================================================
 * GROUP_KICK Wire Format
 * ============================================================
 *
 *  +0: type (1 byte) = 0x24
 *  +1: group_id (8 bytes)
 *  +9: kicked_member (32 bytes)
 * +41: kicked_by (32 bytes)
 * +73: timestamp (8 bytes, big-endian)
 *
 * Total: 81 bytes
 */

#define GROUP_KICK_WIRE_SIZE 81

static size_t serialize_group_kick(
    uint8_t *out,
    size_t out_size,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *kicked_member,
    const cyxwiz_node_id_t *kicked_by,
    uint64_t timestamp
) {
    if (out_size < GROUP_KICK_WIRE_SIZE) return 0;

    size_t offset = 0;

    out[offset++] = CYXCHAT_MSG_GROUP_KICK;

    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    memcpy(out + offset, kicked_member->bytes, 32);
    offset += 32;

    memcpy(out + offset, kicked_by->bytes, 32);
    offset += 32;

    /* Timestamp (big-endian) */
    out[offset++] = (timestamp >> 56) & 0xFF;
    out[offset++] = (timestamp >> 48) & 0xFF;
    out[offset++] = (timestamp >> 40) & 0xFF;
    out[offset++] = (timestamp >> 32) & 0xFF;
    out[offset++] = (timestamp >> 24) & 0xFF;
    out[offset++] = (timestamp >> 16) & 0xFF;
    out[offset++] = (timestamp >> 8) & 0xFF;
    out[offset++] = timestamp & 0xFF;

    return offset;
}

static size_t deserialize_group_kick(
    const uint8_t *in,
    size_t len,
    cyxchat_group_id_t *group_id_out,
    cyxwiz_node_id_t *kicked_member_out,
    cyxwiz_node_id_t *kicked_by_out,
    uint64_t *timestamp_out
) {
    if (len < GROUP_KICK_WIRE_SIZE) return 0;

    size_t offset = 1;  /* Skip type */

    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    memcpy(kicked_member_out->bytes, in + offset, 32);
    offset += 32;

    memcpy(kicked_by_out->bytes, in + offset, 32);
    offset += 32;

    *timestamp_out = ((uint64_t)in[offset] << 56) |
                     ((uint64_t)in[offset + 1] << 48) |
                     ((uint64_t)in[offset + 2] << 40) |
                     ((uint64_t)in[offset + 3] << 32) |
                     ((uint64_t)in[offset + 4] << 24) |
                     ((uint64_t)in[offset + 5] << 16) |
                     ((uint64_t)in[offset + 6] << 8) |
                     (uint64_t)in[offset + 7];
    offset += 8;

    return offset;
}

/* ============================================================
 * GROUP_KEY Wire Format (0x25)
 * ============================================================
 *
 * Key distribution to a single member:
 *  +0: type (1 byte) = 0x25
 *  +1: group_id (8 bytes)
 *  +9: key_version (4 bytes, big-endian)
 * +13: sender_id (32 bytes) - who is distributing
 * +45: sender_pubkey (32 bytes) - for ECDH
 * +77: encrypted_key (72 bytes) - nonce(24) + key(32) + tag(16)
 *
 * Total: 149 bytes
 */

#define GROUP_KEY_WIRE_SIZE 149

static size_t serialize_group_key(
    uint8_t *out,
    size_t out_size,
    const cyxchat_group_id_t *group_id,
    uint32_t key_version,
    const cyxwiz_node_id_t *sender_id,
    const uint8_t *sender_pubkey,
    const uint8_t *encrypted_key  /* 72 bytes */
) {
    if (out_size < GROUP_KEY_WIRE_SIZE) return 0;

    size_t offset = 0;

    out[offset++] = CYXCHAT_MSG_GROUP_KEY;

    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Key version (big-endian) */
    out[offset++] = (key_version >> 24) & 0xFF;
    out[offset++] = (key_version >> 16) & 0xFF;
    out[offset++] = (key_version >> 8) & 0xFF;
    out[offset++] = key_version & 0xFF;

    memcpy(out + offset, sender_id->bytes, 32);
    offset += 32;

    memcpy(out + offset, sender_pubkey, 32);
    offset += 32;

    memcpy(out + offset, encrypted_key, CYXCHAT_ENCRYPTED_KEY_SIZE);
    offset += CYXCHAT_ENCRYPTED_KEY_SIZE;

    return offset;
}

static size_t deserialize_group_key(
    const uint8_t *in,
    size_t len,
    cyxchat_group_id_t *group_id_out,
    uint32_t *key_version_out,
    cyxwiz_node_id_t *sender_id_out,
    uint8_t *sender_pubkey_out,
    uint8_t *encrypted_key_out
) {
    if (len < GROUP_KEY_WIRE_SIZE) return 0;

    size_t offset = 1;  /* Skip type */

    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    *key_version_out = ((uint32_t)in[offset] << 24) |
                       ((uint32_t)in[offset + 1] << 16) |
                       ((uint32_t)in[offset + 2] << 8) |
                       (uint32_t)in[offset + 3];
    offset += 4;

    memcpy(sender_id_out->bytes, in + offset, 32);
    offset += 32;

    memcpy(sender_pubkey_out, in + offset, 32);
    offset += 32;

    memcpy(encrypted_key_out, in + offset, CYXCHAT_ENCRYPTED_KEY_SIZE);
    offset += CYXCHAT_ENCRYPTED_KEY_SIZE;

    return offset;
}

/* ============================================================
 * GROUP_KEY_ACK Wire Format (0x28)
 * ============================================================
 *
 *  +0: type (1 byte) = 0x28
 *  +1: group_id (8 bytes)
 *  +9: key_version (4 bytes, big-endian)
 * +13: member_id (32 bytes) - who is ACKing
 * +45: status (1 byte) - 0=received, 1=applied, 2=error
 *
 * Total: 46 bytes
 */

#define GROUP_KEY_ACK_WIRE_SIZE 46

#define KEY_ACK_STATUS_RECEIVED  0
#define KEY_ACK_STATUS_APPLIED   1
#define KEY_ACK_STATUS_ERROR     2

static size_t serialize_group_key_ack(
    uint8_t *out,
    size_t out_size,
    const cyxchat_group_id_t *group_id,
    uint32_t key_version,
    const cyxwiz_node_id_t *member_id,
    uint8_t status
) {
    if (out_size < GROUP_KEY_ACK_WIRE_SIZE) return 0;

    size_t offset = 0;

    out[offset++] = CYXCHAT_MSG_GROUP_KEY_ACK;

    memcpy(out + offset, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Key version (big-endian) */
    out[offset++] = (key_version >> 24) & 0xFF;
    out[offset++] = (key_version >> 16) & 0xFF;
    out[offset++] = (key_version >> 8) & 0xFF;
    out[offset++] = key_version & 0xFF;

    memcpy(out + offset, member_id->bytes, 32);
    offset += 32;

    out[offset++] = status;

    return offset;
}

static size_t deserialize_group_key_ack(
    const uint8_t *in,
    size_t len,
    cyxchat_group_id_t *group_id_out,
    uint32_t *key_version_out,
    cyxwiz_node_id_t *member_id_out,
    uint8_t *status_out
) {
    if (len < GROUP_KEY_ACK_WIRE_SIZE) return 0;

    size_t offset = 1;  /* Skip type */

    memcpy(group_id_out->bytes, in + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    *key_version_out = ((uint32_t)in[offset] << 24) |
                       ((uint32_t)in[offset + 1] << 16) |
                       ((uint32_t)in[offset + 2] << 8) |
                       (uint32_t)in[offset + 3];
    offset += 4;

    memcpy(member_id_out->bytes, in + offset, 32);
    offset += 32;

    *status_out = in[offset++];

    return offset;
}

/* ============================================================
 * Key Derivation Helper
 * ============================================================
 *
 * Derives encryption key for group key transfer between two nodes.
 * Uses BLAKE2b with domain separation for forward secrecy.
 */

static cyxwiz_error_t derive_member_key(
    const uint8_t *shared_secret,
    const cyxwiz_node_id_t *sender,
    const cyxwiz_node_id_t *recipient,
    uint8_t *key_out
) {
    /* Build input: shared_secret || sender_id || recipient_id */
    uint8_t input[32 + 32 + 32];
    memcpy(input, shared_secret, 32);
    memcpy(input + 32, sender->bytes, 32);
    memcpy(input + 64, recipient->bytes, 32);

    /* Pre-hash the 96-byte input to 32 bytes.
     * cyxwiz_crypto_derive_key uses BLAKE2b keyed hash mode which has a
     * max key size of 64 bytes, so we need to compress first. */
    uint8_t hashed_input[32];
    crypto_generichash(hashed_input, 32, input, sizeof(input), NULL, 0);
    cyxwiz_secure_zero(input, sizeof(input));

    /* Derive key with domain separation */
    cyxwiz_error_t result = cyxwiz_crypto_derive_key(
        hashed_input, 32,
        (const uint8_t*)CYXCHAT_GROUP_KEY_DOMAIN,
        strlen(CYXCHAT_GROUP_KEY_DOMAIN),
        key_out
    );

    cyxwiz_secure_zero(hashed_input, 32);
    return result;
}

/* ============================================================
 * Key Distribution Processing
 * ============================================================
 *
 * Key rotation distributes the new group key to all members.
 * Each member's key is encrypted using X25519 ECDH.
 *
 * Flow:
 * 1. Admin calls rotate_key() - starts distribution job
 * 2. poll() sends encrypted keys at rate-limited intervals
 * 3. Members receive GROUP_KEY, decrypt, send GROUP_KEY_ACK
 * 4. Admin tracks ACKs, retries failed members
 * 5. After timeout or all ACKs, job completes
 */

/**
 * Find a free key distribution job slot
 */
static cyxchat_key_dist_job_t* find_free_key_dist_job(cyxchat_group_ctx_t *ctx) {
    for (int i = 0; i < CYXCHAT_MAX_KEY_DIST_JOBS; i++) {
        if (!ctx->key_dist_jobs[i].active) {
            return &ctx->key_dist_jobs[i];
        }
    }
    return NULL;
}

/**
 * Find active key distribution job for a group
 */
static cyxchat_key_dist_job_t* find_key_dist_job(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    for (int i = 0; i < CYXCHAT_MAX_KEY_DIST_JOBS; i++) {
        if (ctx->key_dist_jobs[i].active &&
            memcmp(ctx->key_dist_jobs[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            return &ctx->key_dist_jobs[i];
        }
    }
    return NULL;
}

/**
 * Clean up a key distribution job
 */
static void cleanup_key_dist_job(cyxchat_key_dist_job_t *job) {
    if (job->members) {
        /* Securely clear any sensitive data */
        for (size_t i = 0; i < job->member_count; i++) {
            cyxwiz_secure_zero(job->members[i].public_key, 32);
        }
        free(job->members);
        job->members = NULL;
    }
    cyxwiz_secure_zero(job->new_key, 32);
    memset(job, 0, sizeof(cyxchat_key_dist_job_t));
}

/**
 * Send encrypted group key to a single member
 *
 * @param ctx       Group context
 * @param job       Key distribution job
 * @param member    Target member
 * @param now_ms    Current timestamp
 * @return          CYXCHAT_OK on success
 */
static cyxchat_error_t send_key_to_member(
    cyxchat_group_ctx_t *ctx,
    cyxchat_key_dist_job_t *job,
    cyxchat_key_dist_member_t *member,
    uint64_t now_ms
) {
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        return CYXCHAT_ERR_NETWORK;
    }

    /* Get our X25519 keypair from onion context */
    uint8_t our_pubkey[32];
    cyxwiz_error_t pk_err = cyxwiz_onion_get_pubkey(onion, our_pubkey);
    if (pk_err != CYXWIZ_OK) {
        CYXWIZ_WARN("Failed to get onion pubkey for key distribution");
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Compute shared secret via X25519 ECDH */
    uint8_t shared_secret[32];
    cyxwiz_error_t err = cyxwiz_onion_compute_ecdh(
        onion, member->public_key, shared_secret
    );
    if (err != CYXWIZ_OK) {
        CYXWIZ_WARN("Failed to compute shared secret for key distribution");
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Derive encryption key for this member */
    uint8_t enc_key[32];
    err = derive_member_key(shared_secret, &ctx->local_id, &member->node_id, enc_key);
    cyxwiz_secure_zero(shared_secret, 32);

    if (err != CYXWIZ_OK) {
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Encrypt group key: nonce(24) + ciphertext(32) + tag(16) = 72 bytes */
    uint8_t encrypted_key[CYXCHAT_ENCRYPTED_KEY_SIZE];
    size_t enc_len = 0;

    err = cyxwiz_crypto_encrypt(
        job->new_key, 32,
        enc_key, encrypted_key, &enc_len
    );
    cyxwiz_secure_zero(enc_key, 32);

    if (err != CYXWIZ_OK || enc_len != CYXCHAT_ENCRYPTED_KEY_SIZE) {
        CYXWIZ_ERROR("Failed to encrypt group key for distribution");
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Serialize GROUP_KEY message */
    uint8_t wire[GROUP_KEY_WIRE_SIZE + 10];
    size_t wire_len = serialize_group_key(
        wire, sizeof(wire),
        &job->group_id,
        job->key_version,
        &ctx->local_id,
        our_pubkey,
        encrypted_key
    );

    if (wire_len == 0) {
        CYXWIZ_ERROR("Failed to serialize GROUP_KEY message");
        return CYXCHAT_ERR_INVALID;
    }

    /* Send via onion routing */
    err = cyxwiz_onion_send_to(onion, &member->node_id, wire, wire_len);
    if (err != CYXWIZ_OK) {
        CYXWIZ_WARN("Failed to send GROUP_KEY to member");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Update tracking */
    member->sent_at = now_ms;

    char member_hex[65];
    cyxchat_node_id_to_hex(&member->node_id, member_hex);
    CYXWIZ_DEBUG("Sent GROUP_KEY v%u to %.16s... (retry=%u)",
                 job->key_version, member_hex, member->retry_count);

    return CYXCHAT_OK;
}

/**
 * Process key distribution job - send phase
 *
 * Rate-limits sending to avoid overwhelming the network.
 * Sends one key per call if interval has passed.
 */
static void process_key_dist_sending(
    cyxchat_group_ctx_t *ctx,
    cyxchat_key_dist_job_t *job,
    uint64_t now_ms
) {
    /* Check rate limit */
    if (now_ms - job->last_send_ms < CYXCHAT_KEY_SEND_INTERVAL_MS) {
        return;
    }

    /* Find next member to send to */
    while (job->current_index < job->member_count) {
        cyxchat_key_dist_member_t *member = &job->members[job->current_index];

        /* Skip if already sent and awaiting ACK */
        if (member->sent_at > 0 && !member->ack_received) {
            job->current_index++;
            continue;
        }

        /* Skip if already ACKed */
        if (member->ack_received) {
            job->current_index++;
            continue;
        }

        /* Send key to this member */
        cyxchat_error_t err = send_key_to_member(ctx, job, member, now_ms);
        job->last_send_ms = now_ms;
        job->current_index++;

        if (err == CYXCHAT_OK) {
            return; /* One send per poll cycle */
        }
        /* On error, continue to next member */
    }

    /* All initial sends complete, move to awaiting ACKs */
    if (job->current_index >= job->member_count) {
        job->state = KEY_DIST_AWAITING_ACKS;
        CYXWIZ_INFO("Key distribution: all initial sends complete, awaiting ACKs");
    }
}

/**
 * Process key distribution job - ACK/retry phase
 *
 * Checks for timeouts and retries failed members.
 */
static void process_key_dist_acks(
    cyxchat_group_ctx_t *ctx,
    cyxchat_key_dist_job_t *job,
    uint64_t now_ms
) {
    /* Check overall timeout */
    if (now_ms - job->started_at > CYXCHAT_KEY_DIST_TIMEOUT_MS) {
        size_t failed = 0;
        for (size_t i = 0; i < job->member_count; i++) {
            if (!job->members[i].ack_received) {
                failed++;
            }
        }

        char group_hex[17];
        cyxchat_group_id_to_hex(&job->group_id, group_hex);
        CYXWIZ_WARN("Key distribution timeout for group %s: %zu/%zu failed",
                    group_hex, failed, job->member_count);

        job->state = KEY_DIST_FAILED;

        /* Invoke completion callback */
        if (ctx->on_key_dist_complete) {
            ctx->on_key_dist_complete(ctx, &job->group_id, job->key_version,
                                      0, failed, ctx->on_key_dist_complete_data);
        }

        cleanup_key_dist_job(job);
        return;
    }

    /* Check if all members ACKed */
    if (job->acked_count >= job->member_count) {
        char group_hex[17];
        cyxchat_group_id_to_hex(&job->group_id, group_hex);
        CYXWIZ_INFO("Key distribution complete for group %s: all %zu members ACKed",
                    group_hex, job->member_count);

        job->state = KEY_DIST_COMPLETE;

        /* Invoke completion callback */
        if (ctx->on_key_dist_complete) {
            ctx->on_key_dist_complete(ctx, &job->group_id, job->key_version,
                                      1, 0, ctx->on_key_dist_complete_data);
        }

        cleanup_key_dist_job(job);
        return;
    }

    /* Check for retry interval */
    if (now_ms - job->last_retry_check_ms < CYXCHAT_KEY_ACK_RETRY_MS) {
        return;
    }
    job->last_retry_check_ms = now_ms;

    /* Retry members who haven't ACKed */
    for (size_t i = 0; i < job->member_count; i++) {
        cyxchat_key_dist_member_t *member = &job->members[i];

        /* Skip if ACKed */
        if (member->ack_received) {
            continue;
        }

        /* Skip if max retries exceeded */
        if (member->retry_count >= CYXCHAT_KEY_MAX_RETRIES) {
            continue;
        }

        /* Check if retry is due (5 seconds since last send) */
        if (member->sent_at > 0 &&
            now_ms - member->sent_at >= CYXCHAT_KEY_ACK_RETRY_MS) {

            member->retry_count++;
            member->sent_at = 0; /* Reset to allow resend */

            char member_hex[65];
            cyxchat_node_id_to_hex(&member->node_id, member_hex);
            CYXWIZ_DEBUG("Retrying GROUP_KEY to %.16s... (attempt %u)",
                         member_hex, member->retry_count);

            send_key_to_member(ctx, job, member, now_ms);
        }
    }
}

/**
 * Start key distribution for a group
 *
 * @param ctx           Group context
 * @param group         Group to distribute key for
 * @param new_key       New group key (32 bytes)
 * @param key_version   New key version
 * @param now_ms        Current timestamp
 * @return              CYXCHAT_OK on success
 */
static cyxchat_error_t start_key_distribution(
    cyxchat_group_ctx_t *ctx,
    cyxchat_group_t *group,
    const uint8_t *new_key,
    uint32_t key_version,
    uint64_t now_ms
) {
    /* Check if distribution already in progress */
    if (find_key_dist_job(ctx, &group->group_id)) {
        CYXWIZ_WARN("Key distribution already in progress for group");
        return CYXCHAT_ERR_EXISTS;
    }

    /* Find free job slot */
    cyxchat_key_dist_job_t *job = find_free_key_dist_job(ctx);
    if (!job) {
        CYXWIZ_ERROR("No free key distribution slots");
        return CYXCHAT_ERR_FULL;
    }

    /* Count members to distribute to (excluding self) */
    size_t target_count = 0;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(&group->members[i].node_id, &ctx->local_id, 32) != 0) {
            target_count++;
        }
    }

    if (target_count == 0) {
        CYXWIZ_INFO("No other members to distribute key to");
        return CYXCHAT_OK; /* Nothing to do */
    }

    /* Allocate member tracking array */
    job->members = calloc(target_count, sizeof(cyxchat_key_dist_member_t));
    if (!job->members) {
        return CYXCHAT_ERR_MEMORY;
    }

    /* Populate member list */
    size_t j = 0;
    for (uint8_t i = 0; i < group->member_count && j < target_count; i++) {
        if (memcmp(&group->members[i].node_id, &ctx->local_id, 32) == 0) {
            continue; /* Skip self */
        }

        memcpy(&job->members[j].node_id, &group->members[i].node_id,
               sizeof(cyxwiz_node_id_t));
        memcpy(job->members[j].public_key, group->members[i].public_key, 32);
        job->members[j].sent_at = 0;
        job->members[j].ack_received = 0;
        job->members[j].retry_count = 0;
        j++;
    }

    /* Initialize job */
    memcpy(&job->group_id, &group->group_id, sizeof(cyxchat_group_id_t));
    job->key_version = key_version;
    memcpy(job->new_key, new_key, 32);
    job->state = KEY_DIST_SENDING;
    job->member_count = target_count;
    job->current_index = 0;
    job->acked_count = 0;
    job->started_at = now_ms;
    job->last_send_ms = 0;
    job->last_retry_check_ms = now_ms;
    job->active = 1;

    char group_hex[17];
    cyxchat_group_id_to_hex(&group->group_id, group_hex);
    CYXWIZ_INFO("Started key distribution for group %s: v%u to %zu members",
                group_hex, key_version, target_count);

    return CYXCHAT_OK;
}

/**
 * Record ACK from a member for key distribution
 */
static void record_key_dist_ack(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint32_t key_version,
    const cyxwiz_node_id_t *member_id
) {
    cyxchat_key_dist_job_t *job = find_key_dist_job(ctx, group_id);
    if (!job) {
        CYXWIZ_DEBUG("Received GROUP_KEY_ACK for unknown distribution job");
        return;
    }

    /* Check version matches */
    if (job->key_version != key_version) {
        CYXWIZ_DEBUG("GROUP_KEY_ACK version mismatch: got %u, expected %u",
                     key_version, job->key_version);
        return;
    }

    /* Find member and mark as ACKed */
    for (size_t i = 0; i < job->member_count; i++) {
        if (memcmp(job->members[i].node_id.bytes, member_id->bytes, 32) == 0) {
            if (!job->members[i].ack_received) {
                job->members[i].ack_received = 1;
                job->acked_count++;

                char member_hex[65];
                cyxchat_node_id_to_hex(member_id, member_hex);
                CYXWIZ_DEBUG("Received GROUP_KEY_ACK from %.16s... (%zu/%zu)",
                             member_hex, job->acked_count, job->member_count);
            }
            return;
        }
    }

    CYXWIZ_DEBUG("Received GROUP_KEY_ACK from unknown member");
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

    /* Default auto-rotation settings */
    c->auto_rotate_on_leave = 1;  /* Enable by default for forward secrecy */
    c->auto_rotate_on_kick = 0;   /* Disabled - kicker already rotates */

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_group_ctx_destroy(cyxchat_group_ctx_t *ctx) {
    if (ctx) {
        /* Free pending group message buffers */
        pending_grp_free_all(ctx);
        media_transfer_free_all(ctx);

        /* Clean up active key distribution jobs */
        for (int i = 0; i < CYXCHAT_MAX_KEY_DIST_JOBS; i++) {
            if (ctx->key_dist_jobs[i].active) {
                cleanup_key_dist_job(&ctx->key_dist_jobs[i]);
            }
        }

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

    int events = 0;

    /* Check pending group message timeouts and retry */
    pending_grp_check_timeouts(ctx, now_ms);

    events += media_tx_poll(ctx, now_ms);
    events += media_rx_poll(ctx, now_ms);

    /* Process active key distribution jobs */
    for (int i = 0; i < CYXCHAT_MAX_KEY_DIST_JOBS; i++) {
        cyxchat_key_dist_job_t *job = &ctx->key_dist_jobs[i];
        if (!job->active) continue;

        switch (job->state) {
            case KEY_DIST_SENDING:
                process_key_dist_sending(ctx, job, now_ms);
                events++;
                break;

            case KEY_DIST_AWAITING_ACKS:
                process_key_dist_acks(ctx, job, now_ms);
                events++;
                break;

            case KEY_DIST_COMPLETE:
            case KEY_DIST_FAILED:
                /* Should have been cleaned up already */
                cleanup_key_dist_job(job);
                break;

            default:
                break;
        }
    }

    return events;
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

cyxchat_error_t cyxchat_group_restore(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *name,
    const uint8_t *group_key,
    uint32_t key_version,
    const cyxwiz_node_id_t *creator_id,
    cyxchat_group_role_t my_role
) {
    if (!ctx || !group_id || !name || !group_key || !creator_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check if group already exists */
    cyxchat_group_t *existing = find_group(ctx, group_id);
    if (existing) {
        CYXWIZ_INFO("Group already restored, skipping");
        return CYXCHAT_OK;
    }

    if (ctx->group_count >= CYXCHAT_MAX_GROUPS) {
        return CYXCHAT_ERR_FULL;
    }

    cyxchat_group_t *group = &ctx->groups[ctx->group_count];
    memset(group, 0, sizeof(cyxchat_group_t));

    /* Copy group ID */
    memcpy(&group->group_id, group_id, sizeof(cyxchat_group_id_t));

    /* Set name */
    strncpy(group->name, name, CYXCHAT_MAX_DISPLAY_NAME - 1);

    /* Copy creator */
    memcpy(&group->creator, creator_id, sizeof(cyxwiz_node_id_t));

    /* Copy group key */
    memcpy(group->group_key, group_key, 32);
    group->key_version = key_version;

    /* Add ourselves with the specified role */
    cyxchat_group_member_t *self = &group->members[0];
    memcpy(&self->node_id, &ctx->local_id, sizeof(cyxwiz_node_id_t));
    self->role = my_role;
    self->joined_at = cyxchat_timestamp_ms();
    group->member_count = 1;

    /* Timestamps (use current time since we don't have originals) */
    group->created_at = cyxchat_timestamp_ms();
    group->key_updated_at = group->created_at;

    ctx->group_count++;

    char group_hex[17] = {0};
    for (int i = 0; i < 8; i++) {
        snprintf(group_hex + i*2, 3, "%02x", group_id->bytes[i]);
    }
    CYXWIZ_INFO("Restored group %.16s with role %d", group_hex, my_role);

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_group_restore_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id,
    cyxchat_group_role_t role
) {
    if (!ctx || !group_id || !member_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check if member already exists */
    for (size_t i = 0; i < group->member_count; i++) {
        if (memcmp(&group->members[i].node_id, member_id, sizeof(cyxwiz_node_id_t)) == 0) {
            return CYXCHAT_OK; /* Already exists */
        }
    }

    if (group->member_count >= CYXCHAT_MAX_GROUP_MEMBERS) {
        return CYXCHAT_ERR_FULL;
    }

    cyxchat_group_member_t *member = &group->members[group->member_count];
    memset(member, 0, sizeof(cyxchat_group_member_t));
    memcpy(&member->node_id, member_id, sizeof(cyxwiz_node_id_t));
    member->role = role;
    member->joined_at = cyxchat_timestamp_ms();
    group->member_count++;

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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
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
    CYXWIZ_INFO("=== Group invite called ===");
    if (!ctx || !group_id || !member || !member_pubkey) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
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

    /* Get onion context for key exchange */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context for group invite");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Check if we have the member's pubkey (key exchange must be complete).
     * Note: We check member_pubkey instead of cyxwiz_onion_has_key() because
     * the onion context uses exact 32-byte node ID matching, but short node IDs
     * (e.g., 16-char hex) get padded with zeros which may not match the stored ID.
     * Since the pubkey was already found (via prefix match in connection layer),
     * we can proceed with ECDH using the provided pubkey. */
    int has_nonzero_pubkey = 0;
    for (int i = 0; i < 32; i++) {
        if (member_pubkey[i] != 0) {
            has_nonzero_pubkey = 1;
            break;
        }
    }
    if (!has_nonzero_pubkey) {
        char member_hex[65];
        cyxchat_node_id_to_hex(member, member_hex);
        CYXWIZ_ERROR("Cannot send group invite - no pubkey for member %.16s... (key exchange not complete)", member_hex);
        CYXWIZ_INFO("Hint: Send a direct message first to establish key exchange");
        return CYXCHAT_ERR_NO_KEY;
    }

    /* Compute ECDH shared secret with recipient's public key */
    uint8_t shared_secret[32];
    cyxwiz_error_t err = cyxwiz_onion_compute_ecdh(onion, member_pubkey, shared_secret);
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to compute ECDH for group invite: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Derive encryption key for this specific transfer */
    uint8_t derived_key[32];
    err = derive_member_key(shared_secret, &ctx->local_id, member, derived_key);
    if (err != CYXWIZ_OK) {
        cyxwiz_secure_zero(shared_secret, 32);
        CYXWIZ_ERROR("Failed to derive key for group invite");
        return CYXCHAT_ERR_CRYPTO;
    }
    cyxwiz_secure_zero(shared_secret, 32);

    /* Encrypt group key for recipient */
    uint8_t encrypted_key[CYXCHAT_ENCRYPTED_KEY_SIZE];
    size_t enc_len = 0;
    err = cyxwiz_crypto_encrypt(
        group->group_key, 32,
        derived_key,
        encrypted_key, &enc_len
    );
    cyxwiz_secure_zero(derived_key, 32);

    if (err != CYXWIZ_OK || enc_len != CYXCHAT_ENCRYPTED_KEY_SIZE) {
        CYXWIZ_ERROR("Failed to encrypt group key: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Get our public key for the invite */
    uint8_t our_pubkey[32];
    err = cyxwiz_onion_get_pubkey(onion, our_pubkey);
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to get our public key");
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Build and serialize invite message */
    cyxchat_msg_id_t msg_id;
    cyxchat_generate_msg_id(&msg_id);

    uint8_t wire[GROUP_INVITE_WIRE_SIZE + 10];
    size_t wire_len = serialize_group_invite(
        wire, sizeof(wire),
        &msg_id,
        &ctx->local_id,
        group_id,
        group->name,
        group->key_version,
        encrypted_key,
        our_pubkey
    );

    if (wire_len == 0) {
        CYXWIZ_ERROR("Failed to serialize group invite");
        return CYXCHAT_ERR_INVALID;
    }

    /* Log invite */
    char group_hex[17];
    cyxchat_group_id_to_hex(group_id, group_hex);
    char member_hex[65];
    cyxchat_node_id_to_hex(member, member_hex);
    CYXWIZ_INFO("Sending group invite for %s to %.16s... (key_version=%u)",
                group_hex, member_hex, group->key_version);

    /* Send invite via onion */
    err = cyxwiz_onion_send_to(onion, member, wire, wire_len);
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to send group invite: %d", err);
        return CYXCHAT_ERR_NETWORK;
    }

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

    /* Check if we already have this group */
    if (find_group(ctx, &invite->group_id) != NULL) {
        CYXWIZ_WARN("Already a member of this group");
        return CYXCHAT_ERR_EXISTS;
    }

    /* Get onion context for key decryption */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context for accepting invite");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Compute ECDH shared secret with inviter's public key */
    uint8_t shared_secret[32];
    cyxwiz_error_t err = cyxwiz_onion_compute_ecdh(onion, invite->inviter_pubkey, shared_secret);
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to compute ECDH for invite accept: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Derive decryption key (same derivation as sender, but roles swapped) */
    uint8_t derived_key[32];
    err = derive_member_key(shared_secret, &invite->inviter, &ctx->local_id, derived_key);
    if (err != CYXWIZ_OK) {
        cyxwiz_secure_zero(shared_secret, 32);
        CYXWIZ_ERROR("Failed to derive key for invite accept");
        return CYXCHAT_ERR_CRYPTO;
    }
    cyxwiz_secure_zero(shared_secret, 32);

    /* Decrypt group key */
    uint8_t decrypted_key[32];
    size_t key_len = 0;
    err = cyxwiz_crypto_decrypt(
        invite->encrypted_key, CYXCHAT_ENCRYPTED_KEY_SIZE,
        derived_key,
        decrypted_key, &key_len
    );
    cyxwiz_secure_zero(derived_key, 32);

    if (err != CYXWIZ_OK || key_len != 32) {
        CYXWIZ_ERROR("Failed to decrypt group key: %d", err);
        cyxwiz_secure_zero(decrypted_key, 32);
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Create new group entry */
    cyxchat_group_t *group = &ctx->groups[ctx->group_count];
    memset(group, 0, sizeof(cyxchat_group_t));

    memcpy(&group->group_id, &invite->group_id, sizeof(cyxchat_group_id_t));
    memcpy(group->name, invite->group_name, CYXCHAT_MAX_DISPLAY_NAME);
    memcpy(group->group_key, decrypted_key, 32);
    cyxwiz_secure_zero(decrypted_key, 32);

    group->key_version = invite->key_version;
    group->created_at = cyxchat_timestamp_ms();
    group->key_updated_at = group->created_at;

    /* Add ourselves as member */
    cyxchat_group_member_t *self = &group->members[0];
    memcpy(&self->node_id, &ctx->local_id, sizeof(cyxwiz_node_id_t));
    self->role = CYXCHAT_ROLE_MEMBER;
    self->joined_at = cyxchat_timestamp_ms();
    group->member_count = 1;

    /* Add inviter as a known member */
    cyxchat_group_member_t *inviter_mem = &group->members[1];
    memcpy(&inviter_mem->node_id, &invite->inviter, sizeof(cyxwiz_node_id_t));
    memcpy(inviter_mem->public_key, invite->inviter_pubkey, 32);
    inviter_mem->role = CYXCHAT_ROLE_MEMBER;  /* Will be updated when we receive member list */
    inviter_mem->joined_at = 0;  /* Unknown */
    group->member_count = 2;

    ctx->group_count++;

    /* Get our public key for the join notification */
    uint8_t our_pubkey[32];
    err = cyxwiz_onion_get_pubkey(onion, our_pubkey);
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to get our public key for join notification");
        /* Group is already added, continue anyway */
    } else {
        /* Build and send join notification to inviter */
        uint8_t wire[GROUP_JOIN_WIRE_SIZE + 10];
        size_t wire_len = serialize_group_join(
            wire, sizeof(wire),
            &invite->group_id,
            &ctx->local_id,
            our_pubkey,
            cyxchat_timestamp_ms()
        );

        if (wire_len > 0) {
            err = cyxwiz_onion_send_to(onion, &invite->inviter, wire, wire_len);
            if (err != CYXWIZ_OK) {
                CYXWIZ_WARN("Failed to send join notification: %d", err);
            } else {
                char group_hex[17];
                cyxchat_group_id_to_hex(&invite->group_id, group_hex);
                CYXWIZ_INFO("Accepted invite to group %s, sent join notification", group_hex);
            }
        }
    }

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

void cyxchat_group_free_invite(cyxchat_group_invite_t *invite) {
    if (invite) {
        /* Zero out sensitive data before freeing */
        cyxwiz_secure_zero(invite, sizeof(cyxchat_group_invite_t));
        free(invite);
    }
}

cyxchat_error_t cyxchat_group_leave(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Already left */
    if (group->left) {
        return CYXCHAT_OK;
    }

    /* Get onion context for sending notifications */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (onion) {
        /* Build leave notification */
        uint8_t wire[GROUP_LEAVE_WIRE_SIZE + 10];
        size_t wire_len = serialize_group_leave(
            wire, sizeof(wire),
            group_id,
            &ctx->local_id,
            cyxchat_timestamp_ms()
        );

        if (wire_len > 0) {
            /* Send to all members */
            int sent = 0;
            for (uint8_t i = 0; i < group->member_count; i++) {
                /* Skip self */
                if (memcmp(&group->members[i].node_id, &ctx->local_id, 32) == 0) {
                    continue;
                }

                cyxwiz_error_t err = cyxwiz_onion_send_to(onion,
                    &group->members[i].node_id, wire, wire_len);
                if (err == CYXWIZ_OK) {
                    sent++;
                }
            }

            char group_hex[17];
            cyxchat_group_id_to_hex(group_id, group_hex);
            CYXWIZ_INFO("Sent leave notification for group %s to %d members", group_hex, sent);
        }
    }

    /* Mark as left */
    group->left = 1;

    /* Invoke leave callback for ourselves */
    if (ctx->on_member_leave) {
        ctx->on_member_leave(ctx, group_id, &ctx->local_id, 0, ctx->on_member_leave_data);
    }

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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
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

            /* Copy member ID before removing from list */
            cyxwiz_node_id_t kicked_member;
            memcpy(&kicked_member, member, sizeof(cyxwiz_node_id_t));

            /* Move last member to this slot */
            if (i < group->member_count - 1) {
                memcpy(&group->members[i],
                       &group->members[group->member_count - 1],
                       sizeof(cyxchat_group_member_t));
            }
            group->member_count--;

            /* Send kick notification before rotating key */
            cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
            if (onion) {
                uint8_t wire[GROUP_KICK_WIRE_SIZE + 10];
                size_t wire_len = serialize_group_kick(
                    wire, sizeof(wire),
                    group_id,
                    &kicked_member,
                    &ctx->local_id,
                    cyxchat_timestamp_ms()
                );

                if (wire_len > 0) {
                    /* Send to all remaining members */
                    int sent = 0;
                    for (uint8_t j = 0; j < group->member_count; j++) {
                        if (memcmp(&group->members[j].node_id, &ctx->local_id, 32) == 0) {
                            continue;
                        }
                        cyxwiz_error_t err = cyxwiz_onion_send_to(onion,
                            &group->members[j].node_id, wire, wire_len);
                        if (err == CYXWIZ_OK) {
                            sent++;
                        }
                    }

                    /* Also send to kicked member */
                    cyxwiz_onion_send_to(onion, &kicked_member, wire, wire_len);

                    char group_hex[17];
                    cyxchat_group_id_to_hex(group_id, group_hex);
                    char member_hex[65];
                    cyxchat_node_id_to_hex(&kicked_member, member_hex);
                    CYXWIZ_INFO("Kicked %.16s... from group %s, notified %d members",
                                member_hex, group_hex, sent);
                }
            }

            /* Invoke callback */
            if (ctx->on_member_leave) {
                ctx->on_member_leave(ctx, group_id, &kicked_member, 1, ctx->on_member_leave_data);
            }

            /* Rotate key after removal (forward secrecy) */
            cyxchat_group_rotate_key(ctx, group_id);

            return CYXCHAT_OK;
        }
    }

    CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
}

cyxchat_error_t cyxchat_group_add_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
) {
    if (!ctx || !group_id || !member) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
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

    if (text_len > GROUP_MAX_ENCRYPTED_TEXT) {
        return CYXCHAT_ERR_INVALID;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    if (!is_member(group, &ctx->local_id) || group->left) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Check send permission based on group settings */
    if (!cyxchat_group_can_send(ctx, group_id, &ctx->local_id)) {
        CYXWIZ_WARN("Send blocked: who_can_send=%d, not permitted", group->who_can_send);
        return CYXCHAT_ERR_NOT_ADMIN; /* Reuse error code for "not permitted" */
    }

    /* Generate message ID */
    cyxchat_msg_id_t msg_id;
    cyxchat_generate_msg_id(&msg_id);

    /* Build plaintext payload: text_len(2) + text(N) + [reply_to(8) if set] */
    uint8_t plaintext[GROUP_MAX_ENCRYPTED_TEXT + 12];
    size_t pt_len = 0;

    /* Text length (2 bytes, little-endian) */
    plaintext[pt_len++] = text_len & 0xFF;
    plaintext[pt_len++] = (text_len >> 8) & 0xFF;

    /* Text content */
    memcpy(plaintext + pt_len, text, text_len);
    pt_len += text_len;

    /* Optional reply_to */
    uint16_t flags = CYXCHAT_FLAG_ENCRYPTED;
    if (reply_to && !cyxchat_msg_id_is_zero(reply_to)) {
        flags |= CYXCHAT_FLAG_REPLY;
        memcpy(plaintext + pt_len, reply_to->bytes, CYXCHAT_MSG_ID_SIZE);
        pt_len += CYXCHAT_MSG_ID_SIZE;
    }

    /* Encrypt with group key using XChaCha20-Poly1305 */
    uint8_t ciphertext[GROUP_MAX_ENCRYPTED_TEXT + 12 + CYXCHAT_CRYPTO_OVERHEAD];
    size_t ct_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        plaintext, pt_len,
        group->group_key,
        ciphertext, &ct_len
    );

    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to encrypt group message: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Build wire message */
    uint8_t wire[256];
    size_t wire_len = serialize_group_text(
        wire, sizeof(wire),
        &msg_id, flags,
        group_id, group->key_version,
        ciphertext, ct_len,
        &ctx->local_id
    );

    if (wire_len == 0) {
        CYXWIZ_ERROR("Failed to serialize group message");
        return CYXCHAT_ERR_INVALID;
    }

    /* Get onion context from chat context */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context available for group messaging");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Log group ID for debugging */
    char group_hex[17];
    cyxchat_group_id_to_hex(group_id, group_hex);
    CYXWIZ_INFO("Sending group message to %s (key_version=%u, %zu bytes, %u members)",
                group_hex, group->key_version, wire_len, group->member_count);

    /* Send to each member via onion routing */
    int sent_count = 0;
    for (uint8_t i = 0; i < group->member_count; i++) {
        /* Skip self */
        if (memcmp(&group->members[i].node_id, &ctx->local_id, 32) == 0) {
            continue;
        }

        char member_hex[65];
        cyxchat_node_id_to_hex(&group->members[i].node_id, member_hex);
        CYXWIZ_INFO("Sending to member %u: %s (onion peer_keys=%zu)",
                    i, member_hex,
                    cyxwiz_onion_peer_key_count(onion));

        err = cyxwiz_onion_send_to(onion, &group->members[i].node_id, wire, wire_len);
        if (err != CYXWIZ_OK) {
            CYXWIZ_WARN("Failed to send to member %u: %d (%s)", i, err,
                        cyxwiz_strerror(err));
            /* Continue trying other members */
        } else {
            sent_count++;
        }
    }

    CYXWIZ_INFO("Group message sent to %d/%u members", sent_count, group->member_count - 1);

    /* Track for retransmission (even if no members reached yet —
     * the retry timer will resend once peers complete key exchange) */
    pending_grp_track(ctx, &msg_id, group_id, wire, wire_len, group,
                      cyxchat_timestamp_ms());

    if (msg_id_out) {
        memcpy(msg_id_out, &msg_id, sizeof(cyxchat_msg_id_t));
    }

    /* Return OK even if 0 members reached — the message is tracked for retry.
     * This prevents the app from throwing and losing the message entirely. */
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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check admin permission */
    if (get_role(group, &ctx->local_id) < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Generate new key */
    uint8_t new_key[32];
    cyxwiz_crypto_random(new_key, 32);

    uint32_t new_version = group->key_version + 1;
    uint64_t now_ms = cyxchat_timestamp_ms();

    /* Start async key distribution to all members */
    cyxchat_error_t dist_err = start_key_distribution(
        ctx, group, new_key, new_version, now_ms
    );

    if (dist_err != CYXCHAT_OK && dist_err != CYXCHAT_ERR_EXISTS) {
        /* Distribution failed to start - don't apply key yet */
        cyxwiz_secure_zero(new_key, 32);
        CYXWIZ_ERROR("Failed to start key distribution: %d", dist_err);
        return dist_err;
    }

    /* Apply new key locally */
    memcpy(group->group_key, new_key, 32);
    cyxwiz_secure_zero(new_key, 32);
    group->key_version = new_version;
    group->key_updated_at = now_ms;

    char group_hex[17];
    cyxchat_group_id_to_hex(group_id, group_hex);
    CYXWIZ_INFO("Group %s key rotated to v%u", group_hex, new_version);

    /* Notify callback (key applied locally, distribution in progress) */
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

cyxchat_error_t cyxchat_group_get_key(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint8_t *key_out,
    uint32_t *version_out
) {
    if (!ctx || !group_id || !key_out || !version_out) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    memcpy(key_out, group->group_key, 32);
    *version_out = group->key_version;

    return CYXCHAT_OK;
}


int cyxchat_group_is_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return 0;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
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

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
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

void cyxchat_group_set_on_media(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_media_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_media = callback;
        ctx->on_media_data = user_data;
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

/**
 * Set callback for key distribution completion
 *
 * Called when key distribution to all members completes (success or failure).
 *
 * @param ctx       Group context
 * @param callback  Callback function (ctx, group_id, version, success, failed_count, user_data)
 * @param user_data User data passed to callback
 */
void cyxchat_group_set_on_key_dist_complete(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_key_dist_complete_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_key_dist_complete = callback;
        ctx->on_key_dist_complete_data = user_data;
    }
}

void cyxchat_group_set_on_delivery_failed(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_delivery_failed_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_delivery_failed = callback;
        ctx->on_delivery_failed_data = user_data;
    }
}

void cyxchat_group_set_on_delivery(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_group_delivery_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_delivery = callback;
        ctx->on_delivery_data = user_data;
    }
}

/* ============================================================
 * Key Distribution Progress Query
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
int cyxchat_group_key_dist_progress(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    size_t *sent_out,
    size_t *acked_out,
    size_t *total_out
) {
    if (!ctx || !group_id) {
        return 0;
    }

    cyxchat_key_dist_job_t *job = find_key_dist_job(ctx, group_id);
    if (!job) {
        return 0; /* No active distribution */
    }

    /* Count sent members */
    size_t sent = 0;
    for (size_t i = 0; i < job->member_count; i++) {
        if (job->members[i].sent_at > 0) {
            sent++;
        }
    }

    if (sent_out) *sent_out = sent;
    if (acked_out) *acked_out = job->acked_count;
    if (total_out) *total_out = job->member_count;

    return 1;
}

/* ============================================================
 * Auto-Rotation Configuration
 * ============================================================ */

/**
 * Enable or disable auto-rotation when a member voluntarily leaves
 *
 * When enabled (default), if we are admin and a member leaves,
 * we automatically rotate the group key for forward secrecy.
 *
 * @param ctx       Group context
 * @param enable    1 to enable, 0 to disable
 */
void cyxchat_group_set_auto_rotate_on_leave(
    cyxchat_group_ctx_t *ctx,
    int enable
) {
    if (ctx) {
        ctx->auto_rotate_on_leave = enable ? 1 : 0;
    }
}

/**
 * Enable or disable auto-rotation when receiving a kick notification
 *
 * When enabled, if we are admin and receive a kick notification from
 * another admin, we also rotate the key (backup rotation).
 * Disabled by default since the kicking admin already rotates.
 *
 * @param ctx       Group context
 * @param enable    1 to enable, 0 to disable
 */
void cyxchat_group_set_auto_rotate_on_kick(
    cyxchat_group_ctx_t *ctx,
    int enable
) {
    if (ctx) {
        ctx->auto_rotate_on_kick = enable ? 1 : 0;
    }
}

/**
 * Get current auto-rotation settings
 *
 * @param ctx               Group context
 * @param on_leave_out      Output: 1 if auto-rotate on leave enabled
 * @param on_kick_out       Output: 1 if auto-rotate on kick enabled
 */
void cyxchat_group_get_auto_rotate_settings(
    cyxchat_group_ctx_t *ctx,
    int *on_leave_out,
    int *on_kick_out
) {
    if (!ctx) return;
    if (on_leave_out) *on_leave_out = ctx->auto_rotate_on_leave;
    if (on_kick_out) *on_kick_out = ctx->auto_rotate_on_kick;
}

/* ============================================================
 * Message Handling
 * ============================================================ */

/**
 * Handle incoming GROUP_TEXT message
 */
static void handle_group_text(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    /* Parse wire format */
    uint8_t type;
    uint16_t flags;
    cyxchat_msg_id_t msg_id;
    cyxwiz_node_id_t sender_id;
    cyxchat_group_id_t group_id;
    uint32_t key_version;
    const uint8_t *encrypted;
    size_t encrypted_len;

    size_t parsed = deserialize_group_text(
        data, len,
        &type, &flags, &msg_id, &sender_id,
        &group_id, &key_version,
        &encrypted, &encrypted_len
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_TEXT message");
        return;
    }

    /* Find group */
    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group) {
        char group_hex[17];
        cyxchat_group_id_to_hex(&group_id, group_hex);
        CYXWIZ_WARN("Received message for unknown group: %s", group_hex);
        return;
    }

    /* Check if we've left the group */
    if (group->left) {
        CYXWIZ_DEBUG("Ignoring message for group we've left");
        return;
    }

    /* Check key version */
    if (key_version != group->key_version) {
        CYXWIZ_WARN("Key version mismatch: got %u, expected %u",
                    key_version, group->key_version);
        /* TODO: Request key update from admin */
        return;
    }

    /* Decrypt message */
    uint8_t plaintext[GROUP_MAX_ENCRYPTED_TEXT + 12];
    size_t pt_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_decrypt(
        encrypted, encrypted_len,
        group->group_key,
        plaintext, &pt_len
    );

    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to decrypt group message: %d", err);
        return;
    }

    /* Parse plaintext: text_len(2) + text(N) + [reply_to(8)] */
    if (pt_len < 2) {
        CYXWIZ_WARN("Decrypted message too short");
        return;
    }

    uint16_t text_len = plaintext[0] | ((uint16_t)plaintext[1] << 8);
    if (pt_len < (size_t)(2 + text_len)) {
        CYXWIZ_WARN("Invalid text length in group message");
        return;
    }

    /* Build group message struct for callback */
    cyxchat_group_msg_t msg;
    memset(&msg, 0, sizeof(msg));

    msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    msg.header.type = CYXCHAT_MSG_GROUP_TEXT;
    msg.header.flags = flags;
    memcpy(&msg.header.msg_id, &msg_id, sizeof(cyxchat_msg_id_t));
    msg.header.timestamp = cyxchat_timestamp_ms();

    memcpy(&msg.group_id, &group_id, sizeof(cyxchat_group_id_t));
    msg.key_version = key_version;
    msg.text_len = text_len;

    if (text_len > 0 && text_len <= CYXCHAT_MAX_TEXT_LEN && text_len <= sizeof(msg.text)) {
        memcpy(msg.text, plaintext + 2, text_len);
    } else if (text_len > sizeof(msg.text)) {
        CYXWIZ_WARN("Text length exceeds buffer: %u > %zu", text_len, sizeof(msg.text));
        return;
    }

    /* Parse reply_to if present */
    if ((flags & CYXCHAT_FLAG_REPLY) && pt_len >= (size_t)(2 + text_len + CYXCHAT_MSG_ID_SIZE)) {
        memcpy(&msg.reply_to, plaintext + 2 + text_len, CYXCHAT_MSG_ID_SIZE);
    }

    char group_hex[17];
    cyxchat_group_id_to_hex(&group_id, group_hex);
    char sender_hex[65];
    cyxchat_node_id_to_hex(&sender_id, sender_hex);
    CYXWIZ_INFO("Received group message in %s from %.16s... (%u bytes)",
                group_hex, sender_hex, text_len);

    /* Invoke callback - ALL data in one heap string to avoid stale pointers.
     * Format: "<16-hex-groupid>:<64-hex-senderid>:<16-hex-msgid>:<text>" */
    if (ctx->on_message) {
        /* groupid(16) + : + senderid(64) + : + msgid(16) + : + text + NUL */
        size_t payload_len = 16 + 1 + 64 + 1 + 16 + 1 + text_len + 1;
        if (payload_len > CYXCHAT_MAX_TEXT_LEN + 128) {
            CYXWIZ_WARN("Group message payload too large: %zu", payload_len);
            return;
        }
        char *payload = (char *)malloc(payload_len);
        if (payload) {
            int pi;
            /* Group ID hex (16 chars) */
            for (pi = 0; pi < 8; pi++)
                snprintf(payload + pi * 2, 3, "%02x", group_id.bytes[pi]);
            payload[16] = ':';
            /* Sender ID hex (64 chars) */
            for (pi = 0; pi < 32; pi++)
                snprintf(payload + 17 + pi * 2, 3, "%02x", sender_id.bytes[pi]);
            payload[81] = ':';
            /* Message ID hex (16 chars) */
            for (pi = 0; pi < 8; pi++)
                snprintf(payload + 82 + pi * 2, 3, "%02x", msg.header.msg_id.bytes[pi]);
            payload[98] = ':';
            /* Text */
            memcpy(payload + 99, msg.text, text_len);
            payload[99 + text_len] = 0;
            ctx->on_message(ctx, &group_id, &sender_id, payload, ctx->on_message_data);
            free(payload);
        }
    }

    /* Send GROUP_TEXT_ACK back to sender */
    {
        cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
        if (onion) {
            /* Wire format: type(1) + flags(1) + msg_id(8) + sender_id(32) + group_id(8) = 50 bytes */
            uint8_t ack_buf[50];
            size_t ack_len = 0;
            ack_buf[ack_len++] = CYXCHAT_MSG_GROUP_TEXT_ACK;
            ack_buf[ack_len++] = 0; /* flags */
            memcpy(ack_buf + ack_len, msg_id.bytes, CYXCHAT_MSG_ID_SIZE);
            ack_len += CYXCHAT_MSG_ID_SIZE;
            memcpy(ack_buf + ack_len, ctx->local_id.bytes, 32);
            ack_len += 32;
            memcpy(ack_buf + ack_len, group_id.bytes, CYXCHAT_GROUP_ID_SIZE);
            ack_len += CYXCHAT_GROUP_ID_SIZE;

            cyxwiz_onion_send_to(onion, &sender_id, ack_buf, ack_len);
            CYXWIZ_DEBUG("Sent GROUP_TEXT_ACK for message in group %s", group_hex);
        }
    }
}

/**
 * Handle incoming GROUP_FILE/GROUP_VOICE/GROUP_IMAGE/GROUP_VIDEO metadata.
 */
static void handle_group_media(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    uint8_t type;
    uint16_t flags;
    cyxchat_msg_id_t msg_id;
    cyxwiz_node_id_t sender_id;
    cyxchat_group_id_t group_id;
    uint32_t key_version;
    const uint8_t *encrypted;
    size_t encrypted_len;

    size_t parsed = deserialize_group_media(
        data, len,
        &type, &flags, &msg_id, &sender_id,
        &group_id, &key_version,
        &encrypted, &encrypted_len
    );
    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse group media metadata");
        return;
    }

    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group) {
        CYXWIZ_WARN("Received media metadata for unknown group");
        return;
    }
    if (group->left) {
        CYXWIZ_DEBUG("Ignoring media metadata for group we've left");
        return;
    }
    if (!is_member(group, &sender_id)) {
        CYXWIZ_WARN("Ignoring group media metadata from non-member");
        return;
    }
    if (key_version != group->key_version) {
        CYXWIZ_WARN("Media key version mismatch: got %u, expected %u",
                    key_version, group->key_version);
        return;
    }

    uint8_t plaintext[GROUP_MEDIA_MAX_PLAINTEXT];
    size_t pt_len = 0;
    cyxwiz_error_t err = cyxwiz_crypto_decrypt(
        encrypted, encrypted_len,
        group->group_key,
        plaintext, &pt_len
    );
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to decrypt group media metadata: %d", err);
        return;
    }

    cyxchat_group_media_t media;
    memset(&media, 0, sizeof(media));
    memcpy(media.msg_id, msg_id.bytes, CYXCHAT_MSG_ID_SIZE);
    memcpy(media.group_id, group_id.bytes, CYXCHAT_GROUP_ID_SIZE);
    memcpy(media.sender_id, sender_id.bytes, 32);

    const uint8_t *payload = NULL;
    size_t payload_len = 0;
    if (!deserialize_group_media_plaintext(plaintext, pt_len, &media, &payload, &payload_len)) {
        CYXWIZ_WARN("Invalid decrypted group media metadata");
        return;
    }

    if (payload_len == 0 && media.file_size > 0) {
        cyxchat_error_t prep_err = media_rx_prepare(ctx, &media, cyxchat_timestamp_ms());
        if (prep_err != CYXCHAT_OK) {
            CYXWIZ_WARN("Failed to prepare group media receive slot: %d", prep_err);
        }
    }

    if (ctx->on_media) {
        ctx->on_media(ctx, &media, payload, payload_len, ctx->on_media_data);
    }

    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (onion) {
        uint8_t ack_buf[50];
        size_t ack_len = 0;
        ack_buf[ack_len++] = CYXCHAT_MSG_GROUP_FILE_ACK;
        ack_buf[ack_len++] = 0;
        memcpy(ack_buf + ack_len, msg_id.bytes, CYXCHAT_MSG_ID_SIZE);
        ack_len += CYXCHAT_MSG_ID_SIZE;
        memcpy(ack_buf + ack_len, ctx->local_id.bytes, 32);
        ack_len += 32;
        memcpy(ack_buf + ack_len, group_id.bytes, CYXCHAT_GROUP_ID_SIZE);
        ack_len += CYXCHAT_GROUP_ID_SIZE;

        cyxwiz_onion_send_to(onion, &sender_id, ack_buf, ack_len);
    }
}

/**
 * Handle incoming GROUP_FILE_CHUNK payload.
 */
static void handle_group_media_chunk(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    cyxchat_msg_id_t msg_id;
    cyxwiz_node_id_t sender_id;
    cyxchat_group_id_t group_id;
    uint32_t key_version;
    uint8_t file_id[CYXCHAT_FILE_ID_SIZE];
    uint32_t chunk_index;
    uint32_t chunk_count;
    const uint8_t *encrypted;
    size_t encrypted_len;

    size_t parsed = deserialize_group_media_chunk(
        data, len,
        &msg_id, &sender_id, &group_id, &key_version,
        file_id, &chunk_index, &chunk_count,
        &encrypted, &encrypted_len
    );
    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse group media chunk");
        return;
    }

    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group || group->left) {
        CYXWIZ_WARN("Received group media chunk for inactive/unknown group");
        return;
    }
    if (!is_member(group, &sender_id)) {
        CYXWIZ_WARN("Ignoring group media chunk from non-member");
        return;
    }
    if (key_version != group->key_version) {
        CYXWIZ_WARN("Group media chunk key version mismatch: got %u, expected %u",
                    key_version, group->key_version);
        return;
    }

    cyxchat_group_media_rx_t *slot = media_rx_find(ctx, &group_id, &sender_id, file_id);
    if (!slot) {
        CYXWIZ_DEBUG("Ignoring group media chunk without metadata");
        return;
    }
    if (memcmp(slot->media.msg_id, msg_id.bytes, CYXCHAT_MSG_ID_SIZE) != 0 ||
        chunk_count != slot->chunk_count || chunk_index >= slot->chunk_count) {
        CYXWIZ_WARN("Invalid group media chunk sequence");
        return;
    }

    uint8_t plaintext[GROUP_MEDIA_CHUNK_DATA_MAX];
    size_t pt_len = 0;
    cyxwiz_error_t err = cyxwiz_crypto_decrypt(
        encrypted, encrypted_len,
        group->group_key,
        plaintext, &pt_len
    );
    if (err != CYXWIZ_OK || pt_len == 0 || pt_len > GROUP_MEDIA_CHUNK_DATA_MAX) {
        CYXWIZ_WARN("Failed to decrypt group media chunk: %d", err);
        return;
    }

    size_t offset = (size_t)chunk_index * GROUP_MEDIA_CHUNK_DATA_MAX;
    if (offset >= slot->media.file_size || offset + pt_len > slot->media.file_size) {
        CYXWIZ_WARN("Group media chunk exceeds declared file size");
        return;
    }

    if (!media_chunk_seen(slot, chunk_index)) {
        memcpy(slot->data + offset, plaintext, pt_len);
        media_mark_chunk_seen(slot, chunk_index);
        slot->chunks_received++;
        slot->updated_at_ms = cyxchat_timestamp_ms();
    }

    if (slot->chunks_received == slot->chunk_count) {
        CYXWIZ_INFO("Completed group media payload assembly (%llu bytes)",
                    (unsigned long long)slot->media.file_size);
        media_rx_send_ack(ctx, slot, GROUP_MEDIA_ACK_COMPLETE, slot->chunk_count);
        if (ctx->on_media) {
            ctx->on_media(ctx, &slot->media, slot->data,
                          (size_t)slot->media.file_size, ctx->on_media_data);
        }
        media_rx_free(slot);
    }
}

static int handle_group_media_chunk_ack(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    if (len < GROUP_MEDIA_CHUNK_ACK_WIRE_SIZE) {
        return 0;
    }

    size_t offset = 2; /* type + flags */
    cyxchat_msg_id_t msg_id;
    memcpy(msg_id.bytes, data + offset, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    cyxwiz_node_id_t acker_id;
    memcpy(acker_id.bytes, data + offset, CYXCHAT_NODE_ID_SIZE);
    offset += CYXCHAT_NODE_ID_SIZE;

    if (from && memcmp(from, &acker_id, CYXCHAT_NODE_ID_SIZE) != 0) {
        CYXWIZ_WARN("Ignoring group media chunk ACK with mismatched sender");
        return 1;
    }

    cyxchat_group_id_t group_id;
    memcpy(group_id.bytes, data + offset, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    uint8_t file_id[CYXCHAT_FILE_ID_SIZE];
    memcpy(file_id, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    uint8_t status = data[offset++];
    uint32_t chunk_index = read_u32_be(data, &offset);
    uint32_t chunks_received = read_u32_be(data, &offset);
    uint32_t chunk_count = read_u32_be(data, &offset);

    cyxchat_group_media_tx_t *slot = media_tx_find(ctx, &msg_id, &group_id, file_id);
    if (!slot) {
        CYXWIZ_DEBUG("Group media chunk ACK for unknown/expired transfer");
        return 1;
    }
    if (chunk_count != slot->chunk_count) {
        CYXWIZ_WARN("Ignoring group media chunk ACK with mismatched chunk count");
        return 1;
    }

    if (status == GROUP_MEDIA_ACK_CHUNK_REQUEST) {
        if (chunk_index >= slot->chunk_count) {
            CYXWIZ_WARN("Ignoring invalid group media chunk request");
            return 1;
        }
        media_tx_send_next(ctx, slot, cyxchat_timestamp_ms(), &acker_id, chunk_index);
    } else if (status == GROUP_MEDIA_ACK_COMPLETE) {
        CYXWIZ_DEBUG("Group media receiver completed %u/%u chunks",
                     chunks_received, chunk_count);
    }
    return 1;
}

/**
 * Handle incoming GROUP_INVITE message
 */
static void handle_group_invite(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    /* Parse invite wire format */
    cyxchat_msg_id_t msg_id;
    cyxwiz_node_id_t inviter_id;
    cyxchat_group_id_t group_id;
    char group_name[CYXCHAT_MAX_DISPLAY_NAME];
    uint32_t key_version;
    uint8_t encrypted_key[CYXCHAT_ENCRYPTED_KEY_SIZE];
    uint8_t inviter_pubkey[32];

    size_t parsed = deserialize_group_invite(
        data, len,
        &msg_id, &inviter_id, &group_id, group_name,
        &key_version, encrypted_key, inviter_pubkey
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_INVITE message");
        return;
    }

    /* Check if we already have this group */
    if (find_group(ctx, &group_id) != NULL) {
        CYXWIZ_DEBUG("Ignoring invite - already member of group");
        return;
    }

    /* Build invite structure for callback - HEAP allocated because Dart
     * callback runs asynchronously via NativeCallable.listener(), so stack
     * variables would be invalid by the time Dart reads them.
     * The Dart side must free this via cyxchat_group_free_invite(). */
    cyxchat_group_invite_t *invite = calloc(1, sizeof(cyxchat_group_invite_t));
    if (!invite) {
        CYXWIZ_ERROR("Failed to allocate memory for invite");
        return;
    }

    invite->header.version = CYXCHAT_PROTOCOL_VERSION;
    invite->header.type = CYXCHAT_MSG_GROUP_INVITE;
    invite->header.timestamp = cyxchat_timestamp_ms();
    memcpy(&invite->header.msg_id, &msg_id, sizeof(cyxchat_msg_id_t));

    memcpy(&invite->group_id, &group_id, sizeof(cyxchat_group_id_t));
    memcpy(invite->group_name, group_name, CYXCHAT_MAX_DISPLAY_NAME);
    invite->key_version = key_version;
    memcpy(invite->encrypted_key, encrypted_key, CYXCHAT_ENCRYPTED_KEY_SIZE);
    memcpy(&invite->inviter, &inviter_id, sizeof(cyxwiz_node_id_t));
    memcpy(invite->inviter_pubkey, inviter_pubkey, 32);

    char group_hex[17];
    cyxchat_group_id_to_hex(&group_id, group_hex);
    char inviter_hex[65];
    cyxchat_node_id_to_hex(&inviter_id, inviter_hex);
    CYXWIZ_INFO("Received group invite to '%s' (%s) from %.16s...",
                group_name, group_hex, inviter_hex);

    /* Invoke callback - app decides whether to accept/decline */
    if (ctx->on_invite) {
        ctx->on_invite(ctx, invite, ctx->on_invite_data);
    } else {
        /* No callback registered, free the invite */
        free(invite);
    }
}

/**
 * Handle incoming GROUP_JOIN notification
 */
static void handle_group_join(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    /* Parse join wire format */
    cyxchat_group_id_t group_id;
    cyxwiz_node_id_t member_id;
    uint8_t member_pubkey[32];
    uint64_t timestamp;

    size_t parsed = deserialize_group_join(
        data, len,
        &group_id, &member_id, member_pubkey, &timestamp
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_JOIN message");
        return;
    }

    /* Find group */
    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group) {
        CYXWIZ_DEBUG("Ignoring join for unknown group");
        return;
    }

    /* Check if member already exists */
    if (is_member(group, &member_id)) {
        CYXWIZ_DEBUG("Member already in group, updating pubkey");
        cyxchat_group_member_t *mem = find_member(group, &member_id);
        if (mem) {
            memcpy(mem->public_key, member_pubkey, 32);
        }
        return;
    }

    /* Check group capacity */
    if (group->member_count >= CYXCHAT_MAX_GROUP_MEMBERS) {
        CYXWIZ_WARN("Group is full, cannot add new member");
        return;
    }

    /* Add new member */
    cyxchat_group_member_t *new_mem = &group->members[group->member_count];
    memset(new_mem, 0, sizeof(cyxchat_group_member_t));
    memcpy(&new_mem->node_id, &member_id, sizeof(cyxwiz_node_id_t));
    memcpy(new_mem->public_key, member_pubkey, 32);
    new_mem->role = CYXCHAT_ROLE_MEMBER;
    new_mem->joined_at = timestamp;
    group->member_count++;

    char group_hex[17];
    cyxchat_group_id_to_hex(&group_id, group_hex);
    char member_hex[65];
    cyxchat_node_id_to_hex(&member_id, member_hex);
    CYXWIZ_INFO("Member %.16s... joined group %s", member_hex, group_hex);

    /* If we are admin/owner, send member list to the new member
     * so they can send messages to all existing members */
    if (get_role(group, &ctx->local_id) >= CYXCHAT_ROLE_ADMIN) {
        /* Build and send member list */
        uint8_t wire[1200];
        size_t wire_len = serialize_group_member_list(
            wire, sizeof(wire),
            &group_id,
            group->members,
            group->member_count
        );

        if (wire_len > 0) {
            cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
            if (onion) {
                cyxwiz_error_t err = cyxwiz_onion_send_to(onion, &member_id, wire, wire_len);
                if (err == CYXWIZ_OK) {
                    CYXWIZ_INFO("Sent member list (%u members) to new member %.16s...",
                                group->member_count, member_hex);
                } else {
                    CYXWIZ_WARN("Failed to send member list to new member: %d", err);
                }
            }
        }
    }

    /* Invoke callback */
    if (ctx->on_member_join) {
        ctx->on_member_join(ctx, &group_id, &member_id, ctx->on_member_join_data);
    } else {
    }
}

/**
 * Handle incoming GROUP_MEMBER_LIST
 * Received by new members to populate their local member list
 */
static void handle_member_list(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;

    cyxchat_group_id_t group_id;
    cyxchat_group_member_t members[GROUP_MEMBER_LIST_MAX_MEMBERS];
    uint8_t member_count = 0;

    size_t parsed = deserialize_group_member_list(
        data, len,
        &group_id, members, &member_count
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_MEMBER_LIST message");
        return;
    }

    /* Find group */
    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group) {
        CYXWIZ_DEBUG("Ignoring member list for unknown group");
        return;
    }

    char group_hex[17];
    cyxchat_group_id_to_hex(&group_id, group_hex);
    CYXWIZ_INFO("Received member list for group %s: %u members", group_hex, member_count);

    /* Add each member we don't already have */
    int added_count = 0;
    for (uint8_t i = 0; i < member_count; i++) {
        /* Skip self */
        if (memcmp(&members[i].node_id, &ctx->local_id, 32) == 0) {
            continue;
        }

        /* Skip if already member */
        if (is_member(group, &members[i].node_id)) {
            /* Update role if needed */
            cyxchat_group_member_t *existing = find_member(group, &members[i].node_id);
            if (existing && existing->role != members[i].role) {
                existing->role = members[i].role;
            }
            continue;
        }

        /* Check capacity */
        if (group->member_count >= CYXCHAT_MAX_GROUP_MEMBERS) {
            CYXWIZ_WARN("Group full, cannot add more members from sync");
            break;
        }

        /* Add member */
        cyxchat_group_member_t *new_mem = &group->members[group->member_count];
        memset(new_mem, 0, sizeof(cyxchat_group_member_t));
        memcpy(&new_mem->node_id, &members[i].node_id, sizeof(cyxwiz_node_id_t));
        new_mem->role = members[i].role;
        new_mem->joined_at = cyxchat_timestamp_ms();
        group->member_count++;
        added_count++;

        char mem_hex[65];
        cyxchat_node_id_to_hex(&members[i].node_id, mem_hex);
        CYXWIZ_DEBUG("Added member from sync: %.16s... (role=%d)", mem_hex, members[i].role);
    }

    CYXWIZ_INFO("Member list sync complete: added %d new members (total: %u)",
                added_count, group->member_count);
}

/**
 * Handle incoming GROUP_LEAVE notification
 */
static void handle_group_leave(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    /* Parse leave wire format */
    cyxchat_group_id_t group_id;
    cyxwiz_node_id_t member_id;
    uint64_t timestamp;

    size_t parsed = deserialize_group_leave(
        data, len,
        &group_id, &member_id, &timestamp
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_LEAVE message");
        return;
    }

    /* Find group */
    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group) {
        CYXWIZ_DEBUG("Ignoring leave for unknown group");
        return;
    }

    /* Find and remove member */
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, member_id.bytes, 32) == 0) {
            /* Move last member to this slot */
            if (i < group->member_count - 1) {
                memcpy(&group->members[i],
                       &group->members[group->member_count - 1],
                       sizeof(cyxchat_group_member_t));
            }
            group->member_count--;

            char group_hex[17];
            cyxchat_group_id_to_hex(&group_id, group_hex);
            char member_hex[65];
            cyxchat_node_id_to_hex(&member_id, member_hex);
            CYXWIZ_INFO("Member %.16s... left group %s", member_hex, group_hex);

            /* Invoke callback */
            if (ctx->on_member_leave) {
                ctx->on_member_leave(ctx, &group_id, &member_id, 0, ctx->on_member_leave_data);
            }

            /* Auto-rotate key if we're admin and setting is enabled */
            if (ctx->auto_rotate_on_leave) {
                cyxchat_group_role_t our_role = get_role(group, &ctx->local_id);
                if (our_role >= CYXCHAT_ROLE_ADMIN) {
                    CYXWIZ_INFO("Auto-rotating key after member leave (forward secrecy)");
                    cyxchat_group_rotate_key(ctx, &group_id);
                }
            }
            return;
        }
    }

    CYXWIZ_DEBUG("Member not found in group for leave notification");
}

/**
 * Handle incoming GROUP_KICK notification
 */
static void handle_group_kick(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    /* Parse kick wire format */
    cyxchat_group_id_t group_id;
    cyxwiz_node_id_t kicked_member;
    cyxwiz_node_id_t kicked_by;
    uint64_t timestamp;

    size_t parsed = deserialize_group_kick(
        data, len,
        &group_id, &kicked_member, &kicked_by, &timestamp
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_KICK message");
        return;
    }

    /* Find group */
    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group) {
        CYXWIZ_DEBUG("Ignoring kick for unknown group");
        return;
    }

    char group_hex[17];
    cyxchat_group_id_to_hex(&group_id, group_hex);
    char member_hex[65];
    cyxchat_node_id_to_hex(&kicked_member, member_hex);
    char kicked_by_hex[65];
    cyxchat_node_id_to_hex(&kicked_by, kicked_by_hex);
    CYXWIZ_INFO("Member %.16s... kicked from group %s by %.16s...",
                member_hex, group_hex, kicked_by_hex);

    /* Check if we were kicked */
    if (memcmp(kicked_member.bytes, ctx->local_id.bytes, 32) == 0) {
        CYXWIZ_WARN("We were kicked from group %s!", group_hex);
        group->left = 1;
        /* Clear our group key for security */
        cyxwiz_secure_zero(group->group_key, 32);

        /* Invoke callback */
        if (ctx->on_member_leave) {
            ctx->on_member_leave(ctx, &group_id, &kicked_member, 1, ctx->on_member_leave_data);
        }
        return;
    }

    /* Remove kicked member from our list */
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, kicked_member.bytes, 32) == 0) {
            /* Move last member to this slot */
            if (i < group->member_count - 1) {
                memcpy(&group->members[i],
                       &group->members[group->member_count - 1],
                       sizeof(cyxchat_group_member_t));
            }
            group->member_count--;

            /* Invoke callback */
            if (ctx->on_member_leave) {
                ctx->on_member_leave(ctx, &group_id, &kicked_member, 1, ctx->on_member_leave_data);
            }

            /* Auto-rotate key if we're admin, setting is enabled, and we didn't kick them */
            if (ctx->auto_rotate_on_kick) {
                cyxchat_group_role_t our_role = get_role(group, &ctx->local_id);
                int we_kicked = (memcmp(kicked_by.bytes, ctx->local_id.bytes, 32) == 0);
                if (our_role >= CYXCHAT_ROLE_ADMIN && !we_kicked) {
                    CYXWIZ_INFO("Auto-rotating key after kick notification (backup rotation)");
                    cyxchat_group_rotate_key(ctx, &group_id);
                }
            }
            return;
        }
    }
}

/**
 * Handle incoming GROUP_KEY message (key distribution from admin)
 */
static void handle_group_key(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    /* Parse GROUP_KEY wire format */
    cyxchat_group_id_t group_id;
    uint32_t key_version;
    cyxwiz_node_id_t sender_id;
    uint8_t sender_pubkey[32];
    uint8_t encrypted_key[CYXCHAT_ENCRYPTED_KEY_SIZE];

    size_t parsed = deserialize_group_key(
        data, len,
        &group_id, &key_version, &sender_id, sender_pubkey, encrypted_key
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_KEY message");
        return;
    }

    /* Find group */
    cyxchat_group_t *group = find_group(ctx, &group_id);
    if (!group) {
        char group_hex[17];
        cyxchat_group_id_to_hex(&group_id, group_hex);
        CYXWIZ_DEBUG("Received GROUP_KEY for unknown group: %s", group_hex);
        return;
    }

    /* Check if we've left the group */
    if (group->left) {
        CYXWIZ_DEBUG("Ignoring GROUP_KEY for group we've left");
        return;
    }

    /* Verify sender is admin */
    cyxchat_group_role_t sender_role = get_role(group, &sender_id);
    if (sender_role < CYXCHAT_ROLE_ADMIN) {
        char sender_hex[65];
        cyxchat_node_id_to_hex(&sender_id, sender_hex);
        CYXWIZ_WARN("Received GROUP_KEY from non-admin: %.16s...", sender_hex);
        return;
    }

    /* Get onion context early (needed for both decryption and ACK) */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context for GROUP_KEY handling");
        return;
    }

    /* Check key version is newer */
    if (key_version <= group->key_version) {
        CYXWIZ_DEBUG("Received GROUP_KEY with old version %u (current %u)",
                     key_version, group->key_version);
        /* Still send ACK for idempotency */
        goto send_ack;
    }

    /* Compute shared secret via X25519 ECDH with sender */
    uint8_t shared_secret[32];
    cyxwiz_error_t err = cyxwiz_onion_compute_ecdh(
        onion, sender_pubkey, shared_secret
    );
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to compute shared secret for GROUP_KEY");
        return;
    }

    /* Derive decryption key */
    uint8_t dec_key[32];
    err = derive_member_key(shared_secret, &sender_id, &ctx->local_id, dec_key);
    cyxwiz_secure_zero(shared_secret, 32);

    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to derive key for GROUP_KEY decryption");
        return;
    }

    /* Decrypt group key */
    uint8_t new_group_key[32];
    size_t key_len = 0;

    err = cyxwiz_crypto_decrypt(
        encrypted_key, CYXCHAT_ENCRYPTED_KEY_SIZE,
        dec_key, new_group_key, &key_len
    );
    cyxwiz_secure_zero(dec_key, 32);

    if (err != CYXWIZ_OK || key_len != 32) {
        CYXWIZ_ERROR("Failed to decrypt GROUP_KEY: %d", err);
        return;
    }

    /* Apply new key */
    memcpy(group->group_key, new_group_key, 32);
    cyxwiz_secure_zero(new_group_key, 32);
    group->key_version = key_version;
    group->key_updated_at = cyxchat_timestamp_ms();

    {
        char group_hex[17];
        cyxchat_group_id_to_hex(&group_id, group_hex);
        CYXWIZ_INFO("Received and applied GROUP_KEY v%u for group %s",
                    key_version, group_hex);
    }

    /* Notify callback */
    if (ctx->on_key_update) {
        ctx->on_key_update(ctx, &group_id, key_version, ctx->on_key_update_data);
    }

send_ack:
    /* Send ACK back to admin */
    {
        uint8_t ack_wire[GROUP_KEY_ACK_WIRE_SIZE + 10];
        size_t ack_len = serialize_group_key_ack(
            ack_wire, sizeof(ack_wire),
            &group_id, key_version, &ctx->local_id, KEY_ACK_STATUS_APPLIED
        );

        if (ack_len > 0) {
            cyxwiz_error_t ack_err = cyxwiz_onion_send_to(onion, &sender_id, ack_wire, ack_len);
            if (ack_err == CYXWIZ_OK) {
                CYXWIZ_DEBUG("Sent GROUP_KEY_ACK for v%u", key_version);
            }
        }
    }
}

/**
 * Handle incoming GROUP_KEY_ACK message (acknowledgment from member)
 */
static void handle_group_key_ack(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    (void)from;
    /* Parse GROUP_KEY_ACK wire format */
    cyxchat_group_id_t group_id;
    uint32_t key_version;
    cyxwiz_node_id_t member_id;
    uint8_t status;

    size_t parsed = deserialize_group_key_ack(
        data, len,
        &group_id, &key_version, &member_id, &status
    );

    if (parsed == 0) {
        CYXWIZ_WARN("Failed to parse GROUP_KEY_ACK message");
        return;
    }

    char group_hex[17];
    cyxchat_group_id_to_hex(&group_id, group_hex);
    char member_hex[65];
    cyxchat_node_id_to_hex(&member_id, member_hex);

    CYXWIZ_DEBUG("Received GROUP_KEY_ACK v%u from %.16s... (status=%u)",
                 key_version, member_hex, status);

    /* Record ACK for key distribution tracking */
    record_key_dist_ack(ctx, &group_id, key_version, &member_id);
}

/**
 * Handle incoming group message ACK.
 */
static void handle_group_msg_ack(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    /* Wire format: type(1) + flags(1) + msg_id(8) + sender_id(32) + group_id(8) = 50 */
    if (len < 50) {
        CYXWIZ_WARN("Group message ACK too short: %zu", len);
        return;
    }

    uint8_t ack_type = data[0];
    if (ack_type == CYXCHAT_MSG_GROUP_FILE_ACK &&
        handle_group_media_chunk_ack(ctx, from, data, len)) {
        return;
    }

    size_t offset = 2; /* skip type + flags */
    cyxchat_msg_id_t msg_id;
    memcpy(&msg_id, data + offset, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    cyxwiz_node_id_t acker_id;
    memcpy(&acker_id, data + offset, 32);
    offset += 32;

    /* Find pending group message */
    cyxchat_pending_group_msg_t *slot = pending_grp_find_by_msg_id(ctx, &msg_id);
    if (!slot) {
        CYXWIZ_DEBUG("Group ACK 0x%02x for unknown/already-completed message", ack_type);
        return;
    }

    /* Mark member as acked */
    for (size_t m = 0; m < slot->member_count; m++) {
        if (memcmp(&slot->members[m].member_id, &acker_id, 32) == 0) {
            slot->members[m].acked = 1;
            CYXWIZ_DEBUG("Group ACK 0x%02x received from member %zu", ack_type, m);
            break;
        }
    }

    /* Check if all members acked */
    int all_acked = 1;
    for (size_t m = 0; m < slot->member_count; m++) {
        if (!slot->members[m].acked) {
            all_acked = 0;
            break;
        }
    }
    if (all_acked) {
        CYXWIZ_INFO("All group members ACKed message");
        if (ctx->on_delivery) {
            ctx->on_delivery(ctx, &slot->group_id, &slot->msg_id,
                             slot->member_count, slot->member_count,
                             ctx->on_delivery_data);
        }
        pending_grp_free(slot);
    }
}

/**
 * Handle incoming group message (called by chat module)
 */
void cyxchat_group_handle_message(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    uint8_t type,
    const uint8_t *data,
    size_t len
) {
    if (!ctx || !from || !data || len < 1) {
        return;
    }

    CYXWIZ_DEBUG("Group handling message type=0x%02x, len=%zu", type, len);

    switch (type) {
        case CYXCHAT_MSG_GROUP_TEXT:
            handle_group_text(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_FILE:
        case CYXCHAT_MSG_GROUP_VOICE:
        case CYXCHAT_MSG_GROUP_IMAGE:
        case CYXCHAT_MSG_GROUP_VIDEO:
            handle_group_media(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_FILE_CHUNK:
            handle_group_media_chunk(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_INVITE:
            handle_group_invite(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_JOIN:
            handle_group_join(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_LEAVE:
            handle_group_leave(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_KICK:
            handle_group_kick(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_KEY:
            handle_group_key(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_INFO:
            /* TODO: Handle info update */
            CYXWIZ_INFO("Received GROUP_INFO (not yet implemented)");
            break;

        case CYXCHAT_MSG_GROUP_ADMIN:
            /* TODO: Handle admin change */
            CYXWIZ_INFO("Received GROUP_ADMIN (not yet implemented)");
            break;

        case CYXCHAT_MSG_GROUP_KEY_ACK:
            handle_group_key_ack(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_TEXT_ACK:
        case CYXCHAT_MSG_GROUP_FILE_ACK:
            handle_group_msg_ack(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_GROUP_MEMBER_LIST:
            handle_member_list(ctx, from, data, len);
            break;

        default:
            CYXWIZ_WARN("Unknown group message type: 0x%02x", type);
            break;
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

/* ============================================================
 * Admin Permissions & Member Restrictions (Phase 1)
 * ============================================================ */

/**
 * Set admin permissions for a group member
 */
cyxchat_error_t cyxchat_group_set_admin_permissions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin_id,
    uint8_t permissions
) {
    if (!ctx || !group_id || !admin_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only owner can set admin permissions */
    if (memcmp(ctx->local_id.bytes, group->creator.bytes, 32) != 0) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Find the admin member */
    cyxchat_group_member_t *member = NULL;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, admin_id->bytes, 32) == 0) {
            member = &group->members[i];
            break;
        }
    }

    if (!member) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Must be admin to have permissions */
    if (member->role == CYXCHAT_ROLE_MEMBER) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Set permissions */
    member->permissions = permissions;

    CYXWIZ_INFO("Set admin permissions 0x%02x for member", permissions);

    /* TODO: Broadcast permission update to group members */
    /* TODO: Call on_admin_action callback */

    return CYXCHAT_OK;
}

/**
 * Get admin permissions for a group member
 */
uint8_t cyxchat_group_get_admin_permissions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin_id
) {
    if (!ctx || !group_id || !admin_id) {
        return 0;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return 0;
    }

    /* Find the member */
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, admin_id->bytes, 32) == 0) {
            /* Owner has all permissions */
            if (group->members[i].role == CYXCHAT_ROLE_OWNER) {
                return CYXCHAT_PERM_ALL;
            }
            /* Admins have their set permissions */
            if (group->members[i].role == CYXCHAT_ROLE_ADMIN) {
                return group->members[i].permissions;
            }
            /* Regular members have no admin permissions */
            return 0;
        }
    }

    return 0;
}

/**
 * Check if admin has a specific permission
 */
int cyxchat_group_has_permission(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin_id,
    uint8_t permission
) {
    uint8_t perms = cyxchat_group_get_admin_permissions(ctx, group_id, admin_id);
    return (perms & permission) != 0 ? 1 : 0;
}

/**
 * Apply restrictions to a member
 */
cyxchat_error_t cyxchat_group_restrict_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id,
    uint8_t restrictions,
    uint64_t until_ms
) {
    if (!ctx || !group_id || !member_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check if caller has permission to restrict members */
    if (!cyxchat_group_has_permission(ctx, group_id, &ctx->local_id, CYXCHAT_PERM_BAN_USERS)) {
        return CYXCHAT_ERR_NO_PERMISSION;
    }

    /* Find the member */
    cyxchat_group_member_t *member = NULL;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, member_id->bytes, 32) == 0) {
            member = &group->members[i];
            break;
        }
    }

    if (!member) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Cannot restrict owner or admins with manage_admins permission */
    if (member->role == CYXCHAT_ROLE_OWNER) {
        return CYXCHAT_ERR_NO_PERMISSION;
    }
    if (member->role == CYXCHAT_ROLE_ADMIN &&
        (member->permissions & CYXCHAT_PERM_MANAGE_ADMINS)) {
        return CYXCHAT_ERR_NO_PERMISSION;
    }

    /* Apply restrictions */
    member->restrictions = restrictions;
    member->restricted_until = until_ms;

    CYXWIZ_INFO("Applied restrictions 0x%02x to member (until %" PRIu64 ")",
                restrictions, until_ms);

    /* TODO: Broadcast restriction update to group members */
    /* TODO: Call on_admin_action callback */

    return CYXCHAT_OK;
}

/**
 * Remove all restrictions from a member
 */
cyxchat_error_t cyxchat_group_unrestrict_member(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id
) {
    return cyxchat_group_restrict_member(ctx, group_id, member_id, 0, 0);
}

/**
 * Get restrictions for a member
 */
uint8_t cyxchat_group_get_member_restrictions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id,
    uint64_t *until_out
) {
    if (!ctx || !group_id || !member_id) {
        return 0;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return 0;
    }

    /* Find the member */
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, member_id->bytes, 32) == 0) {
            /* Check if restriction has expired */
            if (group->members[i].restricted_until != 0 &&
                cyxchat_timestamp_ms() > group->members[i].restricted_until) {
                if (until_out) *until_out = 0;
                return 0; /* Expired */
            }
            if (until_out) *until_out = group->members[i].restricted_until;
            return group->members[i].restrictions;
        }
    }

    if (until_out) *until_out = 0;
    return 0;
}

/**
 * Check if a member is currently muted
 */
int cyxchat_group_is_member_muted(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member_id
) {
    uint8_t restrictions = cyxchat_group_get_member_restrictions(ctx, group_id, member_id, NULL);
    return (restrictions & CYXCHAT_RESTRICT_MUTED) != 0 ? 1 : 0;
}

/**
 * Set slow mode for the group (seconds between messages)
 */
cyxchat_error_t cyxchat_group_set_slow_mode(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    uint16_t seconds
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check if caller can change group settings */
    if (!cyxchat_group_has_permission(ctx, group_id, &ctx->local_id, CYXCHAT_PERM_CHANGE_INFO)) {
        return CYXCHAT_ERR_NO_PERMISSION;
    }

    group->slow_mode_seconds = seconds;

    CYXWIZ_INFO("Set slow mode to %u seconds", seconds);

    /* TODO: Broadcast slow mode update to group members */

    return CYXCHAT_OK;
}

/**
 * Get slow mode setting for the group
 */
uint16_t cyxchat_group_get_slow_mode(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return 0;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return 0;
    }

    return group->slow_mode_seconds;
}

/**
 * Set who can add members to the group
 */
cyxchat_error_t cyxchat_group_set_who_can_add(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_group_add_setting_t setting
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only owner can change this setting */
    if (memcmp(ctx->local_id.bytes, group->creator.bytes, 32) != 0) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    group->who_can_add = setting;

    CYXWIZ_INFO("Set who_can_add to %d", setting);

    return CYXCHAT_OK;
}

/**
 * Set who can edit group info
 */
cyxchat_error_t cyxchat_group_set_who_can_edit(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_group_edit_setting_t setting
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only owner can change this setting */
    if (memcmp(ctx->local_id.bytes, group->creator.bytes, 32) != 0) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    group->who_can_edit = setting;

    CYXWIZ_INFO("Set who_can_edit to %d", setting);

    return CYXCHAT_OK;
}

/**
 * Set who can send messages
 */
cyxchat_error_t cyxchat_group_set_who_can_send(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_group_send_setting_t setting
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only admin/owner can change this setting */
    if (get_role(group, &ctx->local_id) < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    group->who_can_send = setting;

    CYXWIZ_INFO("Set who_can_send to %d", setting);

    /* TODO: Broadcast settings change to all members */

    return CYXCHAT_OK;
}

/**
 * Get who can send messages setting
 */
cyxchat_group_send_setting_t cyxchat_group_get_who_can_send(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_GROUP_SEND_ALL;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_GROUP_SEND_ALL;
    }

    return group->who_can_send;
}

/**
 * Add member to selected senders list
 */
cyxchat_error_t cyxchat_group_add_selected_sender(
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

    /* Only admin/owner can manage selected senders */
    if (get_role(group, &ctx->local_id) < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Check if already in list */
    for (uint8_t i = 0; i < group->selected_sender_count; i++) {
        if (memcmp(&group->selected_senders[i], member, 32) == 0) {
            return CYXCHAT_OK; /* Already added */
        }
    }

    /* Add to list */
    if (group->selected_sender_count >= CYXCHAT_MAX_GROUP_MEMBERS) {
        return CYXCHAT_ERR_FULL;
    }

    memcpy(&group->selected_senders[group->selected_sender_count], member, 32);
    group->selected_sender_count++;

    CYXWIZ_INFO("Added member to selected senders");

    return CYXCHAT_OK;
}

/**
 * Remove member from selected senders list
 */
cyxchat_error_t cyxchat_group_remove_selected_sender(
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

    /* Only admin/owner can manage selected senders */
    if (get_role(group, &ctx->local_id) < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Find and remove */
    for (uint8_t i = 0; i < group->selected_sender_count; i++) {
        if (memcmp(&group->selected_senders[i], member, 32) == 0) {
            /* Shift remaining elements */
            if (i < group->selected_sender_count - 1) {
                memmove(&group->selected_senders[i],
                        &group->selected_senders[i + 1],
                        (group->selected_sender_count - i - 1) * 32);
            }
            group->selected_sender_count--;
            CYXWIZ_INFO("Removed member from selected senders");
            return CYXCHAT_OK;
        }
    }

    return CYXCHAT_ERR_NOT_FOUND;
}

/**
 * Check if member can send messages
 */
int cyxchat_group_can_send(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *member
) {
    if (!ctx || !group_id || !member) {
        return 0;
    }

    cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return 0;
    }

    /* Check based on setting */
    switch (group->who_can_send) {
        case CYXCHAT_GROUP_SEND_ALL:
            return 1; /* Everyone can send */

        case CYXCHAT_GROUP_SEND_ADMINS:
            /* Only admins and owner can send */
            return get_role(group, member) >= CYXCHAT_ROLE_ADMIN;

        case CYXCHAT_GROUP_SEND_SELECTED:
            /* Admins/owner always can send */
            if (get_role(group, member) >= CYXCHAT_ROLE_ADMIN) {
                return 1;
            }
            /* Check if in selected senders list */
            for (uint8_t i = 0; i < group->selected_sender_count; i++) {
                if (memcmp(&group->selected_senders[i], member, 32) == 0) {
                    return 1;
                }
            }
            return 0;

        default:
            return 1;
    }
}

/**
 * Get group type
 */
cyxchat_group_type_t cyxchat_group_get_type(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_GROUP_TYPE_BASIC;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return CYXCHAT_GROUP_TYPE_BASIC;
    }

    return group->group_type;
}

/**
 * Upgrade a basic group to supergroup
 */
cyxchat_error_t cyxchat_group_upgrade_to_supergroup(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only owner can upgrade */
    if (memcmp(ctx->local_id.bytes, group->creator.bytes, 32) != 0) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Already a supergroup */
    if (group->group_type == CYXCHAT_GROUP_TYPE_SUPERGROUP) {
        return CYXCHAT_OK;
    }

    group->group_type = CYXCHAT_GROUP_TYPE_SUPERGROUP;

    CYXWIZ_INFO("Upgraded group to supergroup");

    /* TODO: Broadcast upgrade notification to members */
    /* TODO: Call on_admin_action callback */

    return CYXCHAT_OK;
}

/**
 * Set admin action callback
 */
void cyxchat_group_set_on_admin_action(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_admin_action_t callback,
    void *user_data
) {
    if (!ctx) return;

    ctx->on_admin_action = callback;
    ctx->on_admin_action_data = user_data;
}

/* ============================================================
 * Message Actions (Phase 2)
 * ============================================================ */

/**
 * Helper: Find pinned messages storage for a group
 */
static int find_pinned_storage_index(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->pinned_messages[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            return (int)i;
        }
    }
    /* Find empty slot */
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        int empty = 1;
        for (int j = 0; j < CYXCHAT_GROUP_ID_SIZE; j++) {
            if (ctx->pinned_messages[i].group_id.bytes[j] != 0) {
                empty = 0;
                break;
            }
        }
        if (empty) {
            memcpy(ctx->pinned_messages[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE);
            ctx->pinned_messages[i].count = 0;
            return (int)i;
        }
    }
    return -1;
}

/**
 * Edit a group message
 */
cyxchat_error_t cyxchat_group_edit_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    const char *new_text,
    size_t new_text_len
) {
    if (!ctx || !group_id || !msg_id || !new_text) {
        return CYXCHAT_ERR_NULL;
    }

    if (new_text_len == 0 || new_text_len > CYXCHAT_MAX_TEXT_LEN) {
        return CYXCHAT_ERR_INVALID;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    if (!is_member(group, &ctx->local_id)) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Note: In a full implementation, we would verify:
     * 1. The caller is the original sender of the message
     * 2. The edit is within the time limit
     * These checks require message storage which is in the Dart layer.
     * Here we broadcast the edit; the Dart layer validates ownership. */

    /* Broadcast edit to all members */
    uint8_t packet[1 + 8 + 8 + 2 + CYXCHAT_MAX_TEXT_LEN + 24 + 16];
    size_t offset = 0;

    packet[offset++] = CYXCHAT_MSG_GROUP_EDIT;

    /* Group ID */
    memcpy(&packet[offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Message ID */
    memcpy(&packet[offset], msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    /* Text length (2 bytes, little-endian) */
    packet[offset++] = (uint8_t)(new_text_len & 0xFF);
    packet[offset++] = (uint8_t)((new_text_len >> 8) & 0xFF);

    /* Text */
    memcpy(&packet[offset], new_text, new_text_len);
    offset += new_text_len;

    /* Encrypt with group key using XChaCha20-Poly1305 */
    uint8_t encrypted[sizeof(packet) + CYXCHAT_CRYPTO_OVERHEAD];
    size_t encrypted_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        &packet[1], offset - 1,
        group->group_key,
        encrypted, &encrypted_len
    );

    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to encrypt group edit message: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Build final packet: type + group_id + key_version + encrypted */
    uint8_t final_packet[1 + 8 + 4 + sizeof(encrypted)];
    size_t final_offset = 0;

    final_packet[final_offset++] = CYXCHAT_MSG_GROUP_EDIT;
    memcpy(&final_packet[final_offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    final_offset += CYXCHAT_GROUP_ID_SIZE;

    /* Key version (4 bytes big-endian) */
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 24) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 16) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 8) & 0xFF);
    final_packet[final_offset++] = (uint8_t)(group->key_version & 0xFF);

    memcpy(&final_packet[final_offset], encrypted, encrypted_len);
    final_offset += encrypted_len;

    /* Get onion context for sending */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context available for group edit");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Send to all members via onion routing */
    int sent_count = 0;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, ctx->local_id.bytes, 32) != 0) {
            err = cyxwiz_onion_send_to(onion, &group->members[i].node_id,
                                       final_packet, final_offset);
            if (err == CYXWIZ_OK) sent_count++;
        }
    }

    CYXWIZ_INFO("Sent edit for message to group (%d members)", sent_count);

    return CYXCHAT_OK;
}

/**
 * Delete a group message
 */
cyxchat_error_t cyxchat_group_delete_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    int delete_for_all
) {
    if (!ctx || !group_id || !msg_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    if (!is_member(group, &ctx->local_id)) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* If deleting for all, need permission (admin with DELETE_MESSAGES or owner of message) */
    /* Actual ownership check is done in Dart layer */

    if (!delete_for_all) {
        /* Delete for self only - no broadcast needed */
        CYXWIZ_INFO("Deleted message for self");
        return CYXCHAT_OK;
    }

    /* Broadcast delete to all members */
    uint8_t packet[1 + 8 + 8 + 1];
    size_t offset = 0;

    packet[offset++] = CYXCHAT_MSG_GROUP_DELETE;

    /* Group ID */
    memcpy(&packet[offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;

    /* Message ID */
    memcpy(&packet[offset], msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    /* Delete for all flag */
    packet[offset++] = delete_for_all ? 1 : 0;

    /* Encrypt with group key */
    uint8_t encrypted[sizeof(packet) + CYXCHAT_CRYPTO_OVERHEAD];
    size_t encrypted_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        &packet[1], offset - 1,
        group->group_key,
        encrypted, &encrypted_len
    );

    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to encrypt group delete message: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Build final packet */
    uint8_t final_packet[1 + 8 + 4 + sizeof(encrypted)];
    size_t final_offset = 0;

    final_packet[final_offset++] = CYXCHAT_MSG_GROUP_DELETE;
    memcpy(&final_packet[final_offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    final_offset += CYXCHAT_GROUP_ID_SIZE;

    final_packet[final_offset++] = (uint8_t)((group->key_version >> 24) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 16) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 8) & 0xFF);
    final_packet[final_offset++] = (uint8_t)(group->key_version & 0xFF);

    memcpy(&final_packet[final_offset], encrypted, encrypted_len);
    final_offset += encrypted_len;

    /* Get onion context for sending */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context available for group delete");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Send to all members via onion routing */
    int sent_count = 0;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, ctx->local_id.bytes, 32) != 0) {
            err = cyxwiz_onion_send_to(onion, &group->members[i].node_id,
                                       final_packet, final_offset);
            if (err == CYXWIZ_OK) sent_count++;
        }
    }

    /* Call admin action callback if admin deleted */
    cyxchat_group_role_t role = get_role(group, &ctx->local_id);
    if (role >= CYXCHAT_ROLE_ADMIN && ctx->on_admin_action) {
        ctx->on_admin_action(ctx, group_id, &ctx->local_id,
                            CYXCHAT_ADMIN_ACTION_MESSAGE_DELETED, NULL,
                            ctx->on_admin_action_data);
    }

    CYXWIZ_INFO("Deleted message for all in group (%d members)", sent_count);

    return CYXCHAT_OK;
}

/**
 * Pin a message in group
 */
cyxchat_error_t cyxchat_group_pin_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id,
    int notify
) {
    if (!ctx || !group_id || !msg_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check admin permission */
    cyxchat_group_role_t role = get_role(group, &ctx->local_id);
    if (role < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Check PIN_MESSAGES permission for admins (owners always have it) */
    if (role == CYXCHAT_ROLE_ADMIN) {
        cyxchat_group_member_t *member = find_member(group, &ctx->local_id);
        if (member && !(member->permissions & CYXCHAT_PERM_PIN_MESSAGES)) {
            return CYXCHAT_ERR_NO_PERMISSION;
        }
    }

    /* Find pinned storage */
    int storage_idx = find_pinned_storage_index(ctx, group_id);
    if (storage_idx < 0) {
        return CYXCHAT_ERR_FULL;
    }

    /* Check if already pinned */
    for (size_t i = 0; i < ctx->pinned_messages[storage_idx].count; i++) {
        if (memcmp(ctx->pinned_messages[storage_idx].msg_ids[i].bytes,
                   msg_id->bytes, CYXCHAT_MSG_ID_SIZE) == 0) {
            return CYXCHAT_ERR_ALREADY_PINNED;
        }
    }

    /* Check limit */
    if (ctx->pinned_messages[storage_idx].count >= CYXCHAT_MAX_PINNED_MESSAGES) {
        return CYXCHAT_ERR_PIN_LIMIT;
    }

    /* Add to pinned list */
    memcpy(ctx->pinned_messages[storage_idx].msg_ids[ctx->pinned_messages[storage_idx].count].bytes,
           msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    ctx->pinned_messages[storage_idx].count++;

    /* Broadcast pin to all members */
    uint8_t packet[1 + 8 + 8 + 1];
    size_t offset = 0;

    packet[offset++] = CYXCHAT_MSG_GROUP_PIN;
    memcpy(&packet[offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    memcpy(&packet[offset], msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;
    packet[offset++] = notify ? 1 : 0;

    /* Encrypt with group key */
    uint8_t encrypted[sizeof(packet) + CYXCHAT_CRYPTO_OVERHEAD];
    size_t encrypted_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        &packet[1], offset - 1,
        group->group_key,
        encrypted, &encrypted_len
    );

    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to encrypt group pin message: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    uint8_t final_packet[1 + 8 + 4 + sizeof(encrypted)];
    size_t final_offset = 0;

    final_packet[final_offset++] = CYXCHAT_MSG_GROUP_PIN;
    memcpy(&final_packet[final_offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    final_offset += CYXCHAT_GROUP_ID_SIZE;

    final_packet[final_offset++] = (uint8_t)((group->key_version >> 24) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 16) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 8) & 0xFF);
    final_packet[final_offset++] = (uint8_t)(group->key_version & 0xFF);

    memcpy(&final_packet[final_offset], encrypted, encrypted_len);
    final_offset += encrypted_len;

    /* Get onion context for sending */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context available for group pin");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Send to all members via onion routing */
    int sent_count = 0;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, ctx->local_id.bytes, 32) != 0) {
            err = cyxwiz_onion_send_to(onion, &group->members[i].node_id,
                                       final_packet, final_offset);
            if (err == CYXWIZ_OK) sent_count++;
        }
    }

    /* Call callbacks */
    if (ctx->on_message_pin) {
        ctx->on_message_pin(ctx, group_id, msg_id, &ctx->local_id, 1,
                           ctx->on_message_pin_data);
    }
    if (ctx->on_admin_action) {
        ctx->on_admin_action(ctx, group_id, &ctx->local_id,
                            CYXCHAT_ADMIN_ACTION_MESSAGE_PINNED, NULL,
                            ctx->on_admin_action_data);
    }

    CYXWIZ_INFO("Pinned message in group");

    return CYXCHAT_OK;
}

/**
 * Unpin a message
 */
cyxchat_error_t cyxchat_group_unpin_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id
) {
    if (!ctx || !group_id || !msg_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Check admin permission */
    cyxchat_group_role_t role = get_role(group, &ctx->local_id);
    if (role < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    if (role == CYXCHAT_ROLE_ADMIN) {
        cyxchat_group_member_t *member = find_member(group, &ctx->local_id);
        if (member && !(member->permissions & CYXCHAT_PERM_PIN_MESSAGES)) {
            return CYXCHAT_ERR_NO_PERMISSION;
        }
    }

    /* Find pinned storage */
    int storage_idx = find_pinned_storage_index(ctx, group_id);
    if (storage_idx < 0) {
        return CYXCHAT_ERR_NOT_PINNED;
    }

    /* Find and remove from pinned list */
    int found = -1;
    for (size_t i = 0; i < ctx->pinned_messages[storage_idx].count; i++) {
        if (memcmp(ctx->pinned_messages[storage_idx].msg_ids[i].bytes,
                   msg_id->bytes, CYXCHAT_MSG_ID_SIZE) == 0) {
            found = (int)i;
            break;
        }
    }

    if (found < 0) {
        return CYXCHAT_ERR_NOT_PINNED;
    }

    /* Remove by shifting */
    for (size_t i = found; i < ctx->pinned_messages[storage_idx].count - 1; i++) {
        memcpy(ctx->pinned_messages[storage_idx].msg_ids[i].bytes,
               ctx->pinned_messages[storage_idx].msg_ids[i + 1].bytes,
               CYXCHAT_MSG_ID_SIZE);
    }
    ctx->pinned_messages[storage_idx].count--;

    /* Broadcast unpin */
    uint8_t packet[1 + 8 + 8];
    size_t offset = 0;

    packet[offset++] = CYXCHAT_MSG_GROUP_UNPIN;
    memcpy(&packet[offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    memcpy(&packet[offset], msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    /* Encrypt with group key */
    uint8_t encrypted[sizeof(packet) + CYXCHAT_CRYPTO_OVERHEAD];
    size_t encrypted_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        &packet[1], offset - 1,
        group->group_key,
        encrypted, &encrypted_len
    );

    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to encrypt group unpin message: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    uint8_t final_packet[1 + 8 + 4 + sizeof(encrypted)];
    size_t final_offset = 0;

    final_packet[final_offset++] = CYXCHAT_MSG_GROUP_UNPIN;
    memcpy(&final_packet[final_offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    final_offset += CYXCHAT_GROUP_ID_SIZE;

    final_packet[final_offset++] = (uint8_t)((group->key_version >> 24) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 16) & 0xFF);
    final_packet[final_offset++] = (uint8_t)((group->key_version >> 8) & 0xFF);
    final_packet[final_offset++] = (uint8_t)(group->key_version & 0xFF);

    memcpy(&final_packet[final_offset], encrypted, encrypted_len);
    final_offset += encrypted_len;

    /* Get onion context for sending */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context available for group unpin");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Send to all members via onion routing */
    int sent_count = 0;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, ctx->local_id.bytes, 32) != 0) {
            err = cyxwiz_onion_send_to(onion, &group->members[i].node_id,
                                       final_packet, final_offset);
            if (err == CYXWIZ_OK) sent_count++;
        }
    }

    /* Call callbacks */
    if (ctx->on_message_pin) {
        ctx->on_message_pin(ctx, group_id, msg_id, &ctx->local_id, 0,
                           ctx->on_message_pin_data);
    }
    if (ctx->on_admin_action) {
        ctx->on_admin_action(ctx, group_id, &ctx->local_id,
                            CYXCHAT_ADMIN_ACTION_MESSAGE_UNPINNED, NULL,
                            ctx->on_admin_action_data);
    }

    CYXWIZ_INFO("Unpinned message in group");

    return CYXCHAT_OK;
}

/**
 * Unpin all messages
 */
cyxchat_error_t cyxchat_group_unpin_all(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    cyxchat_group_role_t role = get_role(group, &ctx->local_id);
    if (role < CYXCHAT_ROLE_ADMIN) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    int storage_idx = find_pinned_storage_index(ctx, group_id);
    if (storage_idx >= 0) {
        ctx->pinned_messages[storage_idx].count = 0;
    }

    CYXWIZ_INFO("Unpinned all messages in group");

    return CYXCHAT_OK;
}

/**
 * Get pinned message count
 */
size_t cyxchat_group_get_pinned_count(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return 0;
    }

    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->pinned_messages[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            return ctx->pinned_messages[i].count;
        }
    }
    return 0;
}

/**
 * Get pinned message IDs
 */
size_t cyxchat_group_get_pinned_messages(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_msg_id_t *msg_ids_out,
    size_t max_count
) {
    if (!ctx || !group_id || !msg_ids_out || max_count == 0) {
        return 0;
    }

    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->pinned_messages[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            size_t count = ctx->pinned_messages[i].count;
            if (count > max_count) count = max_count;
            for (size_t j = 0; j < count; j++) {
                memcpy(msg_ids_out[j].bytes,
                       ctx->pinned_messages[i].msg_ids[j].bytes,
                       CYXCHAT_MSG_ID_SIZE);
            }
            return count;
        }
    }
    return 0;
}

/**
 * Check if message is pinned
 */
int cyxchat_group_is_message_pinned(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxchat_msg_id_t *msg_id
) {
    if (!ctx || !group_id || !msg_id) {
        return 0;
    }

    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->pinned_messages[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            for (size_t j = 0; j < ctx->pinned_messages[i].count; j++) {
                if (memcmp(ctx->pinned_messages[i].msg_ids[j].bytes,
                           msg_id->bytes, CYXCHAT_MSG_ID_SIZE) == 0) {
                    return 1;
                }
            }
            break;
        }
    }
    return 0;
}

/**
 * Forward a message to another group
 */
cyxchat_error_t cyxchat_group_forward_message(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *from_group_id,
    const cyxchat_group_id_t *to_group_id,
    const cyxchat_msg_id_t *msg_id,
    cyxchat_msg_id_t *new_msg_id_out
) {
    if (!ctx || !from_group_id || !to_group_id || !msg_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Note: The actual message content is not stored in the C layer.
     * This function broadcasts a forward notification.
     * The Dart layer fetches the original message content and creates
     * a new message with the forward flag set. */

    cyxchat_group_t *to_group = find_group(ctx, to_group_id);
    if (!to_group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    if (!is_member(to_group, &ctx->local_id)) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    /* Generate new message ID */
    cyxchat_msg_id_t new_id;
    cyxwiz_crypto_random(new_id.bytes, CYXCHAT_MSG_ID_SIZE);

    if (new_msg_id_out) {
        memcpy(new_msg_id_out->bytes, new_id.bytes, CYXCHAT_MSG_ID_SIZE);
    }

    CYXWIZ_INFO("Forward message prepared (actual forward handled in Dart layer)");

    return CYXCHAT_OK;
}

/**
 * Set message edit callback
 */
void cyxchat_group_set_on_message_edit(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_message_edit_t callback,
    void *user_data
) {
    if (!ctx) return;

    ctx->on_message_edit = callback;
    ctx->on_message_edit_data = user_data;
}

/**
 * Set message delete callback
 */
void cyxchat_group_set_on_message_delete(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_message_delete_t callback,
    void *user_data
) {
    if (!ctx) return;

    ctx->on_message_delete = callback;
    ctx->on_message_delete_data = user_data;
}

/**
 * Set message pin callback
 */
void cyxchat_group_set_on_message_pin(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_message_pin_t callback,
    void *user_data
) {
    if (!ctx) return;

    ctx->on_message_pin = callback;
    ctx->on_message_pin_data = user_data;
}

/* ============================================================
 * Invite Link Functions (Phase 3)
 * ============================================================ */

/**
 * Helper to find invite links storage for a group
 */
static int find_invite_links_index(cyxchat_group_ctx_t *ctx,
                                   const cyxchat_group_id_t *group_id) {
    /* Find existing entry */
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (ctx->invite_links[i].count > 0 &&
            memcmp(ctx->invite_links[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            return (int)i;
        }
    }

    /* Find empty slot */
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (ctx->invite_links[i].count == 0) {
            memcpy(ctx->invite_links[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE);
            return (int)i;
        }
    }

    return -1;
}

/**
 * Create an invite link for a group
 */
cyxchat_error_t cyxchat_group_create_invite_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *name,
    uint64_t expires_at_ms,
    uint32_t max_uses,
    cyxchat_invite_link_t *link_out
) {
    if (!ctx || !group_id || !link_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Find group and verify we have permission */
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only admins can create invite links */
    cyxchat_group_member_t *self = find_member(group, &ctx->local_id);
    if (!self || self->role == CYXCHAT_ROLE_MEMBER) {
        return CYXCHAT_ERR_NO_PERMISSION;
    }

    /* Find storage slot */
    int idx = find_invite_links_index(ctx, group_id);
    if (idx < 0) {
        return CYXCHAT_ERR_FULL;
    }

    /* Check if we have room for more links */
    if (ctx->invite_links[idx].count >= CYXCHAT_MAX_INVITE_LINKS) {
        return CYXCHAT_ERR_FULL;
    }

    /* Generate random link ID */
    cyxchat_invite_link_t link;
    memset(&link, 0, sizeof(link));
    cyxwiz_crypto_random(link.link_id, CYXCHAT_INVITE_LINK_ID_SIZE);

    /* Fill in link details */
    memcpy(link.group_id, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    memcpy(link.creator_id, ctx->local_id.bytes, CYXCHAT_NODE_ID_SIZE);
    link.created_at = cyxchat_timestamp_ms();
    link.expires_at = expires_at_ms;
    link.max_uses = max_uses;
    link.use_count = 0;
    link.is_revoked = 0;

    if (name) {
        strncpy(link.name, name, CYXCHAT_INVITE_LINK_NAME_LEN - 1);
        link.name[CYXCHAT_INVITE_LINK_NAME_LEN - 1] = '\0';
    }

    /* Store the link */
    ctx->invite_links[idx].links[ctx->invite_links[idx].count] = link;
    ctx->invite_links[idx].count++;

    /* Broadcast to group members */
    uint8_t packet[256];
    size_t offset = 0;

    packet[offset++] = CYXCHAT_MSG_INVITE_LINK;
    memcpy(&packet[offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    memcpy(&packet[offset], link.link_id, CYXCHAT_INVITE_LINK_ID_SIZE);
    offset += CYXCHAT_INVITE_LINK_ID_SIZE;

    /* Encode expiry and max_uses */
    memcpy(&packet[offset], &link.expires_at, 8);
    offset += 8;
    memcpy(&packet[offset], &link.max_uses, 4);
    offset += 4;

    /* Encode name length and name */
    size_t name_len = name ? strlen(link.name) : 0;
    packet[offset++] = (uint8_t)name_len;
    if (name_len > 0) {
        memcpy(&packet[offset], link.name, name_len);
        offset += name_len;
    }

    /* Encrypt and send to all members */
    uint8_t encrypted[sizeof(packet) + CYXCHAT_CRYPTO_OVERHEAD];
    size_t encrypted_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        &packet[1], offset - 1,
        group->group_key,
        encrypted, &encrypted_len
    );
    if (err != CYXWIZ_OK) {
        return CYXCHAT_ERR_CRYPTO;
    }

    /* Build final packet */
    uint8_t final_packet[sizeof(encrypted) + 1];
    final_packet[0] = CYXCHAT_MSG_INVITE_LINK;
    memcpy(&final_packet[1], encrypted, encrypted_len);
    size_t final_len = 1 + encrypted_len;

    /* Get onion context */
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        return CYXCHAT_ERR_NETWORK;
    }

    /* Send to all members */
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(group->members[i].node_id.bytes, ctx->local_id.bytes, 32) != 0) {
            cyxwiz_onion_send_to(onion, &group->members[i].node_id,
                                final_packet, final_len);
        }
    }

    /* Callback */
    if (ctx->on_invite_link) {
        ctx->on_invite_link(ctx, group_id, &link, 0, ctx->on_invite_link_data);
    }

    *link_out = link;
    return CYXCHAT_OK;
}

/**
 * Revoke an invite link
 */
cyxchat_error_t cyxchat_group_revoke_invite_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *link_id
) {
    if (!ctx || !group_id || !link_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Find group */
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Only admins can revoke links */
    cyxchat_group_member_t *self = find_member(group, &ctx->local_id);
    if (!self || self->role == CYXCHAT_ROLE_MEMBER) {
        return CYXCHAT_ERR_NO_PERMISSION;
    }

    /* Find link storage */
    int idx = find_invite_links_index(ctx, group_id);
    if (idx < 0) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Find the link */
    cyxchat_invite_link_t *link = NULL;
    for (size_t i = 0; i < ctx->invite_links[idx].count; i++) {
        if (memcmp(ctx->invite_links[idx].links[i].link_id, link_id,
                   CYXCHAT_INVITE_LINK_ID_SIZE) == 0) {
            link = &ctx->invite_links[idx].links[i];
            break;
        }
    }

    if (!link) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Mark as revoked */
    link->is_revoked = 1;

    /* Broadcast revocation */
    uint8_t packet[64];
    size_t offset = 0;

    packet[offset++] = CYXCHAT_MSG_INVITE_REVOKE;
    memcpy(&packet[offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    memcpy(&packet[offset], link_id, CYXCHAT_INVITE_LINK_ID_SIZE);
    offset += CYXCHAT_INVITE_LINK_ID_SIZE;

    /* Encrypt */
    uint8_t encrypted[sizeof(packet) + CYXCHAT_CRYPTO_OVERHEAD];
    size_t encrypted_len = 0;

    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        &packet[1], offset - 1,
        group->group_key,
        encrypted, &encrypted_len
    );
    if (err != CYXWIZ_OK) {
        return CYXCHAT_ERR_CRYPTO;
    }

    uint8_t final_packet[sizeof(encrypted) + 1];
    final_packet[0] = CYXCHAT_MSG_INVITE_REVOKE;
    memcpy(&final_packet[1], encrypted, encrypted_len);
    size_t final_len = 1 + encrypted_len;

    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (onion) {
        for (uint8_t i = 0; i < group->member_count; i++) {
            if (memcmp(group->members[i].node_id.bytes, ctx->local_id.bytes, 32) != 0) {
                cyxwiz_onion_send_to(onion, &group->members[i].node_id,
                                    final_packet, final_len);
            }
        }
    }

    /* Callback */
    if (ctx->on_invite_link) {
        ctx->on_invite_link(ctx, group_id, link, 1, ctx->on_invite_link_data);
    }

    return CYXCHAT_OK;
}

/**
 * Join a group via invite link
 */
cyxchat_error_t cyxchat_group_join_via_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *link_id
) {
    if (!ctx || !group_id || !link_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Build join request packet */
    uint8_t packet[64];
    size_t offset = 0;

    packet[offset++] = CYXCHAT_MSG_INVITE_JOIN;
    memcpy(&packet[offset], group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    offset += CYXCHAT_GROUP_ID_SIZE;
    memcpy(&packet[offset], link_id, CYXCHAT_INVITE_LINK_ID_SIZE);
    offset += CYXCHAT_INVITE_LINK_ID_SIZE;
    memcpy(&packet[offset], ctx->local_id.bytes, CYXCHAT_NODE_ID_SIZE);
    offset += CYXCHAT_NODE_ID_SIZE;

    /* Get our public key to include */
    uint8_t pubkey[32];
    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (onion) {
        cyxwiz_onion_get_pubkey(onion, pubkey);
        memcpy(&packet[offset], pubkey, 32);
        offset += 32;
    }

    /* Note: This packet is sent unencrypted because we don't have the group key yet.
     * The join request should be sent to a known member or via bootstrap server.
     * The receiving admin will validate the link and send back the group info + key. */

    return CYXCHAT_OK;
}

/**
 * Get all invite links for a group
 */
cyxchat_error_t cyxchat_group_get_invite_links(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_invite_link_t *links_out,
    size_t max_links,
    size_t *count_out
) {
    if (!ctx || !group_id || !links_out || !count_out) {
        return CYXCHAT_ERR_NULL;
    }

    *count_out = 0;

    /* Find link storage */
    int idx = find_invite_links_index(ctx, group_id);
    if (idx < 0 || ctx->invite_links[idx].count == 0) {
        return CYXCHAT_OK; /* No links, but not an error */
    }

    /* Copy links (excluding revoked) */
    size_t copied = 0;
    for (size_t i = 0; i < ctx->invite_links[idx].count && copied < max_links; i++) {
        cyxchat_invite_link_t *link = &ctx->invite_links[idx].links[i];

        /* Skip revoked links */
        if (link->is_revoked) continue;

        /* Skip expired links */
        if (link->expires_at > 0 && link->expires_at < cyxchat_timestamp_ms()) continue;

        /* Skip maxed-out links */
        if (link->max_uses > 0 && link->use_count >= link->max_uses) continue;

        links_out[copied++] = *link;
    }

    *count_out = copied;
    return CYXCHAT_OK;
}

/**
 * Get a specific invite link
 */
cyxchat_error_t cyxchat_group_get_invite_link(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *link_id,
    cyxchat_invite_link_t *link_out
) {
    if (!ctx || !group_id || !link_id || !link_out) {
        return CYXCHAT_ERR_NULL;
    }

    int idx = find_invite_links_index(ctx, group_id);
    if (idx < 0) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    for (size_t i = 0; i < ctx->invite_links[idx].count; i++) {
        if (memcmp(ctx->invite_links[idx].links[i].link_id, link_id,
                   CYXCHAT_INVITE_LINK_ID_SIZE) == 0) {
            *link_out = ctx->invite_links[idx].links[i];
            return CYXCHAT_OK;
        }
    }

    CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
}

/**
 * Generate URL for an invite link
 * Format: cyxchat://join/<group_id_hex>/<link_id_hex>
 */
cyxchat_error_t cyxchat_group_invite_link_to_url(
    const cyxchat_invite_link_t *link,
    char *url_out,
    size_t url_size
) {
    if (!link || !url_out || url_size == 0) {
        return CYXCHAT_ERR_NULL;
    }

    /* Need: "cyxchat://join/" (15) + group_id_hex (32) + "/" (1) + link_id_hex (32) + null */
    if (url_size < 81) {
        return CYXCHAT_ERR_INVALID;
    }

    char group_hex[33];
    char link_hex[33];

    /* Convert to hex */
    for (int i = 0; i < CYXCHAT_GROUP_ID_SIZE; i++) {
        sprintf(&group_hex[i * 2], "%02x", link->group_id[i]);
    }
    group_hex[32] = '\0';

    for (int i = 0; i < CYXCHAT_INVITE_LINK_ID_SIZE; i++) {
        sprintf(&link_hex[i * 2], "%02x", link->link_id[i]);
    }
    link_hex[32] = '\0';

    snprintf(url_out, url_size, "cyxchat://join/%s/%s", group_hex, link_hex);
    return CYXCHAT_OK;
}

/**
 * Parse an invite URL
 */
cyxchat_error_t cyxchat_group_parse_invite_url(
    const char *url,
    cyxchat_group_id_t *group_id_out,
    uint8_t *link_id_out
) {
    if (!url || !group_id_out || !link_id_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check prefix */
    const char *prefix = "cyxchat://join/";
    if (strncmp(url, prefix, strlen(prefix)) != 0) {
        return CYXCHAT_ERR_INVALID;
    }

    const char *pos = url + strlen(prefix);

    /* Parse group ID (32 hex chars) */
    if (strlen(pos) < 33) { /* 32 + at least "/" */
        return CYXCHAT_ERR_INVALID;
    }

    for (int i = 0; i < CYXCHAT_GROUP_ID_SIZE; i++) {
        unsigned int byte;
        if (sscanf(&pos[i * 2], "%2x", &byte) != 1) {
            return CYXCHAT_ERR_INVALID;
        }
        group_id_out->bytes[i] = (uint8_t)byte;
    }

    pos += 32;
    if (*pos != '/') {
        return CYXCHAT_ERR_INVALID;
    }
    pos++;

    /* Parse link ID (32 hex chars) */
    if (strlen(pos) < 32) {
        return CYXCHAT_ERR_INVALID;
    }

    for (int i = 0; i < CYXCHAT_INVITE_LINK_ID_SIZE; i++) {
        unsigned int byte;
        if (sscanf(&pos[i * 2], "%2x", &byte) != 1) {
            return CYXCHAT_ERR_INVALID;
        }
        link_id_out[i] = (uint8_t)byte;
    }

    return CYXCHAT_OK;
}

/**
 * Set invite link callback
 */
void cyxchat_group_set_on_invite_link(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_invite_link_t callback,
    void *user_data
) {
    if (!ctx) return;

    ctx->on_invite_link = callback;
    ctx->on_invite_link_data = user_data;
}

/**
 * Set join via link callback
 */
void cyxchat_group_set_on_join_via_link(
    cyxchat_group_ctx_t *ctx,
    cyxchat_on_join_via_link_t callback,
    void *user_data
) {
    if (!ctx) return;

    ctx->on_join_via_link = callback;
    ctx->on_join_via_link_data = user_data;
}

/* ============================================================
 * Admin Action Log Implementation (Phase 4)
 * ============================================================ */

/**
 * Find or create admin action storage for a group
 */
static int find_admin_action_storage_index(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    /* First, look for existing storage */
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->admin_actions[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0 && ctx->admin_actions[i].count > 0) {
            return (int)i;
        }
    }

    /* Find empty slot */
    static const uint8_t zero_id[CYXCHAT_GROUP_ID_SIZE] = {0};
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->admin_actions[i].group_id.bytes, zero_id,
                   CYXCHAT_GROUP_ID_SIZE) == 0 || ctx->admin_actions[i].count == 0) {
            memcpy(ctx->admin_actions[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE);
            ctx->admin_actions[i].count = 0;
            ctx->admin_actions[i].write_index = 0;
            return (int)i;
        }
    }

    return -1;  /* No space */
}

/**
 * Log an admin action
 */
cyxchat_error_t cyxchat_group_log_admin_action(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_admin_action_type_t action_type,
    const cyxwiz_node_id_t *target_id,
    const cyxchat_msg_id_t *target_msg_id,
    const char *old_value,
    const char *new_value,
    cyxchat_admin_action_t *action_out
) {
    if (!ctx || !group_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Verify group exists and we are admin */
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    cyxchat_group_member_t *self = find_member(group, &ctx->local_id);
    if (!self || (self->role != CYXCHAT_ROLE_ADMIN && self->role != CYXCHAT_ROLE_OWNER)) {
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    /* Find storage for this group */
    int storage_idx = find_admin_action_storage_index(ctx, group_id);
    if (storage_idx < 0) {
        return CYXCHAT_ERR_FULL;
    }

    /* Create the action entry */
    cyxchat_admin_action_t action;
    memset(&action, 0, sizeof(action));

    /* Generate random action ID */
    cyxwiz_crypto_random(action.action_id, CYXCHAT_ADMIN_ACTION_ID_SIZE);

    /* Copy group ID */
    memcpy(action.group_id, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);

    /* Set admin ID to our ID */
    memcpy(action.admin_id, ctx->local_id.bytes, CYXCHAT_NODE_ID_SIZE);

    /* Set action type */
    action.action_type = action_type;

    /* Copy target ID if provided */
    if (target_id) {
        memcpy(action.target_id, target_id->bytes, CYXCHAT_NODE_ID_SIZE);
    }

    /* Copy target message ID if provided */
    if (target_msg_id) {
        memcpy(action.target_msg_id, target_msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    }

    /* Set timestamp */
    action.timestamp = cyxchat_timestamp_ms();

    /* Copy old value if provided */
    if (old_value) {
        strncpy(action.old_value, old_value, CYXCHAT_ADMIN_ACTION_VALUE_LEN - 1);
        action.old_value[CYXCHAT_ADMIN_ACTION_VALUE_LEN - 1] = '\0';
    }

    /* Copy new value if provided */
    if (new_value) {
        strncpy(action.new_value, new_value, CYXCHAT_ADMIN_ACTION_VALUE_LEN - 1);
        action.new_value[CYXCHAT_ADMIN_ACTION_VALUE_LEN - 1] = '\0';
    }

    /* Store in circular buffer */
    size_t idx = ctx->admin_actions[storage_idx].write_index;
    memcpy(&ctx->admin_actions[storage_idx].actions[idx], &action, sizeof(action));

    /* Update indices */
    ctx->admin_actions[storage_idx].write_index =
        (ctx->admin_actions[storage_idx].write_index + 1) % CYXCHAT_MAX_ADMIN_ACTIONS;

    if (ctx->admin_actions[storage_idx].count < CYXCHAT_MAX_ADMIN_ACTIONS) {
        ctx->admin_actions[storage_idx].count++;
    }

    /* Return action if requested */
    if (action_out) {
        memcpy(action_out, &action, sizeof(action));
    }

    CYXWIZ_INFO("Admin action logged: type=%d, group=%02x%02x...",
                action_type, group_id->bytes[0], group_id->bytes[1]);

    return CYXCHAT_OK;
}

/**
 * Get admin actions for a group
 */
cyxchat_error_t cyxchat_group_get_admin_actions(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    cyxchat_admin_action_t *actions_out,
    size_t max_actions,
    size_t offset,
    size_t *count_out
) {
    if (!ctx || !group_id || !actions_out || !count_out) {
        return CYXCHAT_ERR_NULL;
    }

    *count_out = 0;

    /* Find storage for this group */
    int storage_idx = -1;
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->admin_actions[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            storage_idx = (int)i;
            break;
        }
    }

    if (storage_idx < 0 || ctx->admin_actions[storage_idx].count == 0) {
        return CYXCHAT_OK;  /* No actions, return empty */
    }

    size_t total = ctx->admin_actions[storage_idx].count;
    if (offset >= total) {
        return CYXCHAT_OK;  /* Offset past end */
    }

    size_t available = total - offset;
    size_t to_copy = (available < max_actions) ? available : max_actions;

    /* Copy actions in reverse order (most recent first) */
    for (size_t i = 0; i < to_copy; i++) {
        size_t read_idx;
        if (ctx->admin_actions[storage_idx].count < CYXCHAT_MAX_ADMIN_ACTIONS) {
            /* Buffer not full, simple indexing */
            read_idx = ctx->admin_actions[storage_idx].count - 1 - offset - i;
        } else {
            /* Circular buffer full, calculate from write_index */
            read_idx = (ctx->admin_actions[storage_idx].write_index +
                       CYXCHAT_MAX_ADMIN_ACTIONS - 1 - offset - i) % CYXCHAT_MAX_ADMIN_ACTIONS;
        }
        memcpy(&actions_out[i],
               &ctx->admin_actions[storage_idx].actions[read_idx],
               sizeof(cyxchat_admin_action_t));
    }

    *count_out = to_copy;
    return CYXCHAT_OK;
}

/**
 * Get admin actions by a specific admin
 */
cyxchat_error_t cyxchat_group_get_admin_actions_by_admin(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const cyxwiz_node_id_t *admin_id,
    cyxchat_admin_action_t *actions_out,
    size_t max_actions,
    size_t *count_out
) {
    if (!ctx || !group_id || !admin_id || !actions_out || !count_out) {
        return CYXCHAT_ERR_NULL;
    }

    *count_out = 0;

    /* Find storage for this group */
    int storage_idx = -1;
    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->admin_actions[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            storage_idx = (int)i;
            break;
        }
    }

    if (storage_idx < 0 || ctx->admin_actions[storage_idx].count == 0) {
        return CYXCHAT_OK;
    }

    size_t found = 0;
    size_t total = ctx->admin_actions[storage_idx].count;

    /* Iterate through actions and filter by admin */
    for (size_t i = 0; i < total && found < max_actions; i++) {
        size_t read_idx;
        if (total < CYXCHAT_MAX_ADMIN_ACTIONS) {
            read_idx = total - 1 - i;
        } else {
            read_idx = (ctx->admin_actions[storage_idx].write_index +
                       CYXCHAT_MAX_ADMIN_ACTIONS - 1 - i) % CYXCHAT_MAX_ADMIN_ACTIONS;
        }

        cyxchat_admin_action_t *action = &ctx->admin_actions[storage_idx].actions[read_idx];
        if (memcmp(action->admin_id, admin_id->bytes, CYXCHAT_NODE_ID_SIZE) == 0) {
            memcpy(&actions_out[found], action, sizeof(cyxchat_admin_action_t));
            found++;
        }
    }

    *count_out = found;
    return CYXCHAT_OK;
}

/**
 * Get total count of admin actions
 */
size_t cyxchat_group_get_admin_action_count(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id
) {
    if (!ctx || !group_id) {
        return 0;
    }

    for (size_t i = 0; i < CYXCHAT_MAX_GROUPS; i++) {
        if (memcmp(ctx->admin_actions[i].group_id.bytes, group_id->bytes,
                   CYXCHAT_GROUP_ID_SIZE) == 0) {
            return ctx->admin_actions[i].count;
        }
    }

    return 0;
}

/**
 * Get a specific admin action by ID
 */
cyxchat_error_t cyxchat_group_get_admin_action(
    cyxchat_group_ctx_t *ctx,
    const uint8_t *action_id,
    cyxchat_admin_action_t *action_out
) {
    if (!ctx || !action_id || !action_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Search all group storages */
    for (size_t g = 0; g < CYXCHAT_MAX_GROUPS; g++) {
        if (ctx->admin_actions[g].count == 0) continue;

        for (size_t i = 0; i < ctx->admin_actions[g].count; i++) {
            if (memcmp(ctx->admin_actions[g].actions[i].action_id, action_id,
                       CYXCHAT_ADMIN_ACTION_ID_SIZE) == 0) {
                memcpy(action_out, &ctx->admin_actions[g].actions[i],
                       sizeof(cyxchat_admin_action_t));
                return CYXCHAT_OK;
            }
        }
    }

    CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
}

/**
 * Convert admin action ID to hex string
 */
void cyxchat_admin_action_id_to_hex(
    const uint8_t *action_id,
    char *hex_out
) {
    if (!action_id || !hex_out) return;

    for (int i = 0; i < CYXCHAT_ADMIN_ACTION_ID_SIZE; i++) {
        sprintf(&hex_out[i * 2], "%02x", action_id[i]);
    }
    hex_out[CYXCHAT_ADMIN_ACTION_ID_SIZE * 2] = '\0';
}

/**
 * Parse admin action ID from hex string
 */
cyxchat_error_t cyxchat_admin_action_id_from_hex(
    const char *hex,
    uint8_t *action_id_out
) {
    if (!hex || !action_id_out) {
        return CYXCHAT_ERR_NULL;
    }

    if (strlen(hex) < CYXCHAT_ADMIN_ACTION_ID_SIZE * 2) {
        return CYXCHAT_ERR_INVALID;
    }

    for (int i = 0; i < CYXCHAT_ADMIN_ACTION_ID_SIZE; i++) {
        unsigned int byte;
        if (sscanf(&hex[i * 2], "%2x", &byte) != 1) {
            return CYXCHAT_ERR_INVALID;
        }
        action_id_out[i] = (uint8_t)byte;
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Group Media/File Sharing (Phase 5)
 * ============================================================ */

/**
 * Determine media type from MIME type string
 */
static cyxchat_media_type_t get_media_type_from_mime(const char *mime_type) {
    if (!mime_type) return CYXCHAT_MEDIA_TYPE_OTHER;

    if (strncmp(mime_type, "image/", 6) == 0) {
        return CYXCHAT_MEDIA_TYPE_IMAGE;
    } else if (strncmp(mime_type, "video/", 6) == 0) {
        return CYXCHAT_MEDIA_TYPE_VIDEO;
    } else if (strncmp(mime_type, "audio/", 6) == 0) {
        // Check if it's a voice message (opus)
        if (strstr(mime_type, "opus") != NULL || strstr(mime_type, "ogg") != NULL) {
            return CYXCHAT_MEDIA_TYPE_VOICE;
        }
        return CYXCHAT_MEDIA_TYPE_AUDIO;
    } else if (strncmp(mime_type, "application/pdf", 15) == 0 ||
               strncmp(mime_type, "application/msword", 18) == 0 ||
               strstr(mime_type, "document") != NULL ||
               strstr(mime_type, "text") != NULL) {
        return CYXCHAT_MEDIA_TYPE_DOCUMENT;
    } else if (strstr(mime_type, "zip") != NULL ||
               strstr(mime_type, "rar") != NULL ||
               strstr(mime_type, "tar") != NULL ||
               strstr(mime_type, "7z") != NULL ||
               strstr(mime_type, "gzip") != NULL) {
        return CYXCHAT_MEDIA_TYPE_ARCHIVE;
    }

    return CYXCHAT_MEDIA_TYPE_OTHER;
}

static uint8_t group_media_wire_type(cyxchat_media_type_t media_type) {
    switch (media_type) {
        case CYXCHAT_MEDIA_TYPE_IMAGE:
            return CYXCHAT_MSG_GROUP_IMAGE;
        case CYXCHAT_MEDIA_TYPE_VIDEO:
            return CYXCHAT_MSG_GROUP_VIDEO;
        case CYXCHAT_MEDIA_TYPE_VOICE:
            return CYXCHAT_MSG_GROUP_VOICE;
        default:
            return CYXCHAT_MSG_GROUP_FILE;
    }
}

static cyxchat_error_t broadcast_group_media_metadata(
    cyxchat_group_ctx_t *ctx,
    cyxchat_group_t *group,
    const cyxchat_group_id_t *group_id,
    const cyxchat_group_media_t *media,
    const uint8_t *payload,
    size_t payload_len
) {
    if (!cyxchat_group_can_send(ctx, group_id, &ctx->local_id)) {
        CYXWIZ_WARN("Media send blocked: who_can_send=%d, not permitted", group->who_can_send);
        return CYXCHAT_ERR_NOT_ADMIN;
    }

    uint8_t plaintext[GROUP_MEDIA_MAX_PLAINTEXT];
    size_t pt_len = serialize_group_media_plaintext(
        plaintext, sizeof(plaintext), media, payload, payload_len
    );
    if (pt_len == 0) {
        CYXWIZ_ERROR("Failed to serialize group media metadata");
        return CYXCHAT_ERR_INVALID;
    }

    uint8_t ciphertext[GROUP_MEDIA_MAX_PLAINTEXT + CYXCHAT_CRYPTO_OVERHEAD];
    size_t ct_len = 0;
    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        plaintext, pt_len,
        group->group_key,
        ciphertext, &ct_len
    );
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("Failed to encrypt group media metadata: %d", err);
        return CYXCHAT_ERR_CRYPTO;
    }

    uint8_t wire[56 + GROUP_MEDIA_MAX_PLAINTEXT + CYXCHAT_CRYPTO_OVERHEAD];
    cyxchat_msg_id_t msg_id;
    memcpy(msg_id.bytes, media->msg_id, CYXCHAT_MSG_ID_SIZE);
    size_t wire_len = serialize_group_media(
        wire, sizeof(wire),
        group_media_wire_type(media->media_type),
        &msg_id, CYXCHAT_FLAG_ENCRYPTED,
        group_id, group->key_version,
        ciphertext, ct_len,
        &ctx->local_id
    );
    if (wire_len == 0) {
        CYXWIZ_ERROR("Failed to serialize group media wire message");
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_onion_ctx_t *onion = cyxchat_get_onion(ctx->chat_ctx);
    if (!onion) {
        CYXWIZ_ERROR("No onion context available for group media");
        return CYXCHAT_ERR_NETWORK;
    }

    int sent_count = 0;
    for (uint8_t i = 0; i < group->member_count; i++) {
        if (memcmp(&group->members[i].node_id, &ctx->local_id, 32) == 0) {
            continue;
        }

        err = cyxwiz_onion_send_to(onion, &group->members[i].node_id, wire, wire_len);
        if (err != CYXWIZ_OK) {
            CYXWIZ_WARN("Failed to send group media metadata to member %u: %d (%s)",
                        i, err, cyxwiz_strerror(err));
        } else {
            sent_count++;
        }
    }

    CYXWIZ_INFO("Group media metadata sent to %d/%u members",
                sent_count, group->member_count - 1);

    pending_grp_track(ctx, &msg_id, group_id, wire, wire_len, group,
                      cyxchat_timestamp_ms());
    return CYXCHAT_OK;
}

static cyxchat_error_t send_group_media_payload(
    cyxchat_group_ctx_t *ctx,
    cyxchat_group_t *group,
    const cyxchat_group_id_t *group_id,
    const cyxchat_group_media_t *media,
    const uint8_t *data,
    size_t data_len
) {
    const uint8_t *inline_payload = data_len <= GROUP_MEDIA_INLINE_MAX ? data : NULL;
    size_t inline_len = inline_payload ? data_len : 0;
    cyxchat_group_media_tx_t *tx_slot = NULL;

    if (inline_len == 0) {
        cyxchat_error_t tx_err = media_tx_start(
            ctx, group, media, data, data_len, &tx_slot
        );
        if (tx_err != CYXCHAT_OK) {
            CYXWIZ_WARN("Failed to queue group media chunks: %d", tx_err);
            return tx_err;
        }
    }

    cyxchat_error_t err = broadcast_group_media_metadata(
        ctx, group, group_id, media, inline_payload, inline_len
    );
    if (err != CYXCHAT_OK && tx_slot) {
        media_tx_free(tx_slot);
    }
    return err;
}

cyxchat_error_t cyxchat_group_send_file(
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
) {
    if (!ctx || !group_id || !filename || !data || !file_id_out || !msg_id_out) {
        return CYXCHAT_ERR_NULL;
    }

    if (data_len == 0 || data_len > CYXCHAT_MAX_MEDIA_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    if (thumbnail_len > CYXCHAT_MAX_THUMBNAIL_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    // Check if we are a member
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }
    if (!is_member(group, &ctx->local_id) || group->left) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    // Check if member has media restriction
    cyxchat_group_member_t *self_member = find_member(group, &ctx->local_id);
    if (self_member && (self_member->restrictions & CYXCHAT_RESTRICT_NO_MEDIA)) {
        return CYXCHAT_ERR_BLOCKED;
    }

    // Generate file ID and message ID
    cyxwiz_crypto_random(file_id_out->bytes, CYXCHAT_FILE_ID_SIZE);
    cyxwiz_crypto_random(msg_id_out->bytes, CYXCHAT_MSG_ID_SIZE);

    // Build media metadata message
    cyxchat_group_media_t media = {0};
    memcpy(media.msg_id, msg_id_out->bytes, CYXCHAT_MSG_ID_SIZE);
    memcpy(media.group_id, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    memcpy(media.sender_id, ctx->local_id.bytes, 32);
    memcpy(media.file_id, file_id_out->bytes, CYXCHAT_FILE_ID_SIZE);
    media.media_type = get_media_type_from_mime(mime_type);
    media.file_size = data_len;
    media.thumbnail_size = (uint32_t)thumbnail_len;
    media.timestamp = cyxchat_timestamp_ms();

    strncpy(media.filename, filename, CYXCHAT_MAX_FILENAME - 1);
    if (mime_type) {
        strncpy(media.mime_type, mime_type, CYXCHAT_MAX_MIME_TYPE - 1);
    }

    CYXWIZ_INFO("Sending file to group: %s (%zu bytes, type=%d)",
                filename, data_len, media.media_type);

    (void)thumbnail;
    return send_group_media_payload(ctx, group, group_id, &media, data, data_len);
}

cyxchat_error_t cyxchat_group_send_voice(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const uint8_t *audio_data,
    size_t audio_len,
    uint32_t duration_ms,
    cyxchat_msg_id_t *msg_id_out
) {
    if (!ctx || !group_id || !audio_data || !msg_id_out) {
        return CYXCHAT_ERR_NULL;
    }

    if (audio_len == 0 || audio_len > CYXCHAT_MAX_MEDIA_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    if (duration_ms > CYXCHAT_VOICE_MAX_DURATION_MS) {
        return CYXCHAT_ERR_INVALID;
    }

    // Check if we are a member
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }
    if (!is_member(group, &ctx->local_id) || group->left) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    // Check if member has media restriction
    cyxchat_group_member_t *self_member = find_member(group, &ctx->local_id);
    if (self_member && (self_member->restrictions & CYXCHAT_RESTRICT_NO_MEDIA)) {
        return CYXCHAT_ERR_BLOCKED;
    }

    // Generate message ID
    cyxwiz_crypto_random(msg_id_out->bytes, CYXCHAT_MSG_ID_SIZE);

    // Build media metadata
    cyxchat_group_media_t media = {0};
    memcpy(media.msg_id, msg_id_out->bytes, CYXCHAT_MSG_ID_SIZE);
    memcpy(media.group_id, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    memcpy(media.sender_id, ctx->local_id.bytes, 32);
    cyxwiz_crypto_random(media.file_id, CYXCHAT_FILE_ID_SIZE);
    media.media_type = CYXCHAT_MEDIA_TYPE_VOICE;
    media.file_size = audio_len;
    media.duration_ms = duration_ms;
    media.timestamp = cyxchat_timestamp_ms();
    strncpy(media.filename, "voice.opus", CYXCHAT_MAX_FILENAME - 1);
    strncpy(media.mime_type, "audio/opus", CYXCHAT_MAX_MIME_TYPE - 1);

    CYXWIZ_INFO("Sending voice message to group: %zu bytes, %u ms",
                audio_len, duration_ms);

    return send_group_media_payload(ctx, group, group_id, &media, audio_data, audio_len);
}

cyxchat_error_t cyxchat_group_send_image(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    const char *filename,
    const uint8_t *image_data,
    size_t image_len,
    uint16_t width,
    uint16_t height,
    cyxchat_msg_id_t *msg_id_out
) {
    if (!ctx || !group_id || !image_data || !msg_id_out) {
        return CYXCHAT_ERR_NULL;
    }

    if (image_len == 0 || image_len > CYXCHAT_MAX_MEDIA_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    // Check if we are a member
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }
    if (!is_member(group, &ctx->local_id) || group->left) {
        return CYXCHAT_ERR_NOT_MEMBER;
    }

    // Check if member has media restriction
    cyxchat_group_member_t *self_member = find_member(group, &ctx->local_id);
    if (self_member && (self_member->restrictions & CYXCHAT_RESTRICT_NO_MEDIA)) {
        return CYXCHAT_ERR_BLOCKED;
    }

    // Generate message ID
    cyxwiz_crypto_random(msg_id_out->bytes, CYXCHAT_MSG_ID_SIZE);

    // Build media metadata
    cyxchat_group_media_t media = {0};
    memcpy(media.msg_id, msg_id_out->bytes, CYXCHAT_MSG_ID_SIZE);
    memcpy(media.group_id, group_id->bytes, CYXCHAT_GROUP_ID_SIZE);
    memcpy(media.sender_id, ctx->local_id.bytes, 32);
    cyxwiz_crypto_random(media.file_id, CYXCHAT_FILE_ID_SIZE);
    media.media_type = CYXCHAT_MEDIA_TYPE_IMAGE;
    media.file_size = image_len;
    media.width = width;
    media.height = height;
    media.timestamp = cyxchat_timestamp_ms();

    if (filename) {
        strncpy(media.filename, filename, CYXCHAT_MAX_FILENAME - 1);
    }
    strncpy(media.mime_type, "image/jpeg", CYXCHAT_MAX_MIME_TYPE - 1);

    CYXWIZ_INFO("Sending image to group: %s (%ux%u, %zu bytes)",
                filename ? filename : "unnamed", width, height, image_len);

    return send_group_media_payload(ctx, group, group_id, &media, image_data, image_len);
}

cyxchat_error_t cyxchat_group_get_media(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    int media_type,
    cyxchat_group_media_t *media_out,
    size_t max_media,
    size_t offset,
    size_t *count_out
) {
    if (!ctx || !group_id || !media_out || !count_out) {
        return CYXCHAT_ERR_NULL;
    }

    // Check if we are a member
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        CYXWIZ_ERROR("Group not found"); return CYXCHAT_ERR_NOT_FOUND;
    }

    (void)media_type;
    (void)max_media;
    (void)offset;

    // TODO: Implement media gallery query
    *count_out = 0;
    return CYXCHAT_OK;
}

size_t cyxchat_group_get_media_count(
    cyxchat_group_ctx_t *ctx,
    const cyxchat_group_id_t *group_id,
    int media_type
) {
    (void)media_type;
    if (!ctx || !group_id) {
        return 0;
    }

    // Check if we are a member
    CYXWIZ_INFO("Finding group..."); cyxchat_group_t *group = find_group(ctx, group_id);
    if (!group) {
        return 0;
    }

    // TODO: Implement media count query
    // For now, return 0
    return 0;
}

