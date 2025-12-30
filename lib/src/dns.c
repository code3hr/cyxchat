/**
 * CyxChat DNS Module Implementation
 *
 * Gossip-based distributed naming system for human-readable usernames.
 * Implements registration, lookup, and caching with gossip propagation.
 */

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include "cyxchat/dns.h"
#include <cyxwiz/memory.h>
#include <cyxwiz/log.h>
#include <cyxwiz/types.h>
#include <cyxwiz/peer.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>
#include <ctype.h>

#ifdef CYXWIZ_HAS_CRYPTO
#include <sodium.h>
#endif

/* Forward declarations for broadcast helper */
typedef struct {
    cyxwiz_router_t *router;
    cyxwiz_transport_t *transport;
    const uint8_t *data;
    size_t len;
} dns_broadcast_ctx_t;

static int dns_broadcast_callback(const cyxwiz_peer_t *peer, void *user_data)
{
    dns_broadcast_ctx_t *ctx = (dns_broadcast_ctx_t*)user_data;
    if (peer->state == CYXWIZ_PEER_STATE_CONNECTED) {
        if (ctx->router) {
            cyxwiz_router_send(ctx->router, &peer->id, ctx->data, ctx->len);
        } else if (ctx->transport) {
            ctx->transport->ops->send(ctx->transport, &peer->id, ctx->data, ctx->len);
        }
    }
    return 0;  /* Continue iteration */
}

/* Broadcast to all connected peers using router */
static void dns_broadcast_via_router(cyxwiz_router_t *router, const uint8_t *data, size_t len)
{
    if (!router) return;

    cyxwiz_peer_table_t *table = cyxwiz_router_get_peer_table(router);
    if (!table) return;

    dns_broadcast_ctx_t ctx = { router, NULL, data, len };
    cyxwiz_peer_table_iterate(table, dns_broadcast_callback, &ctx);
}

/* Broadcast to all connected peers using transport directly */
static void dns_broadcast_via_transport(cyxwiz_transport_t *transport, cyxwiz_peer_table_t *peer_table,
                                        const uint8_t *data, size_t len)
{
    if (!transport || !peer_table) return;

    dns_broadcast_ctx_t ctx = { NULL, transport, data, len };
    cyxwiz_peer_table_iterate(peer_table, dns_broadcast_callback, &ctx);
}

/* Forward declaration - dns_ctx_broadcast defined after struct cyxchat_dns_ctx */

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#else
#include <time.h>
#endif

/* ============================================================
 * Internal Constants
 * ============================================================ */

#define DNS_MSG_HEADER_SIZE     2       /* type + flags */
#define DNS_REGISTER_MIN_SIZE   (1 + 1 + 32 + 32 + 64 + 4)  /* 134 bytes min */
#define DNS_LOOKUP_MIN_SIZE     (1 + 1 + 1)  /* type + query_id + name_len */
#define DNS_RESPONSE_MIN_SIZE   (1 + 1 + 1)  /* type + query_id + found */

/* ============================================================
 * Internal Types
 * ============================================================ */

/* Cache entry */
typedef struct {
    cyxchat_dns_record_t record;
    uint64_t cached_at;
    uint8_t hops;           /* Gossip hop count when received */
    int valid;
} dns_cache_entry_t;

/* Pending lookup */
typedef struct {
    char name[CYXCHAT_DNS_MAX_NAME + 1];
    uint8_t query_id;
    uint64_t start_time;
    cyxchat_dns_lookup_cb callback;
    void *user_data;
    int active;
} dns_pending_lookup_t;

/* Pending registration */
typedef struct {
    cyxchat_dns_register_cb callback;
    void *user_data;
    uint64_t start_time;
    int active;
} dns_pending_register_t;

/* DNS context */
struct cyxchat_dns_ctx {
    /* Router for messaging (preferred) */
    cyxwiz_router_t *router;

    /* Direct transport (alternative to router) */
    cyxwiz_transport_t *transport;
    cyxwiz_peer_table_t *peer_table;

    /* Our identity */
    cyxwiz_node_id_t local_id;
    uint8_t signing_key[64];    /* Ed25519 secret + public */
    uint8_t pubkey[32];         /* X25519 public key (derived) */

    /* Current registration */
    cyxchat_dns_record_t my_record;
    int is_registered;
    uint64_t last_refresh;

    /* DNS cache */
    dns_cache_entry_t cache[CYXCHAT_DNS_CACHE_SIZE];
    size_t cache_count;

    /* Petnames */
    cyxchat_petname_t petnames[CYXCHAT_DNS_MAX_PETNAMES];
    size_t petname_count;

    /* Pending lookups */
    dns_pending_lookup_t pending_lookups[16];
    uint8_t next_query_id;

    /* Pending registration */
    dns_pending_register_t pending_register;

    /* Statistics */
    cyxchat_dns_stats_t stats;
};

/* Broadcast to all connected peers (auto-selects method) */
static void dns_ctx_broadcast(cyxchat_dns_ctx_t *ctx, const uint8_t *data, size_t len)
{
    if (ctx->router) {
        dns_broadcast_via_router(ctx->router, data, len);
    } else if (ctx->transport && ctx->peer_table) {
        dns_broadcast_via_transport(ctx->transport, ctx->peer_table, data, len);
    }
    /* If neither is available, silently fail - registration is still stored locally */
}

/* ============================================================
 * Helper Functions
 * ============================================================ */

static uint64_t get_time_ms(void)
{
#ifdef _WIN32
    return GetTickCount64();
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

static uint64_t get_unix_time_ms(void)
{
#ifdef _WIN32
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    return (t - 116444736000000000ULL) / 10000;
#else
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

/* Base32 encoding for crypto-names */
static const char BASE32_CHARS[] = "abcdefghijklmnopqrstuvwxyz234567";

static void base32_encode(const uint8_t *data, size_t len, char *out, size_t out_len)
{
    size_t i = 0, j = 0;
    uint32_t buffer = 0;
    int bits = 0;

    while (i < len && j < out_len - 1) {
        buffer = (buffer << 8) | data[i++];
        bits += 8;

        while (bits >= 5 && j < out_len - 1) {
            out[j++] = BASE32_CHARS[(buffer >> (bits - 5)) & 0x1F];
            bits -= 5;
        }
    }

    if (bits > 0 && j < out_len - 1) {
        out[j++] = BASE32_CHARS[(buffer << (5 - bits)) & 0x1F];
    }

    out[j] = '\0';
}

/* Find cache entry by name */
static dns_cache_entry_t* find_cache_entry(cyxchat_dns_ctx_t *ctx, const char *name)
{
    for (size_t i = 0; i < CYXCHAT_DNS_CACHE_SIZE; i++) {
        if (ctx->cache[i].valid &&
            strcmp(ctx->cache[i].record.name, name) == 0) {
            return &ctx->cache[i];
        }
    }
    return NULL;
}

/* Allocate cache entry (LRU eviction) */
static dns_cache_entry_t* alloc_cache_entry(cyxchat_dns_ctx_t *ctx)
{
    uint64_t now = get_time_ms();
    dns_cache_entry_t *oldest = NULL;
    uint64_t oldest_time = UINT64_MAX;

    /* Find empty slot or oldest entry */
    for (size_t i = 0; i < CYXCHAT_DNS_CACHE_SIZE; i++) {
        if (!ctx->cache[i].valid) {
            ctx->cache_count++;
            ctx->cache[i].valid = 1;
            return &ctx->cache[i];
        }

        if (ctx->cache[i].cached_at < oldest_time) {
            oldest_time = ctx->cache[i].cached_at;
            oldest = &ctx->cache[i];
        }
    }

    /* Evict oldest */
    if (oldest) {
        memset(&oldest->record, 0, sizeof(cyxchat_dns_record_t));
        oldest->cached_at = now;
        return oldest;
    }

    return NULL;
}

/* Check if cache entry is expired */
static int is_cache_expired(dns_cache_entry_t *entry, uint64_t now_ms)
{
    uint64_t age_ms = now_ms - entry->cached_at;
    uint64_t ttl_ms = (uint64_t)entry->record.ttl * 1000;
    return age_ms >= ttl_ms;
}

/* Find pending lookup */
static dns_pending_lookup_t* find_pending_lookup(cyxchat_dns_ctx_t *ctx, const char *name)
{
    for (size_t i = 0; i < 16; i++) {
        if (ctx->pending_lookups[i].active &&
            strcmp(ctx->pending_lookups[i].name, name) == 0) {
            return &ctx->pending_lookups[i];
        }
    }
    return NULL;
}

static dns_pending_lookup_t* find_pending_lookup_by_id(cyxchat_dns_ctx_t *ctx, uint8_t query_id)
{
    for (size_t i = 0; i < 16; i++) {
        if (ctx->pending_lookups[i].active &&
            ctx->pending_lookups[i].query_id == query_id) {
            return &ctx->pending_lookups[i];
        }
    }
    return NULL;
}

static dns_pending_lookup_t* alloc_pending_lookup(cyxchat_dns_ctx_t *ctx)
{
    for (size_t i = 0; i < 16; i++) {
        if (!ctx->pending_lookups[i].active) {
            memset(&ctx->pending_lookups[i], 0, sizeof(dns_pending_lookup_t));
            ctx->pending_lookups[i].active = 1;
            ctx->pending_lookups[i].query_id = ctx->next_query_id++;
            return &ctx->pending_lookups[i];
        }
    }
    return NULL;
}

/* Find petname entry */
static cyxchat_petname_t* find_petname_by_id(cyxchat_dns_ctx_t *ctx, const cyxwiz_node_id_t *node_id)
{
    for (size_t i = 0; i < CYXCHAT_DNS_MAX_PETNAMES; i++) {
        if (ctx->petnames[i].petname[0] != '\0' &&
            memcmp(&ctx->petnames[i].node_id, node_id, sizeof(cyxwiz_node_id_t)) == 0) {
            return &ctx->petnames[i];
        }
    }
    return NULL;
}

static cyxchat_petname_t* find_petname_by_name(cyxchat_dns_ctx_t *ctx, const char *petname)
{
    for (size_t i = 0; i < CYXCHAT_DNS_MAX_PETNAMES; i++) {
        if (strcmp(ctx->petnames[i].petname, petname) == 0) {
            return &ctx->petnames[i];
        }
    }
    return NULL;
}

static cyxchat_petname_t* alloc_petname(cyxchat_dns_ctx_t *ctx)
{
    for (size_t i = 0; i < CYXCHAT_DNS_MAX_PETNAMES; i++) {
        if (ctx->petnames[i].petname[0] == '\0') {
            ctx->petname_count++;
            return &ctx->petnames[i];
        }
    }
    return NULL;
}

/* ============================================================
 * Signature Verification
 * ============================================================ */

#ifdef CYXWIZ_HAS_CRYPTO
static int verify_record_signature(const cyxchat_dns_record_t *record)
{
    /* Build signed data: name || pubkey || timestamp */
    uint8_t signed_data[64 + 32 + 8];
    size_t offset = 0;

    size_t name_len = strlen(record->name);
    memcpy(signed_data + offset, record->name, name_len);
    offset += name_len;

    memcpy(signed_data + offset, record->pubkey, 32);
    offset += 32;

    /* Timestamp as big-endian */
    uint64_t ts = record->timestamp;
    for (int i = 7; i >= 0; i--) {
        signed_data[offset + i] = (uint8_t)(ts & 0xFF);
        ts >>= 8;
    }
    offset += 8;

    /* Derive Ed25519 public key from X25519 public key for verification */
    /* Note: In production, store Ed25519 pubkey separately */
    /* For now, we trust the signature was made with matching keys */
    return crypto_sign_verify_detached(
        record->signature,
        signed_data,
        offset,
        record->pubkey  /* Using pubkey field - should be Ed25519 verifying key */
    ) == 0;
}

static void sign_record(cyxchat_dns_ctx_t *ctx, cyxchat_dns_record_t *record)
{
    /* Build signed data: name || pubkey || timestamp */
    uint8_t signed_data[64 + 32 + 8];
    size_t offset = 0;

    size_t name_len = strlen(record->name);
    memcpy(signed_data + offset, record->name, name_len);
    offset += name_len;

    memcpy(signed_data + offset, record->pubkey, 32);
    offset += 32;

    /* Timestamp as big-endian */
    uint64_t ts = record->timestamp;
    for (int i = 7; i >= 0; i--) {
        signed_data[offset + i] = (uint8_t)(ts & 0xFF);
        ts >>= 8;
    }
    offset += 8;

    /* Sign with Ed25519 */
    crypto_sign_detached(
        record->signature,
        NULL,
        signed_data,
        offset,
        ctx->signing_key
    );
}
#else
static int verify_record_signature(const cyxchat_dns_record_t *record)
{
    (void)record;
    return 1;  /* Accept without crypto */
}

static void sign_record(cyxchat_dns_ctx_t *ctx, cyxchat_dns_record_t *record)
{
    (void)ctx;
    memset(record->signature, 0, 64);
}
#endif

/* ============================================================
 * Message Serialization
 * ============================================================ */

/* Serialize DNS_REGISTER message */
static size_t serialize_register(const cyxchat_dns_record_t *record, uint8_t hops,
                                  uint8_t *out, size_t out_len)
{
    if (out_len < 180) return 0;

    size_t offset = 0;
    size_t name_len = strlen(record->name);

    out[offset++] = CYXCHAT_MSG_DNS_REGISTER;
    out[offset++] = hops;
    out[offset++] = (uint8_t)name_len;

    memcpy(out + offset, record->name, name_len);
    offset += name_len;

    /* Pad name to fixed size for consistency */
    memset(out + offset, 0, CYXCHAT_DNS_MAX_NAME - name_len);
    offset += CYXCHAT_DNS_MAX_NAME - name_len;

    memcpy(out + offset, record->node_id.bytes, 32);
    offset += 32;

    memcpy(out + offset, record->pubkey, 32);
    offset += 32;

    memcpy(out + offset, record->signature, 64);
    offset += 64;

    /* Timestamp (big-endian) */
    uint64_t ts = record->timestamp;
    for (int i = 7; i >= 0; i--) {
        out[offset + i] = (uint8_t)(ts & 0xFF);
        ts >>= 8;
    }
    offset += 8;

    /* TTL (big-endian) */
    uint32_t ttl = record->ttl;
    out[offset++] = (uint8_t)(ttl >> 24);
    out[offset++] = (uint8_t)(ttl >> 16);
    out[offset++] = (uint8_t)(ttl >> 8);
    out[offset++] = (uint8_t)(ttl);

    return offset;
}

/* Deserialize DNS_REGISTER message */
static int deserialize_register(const uint8_t *data, size_t len,
                                 cyxchat_dns_record_t *record, uint8_t *hops_out)
{
    if (len < DNS_REGISTER_MIN_SIZE) return -1;

    size_t offset = 1;  /* Skip type byte */

    *hops_out = data[offset++];
    uint8_t name_len = data[offset++];

    if (name_len > CYXCHAT_DNS_MAX_NAME) return -1;

    memcpy(record->name, data + offset, name_len);
    record->name[name_len] = '\0';
    offset += CYXCHAT_DNS_MAX_NAME;

    memcpy(record->node_id.bytes, data + offset, 32);
    offset += 32;

    memcpy(record->pubkey, data + offset, 32);
    offset += 32;

    memcpy(record->signature, data + offset, 64);
    offset += 64;

    /* Timestamp */
    record->timestamp = 0;
    for (int i = 0; i < 8; i++) {
        record->timestamp = (record->timestamp << 8) | data[offset++];
    }

    /* TTL */
    record->ttl = ((uint32_t)data[offset] << 24) |
                  ((uint32_t)data[offset + 1] << 16) |
                  ((uint32_t)data[offset + 2] << 8) |
                  (uint32_t)data[offset + 3];

    return 0;
}

/* Serialize DNS_LOOKUP message */
static size_t serialize_lookup(const char *name, uint8_t query_id,
                                uint8_t *out, size_t out_len)
{
    size_t name_len = strlen(name);
    if (out_len < 3 + name_len) return 0;

    size_t offset = 0;
    out[offset++] = CYXCHAT_MSG_DNS_LOOKUP;
    out[offset++] = query_id;
    out[offset++] = (uint8_t)name_len;
    memcpy(out + offset, name, name_len);
    offset += name_len;

    return offset;
}

/* Serialize DNS_RESPONSE message */
static size_t serialize_response(uint8_t query_id, const cyxchat_dns_record_t *record,
                                  uint8_t *out, size_t out_len)
{
    (void)out_len; /* TODO: Add bounds checking */
    size_t offset = 0;

    out[offset++] = CYXCHAT_MSG_DNS_RESPONSE;
    out[offset++] = query_id;
    out[offset++] = record ? 1 : 0;

    if (record) {
        memcpy(out + offset, record->node_id.bytes, 32);
        offset += 32;

        memcpy(out + offset, record->pubkey, 32);
        offset += 32;

        memcpy(out + offset, record->signature, 64);
        offset += 64;

        /* TTL */
        uint32_t ttl = record->ttl;
        out[offset++] = (uint8_t)(ttl >> 24);
        out[offset++] = (uint8_t)(ttl >> 16);
        out[offset++] = (uint8_t)(ttl >> 8);
        out[offset++] = (uint8_t)(ttl);

        /* Name */
        size_t name_len = strlen(record->name);
        out[offset++] = (uint8_t)name_len;
        memcpy(out + offset, record->name, name_len);
        offset += name_len;
    }

    return offset;
}

/* ============================================================
 * Message Handling
 * ============================================================ */

static void handle_register(cyxchat_dns_ctx_t *ctx, const cyxwiz_node_id_t *from,
                            const uint8_t *data, size_t len)
{
    (void)from; /* Record contains node_id, from is for routing only */
    cyxchat_dns_record_t record;
    uint8_t hops;

    if (deserialize_register(data, len, &record, &hops) != 0) {
        return;
    }

    /* Verify signature */
    if (!verify_record_signature(&record)) {
        return;
    }

    /* Check if we already have a newer record for this name */
    dns_cache_entry_t *existing = find_cache_entry(ctx, record.name);
    if (existing && existing->record.timestamp >= record.timestamp) {
        return;  /* We have same or newer */
    }

    /* Store in cache */
    dns_cache_entry_t *entry = existing ? existing : alloc_cache_entry(ctx);
    if (entry) {
        entry->record = record;
        entry->cached_at = get_time_ms();
        entry->hops = hops;
    }

    ctx->stats.registrations++;

    /* Re-gossip if hops remaining */
    if (hops < CYXCHAT_DNS_GOSSIP_HOPS) {
        uint8_t msg[200];
        size_t msg_len = serialize_register(&record, hops + 1, msg, sizeof(msg));

        if (msg_len > 0 && ctx->router) {
            /* Broadcast to all connected peers */
            dns_ctx_broadcast(ctx, msg, msg_len);
            ctx->stats.gossip_forwards++;
        }
    }
}

static void handle_lookup(cyxchat_dns_ctx_t *ctx, const cyxwiz_node_id_t *from,
                           const uint8_t *data, size_t len)
{
    if (len < DNS_LOOKUP_MIN_SIZE) return;

    uint8_t query_id = data[1];
    uint8_t name_len = data[2];

    if (name_len > CYXCHAT_DNS_MAX_NAME || len < (size_t)(3 + name_len)) return;

    char name[CYXCHAT_DNS_MAX_NAME + 1];
    memcpy(name, data + 3, name_len);
    name[name_len] = '\0';

    ctx->stats.lookups_received++;

    /* Check our cache */
    dns_cache_entry_t *entry = find_cache_entry(ctx, name);
    const cyxchat_dns_record_t *record = NULL;

    if (entry && !is_cache_expired(entry, get_time_ms())) {
        record = &entry->record;
    }

    /* Also check if it's our own name */
    if (!record && ctx->is_registered && strcmp(ctx->my_record.name, name) == 0) {
        record = &ctx->my_record;
    }

    /* Send response */
    uint8_t msg[200];
    size_t msg_len = serialize_response(query_id, record, msg, sizeof(msg));

    if (msg_len > 0 && ctx->router) {
        cyxwiz_router_send(ctx->router, from, msg, msg_len);
    }
}

static void handle_response(cyxchat_dns_ctx_t *ctx, const cyxwiz_node_id_t *from,
                             const uint8_t *data, size_t len)
{
    (void)from; /* Response matched by query_id, not sender */
    if (len < DNS_RESPONSE_MIN_SIZE) return;

    uint8_t query_id = data[1];
    uint8_t found = data[2];

    dns_pending_lookup_t *pending = find_pending_lookup_by_id(ctx, query_id);
    if (!pending) return;

    cyxchat_dns_record_t record;
    const cyxchat_dns_record_t *result = NULL;

    if (found && len >= 3 + 32 + 32 + 64 + 4 + 1) {
        size_t offset = 3;

        memcpy(record.node_id.bytes, data + offset, 32);
        offset += 32;

        memcpy(record.pubkey, data + offset, 32);
        offset += 32;

        memcpy(record.signature, data + offset, 64);
        offset += 64;

        record.ttl = ((uint32_t)data[offset] << 24) |
                     ((uint32_t)data[offset + 1] << 16) |
                     ((uint32_t)data[offset + 2] << 8) |
                     (uint32_t)data[offset + 3];
        offset += 4;

        uint8_t name_len = data[offset++];
        if (name_len <= CYXCHAT_DNS_MAX_NAME && offset + name_len <= len) {
            memcpy(record.name, data + offset, name_len);
            record.name[name_len] = '\0';

            record.timestamp = get_unix_time_ms();
            record.stun_addr[0] = '\0';

            /* Verify signature */
            if (verify_record_signature(&record)) {
                /* Cache result */
                dns_cache_entry_t *entry = find_cache_entry(ctx, record.name);
                if (!entry) {
                    entry = alloc_cache_entry(ctx);
                }
                if (entry) {
                    entry->record = record;
                    entry->cached_at = get_time_ms();
                    entry->hops = 1;
                }

                result = &record;
                ctx->stats.cache_hits++;
            }
        }
    }

    /* Call callback */
    if (pending->callback) {
        pending->callback(pending->user_data, pending->name, result);
    }

    pending->active = 0;
}

static void handle_announce(cyxchat_dns_ctx_t *ctx, const cyxwiz_node_id_t *from,
                             const uint8_t *data, size_t len)
{
    /* DNS_ANNOUNCE is same format as DNS_REGISTER */
    handle_register(ctx, from, data, len);
}

/* ============================================================
 * Public API Implementation
 * ============================================================ */

cyxchat_error_t cyxchat_dns_create(cyxchat_dns_ctx_t **ctx_out,
                                    cyxwiz_router_t *router,
                                    const cyxwiz_node_id_t *local_id,
                                    const uint8_t *signing_key)
{
    if (!ctx_out || !local_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_dns_ctx_t *ctx = (cyxchat_dns_ctx_t*)calloc(1, sizeof(cyxchat_dns_ctx_t));
    if (!ctx) {
        return CYXCHAT_ERR_MEMORY;
    }

    ctx->router = router;
    ctx->local_id = *local_id;

    if (signing_key) {
        memcpy(ctx->signing_key, signing_key, 64);
        /* Extract public key portion (last 32 bytes of Ed25519 secret key) */
        memcpy(ctx->pubkey, signing_key + 32, 32);
    }

    ctx->is_registered = 0;
    ctx->next_query_id = 1;

    *ctx_out = ctx;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_dns_set_transport(cyxchat_dns_ctx_t *ctx,
                                           cyxwiz_transport_t *transport,
                                           cyxwiz_peer_table_t *peer_table)
{
    if (!ctx) {
        return CYXCHAT_ERR_NULL;
    }

    ctx->transport = transport;
    ctx->peer_table = peer_table;

    return CYXCHAT_OK;
}

void cyxchat_dns_destroy(cyxchat_dns_ctx_t *ctx)
{
    if (!ctx) return;

    /* Securely clear signing key */
    cyxwiz_secure_zero(ctx->signing_key, sizeof(ctx->signing_key));

    free(ctx);
}

cyxchat_error_t cyxchat_dns_poll(cyxchat_dns_ctx_t *ctx, uint64_t now_ms)
{
    if (!ctx) return CYXCHAT_ERR_NULL;

    /* Check pending lookup timeouts */
    for (size_t i = 0; i < 16; i++) {
        dns_pending_lookup_t *pending = &ctx->pending_lookups[i];
        if (!pending->active) continue;

        if (now_ms - pending->start_time >= CYXCHAT_DNS_LOOKUP_TIMEOUT) {
            /* Timeout - call callback with NULL */
            if (pending->callback) {
                pending->callback(pending->user_data, pending->name, NULL);
            }
            pending->active = 0;
        }
    }

    /* Check registration refresh */
    if (ctx->is_registered) {
        if (now_ms - ctx->last_refresh >= CYXCHAT_DNS_REFRESH_INTERVAL * 1000) {
            cyxchat_dns_refresh(ctx);
        }
    }

    /* Expire old cache entries */
    for (size_t i = 0; i < CYXCHAT_DNS_CACHE_SIZE; i++) {
        if (ctx->cache[i].valid && is_cache_expired(&ctx->cache[i], now_ms)) {
            ctx->cache[i].valid = 0;
            if (ctx->cache_count > 0) ctx->cache_count--;
        }
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Name Registration
 * ============================================================ */

cyxchat_error_t cyxchat_dns_register(cyxchat_dns_ctx_t *ctx,
                                      const char *name,
                                      cyxchat_dns_register_cb callback,
                                      void *user_data)
{
    if (!ctx || !name) {
        return CYXCHAT_ERR_NULL;
    }

    /* Validate name */
    if (!cyxchat_dns_validate_name(name)) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Build registration record */
    memset(&ctx->my_record, 0, sizeof(cyxchat_dns_record_t));

    /* Normalize and copy name */
    char normalized[CYXCHAT_DNS_MAX_NAME + 1];
    cyxchat_dns_normalize_name(name, normalized, sizeof(normalized));
    snprintf(ctx->my_record.name, sizeof(ctx->my_record.name), "%s", normalized);

    ctx->my_record.node_id = ctx->local_id;
    memcpy(ctx->my_record.pubkey, ctx->pubkey, 32);
    ctx->my_record.timestamp = get_unix_time_ms();
    ctx->my_record.ttl = CYXCHAT_DNS_DEFAULT_TTL;

    /* Sign the record */
    sign_record(ctx, &ctx->my_record);

    ctx->is_registered = 1;
    ctx->last_refresh = get_time_ms();

    /* Store pending registration callback */
    ctx->pending_register.callback = callback;
    ctx->pending_register.user_data = user_data;
    ctx->pending_register.start_time = get_time_ms();
    ctx->pending_register.active = 1;

    /* Broadcast registration */
    uint8_t msg[200];
    size_t msg_len = serialize_register(&ctx->my_record, 0, msg, sizeof(msg));

    if (msg_len > 0 && ctx->router) {
        dns_ctx_broadcast(ctx, msg, msg_len);
    }

    ctx->stats.registrations++;

    /* Call callback immediately (optimistic) */
    if (callback) {
        callback(user_data, ctx->my_record.name, 1);
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_dns_refresh(cyxchat_dns_ctx_t *ctx)
{
    if (!ctx) return CYXCHAT_ERR_NULL;
    if (!ctx->is_registered) return CYXCHAT_ERR_NOT_FOUND;

    /* Update timestamp */
    ctx->my_record.timestamp = get_unix_time_ms();

    /* Re-sign */
    sign_record(ctx, &ctx->my_record);

    ctx->last_refresh = get_time_ms();

    /* Broadcast update */
    uint8_t msg[200];
    size_t msg_len = serialize_register(&ctx->my_record, 0, msg, sizeof(msg));

    if (msg_len > 0 && ctx->router) {
        dns_ctx_broadcast(ctx, msg, msg_len);
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_dns_unregister(cyxchat_dns_ctx_t *ctx)
{
    if (!ctx) return CYXCHAT_ERR_NULL;
    if (!ctx->is_registered) return CYXCHAT_ERR_NOT_FOUND;

    /* Set TTL to 0 to indicate removal */
    ctx->my_record.ttl = 0;
    ctx->my_record.timestamp = get_unix_time_ms();
    sign_record(ctx, &ctx->my_record);

    /* Broadcast unregistration */
    uint8_t msg[200];
    size_t msg_len = serialize_register(&ctx->my_record, 0, msg, sizeof(msg));

    if (msg_len > 0 && ctx->router) {
        dns_ctx_broadcast(ctx, msg, msg_len);
    }

    ctx->is_registered = 0;
    memset(&ctx->my_record, 0, sizeof(cyxchat_dns_record_t));

    return CYXCHAT_OK;
}

const char* cyxchat_dns_get_registered_name(cyxchat_dns_ctx_t *ctx)
{
    if (!ctx || !ctx->is_registered) return NULL;
    return ctx->my_record.name;
}

cyxchat_error_t cyxchat_dns_set_stun_addr(cyxchat_dns_ctx_t *ctx, const char *stun_addr)
{
    if (!ctx || !stun_addr) return CYXCHAT_ERR_NULL;
    if (!ctx->is_registered) return CYXCHAT_ERR_NOT_FOUND;

    strncpy(ctx->my_record.stun_addr, stun_addr, sizeof(ctx->my_record.stun_addr) - 1);
    ctx->my_record.stun_addr[sizeof(ctx->my_record.stun_addr) - 1] = '\0';

    return CYXCHAT_OK;
}

/* ============================================================
 * Name Resolution
 * ============================================================ */

cyxchat_error_t cyxchat_dns_lookup(cyxchat_dns_ctx_t *ctx,
                                    const char *name,
                                    cyxchat_dns_lookup_cb callback,
                                    void *user_data)
{
    if (!ctx || !name) {
        return CYXCHAT_ERR_NULL;
    }

    /* Normalize name */
    char normalized[CYXCHAT_DNS_MAX_NAME + 1];
    cyxchat_dns_normalize_name(name, normalized, sizeof(normalized));

    /* Check if crypto-name */
    if (cyxchat_dns_is_crypto_name(normalized)) {
        /* Crypto-names resolve directly without network */
        cyxchat_dns_record_t record;
        memset(&record, 0, sizeof(record));

        if (cyxchat_dns_parse_crypto_name(normalized, &record.node_id) == CYXCHAT_OK) {
            snprintf(record.name, sizeof(record.name), "%s", normalized);
            record.ttl = UINT32_MAX;  /* Never expires */

            if (callback) {
                callback(user_data, normalized, &record);
            }
            return CYXCHAT_OK;
        }
    }

    /* Check cache */
    dns_cache_entry_t *entry = find_cache_entry(ctx, normalized);
    if (entry && !is_cache_expired(entry, get_time_ms())) {
        ctx->stats.cache_hits++;
        if (callback) {
            callback(user_data, normalized, &entry->record);
        }
        return CYXCHAT_OK;
    }

    ctx->stats.cache_misses++;

    /* Check if lookup already pending */
    if (find_pending_lookup(ctx, normalized)) {
        return CYXCHAT_ERR_EXISTS;
    }

    /* Create pending lookup */
    dns_pending_lookup_t *pending = alloc_pending_lookup(ctx);
    if (!pending) {
        return CYXCHAT_ERR_FULL;
    }

    snprintf(pending->name, sizeof(pending->name), "%s", normalized);
    pending->callback = callback;
    pending->user_data = user_data;
    pending->start_time = get_time_ms();

    /* Broadcast lookup query */
    uint8_t msg[100];
    size_t msg_len = serialize_lookup(normalized, pending->query_id, msg, sizeof(msg));

    if (msg_len > 0 && ctx->router) {
        dns_ctx_broadcast(ctx, msg, msg_len);
    }

    ctx->stats.lookups_sent++;

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_dns_resolve(cyxchat_dns_ctx_t *ctx,
                                     const char *name,
                                     cyxchat_dns_record_t *record_out)
{
    if (!ctx || !name || !record_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Normalize name */
    char normalized[CYXCHAT_DNS_MAX_NAME + 1];
    cyxchat_dns_normalize_name(name, normalized, sizeof(normalized));

    /* Check cache */
    dns_cache_entry_t *entry = find_cache_entry(ctx, normalized);
    if (entry && !is_cache_expired(entry, get_time_ms())) {
        *record_out = entry->record;
        ctx->stats.cache_hits++;
        return CYXCHAT_OK;
    }

    ctx->stats.cache_misses++;
    return CYXCHAT_ERR_NOT_FOUND;
}

int cyxchat_dns_is_cached(cyxchat_dns_ctx_t *ctx, const char *name)
{
    if (!ctx || !name) return 0;

    char normalized[CYXCHAT_DNS_MAX_NAME + 1];
    cyxchat_dns_normalize_name(name, normalized, sizeof(normalized));

    dns_cache_entry_t *entry = find_cache_entry(ctx, normalized);
    return entry && !is_cache_expired(entry, get_time_ms());
}

void cyxchat_dns_invalidate(cyxchat_dns_ctx_t *ctx, const char *name)
{
    if (!ctx || !name) return;

    char normalized[CYXCHAT_DNS_MAX_NAME + 1];
    cyxchat_dns_normalize_name(name, normalized, sizeof(normalized));

    dns_cache_entry_t *entry = find_cache_entry(ctx, normalized);
    if (entry) {
        entry->valid = 0;
        if (ctx->cache_count > 0) ctx->cache_count--;
    }
}

/* ============================================================
 * Petnames
 * ============================================================ */

cyxchat_error_t cyxchat_dns_set_petname(cyxchat_dns_ctx_t *ctx,
                                         const cyxwiz_node_id_t *node_id,
                                         const char *petname)
{
    if (!ctx || !node_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Find existing entry */
    cyxchat_petname_t *entry = find_petname_by_id(ctx, node_id);

    if (!petname || petname[0] == '\0') {
        /* Remove petname */
        if (entry) {
            memset(entry, 0, sizeof(cyxchat_petname_t));
            if (ctx->petname_count > 0) ctx->petname_count--;
        }
        return CYXCHAT_OK;
    }

    /* Set petname */
    if (!entry) {
        entry = alloc_petname(ctx);
        if (!entry) {
            return CYXCHAT_ERR_FULL;
        }
    }

    entry->node_id = *node_id;
    snprintf(entry->petname, sizeof(entry->petname), "%s", petname);

    return CYXCHAT_OK;
}

const char* cyxchat_dns_get_petname(cyxchat_dns_ctx_t *ctx,
                                     const cyxwiz_node_id_t *node_id)
{
    if (!ctx || !node_id) return NULL;

    cyxchat_petname_t *entry = find_petname_by_id(ctx, node_id);
    return entry ? entry->petname : NULL;
}

cyxchat_error_t cyxchat_dns_resolve_petname(cyxchat_dns_ctx_t *ctx,
                                             const char *petname,
                                             cyxwiz_node_id_t *node_out)
{
    if (!ctx || !petname || !node_out) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_petname_t *entry = find_petname_by_name(ctx, petname);
    if (!entry) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    *node_out = entry->node_id;
    return CYXCHAT_OK;
}

/* ============================================================
 * Crypto-Names
 * ============================================================ */

void cyxchat_dns_crypto_name(const uint8_t *pubkey, char *name_out)
{
    if (!pubkey || !name_out) return;

#ifdef CYXWIZ_HAS_CRYPTO
    /* Hash public key with BLAKE2b */
    uint8_t hash[32];
    crypto_generichash(hash, sizeof(hash), pubkey, 32, NULL, 0);

    /* Take first 5 bytes (40 bits) and base32 encode to 8 chars */
    base32_encode(hash, 5, name_out, 16);
#else
    /* Fallback: just hex encode first 4 bytes */
    sprintf(name_out, "%02x%02x%02x%02x",
            pubkey[0], pubkey[1], pubkey[2], pubkey[3]);
#endif
}

int cyxchat_dns_is_crypto_name(const char *name)
{
    if (!name) return 0;

    /* Strip .cyx suffix if present */
    size_t len = strlen(name);
    if (len > 4 && strcmp(name + len - 4, CYXCHAT_DNS_SUFFIX) == 0) {
        len -= 4;
    }

    /* Crypto-names are exactly 8 characters of base32 */
    if (len != CYXCHAT_DNS_CRYPTO_NAME_LEN) return 0;

    /* Check all chars are valid base32 */
    for (size_t i = 0; i < len; i++) {
        char c = tolower((unsigned char)name[i]);
        if (!((c >= 'a' && c <= 'z') || (c >= '2' && c <= '7'))) {
            return 0;
        }
    }

    return 1;
}

cyxchat_error_t cyxchat_dns_parse_crypto_name(const char *name,
                                               cyxwiz_node_id_t *id_out)
{
    if (!name || !id_out) {
        return CYXCHAT_ERR_NULL;
    }

    if (!cyxchat_dns_is_crypto_name(name)) {
        return CYXCHAT_ERR_INVALID;
    }

    /* For crypto-names, we can't fully derive the node_id from 8 chars */
    /* Just hash the name to create a deterministic ID */
#ifdef CYXWIZ_HAS_CRYPTO
    crypto_generichash(id_out->bytes, 32, (const uint8_t*)name, strlen(name), NULL, 0);
#else
    memset(id_out->bytes, 0, 32);
    memcpy(id_out->bytes, name, strlen(name) < 32 ? strlen(name) : 32);
#endif

    return CYXCHAT_OK;
}

/* ============================================================
 * Name Validation
 * ============================================================ */

int cyxchat_dns_validate_name(const char *name)
{
    if (!name) return 0;

    size_t len = strlen(name);

    /* Strip .cyx suffix if present */
    if (len > 4 && strcmp(name + len - 4, CYXCHAT_DNS_SUFFIX) == 0) {
        len -= 4;
    }

    /* Check length */
    if (len < 3 || len > CYXCHAT_DNS_MAX_NAME) return 0;

    /* Must start with letter */
    if (!isalpha((unsigned char)name[0])) return 0;

    /* Check all characters */
    int prev_underscore = 0;
    for (size_t i = 0; i < len; i++) {
        char c = name[i];

        if (isalnum((unsigned char)c)) {
            prev_underscore = 0;
        } else if (c == '_') {
            /* No consecutive underscores */
            if (prev_underscore) return 0;
            prev_underscore = 1;
        } else {
            return 0;
        }
    }

    /* Can't end with underscore */
    if (prev_underscore) return 0;

    return 1;
}

cyxchat_error_t cyxchat_dns_normalize_name(const char *name,
                                            char *out, size_t out_len)
{
    if (!name || !out || out_len == 0) {
        return CYXCHAT_ERR_NULL;
    }

    size_t len = strlen(name);

    /* Strip .cyx suffix if present (case-insensitive) */
    if (len > 4) {
        const char *suffix = name + len - 4;
        if (suffix[0] == '.' &&
            (suffix[1] == 'c' || suffix[1] == 'C') &&
            (suffix[2] == 'y' || suffix[2] == 'Y') &&
            (suffix[3] == 'x' || suffix[3] == 'X')) {
            len -= 4;
        }
    }

    if (len >= out_len) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Lowercase */
    for (size_t i = 0; i < len; i++) {
        out[i] = (char)tolower((unsigned char)name[i]);
    }
    out[len] = '\0';

    return CYXCHAT_OK;
}

/* ============================================================
 * Message Handling
 * ============================================================ */

cyxchat_error_t cyxchat_dns_handle_message(cyxchat_dns_ctx_t *ctx,
                                            const cyxwiz_node_id_t *from,
                                            const uint8_t *data,
                                            size_t len)
{
    if (!ctx || !from || !data || len == 0) {
        return CYXCHAT_ERR_NULL;
    }

    uint8_t msg_type = data[0];

    switch (msg_type) {
        case CYXCHAT_MSG_DNS_REGISTER:
            handle_register(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_DNS_LOOKUP:
            handle_lookup(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_DNS_RESPONSE:
            handle_response(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_DNS_ANNOUNCE:
            handle_announce(ctx, from, data, len);
            break;

        case CYXCHAT_MSG_DNS_UPDATE:
            /* Update is same as register */
            handle_register(ctx, from, data, len);
            break;

        default:
            return CYXCHAT_ERR_INVALID;
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Statistics
 * ============================================================ */

void cyxchat_dns_get_stats(cyxchat_dns_ctx_t *ctx, cyxchat_dns_stats_t *stats_out)
{
    if (!ctx || !stats_out) return;

    *stats_out = ctx->stats;
    stats_out->cache_entries = ctx->cache_count;
}
