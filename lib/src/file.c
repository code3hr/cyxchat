/**
 * CyxChat File Transfer Implementation
 */

#include <cyxchat/file.h>
#include <cyxchat/chat.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/memory.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef _WIN32
#include <windows.h>
#define CHUNK_DELAY_MS(ms) Sleep(ms)
#else
#include <unistd.h>
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
} file_transfer_slot_t;

struct cyxchat_file_ctx {
    cyxchat_ctx_t *chat_ctx;

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

static uint16_t count_received_chunks(file_transfer_slot_t *slot) {
    if (!slot->chunk_bitmap) return 0;
    uint16_t count = 0;
    for (uint16_t i = 0; i < slot->transfer.meta.chunk_count; i++) {
        if (is_chunk_received(slot, i)) count++;
    }
    return count;
}

static uint16_t find_next_missing_chunk(file_transfer_slot_t *slot, uint16_t start) {
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
static uint8_t* encrypt_file_data(
    const uint8_t *plaintext,
    size_t plaintext_len,
    const uint8_t key[32],
    uint8_t nonce_out[24],
    size_t *encrypted_len_out
) {
    /* Generate random nonce */
    cyxwiz_crypto_random(nonce_out, 24);

    /* Allocate buffer for encrypted data (plaintext + 16 bytes auth tag) */
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
static uint8_t* decrypt_file_data(
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
static cyxchat_file_transfer_mode_t select_transfer_mode(
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
    uint8_t chunk_buf[150];  /* Fits in onion payload */
    size_t chunk_wire_len = 0;

    chunk_buf[chunk_wire_len++] = CYXCHAT_MSG_FILE_CHUNK;
    memcpy(chunk_buf + chunk_wire_len, slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
    chunk_wire_len += CYXCHAT_FILE_ID_SIZE;

    /* Chunk index (2 bytes little-endian) */
    chunk_buf[chunk_wire_len++] = (uint8_t)(chunk_idx & 0xFF);
    chunk_buf[chunk_wire_len++] = (uint8_t)((chunk_idx >> 8) & 0xFF);

    /* Calculate chunk data offset and length */
    size_t offset = (size_t)chunk_idx * CYXCHAT_CHUNK_SIZE;
    size_t remaining = slot->transfer.meta.size - offset;
    uint16_t chunk_len = (remaining > CYXCHAT_CHUNK_SIZE) ? CYXCHAT_CHUNK_SIZE : (uint16_t)remaining;

    /* Chunk length (2 bytes) */
    chunk_buf[chunk_wire_len++] = (uint8_t)(chunk_len & 0xFF);
    chunk_buf[chunk_wire_len++] = (uint8_t)((chunk_len >> 8) & 0xFF);

    /* Chunk data */
    memcpy(chunk_buf + chunk_wire_len, slot->data + offset, chunk_len);
    chunk_wire_len += chunk_len;

    cyxchat_send_raw(ctx->chat_ctx, &slot->transfer.peer, chunk_buf, chunk_wire_len);
    slot->transfer.chunks_done++;
    slot->transfer.updated_at = cyxchat_timestamp_ms();
    slot->last_chunk_sent_ms = slot->transfer.updated_at;
}

int cyxchat_file_poll(cyxchat_file_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;

    int events = 0;

    /* Check for timeouts, retransmits, and send pending chunks */
    for (size_t i = 0; i < CYXCHAT_MAX_TRANSFERS; i++) {
        file_transfer_slot_t *slot = &ctx->transfers[i];
        if (!slot->active) continue;

        /* For outgoing transfers, send chunks with delay */
        if (slot->transfer.is_outgoing && slot->transfer.state == CYXCHAT_FILE_SENDING) {
            /* Send one chunk per poll if enough time has passed */
            if (slot->transfer.chunks_done < slot->transfer.meta.chunk_count) {
                uint64_t delay_ms = (slot->transfer.chunks_done == 0) ? 0 : 500;  /* 500ms between chunks */
                if (now_ms - slot->last_chunk_sent_ms >= delay_ms) {
                    send_next_chunk(ctx, slot);
                    events++;
                }
            } else {
                /* All chunks sent, mark as completed */
                slot->transfer.state = CYXCHAT_FILE_COMPLETED;
                if (ctx->on_complete) {
                    ctx->on_complete(ctx, &slot->transfer.meta.file_id,
                                    slot->data, slot->transfer.meta.size,
                                    ctx->on_complete_data);
                }
                events++;
            }
        }

        /* Check for stalled transfers (no update in 60 seconds for file transfers) */
        if (slot->transfer.state == CYXCHAT_FILE_SENDING ||
            slot->transfer.state == CYXCHAT_FILE_RECEIVING) {
            if (now_ms - slot->transfer.updated_at > 60000) {
                slot->transfer.state = CYXCHAT_FILE_FAILED;

                if (ctx->on_error) {
                    ctx->on_error(ctx, &slot->transfer.meta.file_id,
                                 CYXCHAT_ERR_TIMEOUT, ctx->on_error_data);
                }
                events++;
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
    if (!ctx || !to || !filename || !data || data_len == 0) {
        return CYXCHAT_ERR_NULL;
    }

    /* Calculate chunk count */
    uint16_t chunk_count = (uint16_t)((data_len + CYXCHAT_CHUNK_SIZE - 1) / CYXCHAT_CHUNK_SIZE);

    /* Allocate transfer slot */
    file_transfer_slot_t *slot = alloc_transfer(ctx);
    if (!slot) {
        return CYXCHAT_ERR_FULL;
    }

    /* Generate file ID and key */
    cyxwiz_crypto_random(slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
    cyxwiz_crypto_random(slot->transfer.meta.file_key, 32);

    /* Set metadata */
    strncpy(slot->transfer.meta.filename, filename, CYXCHAT_MAX_FILENAME - 1);
    if (mime_type) {
        strncpy(slot->transfer.meta.mime_type, mime_type, 63);
    } else {
        /* Detect from extension */
        const char *detected = cyxchat_file_detect_mime(filename);
        strncpy(slot->transfer.meta.mime_type, detected, 63);
    }
    slot->transfer.meta.size = (uint32_t)data_len;
    slot->transfer.meta.chunk_count = chunk_count;

    /* Hash file */
    cyxwiz_crypto_hash(data, data_len, slot->transfer.meta.file_hash, 32);

    /* Copy peer and state */
    memcpy(&slot->transfer.peer, to, sizeof(cyxwiz_node_id_t));
    slot->transfer.state = CYXCHAT_FILE_PENDING;
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

    /* Build and send metadata message using compact wire format */
    /* Wire format: type(1) + file_id(8) + filename_len(1) + filename(N) +
     *              mime_len(1) + mime(N) + size(4) + chunk_count(2) + file_hash(32) */
    uint8_t wire_buf[250];
    size_t wire_len = 0;

    wire_buf[wire_len++] = CYXCHAT_MSG_FILE_META;
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
    cyxchat_error_t send_err = cyxchat_send_raw(ctx->chat_ctx, to, wire_buf, wire_len);
    if (send_err != CYXCHAT_OK) {
        free_transfer(ctx, slot);
        return send_err;
    }

    slot->transfer.state = CYXCHAT_FILE_SENDING;

    /* For small files (<= 1 chunk), send the data immediately after metadata */
    if (chunk_count == 1) {
        /* Single chunk - send immediately */
        uint8_t chunk_buf[250];
        size_t chunk_wire_len = 0;

        chunk_buf[chunk_wire_len++] = CYXCHAT_MSG_FILE_CHUNK;
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
        /* Multi-chunk: send all chunks */
        for (uint16_t i = 0; i < chunk_count; i++) {
            uint8_t chunk_buf[250];
            size_t chunk_wire_len = 0;

            chunk_buf[chunk_wire_len++] = CYXCHAT_MSG_FILE_CHUNK;
            memcpy(chunk_buf + chunk_wire_len, slot->transfer.meta.file_id.bytes, CYXCHAT_FILE_ID_SIZE);
            chunk_wire_len += CYXCHAT_FILE_ID_SIZE;

            /* Chunk index (2 bytes little-endian) */
            chunk_buf[chunk_wire_len++] = (uint8_t)(i & 0xFF);
            chunk_buf[chunk_wire_len++] = (uint8_t)((i >> 8) & 0xFF);

            /* Calculate chunk data offset and length */
            size_t offset = (size_t)i * CYXCHAT_CHUNK_SIZE;
            size_t remaining = data_len - offset;
            uint16_t chunk_len = (remaining > CYXCHAT_CHUNK_SIZE) ? CYXCHAT_CHUNK_SIZE : (uint16_t)remaining;

            /* Chunk length (2 bytes) */
            chunk_buf[chunk_wire_len++] = (uint8_t)(chunk_len & 0xFF);
            chunk_buf[chunk_wire_len++] = (uint8_t)((chunk_len >> 8) & 0xFF);

            /* Chunk data - limit to fit in wire buffer */
            if (chunk_wire_len + chunk_len > sizeof(chunk_buf)) {
                chunk_len = (uint16_t)(sizeof(chunk_buf) - chunk_wire_len);
            }
            memcpy(chunk_buf + chunk_wire_len, data + offset, chunk_len);
            chunk_wire_len += chunk_len;

            cyxchat_send_raw(ctx->chat_ctx, to, chunk_buf, chunk_wire_len);
            slot->transfer.chunks_done = i + 1;
            slot->transfer.updated_at = cyxchat_timestamp_ms();

            /* Small delay between chunks to avoid rate limiting */
            if (i < chunk_count - 1) {
                CHUNK_DELAY_MS(100);  /* 100ms delay between chunks */
            }
        }
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

    /* TODO: Send accept message to sender */

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

    /* TODO: Send reject message */

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

    /* TODO: Send cancel message to peer */

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
    /* Parse wire format:
     * file_id(8) + filename_len(1) + filename(N) + mime_len(1) + mime(N) +
     * size(4) + chunk_count(2) + file_hash(32) */
    size_t offset = 0;

    if (data_len < 8 + 1) return CYXCHAT_ERR_INVALID;

    /* File ID */
    cyxchat_file_id_t file_id;
    memcpy(file_id.bytes, data + offset, CYXCHAT_FILE_ID_SIZE);
    offset += CYXCHAT_FILE_ID_SIZE;

    /* Filename */
    uint8_t fname_len = data[offset++];
    if (offset + fname_len > data_len) return CYXCHAT_ERR_INVALID;
    char filename[CYXCHAT_MAX_FILENAME] = {0};
    memcpy(filename, data + offset, fname_len);
    offset += fname_len;

    /* MIME type */
    if (offset >= data_len) return CYXCHAT_ERR_INVALID;
    uint8_t mime_len = data[offset++];
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
    strncpy(slot->transfer.meta.filename, filename, CYXCHAT_MAX_FILENAME - 1);
    strncpy(slot->transfer.meta.mime_type, mime_type, 63);
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

    /* Pre-allocate receive buffer for auto-accept */
    slot->data = calloc(1, size);
    if (slot->data) {
        slot->data_capacity = size;
        slot->transfer.state = CYXCHAT_FILE_RECEIVING;
    }

    /* Notify callback */
    if (ctx->on_request) {
        ctx->on_request(ctx, from, &slot->transfer.meta, ctx->on_request_data);
    }

    return CYXCHAT_OK;
}

static cyxchat_error_t handle_file_chunk(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t data_len
) {
    /* Parse wire format: file_id(8) + chunk_idx(2) + chunk_len(2) + data(N) */
    if (data_len < 8 + 2 + 2) return CYXCHAT_ERR_INVALID;

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

    /* Copy chunk data to buffer */
    size_t data_offset = (size_t)chunk_idx * CYXCHAT_CHUNK_SIZE;
    if (data_offset + chunk_len <= slot->data_capacity) {
        memcpy(slot->data + data_offset, data + offset, chunk_len);
        slot->transfer.chunks_done++;
        slot->transfer.updated_at = cyxchat_timestamp_ms();

        /* Notify progress */
        if (ctx->on_progress) {
            ctx->on_progress(ctx, &file_id,
                            slot->transfer.chunks_done,
                            slot->transfer.meta.chunk_count,
                            ctx->on_progress_data);
        }

        /* Check if complete */
        if (slot->transfer.chunks_done >= slot->transfer.meta.chunk_count) {
            slot->transfer.state = CYXCHAT_FILE_COMPLETED;

            /* Notify completion */
            if (ctx->on_complete) {
                ctx->on_complete(ctx, &file_id, slot->data,
                                slot->transfer.meta.size, ctx->on_complete_data);
            }
        }
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
    strncpy(slot->transfer.meta.filename, filename, CYXCHAT_MAX_FILENAME - 1);
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
        ctx->on_request(ctx, from, &slot->transfer.meta, ctx->on_request_data);
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
            ctx->on_complete(ctx, &file_id, slot->data,
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
            /* TODO: Handle acknowledgments for reliable transfer */
            return CYXCHAT_OK;

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

        default:
            return CYXCHAT_ERR_INVALID;
    }
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

    /* Compute DHT key for offer */
    uint8_t dht_key[32];
    compute_offer_dht_key(&slot->transfer.peer, file_id, dht_key);

    /* TODO: Store offer in DHT using cyxwiz_dht_put() */
    /* This requires access to the DHT context from the chat layer */
    /* For now, just mark the mode */
    slot->transfer.mode = CYXCHAT_FILE_MODE_DHT_SIGNAL;

    (void)dht_key;  /* Will be used when DHT integration is complete */

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

    /* Check size limit for DHT storage */
    if (slot->transfer.meta.size > CYXCHAT_DHT_MAX_FILE_SIZE) {
        return CYXCHAT_ERR_FILE_TOO_LARGE;
    }

    /* Store each chunk in DHT */
    uint16_t dht_chunk_count = (uint16_t)((slot->transfer.meta.size + CYXCHAT_DHT_CHUNK_SIZE - 1)
                                           / CYXCHAT_DHT_CHUNK_SIZE);

    for (uint16_t i = 0; i < dht_chunk_count; i++) {
        uint8_t dht_key[32];
        compute_chunk_dht_key(slot->transfer.meta.file_hash, i, dht_key);

        size_t offset = (size_t)i * CYXCHAT_DHT_CHUNK_SIZE;
        size_t remaining = slot->transfer.meta.size - offset;
        size_t len = (remaining > CYXCHAT_DHT_CHUNK_SIZE) ? CYXCHAT_DHT_CHUNK_SIZE : remaining;

        /* TODO: Store chunk in DHT using cyxwiz_dht_put() */
        /* cyxwiz_dht_put(dht, dht_key, slot->data + offset, len, CYXCHAT_DHT_TTL_SECONDS); */

        (void)dht_key;
        (void)len;
    }

    slot->transfer.mode = CYXCHAT_FILE_MODE_DHT_MICRO;

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_file_retrieve_dht_chunks(
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

    /* Retrieve each chunk from DHT */
    uint16_t dht_chunk_count = (uint16_t)((slot->transfer.meta.size + CYXCHAT_DHT_CHUNK_SIZE - 1)
                                           / CYXCHAT_DHT_CHUNK_SIZE);

    for (uint16_t i = 0; i < dht_chunk_count; i++) {
        if (is_chunk_received(slot, i)) continue;  /* Already have this chunk */

        uint8_t dht_key[32];
        compute_chunk_dht_key(slot->transfer.meta.file_hash, i, dht_key);

        /* TODO: Retrieve chunk from DHT using cyxwiz_dht_get() */
        /* This is async, so we'd need callbacks to handle the response */

        (void)dht_key;
    }

    slot->transfer.state = CYXCHAT_FILE_RECEIVING;

    return CYXCHAT_OK;
}

int cyxchat_file_check_dht_offers(cyxchat_file_ctx_t *ctx) {
    if (!ctx) {
        return -1;
    }

    /* TODO: Query DHT for pending offers addressed to us */
    /* This requires knowing our own node ID and querying with our offer DHT key */

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
