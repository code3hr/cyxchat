/**
 * CyxChat Core Implementation
 * Direct messaging functionality with E2E encryption via onion routing
 */

#include <cyxchat/chat.h>
#include <cyxchat/file.h>
#include <cyxwiz/onion.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/memory.h>
#include <cyxwiz/peer.h>
#include <cyxwiz/routing.h>
#include <cyxwiz/log.h>
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
 * Wire Format Constants
 * ============================================================
 * Compact format for LoRa compatibility:
 * - 1-hop onion: 139 bytes max payload
 * - 2-hop onion: 35 bytes max payload
 *
 * Wire header (compact): type(1) + flags(1) + msg_id(8) = 10 bytes
 * TEXT payload: text_len(1) + text(N) [+ reply_to(8) if flagged]
 */

#define WIRE_HEADER_SIZE     42   /* type + flags + msg_id + sender_id */
#define WIRE_MAX_PAYLOAD     250  /* Max for direct routing */

/* ============================================================
 * Receive Queue
 * ============================================================
 * Ring buffer for storing received messages for FFI polling
 */

#define RECV_QUEUE_SIZE      32
#define RECV_MSG_MAX_DATA    4096

typedef struct {
    cyxwiz_node_id_t from;
    uint8_t type;
    uint8_t data[RECV_MSG_MAX_DATA];
    size_t data_len;
    int valid;
} cyxchat_recv_msg_t;

/* ============================================================
 * Fragment Reassembly Buffer
 * ============================================================
 * Holds incomplete fragmented messages until all parts arrive
 */

#define FRAG_BUFFER_SIZE     8
#define FRAG_MAX_CHUNKS      32
#define FRAG_MAX_TEXT        4096  /* Max reassembled message size */
#define FRAG_TIMEOUT_MS      30000 /* Discard after 30 seconds */

/* ============================================================
 * Message Deduplication Buffer
 * ============================================================
 * Tracks recently seen message IDs to prevent duplicates when
 * messages arrive via both direct and relay paths.
 */

#define SEEN_MSG_BUFFER_SIZE 64
#define SEEN_MSG_EXPIRE_MS   30000 /* Expire after 30 seconds */

typedef struct {
    cyxchat_msg_id_t msg_id;
    cyxwiz_node_id_t from;
    uint64_t timestamp_ms;
    int valid;
} cyxchat_seen_msg_t;

typedef struct {
    cyxwiz_node_id_t from;
    cyxchat_msg_id_t msg_id;
    uint8_t total_frags;
    uint8_t received_mask[4];  /* Bitmask for up to 32 fragments */
    uint8_t received_count;
    uint8_t text[FRAG_MAX_TEXT];
    size_t chunk_offsets[FRAG_MAX_CHUNKS];  /* Where each chunk starts */
    size_t chunk_lengths[FRAG_MAX_CHUNKS];  /* Length of each chunk */
    uint64_t start_time_ms;
    int valid;
} cyxchat_frag_entry_t;

/* ============================================================
 * Pending Message Queue (for retransmission)
 * ============================================================ */

typedef struct {
    cyxchat_msg_id_t msg_id;
    cyxwiz_node_id_t to;
    uint8_t *wire_data;       /* Heap-allocated serialized message */
    size_t wire_len;
    uint64_t sent_at_ms;      /* Last send/retry timestamp */
    uint8_t retry_count;
    int active;
} cyxchat_pending_msg_t;

/* ============================================================
 * Internal Structures
 * ============================================================ */

/* Forward declaration for group context */
struct cyxchat_group_ctx;
typedef struct cyxchat_group_ctx cyxchat_group_ctx_t;

/* External function to handle group messages */
extern void cyxchat_group_handle_message(
    cyxchat_group_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    uint8_t type,
    const uint8_t *data,
    size_t len
);

struct cyxchat_ctx {
    cyxwiz_onion_ctx_t *onion;
    cyxwiz_node_id_t local_id;

    /* Receive queue (ring buffer) */
    cyxchat_recv_msg_t recv_queue[RECV_QUEUE_SIZE];
    size_t recv_head;   /* Next write position */
    size_t recv_tail;   /* Next read position */

    /* Fragment reassembly buffer */
    cyxchat_frag_entry_t frag_buffer[FRAG_BUFFER_SIZE];

    /* Message deduplication buffer */
    cyxchat_seen_msg_t seen_msgs[SEEN_MSG_BUFFER_SIZE];
    size_t seen_msgs_idx;  /* Next write position (circular) */

    /* File module context (for message routing) */
    cyxchat_file_ctx_t *file_ctx;

    /* Group module context (for message routing) */
    cyxchat_group_ctx_t *group_ctx;

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

    cyxchat_on_delivery_failed_t on_delivery_failed;
    void *on_delivery_failed_data;

    /* Pending message queue for retransmission */
    cyxchat_pending_msg_t pending_msgs[CYXCHAT_MAX_PENDING_MSGS];
};

/* ============================================================
 * Pending Message Helpers (Retransmission)
 * ============================================================ */

static cyxchat_pending_msg_t* pending_find_slot(cyxchat_ctx_t *ctx) {
    for (int i = 0; i < CYXCHAT_MAX_PENDING_MSGS; i++) {
        if (!ctx->pending_msgs[i].active) {
            return &ctx->pending_msgs[i];
        }
    }
    return NULL;
}

static cyxchat_pending_msg_t* pending_find_by_msg_id(
    cyxchat_ctx_t *ctx,
    const cyxchat_msg_id_t *msg_id
) {
    for (int i = 0; i < CYXCHAT_MAX_PENDING_MSGS; i++) {
        if (ctx->pending_msgs[i].active &&
            memcmp(ctx->pending_msgs[i].msg_id.bytes, msg_id->bytes,
                   CYXCHAT_MSG_ID_SIZE) == 0) {
            return &ctx->pending_msgs[i];
        }
    }
    return NULL;
}

static void pending_free(cyxchat_pending_msg_t *slot) {
    if (slot->wire_data) {
        free(slot->wire_data);
        slot->wire_data = NULL;
    }
    slot->active = 0;
}

static void pending_free_all(cyxchat_ctx_t *ctx) {
    for (int i = 0; i < CYXCHAT_MAX_PENDING_MSGS; i++) {
        if (ctx->pending_msgs[i].active) {
            pending_free(&ctx->pending_msgs[i]);
        }
    }
}

static void pending_track(
    cyxchat_ctx_t *ctx,
    const cyxchat_msg_id_t *msg_id,
    const cyxwiz_node_id_t *to,
    const uint8_t *wire_data,
    size_t wire_len,
    uint64_t now_ms
) {
    cyxchat_pending_msg_t *slot = pending_find_slot(ctx);
    if (!slot) {
        CYXWIZ_WARN("Pending message queue full, message sent without retry tracking");
        return;
    }

    slot->wire_data = (uint8_t *)malloc(wire_len);
    if (!slot->wire_data) {
        CYXWIZ_WARN("Failed to allocate pending message buffer");
        return;
    }

    memcpy(&slot->msg_id, msg_id, sizeof(cyxchat_msg_id_t));
    memcpy(&slot->to, to, sizeof(cyxwiz_node_id_t));
    memcpy(slot->wire_data, wire_data, wire_len);
    slot->wire_len = wire_len;
    slot->sent_at_ms = now_ms;
    slot->retry_count = 0;
    slot->active = 1;
}

static void pending_check_timeouts(cyxchat_ctx_t *ctx, uint64_t now_ms) {
    for (int i = 0; i < CYXCHAT_MAX_PENDING_MSGS; i++) {
        cyxchat_pending_msg_t *slot = &ctx->pending_msgs[i];
        if (!slot->active) continue;

        if (now_ms - slot->sent_at_ms < CYXCHAT_MSG_ACK_TIMEOUT_MS) continue;

        if (slot->retry_count < CYXCHAT_MSG_MAX_RETRIES) {
            /* Retry */
            slot->retry_count++;
            slot->sent_at_ms = now_ms;

            CYXWIZ_INFO("Retransmitting message (retry %u/%u)",
                        slot->retry_count, CYXCHAT_MSG_MAX_RETRIES);

            cyxwiz_onion_send_to(ctx->onion, &slot->to,
                                 slot->wire_data, slot->wire_len);
        } else {
            /* Max retries exhausted */
            CYXWIZ_WARN("Message delivery failed after %u retries",
                        CYXCHAT_MSG_MAX_RETRIES);

            if (ctx->on_delivery_failed) {
                ctx->on_delivery_failed(ctx, &slot->to, &slot->msg_id,
                                        ctx->on_delivery_failed_data);
            }

            pending_free(slot);
        }
    }
}

/* ============================================================
 * Wire Format Serialization
 * ============================================================ */

/*
 * Serialize message to compact wire format
 * Returns bytes written, or 0 on error
 */
static size_t serialize_wire_header(
    uint8_t *out,
    uint8_t type,
    uint16_t flags,
    const cyxchat_msg_id_t *msg_id,
    const cyxwiz_node_id_t *sender_id
) {
    out[0] = type;
    out[1] = (uint8_t)(flags & 0xFF);  /* Lower 8 bits of flags */
    memcpy(out + 2, msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    memcpy(out + 10, sender_id->bytes, sizeof(cyxwiz_node_id_t));  /* 32 bytes */
    return WIRE_HEADER_SIZE;
}

/*
 * Deserialize wire header
 */
static size_t deserialize_wire_header(
    const uint8_t *in,
    size_t len,
    uint8_t *type_out,
    uint16_t *flags_out,
    cyxchat_msg_id_t *msg_id_out,
    cyxwiz_node_id_t *sender_id_out
) {
    if (len < WIRE_HEADER_SIZE) return 0;

    *type_out = in[0];
    *flags_out = in[1];
    memcpy(msg_id_out->bytes, in + 2, CYXCHAT_MSG_ID_SIZE);
    memcpy(sender_id_out->bytes, in + 10, sizeof(cyxwiz_node_id_t));  /* 32 bytes */
    return WIRE_HEADER_SIZE;
}

/*
 * Serialize TEXT message
 */
static size_t serialize_text_msg(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    uint16_t flags,
    const char *text,
    size_t text_len,
    const cyxchat_msg_id_t *reply_to,
    const cyxwiz_node_id_t *sender_id
) {
    size_t offset = 0;

    /* Header */
    offset += serialize_wire_header(out + offset, CYXCHAT_MSG_TEXT, flags, msg_id, sender_id);

    /* Text length (1 byte, max 255) */
    if (text_len > 255 || offset + 1 + text_len > out_size) return 0;
    out[offset++] = (uint8_t)text_len;

    /* Text */
    memcpy(out + offset, text, text_len);
    offset += text_len;

    /* Optional reply_to */
    if (reply_to && (flags & CYXCHAT_FLAG_REPLY)) {
        if (offset + CYXCHAT_MSG_ID_SIZE > out_size) return 0;
        memcpy(out + offset, reply_to->bytes, CYXCHAT_MSG_ID_SIZE);
        offset += CYXCHAT_MSG_ID_SIZE;
    }

    return offset;
}

/*
 * Serialize ACK message
 */
static size_t serialize_ack_msg(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_msg_id_t *ack_msg_id,
    uint8_t status,
    const cyxwiz_node_id_t *sender_id
) {
    size_t offset = 0;

    /* Header */
    offset += serialize_wire_header(out + offset, CYXCHAT_MSG_ACK, 0, msg_id, sender_id);

    /* ACK target and status */
    if (offset + CYXCHAT_MSG_ID_SIZE + 1 > out_size) return 0;
    memcpy(out + offset, ack_msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;
    out[offset++] = status;

    return offset;
}

/*
 * Serialize TYPING message
 */
static size_t serialize_typing_msg(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    uint8_t is_typing,
    const cyxwiz_node_id_t *sender_id
) {
    size_t offset = 0;

    offset += serialize_wire_header(out + offset, CYXCHAT_MSG_TYPING, 0, msg_id, sender_id);

    if (offset + 1 > out_size) return 0;
    out[offset++] = is_typing;

    return offset;
}

/*
 * Serialize REACTION message
 */
static size_t serialize_reaction_msg(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_msg_id_t *target_msg_id,
    const char *reaction,
    size_t reaction_len,
    uint8_t remove,
    const cyxwiz_node_id_t *sender_id
) {
    size_t offset = 0;

    offset += serialize_wire_header(out + offset, CYXCHAT_MSG_REACTION, 0, msg_id, sender_id);

    /* Target msg ID + reaction_len + reaction + remove flag */
    if (offset + CYXCHAT_MSG_ID_SIZE + 1 + reaction_len + 1 > out_size) return 0;

    memcpy(out + offset, target_msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    out[offset++] = (uint8_t)reaction_len;
    memcpy(out + offset, reaction, reaction_len);
    offset += reaction_len;

    out[offset++] = remove;

    return offset;
}

/*
 * Serialize DELETE message
 */
static size_t serialize_delete_msg(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_msg_id_t *target_msg_id,
    const cyxwiz_node_id_t *sender_id
) {
    size_t offset = 0;

    offset += serialize_wire_header(out + offset, CYXCHAT_MSG_DELETE, 0, msg_id, sender_id);

    if (offset + CYXCHAT_MSG_ID_SIZE > out_size) return 0;
    memcpy(out + offset, target_msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    return offset;
}

/*
 * Serialize EDIT message
 */
static size_t serialize_edit_msg(
    uint8_t *out,
    size_t out_size,
    const cyxchat_msg_id_t *msg_id,
    const cyxchat_msg_id_t *target_msg_id,
    const char *new_text,
    size_t new_text_len,
    const cyxwiz_node_id_t *sender_id
) {
    size_t offset = 0;

    offset += serialize_wire_header(out + offset, CYXCHAT_MSG_EDIT, 0, msg_id, sender_id);

    /* Target ID + text_len + text */
    if (offset + CYXCHAT_MSG_ID_SIZE + 1 + new_text_len > out_size) return 0;

    memcpy(out + offset, target_msg_id->bytes, CYXCHAT_MSG_ID_SIZE);
    offset += CYXCHAT_MSG_ID_SIZE;

    out[offset++] = (uint8_t)new_text_len;
    memcpy(out + offset, new_text, new_text_len);
    offset += new_text_len;

    return offset;
}

/* ============================================================
 * Fragment Reassembly Operations
 * ============================================================ */

static cyxchat_frag_entry_t* frag_find_or_create(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    uint8_t total_frags,
    uint64_t now_ms
) {
    /* First, try to find existing entry */
    for (int i = 0; i < FRAG_BUFFER_SIZE; i++) {
        cyxchat_frag_entry_t *e = &ctx->frag_buffer[i];
        if (e->valid &&
            memcmp(&e->from, from, sizeof(cyxwiz_node_id_t)) == 0 &&
            memcmp(&e->msg_id, msg_id, sizeof(cyxchat_msg_id_t)) == 0) {
            return e;
        }
    }

    /* Find empty slot or expire oldest */
    cyxchat_frag_entry_t *oldest = NULL;
    uint64_t oldest_time = UINT64_MAX;

    for (int i = 0; i < FRAG_BUFFER_SIZE; i++) {
        cyxchat_frag_entry_t *e = &ctx->frag_buffer[i];
        if (!e->valid) {
            /* Empty slot found */
            memcpy(&e->from, from, sizeof(cyxwiz_node_id_t));
            memcpy(&e->msg_id, msg_id, sizeof(cyxchat_msg_id_t));
            e->total_frags = total_frags;
            memset(e->received_mask, 0, sizeof(e->received_mask));
            e->received_count = 0;
            memset(e->text, 0, FRAG_MAX_TEXT);
            e->start_time_ms = now_ms;
            e->valid = 1;
            return e;
        }
        if (e->start_time_ms < oldest_time) {
            oldest_time = e->start_time_ms;
            oldest = e;
        }
    }

    /* Expire oldest and reuse */
    if (oldest) {
        memcpy(&oldest->from, from, sizeof(cyxwiz_node_id_t));
        memcpy(&oldest->msg_id, msg_id, sizeof(cyxchat_msg_id_t));
        oldest->total_frags = total_frags;
        memset(oldest->received_mask, 0, sizeof(oldest->received_mask));
        oldest->received_count = 0;
        memset(oldest->text, 0, FRAG_MAX_TEXT);
        oldest->start_time_ms = now_ms;
        oldest->valid = 1;
        return oldest;
    }

    return NULL;
}

static int frag_add_chunk(
    cyxchat_frag_entry_t *entry,
    uint8_t frag_idx,
    const uint8_t *text,
    size_t text_len
) {
    if (frag_idx >= entry->total_frags || frag_idx >= FRAG_MAX_CHUNKS) {
        return 0;
    }

    /* Check if already received */
    int byte_idx = frag_idx / 8;
    int bit_idx = frag_idx % 8;
    if (entry->received_mask[byte_idx] & (1 << bit_idx)) {
        return 0;  /* Duplicate */
    }

    /* Store chunk */
    entry->chunk_lengths[frag_idx] = text_len;

    /* Calculate offset (sum of previous chunk lengths) */
    size_t offset = 0;
    for (int i = 0; i < frag_idx; i++) {
        offset += entry->chunk_lengths[i];
    }
    entry->chunk_offsets[frag_idx] = offset;

    /* Copy text (we'll need to reassemble in order later) */
    if (offset + text_len > FRAG_MAX_TEXT) {
        return 0;  /* Too large */
    }
    memcpy(entry->text + offset, text, text_len);

    /* Mark as received */
    entry->received_mask[byte_idx] |= (1 << bit_idx);
    entry->received_count++;

    return 1;
}

static int frag_is_complete(cyxchat_frag_entry_t *entry) {
    return entry->received_count == entry->total_frags;
}

static size_t frag_get_total_length(cyxchat_frag_entry_t *entry) {
    size_t total = 0;
    for (int i = 0; i < entry->total_frags; i++) {
        total += entry->chunk_lengths[i];
    }
    return total;
}

static void frag_reassemble(cyxchat_frag_entry_t *entry, uint8_t *out, size_t *out_len) {
    /* Fragments are stored sequentially, just need to compute total length */
    *out_len = frag_get_total_length(entry);
    if (*out_len > FRAG_MAX_TEXT) *out_len = FRAG_MAX_TEXT;
    memcpy(out, entry->text, *out_len);
}

static void frag_expire_old(cyxchat_ctx_t *ctx, uint64_t now_ms) {
    for (int i = 0; i < FRAG_BUFFER_SIZE; i++) {
        cyxchat_frag_entry_t *e = &ctx->frag_buffer[i];
        if (e->valid && now_ms - e->start_time_ms > FRAG_TIMEOUT_MS) {
            e->valid = 0;
        }
    }
}

/* ============================================================
 * Receive Queue Operations
 * ============================================================ */

static int queue_is_full(cyxchat_ctx_t *ctx) {
    return ((ctx->recv_head + 1) % RECV_QUEUE_SIZE) == ctx->recv_tail;
}

static int queue_is_empty(cyxchat_ctx_t *ctx) {
    return ctx->recv_head == ctx->recv_tail;
}

static int queue_push(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    uint8_t type,
    const uint8_t *data,
    size_t data_len
) {
    if (queue_is_full(ctx)) {
        /* Drop oldest message */
        ctx->recv_tail = (ctx->recv_tail + 1) % RECV_QUEUE_SIZE;
    }

    cyxchat_recv_msg_t *msg = &ctx->recv_queue[ctx->recv_head];
    memcpy(&msg->from, from, sizeof(cyxwiz_node_id_t));
    msg->type = type;
    msg->data_len = (data_len > RECV_MSG_MAX_DATA) ? RECV_MSG_MAX_DATA : data_len;
    memcpy(msg->data, data, msg->data_len);
    msg->valid = 1;

    ctx->recv_head = (ctx->recv_head + 1) % RECV_QUEUE_SIZE;
    return 1;
}

static int queue_pop(
    cyxchat_ctx_t *ctx,
    cyxwiz_node_id_t *from_out,
    uint8_t *type_out,
    uint8_t *data_out,
    size_t *data_len
) {
    if (queue_is_empty(ctx)) {
        return 0;
    }

    cyxchat_recv_msg_t *msg = &ctx->recv_queue[ctx->recv_tail];

    if (from_out) memcpy(from_out, &msg->from, sizeof(cyxwiz_node_id_t));
    if (type_out) *type_out = msg->type;

    if (data_out && data_len) {
        size_t copy_len = (*data_len < msg->data_len) ? *data_len : msg->data_len;
        memcpy(data_out, msg->data, copy_len);
        *data_len = msg->data_len;
    }

    msg->valid = 0;
    ctx->recv_tail = (ctx->recv_tail + 1) % RECV_QUEUE_SIZE;
    return 1;
}

/* ============================================================
 * Message Deduplication
 * ============================================================ */

/**
 * Check if message was already seen. If not, mark as seen.
 * Returns 1 if duplicate (already seen), 0 if new.
 */
static int is_duplicate_msg(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_msg_id_t *msg_id,
    uint64_t now_ms
) {
    /* Check if we've seen this message ID from this sender */
    for (int i = 0; i < SEEN_MSG_BUFFER_SIZE; i++) {
        cyxchat_seen_msg_t *entry = &ctx->seen_msgs[i];
        if (!entry->valid) continue;

        /* Expire old entries */
        if (now_ms - entry->timestamp_ms > SEEN_MSG_EXPIRE_MS) {
            entry->valid = 0;
            continue;
        }

        /* Check for match */
        if (memcmp(&entry->msg_id, msg_id, sizeof(cyxchat_msg_id_t)) == 0 &&
            memcmp(&entry->from, from, sizeof(cyxwiz_node_id_t)) == 0) {
            CYXWIZ_INFO("Duplicate message detected from %02x%02x... (via backup path), ignoring",
                        from->bytes[0], from->bytes[1]);
            return 1;  /* Duplicate */
        }
    }

    /* Not seen - add to buffer */
    cyxchat_seen_msg_t *new_entry = &ctx->seen_msgs[ctx->seen_msgs_idx];
    memcpy(&new_entry->msg_id, msg_id, sizeof(cyxchat_msg_id_t));
    memcpy(&new_entry->from, from, sizeof(cyxwiz_node_id_t));
    new_entry->timestamp_ms = now_ms;
    new_entry->valid = 1;

    ctx->seen_msgs_idx = (ctx->seen_msgs_idx + 1) % SEEN_MSG_BUFFER_SIZE;

    return 0;  /* New message */
}

/* ============================================================
 * Onion Delivery Callback
 * ============================================================ */

/*
 * Handle incoming messages from onion routing layer
 */
static void on_onion_delivery(
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len,
    void *user_data
) {
    cyxchat_ctx_t *ctx = (cyxchat_ctx_t *)user_data;
    if (!ctx || !from || !data || len < 1) {
        return;
    }

    /* Check message type first (byte 0) to determine format */
    uint8_t msg_type = data[0];

    /* File messages use simple format without wire header:
     * - byte 0: type
     * - remaining: file-specific payload
     * For these, use 'from' parameter as the sender.
     *
     * File message types:
     * - 0x14-0x16: FILE_META, FILE_CHUNK, FILE_ACK
     * - 0x40-0x45: FILE v2 (OFFER, ACCEPT, REJECT, COMPLETE, CANCEL, DHT_READY)
     * - 0x60-0x61: PEER_ADDR, PEER_ADDR_ACK
     */
    int is_file_msg = ((msg_type >= 0x14 && msg_type <= 0x16) ||
                       (msg_type >= 0x40 && msg_type <= 0x45) ||
                       (msg_type >= 0x60 && msg_type <= 0x61));

    uint8_t type;
    uint16_t flags = 0;
    cyxchat_msg_id_t msg_id;
    cyxwiz_node_id_t sender_id;
    size_t offset;
    const cyxwiz_node_id_t *actual_sender;

    if (is_file_msg) {
        /* File messages: type(1) + sender_id(32) + payload
         * Parse sender_id from wire format (for onion routing support) */
        if (len < 33) {  /* Need type(1) + sender_id(32) minimum */
            CYXWIZ_WARN("File message too short: %zu bytes", len);
            return;
        }
        type = msg_type;
        /* Parse sender_id from bytes 1-32 */
        memcpy(&sender_id, data + 1, 32);
        offset = 33;  /* Skip type(1) + sender_id(32) */
        actual_sender = &sender_id;
        memset(&msg_id, 0, sizeof(msg_id));

        char hex_id[17];
        for (int i = 0; i < 8; i++) {
            snprintf(hex_id + i*2, 3, "%02x", sender_id.bytes[i]);
        }
        CYXWIZ_INFO("Received file message (type=0x%02x) from %.16s... (%zu bytes)",
                    type, hex_id, len);
    } else {
        /* Text/control messages: parse wire header with embedded sender_id */
        if (len < WIRE_HEADER_SIZE) {
            return;
        }

        offset = deserialize_wire_header(data, len, &type, &flags, &msg_id, &sender_id);
        if (offset == 0) return;

        /* Use sender from payload (text messages embed sender in wire header) */
        actual_sender = &sender_id;

        /* Log received message with actual sender */
        char hex_id[17];
        for (int i = 0; i < 8; i++) {
            snprintf(hex_id + i*2, 3, "%02x", actual_sender->bytes[i]);
        }
        CYXWIZ_INFO("Received message from peer %.16s... (%zu bytes, type=0x%02x)",
                    hex_id, len, data[0]);
    }

    /* Handle fragmented TEXT messages */
    if (type == CYXCHAT_MSG_TEXT && (flags & CYXCHAT_FLAG_FRAGMENTED)) {
        /* Parse fragment header: frag_idx(1) + total_frags(1) + text_len(1) + text(N) */
        if (len < offset + 3) return;  /* Need at least frag info + text_len */

        uint8_t frag_idx = data[offset++];
        uint8_t total_frags = data[offset++];
        uint8_t text_len = data[offset++];

        if (len < offset + text_len) return;  /* Truncated */

        char frag_hex_id[17];
        for (int i = 0; i < 8; i++) {
            snprintf(frag_hex_id + i*2, 3, "%02x", actual_sender->bytes[i]);
        }
        CYXWIZ_INFO("Received fragment %u/%u from %.16s... (%u bytes)",
                    frag_idx + 1, total_frags, frag_hex_id, text_len);

        /* Get current timestamp */
        uint64_t now_ms = cyxchat_timestamp_ms();

        /* Find or create fragment entry */
        cyxchat_frag_entry_t *entry = frag_find_or_create(
            ctx, actual_sender, &msg_id, total_frags, now_ms);
        if (!entry) {
            CYXWIZ_ERROR("Failed to allocate fragment entry");
            return;
        }

        /* Add this chunk */
        if (!frag_add_chunk(entry, frag_idx, data + offset, text_len)) {
            CYXWIZ_ERROR("Failed to add fragment chunk");
            return;
        }

        /* Check if complete */
        if (frag_is_complete(entry)) {
            CYXWIZ_INFO("All %u fragments received, reassembling message", total_frags);

            /* Reassemble message */
            uint8_t reassembled[FRAG_MAX_TEXT + 1];
            size_t total_len;
            frag_reassemble(entry, reassembled, &total_len);

            /* Queue reassembled message with 2-byte length prefix */
            if (total_len > CYXCHAT_MAX_TEXT_LEN) {
                total_len = CYXCHAT_MAX_TEXT_LEN;
            }
            uint8_t queued_data[RECV_MSG_MAX_DATA];
            /* Use 2-byte little-endian length for long messages */
            queued_data[0] = (uint8_t)(total_len & 0xFF);
            queued_data[1] = (uint8_t)((total_len >> 8) & 0xFF);
            memcpy(queued_data + 2, reassembled, total_len);
            
            CYXWIZ_INFO("Queuing reassembled message: %zu bytes", total_len);
            queue_push(ctx, actual_sender, type, queued_data, 2 + total_len);

            /* Mark entry as used */
            entry->valid = 0;
        }
        return;  /* Fragment handled, don't fall through */
    }

    /* Check for duplicate messages (can arrive via both direct and relay paths) */
    uint64_t now_ms = cyxchat_timestamp_ms();
    if (!is_file_msg && is_duplicate_msg(ctx, actual_sender, &msg_id, now_ms)) {
        return;  /* Duplicate - already processed */
    }

    /* Non-fragmented message - convert to 2-byte length format for TEXT messages */
    if (type == CYXCHAT_MSG_TEXT && len > offset) {
        uint8_t wire_text_len = data[offset];  /* 1-byte on wire */
        if (offset + 1 + wire_text_len <= len) {
            uint8_t converted[RECV_MSG_MAX_DATA];
            /* Convert to 2-byte little-endian length */
            converted[0] = wire_text_len;
            converted[1] = 0;
            memcpy(converted + 2, data + offset + 1, wire_text_len);
            queue_push(ctx, actual_sender, type, converted, 2 + wire_text_len);
        }
    } else if (type < CYXCHAT_MSG_GROUP_TEXT || type > CYXCHAT_MSG_GROUP_KEY_ACK) {
        /* Only queue non-group messages; group messages are handled by callbacks only */
        queue_push(ctx, actual_sender, type, data + offset, len - offset);
    }

    /* Also fire callbacks if registered */
    switch (type) {
        case CYXCHAT_MSG_TEXT:
            if (ctx->on_message && len > offset) {
                uint8_t text_len = data[offset++];
                if (offset + text_len <= len) {
                    cyxchat_text_msg_t text_msg;
                    memset(&text_msg, 0, sizeof(text_msg));
                    text_msg.header.type = type;
                    text_msg.header.flags = flags;
                    memcpy(&text_msg.header.msg_id, &msg_id, sizeof(msg_id));
                    text_msg.text_len = text_len;
                    memcpy(text_msg.text, data + offset, text_len);
                    offset += text_len;

                    /* Check for reply_to */
                    if ((flags & CYXCHAT_FLAG_REPLY) && offset + CYXCHAT_MSG_ID_SIZE <= len) {
                        memcpy(&text_msg.reply_to, data + offset, CYXCHAT_MSG_ID_SIZE);
                    }

                    ctx->on_message(ctx, actual_sender, &text_msg, ctx->on_message_data);
                }
            }
            break;

        case CYXCHAT_MSG_ACK:
            if (offset + CYXCHAT_MSG_ID_SIZE + 1 <= len) {
                cyxchat_msg_id_t ack_id;
                memcpy(&ack_id, data + offset, CYXCHAT_MSG_ID_SIZE);
                offset += CYXCHAT_MSG_ID_SIZE;
                uint8_t status = data[offset];

                /* Clear from pending queue — message was delivered */
                cyxchat_pending_msg_t *pending = pending_find_by_msg_id(ctx, &ack_id);
                if (pending) {
                    CYXWIZ_DEBUG("ACK received, clearing pending message");
                    pending_free(pending);
                }

                if (ctx->on_ack) {
                    ctx->on_ack(ctx, actual_sender, &ack_id, (cyxchat_msg_status_t)status, ctx->on_ack_data);
                }
            }
            break;

        case CYXCHAT_MSG_TYPING:
            if (ctx->on_typing && offset + 1 <= len) {
                int is_typing = data[offset];
                ctx->on_typing(ctx, actual_sender, is_typing, ctx->on_typing_data);
            }
            break;

        case CYXCHAT_MSG_REACTION:
            if (ctx->on_reaction && offset + CYXCHAT_MSG_ID_SIZE + 2 <= len) {
                cyxchat_msg_id_t target_id;
                memcpy(&target_id, data + offset, CYXCHAT_MSG_ID_SIZE);
                offset += CYXCHAT_MSG_ID_SIZE;
                uint8_t reaction_len = data[offset++];
                if (offset + reaction_len + 1 <= len) {
                    char reaction[9] = {0};
                    memcpy(reaction, data + offset, reaction_len);
                    offset += reaction_len;
                    int remove = data[offset];
                    ctx->on_reaction(ctx, actual_sender, &target_id, reaction, remove, ctx->on_reaction_data);
                }
            }
            break;

        case CYXCHAT_MSG_DELETE:
            if (ctx->on_delete && offset + CYXCHAT_MSG_ID_SIZE <= len) {
                cyxchat_msg_id_t target_id;
                memcpy(&target_id, data + offset, CYXCHAT_MSG_ID_SIZE);
                ctx->on_delete(ctx, actual_sender, &target_id, ctx->on_delete_data);
            }
            break;

        case CYXCHAT_MSG_EDIT:
            if (ctx->on_edit && offset + CYXCHAT_MSG_ID_SIZE + 1 <= len) {
                cyxchat_msg_id_t target_id;
                memcpy(&target_id, data + offset, CYXCHAT_MSG_ID_SIZE);
                offset += CYXCHAT_MSG_ID_SIZE;
                uint8_t new_len = data[offset++];
                if (offset + new_len <= len) {
                    ctx->on_edit(ctx, actual_sender, &target_id, (const char *)(data + offset), new_len, ctx->on_edit_data);
                }
            }
            break;

        case CYXCHAT_MSG_FILE_META:
        case CYXCHAT_MSG_FILE_CHUNK:
        case CYXCHAT_MSG_FILE_ACK:
        case CYXCHAT_MSG_PEER_ADDR:
        case CYXCHAT_MSG_PEER_ADDR_ACK:
            /* Route to file module if registered */
            if (ctx->file_ctx) {
                CYXWIZ_INFO("Routing file message (type=0x%02x) to file module", type);
                /* Pass payload data after wire header (offset points past header) */
                cyxchat_file_handle_message(ctx->file_ctx, actual_sender, type, data + offset, len - offset);
            } else {
                CYXWIZ_WARN("Received file message but no file context registered");
            }
            break;

        /* Group messages (0x20-0x28) - route to group module */
        case CYXCHAT_MSG_GROUP_TEXT:
        case CYXCHAT_MSG_GROUP_INVITE:
        case CYXCHAT_MSG_GROUP_JOIN:
        case CYXCHAT_MSG_GROUP_LEAVE:
        case CYXCHAT_MSG_GROUP_KICK:
        case CYXCHAT_MSG_GROUP_KEY:
        case CYXCHAT_MSG_GROUP_INFO:
        case CYXCHAT_MSG_GROUP_ADMIN:
        case CYXCHAT_MSG_GROUP_KEY_ACK:
        case CYXCHAT_MSG_GROUP_TEXT_ACK:
            /* Route to group module if registered */
            if (ctx->group_ctx) {
                CYXWIZ_INFO("Routing group message (type=0x%02x) to group module", type);
                { FILE *dbg = fopen("group_debug.log", "a"); if (dbg) { fprintf(dbg, "chat.c: routing type=0x%02x ctx=%p\n", type, (void*)ctx->group_ctx); fclose(dbg); } }
                /* Pass full message data (group module handles wire format) */
                cyxchat_group_handle_message(ctx->group_ctx, actual_sender, type, data, len);
            } else {
                CYXWIZ_WARN("Received group message but no group context registered");
                { FILE *dbg = fopen("group_debug.log", "a"); if (dbg) { fprintf(dbg, "chat.c: NO GROUP CTX\n"); fclose(dbg); } }
            }
            break;

        default:
            /* Unknown message type, just queued for FFI */
            break;
    }
}

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

    /* Initialize receive queue */
    c->recv_head = 0;
    c->recv_tail = 0;

    /* Register callback with onion layer */
    cyxwiz_onion_set_callback(onion, on_onion_delivery, c);

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_destroy(cyxchat_ctx_t *ctx) {
    if (ctx) {
        /* Free pending message buffers */
        pending_free_all(ctx);

        /* Clear callback in onion layer */
        if (ctx->onion) {
            cyxwiz_onion_set_callback(ctx->onion, NULL, NULL);
        }
        cyxwiz_secure_zero(ctx, sizeof(cyxchat_ctx_t));
        free(ctx);
    }
}

int cyxchat_poll(cyxchat_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;

    /* Poll onion layer for incoming messages */
    if (ctx->onion) {
        cyxwiz_onion_poll(ctx->onion, now_ms);
    }

    /* Expire old incomplete fragments */
    frag_expire_old(ctx, now_ms);

    /* Check pending message timeouts and retry */
    pending_check_timeouts(ctx, now_ms);

    /* Return number of messages in queue */
    if (ctx->recv_head >= ctx->recv_tail) {
        return (int)(ctx->recv_head - ctx->recv_tail);
    } else {
        return (int)(RECV_QUEUE_SIZE - ctx->recv_tail + ctx->recv_head);
    }
}

int cyxchat_recv_next(
    cyxchat_ctx_t *ctx,
    cyxwiz_node_id_t *from_out,
    uint8_t *type_out,
    uint8_t *data_out,
    size_t *data_len
) {
    if (!ctx) return 0;
    return queue_pop(ctx, from_out, type_out, data_out, data_len);
}

const cyxwiz_node_id_t* cyxchat_get_local_id(cyxchat_ctx_t *ctx) {
    if (!ctx) return NULL;
    return &ctx->local_id;
}

/* ============================================================
 * Sending Messages
 * ============================================================ */

/*
 * Max text per chunk for 1-hop onion circuit:
 * 139 bytes max payload
 * - 10 bytes header (type + flags + msg_id)
 * - 2 bytes fragment info (frag_idx + total_frags)
 * - 1 byte text_len
 * = 126 bytes available for text
 */
#define CYXCHAT_MAX_CHUNK_TEXT 80

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

    /* Generate message ID */
    cyxchat_msg_id_t msg_id;
    cyxchat_generate_msg_id(&msg_id);

    char hex_id[17];
    for (int i = 0; i < 8; i++) {
        snprintf(hex_id + i*2, 3, "%02x", to->bytes[i]);
    }

    /* Check if message needs fragmentation */
    size_t first_chunk_max = CYXCHAT_MAX_CHUNK_TEXT;
    if (reply_to && !cyxchat_msg_id_is_zero(reply_to)) {
        first_chunk_max -= CYXCHAT_MSG_ID_SIZE;  /* Reserve space for reply_to */
    }

    if (text_len <= first_chunk_max) {
        /* Short message - send directly */
        uint16_t flags = CYXCHAT_FLAG_ENCRYPTED;
        if (reply_to && !cyxchat_msg_id_is_zero(reply_to)) {
            flags |= CYXCHAT_FLAG_REPLY;
        }

        uint8_t wire_buf[WIRE_MAX_PAYLOAD];
        size_t wire_len = serialize_text_msg(
            wire_buf, sizeof(wire_buf),
            &msg_id, flags, text, text_len,
            (flags & CYXCHAT_FLAG_REPLY) ? reply_to : NULL,
            &ctx->local_id
        );

        if (wire_len == 0) {
            return CYXCHAT_ERR_INVALID;
        }

        CYXWIZ_INFO("Sending text message to peer %.16s... (%zu bytes)", hex_id, wire_len);

        cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, wire_buf, wire_len);
        if (err != CYXWIZ_OK) {
            CYXWIZ_ERROR("Failed to send message: error %d", err);
            return CYXCHAT_ERR_NETWORK;
        }

        /* Track for retransmission */
        pending_track(ctx, &msg_id, to, wire_buf, wire_len, cyxchat_timestamp_ms());

        CYXWIZ_INFO("Message sent successfully via onion routing");
    } else {
        /* Long message - fragment it */
        size_t total_chunks = (text_len + CYXCHAT_MAX_CHUNK_TEXT - 1) / CYXCHAT_MAX_CHUNK_TEXT;
        if (total_chunks > 255) {
            return CYXCHAT_ERR_INVALID;  /* Too long even for fragmentation */
        }

        CYXWIZ_INFO("Fragmenting message into %zu chunks for peer %.16s...", total_chunks, hex_id);

        size_t offset = 0;
        for (size_t i = 0; i < total_chunks; i++) {
            size_t chunk_len = text_len - offset;
            if (chunk_len > CYXCHAT_MAX_CHUNK_TEXT) {
                chunk_len = CYXCHAT_MAX_CHUNK_TEXT;
            }

            /* Build fragmented message:
             * header(11) + frag_idx(1) + total_frags(1) + text_len(1) + text(N) */
            uint16_t flags = CYXCHAT_FLAG_ENCRYPTED | CYXCHAT_FLAG_FRAGMENTED;

            uint8_t wire_buf[WIRE_MAX_PAYLOAD];
            size_t wire_len = 0;

            /* Serialize header */
            wire_len = serialize_wire_header(wire_buf, CYXCHAT_MSG_TEXT, flags, &msg_id, &ctx->local_id);

            /* Add fragment info */
            wire_buf[wire_len++] = (uint8_t)i;              /* Fragment index */
            wire_buf[wire_len++] = (uint8_t)total_chunks;   /* Total fragments */

            /* Add text chunk */
            wire_buf[wire_len++] = (uint8_t)chunk_len;
            memcpy(wire_buf + wire_len, text + offset, chunk_len);
            wire_len += chunk_len;

            cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, wire_buf, wire_len);
            if (err != CYXWIZ_OK) {
                CYXWIZ_ERROR("Failed to send fragment %zu/%zu: error %d", i + 1, total_chunks, err);
                return CYXCHAT_ERR_NETWORK;
            }

            offset += chunk_len;
        }

        CYXWIZ_INFO("All %zu fragments sent successfully", total_chunks);
    }

    if (msg_id_out) {
        memcpy(msg_id_out, &msg_id, sizeof(cyxchat_msg_id_t));
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

    cyxchat_msg_id_t our_msg_id;
    cyxchat_generate_msg_id(&our_msg_id);

    uint8_t wire_buf[WIRE_MAX_PAYLOAD];
    size_t wire_len = serialize_ack_msg(
        wire_buf, sizeof(wire_buf),
        &our_msg_id, msg_id, (uint8_t)status,
        &ctx->local_id
    );

    if (wire_len == 0) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, wire_buf, wire_len);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
}

cyxchat_error_t cyxchat_send_typing(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    int is_typing
) {
    if (!ctx || !to) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_msg_id_t msg_id;
    cyxchat_generate_msg_id(&msg_id);

    uint8_t wire_buf[WIRE_MAX_PAYLOAD];
    size_t wire_len = serialize_typing_msg(
        wire_buf, sizeof(wire_buf),
        &msg_id, is_typing ? 1 : 0,
        &ctx->local_id
    );

    if (wire_len == 0) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, wire_buf, wire_len);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
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

    cyxchat_msg_id_t our_msg_id;
    cyxchat_generate_msg_id(&our_msg_id);

    uint8_t wire_buf[WIRE_MAX_PAYLOAD];
    size_t wire_len = serialize_reaction_msg(
        wire_buf, sizeof(wire_buf),
        &our_msg_id, msg_id, reaction, reaction_len, remove ? 1 : 0,
        &ctx->local_id
    );

    if (wire_len == 0) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, wire_buf, wire_len);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
}

cyxchat_error_t cyxchat_send_delete(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_msg_id_t *msg_id
) {
    if (!ctx || !to || !msg_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_msg_id_t our_msg_id;
    cyxchat_generate_msg_id(&our_msg_id);

    uint8_t wire_buf[WIRE_MAX_PAYLOAD];
    size_t wire_len = serialize_delete_msg(
        wire_buf, sizeof(wire_buf),
        &our_msg_id, msg_id,
        &ctx->local_id
    );

    if (wire_len == 0) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, wire_buf, wire_len);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
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

    if (new_text_len > 255) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxchat_msg_id_t our_msg_id;
    cyxchat_generate_msg_id(&our_msg_id);

    uint8_t wire_buf[WIRE_MAX_PAYLOAD];
    size_t wire_len = serialize_edit_msg(
        wire_buf, sizeof(wire_buf),
        &our_msg_id, msg_id, new_text, new_text_len,
        &ctx->local_id
    );

    if (wire_len == 0) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, wire_buf, wire_len);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
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

void cyxchat_set_on_delivery_failed(
    cyxchat_ctx_t *ctx,
    cyxchat_on_delivery_failed_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_delivery_failed = callback;
        ctx->on_delivery_failed_data = user_data;
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

cyxchat_error_t cyxchat_send_raw(
    cyxchat_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const uint8_t *data,
    size_t data_len
) {
    if (!ctx || !to || !data || data_len == 0) {
        return CYXCHAT_ERR_NULL;
    }

    /* Debug: log destination peer ID for file messages */
    /* File messages: 0x14-0x16, 0x40-0x45, 0x60-0x61 */
    if ((data[0] >= 0x14 && data[0] <= 0x16) ||
        (data[0] >= 0x40 && data[0] <= 0x45) ||
        (data[0] >= 0x60 && data[0] <= 0x61)) {
        char to_hex[65];
        for (int i = 0; i < 32; i++) {
            snprintf(to_hex + i*2, 3, "%02x", to->bytes[i]);
        }
        CYXWIZ_INFO("cyxchat_send_raw: FILE msg type=0x%02x to peer_id=%s", data[0], to_hex);
    }

    CYXWIZ_DEBUG("cyxchat_send_raw: sending %zu bytes (type=0x%02x)", data_len, data[0]);
    cyxwiz_error_t err = cyxwiz_onion_send_to(ctx->onion, to, data, data_len);
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("cyxchat_send_raw: cyxwiz_onion_send_to failed with %d (%s), payload=%zu",
                     err, cyxwiz_strerror(err), data_len);
    }
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
}

cyxwiz_onion_ctx_t* cyxchat_get_onion(cyxchat_ctx_t *ctx) {
    return ctx ? ctx->onion : NULL;
}

void cyxchat_set_hop_count(cyxchat_ctx_t *ctx, uint8_t hop_count) {
    if (ctx && ctx->onion) {
        cyxwiz_onion_set_hop_count(ctx->onion, hop_count);
    }
}

uint8_t cyxchat_get_hop_count(cyxchat_ctx_t *ctx) {
    if (ctx && ctx->onion) {
        return cyxwiz_onion_get_hop_count(ctx->onion);
    }
    return 0;
}

void cyxchat_set_file_ctx(cyxchat_ctx_t *ctx, cyxchat_file_ctx_t *file_ctx) {
    if (ctx) {
        ctx->file_ctx = file_ctx;
    }
}

void cyxchat_set_group_ctx(cyxchat_ctx_t *ctx, cyxchat_group_ctx_t *group_ctx) {
    if (ctx) {
        ctx->group_ctx = group_ctx;
    }
}
