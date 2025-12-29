/**
 * CyxChat Relay Client
 *
 * Relay fallback for when direct UDP hole punching fails.
 * All data remains end-to-end encrypted.
 */

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

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
#include <time.h>
#endif

/* ============================================================
 * Internal Types
 * ============================================================ */

/* Relay server endpoint */
typedef struct {
    uint32_t ip;            /* Network byte order */
    uint16_t port;          /* Network byte order */
    int active;
} cyxchat_relay_server_t;

/* Active relay connection */
typedef struct {
    cyxwiz_node_id_t peer_id;
    uint64_t connected_at;
    uint64_t last_activity;
    uint64_t last_keepalive;
    uint32_t bytes_sent;
    uint32_t bytes_received;
    int server_index;       /* Which relay server */
    int active;
} cyxchat_relay_conn_internal_t;

/* Relay context */
struct cyxchat_relay_ctx {
    /* Transport for sending/receiving */
    cyxwiz_transport_t *transport;

    /* Our identity */
    cyxwiz_node_id_t local_id;

    /* Relay servers */
    cyxchat_relay_server_t servers[CYXCHAT_MAX_RELAY_SERVERS];
    size_t server_count;

    /* Active connections */
    cyxchat_relay_conn_internal_t connections[CYXCHAT_MAX_RELAY_CONNECTIONS];
    size_t connection_count;

    /* Callbacks */
    cyxchat_relay_data_callback_t on_data;
    void *data_user_data;
    cyxchat_relay_state_callback_t on_state;
    void *state_user_data;
};

/* Relay protocol messages - packed for network */
#ifdef _MSC_VER
#pragma pack(push, 1)
#endif

typedef struct {
    uint8_t type;
    cyxwiz_node_id_t from;
    cyxwiz_node_id_t to;
} cyxchat_relay_connect_msg_t;

typedef struct {
    uint8_t type;
    cyxwiz_node_id_t peer;
    uint8_t success;
} cyxchat_relay_connect_ack_msg_t;

typedef struct {
    uint8_t type;
    cyxwiz_node_id_t from;
    cyxwiz_node_id_t to;
    uint16_t data_len;
    uint8_t data[1];        /* Flexible array */
} cyxchat_relay_data_msg_t;

#define CYXCHAT_RELAY_DATA_HDR_SIZE (1 + 32 + 32 + 2)

typedef struct {
    uint8_t type;
    cyxwiz_node_id_t from;
} cyxchat_relay_keepalive_msg_t;

#ifdef _MSC_VER
#pragma pack(pop)
#endif

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

static cyxchat_relay_conn_internal_t* find_connection(cyxchat_relay_ctx_t *ctx,
                                                       const cyxwiz_node_id_t *peer_id)
{
    for (size_t i = 0; i < CYXCHAT_MAX_RELAY_CONNECTIONS; i++) {
        if (ctx->connections[i].active &&
            memcmp(&ctx->connections[i].peer_id, peer_id, sizeof(cyxwiz_node_id_t)) == 0) {
            return &ctx->connections[i];
        }
    }
    return NULL;
}

static cyxchat_relay_conn_internal_t* alloc_connection(cyxchat_relay_ctx_t *ctx)
{
    for (size_t i = 0; i < CYXCHAT_MAX_RELAY_CONNECTIONS; i++) {
        if (!ctx->connections[i].active) {
            memset(&ctx->connections[i], 0, sizeof(cyxchat_relay_conn_internal_t));
            ctx->connections[i].active = 1;
            ctx->connection_count++;
            return &ctx->connections[i];
        }
    }
    return NULL;
}

static void free_connection(cyxchat_relay_ctx_t *ctx, cyxchat_relay_conn_internal_t *conn)
{
    if (!conn) return;

    if (ctx->on_state) {
        ctx->on_state(ctx, &conn->peer_id, 0, ctx->state_user_data);
    }

    conn->active = 0;
    if (ctx->connection_count > 0) {
        ctx->connection_count--;
    }
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

/* Send to a specific relay server */
static cyxchat_error_t send_to_relay(cyxchat_relay_ctx_t *ctx, int server_idx,
                                      const uint8_t *data, size_t len)
{
    if (server_idx < 0 || (size_t)server_idx >= ctx->server_count) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Build a fake node ID from relay server address for transport layer */
    /* In a real implementation, relay servers would have node IDs */
    cyxwiz_node_id_t relay_id;
    memset(&relay_id, 0, sizeof(relay_id));
    memcpy(relay_id.bytes, &ctx->servers[server_idx].ip, 4);
    memcpy(relay_id.bytes + 4, &ctx->servers[server_idx].port, 2);
    relay_id.bytes[6] = 0xFF;  /* Mark as relay address */

    cyxwiz_error_t err = ctx->transport->ops->send(ctx->transport, &relay_id, data, len);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
}

/* ============================================================
 * Lifecycle
 * ============================================================ */

cyxchat_error_t cyxchat_relay_create(cyxchat_relay_ctx_t **ctx,
                                      cyxwiz_transport_t *transport,
                                      const cyxwiz_node_id_t *local_id)
{
    if (!ctx || !transport || !local_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_relay_ctx_t *r = (cyxchat_relay_ctx_t*)calloc(1, sizeof(cyxchat_relay_ctx_t));
    if (!r) {
        return CYXCHAT_ERR_MEMORY;
    }

    r->transport = transport;
    r->local_id = *local_id;

    /* Check for relay servers in environment */
    const char *env = getenv("CYXCHAT_RELAY");
    if (env && strlen(env) > 0) {
        char *copy = strdup(env);
        char *token = strtok(copy, ",");
        while (token && r->server_count < CYXCHAT_MAX_RELAY_SERVERS) {
            uint32_t ip;
            uint16_t port;
            if (parse_address(token, &ip, &port)) {
                r->servers[r->server_count].ip = ip;
                r->servers[r->server_count].port = port;
                r->servers[r->server_count].active = 1;
                r->server_count++;
            }
            token = strtok(NULL, ",");
        }
        free(copy);
    }

    *ctx = r;
    return CYXCHAT_OK;
}

void cyxchat_relay_destroy(cyxchat_relay_ctx_t *ctx)
{
    if (!ctx) return;

    /* Disconnect all connections */
    for (size_t i = 0; i < CYXCHAT_MAX_RELAY_CONNECTIONS; i++) {
        if (ctx->connections[i].active) {
            free_connection(ctx, &ctx->connections[i]);
        }
    }

    free(ctx);
}

int cyxchat_relay_poll(cyxchat_relay_ctx_t *ctx, uint64_t now_ms)
{
    if (!ctx) return 0;

    int events = 0;

    /* Send keepalives and check timeouts */
    for (size_t i = 0; i < CYXCHAT_MAX_RELAY_CONNECTIONS; i++) {
        cyxchat_relay_conn_internal_t *conn = &ctx->connections[i];
        if (!conn->active) continue;

        /* Check for timeout */
        if (now_ms - conn->last_activity > CYXCHAT_RELAY_TIMEOUT_MS) {
            free_connection(ctx, conn);
            events++;
            continue;
        }

        /* Send keepalive if needed */
        if (now_ms - conn->last_keepalive > CYXCHAT_RELAY_KEEPALIVE_MS) {
            cyxchat_relay_keepalive_msg_t msg;
            msg.type = CYXCHAT_RELAY_KEEPALIVE;
            msg.from = ctx->local_id;

            send_to_relay(ctx, conn->server_index, (uint8_t*)&msg, sizeof(msg));
            conn->last_keepalive = now_ms;
            events++;
        }
    }

    return events;
}

/* ============================================================
 * Relay Server Management
 * ============================================================ */

cyxchat_error_t cyxchat_relay_add_server(cyxchat_relay_ctx_t *ctx, const char *addr)
{
    if (!ctx || !addr) {
        return CYXCHAT_ERR_NULL;
    }

    if (ctx->server_count >= CYXCHAT_MAX_RELAY_SERVERS) {
        return CYXCHAT_ERR_FULL;
    }

    uint32_t ip;
    uint16_t port;
    if (!parse_address(addr, &ip, &port)) {
        return CYXCHAT_ERR_INVALID;
    }

    ctx->servers[ctx->server_count].ip = ip;
    ctx->servers[ctx->server_count].port = port;
    ctx->servers[ctx->server_count].active = 1;
    ctx->server_count++;

    return CYXCHAT_OK;
}

size_t cyxchat_relay_server_count(cyxchat_relay_ctx_t *ctx)
{
    return ctx ? ctx->server_count : 0;
}

/* ============================================================
 * Connection Management
 * ============================================================ */

cyxchat_error_t cyxchat_relay_connect(cyxchat_relay_ctx_t *ctx,
                                       const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check if no relay servers available */
    if (ctx->server_count == 0) {
        return CYXCHAT_ERR_NETWORK;
    }

    /* Check if already connected */
    if (find_connection(ctx, peer_id)) {
        return CYXCHAT_OK;
    }

    /* Allocate new connection */
    cyxchat_relay_conn_internal_t *conn = alloc_connection(ctx);
    if (!conn) {
        return CYXCHAT_ERR_FULL;
    }

    conn->peer_id = *peer_id;
    conn->connected_at = get_time_ms();
    conn->last_activity = conn->connected_at;
    conn->last_keepalive = conn->connected_at;
    conn->server_index = 0;  /* Use first relay server */

    /* Send connect request to relay */
    cyxchat_relay_connect_msg_t msg;
    msg.type = CYXCHAT_RELAY_CONNECT;
    msg.from = ctx->local_id;
    msg.to = *peer_id;

    cyxchat_error_t err = send_to_relay(ctx, 0, (uint8_t*)&msg, sizeof(msg));
    if (err != CYXCHAT_OK) {
        free_connection(ctx, conn);
        return err;
    }

    /* Notify state change */
    if (ctx->on_state) {
        ctx->on_state(ctx, peer_id, 1, ctx->state_user_data);
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_relay_disconnect(cyxchat_relay_ctx_t *ctx,
                                          const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_relay_conn_internal_t *conn = find_connection(ctx, peer_id);
    if (!conn) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Send disconnect to relay */
    cyxchat_relay_connect_msg_t msg;
    msg.type = CYXCHAT_RELAY_DISCONNECT;
    msg.from = ctx->local_id;
    msg.to = *peer_id;

    send_to_relay(ctx, conn->server_index, (uint8_t*)&msg, sizeof(msg));

    free_connection(ctx, conn);
    return CYXCHAT_OK;
}

int cyxchat_relay_is_connected(cyxchat_relay_ctx_t *ctx, const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) return 0;
    return find_connection(ctx, peer_id) != NULL;
}

cyxchat_error_t cyxchat_relay_get_info(cyxchat_relay_ctx_t *ctx,
                                        const cyxwiz_node_id_t *peer_id,
                                        cyxchat_relay_conn_t *info_out)
{
    if (!ctx || !peer_id || !info_out) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_relay_conn_internal_t *conn = find_connection(ctx, peer_id);
    if (!conn) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    info_out->peer_id = conn->peer_id;
    info_out->connected_at = conn->connected_at;
    info_out->last_activity = conn->last_activity;
    info_out->bytes_sent = conn->bytes_sent;
    info_out->bytes_received = conn->bytes_received;
    info_out->active = conn->active;

    return CYXCHAT_OK;
}

/* ============================================================
 * Data Transfer
 * ============================================================ */

cyxchat_error_t cyxchat_relay_send(cyxchat_relay_ctx_t *ctx,
                                    const cyxwiz_node_id_t *peer_id,
                                    const uint8_t *data,
                                    size_t len)
{
    if (!ctx || !peer_id || !data) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_relay_conn_internal_t *conn = find_connection(ctx, peer_id);
    if (!conn) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Build relay data message */
    size_t msg_len = CYXCHAT_RELAY_DATA_HDR_SIZE + len;
    uint8_t *msg_buf = (uint8_t*)malloc(msg_len);
    if (!msg_buf) {
        return CYXCHAT_ERR_MEMORY;
    }

    cyxchat_relay_data_msg_t *msg = (cyxchat_relay_data_msg_t*)msg_buf;
    msg->type = CYXCHAT_RELAY_DATA;
    msg->from = ctx->local_id;
    msg->to = *peer_id;
    msg->data_len = htons((uint16_t)len);
    memcpy(msg->data, data, len);

    cyxchat_error_t err = send_to_relay(ctx, conn->server_index, msg_buf, msg_len);

    if (err == CYXCHAT_OK) {
        conn->bytes_sent += (uint32_t)len;
        conn->last_activity = get_time_ms();
    }

    free(msg_buf);
    return err;
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_relay_set_on_data(cyxchat_relay_ctx_t *ctx,
                                cyxchat_relay_data_callback_t callback,
                                void *user_data)
{
    if (!ctx) return;
    ctx->on_data = callback;
    ctx->data_user_data = user_data;
}

void cyxchat_relay_set_on_state(cyxchat_relay_ctx_t *ctx,
                                 cyxchat_relay_state_callback_t callback,
                                 void *user_data)
{
    if (!ctx) return;
    ctx->on_state = callback;
    ctx->state_user_data = user_data;
}
