/**
 * CyxChat Connection Management
 *
 * NAT traversal and peer-to-peer connection management.
 * Wraps CyxWiz transport layer with connection state tracking
 * and automatic relay fallback.
 */

#ifndef CYXCHAT_CONNECTION_H
#define CYXCHAT_CONNECTION_H

#include "types.h"
#include <cyxwiz/transport.h>
#include <cyxwiz/peer.h>
#include <cyxwiz/onion.h>
#include <cyxwiz/dht.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Configuration
 * ============================================================ */

#define CYXCHAT_MAX_PEER_CONNECTIONS    32      /* Max simultaneous connections */
#define CYXCHAT_HOLE_PUNCH_TIMEOUT_MS   5000    /* Time before relay fallback */
#define CYXCHAT_HOLE_PUNCH_ATTEMPTS     5       /* Punch attempts */
#define CYXCHAT_HOLE_PUNCH_INTERVAL_MS  50      /* Between attempts */
#define CYXCHAT_KEEPALIVE_INTERVAL_MS   30000   /* Keepalive interval */
#define CYXCHAT_CONNECTION_TIMEOUT_MS   90000   /* Peer timeout */
#define CYXCHAT_STUN_INTERVAL_MS        60000   /* STUN refresh interval */

/* ============================================================
 * Connection States
 * ============================================================ */

typedef enum {
    CYXCHAT_CONN_DISCONNECTED = 0,      /* No connection */
    CYXCHAT_CONN_DISCOVERING,           /* STUN discovery in progress */
    CYXCHAT_CONN_CONNECTING,            /* Hole punch in progress */
    CYXCHAT_CONN_RELAYING,              /* Connected via relay */
    CYXCHAT_CONN_CONNECTED              /* Direct P2P connection */
} cyxchat_conn_state_t;

/* ============================================================
 * Connection Info
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t peer_id;           /* Peer node ID */
    cyxchat_conn_state_t state;         /* Current state */
    uint64_t connected_at;              /* Connection timestamp */
    uint64_t last_activity;             /* Last activity timestamp */
    uint32_t bytes_sent;                /* Bytes sent */
    uint32_t bytes_received;            /* Bytes received */
    int8_t rssi;                        /* Signal strength (if available) */
    int is_relayed;                     /* 1 if via relay, 0 if direct */
} cyxchat_conn_info_t;

/* Network status */
typedef struct {
    uint32_t public_ip;                 /* Public IP (network byte order) */
    uint16_t public_port;               /* Public port (network byte order) */
    cyxwiz_nat_type_t nat_type;         /* Detected NAT type */
    int stun_complete;                  /* STUN discovery complete */
    int bootstrap_connected;            /* Connected to bootstrap server */
    size_t active_connections;          /* Number of active connections */
    size_t relay_connections;           /* Number of relay connections */
    /* DHT status */
    int dht_enabled;                    /* DHT is active */
    size_t dht_nodes;                   /* Nodes in DHT routing table */
    size_t dht_active_buckets;          /* Non-empty DHT buckets */
} cyxchat_network_status_t;

/* ============================================================
 * Context
 * ============================================================ */

typedef struct cyxchat_conn_ctx cyxchat_conn_ctx_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

/**
 * Connection state change callback
 */
typedef void (*cyxchat_conn_state_callback_t)(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    cyxchat_conn_state_t old_state,
    cyxchat_conn_state_t new_state,
    void *user_data
);

/**
 * Data received callback
 */
typedef void (*cyxchat_conn_data_callback_t)(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len,
    void *user_data
);

/**
 * Connection complete callback (for async connect)
 */
typedef void (*cyxchat_conn_complete_callback_t)(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    cyxchat_conn_state_t state,
    cyxchat_error_t result,
    void *user_data
);

/* ============================================================
 * Lifecycle
 * ============================================================ */

/**
 * Create connection context
 *
 * @param ctx           Output: created context
 * @param bootstrap     Bootstrap server address (IP:port string, e.g. "1.2.3.4:19850")
 * @param local_id      Our node ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_create(
    cyxchat_conn_ctx_t **ctx,
    const char *bootstrap,
    const cyxwiz_node_id_t *local_id
);

/**
 * Destroy connection context
 */
CYXCHAT_API void cyxchat_conn_destroy(cyxchat_conn_ctx_t *ctx);

/**
 * Process events (call from main loop)
 *
 * @param ctx           Connection context
 * @param now_ms        Current timestamp in milliseconds
 * @return              Number of events processed
 */
CYXCHAT_API int cyxchat_conn_poll(cyxchat_conn_ctx_t *ctx, uint64_t now_ms);

/* ============================================================
 * Connection Management
 * ============================================================ */

/**
 * Initiate connection to peer
 *
 * Attempts direct P2P connection via UDP hole punching.
 * Falls back to relay if direct connection fails.
 *
 * @param ctx           Connection context
 * @param peer_id       Peer to connect to
 * @param callback      Called when connection completes (or NULL)
 * @param user_data     Passed to callback
 * @return              CYXCHAT_OK if initiated, error otherwise
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_connect(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    cyxchat_conn_complete_callback_t callback,
    void *user_data
);

/**
 * Disconnect from peer
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_disconnect(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id
);

/**
 * Get connection state for peer
 */
CYXCHAT_API cyxchat_conn_state_t cyxchat_conn_get_state(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id
);

/**
 * Get detailed connection info for peer
 *
 * @param ctx           Connection context
 * @param peer_id       Peer to query
 * @param info_out      Output: connection info
 * @return              CYXCHAT_OK if found, CYXCHAT_ERR_NOT_FOUND otherwise
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_get_info(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    cyxchat_conn_info_t *info_out
);

/**
 * Check if connection is using relay
 */
CYXCHAT_API int cyxchat_conn_is_relayed(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id
);

/* ============================================================
 * Data Transfer
 * ============================================================ */

/**
 * Send data to peer
 *
 * Automatically uses direct or relay connection based on state.
 *
 * @param ctx           Connection context
 * @param peer_id       Destination peer
 * @param data          Data to send
 * @param len           Data length
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_send(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    const uint8_t *data,
    size_t len
);

/* ============================================================
 * Network Status
 * ============================================================ */

/**
 * Get network status
 */
CYXCHAT_API void cyxchat_conn_get_status(
    cyxchat_conn_ctx_t *ctx,
    cyxchat_network_status_t *status_out
);

/**
 * Get public address as string
 *
 * @param ctx           Connection context
 * @param buf           Output buffer
 * @param buf_size      Buffer size (at least 22 bytes for "xxx.xxx.xxx.xxx:xxxxx")
 * @return              CYXCHAT_OK on success, CYXCHAT_ERR_NETWORK if not discovered yet
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_get_public_addr(
    cyxchat_conn_ctx_t *ctx,
    char *buf,
    size_t buf_size
);

/**
 * Get NAT type name string
 */
CYXCHAT_API const char* cyxchat_conn_nat_type_name(cyxwiz_nat_type_t nat_type);

/**
 * Get connection state name string
 */
CYXCHAT_API const char* cyxchat_conn_state_name(cyxchat_conn_state_t state);

/* ============================================================
 * Callbacks
 * ============================================================ */

/**
 * Set state change callback
 */
CYXCHAT_API void cyxchat_conn_set_on_state_change(
    cyxchat_conn_ctx_t *ctx,
    cyxchat_conn_state_callback_t callback,
    void *user_data
);

/**
 * Set data received callback
 */
CYXCHAT_API void cyxchat_conn_set_on_data(
    cyxchat_conn_ctx_t *ctx,
    cyxchat_conn_data_callback_t callback,
    void *user_data
);

/* ============================================================
 * Relay Management
 * ============================================================ */

/**
 * Add relay server
 *
 * @param ctx           Connection context
 * @param relay_addr    Relay address (IP:port string)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_add_relay(
    cyxchat_conn_ctx_t *ctx,
    const char *relay_addr
);

/**
 * Get number of active relay connections
 */
CYXCHAT_API size_t cyxchat_conn_relay_count(cyxchat_conn_ctx_t *ctx);

/**
 * Force relay for specific peer (for testing or known symmetric NAT)
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_force_relay(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id
);

/* ============================================================
 * Access to Underlying Transport
 * ============================================================ */

/**
 * Get underlying CyxWiz transport
 * (Advanced use only)
 */
CYXCHAT_API cyxwiz_transport_t* cyxchat_conn_get_transport(
    cyxchat_conn_ctx_t *ctx
);

/**
 * Get underlying peer table
 * (Advanced use only)
 */
CYXCHAT_API cyxwiz_peer_table_t* cyxchat_conn_get_peer_table(
    cyxchat_conn_ctx_t *ctx
);

/**
 * Get onion routing context
 * (For use with chat module)
 */
CYXCHAT_API cyxwiz_onion_ctx_t* cyxchat_conn_get_onion(
    cyxchat_conn_ctx_t *ctx
);

/**
 * Get DHT context
 * (Advanced use only)
 */
CYXCHAT_API cyxwiz_dht_t* cyxchat_conn_get_dht(
    cyxchat_conn_ctx_t *ctx
);

/* ============================================================
 * DHT (Distributed Hash Table) for Peer Discovery
 * ============================================================ */

/**
 * Callback for DHT node lookup completion
 */
typedef void (*cyxchat_dht_find_callback_t)(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *target,
    int found,
    void *user_data
);

/**
 * Callback when new node discovered via DHT
 */
typedef void (*cyxchat_dht_node_callback_t)(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id,
    void *user_data
);

/**
 * Bootstrap DHT with seed nodes
 *
 * @param ctx         Connection context
 * @param seed_nodes  Array of seed node IDs
 * @param count       Number of seed nodes
 * @return            CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_dht_bootstrap(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *seed_nodes,
    size_t count
);

/**
 * Add a known node to DHT routing table
 *
 * @param ctx      Connection context
 * @param node_id  Node to add
 * @return         CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_dht_add_node(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
);

/**
 * Find a node via DHT (iterative lookup)
 *
 * @param ctx        Connection context
 * @param target     Target node ID to find
 * @param callback   Called when lookup completes (or NULL for fire-and-forget)
 * @param user_data  Passed to callback
 * @return           CYXCHAT_OK if lookup started
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_dht_find_node(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *target,
    cyxchat_dht_find_callback_t callback,
    void *user_data
);

/**
 * Get closest known nodes to target (synchronous)
 *
 * @param ctx        Connection context
 * @param target     Target node ID
 * @param out_nodes  Output: array of closest nodes
 * @param max_nodes  Maximum nodes to return
 * @return           Number of nodes returned
 */
CYXCHAT_API size_t cyxchat_conn_dht_get_closest(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *target,
    cyxwiz_node_id_t *out_nodes,
    size_t max_nodes
);

/**
 * Set callback for newly discovered DHT nodes
 *
 * @param ctx        Connection context
 * @param callback   Called when new node discovered
 * @param user_data  Passed to callback
 */
CYXCHAT_API void cyxchat_conn_dht_set_node_callback(
    cyxchat_conn_ctx_t *ctx,
    cyxchat_dht_node_callback_t callback,
    void *user_data
);

/**
 * Get DHT statistics
 */
CYXCHAT_API void cyxchat_conn_dht_get_stats(
    cyxchat_conn_ctx_t *ctx,
    cyxwiz_dht_stats_t *stats_out
);

/**
 * Check if DHT is enabled and has nodes
 */
CYXCHAT_API int cyxchat_conn_dht_is_ready(cyxchat_conn_ctx_t *ctx);

/* ============================================================
 * Manual Peer Addition (for testing/bootstrapping)
 * ============================================================ */

/**
 * Add a peer by address (for local testing or manual bootstrapping)
 *
 * This allows manually adding a peer when automatic discovery isn't available.
 * The peer will be added to the peer table and a discovery message sent.
 *
 * @param ctx       Connection context
 * @param node_id   Peer's 32-byte node ID
 * @param addr      IP:port string (e.g., "127.0.0.1:55151")
 * @return          CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_conn_add_peer_addr(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id,
    const char *addr
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_CONNECTION_H */
