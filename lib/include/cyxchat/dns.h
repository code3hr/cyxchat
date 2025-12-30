/**
 * CyxChat DNS Module
 * Gossip-based distributed naming system for human-readable usernames
 *
 * Three-layer naming system:
 * 1. Petnames (local) - Personal aliases stored locally
 * 2. Global names - "alice.cyx" registered via gossip protocol
 * 3. Crypto-names - Self-certifying from pubkey (e.g., "k5xq3v7b.cyx")
 */

#ifndef CYXCHAT_DNS_H
#define CYXCHAT_DNS_H

#include "types.h"
#include <cyxwiz/routing.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Constants
 * ============================================================ */

#define CYXCHAT_DNS_MAX_NAME        63      /* Max name length (without .cyx) */
#define CYXCHAT_DNS_SUFFIX          ".cyx"  /* Name suffix */
#define CYXCHAT_DNS_CACHE_SIZE      128     /* Max cached records */
#define CYXCHAT_DNS_DEFAULT_TTL     3600    /* 1 hour in seconds */
#define CYXCHAT_DNS_REFRESH_INTERVAL 1800   /* 30 min refresh */
#define CYXCHAT_DNS_GOSSIP_HOPS     3       /* Max re-broadcast depth */
#define CYXCHAT_DNS_LOOKUP_TIMEOUT  5000    /* Lookup timeout (ms) */
#define CYXCHAT_DNS_MAX_PETNAMES    256     /* Max local petnames */
#define CYXCHAT_DNS_CRYPTO_NAME_LEN 8       /* Crypto-name length (chars) */

/* ============================================================
 * DNS Record Structure (~180 bytes, fits LoRa)
 * ============================================================ */

typedef struct {
    char name[CYXCHAT_DNS_MAX_NAME + 1];    /* "alice" (without .cyx) */
    cyxwiz_node_id_t node_id;               /* 32 bytes */
    uint8_t pubkey[32];                     /* X25519 public key */
    uint8_t signature[64];                  /* Ed25519 signature of (name||pubkey||timestamp) */
    uint64_t timestamp;                     /* Registration time (unix ms) */
    uint32_t ttl;                           /* Time-to-live (seconds) */
    char stun_addr[24];                     /* "ip:port" for hole punching hint */
} cyxchat_dns_record_t;

/* ============================================================
 * Petname Entry (local alias)
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t node_id;               /* Node this petname refers to */
    char petname[CYXCHAT_DNS_MAX_NAME + 1]; /* Local alias */
} cyxchat_petname_t;

/* ============================================================
 * Callback Types
 * ============================================================ */

/**
 * Called when name registration completes
 *
 * @param user_data   User context
 * @param name        The registered name
 * @param success     1 if successful, 0 if name taken
 */
typedef void (*cyxchat_dns_register_cb)(
    void *user_data,
    const char *name,
    int success
);

/**
 * Called when name lookup completes
 *
 * @param user_data   User context
 * @param name        The queried name
 * @param record      The resolved record (NULL if not found)
 */
typedef void (*cyxchat_dns_lookup_cb)(
    void *user_data,
    const char *name,
    const cyxchat_dns_record_t *record
);

/* ============================================================
 * DNS Context
 * ============================================================ */

typedef struct cyxchat_dns_ctx cyxchat_dns_ctx_t;

/**
 * Create DNS context
 *
 * @param ctx_out      Output: created context
 * @param router       CyxWiz router for messaging
 * @param local_id     Our node ID
 * @param signing_key  Our Ed25519 signing key (64 bytes, secret+public)
 * @return             CYXCHAT_OK or error
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_create(
    cyxchat_dns_ctx_t **ctx_out,
    cyxwiz_router_t *router,
    const cyxwiz_node_id_t *local_id,
    const uint8_t *signing_key
);

/**
 * Destroy DNS context
 */
CYXCHAT_API void cyxchat_dns_destroy(cyxchat_dns_ctx_t *ctx);

/**
 * Poll DNS context (process incoming messages, check timeouts)
 * Call this regularly from main loop.
 *
 * @param ctx      DNS context
 * @param now_ms   Current time in milliseconds
 * @return         CYXCHAT_OK or error
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_poll(
    cyxchat_dns_ctx_t *ctx,
    uint64_t now_ms
);

/* ============================================================
 * Name Registration
 * ============================================================ */

/**
 * Register a global name
 *
 * Broadcasts DNS_REGISTER to all peers. Peers verify signature
 * and store in cache, then re-gossip to their peers.
 *
 * @param ctx       DNS context
 * @param name      Desired name (without .cyx suffix, 3-63 chars)
 * @param callback  Called when registration completes (or NULL)
 * @param user_data User context for callback
 * @return          CYXCHAT_OK or error (CYXCHAT_ERR_INVALID if name invalid)
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_register(
    cyxchat_dns_ctx_t *ctx,
    const char *name,
    cyxchat_dns_register_cb callback,
    void *user_data
);

/**
 * Refresh current registration (extend TTL)
 *
 * Should be called periodically (e.g., every 30 min) to keep name alive.
 *
 * @return CYXCHAT_OK, or CYXCHAT_ERR_NOT_FOUND if not registered
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_refresh(cyxchat_dns_ctx_t *ctx);

/**
 * Unregister current name
 *
 * Broadcasts unregistration (TTL=0) to peers.
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_unregister(cyxchat_dns_ctx_t *ctx);

/**
 * Get currently registered name
 *
 * @return Name string or NULL if not registered
 */
CYXCHAT_API const char* cyxchat_dns_get_registered_name(cyxchat_dns_ctx_t *ctx);

/**
 * Update STUN address hint in registration
 *
 * Call after STUN discovery to help peers find us.
 *
 * @param ctx        DNS context
 * @param stun_addr  Public address "ip:port"
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_set_stun_addr(
    cyxchat_dns_ctx_t *ctx,
    const char *stun_addr
);

/* ============================================================
 * Name Resolution
 * ============================================================ */

/**
 * Lookup a name asynchronously
 *
 * 1. Checks local cache first
 * 2. If crypto-name, derives directly
 * 3. Otherwise broadcasts DNS_LOOKUP to peers
 *
 * @param ctx       DNS context
 * @param name      Name to lookup (with or without .cyx suffix)
 * @param callback  Called when lookup completes
 * @param user_data User context for callback
 * @return          CYXCHAT_OK or error
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_lookup(
    cyxchat_dns_ctx_t *ctx,
    const char *name,
    cyxchat_dns_lookup_cb callback,
    void *user_data
);

/**
 * Synchronous lookup (cache only)
 *
 * Only returns cached records, doesn't query network.
 *
 * @param ctx        DNS context
 * @param name       Name to lookup
 * @param record_out Output: found record
 * @return           CYXCHAT_OK or CYXCHAT_ERR_NOT_FOUND
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_resolve(
    cyxchat_dns_ctx_t *ctx,
    const char *name,
    cyxchat_dns_record_t *record_out
);

/**
 * Check if name is in cache
 */
CYXCHAT_API int cyxchat_dns_is_cached(
    cyxchat_dns_ctx_t *ctx,
    const char *name
);

/**
 * Invalidate cached record
 */
CYXCHAT_API void cyxchat_dns_invalidate(
    cyxchat_dns_ctx_t *ctx,
    const char *name
);

/* ============================================================
 * Petnames (Local Aliases)
 * ============================================================ */

/**
 * Set a local petname for a node
 *
 * Petnames are local-only and not shared with the network.
 *
 * @param ctx      DNS context
 * @param node_id  Node to alias
 * @param petname  Local name (NULL to remove)
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_set_petname(
    cyxchat_dns_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id,
    const char *petname
);

/**
 * Get petname for a node
 *
 * @return Petname string or NULL if not set
 */
CYXCHAT_API const char* cyxchat_dns_get_petname(
    cyxchat_dns_ctx_t *ctx,
    const cyxwiz_node_id_t *node_id
);

/**
 * Resolve petname to node ID
 *
 * @param ctx       DNS context
 * @param petname   Petname to resolve
 * @param node_out  Output: node ID
 * @return          CYXCHAT_OK or CYXCHAT_ERR_NOT_FOUND
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_resolve_petname(
    cyxchat_dns_ctx_t *ctx,
    const char *petname,
    cyxwiz_node_id_t *node_out
);

/* ============================================================
 * Crypto-Names (Self-Certifying)
 * ============================================================ */

/**
 * Generate crypto-name from public key
 *
 * Crypto-names are deterministically derived from pubkey,
 * like Tor .onion addresses. Format: "k5xq3v7b.cyx"
 *
 * @param pubkey    X25519 public key (32 bytes)
 * @param name_out  Output buffer (at least 16 bytes)
 */
CYXCHAT_API void cyxchat_dns_crypto_name(
    const uint8_t *pubkey,
    char *name_out
);

/**
 * Check if name is a crypto-name
 *
 * @param name  Name to check
 * @return      1 if crypto-name, 0 otherwise
 */
CYXCHAT_API int cyxchat_dns_is_crypto_name(const char *name);

/**
 * Derive node ID from crypto-name
 *
 * @param name     Crypto-name (e.g., "k5xq3v7b.cyx")
 * @param id_out   Output: derived node ID
 * @return         CYXCHAT_OK or CYXCHAT_ERR_INVALID
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_parse_crypto_name(
    const char *name,
    cyxwiz_node_id_t *id_out
);

/* ============================================================
 * Name Validation
 * ============================================================ */

/**
 * Validate name format
 *
 * Valid names: 3-63 chars, alphanumeric + underscore,
 * starts with letter, no consecutive underscores.
 *
 * @param name  Name to validate (without .cyx)
 * @return      1 if valid, 0 if invalid
 */
CYXCHAT_API int cyxchat_dns_validate_name(const char *name);

/**
 * Normalize name (lowercase, strip suffix)
 *
 * @param name      Input name
 * @param out       Output buffer (at least CYXCHAT_DNS_MAX_NAME + 1)
 * @param out_len   Output buffer length
 * @return          CYXCHAT_OK or error
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_normalize_name(
    const char *name,
    char *out,
    size_t out_len
);

/* ============================================================
 * Message Handling (Internal)
 * ============================================================ */

/**
 * Handle incoming DNS message
 *
 * Called by the router when DNS messages (0xD0-0xD6) are received.
 *
 * @param ctx   DNS context
 * @param from  Sender node ID
 * @param data  Message data
 * @param len   Message length
 * @return      CYXCHAT_OK or error
 */
CYXCHAT_API cyxchat_error_t cyxchat_dns_handle_message(
    cyxchat_dns_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
);

/* ============================================================
 * Statistics
 * ============================================================ */

typedef struct {
    size_t cache_entries;       /* Current cache size */
    size_t cache_hits;          /* Cache hit count */
    size_t cache_misses;        /* Cache miss count */
    size_t lookups_sent;        /* Lookup queries sent */
    size_t lookups_received;    /* Lookup queries received */
    size_t registrations;       /* Registration announcements */
    size_t gossip_forwards;     /* Gossip messages forwarded */
} cyxchat_dns_stats_t;

/**
 * Get DNS statistics
 */
CYXCHAT_API void cyxchat_dns_get_stats(
    cyxchat_dns_ctx_t *ctx,
    cyxchat_dns_stats_t *stats_out
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_DNS_H */
