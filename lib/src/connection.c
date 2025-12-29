/**
 * CyxChat Connection Management
 *
 * NAT traversal and peer-to-peer connection management.
 * Wraps CyxWiz transport layer with connection state tracking
 * and automatic relay fallback.
 */

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include "cyxchat/connection.h"
#include "cyxchat/relay.h"
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
#include <sys/time.h>
#include <time.h>
#endif

/* ============================================================
 * Internal Types
 * ============================================================ */

/* Pending connection request */
typedef struct {
    cyxwiz_node_id_t peer_id;
    cyxchat_conn_complete_callback_t callback;
    void *user_data;
    uint64_t start_time;
    uint8_t punch_attempts;
    int active;
} cyxchat_pending_conn_t;

/* Per-peer connection info */
typedef struct {
    cyxwiz_node_id_t peer_id;
    cyxchat_conn_state_t state;
    uint64_t connected_at;
    uint64_t last_activity;
    uint64_t last_keepalive;
    uint32_t bytes_sent;
    uint32_t bytes_received;
    int8_t rssi;
    int is_relayed;
    int active;
} cyxchat_peer_conn_t;

/* Connection context */
struct cyxchat_conn_ctx {
    /* CyxWiz components */
    cyxwiz_transport_t *transport;
    cyxwiz_peer_table_t *peer_table;

    /* Our identity */
    cyxwiz_node_id_t local_id;

    /* Network status */
    uint32_t public_ip;
    uint16_t public_port;
    cyxwiz_nat_type_t nat_type;
    int stun_complete;
    int bootstrap_connected;

    /* Peer connections */
    cyxchat_peer_conn_t peers[CYXCHAT_MAX_PEER_CONNECTIONS];
    size_t peer_count;

    /* Pending connection requests */
    cyxchat_pending_conn_t pending[CYXCHAT_MAX_PEER_CONNECTIONS];
    size_t pending_count;

    /* Relay context */
    cyxchat_relay_ctx_t *relay;

    /* Callbacks */
    cyxchat_conn_state_callback_t on_state_change;
    void *state_change_user_data;
    cyxchat_conn_data_callback_t on_data;
    void *data_user_data;

    /* Timing */
    uint64_t last_stun_time;
    uint64_t last_poll_time;
};

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

static cyxchat_peer_conn_t* find_peer_conn(cyxchat_conn_ctx_t *ctx, const cyxwiz_node_id_t *peer_id)
{
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (ctx->peers[i].active &&
            memcmp(&ctx->peers[i].peer_id, peer_id, sizeof(cyxwiz_node_id_t)) == 0) {
            return &ctx->peers[i];
        }
    }
    return NULL;
}

static cyxchat_peer_conn_t* alloc_peer_conn(cyxchat_conn_ctx_t *ctx)
{
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (!ctx->peers[i].active) {
            memset(&ctx->peers[i], 0, sizeof(cyxchat_peer_conn_t));
            ctx->peers[i].active = 1;
            ctx->peer_count++;
            return &ctx->peers[i];
        }
    }
    return NULL;
}

static cyxchat_pending_conn_t* find_pending(cyxchat_conn_ctx_t *ctx, const cyxwiz_node_id_t *peer_id)
{
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (ctx->pending[i].active &&
            memcmp(&ctx->pending[i].peer_id, peer_id, sizeof(cyxwiz_node_id_t)) == 0) {
            return &ctx->pending[i];
        }
    }
    return NULL;
}

static cyxchat_pending_conn_t* alloc_pending(cyxchat_conn_ctx_t *ctx)
{
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (!ctx->pending[i].active) {
            memset(&ctx->pending[i], 0, sizeof(cyxchat_pending_conn_t));
            ctx->pending[i].active = 1;
            ctx->pending_count++;
            return &ctx->pending[i];
        }
    }
    return NULL;
}

static void free_pending(cyxchat_conn_ctx_t *ctx, cyxchat_pending_conn_t *pending)
{
    pending->active = 0;
    if (ctx->pending_count > 0) {
        ctx->pending_count--;
    }
}

static void set_peer_state(cyxchat_conn_ctx_t *ctx, cyxchat_peer_conn_t *peer,
                           cyxchat_conn_state_t new_state)
{
    cyxchat_conn_state_t old_state = peer->state;
    if (old_state == new_state) return;

    peer->state = new_state;

    if (new_state == CYXCHAT_CONN_CONNECTED || new_state == CYXCHAT_CONN_RELAYING) {
        peer->connected_at = get_time_ms();
    }

    if (ctx->on_state_change) {
        ctx->on_state_change(ctx, &peer->peer_id, old_state, new_state,
                            ctx->state_change_user_data);
    }
}

/* Transport callbacks */
static void on_transport_recv(cyxwiz_transport_t *transport,
                              const cyxwiz_node_id_t *from,
                              const uint8_t *data, size_t len,
                              void *user_data)
{
    (void)transport;  /* Unused - we use the transport from context */
    cyxchat_conn_ctx_t *ctx = (cyxchat_conn_ctx_t*)user_data;

    /* Update peer connection state */
    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, from);
    if (peer) {
        peer->last_activity = get_time_ms();
        peer->bytes_received += (uint32_t)len;

        /* If we were connecting and got data, we're connected */
        if (peer->state == CYXCHAT_CONN_CONNECTING) {
            set_peer_state(ctx, peer, CYXCHAT_CONN_CONNECTED);
            peer->is_relayed = 0;

            /* Complete pending connection */
            cyxchat_pending_conn_t *pending = find_pending(ctx, from);
            if (pending && pending->callback) {
                pending->callback(ctx, from, CYXCHAT_CONN_CONNECTED, CYXCHAT_OK,
                                 pending->user_data);
            }
            if (pending) {
                free_pending(ctx, pending);
            }
        }
    }

    /* Forward to application callback */
    if (ctx->on_data) {
        ctx->on_data(ctx, from, data, len, ctx->data_user_data);
    }
}

static void on_peer_discovered(cyxwiz_transport_t *transport,
                               const cyxwiz_peer_info_t *peer,
                               void *user_data)
{
    (void)transport;  /* Unused - we use the transport from context */
    cyxchat_conn_ctx_t *ctx = (cyxchat_conn_ctx_t*)user_data;

    /* Check if we have a pending connection request for this peer */
    cyxchat_pending_conn_t *pending = find_pending(ctx, &peer->id);
    if (pending) {
        /* Peer discovered, initiate hole punch */
        cyxchat_peer_conn_t *conn = find_peer_conn(ctx, &peer->id);
        if (conn && conn->state == CYXCHAT_CONN_CONNECTING) {
            /* The transport layer handles hole punching automatically */
            conn->rssi = peer->rssi;
        }
    }

    /* Update or create peer connection record */
    cyxchat_peer_conn_t *conn = find_peer_conn(ctx, &peer->id);
    if (!conn) {
        conn = alloc_peer_conn(ctx);
        if (conn) {
            conn->peer_id = peer->id;
            conn->state = CYXCHAT_CONN_DISCONNECTED;
            conn->rssi = peer->rssi;
        }
    } else {
        conn->rssi = peer->rssi;
        conn->last_activity = get_time_ms();
    }
}

/* ============================================================
 * Lifecycle
 * ============================================================ */

cyxchat_error_t cyxchat_conn_create(cyxchat_conn_ctx_t **ctx,
                                     const char *bootstrap,
                                     const cyxwiz_node_id_t *local_id)
{
    if (!ctx || !local_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Set bootstrap environment if provided */
    if (bootstrap && strlen(bootstrap) > 0) {
#ifdef _WIN32
        _putenv_s("CYXWIZ_BOOTSTRAP", bootstrap);
#else
        setenv("CYXWIZ_BOOTSTRAP", bootstrap, 1);
#endif
    }

    /* Allocate context */
    cyxchat_conn_ctx_t *c = (cyxchat_conn_ctx_t*)calloc(1, sizeof(cyxchat_conn_ctx_t));
    if (!c) {
        return CYXCHAT_ERR_MEMORY;
    }

    c->local_id = *local_id;

    /* Create UDP transport */
    cyxwiz_error_t err = cyxwiz_transport_create(CYXWIZ_TRANSPORT_UDP, &c->transport);
    if (err != CYXWIZ_OK) {
        free(c);
        return CYXCHAT_ERR_NETWORK;
    }

    /* Set local ID */
    cyxwiz_transport_set_local_id(c->transport, local_id);

    /* Set callbacks */
    cyxwiz_transport_set_recv_callback(c->transport, on_transport_recv, c);
    cyxwiz_transport_set_peer_callback(c->transport, on_peer_discovered, c);

    /* Initialize transport */
    err = c->transport->ops->init(c->transport);
    if (err != CYXWIZ_OK) {
        cyxwiz_transport_destroy(c->transport);
        free(c);
        return CYXCHAT_ERR_NETWORK;
    }

    /* Create peer table */
    err = cyxwiz_peer_table_create(&c->peer_table);
    if (err != CYXWIZ_OK) {
        c->transport->ops->shutdown(c->transport);
        cyxwiz_transport_destroy(c->transport);
        free(c);
        return CYXCHAT_ERR_MEMORY;
    }

    /* Create relay context */
    cyxchat_relay_create(&c->relay, c->transport, local_id);

    /* Start discovery */
    c->transport->ops->discover(c->transport);

    c->last_poll_time = get_time_ms();
    c->stun_complete = 0;
    c->bootstrap_connected = 0;

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_conn_destroy(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return;

    /* Destroy relay */
    if (ctx->relay) {
        cyxchat_relay_destroy(ctx->relay);
    }

    /* Destroy peer table */
    if (ctx->peer_table) {
        cyxwiz_peer_table_destroy(ctx->peer_table);
    }

    /* Shutdown transport */
    if (ctx->transport) {
        ctx->transport->ops->stop_discover(ctx->transport);
        ctx->transport->ops->shutdown(ctx->transport);
        cyxwiz_transport_destroy(ctx->transport);
    }

    free(ctx);
}

int cyxchat_conn_poll(cyxchat_conn_ctx_t *ctx, uint64_t now_ms)
{
    if (!ctx) return 0;

    int events = 0;

    /* Poll transport */
    if (ctx->transport) {
        ctx->transport->ops->poll(ctx->transport, 10);
        events++;
    }

    /* Poll relay */
    if (ctx->relay) {
        events += cyxchat_relay_poll(ctx->relay, now_ms);
    }

    /* Update NAT info from transport */
    if (!ctx->stun_complete) {
        ctx->nat_type = cyxwiz_transport_get_nat_type(ctx->transport);
        if (ctx->nat_type != CYXWIZ_NAT_UNKNOWN) {
            ctx->stun_complete = 1;
        }
    }

    /* Check pending connections for timeout */
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        cyxchat_pending_conn_t *pending = &ctx->pending[i];
        if (!pending->active) continue;

        uint64_t elapsed = now_ms - pending->start_time;

        if (elapsed >= CYXCHAT_HOLE_PUNCH_TIMEOUT_MS) {
            /* Hole punch timed out, try relay */
            cyxchat_peer_conn_t *peer = find_peer_conn(ctx, &pending->peer_id);
            if (peer) {
                /* Switch to relay */
                cyxchat_error_t relay_err = cyxchat_relay_connect(
                    ctx->relay, &pending->peer_id
                );

                if (relay_err == CYXCHAT_OK) {
                    set_peer_state(ctx, peer, CYXCHAT_CONN_RELAYING);
                    peer->is_relayed = 1;

                    if (pending->callback) {
                        pending->callback(ctx, &pending->peer_id, CYXCHAT_CONN_RELAYING,
                                         CYXCHAT_OK, pending->user_data);
                    }
                } else {
                    set_peer_state(ctx, peer, CYXCHAT_CONN_DISCONNECTED);

                    if (pending->callback) {
                        pending->callback(ctx, &pending->peer_id, CYXCHAT_CONN_DISCONNECTED,
                                         CYXCHAT_ERR_TIMEOUT, pending->user_data);
                    }
                }
            }

            free_pending(ctx, pending);
            events++;
        }
    }

    /* Check for peer timeouts */
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        cyxchat_peer_conn_t *peer = &ctx->peers[i];
        if (!peer->active) continue;

        if (peer->state == CYXCHAT_CONN_CONNECTED || peer->state == CYXCHAT_CONN_RELAYING) {
            uint64_t elapsed = now_ms - peer->last_activity;

            if (elapsed >= CYXCHAT_CONNECTION_TIMEOUT_MS) {
                /* Peer timed out */
                set_peer_state(ctx, peer, CYXCHAT_CONN_DISCONNECTED);
                events++;
            }
        }
    }

    ctx->last_poll_time = now_ms;
    return events;
}

/* ============================================================
 * Connection Management
 * ============================================================ */

cyxchat_error_t cyxchat_conn_connect(cyxchat_conn_ctx_t *ctx,
                                      const cyxwiz_node_id_t *peer_id,
                                      cyxchat_conn_complete_callback_t callback,
                                      void *user_data)
{
    if (!ctx || !peer_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check if already connected */
    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, peer_id);
    if (peer && (peer->state == CYXCHAT_CONN_CONNECTED || peer->state == CYXCHAT_CONN_RELAYING)) {
        if (callback) {
            callback(ctx, peer_id, peer->state, CYXCHAT_OK, user_data);
        }
        return CYXCHAT_OK;
    }

    /* Check if already connecting */
    if (find_pending(ctx, peer_id)) {
        return CYXCHAT_ERR_EXISTS;
    }

    /* Allocate peer connection if needed */
    if (!peer) {
        peer = alloc_peer_conn(ctx);
        if (!peer) {
            return CYXCHAT_ERR_FULL;
        }
        peer->peer_id = *peer_id;
    }

    /* Create pending connection request */
    cyxchat_pending_conn_t *pending = alloc_pending(ctx);
    if (!pending) {
        return CYXCHAT_ERR_FULL;
    }

    pending->peer_id = *peer_id;
    pending->callback = callback;
    pending->user_data = user_data;
    pending->start_time = get_time_ms();
    pending->punch_attempts = 0;

    /* Set state to connecting */
    set_peer_state(ctx, peer, CYXCHAT_CONN_CONNECTING);

    /* The transport layer's discovery and hole punching handles the rest */
    /* When we receive data from this peer, we know hole punch succeeded */

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_conn_disconnect(cyxchat_conn_ctx_t *ctx,
                                         const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Cancel any pending connection */
    cyxchat_pending_conn_t *pending = find_pending(ctx, peer_id);
    if (pending) {
        free_pending(ctx, pending);
    }

    /* Disconnect peer */
    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, peer_id);
    if (peer) {
        if (peer->is_relayed && ctx->relay) {
            cyxchat_relay_disconnect(ctx->relay, peer_id);
        }
        set_peer_state(ctx, peer, CYXCHAT_CONN_DISCONNECTED);
        return CYXCHAT_OK;
    }

    return CYXCHAT_ERR_NOT_FOUND;
}

cyxchat_conn_state_t cyxchat_conn_get_state(cyxchat_conn_ctx_t *ctx,
                                             const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) {
        return CYXCHAT_CONN_DISCONNECTED;
    }

    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, peer_id);
    if (peer) {
        return peer->state;
    }

    return CYXCHAT_CONN_DISCONNECTED;
}

cyxchat_error_t cyxchat_conn_get_info(cyxchat_conn_ctx_t *ctx,
                                       const cyxwiz_node_id_t *peer_id,
                                       cyxchat_conn_info_t *info_out)
{
    if (!ctx || !peer_id || !info_out) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, peer_id);
    if (!peer) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    info_out->peer_id = peer->peer_id;
    info_out->state = peer->state;
    info_out->connected_at = peer->connected_at;
    info_out->last_activity = peer->last_activity;
    info_out->bytes_sent = peer->bytes_sent;
    info_out->bytes_received = peer->bytes_received;
    info_out->rssi = peer->rssi;
    info_out->is_relayed = peer->is_relayed;

    return CYXCHAT_OK;
}

int cyxchat_conn_is_relayed(cyxchat_conn_ctx_t *ctx, const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) return 0;

    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, peer_id);
    return peer ? peer->is_relayed : 0;
}

/* ============================================================
 * Data Transfer
 * ============================================================ */

cyxchat_error_t cyxchat_conn_send(cyxchat_conn_ctx_t *ctx,
                                   const cyxwiz_node_id_t *peer_id,
                                   const uint8_t *data,
                                   size_t len)
{
    if (!ctx || !peer_id || !data) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, peer_id);
    if (!peer) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    cyxchat_error_t result;

    if (peer->is_relayed && ctx->relay) {
        /* Send via relay */
        result = cyxchat_relay_send(ctx->relay, peer_id, data, len);
    } else {
        /* Send directly via transport */
        cyxwiz_error_t err = ctx->transport->ops->send(ctx->transport, peer_id, data, len);
        result = (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
    }

    if (result == CYXCHAT_OK) {
        peer->bytes_sent += (uint32_t)len;
        peer->last_activity = get_time_ms();
    }

    return result;
}

/* ============================================================
 * Network Status
 * ============================================================ */

void cyxchat_conn_get_status(cyxchat_conn_ctx_t *ctx, cyxchat_network_status_t *status_out)
{
    if (!ctx || !status_out) return;

    status_out->public_ip = ctx->public_ip;
    status_out->public_port = ctx->public_port;
    status_out->nat_type = ctx->nat_type;
    status_out->stun_complete = ctx->stun_complete;
    status_out->bootstrap_connected = ctx->bootstrap_connected;

    /* Count active and relay connections */
    status_out->active_connections = 0;
    status_out->relay_connections = 0;

    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (ctx->peers[i].active) {
            if (ctx->peers[i].state == CYXCHAT_CONN_CONNECTED ||
                ctx->peers[i].state == CYXCHAT_CONN_RELAYING) {
                status_out->active_connections++;
                if (ctx->peers[i].is_relayed) {
                    status_out->relay_connections++;
                }
            }
        }
    }
}

cyxchat_error_t cyxchat_conn_get_public_addr(cyxchat_conn_ctx_t *ctx,
                                              char *buf, size_t buf_size)
{
    if (!ctx || !buf || buf_size < 22) {
        return CYXCHAT_ERR_INVALID;
    }

    if (!ctx->stun_complete || ctx->public_ip == 0) {
        return CYXCHAT_ERR_NETWORK;
    }

    struct in_addr addr;
    addr.s_addr = ctx->public_ip;

    snprintf(buf, buf_size, "%s:%u",
             inet_ntoa(addr),
             ntohs(ctx->public_port));

    return CYXCHAT_OK;
}

const char* cyxchat_conn_nat_type_name(cyxwiz_nat_type_t nat_type)
{
    switch (nat_type) {
        case CYXWIZ_NAT_UNKNOWN:   return "Unknown";
        case CYXWIZ_NAT_OPEN:      return "Open/Public";
        case CYXWIZ_NAT_CONE:      return "Cone NAT";
        case CYXWIZ_NAT_SYMMETRIC: return "Symmetric NAT";
        case CYXWIZ_NAT_BLOCKED:   return "Blocked";
        default:                   return "Unknown";
    }
}

const char* cyxchat_conn_state_name(cyxchat_conn_state_t state)
{
    switch (state) {
        case CYXCHAT_CONN_DISCONNECTED: return "Disconnected";
        case CYXCHAT_CONN_DISCOVERING:  return "Discovering";
        case CYXCHAT_CONN_CONNECTING:   return "Connecting";
        case CYXCHAT_CONN_RELAYING:     return "Relaying";
        case CYXCHAT_CONN_CONNECTED:    return "Connected";
        default:                        return "Unknown";
    }
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_conn_set_on_state_change(cyxchat_conn_ctx_t *ctx,
                                       cyxchat_conn_state_callback_t callback,
                                       void *user_data)
{
    if (!ctx) return;
    ctx->on_state_change = callback;
    ctx->state_change_user_data = user_data;
}

void cyxchat_conn_set_on_data(cyxchat_conn_ctx_t *ctx,
                               cyxchat_conn_data_callback_t callback,
                               void *user_data)
{
    if (!ctx) return;
    ctx->on_data = callback;
    ctx->data_user_data = user_data;
}

/* ============================================================
 * Relay Management
 * ============================================================ */

cyxchat_error_t cyxchat_conn_add_relay(cyxchat_conn_ctx_t *ctx, const char *relay_addr)
{
    if (!ctx || !relay_addr) {
        return CYXCHAT_ERR_NULL;
    }

    if (ctx->relay) {
        return cyxchat_relay_add_server(ctx->relay, relay_addr);
    }

    return CYXCHAT_ERR_INVALID;
}

size_t cyxchat_conn_relay_count(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return 0;

    size_t count = 0;
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (ctx->peers[i].active && ctx->peers[i].is_relayed) {
            count++;
        }
    }
    return count;
}

cyxchat_error_t cyxchat_conn_force_relay(cyxchat_conn_ctx_t *ctx,
                                          const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, peer_id);
    if (!peer) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Force relay connection */
    if (ctx->relay) {
        cyxchat_error_t err = cyxchat_relay_connect(ctx->relay, peer_id);
        if (err == CYXCHAT_OK) {
            set_peer_state(ctx, peer, CYXCHAT_CONN_RELAYING);
            peer->is_relayed = 1;
            return CYXCHAT_OK;
        }
        return err;
    }

    return CYXCHAT_ERR_NETWORK;
}

/* ============================================================
 * Access to Underlying Transport
 * ============================================================ */

cyxwiz_transport_t* cyxchat_conn_get_transport(cyxchat_conn_ctx_t *ctx)
{
    return ctx ? ctx->transport : NULL;
}

cyxwiz_peer_table_t* cyxchat_conn_get_peer_table(cyxchat_conn_ctx_t *ctx)
{
    return ctx ? ctx->peer_table : NULL;
}
