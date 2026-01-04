/**
 * CyxChat File Transfer API
 * File sharing functionality
 */

#ifndef CYXCHAT_FILE_H
#define CYXCHAT_FILE_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Forward declaration */
typedef struct cyxchat_ctx cyxchat_ctx_t;

/* ============================================================
 * File Transfer State
 * ============================================================ */

typedef enum {
    CYXCHAT_FILE_PENDING    = 0,    /* Not started */
    CYXCHAT_FILE_SENDING    = 1,    /* Sending chunks */
    CYXCHAT_FILE_RECEIVING  = 2,    /* Receiving chunks */
    CYXCHAT_FILE_PAUSED     = 3,    /* Paused */
    CYXCHAT_FILE_COMPLETED  = 4,    /* Transfer complete */
    CYXCHAT_FILE_FAILED     = 5,    /* Transfer failed */
    CYXCHAT_FILE_CANCELLED  = 6     /* Cancelled by user */
} cyxchat_file_state_t;

/* ============================================================
 * File Metadata
 * ============================================================ */

typedef struct {
    cyxchat_file_id_t file_id;
    char filename[CYXCHAT_MAX_FILENAME];
    char mime_type[64];
    uint32_t size;                          /* Total size in bytes */
    uint16_t chunk_count;                   /* Total chunks */
    uint8_t file_key[32];                   /* Encryption key */
    uint8_t nonce[24];                      /* XChaCha20 nonce */
    uint8_t file_hash[32];                  /* BLAKE2b hash of encrypted content */
    uint8_t encrypted_key[48];              /* File key sealed for recipient */
} cyxchat_file_meta_t;

/* ============================================================
 * File Transfer
 * ============================================================ */

typedef struct {
    cyxchat_file_meta_t meta;
    cyxwiz_node_id_t peer;                  /* Other party */
    cyxchat_file_state_t state;
    cyxchat_file_transfer_mode_t mode;      /* Transfer mode (direct, relay, DHT) */
    uint16_t chunks_done;                   /* Chunks transferred */
    uint64_t started_at;
    uint64_t updated_at;
    int is_outgoing;                        /* 1 = sending, 0 = receiving */
} cyxchat_file_transfer_t;

/* ============================================================
 * File Messages
 * ============================================================ */

/* File metadata message (sent first) */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_file_id_t file_id;
    char filename[CYXCHAT_MAX_FILENAME];
    char mime_type[64];
    uint32_t size;
    uint16_t chunk_count;
    uint8_t file_hash[32];
    uint8_t encrypted_key[48];              /* Key encrypted for recipient */
} cyxchat_file_meta_msg_t;

/* File chunk message */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_file_id_t file_id;
    uint16_t chunk_index;
    uint16_t chunk_len;
    uint8_t data[CYXCHAT_CHUNK_SIZE];
} cyxchat_file_chunk_msg_t;

/* File chunk acknowledgment */
typedef struct {
    cyxchat_msg_header_t header;
    cyxchat_file_id_t file_id;
    uint16_t chunk_index;
    uint8_t accepted;                       /* 1 = accepted, 0 = rejected */
} cyxchat_file_ack_msg_t;

/* ============================================================
 * File Transfer Protocol v2 Messages
 * ============================================================ */

/**
 * FILE_OFFER message (~150 bytes, fits LoRa 250-byte limit)
 * Sent to initiate a file transfer with encryption info
 */
typedef struct {
    uint8_t type;                           /* CYXCHAT_MSG_FILE_OFFER (0x40) */
    cyxchat_file_id_t file_id;              /* 8 bytes - unique file ID */
    uint8_t file_hash[32];                  /* BLAKE2b hash of encrypted content */
    uint32_t encrypted_size;                /* Size after encryption */
    uint16_t chunk_count;                   /* Total chunks */
    uint8_t filename_len;                   /* Filename length (max 64) */
    char filename[64];                      /* Truncated filename (UTF-8) */
    uint8_t nonce[24];                      /* XChaCha20 nonce */
    uint8_t encrypted_key[48];              /* File key sealed for recipient */
} cyxchat_file_offer_msg_t;

/**
 * FILE_ACCEPT message (12 bytes)
 * Sent to accept a file offer
 */
typedef struct {
    uint8_t type;                           /* CYXCHAT_MSG_FILE_ACCEPT (0x41) */
    cyxchat_file_id_t file_id;              /* 8 bytes */
    uint8_t transfer_mode;                  /* cyxchat_file_transfer_mode_t */
    uint16_t start_chunk;                   /* For resume: start from this chunk */
} cyxchat_file_accept_msg_t;

/**
 * FILE_REJECT message (10 bytes)
 * Sent to reject a file offer
 */
typedef struct {
    uint8_t type;                           /* CYXCHAT_MSG_FILE_REJECT (0x42) */
    cyxchat_file_id_t file_id;              /* 8 bytes */
    uint8_t reason;                         /* cyxchat_file_reject_reason_t */
} cyxchat_file_reject_msg_t;

/**
 * FILE_COMPLETE message (44 bytes)
 * Sent when transfer is complete
 */
typedef struct {
    uint8_t type;                           /* CYXCHAT_MSG_FILE_COMPLETE (0x43) */
    cyxchat_file_id_t file_id;              /* 8 bytes */
    uint8_t status;                         /* 0 = success, 1 = failed, 2 = cancelled */
    uint16_t chunks_received;               /* Number of chunks received */
    uint8_t verify_hash[32];                /* Hash of reassembled encrypted file */
} cyxchat_file_complete_msg_t;

/**
 * FILE_CANCEL message (9 bytes)
 * Sent to cancel an in-progress transfer
 */
typedef struct {
    uint8_t type;                           /* CYXCHAT_MSG_FILE_CANCEL (0x44) */
    cyxchat_file_id_t file_id;              /* 8 bytes */
} cyxchat_file_cancel_msg_t;

/**
 * FILE_DHT_READY message (11 bytes)
 * Notifies recipient that file chunks are stored in DHT
 */
typedef struct {
    uint8_t type;                           /* CYXCHAT_MSG_FILE_DHT_READY (0x45) */
    cyxchat_file_id_t file_id;              /* 8 bytes */
    uint16_t chunk_count;                   /* Number of chunks in DHT */
} cyxchat_file_dht_ready_msg_t;

/* ============================================================
 * File Transfer Context
 * ============================================================ */

typedef struct cyxchat_file_ctx cyxchat_file_ctx_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

typedef void (*cyxchat_on_file_request_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const cyxchat_file_meta_t *meta,
    void *user_data
);

typedef void (*cyxchat_on_file_progress_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id,
    uint16_t chunks_done,
    uint16_t chunks_total,
    void *user_data
);

typedef void (*cyxchat_on_file_complete_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id,
    const uint8_t *data,
    size_t data_len,
    void *user_data
);

typedef void (*cyxchat_on_file_error_t)(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id,
    cyxchat_error_t error,
    void *user_data
);

/* ============================================================
 * Initialization
 * ============================================================ */

CYXCHAT_API cyxchat_error_t cyxchat_file_ctx_create(
    cyxchat_file_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
);

CYXCHAT_API void cyxchat_file_ctx_destroy(cyxchat_file_ctx_t *ctx);

CYXCHAT_API int cyxchat_file_poll(cyxchat_file_ctx_t *ctx, uint64_t now_ms);

/* ============================================================
 * Sending Files
 * ============================================================ */

/**
 * Send file to peer
 *
 * @param ctx           File context
 * @param to            Recipient node ID
 * @param filename      Original filename
 * @param mime_type     MIME type (e.g., "image/png")
 * @param data          File data
 * @param data_len      File size in bytes
 * @param file_id_out   Output: file transfer ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_send(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *filename,
    const char *mime_type,
    const uint8_t *data,
    size_t data_len,
    cyxchat_file_id_t *file_id_out
);

/**
 * Send file from path
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_send_path(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *file_path,
    cyxchat_file_id_t *file_id_out
);

/* ============================================================
 * Receiving Files
 * ============================================================ */

/**
 * Accept incoming file transfer
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_accept(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Reject incoming file transfer
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_reject(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/* ============================================================
 * Transfer Control
 * ============================================================ */

/**
 * Cancel ongoing transfer
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_cancel(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Pause transfer
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_pause(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Resume paused transfer
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_resume(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/* ============================================================
 * Queries
 * ============================================================ */

/**
 * Get transfer by ID
 */
CYXCHAT_API cyxchat_file_transfer_t* cyxchat_file_find(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Get active transfer count
 */
CYXCHAT_API size_t cyxchat_file_active_count(cyxchat_file_ctx_t *ctx);

/**
 * Get transfer by index
 */
CYXCHAT_API cyxchat_file_transfer_t* cyxchat_file_get(
    cyxchat_file_ctx_t *ctx,
    size_t index
);

/* ============================================================
 * Callbacks
 * ============================================================ */

CYXCHAT_API void cyxchat_file_set_on_request(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_request_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_file_set_on_progress(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_progress_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_file_set_on_complete(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_complete_t callback,
    void *user_data
);

CYXCHAT_API void cyxchat_file_set_on_error(
    cyxchat_file_ctx_t *ctx,
    cyxchat_on_file_error_t callback,
    void *user_data
);

/* ============================================================
 * Message Handling (called by chat layer)
 * ============================================================ */

/**
 * Handle incoming file-related message
 * Called by the chat layer when it receives FILE_META, FILE_CHUNK, or FILE_ACK
 *
 * @param ctx           File context
 * @param from          Sender node ID
 * @param type          Message type (CYXCHAT_MSG_FILE_*)
 * @param data          Message data (after type byte)
 * @param data_len      Data length
 * @return              CYXCHAT_OK if handled
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_handle_message(
    cyxchat_file_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    uint8_t type,
    const uint8_t *data,
    size_t data_len
);

/* ============================================================
 * Utilities
 * ============================================================ */

CYXCHAT_API void cyxchat_file_id_to_hex(
    const cyxchat_file_id_t *id,
    char *hex_out
);

CYXCHAT_API cyxchat_error_t cyxchat_file_id_from_hex(
    const char *hex,
    cyxchat_file_id_t *id_out
);

/**
 * Detect MIME type from filename extension
 */
CYXCHAT_API const char* cyxchat_file_detect_mime(const char *filename);

/**
 * Get human-readable file size (e.g., "1.5 MB")
 */
CYXCHAT_API void cyxchat_file_format_size(
    uint32_t size_bytes,
    char *out,
    size_t out_len
);

/* ============================================================
 * DHT-Based Transfer (for offline recipients)
 * ============================================================ */

/**
 * Store file offer in DHT for offline recipient
 * The offer contains encrypted file metadata that only the recipient can decrypt.
 * Use this when the recipient is offline and cannot receive direct messages.
 *
 * @param ctx       File context
 * @param file_id   File transfer ID
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_store_offer(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Store small file chunks in DHT (for files <= CYXCHAT_DHT_MAX_FILE_SIZE)
 * Each chunk is stored with a deterministic key derived from the file hash.
 * Only call this for files small enough to fit entirely in DHT.
 *
 * @param ctx       File context
 * @param file_id   File transfer ID
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_store_dht_chunks(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Retrieve file chunks from DHT
 * Call this when you receive a FILE_DHT_READY notification or find a stored offer.
 *
 * @param ctx       File context
 * @param file_id   File transfer ID
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_file_retrieve_dht_chunks(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

/**
 * Check DHT for pending file offers addressed to us
 * Call this periodically or when coming online to check for offline files.
 *
 * @param ctx       File context
 * @return          Number of pending offers found, or negative error code
 */
CYXCHAT_API int cyxchat_file_check_dht_offers(cyxchat_file_ctx_t *ctx);

/**
 * Get the transfer mode for a file transfer
 *
 * @param ctx       File context
 * @param file_id   File transfer ID
 * @return          Transfer mode, or -1 if not found
 */
CYXCHAT_API int cyxchat_file_get_transfer_mode(
    cyxchat_file_ctx_t *ctx,
    const cyxchat_file_id_t *file_id
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_FILE_H */
