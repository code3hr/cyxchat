/**
 * CyxChat Relay Client
 *
 * Relay fallback for when direct UDP hole punching fails.
 * All data remains end-to-end encrypted - relay nodes cannot
 * read message content.
 */

#ifndef CYXCHAT_RELAY_H
#define CYXCHAT_RELAY_H

#include "types.h"
#include <cyxwiz/transport.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Configuration
 * ============================================================ */

#define CYXCHAT_MAX_RELAY_SERVERS       4       /* Max relay servers */
#define CYXCHAT_MAX_RELAY_CONNECTIONS   16      /* Max relayed connections */
#define CYXCHAT_RELAY_TIMEOUT_MS        10000   /* Relay connection timeout */
#define CYXCHAT_RELAY_KEEPALIVE_MS      30000   /* Keepalive interval */

/* ============================================================
 * Relay Protocol Message Types
 * ============================================================ */

#define CYXCHAT_RELAY_CONNECT           0xE0    /* Connect via relay */
#define CYXCHAT_RELAY_CONNECT_ACK       0xE1    /* Connection acknowledged */
#define CYXCHAT_RELAY_DISCONNECT        0xE2    /* Disconnect */
#define CYXCHAT_RELAY_DATA              0xE3    /* Relayed data */
#define CYXCHAT_RELAY_KEEPALIVE         0xE4    /* Keepalive */
#define CYXCHAT_RELAY_ERROR             0xE5    /* Error response */

/* ============================================================
 * Context
 * ============================================================ */

typedef struct cyxchat_relay_ctx cyxchat_relay_ctx_t;

/* ============================================================
 * Relay Connection Info
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t peer_id;           /* Remote peer ID */
    uint64_t connected_at;              /* Connection timestamp */
    uint64_t last_activity;             /* Last activity timestamp */
    uint32_t bytes_sent;                /* Bytes sent via relay */
    uint32_t bytes_received;            /* Bytes received via relay */
    int active;                         /* Connection active */
} cyxchat_relay_conn_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

/**
 * Data received via relay callback
 */
typedef void (*cyxchat_relay_data_callback_t)(
    cyxchat_relay_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len,
    void *user_data
);

/**
 * Relay connection state callback
 */
typedef void (*cyxchat_relay_state_callback_t)(
    cyxchat_relay_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    int connected,
    void *user_data
);

/* ============================================================
 * Lifecycle
 * ============================================================ */

/**
 * Create relay context
 *
 * @param ctx           Output: created context
 * @param transport     Underlying transport for relay communication
 * @param local_id      Our node ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_relay_create(
    cyxchat_relay_ctx_t **ctx,
    cyxwiz_transport_t *transport,
    const cyxwiz_node_id_t *local_id
);

/**
 * Destroy relay context
 */
CYXCHAT_API void cyxchat_relay_destroy(cyxchat_relay_ctx_t *ctx);

/**
 * Process relay events
 *
 * @param ctx           Relay context
 * @param now_ms        Current timestamp
 * @return              Number of events processed
 */
CYXCHAT_API int cyxchat_relay_poll(cyxchat_relay_ctx_t *ctx, uint64_t now_ms);

/* ============================================================
 * Relay Server Management
 * ============================================================ */

/**
 * Add relay server
 *
 * @param ctx           Relay context
 * @param addr          Server address (IP:port string)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_relay_add_server(
    cyxchat_relay_ctx_t *ctx,
    const char *addr
);

/**
 * Get number of configured relay servers
 */
CYXCHAT_API size_t cyxchat_relay_server_count(cyxchat_relay_ctx_t *ctx);

/* ============================================================
 * Connection Management
 * ============================================================ */

/**
 * Connect to peer via relay
 *
 * @param ctx           Relay context
 * @param peer_id       Peer to connect to
 * @return              CYXCHAT_OK if initiated
 */
CYXCHAT_API cyxchat_error_t cyxchat_relay_connect(
    cyxchat_relay_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id
);

/**
 * Disconnect from peer via relay
 */
CYXCHAT_API cyxchat_error_t cyxchat_relay_disconnect(
    cyxchat_relay_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id
);

/**
 * Check if peer is connected via relay
 */
CYXCHAT_API int cyxchat_relay_is_connected(
    cyxchat_relay_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id
);

/**
 * Get relay connection info
 */
CYXCHAT_API cyxchat_error_t cyxchat_relay_get_info(
    cyxchat_relay_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    cyxchat_relay_conn_t *info_out
);

/* ============================================================
 * Data Transfer
 * ============================================================ */

/**
 * Send data via relay
 *
 * Data is forwarded through relay server to destination peer.
 * Content is end-to-end encrypted (relay cannot read it).
 *
 * @param ctx           Relay context
 * @param peer_id       Destination peer
 * @param data          Data to send
 * @param len           Data length
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_relay_send(
    cyxchat_relay_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    const uint8_t *data,
    size_t len
);

/* ============================================================
 * Callbacks
 * ============================================================ */

/**
 * Set data received callback
 */
CYXCHAT_API void cyxchat_relay_set_on_data(
    cyxchat_relay_ctx_t *ctx,
    cyxchat_relay_data_callback_t callback,
    void *user_data
);

/**
 * Set connection state callback
 */
CYXCHAT_API void cyxchat_relay_set_on_state(
    cyxchat_relay_ctx_t *ctx,
    cyxchat_relay_state_callback_t callback,
    void *user_data
);

/* ============================================================
 * Message Handling
 * ============================================================ */

/**
 * Handle incoming relay message
 *
 * Call this when a message is received that may be a relay protocol
 * message (types 0xE0-0xE5).
 *
 * @param ctx           Relay context
 * @param data          Message data
 * @param len           Message length
 * @return              CYXCHAT_OK if handled, CYXCHAT_ERR_INVALID if not a relay msg
 */
CYXCHAT_API cyxchat_error_t cyxchat_relay_handle_message(
    cyxchat_relay_ctx_t *ctx,
    const uint8_t *data,
    size_t len
);

/**
 * Check if message type is a relay message
 */
CYXCHAT_API int cyxchat_relay_is_relay_message(uint8_t msg_type);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_RELAY_H */
