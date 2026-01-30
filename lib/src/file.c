/**
 * CyxChat File Transfer Implementation
 */

#include <cyxchat/file.h>
#include <cyxchat/chat.h>
#include <cyxchat/connection.h>
#include <cyxwiz/routing.h>
#include <cyxwiz/transport.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/dht.h>
#include <cyxwiz/memory.h>
#include <cyxwiz/log.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <winsock2.h>
#include <ws2tcpip.h>
#define CHUNK_DELAY_MS(ms) Sleep(ms)
#else
#include <unistd.h>
#include <arpa/inet.h>
#define CHUNK_DELAY_MS(ms) usleep((ms) * 1000)
#endif

/* ============================================================
 * Constants
 * ============================================================ */

#define CYXCHAT_MAX_TRANSFERS 16

/* ============================================================
 * Internal Structures
 * ============================================================ */

typedef struct {
    cyxchat_file_transfer_t transfer;
    uint8_t *data;                          /* File data buffer */
    size_t data_capacity;
    uint8_t *chunk_bitmap;                  /* Bitmap for received chunks (1 bit per chunk) */
    size_t bitmap_size;                     /* Size of bitmap in bytes */
    uint64_t offer_sent_at;                 /* Timestamp when offer was sent */
    int active;
    uint64_t last_chunk_sent_ms;            /* Timestamp of last chunk sent */
    size_t chunk_size;                      /* Chunk size used for this transfer */
    int peer_addr_sent;                     /* 1 if we sent our address for this transfer */
    int peer_addr_received;                 /* 1 if we received peer's address */
    /* ACK/retry fields */
    uint64_t last_chunk_received_ms;        /* When last chunk was received (receiver) */
    uint64_t last_ack_sent_ms;              /* When last ACK was sent (receiver) */
    int ack_requested;                      /* 1 if we requested missing chunks (receiver) */
    int retries;                            /* Number of retransmit attempts (sender) */
    int waiting_for_ack;                    /* 1 if sender is waiting for ACK */
} file_transfer_slot_t;

/* Forward declare connection context for peer address exchange */
typedef struct cyxchat_conn_ctx cyxchat_conn_ctx_t;

/* Forward declare send_file_ack */
static cyxchat_error_t send_file_ack(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_file_id_t *file_id,
    file_transfer_slot_t *slot,
    int complete);

/* Peer address message (sent via onion, contains public IP:port) */
typedef struct {
    uint8_t type;                           /* CYXCHAT_MSG_PEER_ADDR (0x60) */
    uint8_t sender_id[32];                  /* Sender node ID for onion routing */
    uint8_t file_id[CYXCHAT_FILE_ID_SIZE];  /* Related file transfer ID (optional) */
    uint32_t public_ip;                     /* Public IP (network byte order) */
    uint16_t public_port;                   /* Public port (network byte order) */
} cyxchat_peer_addr_msg_t;

struct cyxchat_file_ctx {
    cyxchat_ctx_t *chat_ctx;

    /* DHT for offline storage */
    cyxwiz_dht_t *dht;
    cyxwiz_node_id_t local_id;

    /* Direct P2P mode */
    int use_direct_mode;            /* 0 = onion (default), 1 = direct P2P */
    cyxwiz_router_t *router;        /* Router for direct P2P sending */
    cyxwiz_transport_t *transport;  /* Transport for direct P2P (bypasses router) */
    cyxchat_conn_ctx_t *conn_ctx;   /* Connection context for peer address exchange */

    /* Transfers */
    file_transfer_slot_t transfers[CYXCHAT_MAX_TRANSFERS];
    size_t transfer_count;

    /* Callbacks */
    cyxchat_on_file_request_t on_request;
    void *on_request_data;

    cyxchat_on_file_progress_t on_progress;
    void *on_progress_data;

    cyxchat_on_file_complete_t on_complete;
    void *on_complete_data;

    cyxchat_on_file_error_t on_error;
    void *on_error_data;
};
/* ============================================================
 * Forward Declarations
 * ============================================================ */

static cyxchat_error_t send_peer_addr_to_peer(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_file_id_t *file_id
);


/* ============================================================
 * Helper Functions
 * ============================================================ */

static file_transfer_slot_t* find_transfer(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    for (size_t i = 0; i < CYXCHAT_MAX_TRANSFERS; i++) {
        if (ctx->transfers[i].active &&
            memcmp(ctx->transfers[i].transfer.meta.file_id.bytes,
                   file_id->bytes, CYXCHAT_FILE_ID_SIZE) == 0) {
            return &ctx->transfers[i];
        }
    }
    return NULL;
}

static file_transfer_slot_t* alloc_transfer(cyxchat_file_ctx_t *ctx) {
    for (size_t i = 0; i < CYXCHAT_MAX_TRANSFERS; i++) {
        if (!ctx->transfers[i].active) {
            memset(&ctx->transfers[i], 0, sizeof(file_transfer_slot_t));
            ctx->transfers[i].active = 1;
            ctx->transfer_count++;
            return &ctx->transfers[i];
        }
    }
    return NULL;
}

static void free_transfer(cyxchat_file_ctx_t *ctx, file_transfer_slot_t *slot) {
    if (slot->data) {
        cyxwiz_secure_zero(slot->data, slot->data_capacity);
        free(slot->data);
    }
    if (slot->chunk_bitmap) {
        free(slot->chunk_bitmap);
    }
    cyxwiz_secure_zero(&slot->transfer.meta.file_key, 32);
    cyxwiz_secure_zero(&slot->transfer.meta.nonce, 24);
    memset(slot, 0, sizeof(file_transfer_slot_t));
    ctx->transfer_count--;
}

/* ============================================================
 * Chunk Bitmap Helpers
 * ============================================================ */

static int alloc_chunk_bitmap(file_transfer_slot_t *slot, uint16_t chunk_count) {
    size_t bitmap_size = (chunk_count + 7) / 8;
    slot->chunk_bitmap = calloc(1, bitmap_size);
    if (!slot->chunk_bitmap) return 0;
    slot->bitmap_size = bitmap_size;
    return 1;
}

static void set_chunk_received(file_transfer_slot_t *slot, uint16_t idx) {
    if (slot->chunk_bitmap && idx < slot->transfer.meta.chunk_count) {
        slot->chunk_bitmap[idx / 8] |= (1 << (idx % 8));
    }
}

static int is_chunk_received(file_transfer_slot_t *slot, uint16_t idx) {
    if (!slot->chunk_bitmap || idx >= slot->transfer.meta.chunk_count) return 0;
    return (slot->chunk_bitmap[idx / 8] >> (idx % 8)) & 1;
}

CYXWIZ_MAYBE_UNUSED static uint16_t count_received_chunks(file_transfer_slot_t *slot) {
    if (!slot->chunk_bitmap) return 0;
    uint16_t count = 0;
    for (uint16_t i = 0; i < slot->transfer.meta.chunk_count; i++) {
        if (is_chunk_received(slot, i)) count++;
    }
    return count;
}

CYXWIZ_MAYBE_UNUSED static uint16_t find_next_missing_chunk(file_transfer_slot_t *slot, uint16_t start) {
    if (!slot->chunk_bitmap) return start;
    for (uint16_t i = start; i < slot->transfer.meta.chunk_count; i++) {
        if (!is_chunk_received(slot, i)) return i;
    }
    return slot->transfer.meta.chunk_count;  /* All received */
}

/* ============================================================
 * Encryption Helpers
 * ============================================================ */

/**
 * Encrypt file data using XChaCha20-Poly1305
 * Returns encrypted data with 40 bytes of overhead (24 nonce + 16 tag)
 */
CYXWIZ_MAYBE_UNUSED static uint8_t* encrypt_file_data(
    const uint8_t *plaintext,
    size_t plaintext_len,
    const uint8_t key[32],
    uint8_t nonce_out[24],
    size_t *encrypted_len_out
) {
    /* Generate random nonce */
    cyxwiz_crypto_random(nonce_out, 24);

    /* Allocate buffer for encrypted data (plaintext + 16 bytes auth tag) */
    if (plaintext_len > SIZE_MAX - 16) return NULL;
    size_t encrypted_len = plaintext_len + 16;
    uint8_t *encrypted = malloc(encrypted_len);
    if (!encrypted) return NULL;

    /* Encrypt using libsodium crypto_aead_xchacha20poly1305 via cyxwiz wrapper */
    cyxwiz_error_t err = cyxwiz_crypto_encrypt(
        plaintext, plaintext_len,
        key,
        encrypted, &encrypted_len
    );

    if (err != CYXWIZ_OK) {
        free(encrypted);
        return NULL;
    }

    *encrypted_len_out = encrypted_len;
    return encrypted;
}

/**
 * Decrypt file data using XChaCha20-Poly1305
 */
CYXWIZ_MAYBE_UNUSED static uint8_t* decrypt_file_data(
    const uint8_t *ciphertext,
    size_t ciphertext_len,
    const uint8_t key[32],
    size_t *plaintext_len_out
) {
    if (ciphertext_len < 16) return NULL;  /* Needs at least auth tag */

    /* Allocate buffer for plaintext (ciphertext - 16 bytes auth tag) */
    size_t plaintext_len = ciphertext_len - 16;
    uint8_t *plaintext = malloc(plaintext_len);
    if (!plaintext) return NULL;

    /* Decrypt */
    cyxwiz_error_t err = cyxwiz_crypto_decrypt(
        ciphertext, ciphertext_len,
        key,
        plaintext, &plaintext_len
    );

    if (err != CYXWIZ_OK) {
        cyxwiz_secure_zero(plaintext, ciphertext_len - 16);
        free(plaintext);
        return NULL;
    }

    *plaintext_len_out = plaintext_len;
    return plaintext;
}

/* ============================================================
 * Transfer Mode Selection
 * ============================================================ */

/**
 * Select appropriate transfer mode based on peer connectivity and file size
 */
CYXWIZ_MAYBE_UNUSED static cyxchat_file_transfer_mode_t select_transfer_mode(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *recipient,
    size_t file_size
) {
    (void)ctx;
    (void)recipient;

    /* For now, always use direct mode since we don't have access to connection state
     * In a full implementation, we would check:
     * 1. If peer is directly connected -> DIRECT
     * 2. If peer is relayed -> RELAY
     * 3. If peer is offline and file small -> DHT_MICRO
     * 4. If peer is offline and file large -> DHT_SIGNAL
     */

    /* Small files that fit in DHT - could use DHT_MICRO if offline */
    if (file_size <= CYXCHAT_DHT_MAX_FILE_SIZE) {
        /* Still default to DIRECT, but DHT_MICRO is available as fallback */
        return CYXCHAT_FILE_MODE_DIRECT;
    }

    return CYXCHAT_FILE_MODE_DIRECT;
}

/* ============================================================
 * FILE_META Send Helper
 * ============================================================ */

/**
 * Send FILE_META message for a transfer slot.
 * Used both for initial send and ACK timeout retries.
 */
static cyxchat_error_t send_file_meta(cyxchat_file_ctx_t *ctx, file_transfer_slot_t *slot)
{
    if (!ctx || !slot || !ctx->chat_ctx) {
        return CYXCHAT_ERR_NULL;
    }

    /* Build and send metadata message using compact wire format */
    uint8_t wire_buf[250];
    size_t wire_len = 0;

    wire_buf[wire_len++] = CYXCHAT_MSG_FILE_META;
    memcpy(wire_buf + wire_len, ctx->local_id.bytes, 32);
    wire_len += 32;
    memcpy(wire_buf + wire_len, slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
    wire_len += CYXCHAT_FILE_ID_SIZE;

    /* Filename (length-prefixed) */
    size_t fname_len = strlen(slot->transfer.meta.filename);
    if (fname_len > 127) fname_len = 127;
    wire_buf[wire_len++] = (uint8_t)fname_len;
    memcpy(wire_buf + wire_len, slot->transfer.meta.filename, fname_len);
    wire_len += fname_len;

    /* MIME type (length-prefixed) */
    size_t mime_len = strlen(slot->transfer.meta.mime_type);
    if (mime_len > 63) mime_len = 63;
    wire_buf[wire_len++] = (uint8_t)mime_len;
    memcpy(wire_buf + wire_len, slot->transfer.meta.mime_type, mime_len);
    wire_len += mime_len;

    /* Size (4 bytes little-endian) */
    wire_buf[wire_len++] = (uint8_t)(slot->transfer.meta.size & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((slot->transfer.meta.size >> 8) & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((slot->transfer.meta.size >> 16) & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((slot->transfer.meta.size >> 24) & 0xFF);

    /* Chunk count (2 bytes little-endian) */
    wire_buf[wire_len++] = (uint8_t)(slot->transfer.meta.chunk_count & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((slot->transfer.meta.chunk_count >> 8) & 0xFF);

    /* File hash (32 bytes) */
    memcpy(wire_buf + wire_len, slot->transfer.meta.file_hash, 32);
    wire_len += 32;

    /* Send metadata via chat layer */
    CYXWIZ_INFO("send_file_meta: sending FILE_META (%zu bytes)", wire_len);
    cyxchat_error_t send_err = cyxchat_send_raw(ctx->chat_ctx, &slot->transfer.peer, wire_buf, wire_len);
    if (send_err != CYXCHAT_OK) {
        CYXWIZ_ERROR("send_file_meta: failed to send FILE_META, error %d", send_err);
        return send_err;
    }
    CYXWIZ_INFO("send_file_meta: FILE_META sent successfully");

    return CYXCHAT_OK;
}

/* ============================================================
 * DHT Key Derivation
 * ============================================================ */

/**
 * Compute DHT key for file offer metadata
 * Key = BLAKE2b(recipient || "CYXCHAT_FILE_OFFER" || file_id)
 */
static void compute_offer_dht_key(
    const cyxwiz_node_id_t *recipient,
    const cyxchat_file_id_t *file_id,
    uint8_t key_out[32]
) {
    uint8_t data[32 + 18 + 8];  /* node_id + "CYXCHAT_FILE_OFFER" + file_id */
    memcpy(data, recipient->bytes, 32);
    memcpy(data + 32, "CYXCHAT_FILE_OFFER", 18);
    memcpy(data + 50, file_id->bytes, 8);
    cyxwiz_crypto_hash(data, sizeof(data), key_out, 32);
}

/**
 * Compute DHT key for file chunk
 * Key = BLAKE2b(file_hash || "CHUNK" || chunk_index)
 */
static void compute_chunk_dht_key(
    const uint8_t file_hash[32],
    uint32_t chunk_idx,
    uint8_t key_out[32]
) {
    uint8_t data[32 + 5 + 4];  /* hash + "CHUNK" + index */
    memcpy(data, file_hash, 32);
    memcpy(data + 32, "CHUNK", 5);
    data[37] = (uint8_t)(chunk_idx & 0xFF);
    data[38] = (uint8_t)((chunk_idx >> 8) & 0xFF);
    data[39] = (uint8_t)((chunk_idx >> 16) & 0xFF);
    data[40] = (uint8_t)((chunk_idx >> 24) & 0xFF);
    cyxwiz_crypto_hash(data, sizeof(data), key_out, 32);
}

/* ============================================================
 * Initialization
 * ============================================================ */

cyxchat_error_t cyxchat_file_ctx_create(
    cyxchat_file_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
) {
    if (!ctx || !chat_ctx) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_file_ctx_t *c = calloc(1, sizeof(cyxchat_file_ctx_t));
    if (!c) {
        return CYXCHAT_ERR_MEMORY;
    }

    c->chat_ctx = chat_ctx;

    /* Copy local_id from chat context for sender identification in file messages */
    const cyxwiz_node_id_t *local_id = cyxchat_get_local_id(chat_ctx);
    if (local_id) {
        memcpy(&c->local_id, local_id, sizeof(cyxwiz_node_id_t));
    }

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_file_ctx_destroy(cyxchat_file_ctx_t *ctx) {
    if (ctx) {
        /* Free all transfers */
        for (size_t i = 0; i < CYXCHAT_MAX_TRANSFERS; i++) {
            if (ctx->transfers[i].active) {
                free_transfer(ctx, &ctx->transfers[i]);
            }
        }
        free(ctx);
    }
}

/* Helper to send next chunk for a transfer */
static void send_next_chunk(cyxchat_file_ctx_t *ctx, file_transfer_slot_t *slot) {
    if (!slot->data || slot->transfer.chunks_done >= slot->transfer.meta.chunk_count) {
        return;
    }

    uint16_t chunk_idx = slot->transfer.chunks_done;

    /* Use the chunk_size stored when transfer was created */
    size_t chunk_size = slot->chunk_size;
    if (chunk_size == 0) {
        /* Fallback if not set (shouldn't happen) */
        chunk_size = (ctx->use_direct_mode && ctx->router)
            ? CYXCHAT_DIRECT_CHUNK_SIZE
            : CYXCHAT_CHUNK_SIZE;
    }

    /* Allocate buffer for chunk - always use heap for portability */
    /* header(13) + sender_id(32) + data */
    size_t max_wire_len = 13 + 32 + chunk_size;
    uint8_t *chunk_buf = malloc(max_wire_len);

    if (!chunk_buf) {
        CYXWIZ_ERROR("send_next_chunk: failed to allocate chunk buffer");
        return;
    }

    size_t chunk_wire_len = 0;

    chunk_buf[chunk_wire_len++] = CYXCHAT_MSG_FILE_CHUNK;
    /* Add sender_id for onion routing */
    memcpy(chunk_buf + chunk_wire_len, ctx->local_id.bytes, 32);
    chunk_wire_len += 32;
    memcpy(chunk_buf + chunk_wire_len, slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
    chunk_wire_len += CYXCHAT_FILE_ID_SIZE;

    /* Chunk index (2 bytes little-endian) */
    chunk_buf[chunk_wire_len++] = (uint8_t)(chunk_idx & 0xFF);
    chunk_buf[chunk_wire_len++] = (uint8_t)((chunk_idx >> 8) & 0xFF);

    /* Calculate chunk data offset and length based on mode */
    size_t offset = (size_t)chunk_idx * chunk_size;
    if (offset >= slot->transfer.meta.size) {
        CYXWIZ_ERROR("send_next_chunk: offset out of bounds (%zu >= %u)",
                     offset, slot->transfer.meta.size);
        free(chunk_buf);
        return;
    }
    size_t remaining = slot->transfer.meta.size - offset;
    uint16_t chunk_len = (remaining > chunk_size) ? (uint16_t)chunk_size : (uint16_t)remaining;

    /* Chunk length (2 bytes) */
    chunk_buf[chunk_wire_len++] = (uint8_t)(chunk_len & 0xFF);
    chunk_buf[chunk_wire_len++] = (uint8_t)((chunk_len >> 8) & 0xFF);

    /* Chunk data */
    memcpy(chunk_buf + chunk_wire_len, slot->data + offset, chunk_len);
    chunk_wire_len += chunk_len;

    /* Debug: log destination peer ID */
    {
        char peer_hex[65];
        for (int i = 0; i < 32; i++) {
            snprintf(peer_hex + i*2, 3, "%02x", slot->transfer.peer.bytes[i]);
        }
        CYXWIZ_INFO("send_next_chunk: chunk %u to peer_id=%s", chunk_idx, peer_hex);
    }

    cyxchat_error_t err;
    if (ctx->use_direct_mode && ctx->transport) {
        /* Direct P2P: send via transport directly (bypasses router peer check) */
        cyxwiz_error_t werr = ctx->transport->ops->send(
            ctx->transport, &slot->transfer.peer, chunk_buf, chunk_wire_len);
        if (werr == CYXWIZ_OK) {
            err = CYXCHAT_OK;
        } else if (werr == CYXWIZ_ERR_PEER_NOT_FOUND && ctx->chat_ctx) {
            /* Peer not in transport's peer list - fall back to onion routing */
            CYXWIZ_INFO("send_next_chunk: direct send failed (peer not found), falling back to onion");
            err = cyxchat_send_raw(ctx->chat_ctx, &slot->transfer.peer, chunk_buf, chunk_wire_len);
        } else {
            err = CYXCHAT_ERR_NETWORK;
        }
    } else {
        /* Onion routing: send via chat layer (slower, anonymous) */
        err = cyxchat_send_raw(ctx->chat_ctx, &slot->transfer.peer, chunk_buf, chunk_wire_len);
    }

    /* Free buffer */
    free(chunk_buf);
    slot->transfer.chunks_done++;
    slot->transfer.updated_at = cyxchat_timestamp_ms();
    slot->last_chunk_sent_ms = slot->transfer.updated_at;
    if (err != CYXCHAT_OK) {
        CYXWIZ_ERROR("send_next_chunk: FAILED to send chunk %u/%u, error=%d",
                     slot->transfer.chunks_done, slot->transfer.meta.chunk_count, err);
    } else {
        CYXWIZ_INFO("send_next_chunk: sent chunk %u/%u (%u bytes, %s mode)",
                    slot->transfer.chunks_done, slot->transfer.meta.chunk_count, chunk_len,
                    (ctx->use_direct_mode && ctx->transport) ? "direct" : "onion");
        /* Notify progress for outgoing transfers */
        if (ctx->on_progress) {
            ctx->on_progress(ctx, &slot->transfer.meta.file_id,
                            slot->transfer.chunks_done,
                            slot->transfer.meta.chunk_count,
                            ctx->on_progress_data);
        }
    }
}

int cyxchat_file_poll(cyxchat_file_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;

    int events = 0;

    /* Check for timeouts, retransmits, and send pending chunks */
    for (size_t i = 0; i < CYXCHAT_MAX_TRANSFERS; i++) {
        file_transfer_slot_t *slot = &ctx->transfers[i];
        if (!slot->active) continue;

        /* For outgoing transfers, send chunks */
        if (slot->transfer.is_outgoing && slot->transfer.state == CYXCHAT_FILE_SENDING) {
            if (slot->transfer.chunks_done < slot->transfer.meta.chunk_count) {
                if (ctx->use_direct_mode && ctx->router) {
                    /* Direct P2P mode: send multiple chunks per poll, no rate limiting
                     * Send up to 10 chunks per poll for fast transfer */
                    int chunks_this_poll = 0;
                    while (slot->transfer.chunks_done < slot->transfer.meta.chunk_count &&
                           chunks_this_poll < 10) {
                        send_next_chunk(ctx, slot);
                        chunks_this_poll++;
                        events++;
                    }
                } else {
                    /* Onion routing mode: rate limited (4 chunks/sec for LoRa compatibility) */
                    uint64_t delay_ms = (slot->transfer.chunks_done == 0) ? 0 : 250;
                    if (now_ms - slot->last_chunk_sent_ms >= delay_ms) {
                        send_next_chunk(ctx, slot);
                        events++;
                    }
                }
            } else if (!slot->waiting_for_ack) {
                /* All chunks sent, wait for ACK from receiver */
                slot->waiting_for_ack = 1;
                slot->transfer.updated_at = now_ms;
                CYXWIZ_INFO("file_poll: All chunks sent, waiting for ACK");
                events++;
            } else {
                /* Waiting for ACK - check for timeout */
                uint64_t since_waiting = now_ms - slot->transfer.updated_at;
                if (since_waiting > 10000) {
                    slot->retries++;
                    if (slot->retries >= 3) {
                        CYXWIZ_WARN("file_poll: ACK timeout after retries, failing");
                        slot->transfer.state = CYXCHAT_FILE_FAILED;
                        if (ctx->on_error) {
                            ctx->on_error(ctx, &slot->transfer.meta.file_id, CYXCHAT_ERR_TIMEOUT, ctx->on_error_data);
                        }
                    } else {
                        CYXWIZ_INFO("file_poll: ACK timeout (retry %d), resending META + chunks", slot->retries);
                        /* Resend FILE_META in case it was lost */
                        send_file_meta(ctx, slot);
                        /* Reset to resend all chunks */
                        slot->transfer.chunks_done = 0;
                        slot->waiting_for_ack = 0;
                        slot->transfer.updated_at = now_ms;
                        events++;
                    }
                }
            }
        }

        /* For incoming transfers, check if we need to request missing chunks */
        if (!slot->transfer.is_outgoing && slot->transfer.state == CYXCHAT_FILE_RECEIVING) {
            uint64_t since_last_chunk = now_ms - slot->last_chunk_received_ms;
            uint64_t since_last_ack = now_ms - slot->last_ack_sent_ms;

            /* If no chunk received for 3 seconds and ACK not sent recently, send ACK */
            if (since_last_chunk > 3000 && since_last_ack > 5000 &&
                slot->transfer.chunks_done < slot->transfer.meta.chunk_count) {

                /* Limit retries */
                if (slot->retries < 5) {
                    CYXWIZ_INFO("file_poll: Requesting missing chunks (retry %d)", slot->retries + 1);
                    send_file_ack(ctx, &slot->transfer.peer, &slot->transfer.meta.file_id, slot, 0);
                    slot->retries++;
                    slot->ack_requested = 1;
                    events++;
                }
            }
        }

        /* Check for stalled transfers (timeout depends on mode) */
        if (slot->transfer.state == CYXCHAT_FILE_SENDING ||
            slot->transfer.state == CYXCHAT_FILE_RECEIVING) {
            /* Guard against clock skew: if updated_at is in the future, skip timeout check */
            if (now_ms > slot->transfer.updated_at) {
                uint64_t elapsed = now_ms - slot->transfer.updated_at;
                /* Direct mode: 5 minute timeout (large files take time)
                 * Onion mode: 60 second timeout, but extend if ACK retry in progress */
                uint64_t timeout_ms = (ctx->use_direct_mode && ctx->router) ? 300000 : 60000;
                if (slot->ack_requested) timeout_ms = 120000;  /* Extend to 2 min if retrying */
                if (elapsed > timeout_ms) {
                    CYXWIZ_WARN("file_poll: Transfer timeout after %llu ms", (unsigned long long)elapsed);
                    slot->transfer.state = CYXCHAT_FILE_FAILED;

                    if (ctx->on_error) {
                        ctx->on_error(ctx, &slot->transfer.meta.file_id,
                                     CYXCHAT_ERR_TIMEOUT, ctx->on_error_data);
                    }
                    events++;
                }
            }
        }
    }

    return events;
}

/* ============================================================
 * Sending Files
 * ============================================================ */

cyxchat_error_t cyxchat_file_send(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *filename,
    const char *mime_type,
    const uint8_t *data,
    size_t data_len,
    cyxchat_file_id_t *file_id_out
) {
    CYXWIZ_INFO("cyxchat_file_send: filename=%s, data_len=%zu, direct_mode=%d",
                filename, data_len, ctx ? ctx->use_direct_mode : 0);

    if (!ctx || !to || !filename || !data || data_len == 0) {
        CYXWIZ_ERROR("cyxchat_file_send: invalid parameters (ctx=%p, to=%p, filename=%p, data=%p, data_len=%zu)",
                     (void*)ctx, (void*)to, (void*)filename, (void*)data, data_len);
        return CYXCHAT_ERR_NULL;
    }

    if (!ctx->chat_ctx) {
        CYXWIZ_ERROR("cyxchat_file_send: chat_ctx is NULL!");
        return CYXCHAT_ERR_NULL;
    }

    /* Check file size limit based on mode */
    size_t max_file_size = (ctx->use_direct_mode && ctx->router)
        ? CYXCHAT_DIRECT_MAX_FILE
        : (65536);  /* 64KB limit for onion routing */

    if (data_len > max_file_size) {
        CYXWIZ_ERROR("cyxchat_file_send: file too large (%zu > %zu)", data_len, max_file_size);
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    /* Calculate chunk count based on mode */
    size_t chunk_size = (ctx->use_direct_mode && ctx->router)
        ? CYXCHAT_DIRECT_CHUNK_SIZE
        : CYXCHAT_CHUNK_SIZE;

    /* For direct mode with large files, we need more than uint16_t can hold
     * Use uint32_t for calculation, but cap at uint16_t max for protocol */
    /* Safe: data_len already bounded by max_file_size check above */
    if (data_len > (size_t)(UINT32_MAX - chunk_size)) {
        CYXWIZ_ERROR("cyxchat_file_send: data_len too large for chunk calc");
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }
    uint32_t chunk_count_32 = (uint32_t)((data_len + chunk_size - 1) / chunk_size);
    if (chunk_count_32 > 65535) {
        CYXWIZ_ERROR("cyxchat_file_send: too many chunks (%u)", chunk_count_32);
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }
    uint16_t chunk_count = (uint16_t)chunk_count_32;

    CYXWIZ_INFO("cyxchat_file_send: using chunk_size=%zu, chunk_count=%u", chunk_size, chunk_count);

    /* Allocate transfer slot */
    file_transfer_slot_t *slot = alloc_transfer(ctx);
    if (!slot) {
        return CYXCHAT_ERR_FULL;
    }

    /* Generate file ID and key */
    cyxwiz_crypto_random(slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
    cyxwiz_crypto_random(slot->transfer.meta.file_key, 32);

    /* Set metadata */
    snprintf(slot->transfer.meta.filename, sizeof(slot->transfer.meta.filename), "%s", filename);
    if (mime_type) {
    memset(slot->transfer.meta.mime_type, 0, sizeof(slot->transfer.meta.mime_type));
    snprintf(slot->transfer.meta.mime_type, sizeof(slot->transfer.meta.mime_type), "%s", mime_type);
    } else {
        /* Detect from extension */
        const char *detected = cyxchat_file_detect_mime(filename);
        strncpy(slot->transfer.meta.mime_type, detected, 63);
    }
    slot->transfer.meta.size = (uint32_t)data_len;
    slot->transfer.meta.chunk_count = chunk_count;
    slot->chunk_size = chunk_size;  /* Store for send_next_chunk */

    /* Hash file */
    cyxwiz_crypto_hash(data, data_len, slot->transfer.meta.file_hash, 32);

    /* Copy peer and state */
    memcpy(&slot->transfer.peer, to, sizeof(cyxwiz_node_id_t));
    slot->transfer.state = CYXCHAT_FILE_PENDING;

    /* Debug: log destination peer ID */
    {
        char to_hex[65];
        for (int i = 0; i < 32; i++) {
            snprintf(to_hex + i*2, 3, "%02x", to->bytes[i]);
        }
        CYXWIZ_INFO("cyxchat_file_send: TO peer_id=%s", to_hex);
    }
    slot->transfer.is_outgoing = 1;
    slot->transfer.started_at = cyxchat_timestamp_ms();
    slot->transfer.updated_at = slot->transfer.started_at;

    /* Store data copy */
    slot->data = malloc(data_len);
    if (!slot->data) {
        free_transfer(ctx, slot);
        return CYXCHAT_ERR_MEMORY;
    }
    memcpy(slot->data, data, data_len);
    slot->data_capacity = data_len;

    /* For direct mode, send our public address BEFORE file metadata.
     * This allows the peer to add us to their transport for direct P2P. */
    if (ctx->use_direct_mode && ctx->conn_ctx) {
        cyxchat_error_t addr_err = send_peer_addr_to_peer(ctx, to, &slot->transfer.meta.file_id);
        if (addr_err != CYXCHAT_OK) {
            CYXWIZ_WARN("file: failed to send peer addr for direct mode: %d", addr_err);
            /* Continue anyway - maybe they already have our address */
        } else {
            slot->peer_addr_sent = 1;
            CYXWIZ_INFO("file: sent peer addr for direct transfer");
        }
    }

    /* Build and send metadata message using compact wire format */
    /* Wire format: type(1) + sender_id(32) + file_id(8) + filename_len(1) + filename(N) +
     *              mime_len(1) + mime(N) + size(4) + chunk_count(2) + file_hash(32) */
    uint8_t wire_buf[250];
    size_t wire_len = 0;

    wire_buf[wire_len++] = CYXCHAT_MSG_FILE_META;
    /* Add sender_id so receiver knows who sent the file (for onion routing) */
    memcpy(wire_buf + wire_len, ctx->local_id.bytes, 32);
    wire_len += 32;
    memcpy(wire_buf + wire_len, slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
    wire_len += CYXCHAT_FILE_ID_SIZE;

    /* Filename (length-prefixed) */
    size_t fname_len = strlen(slot->transfer.meta.filename);
    if (fname_len > 127) fname_len = 127;
    wire_buf[wire_len++] = (uint8_t)fname_len;
    memcpy(wire_buf + wire_len, slot->transfer.meta.filename, fname_len);
    wire_len += fname_len;

    /* MIME type (length-prefixed) */
    size_t mime_len = strlen(slot->transfer.meta.mime_type);
    if (mime_len > 63) mime_len = 63;
    wire_buf[wire_len++] = (uint8_t)mime_len;
    memcpy(wire_buf + wire_len, slot->transfer.meta.mime_type, mime_len);
    wire_len += mime_len;

    /* Size (4 bytes little-endian) */
    wire_buf[wire_len++] = (uint8_t)(slot->transfer.meta.size & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((slot->transfer.meta.size >> 8) & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((slot->transfer.meta.size >> 16) & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((slot->transfer.meta.size >> 24) & 0xFF);

    /* Chunk count (2 bytes little-endian) */
    wire_buf[wire_len++] = (uint8_t)(chunk_count & 0xFF);
    wire_buf[wire_len++] = (uint8_t)((chunk_count >> 8) & 0xFF);

    /* File hash (32 bytes) */
    memcpy(wire_buf + wire_len, slot->transfer.meta.file_hash, 32);
    wire_len += 32;

    /* Send metadata via chat layer */
    CYXWIZ_INFO("cyxchat_file_send: sending FILE_META (%zu bytes)", wire_len);
    cyxchat_error_t send_err = cyxchat_send_raw(ctx->chat_ctx, to, wire_buf, wire_len);
    if (send_err != CYXCHAT_OK) {
        CYXWIZ_ERROR("cyxchat_file_send: failed to send FILE_META, error %d", send_err);
        free_transfer(ctx, slot);
        return send_err;
    }
    CYXWIZ_INFO("cyxchat_file_send: FILE_META sent successfully");

    slot->transfer.state = CYXCHAT_FILE_SENDING;

    /* For small files (<= 1 chunk), send the data immediately after metadata */
    if (chunk_count == 1) {
        /* Single chunk - send immediately */
        uint8_t chunk_buf[250];
        size_t chunk_wire_len = 0;

        chunk_buf[chunk_wire_len++] = CYXCHAT_MSG_FILE_CHUNK;
        /* Add sender_id for onion routing */
        memcpy(chunk_buf + chunk_wire_len, ctx->local_id.bytes, 32);
        chunk_wire_len += 32;
        memcpy(chunk_buf + chunk_wire_len, slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
        chunk_wire_len += CYXCHAT_FILE_ID_SIZE;

        /* Chunk index (2 bytes) */
        chunk_buf[chunk_wire_len++] = 0;
        chunk_buf[chunk_wire_len++] = 0;

        /* Chunk length (2 bytes) */
        uint16_t chunk_len = (uint16_t)data_len;
        chunk_buf[chunk_wire_len++] = (uint8_t)(chunk_len & 0xFF);
        chunk_buf[chunk_wire_len++] = (uint8_t)((chunk_len >> 8) & 0xFF);

        /* Chunk data */
        if (chunk_wire_len + data_len <= sizeof(chunk_buf)) {
            memcpy(chunk_buf + chunk_wire_len, data, data_len);
            chunk_wire_len += data_len;

            cyxchat_send_raw(ctx->chat_ctx, to, chunk_buf, chunk_wire_len);
            slot->transfer.chunks_done = 1;
        }
    } else {
        /* Multi-chunk: let cyxchat_file_poll() send chunks with proper delays */
        slot->transfer.chunks_done = 0;
        slot->last_chunk_sent_ms = 0;  /* Poll will send first chunk immediately */
        CYXWIZ_INFO("cyxchat_file_send: multi-chunk transfer (%u chunks), polling will send", chunk_count);
    }

    if (file_id_out) {
        memcpy(file_id_out, &slot->transfer.meta.file_id, sizeof(cyxchat_file_id_t));
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_file_send_path(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *file_path,
    cyxchat_file_id_t *file_id_out
) {
    if (!ctx || !to || !file_path) {
        return CYXCHAT_ERR_NULL;
    }

    /* Open file */
    FILE *f = fopen(file_path, "rb");
    if (!f) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Get size */
    fseek(f, 0, SEEK_END);
    long size = ftell(f);
    fseek(f, 0, SEEK_SET);

    if (size <= 0 || size > 10 * 1024 * 1024) {  /* 10MB limit */
        fclose(f);
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    /* Read file */
    uint8_t *data = malloc((size_t)size);
    if (!data) {
        fclose(f);
        return CYXCHAT_ERR_MEMORY;
    }

    if (fread(data, 1, (size_t)size, f) != (size_t)size) {
        free(data);
        fclose(f);
        return CYXCHAT_ERR_TRANSFER;
    }
    fclose(f);

    /* Extract filename from path */
    const char *filename = file_path;
    const char *p = file_path;
    while (*p) {
        if (*p == '/' || *p == '\\') {
            filename = p + 1;
        }
        p++;
    }

    /* Send file */
    cyxchat_error_t err = cyxchat_file_send(ctx, to, filename, NULL,
                                            data, (size_t)size, file_id_out);

    cyxwiz_secure_zero(data, (size_t)size);
    free(data);

    return err;
}

/* ============================================================
 * Receiving Files
 * ============================================================ */

cyxchat_error_t cyxchat_file_accept(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    if (slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    if (slot->transfer.state != CYXCHAT_FILE_PENDING) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Allocate receive buffer */
    slot->data = calloc(1, slot->transfer.meta.size);
    if (!slot->data) {
        return CYXCHAT_ERR_MEMORY;
    }
    slot->data_capacity = slot->transfer.meta.size;

    slot->transfer.state = CYXCHAT_FILE_RECEIVING;
    slot->transfer.updated_at = cyxchat_timestamp_ms();

    /* Send accept message to sender */
    {
        uint8_t wire_buf[44];  /* 12 + 32 for sender_id */
        size_t wire_len = 0;

        wire_buf[wire_len++] = CYXCHAT_MSG_FILE_ACCEPT;
        /* Add sender_id for onion routing */
        memcpy(wire_buf + wire_len, ctx->local_id.bytes, 32);
        wire_len += 32;
        memcpy(wire_buf + wire_len, file_id->bytes, CYXCHAT_FILE_ID_SIZE);
        wire_len += CYXCHAT_FILE_ID_SIZE;
        wire_buf[wire_len++] = (uint8_t)slot->transfer.mode;
        uint16_t start_chunk = slot->transfer.chunks_done;
        wire_buf[wire_len++] = (uint8_t)(start_chunk & 0xFF);
        wire_buf[wire_len++] = (uint8_t)((start_chunk >> 8) & 0xFF);

        cyxchat_error_t send_err = cyxchat_send_raw(ctx->chat_ctx, &slot->transfer.peer, wire_buf, wire_len);
        if (send_err != CYXCHAT_OK) {
            CYXWIZ_WARN("cyxchat_file_accept: failed to send FILE_ACCEPT, error %d", send_err);
            /* Don't fail - transfer may still work via poll */
        }
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_file_reject(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Send reject message to sender */
    {
        uint8_t wire_buf[42];  /* 10 + 32 for sender_id */
        size_t wire_len = 0;

        wire_buf[wire_len++] = CYXCHAT_MSG_FILE_REJECT;
        /* Add sender_id for onion routing */
        memcpy(wire_buf + wire_len, ctx->local_id.bytes, 32);
        wire_len += 32;
        memcpy(wire_buf + wire_len, file_id->bytes, CYXCHAT_FILE_ID_SIZE);
        wire_len += CYXCHAT_FILE_ID_SIZE;
        wire_buf[wire_len++] = 0; /* CYXCHAT_FILE_REJECT_DECLINED */

        cyxchat_error_t send_err = cyxchat_send_raw(ctx->chat_ctx, &slot->transfer.peer, wire_buf, wire_len);
        if (send_err != CYXCHAT_OK) {
            CYXWIZ_WARN("cyxchat_file_reject: failed to send FILE_REJECT, error %d", send_err);
            /* Continue with cleanup even if send fails */
        }
    }

    free_transfer(ctx, slot);
    return CYXCHAT_OK;
}

/* ============================================================
 * Transfer Control
 * ============================================================ */

cyxchat_error_t cyxchat_file_cancel(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    slot->transfer.state = CYXCHAT_FILE_CANCELLED;

    /* Send cancel message to peer */
    {
        uint8_t wire_buf[41];  /* 9 + 32 for sender_id */
        size_t wire_len = 0;

        wire_buf[wire_len++] = CYXCHAT_MSG_FILE_CANCEL;
        /* Add sender_id for onion routing */
        memcpy(wire_buf + wire_len, ctx->local_id.bytes, 32);
        wire_len += 32;
        memcpy(wire_buf + wire_len, file_id->bytes, CYXCHAT_FILE_ID_SIZE);
        wire_len += CYXCHAT_FILE_ID_SIZE;

        cyxchat_error_t send_err = cyxchat_send_raw(ctx->chat_ctx, &slot->transfer.peer, wire_buf, wire_len);
        if (send_err != CYXCHAT_OK) {
            CYXWIZ_WARN("cyxchat_file_cancel: failed to send FILE_CANCEL, error %d", send_err);
            /* Continue with cleanup even if send fails */
        }
    }

    free_transfer(ctx, slot);
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_file_pause(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    if (slot->transfer.state == CYXCHAT_FILE_SENDING ||
        slot->transfer.state == CYXCHAT_FILE_RECEIVING) {
        slot->transfer.state = CYXCHAT_FILE_PAUSED;
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_file_resume(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    if (slot->transfer.state == CYXCHAT_FILE_PAUSED) {
        slot->transfer.state = slot->transfer.is_outgoing ?
            CYXCHAT_FILE_SENDING : CYXCHAT_FILE_RECEIVING;
        slot->transfer.updated_at = cyxchat_timestamp_ms();
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Queries
 * ============================================================ */

cyxchat_file_transfer_t* cyxchat_file_find(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    return slot ? &slot->transfer : NULL;
}

size_t cyxchat_file_active_count(cyxchat_file_ctx_t *ctx) {
    return ctx ? ctx->transfer_count : 0;
}

cyxchat_file_transfer_t* cyxchat_file_get(
    cyxchat_file_ctx_t *ctx,
    size_t index
) {
    if (!ctx) return NULL;

    size_t count = 0;
    for (size_t i = 0; i < CYXCHAT_MAX_TRANSFERS; i++) {
        if (ctx->transfers[i].active) {
            if (count == index) {
                return &ctx->transfers[i].transfer;
            }
            count++;
        }
    }
    return NULL;
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_file_set_on_request(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_request_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_request = callback;
        ctx->on_request_data = user_data;
    }
}

void cyxchat_file_set_on_progress(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_progress_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_progress = callback;
        ctx->on_progress_data = user_data;
    }
}

void cyxchat_file_set_on_complete(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_complete_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_complete = callback;
        ctx->on_complete_data = user_data;
    }
}

void cyxchat_file_set_on_error(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_error_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_error = callback;
        ctx->on_error_data = user_data;
    }
}

/* ============================================================
 * Utilities
 * ============================================================ */

static const char hex_table[] = "0123456789abcdef";

void cyxchat_file_id_to_hex(
    const cyxchat_file_id_t *id,
    char *hex_out
) {
    if (!id || !hex_out) return;

    for (size_t i = 0; i < CYXCHAT_FILE_ID_SIZE; i++) {
        hex_out[i * 2] = hex_table[(id->bytes[i] >> 4) & 0x0F];
        hex_out[i * 2 + 1] = hex_table[id->bytes[i] & 0x0F];
    }
    hex_out[CYXCHAT_FILE_ID_SIZE * 2] = '\0';
}

static int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

cyxchat_error_t cyxchat_file_id_from_hex(
    const char *hex,
    cyxchat_file_id_t *id_out
) {
    if (!hex || !id_out) {
        return CYXCHAT_ERR_NULL;
    }

    size_t len = strlen(hex);
    if (len != CYXCHAT_FILE_ID_SIZE * 2) {
        return CYXCHAT_ERR_INVALID;
    }

    for (size_t i = 0; i < CYXCHAT_FILE_ID_SIZE; i++) {
        int hi = hex_nibble(hex[i * 2]);
        int lo = hex_nibble(hex[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            return CYXCHAT_ERR_INVALID;
        }
        id_out->bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    return CYXCHAT_OK;
}

/* MIME type detection */
typedef struct {
    const char *ext;
    const char *mime;
} mime_entry_t;

static const mime_entry_t mime_table[] = {
    { ".jpg",  "image/jpeg" },
    { ".jpeg", "image/jpeg" },
    { ".png",  "image/png" },
    { ".gif",  "image/gif" },
    { ".webp", "image/webp" },
    { ".svg",  "image/svg+xml" },
    { ".mp3",  "audio/mpeg" },
    { ".ogg",  "audio/ogg" },
    { ".wav",  "audio/wav" },
    { ".mp4",  "video/mp4" },
    { ".webm", "video/webm" },
    { ".pdf",  "application/pdf" },
    { ".zip",  "application/zip" },
    { ".txt",  "text/plain" },
    { ".json", "application/json" },
    { ".xml",  "application/xml" },
    { NULL, NULL }
};

const char* cyxchat_file_detect_mime(const char *filename) {
    if (!filename) {
        return "application/octet-stream";
    }

    /* Find extension */
    const char *ext = NULL;
    const char *p = filename;
    while (*p) {
        if (*p == '.') {
            ext = p;
        }
        p++;
    }

    if (!ext) {
        return "application/octet-stream";
    }

    /* Look up MIME type */
    for (const mime_entry_t *e = mime_table; e->ext; e++) {
        /* Case-insensitive compare */
        const char *a = ext;
        const char *b = e->ext;
        int match = 1;
        while (*a && *b) {
            char ca = *a >= 'A' && *a <= 'Z' ? *a + 32 : *a;
            char cb = *b >= 'A' && *b <= 'Z' ? *b + 32 : *b;
            if (ca != cb) {
                match = 0;
                break;
            }
            a++;
            b++;
        }
        if (match && !*a && !*b) {
            return e->mime;
        }
    }

    return "application/octet-stream";
}

void cyxchat_file_format_size(
    uint32_t size_bytes,
    char *out,
    size_t out_len
) {
    if (!out || out_len < 16) return;

    if (size_bytes < 1024) {
        snprintf(out, out_len, "%u B", size_bytes);
    } else if (size_bytes < 1024 * 1024) {
        snprintf(out, out_len, "%.1f KB", size_bytes / 1024.0);
    } else {
        snprintf(out, out_len, "%.1f MB", size_bytes / (1024.0 * 1024.0));
    }
}

/* ============================================================
 * Incoming Message Handling
 * ============================================================ */

static cyxchat_error_t handle_file_meta(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    CYXWIZ_INFO("handle_file_meta: received %zu bytes", data_len);

    /* Parse wire format:
     * file_id(8) + filename_len(1) + filename(N) + mime_len(1) + mime(N) +
     * size(4) + chunk_count(2) + file_hash(32) */
    size_t offset = 0;

    if (data_len < 8 + 1) {
        CYXWIZ_ERROR("handle_file_meta: data too short (%zu bytes)", data_len);
        return CYXCHAT_ERR_INVALID;
    }

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* Filename */
    uint8_t fname_len = data[offset++];
    if (fname_len >= CYXCHAT_MAX_FILENAME) return CYXCHAT_ERR_INVALID;
    if (offset + fname_len > data_len) return CYXCHAT_ERR_INVALID;
    char filename[CYXCHAT_MAX_FILENAME] = {0};
    memcpy(filename, data + offset, fname_len);
    offset += fname_len;

    /* MIME type */
    if (offset >= data_len) return CYXCHAT_ERR_INVALID;
    uint8_t mime_len = data[offset++];
    if (mime_len >= 64) return CYXCHAT_ERR_INVALID;
    if (offset + mime_len > data_len) return CYXCHAT_ERR_INVALID;
    char mime_type[64] = {0};
    memcpy(mime_type, data + offset, mime_len);
    offset += mime_len;

    /* Size (4 bytes little-endian) */
    if (offset + 4 > data_len) return CYXCHAT_ERR_INVALID;
    uint32_t size = (uint32_t)data[offset] |
                    ((uint32_t)data[offset + 1] << 8) |
                    ((uint32_t)data[offset + 2] << 16) |
                    ((uint32_t)data[offset + 3] << 24);
    offset += 4;

    /* Chunk count (2 bytes little-endian) */
    if (offset + 2 > data_len) return CYXCHAT_ERR_INVALID;
    uint16_t chunk_count = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;

    /* File hash (32 bytes) */
    uint8_t file_hash[32] = {0};
    if (offset + 32 <= data_len) {
        memcpy(file_hash, data + offset, 32);
    }

    /* Check if we already have this transfer */
    if (find_transfer(ctx, &file_id)) {
        return CYXCHAT_ERR_EXISTS;
    }

    /* Allocate transfer slot */
    file_transfer_slot_t *slot = alloc_transfer(ctx);
    if (!slot) {
        return CYXCHAT_ERR_FULL;
    }

    /* Fill in metadata */
    memcpy(&slot->transfer.meta.file_id, &file_id, sizeof(cyxchat_file_id_t));
    snprintf(slot->transfer.meta.filename, sizeof(slot->transfer.meta.filename), "%s", filename);
    snprintf(slot->transfer.meta.mime_type, sizeof(slot->transfer.meta.mime_type), "%s", mime_type);
    slot->transfer.meta.size = size;
    slot->transfer.meta.chunk_count = chunk_count;
    memcpy(slot->transfer.meta.file_hash, file_hash, 32);

    /* Set transfer state */
    memcpy(&slot->transfer.peer, from, sizeof(cyxwiz_node_id_t));
    slot->transfer.state = CYXCHAT_FILE_PENDING;
    slot->transfer.is_outgoing = 0;  /* Incoming */
    slot->transfer.started_at = cyxchat_timestamp_ms();
    slot->transfer.updated_at = slot->transfer.started_at;
    slot->transfer.chunks_done = 0;

    /* Calculate chunk_size from metadata (sender may use different chunk size)
     * chunk_size = ceil(size / chunk_count), handle div by zero */
    if (chunk_count > 0) {
        slot->chunk_size = (size + chunk_count - 1) / chunk_count;
    } else {
        slot->chunk_size = CYXCHAT_CHUNK_SIZE;  /* Fallback */
    }

    /* Validate file size before allocation */
    if (size == 0 || size > CYXCHAT_DIRECT_MAX_FILE) {
        CYXWIZ_ERROR("handle_file_meta: invalid file size %u", size);
        free_transfer(ctx, slot);
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    /* Pre-allocate receive buffer for auto-accept */
    slot->data = calloc(1, size);
    if (slot->data) {
        slot->data_capacity = size;
        slot->transfer.state = CYXCHAT_FILE_RECEIVING;
    }

    CYXWIZ_INFO("handle_file_meta: file '%s', size=%u, chunks=%u, chunk_size=%zu",
                filename, size, chunk_count, slot->chunk_size);

    /* Notify callback */
    if (ctx->on_request) {
        CYXWIZ_INFO("handle_file_meta: calling on_request callback");
        /* Pass slot->transfer.peer (persistent) instead of from (stack variable)
         * because Dart FFI callback is async and from may be freed by then */
        ctx->on_request(ctx, &slot->transfer.peer, &slot->transfer.meta, ctx->on_request_data);
    } else {
        CYXWIZ_WARN("handle_file_meta: no on_request callback registered");
    }

    return CYXCHAT_OK;
}

static cyxchat_error_t handle_file_chunk(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    (void)from;  /* Currently unused, reserved for future sender verification */
    CYXWIZ_INFO("handle_file_chunk: received %zu bytes", data_len);

    /* Parse wire format: file_id(8) + chunk_idx(2) + chunk_len(2) + data(N) */
    if (data_len < 8 + 2 + 2) {
        CYXWIZ_ERROR("handle_file_chunk: data too short (%zu bytes)", data_len);
        return CYXCHAT_ERR_INVALID;
    }

    size_t offset = 0;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* Chunk index (2 bytes little-endian) */
    uint16_t chunk_idx = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;

    /* Chunk length (2 bytes little-endian) */
    uint16_t chunk_len = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;

    if (offset + chunk_len > data_len) return CYXCHAT_ERR_INVALID;

    /* Find transfer */
    file_transfer_slot_t *slot = find_transfer(ctx, &file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Verify this is an incoming transfer */
    if (slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Check state */
    if (slot->transfer.state != CYXCHAT_FILE_RECEIVING &&
        slot->transfer.state != CYXCHAT_FILE_PENDING) {
        return CYXCHAT_ERR_INVALID;
    }

    /* If still pending, switch to receiving */
    if (slot->transfer.state == CYXCHAT_FILE_PENDING) {
        if (!slot->data) {
            slot->data = calloc(1, slot->transfer.meta.size);
            if (!slot->data) return CYXCHAT_ERR_MEMORY;
            slot->data_capacity = slot->transfer.meta.size;
        }
        slot->transfer.state = CYXCHAT_FILE_RECEIVING;
    }

    /* Validate chunk index */
    if (chunk_idx >= slot->transfer.meta.chunk_count) {
        CYXWIZ_WARN("handle_file_chunk: chunk_idx %u >= chunk_count %u",
                    chunk_idx, slot->transfer.meta.chunk_count);
        return CYXCHAT_ERR_INVALID;
    }

    /* Copy chunk data to buffer using the calculated chunk_size */
    size_t data_offset = (size_t)chunk_idx * slot->chunk_size;
    if (data_offset + chunk_len <= slot->data_capacity) {
        /* Check if this chunk was already received (duplicate) */
        if (!is_chunk_received(slot, chunk_idx)) {
            memcpy(slot->data + data_offset, data + offset, chunk_len);
            set_chunk_received(slot, chunk_idx);
            slot->transfer.chunks_done++;
            slot->transfer.updated_at = cyxchat_timestamp_ms();
            slot->last_chunk_received_ms = cyxchat_timestamp_ms();
            slot->ack_requested = 0;  /* Reset ACK request since we got new data */

            /* Notify progress */
            if (ctx->on_progress) {
                /* Use slot->transfer.meta.file_id (persistent) instead of file_id (stack)
                 * because Dart FFI callback is async */
                ctx->on_progress(ctx, &slot->transfer.meta.file_id,
                                slot->transfer.chunks_done,
                                slot->transfer.meta.chunk_count,
                                ctx->on_progress_data);
            }

            /* Check if complete */
            if (slot->transfer.chunks_done >= slot->transfer.meta.chunk_count) {
                slot->transfer.state = CYXCHAT_FILE_COMPLETED;

                /* Send completion ACK to sender */
                send_file_ack(ctx, &slot->transfer.peer, &file_id, slot, 1);

                /* Notify completion */
                if (ctx->on_complete) {
                    /* Use slot->transfer.meta.file_id (persistent) instead of file_id (stack)
                     * because Dart FFI callback is async */
                    ctx->on_complete(ctx, &slot->transfer.meta.file_id, slot->data,
                                    slot->transfer.meta.size, ctx->on_complete_data);
                }
            }
        } else {
            CYXWIZ_DEBUG("handle_file_chunk: duplicate chunk %u ignored", chunk_idx);
        }
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * ACK/Retry Functions
 * ============================================================ */

/**
 * Send FILE_ACK message to peer
 * @param complete 1 if all chunks received, 0 to request missing chunks
 */
static cyxchat_error_t send_file_ack(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const cyxchat_file_id_t *file_id,
    file_transfer_slot_t *slot,
    int complete
) {
    /* Wire format: type(1) + sender_id(32) + file_id(8) + complete(1) + chunks_received(2) + bitmap(N) */
    size_t bitmap_len = complete ? 0 : slot->bitmap_size;
    size_t msg_len = 1 + 32 + CYXCHAT_FILE_ID_SIZE + 1 + 2 + bitmap_len;
    uint8_t *msg = calloc(1, msg_len);
    if (!msg) return CYXCHAT_ERR_MEMORY;

    size_t offset = 0;
    msg[offset++] = CYXCHAT_MSG_FILE_ACK;
    memcpy(msg + offset, ctx->local_id.bytes, 32);
    offset += 32;
    memcpy(msg + offset, file_id->bytes, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;
    msg[offset++] = complete ? 1 : 0;
    uint16_t chunks_received = slot->transfer.chunks_done;
    msg[offset++] = chunks_received & 0xFF;
    msg[offset++] = (chunks_received >> 8) & 0xFF;

    if (!complete && slot->chunk_bitmap && bitmap_len > 0) {
        memcpy(msg + offset, slot->chunk_bitmap, bitmap_len);
    }

    CYXWIZ_INFO("send_file_ack: complete=%d, chunks=%u/%u", complete, chunks_received,
                slot->transfer.meta.chunk_count);

    cyxchat_error_t err = cyxchat_send_raw(ctx->chat_ctx, to, msg, msg_len);
    free(msg);

    slot->last_ack_sent_ms = cyxchat_timestamp_ms();
    return err;
}

/**
 * Handle FILE_ACK message from receiver
 * Either marks transfer complete or retransmits missing chunks
 */
static cyxchat_error_t handle_file_ack(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Wire format: file_id(8) + complete(1) + chunks_received(2) + bitmap(N) */
    if (data_len < CYXCHAT_FILE_ID_SIZE + 1 + 2) {
        CYXWIZ_WARN("handle_file_ack: message too short");
        return CYXCHAT_ERR_INVALID;
    }

    size_t offset = 0;
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    int complete = data[offset++];
    uint16_t chunks_received = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;

    CYXWIZ_INFO("handle_file_ack: complete=%d, chunks=%u", complete, chunks_received);

    /* Find the outgoing transfer */
    file_transfer_slot_t *slot = find_transfer(ctx, &file_id);
    if (!slot || !slot->transfer.is_outgoing) {
        CYXWIZ_WARN("handle_file_ack: transfer not found or not outgoing");
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Verify sender matches */
    if (memcmp(from->bytes, slot->transfer.peer.bytes, sizeof(cyxwiz_node_id_t)) != 0) {
        CYXWIZ_WARN("handle_file_ack: sender mismatch");
        return CYXCHAT_ERR_INVALID;
    }

    if (complete) {
        /* Receiver confirmed all chunks received */
        slot->transfer.state = CYXCHAT_FILE_COMPLETED;
        slot->waiting_for_ack = 0;
        CYXWIZ_INFO("handle_file_ack: Transfer complete confirmed by receiver");

        if (ctx->on_complete) {
            /* Use slot->transfer.meta.file_id (persistent) instead of file_id (stack)
             * because Dart FFI callback is async */
            ctx->on_complete(ctx, &slot->transfer.meta.file_id, slot->data, slot->transfer.meta.size,
                            ctx->on_complete_data);
        }
    } else {
        /* Receiver needs missing chunks - retransmit them */
        size_t bitmap_len = data_len - offset;
        const uint8_t *bitmap = (bitmap_len > 0) ? (data + offset) : NULL;

        CYXWIZ_INFO("handle_file_ack: Retransmitting missing chunks (have bitmap: %d)", bitmap != NULL);

        /* Limit retries */
        if (slot->retries >= 10) {
            CYXWIZ_WARN("handle_file_ack: Max retries exceeded");
            slot->transfer.state = CYXCHAT_FILE_FAILED;
            if (ctx->on_error) {
                ctx->on_error(ctx, &file_id, CYXCHAT_ERR_TIMEOUT, ctx->on_error_data);
            }
            return CYXCHAT_ERR_TIMEOUT;
        }
        slot->retries++;

        /* Retransmit missing chunks based on bitmap */
        for (uint16_t i = 0; i < slot->transfer.meta.chunk_count; i++) {
            int chunk_received = 0;
            if (bitmap && (i / 8) < bitmap_len) {
                chunk_received = (bitmap[i / 8] >> (i % 8)) & 1;
            }

            if (!chunk_received) {
                /* Resend this chunk */
                size_t chunk_size = slot->chunk_size;
                size_t chunk_offset = (size_t)i * chunk_size;
                size_t remaining = slot->transfer.meta.size - chunk_offset;
                size_t chunk_len = (remaining < chunk_size) ? remaining : chunk_size;

                /* Build chunk message */
                size_t msg_len = 1 + 32 + CYXCHAT_FILE_ID_SIZE + 2 + 2 + chunk_len;
                uint8_t *msg = calloc(1, msg_len);
                if (!msg) continue;

                size_t pos = 0;
                msg[pos++] = CYXCHAT_MSG_FILE_CHUNK;
                memcpy(msg + pos, ctx->local_id.bytes, 32);
                pos += 32;
                memcpy(msg + pos, file_id.bytes, CYXCHAT_FILE_ID_SIZE);
                pos += CYXCHAT_FILE_ID_SIZE;
                msg[pos++] = i & 0xFF;
                msg[pos++] = (i >> 8) & 0xFF;
                msg[pos++] = chunk_len & 0xFF;
                msg[pos++] = (chunk_len >> 8) & 0xFF;
                memcpy(msg + pos, slot->data + chunk_offset, chunk_len);

                CYXWIZ_INFO("handle_file_ack: Resending chunk %u", i);
                cyxchat_send_raw(ctx->chat_ctx, from, msg, msg_len);
                free(msg);
            }
        }

        slot->transfer.updated_at = cyxchat_timestamp_ms();
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Protocol v2 Message Handlers
 * ============================================================ */

/**
 * Handle FILE_OFFER message (0x40)
 * Creates a pending transfer and notifies the application
 */
static cyxchat_error_t handle_file_offer(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Parse wire format:
     * file_id(8) + file_hash(32) + encrypted_size(4) + chunk_count(2) +
     * filename_len(1) + filename(N) + nonce(24) + encrypted_key(48) */
    size_t offset = 0;

    if (data_len < 8 + 32 + 4 + 2 + 1) return CYXCHAT_ERR_INVALID;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* File hash */
    uint8_t file_hash[32];
    memcpy(file_hash, data + offset, 32);
    offset += 32;

    /* Encrypted size (4 bytes little-endian) */
    uint32_t encrypted_size = (uint32_t)data[offset] |
                              ((uint32_t)data[offset + 1] << 8) |
                              ((uint32_t)data[offset + 2] << 16) |
                              ((uint32_t)data[offset + 3] << 24);
    offset += 4;

    /* Chunk count (2 bytes little-endian) */
    uint16_t chunk_count = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;

    /* Filename (length-prefixed) */
    if (offset >= data_len) return CYXCHAT_ERR_INVALID;
    uint8_t fname_len = data[offset++];
    if (fname_len > 64) fname_len = 64;
    if (offset + fname_len > data_len) return CYXCHAT_ERR_INVALID;
    char filename[65] = {0};
    memcpy(filename, data + offset, fname_len);
    offset += fname_len;

    /* Nonce (24 bytes) */
    if (offset + 24 > data_len) return CYXCHAT_ERR_INVALID;
    uint8_t nonce[24];
    memcpy(nonce, data + offset, 24);
    offset += 24;

    /* Encrypted key (48 bytes) */
    if (offset + 48 > data_len) return CYXCHAT_ERR_INVALID;
    uint8_t encrypted_key[48];
    memcpy(encrypted_key, data + offset, 48);
    offset += 48;

    /* Check if we already have this transfer */
    if (find_transfer(ctx, &file_id)) {
        return CYXCHAT_ERR_EXISTS;
    }

    /* Allocate transfer slot */
    file_transfer_slot_t *slot = alloc_transfer(ctx);
    if (!slot) {
        return CYXCHAT_ERR_FULL;
    }

    /* Fill in metadata */
    memcpy(&slot->transfer.meta.file_id, &file_id, sizeof(cyxchat_file_id_t));
    snprintf(slot->transfer.meta.filename, sizeof(slot->transfer.meta.filename), "%s", filename);
    slot->transfer.meta.size = encrypted_size;
    slot->transfer.meta.chunk_count = chunk_count;
    memcpy(slot->transfer.meta.file_hash, file_hash, 32);
    memcpy(slot->transfer.meta.nonce, nonce, 24);
    memcpy(slot->transfer.meta.encrypted_key, encrypted_key, 48);

    /* Set transfer state */
    memcpy(&slot->transfer.peer, from, sizeof(cyxwiz_node_id_t));
    slot->transfer.state = CYXCHAT_FILE_PENDING;
    slot->transfer.mode = CYXCHAT_FILE_MODE_DIRECT;
    slot->transfer.is_outgoing = 0;  /* Incoming */
    slot->transfer.started_at = cyxchat_timestamp_ms();
    slot->transfer.updated_at = slot->transfer.started_at;
    slot->transfer.chunks_done = 0;

    /* Allocate chunk bitmap */
    if (!alloc_chunk_bitmap(slot, chunk_count)) {
        free_transfer(ctx, slot);
        return CYXCHAT_ERR_MEMORY;
    }

    /* Notify callback */
    if (ctx->on_request) {
        /* Pass slot->transfer.peer (persistent) instead of from (stack variable)
         * because Dart FFI callback is async and from may be freed by then */
        ctx->on_request(ctx, &slot->transfer.peer, &slot->transfer.meta, ctx->on_request_data);
    }

    return CYXCHAT_OK;
}

/**
 * Handle FILE_ACCEPT message (0x41)
 * Starts sending chunks when our offer is accepted
 */
static cyxchat_error_t handle_file_accept(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Parse wire format: file_id(8) + transfer_mode(1) + start_chunk(2) */
    if (data_len < 8 + 1 + 2) return CYXCHAT_ERR_INVALID;

    size_t offset = 0;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* Transfer mode */
    uint8_t transfer_mode = data[offset++];

    /* Start chunk (for resume) */
    uint16_t start_chunk = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;

    (void)transfer_mode;  /* Currently unused */

    /* Find transfer */
    file_transfer_slot_t *slot = find_transfer(ctx, &file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Verify this is our outgoing transfer */
    if (!slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Verify sender matches peer */
    if (memcmp(from->bytes, slot->transfer.peer.bytes, CYXWIZ_NODE_ID_LEN) != 0) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Start sending from the requested chunk */
    slot->transfer.chunks_done = start_chunk;
    slot->transfer.state = CYXCHAT_FILE_SENDING;
    slot->transfer.updated_at = cyxchat_timestamp_ms();

    return CYXCHAT_OK;
}

/**
 * Handle FILE_REJECT message (0x42)
 * Cleans up transfer when rejected
 */
static cyxchat_error_t handle_file_reject(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Parse wire format: file_id(8) + reason(1) */
    if (data_len < 8 + 1) return CYXCHAT_ERR_INVALID;

    size_t offset = 0;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* Reason */
    uint8_t reason = data[offset++];
    (void)reason;  /* Could be logged */

    /* Find transfer */
    file_transfer_slot_t *slot = find_transfer(ctx, &file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Verify this is our outgoing transfer */
    if (!slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Verify sender matches peer */
    if (memcmp(from->bytes, slot->transfer.peer.bytes, CYXWIZ_NODE_ID_LEN) != 0) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Notify error callback */
    if (ctx->on_error) {
        ctx->on_error(ctx, &file_id, CYXCHAT_ERR_TRANSFER, ctx->on_error_data);
    }

    /* Clean up */
    slot->transfer.state = CYXCHAT_FILE_FAILED;
    free_transfer(ctx, slot);

    return CYXCHAT_OK;
}

/**
 * Handle FILE_COMPLETE message (0x43)
 * Confirms transfer completion or reports failure
 */
static cyxchat_error_t handle_file_complete(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Parse wire format: file_id(8) + status(1) + chunks_received(2) + verify_hash(32) */
    if (data_len < 8 + 1 + 2 + 32) return CYXCHAT_ERR_INVALID;

    size_t offset = 0;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* Status */
    uint8_t status = data[offset++];

    /* Chunks received */
    uint16_t chunks_received = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;
    (void)chunks_received;  /* Could be logged */

    /* Verify hash */
    uint8_t verify_hash[32];
    memcpy(verify_hash, data + offset, 32);
    offset += 32;
    (void)verify_hash;  /* Could verify against our hash */

    /* Find transfer */
    file_transfer_slot_t *slot = find_transfer(ctx, &file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Verify this is our outgoing transfer */
    if (!slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Verify sender matches peer */
    if (memcmp(from->bytes, slot->transfer.peer.bytes, CYXWIZ_NODE_ID_LEN) != 0) {
        return CYXCHAT_ERR_INVALID;
    }

    if (status == 0) {
        /* Success */
        slot->transfer.state = CYXCHAT_FILE_COMPLETED;
        if (ctx->on_complete) {
            /* Use slot->transfer.meta.file_id (persistent) instead of file_id (stack)
             * because Dart FFI callback is async */
            ctx->on_complete(ctx, &slot->transfer.meta.file_id, slot->data,
                            slot->transfer.meta.size, ctx->on_complete_data);
        }
    } else {
        /* Failure */
        slot->transfer.state = CYXCHAT_FILE_FAILED;
        if (ctx->on_error) {
            ctx->on_error(ctx, &file_id, CYXCHAT_ERR_TRANSFER, ctx->on_error_data);
        }
    }

    return CYXCHAT_OK;
}

/**
 * Handle FILE_CANCEL message (0x44)
 * Cancels in-progress transfer
 */
static cyxchat_error_t handle_file_cancel(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Parse wire format: file_id(8) */
    if (data_len < 8) return CYXCHAT_ERR_INVALID;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data, CYXCHAT_FILE_ID_SIZE);

    /* Find transfer */
    file_transfer_slot_t *slot = find_transfer(ctx, &file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Verify sender matches peer */
    if (memcmp(from->bytes, slot->transfer.peer.bytes, CYXWIZ_NODE_ID_LEN) != 0) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Notify error callback */
    if (ctx->on_error) {
        ctx->on_error(ctx, &file_id, CYXCHAT_ERR_TRANSFER, ctx->on_error_data);
    }

    /* Clean up */
    slot->transfer.state = CYXCHAT_FILE_CANCELLED;
    free_transfer(ctx, slot);

    return CYXCHAT_OK;
}

/**
 * Handle FILE_DHT_READY message (0x45)
 * Notifies that file chunks are available in DHT
 */
static cyxchat_error_t handle_file_dht_ready(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Parse wire format: file_id(8) + chunk_count(2) */
    if (data_len < 8 + 2) return CYXCHAT_ERR_INVALID;

    size_t offset = 0;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* Chunk count */
    uint16_t chunk_count = (uint16_t)data[offset] | ((uint16_t)data[offset + 1] << 8);
    offset += 2;
    (void)chunk_count;

    /* Find transfer */
    file_transfer_slot_t *slot = find_transfer(ctx, &file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Verify this is incoming and we're waiting for DHT data */
    if (slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Verify sender matches peer */
    if (memcmp(from->bytes, slot->transfer.peer.bytes, CYXWIZ_NODE_ID_LEN) != 0) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Update mode to indicate DHT transfer */
    slot->transfer.mode = CYXCHAT_FILE_MODE_DHT_MICRO;
    slot->transfer.updated_at = cyxchat_timestamp_ms();

    /* The application should call cyxchat_file_retrieve_dht_chunks() to fetch */

    return CYXCHAT_OK;
}

/**
 * Handle incoming PEER_ADDR message
 * This is sent by peer before direct mode file transfer to exchange public address.
 */
static cyxchat_error_t handle_peer_addr(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Expected: file_id(8) + ip(4) + port(2) = 14 bytes (type+sender_id already stripped) */
    if (data_len < CYXCHAT_FILE_ID_SIZE + sizeof(uint32_t) + sizeof(uint16_t)) {
        CYXWIZ_WARN("file: peer addr message too short (%zu bytes)", data_len);
        return CYXCHAT_ERR_INVALID;
    }

    /* Parse the message (type+sender_id already consumed, data points to file_id) */
    const uint8_t *file_id = data;
    uint32_t public_ip;
    uint16_t public_port;

    memcpy(&public_ip, data + CYXCHAT_FILE_ID_SIZE, sizeof(uint32_t));
    memcpy(&public_port, data + CYXCHAT_FILE_ID_SIZE + sizeof(uint32_t), sizeof(uint16_t));

    /* Format IP:port string for logging and connection */
    uint32_t ip = ntohl(public_ip);
    uint16_t port = ntohs(public_port);
    char addr_str[32];
    snprintf(addr_str, sizeof(addr_str), "%u.%u.%u.%u:%u",
        (ip >> 24) & 0xFF, (ip >> 16) & 0xFF, (ip >> 8) & 0xFF, ip & 0xFF, port);

    CYXWIZ_INFO("file: received peer addr %s from peer for direct mode", addr_str);

    /* Find transfer slot if file_id is specified */
    cyxchat_file_id_t fid;
    memcpy(fid.bytes, file_id, CYXCHAT_FILE_ID_SIZE);

    /* Check if file_id is all zeros (no specific transfer) */
    int is_zero_id = 1;
    for (int i = 0; i < CYXCHAT_FILE_ID_SIZE && is_zero_id; i++) {
        if (file_id[i] != 0) is_zero_id = 0;
    }

    if (!is_zero_id) {
        file_transfer_slot_t *slot = find_transfer(ctx, &fid);
        if (slot) {
            slot->peer_addr_received = 1;
            CYXWIZ_DEBUG("file: marked peer addr received for transfer");
        }
    }

    /* Add the peer's address to our connection context for direct sending */
    if (ctx->conn_ctx) {
        cyxchat_error_t err = cyxchat_conn_add_peer_addr(ctx->conn_ctx, from, addr_str);
        if (err == CYXCHAT_OK) {
            CYXWIZ_INFO("file: added peer to transport for direct P2P");
        } else {
            CYXWIZ_WARN("file: failed to add peer addr: %d", err);
        }
    }

    /* Send acknowledgment */
    uint8_t ack[1 + 32 + CYXCHAT_FILE_ID_SIZE];  /* type + sender_id + file_id */
    ack[0] = CYXCHAT_MSG_PEER_ADDR_ACK;
    /* Add sender_id for onion routing */
    memcpy(ack + 1, ctx->local_id.bytes, 32);
    memcpy(ack + 33, file_id, CYXCHAT_FILE_ID_SIZE);
    cyxchat_send_raw(ctx->chat_ctx, from, ack, sizeof(ack));

    return CYXCHAT_OK;
}

/**
 * Handle incoming PEER_ADDR_ACK message
 */
static cyxchat_error_t handle_peer_addr_ack(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    (void)from;  /* Suppress unused parameter warning */
    CYXWIZ_DEBUG("file: received peer addr ACK from peer");

    /* Find transfer if file_id specified */
    if (data_len >= CYXCHAT_FILE_ID_SIZE) {
        cyxchat_file_id_t fid;
        memcpy(fid.bytes, data, CYXCHAT_FILE_ID_SIZE);

        /* Check if file_id is all zeros */
        int is_zero_id = 1;
        for (int i = 0; i < CYXCHAT_FILE_ID_SIZE && is_zero_id; i++) {
            if (data[i] != 0) is_zero_id = 0;
        }

        if (!is_zero_id) {
            file_transfer_slot_t *slot = find_transfer(ctx, &fid);
            if (slot) {
                /* Peer received our address - they can now send to us directly */
                CYXWIZ_DEBUG("file: peer confirmed receipt of our address");
            }
        }
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_file_handle_message(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    uint8_t type,
    const uint8_t *data,
    size_t data_len
) {
    if (!ctx || !from || !data) {
        return CYXCHAT_ERR_NULL;
    }

    switch (type) {
        /* Legacy protocol v1 */
        case CYXCHAT_MSG_FILE_META:
            return handle_file_meta(ctx, from, data, data_len);

        case CYXCHAT_MSG_FILE_CHUNK:
            return handle_file_chunk(ctx, from, data, data_len);

        case CYXCHAT_MSG_FILE_ACK:
            return handle_file_ack(ctx, from, data, data_len);

        /* Protocol v2 */
        case CYXCHAT_MSG_FILE_OFFER:
            return handle_file_offer(ctx, from, data, data_len);

        case CYXCHAT_MSG_FILE_ACCEPT:
            return handle_file_accept(ctx, from, data, data_len);

        case CYXCHAT_MSG_FILE_REJECT:
            return handle_file_reject(ctx, from, data, data_len);

        case CYXCHAT_MSG_FILE_COMPLETE:
            return handle_file_complete(ctx, from, data, data_len);

        case CYXCHAT_MSG_FILE_CANCEL:
            return handle_file_cancel(ctx, from, data, data_len);

        case CYXCHAT_MSG_FILE_DHT_READY:
            return handle_file_dht_ready(ctx, from, data, data_len);

        /* Peer address exchange for direct mode */
        case CYXCHAT_MSG_PEER_ADDR:
            return handle_peer_addr(ctx, from, data, data_len);

        case CYXCHAT_MSG_PEER_ADDR_ACK:
            return handle_peer_addr_ack(ctx, from, data, data_len);

        default:
            return CYXCHAT_ERR_INVALID;
    }
}

/* ============================================================
 * DHT Configuration
 * ============================================================ */

void cyxchat_file_set_dht(cyxchat_file_ctx_t *ctx, cyxwiz_dht_t *dht) {
    if (ctx) {
        ctx->dht = dht;
    }
}

void cyxchat_file_set_local_id(cyxchat_file_ctx_t *ctx, const cyxwiz_node_id_t *local_id) {
    if (ctx && local_id) {
        memcpy(&ctx->local_id, local_id, sizeof(cyxwiz_node_id_t));
    }
}

void cyxchat_file_set_router(cyxchat_file_ctx_t *ctx, cyxwiz_router_t *router) {
    if (ctx) {
        ctx->router = router;
    }
}

void cyxchat_file_set_transport(cyxchat_file_ctx_t *ctx, cyxwiz_transport_t *transport) {
    if (ctx) {
        ctx->transport = transport;
        CYXWIZ_INFO("file: transport set for direct P2P transfers");
    }
}

void cyxchat_file_set_conn_ctx(cyxchat_file_ctx_t *ctx, cyxchat_conn_ctx_t *conn_ctx) {
    if (ctx) {
        ctx->conn_ctx = conn_ctx;
        CYXWIZ_INFO("file: connection context set for peer address exchange");
    }
}

/**
 * Send our public address to peer via onion routing (stays private from relay nodes).
 * This must be called before direct P2P file transfer can work.
 */
static cyxchat_error_t send_peer_addr_to_peer(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !peer_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Get our public address from connection context */
    if (!ctx->conn_ctx) {
        CYXWIZ_WARN("file: cannot send peer addr - no connection context");
        return CYXCHAT_ERR_NETWORK;
    }

    cyxchat_network_status_t status;
    cyxchat_conn_get_status(ctx->conn_ctx, &status);

    if (!status.stun_complete) {
        CYXWIZ_WARN("file: cannot send peer addr - STUN not complete");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Build peer address message */
    cyxchat_peer_addr_msg_t msg;
    memset(&msg, 0, sizeof(msg));
    msg.type = CYXCHAT_MSG_PEER_ADDR;
    /* Add sender_id for onion routing */
    memcpy(msg.sender_id, ctx->local_id.bytes, 32);
    if (file_id) {
        memcpy(msg.file_id, file_id->bytes, CYXCHAT_FILE_ID_SIZE);
    }
    msg.public_ip = status.public_ip;
    msg.public_port = status.public_port;

    /* Log what we're sending */
    uint32_t ip = ntohl(status.public_ip);
    uint16_t port = ntohs(status.public_port);
    CYXWIZ_INFO("file: sending peer addr %u.%u.%u.%u:%u to peer for direct mode",
        (ip >> 24) & 0xFF, (ip >> 16) & 0xFF, (ip >> 8) & 0xFF, ip & 0xFF, port);

    /* Send via onion routing (chat layer) - address stays private from relays */
    return cyxchat_send_raw(ctx->chat_ctx, peer_id, (uint8_t *)&msg, sizeof(msg));
}

cyxchat_error_t cyxchat_file_set_direct_mode(cyxchat_file_ctx_t *ctx, int direct) {
    if (!ctx) {
        return CYXCHAT_ERR_NULL;
    }
    ctx->use_direct_mode = direct ? 1 : 0;
    CYXWIZ_INFO("file: direct mode %s", direct ? "enabled" : "disabled");
    return CYXCHAT_OK;
}

int cyxchat_file_get_direct_mode(cyxchat_file_ctx_t *ctx) {
    return ctx ? ctx->use_direct_mode : 0;
}

/* ============================================================
 * DHT-Based Transfer API
 * ============================================================ */

cyxchat_error_t cyxchat_file_store_offer(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Must be outgoing transfer */
    if (!slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Check if DHT is available */
    if (!ctx->dht) {
        CYXWIZ_WARN("cyxchat_file_store_offer: DHT not available");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Compute DHT key for offer */
    uint8_t dht_key[32];
    compute_offer_dht_key(&slot->transfer.peer, file_id, dht_key);

    /* Serialize offer metadata (must fit in 160 bytes) */
    /* Format: file_id(8) + file_hash(32) + size(4) + chunk_count(2) + filename_len(1) + filename(N) */
    uint8_t offer_value[160];
    size_t offset = 0;

    /* File ID */
    memcpy(offer_value + offset, file_id->bytes, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* File hash */
    memcpy(offer_value + offset, slot->transfer.meta.file_hash, 32);
    offset += 32;

    /* Size (4 bytes little-endian) */
    uint32_t size = (uint32_t)slot->transfer.meta.size;
    offer_value[offset++] = (uint8_t)(size & 0xFF);
    offer_value[offset++] = (uint8_t)((size >> 8) & 0xFF);
    offer_value[offset++] = (uint8_t)((size >> 16) & 0xFF);
    offer_value[offset++] = (uint8_t)((size >> 24) & 0xFF);

    /* Chunk count (2 bytes little-endian) */
    offer_value[offset++] = (uint8_t)(slot->transfer.meta.chunk_count & 0xFF);
    offer_value[offset++] = (uint8_t)((slot->transfer.meta.chunk_count >> 8) & 0xFF);

    /* Filename (length-prefixed, max 64 bytes) */
    size_t fname_len = strlen(slot->transfer.meta.filename);
    if (fname_len > 64) fname_len = 64;
    offer_value[offset++] = (uint8_t)fname_len;
    memcpy(offer_value + offset, slot->transfer.meta.filename, fname_len);
    offset += fname_len;

    /* Store in DHT with 24-hour TTL */
    cyxwiz_error_t err = cyxwiz_dht_put(ctx->dht, dht_key, offer_value, offset, CYXCHAT_DHT_TTL_SECONDS);
    if (err != CYXWIZ_OK) {
        CYXWIZ_ERROR("cyxchat_file_store_offer: DHT put failed with %d", err);
        return CYXCHAT_ERR_NETWORK;
    }

    slot->transfer.mode = CYXCHAT_FILE_MODE_DHT_SIGNAL;
    CYXWIZ_INFO("Stored file offer in DHT for offline recipient");

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_file_store_dht_chunks(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Must be outgoing transfer */
    if (!slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Check if DHT is available */
    if (!ctx->dht) {
        CYXWIZ_WARN("cyxchat_file_store_dht_chunks: DHT not available");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Check size limit for DHT storage */
    if (slot->transfer.meta.size > CYXCHAT_DHT_MAX_FILE_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    /* Need file data to store */
    if (!slot->data) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Store each chunk in DHT */
    uint16_t dht_chunk_count = (uint16_t)((slot->transfer.meta.size + CYXCHAT_DHT_CHUNK_SIZE - 1)
                                           / CYXCHAT_DHT_CHUNK_SIZE);

    int stored_count = 0;
    for (uint16_t i = 0; i < dht_chunk_count; i++) {
        uint8_t dht_key[32];
        compute_chunk_dht_key(slot->transfer.meta.file_hash, i, dht_key);

        size_t chunk_offset = (size_t)i * CYXCHAT_DHT_CHUNK_SIZE;
        size_t remaining = slot->transfer.meta.size - chunk_offset;
        size_t len = (remaining > CYXCHAT_DHT_CHUNK_SIZE) ? CYXCHAT_DHT_CHUNK_SIZE : remaining;

        /* Store chunk in DHT */
        cyxwiz_error_t err = cyxwiz_dht_put(ctx->dht, dht_key, slot->data + chunk_offset, len, CYXCHAT_DHT_TTL_SECONDS);
        if (err == CYXWIZ_OK) {
            stored_count++;
        } else {
            CYXWIZ_WARN("Failed to store DHT chunk %u/%u, error %d", i, dht_chunk_count, err);
        }
    }

    if (stored_count == dht_chunk_count) {
        slot->transfer.mode = CYXCHAT_FILE_MODE_DHT_MICRO;
        CYXWIZ_INFO("Stored all %u file chunks in DHT", dht_chunk_count);
        return CYXCHAT_OK;
    }

    CYXWIZ_WARN("Only stored %d/%u chunks in DHT", stored_count, dht_chunk_count);
    return CYXCHAT_ERR_NETWORK;  /* Partial failure */
}

/* Callback context for DHT chunk retrieval */
typedef struct {
    cyxchat_file_ctx_t *file_ctx;
    cyxchat_file_id_t file_id;
    uint16_t chunk_idx;
    uint16_t total_chunks;
} dht_chunk_get_ctx_t;

/* Callback for DHT chunk retrieval */
static void on_dht_chunk_received(
    const uint8_t *key,
    bool found,
    const uint8_t *value,
    size_t value_len,
    void *user_data
) {
    (void)key;  /* Unused */

    dht_chunk_get_ctx_t *get_ctx = (dht_chunk_get_ctx_t *)user_data;
    if (!get_ctx) return;

    cyxchat_file_ctx_t *ctx = get_ctx->file_ctx;
    if (!ctx) {
        free(get_ctx);
        return;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, &get_ctx->file_id);
    if (!slot || !slot->data) {
        CYXWIZ_WARN("DHT chunk callback: transfer not found");
        free(get_ctx);
        return;
    }

    if (found && value && value_len > 0) {
        /* Copy chunk data to buffer */
        size_t chunk_offset = (size_t)get_ctx->chunk_idx * CYXCHAT_DHT_CHUNK_SIZE;
        if (chunk_offset + value_len <= slot->data_capacity) {
            memcpy(slot->data + chunk_offset, value, value_len);
            set_chunk_received(slot, get_ctx->chunk_idx);
            slot->transfer.chunks_done++;
            slot->transfer.updated_at = cyxchat_timestamp_ms();

            CYXWIZ_DEBUG("DHT chunk %u/%u received (%zu bytes)",
                        get_ctx->chunk_idx, get_ctx->total_chunks, value_len);

            /* Notify progress */
            if (ctx->on_progress) {
                ctx->on_progress(ctx, &get_ctx->file_id,
                                slot->transfer.chunks_done,
                                get_ctx->total_chunks,
                                ctx->on_progress_data);
            }

            /* Check completion */
            if (slot->transfer.chunks_done >= get_ctx->total_chunks) {
                slot->transfer.state = CYXCHAT_FILE_COMPLETED;
                CYXWIZ_INFO("DHT file transfer complete");
                if (ctx->on_complete) {
                    ctx->on_complete(ctx, &get_ctx->file_id, slot->data,
                                    slot->transfer.meta.size, ctx->on_complete_data);
                }
            }
        } else {
            CYXWIZ_WARN("DHT chunk %u: buffer overflow", get_ctx->chunk_idx);
        }
    } else {
        CYXWIZ_WARN("DHT chunk %u not found in DHT", get_ctx->chunk_idx);
    }

    free(get_ctx);
}

cyxchat_error_t cyxchat_file_retrieve_dht_chunks(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check if DHT is available */
    if (!ctx->dht) {
        CYXWIZ_WARN("cyxchat_file_retrieve_dht_chunks: DHT not available");
        return CYXCHAT_ERR_NETWORK;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Must be incoming transfer */
    if (slot->transfer.is_outgoing) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Allocate receive buffer if needed */
    if (!slot->data) {
        slot->data = calloc(1, slot->transfer.meta.size);
        if (!slot->data) {
            return CYXCHAT_ERR_MEMORY;
        }
        slot->data_capacity = slot->transfer.meta.size;
    }

    /* Allocate chunk bitmap if needed */
    uint16_t dht_chunk_count = (uint16_t)((slot->transfer.meta.size + CYXCHAT_DHT_CHUNK_SIZE - 1)
                                           / CYXCHAT_DHT_CHUNK_SIZE);

    if (!slot->chunk_bitmap) {
        size_t bitmap_bytes = (dht_chunk_count + 7) / 8;
        slot->chunk_bitmap = calloc(1, bitmap_bytes);
        if (!slot->chunk_bitmap) {
            return CYXCHAT_ERR_MEMORY;
        }
        slot->bitmap_size = bitmap_bytes;
    }

    /* Start async retrieval for each missing chunk */
    int requests_started = 0;
    for (uint16_t i = 0; i < dht_chunk_count; i++) {
        if (is_chunk_received(slot, i)) continue;  /* Already have this chunk */

        uint8_t dht_key[32];
        compute_chunk_dht_key(slot->transfer.meta.file_hash, i, dht_key);

        /* Allocate callback context */
        dht_chunk_get_ctx_t *get_ctx = malloc(sizeof(dht_chunk_get_ctx_t));
        if (!get_ctx) continue;

        get_ctx->file_ctx = ctx;
        memcpy(&get_ctx->file_id, file_id, sizeof(cyxchat_file_id_t));
        get_ctx->chunk_idx = i;
        get_ctx->total_chunks = dht_chunk_count;

        /* Start async DHT get */
        cyxwiz_error_t err = cyxwiz_dht_get(ctx->dht, dht_key, on_dht_chunk_received, get_ctx);
        if (err == CYXWIZ_OK) {
            requests_started++;
        } else {
            CYXWIZ_WARN("Failed to start DHT get for chunk %u", i);
            free(get_ctx);
        }
    }

    if (requests_started > 0) {
        slot->transfer.state = CYXCHAT_FILE_RECEIVING;
        slot->transfer.mode = CYXCHAT_FILE_MODE_DHT_MICRO;
        CYXWIZ_INFO("Started DHT retrieval for %d chunks", requests_started);
        return CYXCHAT_OK;
    }

    /* No requests started - either all chunks received or all failed */
    if (slot->transfer.chunks_done >= dht_chunk_count) {
        slot->transfer.state = CYXCHAT_FILE_COMPLETED;
        return CYXCHAT_OK;
    }

    return CYXCHAT_ERR_NETWORK;
}

int cyxchat_file_check_dht_offers(cyxchat_file_ctx_t *ctx) {
    if (!ctx) {
        return -1;
    }

    if (!ctx->dht) {
        CYXWIZ_DEBUG("cyxchat_file_check_dht_offers: DHT not available");
        return 0;
    }

    /*
     * DHT offer lookup requires knowing the file_id of pending offers.
     * Key format: BLAKE2b(our_node_id || "CYXCHAT_FILE_OFFER" || file_id)
     *
     * Since DHT doesn't support prefix queries, we cannot enumerate all
     * offers addressed to us. Instead, the sender must notify us through
     * an alternative channel (e.g., a text message with the file_id hint)
     * or we must already know the file_id from a previous FILE_DHT_READY
     * notification.
     *
     * For now, this function returns 0 (no automatic discovery).
     * Use cyxchat_file_retrieve_dht_chunks() with a known file_id instead.
     */
    CYXWIZ_DEBUG("DHT offer check called - requires file_id hint for lookup");

    return 0;
}

int cyxchat_file_get_transfer_mode(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
) {
    if (!ctx || !file_id) {
        return -1;
    }

    file_transfer_slot_t *slot = find_transfer(ctx, file_id);
    if (!slot) {
        return -1;
    }

    return (int)slot->transfer.mode;
}

