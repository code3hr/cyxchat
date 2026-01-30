/**
 * CyxChat Server Registry
 *
 * Multi-server management with Ed25519 verification,
 * health checking, and latency-based selection.
 */

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include "cyxchat/server_registry.h"
#include <cyxwiz/memory.h>
#include <cyxwiz/log.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <time.h>
#endif

#ifdef CYXWIZ_HAS_CRYPTO
#include <sodium.h>
#endif

/* ============================================================
 * Internal Types
 * ============================================================ */

/* Internal server entry */
typedef struct {
    char     addr[64];                              /* "ip:port" */
    uint32_t ip;                                    /* Network byte order */
    uint16_t port;                                  /* Network byte order */
    uint8_t  pubkey[CYXCHAT_SERVER_PUBKEY_SIZE];    /* Expected Ed25519 pubkey */
    int      has_pubkey;                            /* 1 if pubkey is set */

    cyxchat_server_state_t state;

    /* Health tracking */
    uint32_t latency_ms;                            /* Last measured RTT */
    uint32_t avg_latency_ms;                        /* EMA (alpha=0.3) */
    uint64_t last_ping_sent;                        /* When we sent last ping */
    uint64_t last_pong_received;                    /* When we got last pong */
    uint8_t  missed_pongs;                          /* Consecutive missed */
    uint64_t ping_timestamp;                        /* Timestamp in current ping */

    /* Verification */
    uint8_t  challenge_nonce[CYXCHAT_SERVER_NONCE_SIZE]; /* Active challenge */
    uint64_t challenge_sent_at;                     /* When challenge was sent */
    int      challenge_active;                      /* 1 if waiting for response */

    /* Flags */
    int      is_seed;
    int      is_bootstrap;
    int      is_relay;
    int      active;
} cyxchat_server_entry_t;

/* Registry context */
struct cyxchat_server_registry {
    cyxwiz_transport_t *transport;
    cyxwiz_node_id_t local_id;

    cyxchat_server_entry_t servers[CYXCHAT_MAX_SERVERS];
    size_t server_count;

    /* Callbacks */
    cyxchat_server_state_callback_t on_state_change;
    void *state_user_data;
};

/* ============================================================
 * Protocol Structures (packed for network)
 * ============================================================ */

#ifdef _MSC_VER
#pragma pack(push, 1)
#endif

/* Health ping: [type:1][timestamp:8] = 9 bytes */
typedef struct {
    uint8_t  type;
    uint64_t timestamp;
}
#ifdef __GNUC__
__attribute__((packed))
#endif
cyxchat_health_ping_t;

/* Health pong: [type:1][timestamp:8] = 9 bytes */
typedef struct {
    uint8_t  type;
    uint64_t timestamp;
}
#ifdef __GNUC__
__attribute__((packed))
#endif
cyxchat_health_pong_t;

/* Challenge: [type:1][nonce:32] = 33 bytes */
typedef struct {
    uint8_t  type;
    uint8_t  nonce[CYXCHAT_SERVER_NONCE_SIZE];
}
#ifdef __GNUC__
__attribute__((packed))
#endif
cyxchat_server_challenge_t;

/* Challenge response: [type:1][nonce:32][pubkey:32][signature:64] = 129 bytes */
typedef struct {
    uint8_t  type;
    uint8_t  nonce[CYXCHAT_SERVER_NONCE_SIZE];
    uint8_t  pubkey[CYXCHAT_SERVER_PUBKEY_SIZE];
    uint8_t  signature[CYXCHAT_SERVER_SIG_SIZE];
}
#ifdef __GNUC__
__attribute__((packed))
#endif
cyxchat_server_challenge_resp_t;

#ifdef _MSC_VER
#pragma pack(pop)
#endif

/* ============================================================
 * Seed Server List
 * ============================================================ */

typedef struct {
    const char *addr;
    /* Ed25519 pubkey hex (64 chars) - NULL if not yet known.
     * Once the server generates its keypair and we hardcode it here,
     * clients will verify the server on first contact. */
    const char *pubkey_hex;
} cyxchat_seed_server_t;

static const cyxchat_seed_server_t SEED_SERVERS[] = {
    /* Primary server */
    { "129.151.146.219:7777", "87a16820981e16be773d64a49ef434cb62c233abaf1785bfb5ed25affad7640b" },
    /* Add more seed servers here as they come online:
     * { "IP:PORT", "ED25519_PUBKEY_HEX_64_CHARS" },
     */
};

#define SEED_SERVER_COUNT (sizeof(SEED_SERVERS) / sizeof(SEED_SERVERS[0]))

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

static int parse_address(const char *addr, uint32_t *ip_out, uint16_t *port_out)
{
    char host[256];
    int port;

    const char *colon = strchr(addr, ':');
    if (!colon) return 0;

    size_t host_len = (size_t)(colon - addr);
    if (host_len >= sizeof(host)) return 0;

    memcpy(host, addr, host_len);
    host[host_len] = '\0';
    port = atoi(colon + 1);

    if (port <= 0 || port > 65535) return 0;

    struct in_addr in;
    if (inet_pton(AF_INET, host, &in) != 1) {
        return 0;
    }

    *ip_out = in.s_addr;
    *port_out = htons((uint16_t)port);
    return 1;
}

static int hex_to_bytes(const char *hex, uint8_t *out, size_t out_len)
{
    size_t hex_len = strlen(hex);
    if (hex_len != out_len * 2) return 0;

    for (size_t i = 0; i < out_len; i++) {
        unsigned int byte;
        if (sscanf(hex + i * 2, "%02x", &byte) != 1) return 0;
        out[i] = (uint8_t)byte;
    }
    return 1;
}

/* Build a fake node ID from server address for transport layer */
static void server_to_node_id(const cyxchat_server_entry_t *srv, cyxwiz_node_id_t *id)
{
    memset(id, 0, sizeof(*id));
    memcpy(id->bytes, &srv->ip, 4);
    memcpy(id->bytes + 4, &srv->port, 2);
    id->bytes[6] = 0xFF;  /* Mark as server address */
}

static cyxchat_error_t send_to_server(cyxchat_server_registry_t *reg,
                                       cyxchat_server_entry_t *srv,
                                       const uint8_t *data, size_t len)
{
    cyxwiz_node_id_t srv_id;
    server_to_node_id(srv, &srv_id);

    cyxwiz_error_t err = reg->transport->ops->send(reg->transport, &srv_id, data, len);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
}

static cyxchat_server_entry_t* find_server(cyxchat_server_registry_t *reg, const char *addr)
{
    for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
        if (reg->servers[i].active && strcmp(reg->servers[i].addr, addr) == 0) {
            return &reg->servers[i];
        }
    }
    return NULL;
}

/* Find server by IP:port (network byte order) */
static cyxchat_server_entry_t* find_server_by_endpoint(cyxchat_server_registry_t *reg,
                                                         uint32_t ip, uint16_t port)
{
    for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
        if (reg->servers[i].active &&
            reg->servers[i].ip == ip &&
            reg->servers[i].port == port) {
            return &reg->servers[i];
        }
    }
    return NULL;
}

static void set_server_state(cyxchat_server_registry_t *reg,
                              cyxchat_server_entry_t *srv,
                              cyxchat_server_state_t new_state)
{
    cyxchat_server_state_t old_state = srv->state;
    if (old_state == new_state) return;

    srv->state = new_state;

    CYXWIZ_INFO("Server %s: %s -> %s",
                srv->addr,
                cyxchat_server_state_name(old_state),
                cyxchat_server_state_name(new_state));

    if (reg->on_state_change) {
        cyxchat_server_info_t info;
        memset(&info, 0, sizeof(info));
        strncpy(info.addr, srv->addr, sizeof(info.addr) - 1);
        memcpy(info.pubkey, srv->pubkey, CYXCHAT_SERVER_PUBKEY_SIZE);
        info.state = new_state;
        info.latency_ms = srv->latency_ms;
        info.avg_latency_ms = srv->avg_latency_ms;
        info.last_pong_received = srv->last_pong_received;
        info.missed_pongs = srv->missed_pongs;
        info.is_seed = srv->is_seed;
        info.is_bootstrap = srv->is_bootstrap;
        info.is_relay = srv->is_relay;

        reg->on_state_change(reg, &info, old_state, new_state, reg->state_user_data);
    }
}

static void fill_server_info(const cyxchat_server_entry_t *srv, cyxchat_server_info_t *out)
{
    memset(out, 0, sizeof(*out));
    strncpy(out->addr, srv->addr, sizeof(out->addr) - 1);
    memcpy(out->pubkey, srv->pubkey, CYXCHAT_SERVER_PUBKEY_SIZE);
    out->state = srv->state;
    out->latency_ms = srv->latency_ms;
    out->avg_latency_ms = srv->avg_latency_ms;
    out->last_pong_received = srv->last_pong_received;
    out->missed_pongs = srv->missed_pongs;
    out->is_seed = srv->is_seed;
    out->is_bootstrap = srv->is_bootstrap;
    out->is_relay = srv->is_relay;
}

/* ============================================================
 * Verification
 * ============================================================ */

static void send_challenge(cyxchat_server_registry_t *reg, cyxchat_server_entry_t *srv)
{
#ifdef CYXWIZ_HAS_CRYPTO
    cyxchat_server_challenge_t msg;
    msg.type = CYXCHAT_MSG_SERVER_CHALLENGE;

    /* Generate random nonce */
    randombytes_buf(msg.nonce, CYXCHAT_SERVER_NONCE_SIZE);
    memcpy(srv->challenge_nonce, msg.nonce, CYXCHAT_SERVER_NONCE_SIZE);
    srv->challenge_sent_at = get_time_ms();
    srv->challenge_active = 1;

    send_to_server(reg, srv, (uint8_t*)&msg, sizeof(msg));
    set_server_state(reg, srv, CYXCHAT_SERVER_VERIFYING);

    CYXWIZ_INFO("Sent verification challenge to %s", srv->addr);
#else
    /* Without crypto, skip verification - go straight to verified */
    (void)reg;
    set_server_state(reg, srv, CYXCHAT_SERVER_VERIFIED);
#endif
}

static int verify_challenge_response(cyxchat_server_entry_t *srv,
                                      const cyxchat_server_challenge_resp_t *resp)
{
#ifdef CYXWIZ_HAS_CRYPTO
    /* Check nonce matches */
    if (memcmp(resp->nonce, srv->challenge_nonce, CYXCHAT_SERVER_NONCE_SIZE) != 0) {
        CYXWIZ_WARN("Challenge nonce mismatch from %s", srv->addr);
        return 0;
    }

    /* If we have an expected pubkey, verify it matches */
    if (srv->has_pubkey) {
        if (memcmp(resp->pubkey, srv->pubkey, CYXCHAT_SERVER_PUBKEY_SIZE) != 0) {
            CYXWIZ_WARN("Server %s pubkey mismatch", srv->addr);
            return 0;
        }
    }

    /* Verify Ed25519 signature over the nonce */
    if (crypto_sign_ed25519_verify_detached(
            resp->signature,
            resp->nonce,
            CYXCHAT_SERVER_NONCE_SIZE,
            resp->pubkey) != 0) {
        CYXWIZ_WARN("Server %s: invalid signature", srv->addr);
        return 0;
    }

    /* Store the pubkey if we didn't have one */
    if (!srv->has_pubkey) {
        memcpy(srv->pubkey, resp->pubkey, CYXCHAT_SERVER_PUBKEY_SIZE);
        srv->has_pubkey = 1;
    }

    return 1;
#else
    (void)srv;
    (void)resp;
    return 1;  /* No crypto = always accept */
#endif
}

/* ============================================================
 * Health Checking
 * ============================================================ */

static void send_health_ping(cyxchat_server_registry_t *reg, cyxchat_server_entry_t *srv)
{
    cyxchat_health_ping_t msg;
    msg.type = CYXCHAT_MSG_SERVER_HEALTH_PING;
    msg.timestamp = get_time_ms();

    srv->ping_timestamp = msg.timestamp;
    srv->last_ping_sent = msg.timestamp;

    send_to_server(reg, srv, (uint8_t*)&msg, sizeof(msg));
}

static void handle_health_pong(cyxchat_server_registry_t *reg,
                                cyxchat_server_entry_t *srv,
                                uint64_t echoed_timestamp)
{
    uint64_t now = get_time_ms();

    /* Calculate RTT */
    if (echoed_timestamp <= now) {
        srv->latency_ms = (uint32_t)(now - echoed_timestamp);
    } else {
        srv->latency_ms = 0;
    }

    /* Update EMA (alpha = 0.3) */
    if (srv->avg_latency_ms == 0) {
        srv->avg_latency_ms = srv->latency_ms;
    } else {
        /* avg = 0.3 * new + 0.7 * old */
        srv->avg_latency_ms = (uint32_t)(
            (3 * (uint64_t)srv->latency_ms + 7 * (uint64_t)srv->avg_latency_ms) / 10
        );
    }

    srv->last_pong_received = now;
    srv->missed_pongs = 0;

    /* If verified but not yet healthy, promote to healthy */
    if (srv->state == CYXCHAT_SERVER_VERIFIED || srv->state == CYXCHAT_SERVER_UNHEALTHY) {
        set_server_state(reg, srv, CYXCHAT_SERVER_HEALTHY);
    }
    /* If unknown (no crypto verification), still mark healthy after first pong */
    if (srv->state == CYXCHAT_SERVER_UNKNOWN) {
        set_server_state(reg, srv, CYXCHAT_SERVER_HEALTHY);
    }
}

/* ============================================================
 * Lifecycle
 * ============================================================ */

cyxchat_error_t cyxchat_server_registry_create(cyxchat_server_registry_t **reg,
                                                cyxwiz_transport_t *transport,
                                                const cyxwiz_node_id_t *local_id)
{
    if (!reg || !transport || !local_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_server_registry_t *r = (cyxchat_server_registry_t*)calloc(
        1, sizeof(cyxchat_server_registry_t));
    if (!r) {
        return CYXCHAT_ERR_MEMORY;
    }

    r->transport = transport;
    r->local_id = *local_id;

    *reg = r;
    return CYXCHAT_OK;
}

void cyxchat_server_registry_destroy(cyxchat_server_registry_t *reg)
{
    if (!reg) return;
    free(reg);
}

int cyxchat_server_registry_poll(cyxchat_server_registry_t *reg, uint64_t now_ms)
{
    if (!reg) return 0;

    int events = 0;

    for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
        cyxchat_server_entry_t *srv = &reg->servers[i];
        if (!srv->active) continue;

        /* Check verification timeout */
        if (srv->state == CYXCHAT_SERVER_VERIFYING && srv->challenge_active) {
            if (now_ms - srv->challenge_sent_at > CYXCHAT_SERVER_VERIFY_TIMEOUT_MS) {
                CYXWIZ_WARN("Server %s: verification timed out", srv->addr);
                srv->challenge_active = 0;
                /* Retry verification */
                send_challenge(reg, srv);
                events++;
            }
            continue;  /* Don't health-ping while verifying */
        }

        /* Only health-check verified/healthy/unhealthy/unknown servers */
        if (srv->state == CYXCHAT_SERVER_REJECTED) continue;

        /* Send health ping if interval elapsed */
        if (now_ms - srv->last_ping_sent >= CYXCHAT_HEALTH_PING_INTERVAL_MS) {
            send_health_ping(reg, srv);
            events++;
        }

        /* Check for missed pong */
        if (srv->last_ping_sent > 0 &&
            srv->last_pong_received < srv->last_ping_sent &&
            now_ms - srv->last_ping_sent > CYXCHAT_HEALTH_TIMEOUT_MS) {
            srv->missed_pongs++;

            if (srv->missed_pongs >= CYXCHAT_SERVER_UNHEALTHY_COUNT) {
                if (srv->state == CYXCHAT_SERVER_HEALTHY ||
                    srv->state == CYXCHAT_SERVER_VERIFIED) {
                    set_server_state(reg, srv, CYXCHAT_SERVER_UNHEALTHY);
                    events++;
                }
            }
        }
    }

    return events;
}

/* ============================================================
 * Server Management
 * ============================================================ */

cyxchat_error_t cyxchat_server_registry_add(cyxchat_server_registry_t *reg,
                                             const char *addr,
                                             const uint8_t *expected_pubkey)
{
    if (!reg || !addr) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check if already exists */
    cyxchat_server_entry_t *existing = find_server(reg, addr);
    if (existing) {
        /* Update pubkey if provided and not already set */
        if (expected_pubkey && !existing->has_pubkey) {
            memcpy(existing->pubkey, expected_pubkey, CYXCHAT_SERVER_PUBKEY_SIZE);
            existing->has_pubkey = 1;
        }
        return CYXCHAT_OK;
    }

    /* Find empty slot */
    cyxchat_server_entry_t *srv = NULL;
    for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
        if (!reg->servers[i].active) {
            srv = &reg->servers[i];
            break;
        }
    }

    if (!srv) {
        return CYXCHAT_ERR_FULL;
    }

    /* Parse address */
    uint32_t ip;
    uint16_t port;
    if (!parse_address(addr, &ip, &port)) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Initialize entry */
    memset(srv, 0, sizeof(*srv));
    strncpy(srv->addr, addr, sizeof(srv->addr) - 1);
    srv->ip = ip;
    srv->port = port;
    srv->active = 1;
    srv->is_bootstrap = 1;
    srv->is_relay = 1;
    srv->state = CYXCHAT_SERVER_UNKNOWN;

    if (expected_pubkey) {
        memcpy(srv->pubkey, expected_pubkey, CYXCHAT_SERVER_PUBKEY_SIZE);
        srv->has_pubkey = 1;
        /* Start verification */
        send_challenge(reg, srv);
    }

    reg->server_count++;

    CYXWIZ_INFO("Added server %s to registry (count=%zu, has_pubkey=%d)",
                addr, reg->server_count, srv->has_pubkey);

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_server_registry_remove(cyxchat_server_registry_t *reg,
                                                const char *addr)
{
    if (!reg || !addr) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_server_entry_t *srv = find_server(reg, addr);
    if (!srv) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    srv->active = 0;
    if (reg->server_count > 0) {
        reg->server_count--;
    }

    CYXWIZ_INFO("Removed server %s from registry", addr);
    return CYXCHAT_OK;
}

size_t cyxchat_server_registry_load_seeds(cyxchat_server_registry_t *reg)
{
    if (!reg) return 0;

    size_t added = 0;

    for (size_t i = 0; i < SEED_SERVER_COUNT; i++) {
        uint8_t pubkey[CYXCHAT_SERVER_PUBKEY_SIZE];
        const uint8_t *pk = NULL;

        if (SEED_SERVERS[i].pubkey_hex) {
            if (hex_to_bytes(SEED_SERVERS[i].pubkey_hex, pubkey, CYXCHAT_SERVER_PUBKEY_SIZE)) {
                pk = pubkey;
            }
        }

        cyxchat_error_t err = cyxchat_server_registry_add(reg, SEED_SERVERS[i].addr, pk);
        if (err == CYXCHAT_OK) {
            /* Mark as seed */
            cyxchat_server_entry_t *srv = find_server(reg, SEED_SERVERS[i].addr);
            if (srv) {
                srv->is_seed = 1;
            }
            added++;
        }
    }

    CYXWIZ_INFO("Loaded %zu seed servers", added);
    return added;
}

/* ============================================================
 * Server Selection
 * ============================================================ */

cyxchat_error_t cyxchat_server_registry_get_best(cyxchat_server_registry_t *reg,
                                                  cyxchat_server_info_t *out)
{
    if (!reg || !out) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_server_entry_t *best = NULL;
    uint32_t best_latency = UINT32_MAX;

    for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
        cyxchat_server_entry_t *srv = &reg->servers[i];
        if (!srv->active) continue;

        /* Prefer healthy servers; fall back to verified, then unknown */
        int usable = (srv->state == CYXCHAT_SERVER_HEALTHY ||
                      srv->state == CYXCHAT_SERVER_VERIFIED ||
                      srv->state == CYXCHAT_SERVER_UNKNOWN);
        if (!usable) continue;

        uint32_t effective_latency = srv->avg_latency_ms;

        /* Penalize non-healthy servers */
        if (srv->state == CYXCHAT_SERVER_VERIFIED) {
            effective_latency += 100;  /* +100ms penalty */
        } else if (srv->state == CYXCHAT_SERVER_UNKNOWN) {
            effective_latency += 500;  /* +500ms penalty for unverified */
        }

        if (effective_latency < best_latency) {
            best_latency = effective_latency;
            best = srv;
        }
    }

    if (!best) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    fill_server_info(best, out);
    return CYXCHAT_OK;
}

size_t cyxchat_server_registry_get_all(cyxchat_server_registry_t *reg,
                                        cyxchat_server_info_t *out,
                                        size_t max)
{
    if (!reg || !out || max == 0) return 0;

    size_t count = 0;
    for (size_t i = 0; i < CYXCHAT_MAX_SERVERS && count < max; i++) {
        if (reg->servers[i].active) {
            fill_server_info(&reg->servers[i], &out[count]);
            count++;
        }
    }
    return count;
}

size_t cyxchat_server_registry_count(cyxchat_server_registry_t *reg)
{
    return reg ? reg->server_count : 0;
}

size_t cyxchat_server_registry_healthy_count(cyxchat_server_registry_t *reg)
{
    if (!reg) return 0;

    size_t count = 0;
    for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
        if (reg->servers[i].active && reg->servers[i].state == CYXCHAT_SERVER_HEALTHY) {
            count++;
        }
    }
    return count;
}

/* ============================================================
 * Message Handling
 * ============================================================ */

int cyxchat_server_registry_is_message(uint8_t msg_type)
{
    return msg_type == CYXCHAT_MSG_SERVER_HEALTH_PING ||
           msg_type == CYXCHAT_MSG_SERVER_HEALTH_PONG ||
           msg_type == CYXCHAT_MSG_SERVER_CHALLENGE ||
           msg_type == CYXCHAT_MSG_SERVER_CHALLENGE_RESP;
}

cyxchat_error_t cyxchat_server_registry_handle_message(cyxchat_server_registry_t *reg,
                                                        const uint8_t *data,
                                                        size_t len)
{
    if (!reg || !data || len < 1) {
        return CYXCHAT_ERR_NULL;
    }

    uint8_t msg_type = data[0];

    switch (msg_type) {
        case CYXCHAT_MSG_SERVER_HEALTH_PONG: {
            if (len < sizeof(cyxchat_health_pong_t)) {
                return CYXCHAT_ERR_INVALID;
            }
            const cyxchat_health_pong_t *pong = (const cyxchat_health_pong_t*)data;

            /* Find server that matches this pong's timestamp */
            for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
                cyxchat_server_entry_t *srv = &reg->servers[i];
                if (!srv->active) continue;
                if (srv->ping_timestamp == pong->timestamp) {
                    handle_health_pong(reg, srv, pong->timestamp);
                    return CYXCHAT_OK;
                }
            }
            /* No matching server - could be a late/stale pong */
            return CYXCHAT_OK;
        }

        case CYXCHAT_MSG_SERVER_CHALLENGE_RESP: {
            if (len < sizeof(cyxchat_server_challenge_resp_t)) {
                return CYXCHAT_ERR_INVALID;
            }
            const cyxchat_server_challenge_resp_t *resp =
                (const cyxchat_server_challenge_resp_t*)data;

            /* Find server with active challenge matching this nonce */
            for (size_t i = 0; i < CYXCHAT_MAX_SERVERS; i++) {
                cyxchat_server_entry_t *srv = &reg->servers[i];
                if (!srv->active || !srv->challenge_active) continue;
                if (memcmp(srv->challenge_nonce, resp->nonce,
                           CYXCHAT_SERVER_NONCE_SIZE) != 0) continue;

                srv->challenge_active = 0;

                if (verify_challenge_response(srv, resp)) {
                    CYXWIZ_INFO("Server %s verified successfully", srv->addr);
                    set_server_state(reg, srv, CYXCHAT_SERVER_VERIFIED);
                } else {
                    CYXWIZ_WARN("Server %s verification FAILED", srv->addr);
                    set_server_state(reg, srv, CYXCHAT_SERVER_REJECTED);
                }
                return CYXCHAT_OK;
            }
            return CYXCHAT_OK;
        }

        default:
            return CYXCHAT_ERR_INVALID;
    }
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_server_registry_set_callback(cyxchat_server_registry_t *reg,
                                           cyxchat_server_state_callback_t callback,
                                           void *user_data)
{
    if (!reg) return;
    reg->on_state_change = callback;
    reg->state_user_data = user_data;
}

const char* cyxchat_server_state_name(cyxchat_server_state_t state)
{
    switch (state) {
        case CYXCHAT_SERVER_UNKNOWN:    return "Unknown";
        case CYXCHAT_SERVER_VERIFYING:  return "Verifying";
        case CYXCHAT_SERVER_VERIFIED:   return "Verified";
        case CYXCHAT_SERVER_HEALTHY:    return "Healthy";
        case CYXCHAT_SERVER_UNHEALTHY:  return "Unhealthy";
        case CYXCHAT_SERVER_REJECTED:   return "Rejected";
        default:                        return "Unknown";
    }
}
