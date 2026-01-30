/**
 * CyxChat Server Registry
 *
 * Manages multiple bootstrap/relay servers with:
 * - Ed25519 verification (challenge-response)
 * - Health checking (periodic pings with latency measurement)
 * - Automatic best-server selection (lowest latency among healthy servers)
 * - Seed list of known-good servers
 */

#ifndef CYXCHAT_SERVER_REGISTRY_H
#define CYXCHAT_SERVER_REGISTRY_H

#include "types.h"
#include <cyxwiz/transport.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Configuration
 * ============================================================ */

#define CYXCHAT_MAX_SERVERS              8       /* Max tracked servers */
#define CYXCHAT_SERVER_PUBKEY_SIZE       32      /* Ed25519 public key */
#define CYXCHAT_SERVER_SIG_SIZE          64      /* Ed25519 signature */
#define CYXCHAT_SERVER_NONCE_SIZE        32      /* Challenge nonce */
#define CYXCHAT_HEALTH_PING_INTERVAL_MS  15000   /* 15s health pings */
#define CYXCHAT_HEALTH_TIMEOUT_MS        5000    /* 5s ping timeout */
#define CYXCHAT_SERVER_UNHEALTHY_COUNT   3       /* Missed pongs before unhealthy */
#define CYXCHAT_SERVER_VERIFY_TIMEOUT_MS 10000   /* 10s verification timeout */

/* ============================================================
 * Server Registry Message Types (0xF5-0xFA)
 * ============================================================ */

#define CYXCHAT_MSG_SERVER_HEALTH_PING      0xF5    /* Health ping */
#define CYXCHAT_MSG_SERVER_HEALTH_PONG      0xF6    /* Health pong (echo) */
#define CYXCHAT_MSG_SERVER_CHALLENGE        0xF9    /* Verification challenge */
#define CYXCHAT_MSG_SERVER_CHALLENGE_RESP   0xFA    /* Challenge response */

/* ============================================================
 * Server State
 * ============================================================ */

typedef enum {
    CYXCHAT_SERVER_UNKNOWN    = 0,   /* Initial state */
    CYXCHAT_SERVER_VERIFYING,        /* Challenge sent, awaiting response */
    CYXCHAT_SERVER_VERIFIED,         /* Ed25519 signature verified */
    CYXCHAT_SERVER_HEALTHY,          /* Verified + responding to pings */
    CYXCHAT_SERVER_UNHEALTHY,        /* Verified but not responding */
    CYXCHAT_SERVER_REJECTED          /* Failed verification */
} cyxchat_server_state_t;

/* ============================================================
 * Server Info (public, returned by query APIs)
 * ============================================================ */

typedef struct {
    char     addr[64];                              /* "ip:port" */
    uint8_t  pubkey[CYXCHAT_SERVER_PUBKEY_SIZE];    /* Ed25519 pubkey */
    cyxchat_server_state_t state;
    uint32_t latency_ms;                            /* Last measured RTT */
    uint32_t avg_latency_ms;                        /* Exponential moving avg */
    uint64_t last_pong_received;                    /* Timestamp of last pong */
    uint8_t  missed_pongs;                          /* Consecutive missed */
    int      is_seed;                               /* From hardcoded seed list */
    int      is_bootstrap;                          /* Can serve as bootstrap */
    int      is_relay;                              /* Can serve as relay */
} cyxchat_server_info_t;

/* ============================================================
 * Context (opaque)
 * ============================================================ */

typedef struct cyxchat_server_registry cyxchat_server_registry_t;

/* ============================================================
 * Callbacks
 * ============================================================ */

/**
 * Called when a server's state changes (e.g. becomes healthy/unhealthy)
 */
typedef void (*cyxchat_server_state_callback_t)(
    cyxchat_server_registry_t *reg,
    const cyxchat_server_info_t *server,
    cyxchat_server_state_t old_state,
    cyxchat_server_state_t new_state,
    void *user_data
);

/* ============================================================
 * Lifecycle
 * ============================================================ */

/**
 * Create server registry
 *
 * @param reg           Output: created registry
 * @param transport     Transport for sending health pings / challenges
 * @param local_id      Our node ID
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_server_registry_create(
    cyxchat_server_registry_t **reg,
    cyxwiz_transport_t *transport,
    const cyxwiz_node_id_t *local_id
);

/**
 * Destroy server registry
 */
CYXCHAT_API void cyxchat_server_registry_destroy(
    cyxchat_server_registry_t *reg
);

/**
 * Poll registry (send health pings, check timeouts, update states)
 *
 * @param reg       Registry
 * @param now_ms    Current timestamp
 * @return          Number of events processed
 */
CYXCHAT_API int cyxchat_server_registry_poll(
    cyxchat_server_registry_t *reg,
    uint64_t now_ms
);

/* ============================================================
 * Server Management
 * ============================================================ */

/**
 * Add a server to the registry
 *
 * If expected_pubkey is provided, the server will be verified via
 * Ed25519 challenge-response before being marked as trusted.
 * If expected_pubkey is NULL, the server is added but remains UNKNOWN
 * (usable but not verified).
 *
 * @param reg               Registry
 * @param addr              Server address "ip:port"
 * @param expected_pubkey   Expected Ed25519 pubkey (32 bytes), or NULL
 * @return                  CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_server_registry_add(
    cyxchat_server_registry_t *reg,
    const char *addr,
    const uint8_t *expected_pubkey
);

/**
 * Remove a server from the registry
 *
 * @param reg   Registry
 * @param addr  Server address to remove
 * @return      CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_server_registry_remove(
    cyxchat_server_registry_t *reg,
    const char *addr
);

/**
 * Load hardcoded seed servers into registry
 *
 * @param reg   Registry
 * @return      Number of seed servers added
 */
CYXCHAT_API size_t cyxchat_server_registry_load_seeds(
    cyxchat_server_registry_t *reg
);

/* ============================================================
 * Server Selection
 * ============================================================ */

/**
 * Get the best available server (lowest latency among healthy+verified)
 *
 * @param reg   Registry
 * @param out   Output: best server info
 * @return      CYXCHAT_OK if found, CYXCHAT_ERR_NOT_FOUND if none available
 */
CYXCHAT_API cyxchat_error_t cyxchat_server_registry_get_best(
    cyxchat_server_registry_t *reg,
    cyxchat_server_info_t *out
);

/**
 * Get all servers and their status
 *
 * @param reg   Registry
 * @param out   Output array
 * @param max   Max entries in output array
 * @return      Number of servers written
 */
CYXCHAT_API size_t cyxchat_server_registry_get_all(
    cyxchat_server_registry_t *reg,
    cyxchat_server_info_t *out,
    size_t max
);

/**
 * Get number of servers in registry
 */
CYXCHAT_API size_t cyxchat_server_registry_count(
    cyxchat_server_registry_t *reg
);

/**
 * Get number of healthy servers
 */
CYXCHAT_API size_t cyxchat_server_registry_healthy_count(
    cyxchat_server_registry_t *reg
);

/* ============================================================
 * Message Handling
 * ============================================================ */

/**
 * Handle incoming server registry message (pong, challenge response)
 *
 * @param reg   Registry
 * @param data  Message data
 * @param len   Message length
 * @return      CYXCHAT_OK if handled
 */
CYXCHAT_API cyxchat_error_t cyxchat_server_registry_handle_message(
    cyxchat_server_registry_t *reg,
    const uint8_t *data,
    size_t len
);

/**
 * Check if message type is a server registry message
 */
CYXCHAT_API int cyxchat_server_registry_is_message(uint8_t msg_type);

/* ============================================================
 * Callbacks
 * ============================================================ */

/**
 * Set server state change callback
 */
CYXCHAT_API void cyxchat_server_registry_set_callback(
    cyxchat_server_registry_t *reg,
    cyxchat_server_state_callback_t callback,
    void *user_data
);

/**
 * Get state name string
 */
CYXCHAT_API const char* cyxchat_server_state_name(cyxchat_server_state_t state);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_SERVER_REGISTRY_H */
