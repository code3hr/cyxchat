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
    uint16_t chunks_received;               /* Bitmap for received chunks */
    int active;
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
    cyxwiz_secure_zero(&slot->transfer.meta.file_key, 32);
    memset(slot, 0, sizeof(file_transfer_slot_t));
    ctx->transfer_count--;
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

int cyxchat_file_poll(cyxchat_file_ctx_t *ctx, uint64_t now_ms) {
    if (!ctx) return 0;

    int events = 0;

    /* Check for timeouts, retransmits, etc. */
    for (size_t i = 0; i < CYXCHAT_MAX_TRANSFERS; i++) {
        file_transfer_slot_t *slot = &ctx->transfers[i];
        if (!slot->active) continue;

        /* Check for stalled transfers (no update in 30 seconds) */
        if (slot->transfer.state == CYXCHAT_FILE_SENDING ||
            slot->transfer.state == CYXCHAT_FILE_RECEIVING) {
            if (now_ms - slot->transfer.updated_at > 30000) {
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

    /* Build and send metadata message */
    cyxchat_file_meta_msg_t meta_msg;
    memset(&meta_msg, 0, sizeof(meta_msg));

    meta_msg.header.version = CYXCHAT_PROTOCOL_VERSION;
    meta_msg.header.type = CYXCHAT_MSG_FILE_META;
    meta_msg.header.timestamp = cyxchat_timestamp_ms();
    cyxchat_generate_msg_id(&meta_msg.header.msg_id);

    memcpy(&meta_msg.file_id, &slot->transfer.meta.file_id, sizeof(cyxchat_file_id_t));
    memcpy(meta_msg.filename, slot->transfer.meta.filename, CYXCHAT_MAX_FILENAME);
    memcpy(meta_msg.mime_type, slot->transfer.meta.mime_type, 64);
    meta_msg.size = slot->transfer.meta.size;
    meta_msg.chunk_count = chunk_count;
    memcpy(meta_msg.file_hash, slot->transfer.meta.file_hash, 32);

    /* TODO: Encrypt file_key for recipient and store in meta_msg.encrypted_key */
    /* TODO: Send meta_msg via onion */

    slot->transfer.state = CYXCHAT_FILE_SENDING;

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

