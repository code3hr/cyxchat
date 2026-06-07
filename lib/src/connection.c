/**
 * CyxChat Connection Management
 *
 * NAT traversal and peer-to-peer connection management.
 * Wraps CyxWiz transport layer with connection state tracking
 * and automatic relay fallback.
 */

#include "cyxchat/connection.h"
#include "cyxchat/relay.h"
#include "cyxchat/file.h"
#include "cyxchat/server_registry.h"
#include <cyxwiz/memory.h>
#include <cyxwiz/log.h>
#include <cyxwiz/routing.h>
#include <cyxwiz/onion.h>
#include <cyxwiz/dht.h>
#include <cyxwiz/peer.h>
#include <cyxwiz/upnp.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netdb.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <time.h>
#include <errno.h>
#endif

/* External UDP transport UPnP functions (from udp.c) */
#ifdef CYXWIZ_HAS_UPNP
extern cyxwiz_error_t cyxwiz_udp_get_upnp_status(void *driver_data, cyxwiz_upnp_status_t *status);
extern bool cyxwiz_udp_is_upnp_active(void *driver_data);
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
    uint8_t pubkey[32];             /* Peer's X25519 public key */
    int has_pubkey;                 /* 1 if pubkey is valid */
} cyxchat_pending_conn_t;

/* Throttle interval for sending ANNOUNCEs to same peer */
#define CYXCHAT_ANNOUNCE_THROTTLE_MS 10000
/* Retry interval and max for key exchange */
#define CYXCHAT_ANNOUNCE_RETRY_MS    3000  /* Retry every 3s until key exchange completes */
#define CYXCHAT_ANNOUNCE_MAX_RETRIES 10    /* Give up after 30s */

/* Per-peer connection info */
typedef struct {
    cyxwiz_node_id_t peer_id;
    cyxchat_conn_state_t state;
    uint64_t connected_at;
    uint64_t last_activity;
    uint64_t last_keepalive;
    uint64_t last_announce_sent;    /* When we last sent ANNOUNCE to this peer */
    uint64_t last_key_exchange;     /* When we last processed key from this peer */
    uint32_t bytes_sent;
    uint32_t bytes_received;
    int8_t rssi;
    int is_relayed;
    int active;
    uint8_t pubkey[32];             /* Peer's X25519 public key */
    int has_pubkey;                 /* 1 if pubkey is valid */
    uint8_t announce_retries;       /* ANNOUNCE retry count for key exchange */
} cyxchat_peer_conn_t;

/* DHT find callback wrapper */
typedef struct {
    cyxchat_conn_ctx_t *ctx;
    cyxchat_dht_find_callback_t callback;
    void *user_data;
    cyxwiz_node_id_t target;
} cyxchat_dht_find_ctx_t;

/* Connection context */
struct cyxchat_conn_ctx {
    /* CyxWiz components */
    cyxwiz_transport_t *transport;
    cyxwiz_peer_table_t *peer_table;
    cyxwiz_router_t *router;
    cyxwiz_onion_ctx_t *onion;
    cyxwiz_dht_t *dht;
    cyxwiz_discovery_t *discovery;

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

    /* Server registry (multi-server health + failover) */
    cyxchat_server_registry_t *server_registry;

    /* Callbacks */
    cyxchat_conn_state_callback_t on_state_change;
    void *state_change_user_data;
    cyxchat_conn_data_callback_t on_data;
    void *data_user_data;

    /* DHT callbacks */
    cyxchat_dht_node_callback_t on_dht_node;
    void *dht_node_user_data;

    /* Progress callback for real-time connection feedback */
    cyxchat_conn_progress_callback_t on_progress;
    void *progress_user_data;

    /* Presence query callback */
    cyxchat_presence_callback_t on_presence;
    void *presence_user_data;

    /* File context for direct mode routing */
    void *file_ctx;

    /* Timing */
    uint64_t last_stun_time;
    uint64_t last_poll_time;
    uint64_t last_server_discovery;  /* DHT server discovery timer */
};

/* ============================================================
 * Helper Functions
 * ============================================================ */

/* Forward declarations */
static void send_announce_to_peer(cyxchat_conn_ctx_t *ctx,
                                   const cyxwiz_node_id_t *peer_id);
static int is_discovery_message(uint8_t type);
static void fire_progress_event(cyxchat_conn_ctx_t *ctx,
                                const cyxwiz_node_id_t *peer_id,
                                cyxchat_conn_event_t event,
                                uint8_t retry_num,
                                uint8_t retry_max,
                                cyxchat_conn_fail_t fail_reason);

static uint64_t get_time_ms(void)
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

/* Promote an established relay-backed peer to direct P2P once direct traffic
 * is observed. The relay is only torn down after direct traffic is confirmed. */
static void promote_peer_to_direct(cyxchat_conn_ctx_t *ctx,
                                   cyxchat_peer_conn_t *peer,
                                   const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer || !peer_id) return;

    if (peer->is_relayed && ctx->relay && cyxchat_relay_is_connected(ctx->relay, peer_id)) {
        cyxchat_relay_disconnect(ctx->relay, peer_id);
    }

    peer->is_relayed = 0;
    set_peer_state(ctx, peer, CYXCHAT_CONN_CONNECTED);
    fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_CONNECTED_P2P,
                        0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);
}

/* Fire progress event for real-time UI feedback */
static void fire_progress_event(cyxchat_conn_ctx_t *ctx,
                                 const cyxwiz_node_id_t *peer_id,
                                 cyxchat_conn_event_t event,
                                 uint8_t retry_num,
                                 uint8_t retry_max,
                                 cyxchat_conn_fail_t fail_reason)
{
    if (!ctx || !peer_id) {
        CYXWIZ_DEBUG("fire_progress_event: ctx=%p peer=%p - skipping", (void*)ctx, (void*)peer_id);
        return;
    }
    if (!ctx->on_progress) {
        CYXWIZ_DEBUG("fire_progress_event: event=%d but no callback registered", event);
        return;
    }
    CYXWIZ_INFO("PROGRESS: event=%d retry=%d/%d fail=%d", event, retry_num, retry_max, fail_reason);

    /* Input validation: clamp event to valid range */
    if (event > CYXCHAT_CONN_EVENT_FAILED) {
        event = CYXCHAT_CONN_EVENT_FAILED;
    }

    /* Input validation: clamp fail_reason to valid range */
    if (fail_reason > CYXCHAT_CONN_FAIL_RELAY_UNAVAILABLE) {
        fail_reason = CYXCHAT_CONN_FAIL_NONE;
    }

    /* Input validation: ensure retry_num doesn't exceed retry_max */
    if (retry_max > 0 && retry_num > retry_max) {
        retry_num = retry_max;
    }

    ctx->on_progress(peer_id, event, retry_num, retry_max, fail_reason,
                     ctx->progress_user_data);
}

/* Relay data callback - forwards relay data to application */
static void on_relay_data(cyxchat_relay_ctx_t *relay_ctx,
                          const cyxwiz_node_id_t *from,
                          const uint8_t *data, size_t len,
                          void *user_data)
{
    (void)relay_ctx;
    cyxchat_conn_ctx_t *ctx = (cyxchat_conn_ctx_t*)user_data;

    /* Update peer connection state */
    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, from);
    int was_connecting = peer && peer->state == CYXCHAT_CONN_CONNECTING;
    if (!peer) {
        peer = alloc_peer_conn(ctx);
        if (peer) {
            peer->peer_id = *from;
            peer->state = CYXCHAT_CONN_DISCONNECTED;
        }
    }
    if (peer) {
        peer->last_activity = get_time_ms();
        peer->bytes_received += (uint32_t)len;

        /* Relay traffic is enough to revive stale disconnected relay state. */
        if (!peer->is_relayed ||
            (peer->state != CYXCHAT_CONN_RELAYING &&
             peer->state != CYXCHAT_CONN_CONNECTED)) {
            peer->is_relayed = 1;
            set_peer_state(ctx, peer, CYXCHAT_CONN_RELAYING);
        }

    }

    /* Complete pending connection if relay traffic arrived while connecting. */
    if (peer && was_connecting) {
        cyxchat_pending_conn_t *pending = find_pending(ctx, from);
        if (pending && pending->callback) {
            pending->callback(ctx, from, CYXCHAT_CONN_RELAYING, CYXCHAT_OK,
                             pending->user_data);
        }
        if (pending) {
            free_pending(ctx, pending);
        }
    }

    /* Route discovery messages through discovery handler for key exchange */
    if (len > 0 && ctx->discovery && is_discovery_message(data[0])) {
        /* CRITICAL: Check if we need to respond BEFORE processing the message.
         * The discovery handler triggers on_peer_key_received which sets
         * has_pubkey=1. We must decide whether to respond first. */
        int should_respond_relay = 0;
        if (data[0] == 0x01 /* ANNOUNCE */ && ctx->onion) {
            char hex_id[17];
            for (int i = 0; i < 8; i++) {
                snprintf(hex_id + i*2, 3, "%02x", from->bytes[i]);
            }
            cyxchat_peer_conn_t *conn = find_peer_conn(ctx, from);
            uint64_t now = get_time_ms();
            int need_key = !conn || !conn->has_pubkey;
            int throttle_ok = !conn || (now - conn->last_announce_sent >= CYXCHAT_ANNOUNCE_THROTTLE_MS);
            should_respond_relay = need_key && throttle_ok;
            CYXWIZ_INFO("RELAY ANNOUNCE from %.16s: conn=%p has_pk=%d need=%d throttle=%d respond=%d",
                        hex_id, (void*)conn, conn ? conn->has_pubkey : -1, need_key, throttle_ok, should_respond_relay);
            if (should_respond_relay && conn) conn->last_announce_sent = now;
        }

        cyxwiz_discovery_handle_message(ctx->discovery, from, data, len);

        /* Send ANNOUNCE back via relay so the peer gets our pubkey too. */
        if (should_respond_relay) {
            CYXWIZ_INFO("Sending ANNOUNCE response via relay for bidirectional key exchange");
            /* Ensure relay connection exists before sending response */
            if (ctx->relay && !cyxchat_relay_is_connected(ctx->relay, from)) {
                CYXWIZ_INFO("Creating reverse relay connection to peer for ANNOUNCE response");
                cyxchat_relay_connect(ctx->relay, from);  /* server_index=0 */
            }
            send_announce_to_peer(ctx, from);
        }
    }

    /* Relay-delivered onion payloads must enter the same decrypt/dispatch path
     * as direct transport onion payloads. Otherwise relay traffic reaches the
     * socket but never becomes a chat message in Dart. */
    if (len > 0 && ctx->onion && data[0] == CYXWIZ_MSG_ONION_DATA) {
        cyxwiz_error_t err = cyxwiz_onion_handle_message(ctx->onion, from, data, len);
        if (err != CYXWIZ_OK && err != CYXWIZ_ERR_RATE_LIMITED) {
            CYXWIZ_DEBUG("Relayed onion message handling failed: %d", err);
        }
        return;
    }

    /* Forward to application callback */
    if (ctx->on_data) {
        ctx->on_data(ctx, from, data, len, ctx->data_user_data);
    }
}

/* Router data callback - forwards direct P2P data to application
 * This handles data sent via cyxwiz_router_send() (direct mode) */
static void on_router_data(const cyxwiz_node_id_t *from,
                           const uint8_t *data, size_t len,
                           void *user_data)
{
    cyxchat_conn_ctx_t *ctx = (cyxchat_conn_ctx_t*)user_data;

    if (!ctx || len == 0) return;

    /* Update peer connection state */
    cyxchat_peer_conn_t *peer = find_peer_conn(ctx, from);
    int was_relayed = peer && peer->is_relayed;
    int was_connecting = peer && peer->state == CYXCHAT_CONN_CONNECTING;
    if (peer) {
        peer->last_activity = get_time_ms();
        peer->bytes_received += (uint32_t)len;

        if (was_relayed) {
            promote_peer_to_direct(ctx, peer, from);
        } else if (peer->state == CYXCHAT_CONN_CONNECTING) {
            set_peer_state(ctx, peer, CYXCHAT_CONN_CONNECTED);
        }
    }

    if (peer && was_connecting) {
        cyxchat_pending_conn_t *pending = find_pending(ctx, from);
        if (pending && pending->callback) {
            pending->callback(ctx, from, CYXCHAT_CONN_CONNECTED, CYXCHAT_OK,
                             pending->user_data);
        }
        if (pending) {
            free_pending(ctx, pending);
        }
    }

    /* Forward to application callback (same as relay/onion data) */
    if (ctx->on_data) {
        CYXWIZ_INFO("Router received direct data: type=0x%02x, len=%zu", data[0], len);
        ctx->on_data(ctx, from, data, len, ctx->data_user_data);
    }
}

/* Discovery message types (0x01-0x05) */
#define CYXCHAT_DISC_ANNOUNCE     0x01
#define CYXCHAT_DISC_ANNOUNCE_ACK 0x02
#define CYXCHAT_DISC_PING         0x03
#define CYXCHAT_DISC_PONG         0x04
#define CYXCHAT_DISC_GOODBYE      0x05

/* Check if message is a discovery protocol message */
static int is_discovery_message(uint8_t type)
{
    return type >= CYXCHAT_DISC_ANNOUNCE && type <= CYXCHAT_DISC_GOODBYE;
}

/* Transport callbacks */
static void on_transport_recv(cyxwiz_transport_t *transport,
                              const cyxwiz_node_id_t *from,
                              const uint8_t *data, size_t len,
                              void *user_data)
{
    (void)transport;  /* Unused - we use the transport from context */
    cyxchat_conn_ctx_t *ctx = (cyxchat_conn_ctx_t*)user_data;

    /* Check for server registry messages (health pong, challenge response) */
    if (len > 0 && ctx->server_registry && cyxchat_server_registry_is_message(data[0])) {
        cyxchat_server_registry_handle_message(ctx->server_registry, data, len);
        return;
    }

/* Handle presence query response from server */    if (len >= 34 && data[0] == CYXCHAT_PRESENCE_RESPONSE) {        if (ctx->on_presence) {            const cyxwiz_node_id_t *peer_id = (const cyxwiz_node_id_t *)(data + 1);            uint8_t online = data[33];            ctx->on_presence(peer_id, online, ctx->presence_user_data);        }        return;    }
    /* Check for relay messages and handle them */
    if (len > 0 && ctx->relay && cyxchat_relay_is_relay_message(data[0])) {
        cyxchat_relay_handle_message(ctx->relay, data, len);
        return;  /* Relay handler forwards data via callback */
    }

    /* Route discovery messages to discovery handler for key exchange */
    if (len > 0 && ctx->discovery && is_discovery_message(data[0])) {
        /* Debug: log announce message details (pubkey at offset 37) */
        if (data[0] == CYXCHAT_DISC_ANNOUNCE && len >= 69) {
            const uint8_t *pk = data + 37;  /* pubkey offset */
            int has_pk = 0;
            for (int i = 0; i < 32; i++) {
                if (pk[i] != 0) { has_pk = 1; break; }
            }
            (void)has_pk;  /* Used for debugging */
        }

        /* CRITICAL: Check if we need to respond BEFORE processing the message.
         * The discovery handler triggers on_peer_key_received which sets
         * has_pubkey=1. We must decide whether to respond first. */
        int should_respond = 0;
        if (data[0] == CYXCHAT_DISC_ANNOUNCE && ctx->onion) {
            char hex_id[17];
            for (int i = 0; i < 8; i++) {
                snprintf(hex_id + i*2, 3, "%02x", from->bytes[i]);
            }
            cyxchat_peer_conn_t *conn = find_peer_conn(ctx, from);
            uint64_t now = get_time_ms();
            int need_key = !conn || !conn->has_pubkey;
            int throttle_ok = !conn || (now - conn->last_announce_sent >= CYXCHAT_ANNOUNCE_THROTTLE_MS);
            should_respond = need_key && throttle_ok;
            CYXWIZ_INFO("TRANSPORT ANNOUNCE from %.16s: conn=%p has_pk=%d need=%d throttle=%d respond=%d",
                        hex_id, (void*)conn, conn ? conn->has_pubkey : -1, need_key, throttle_ok, should_respond);
            /* Update timestamp immediately to prevent rapid re-sends */
            if (should_respond && conn) conn->last_announce_sent = now;
        }

        cyxwiz_discovery_handle_message(ctx->discovery, from, data, len);

        /* Send ANNOUNCE back AFTER processing, using pre-computed decision.
         * This completes bidirectional key exchange. */
        if (should_respond) {
            CYXWIZ_INFO("Sending ANNOUNCE response for bidirectional key exchange");
            /* Ensure relay connection exists in case direct send fails */
            if (ctx->relay && !cyxchat_relay_is_connected(ctx->relay, from)) {
                CYXWIZ_INFO("Creating relay connection to peer for ANNOUNCE response");
                cyxchat_relay_connect(ctx->relay, from);  /* server_index=0 */
            }
            send_announce_to_peer(ctx, from);
        }
        /* Don't return - also process below for connection state updates */
    }

    /* Route onion data messages to onion handler */
    if (len > 0 && ctx->onion && data[0] == CYXWIZ_MSG_ONION_DATA) {
        cyxwiz_error_t err = cyxwiz_onion_handle_message(ctx->onion, from, data, len);
        if (err != CYXWIZ_OK && err != CYXWIZ_ERR_RATE_LIMITED) {
            CYXWIZ_DEBUG("Onion message handling failed: %d", err);
        }
        return;  /* Onion messages are fully handled by onion layer */
    }

    /* Route direct file messages to file handler (bypasses onion) */
    if (len > 0 && ctx->file_ctx) {
        uint8_t msg_type = data[0];
        /* File messages: 0x14-0x19 (v1) and 0x40-0x45 (v2) */
        if ((msg_type >= 0x14 && msg_type <= 0x19) ||
            (msg_type >= 0x40 && msg_type <= 0x45)) {
            CYXWIZ_INFO("Routing direct file message (type=0x%02x) to file module", msg_type);
            cyxchat_file_handle_message(
                (cyxchat_file_ctx_t *)ctx->file_ctx,
                from,
                msg_type,
                data + 1,
                len - 1
            );
            return;  /* File messages fully handled */
        }
    }

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

    /* Forward to application callback (skip discovery messages) */
    if (ctx->on_data && !(len > 0 && is_discovery_message(data[0]))) {
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

            /* Fire progress event: peer found */
            fire_progress_event(ctx, &peer->id, CYXCHAT_CONN_EVENT_PEER_FOUND,
                                0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);
        }
    }

    /* Update or create peer connection record */
    cyxchat_peer_conn_t *conn = find_peer_conn(ctx, &peer->id);
    int is_new_peer = (conn == NULL);
    uint64_t now = get_time_ms();

    if (!conn) {
        conn = alloc_peer_conn(ctx);
        if (conn) {
            conn->peer_id = peer->id;
            conn->state = CYXCHAT_CONN_DISCONNECTED;
            conn->rssi = peer->rssi;
            conn->last_announce_sent = 0;  /* Never sent */
        }
    } else {
        conn->rssi = peer->rssi;
        conn->last_activity = now;
    }

    /* Auto-create pending connection for bootstrap-discovered peers so that
     * relay fallback triggers if hole punch fails (e.g. hairpin NAT) */
    if (conn && !pending && conn->state == CYXCHAT_CONN_DISCONNECTED) {
        pending = alloc_pending(ctx);
        if (pending) {
            pending->peer_id = peer->id;
            pending->callback = NULL;
            pending->user_data = NULL;
            pending->start_time = now;
            pending->punch_attempts = 0;
            set_peer_state(ctx, conn, CYXCHAT_CONN_CONNECTING);
            CYXWIZ_INFO("Auto-created pending connection for relay fallback");
        }
    }

    /* Send discovery ANNOUNCE to initiate key exchange (with throttling) */
    if (conn && ctx->onion) {
        uint64_t elapsed = now - conn->last_announce_sent;
        /* Send if: new peer OR throttle interval has passed */
        if (is_new_peer || elapsed >= CYXCHAT_ANNOUNCE_THROTTLE_MS) {
            CYXWIZ_INFO("Initiating key exchange with new peer (is_new=%d)", is_new_peer);
            send_announce_to_peer(ctx, &peer->id);
            conn->last_announce_sent = now;
        }
    } else {
        CYXWIZ_WARN("Skip announce: conn=%p, onion=%p", (void*)conn, (void*)(ctx ? ctx->onion : NULL));
    }
}

/* DHT node discovery callback - adds new nodes to peer table */
static void on_dht_node_discovered(const cyxwiz_node_id_t *node_id, void *user_data)
{
    cyxchat_conn_ctx_t *ctx = (cyxchat_conn_ctx_t*)user_data;
    if (!ctx || !node_id) return;

    /* Add to peer table if not already there */
    const cyxwiz_peer_t *peer = cyxwiz_peer_table_find(ctx->peer_table, node_id);
    if (!peer) {
        cyxwiz_peer_table_add(ctx->peer_table, node_id, CYXWIZ_TRANSPORT_UDP, 0);
    }

    /* Update or create peer connection record */
    cyxchat_peer_conn_t *conn = find_peer_conn(ctx, node_id);
    if (!conn) {
        conn = alloc_peer_conn(ctx);
        if (conn) {
            conn->peer_id = *node_id;
            conn->state = CYXCHAT_CONN_DISCONNECTED;
            conn->rssi = 0;
        }
    }

    /* Notify application */
    if (ctx->on_dht_node) {
        ctx->on_dht_node(ctx, node_id, ctx->dht_node_user_data);
    }
}

/* Key exchange callback - called when peer's X25519 public key is received */
static void on_peer_key_received(const cyxwiz_node_id_t *peer_id,
                                  const uint8_t *peer_pubkey,
                                  void *user_data)
{
    cyxchat_conn_ctx_t *ctx = (cyxchat_conn_ctx_t*)user_data;
    if (!ctx || !ctx->onion || !peer_id || !peer_pubkey) {
        return;
    }

    /* Find or create peer connection for throttle tracking */
    cyxchat_peer_conn_t *conn = find_peer_conn(ctx, peer_id);
    uint64_t now = get_time_ms();

    if (!conn) {
        /* Create peer connection for new peer */
        conn = alloc_peer_conn(ctx);
        if (conn) {
            conn->peer_id = *peer_id;
            conn->state = CYXCHAT_CONN_DISCONNECTED;
            conn->last_key_exchange = 0;
        }
    }

    /* Skip if key exchange already completed - don't rotate keys */
    if (conn && conn->has_pubkey) {
        return;
    }

    /* Throttle key exchange processing */
    if (conn && conn->last_key_exchange > 0) {
        uint64_t elapsed = now - conn->last_key_exchange;
        if (elapsed < CYXCHAT_ANNOUNCE_THROTTLE_MS) {
            return;  /* Already processed recently */
        }
    }

    /* Update key exchange timestamp */
    if (conn) {
        conn->last_key_exchange = now;
    }

    /* Add peer's public key to onion context for shared secret computation */
    cyxwiz_error_t err = cyxwiz_onion_add_peer_key(ctx->onion, peer_id, peer_pubkey);
    if (err == CYXWIZ_OK) {
        char hex_id[17];
        for (int i = 0; i < 8; i++) {
            snprintf(hex_id + i*2, 3, "%02x", peer_id->bytes[i]);
        }
        CYXWIZ_INFO("Key exchange complete with peer %.16s...", hex_id);

        /* Fire progress event: key received */
        fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_KEY_RECEIVED,
                            0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);

        /* Store pubkey in peer connection for later retrieval */
        if (conn) {
            memcpy(conn->pubkey, peer_pubkey, 32);
            conn->has_pubkey = 1;
            conn->last_activity = now;
            conn->announce_retries = 0;
        }

        /* Set peer to connected/relaying state after successful key exchange.
         * Preserve relay state if already set. */
        if (conn && conn->state != CYXCHAT_CONN_CONNECTED &&
            conn->state != CYXCHAT_CONN_RELAYING) {
            /* If relay is active for this peer, mark as relaying */
            if (conn->is_relayed) {
                set_peer_state(ctx, conn, CYXCHAT_CONN_RELAYING);
                /* Fire progress event: connected via relay */
                fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_CONNECTED_RELAY,
                                    0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);
            } else {
                set_peer_state(ctx, conn, CYXCHAT_CONN_CONNECTED);
                /* Fire progress event: connected P2P */
                fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_CONNECTED_P2P,
                                    0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);
            }
        }
        if (ctx->peer_table) {
            cyxwiz_peer_table_set_state(ctx->peer_table, peer_id, CYXWIZ_PEER_STATE_CONNECTED);
            cyxwiz_peer_table_record_success(ctx->peer_table, peer_id);
        }
    }
}

/* Minimal UDP state view for socket access (punch function) */
typedef struct {
    uint8_t initialized;  /* bool - 1 byte */
    uint8_t _pad1[7];     /* padding to align socket */
#ifdef _WIN32
    SOCKET socket_fd;
#else
    int socket_fd;
#endif
    /* Rest not needed */
} cyxchat_udp_state_view_t;

/* Discovery announce message - matches cyxwiz_disc_announce_t */
#ifdef _MSC_VER
#pragma pack(push, 1)
#endif
typedef struct {
    uint8_t type;           /* 0x01 = ANNOUNCE */
    uint8_t version;        /* 1 */
    cyxwiz_node_id_t node_id;
    uint8_t capabilities;
    uint16_t port;
    uint8_t pubkey[32];
}
#ifdef __GNUC__
__attribute__((packed))
#endif
cyxchat_announce_t;
#ifdef _MSC_VER
#pragma pack(pop)
#endif

/* Send discovery ANNOUNCE to a specific peer to initiate key exchange */
static void send_announce_to_peer(cyxchat_conn_ctx_t *ctx,
                                   const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !ctx->transport || !ctx->onion || !peer_id) {
        CYXWIZ_WARN("send_announce_to_peer: null check failed (ctx=%p, transport=%p, onion=%p, peer_id=%p)",
                    (void*)ctx, ctx ? (void*)ctx->transport : NULL,
                    ctx ? (void*)ctx->onion : NULL, (void*)peer_id);
        return;
    }

    /* Get our X25519 public key */
    uint8_t our_pubkey[32];
    if (cyxwiz_onion_get_pubkey(ctx->onion, our_pubkey) != CYXWIZ_OK) {
        CYXWIZ_WARN("Cannot send announce - failed to get pubkey");
        return;
    }

    /* Build ANNOUNCE message with our pubkey */
    cyxchat_announce_t announce;
    memset(&announce, 0, sizeof(announce));
    announce.type = 0x01;  /* CYXWIZ_DISC_ANNOUNCE */
    announce.version = 1;
    memcpy(&announce.node_id, &ctx->local_id, sizeof(cyxwiz_node_id_t));
    announce.capabilities = 0;
    announce.port = 0;  /* Will be filled by transport */
    memcpy(announce.pubkey, our_pubkey, 32);

    /* Try direct transport send first */
    cyxwiz_error_t err = ctx->transport->ops->send(ctx->transport, peer_id,
                                                    (uint8_t*)&announce, sizeof(announce));

    char hex_id[17];
    for (int i = 0; i < 8; i++) {
        snprintf(hex_id + i*2, 3, "%02x", peer_id->bytes[i]);
    }

    if (err == CYXWIZ_OK) {
        CYXWIZ_INFO("Sent key exchange announce to peer %.16s... (direct)", hex_id);
        /* Fire progress event: announce sent */
        cyxchat_peer_conn_t *conn = find_peer_conn(ctx, peer_id);
        uint8_t retry = conn ? conn->announce_retries : 0;
        if (retry == 0) {
            fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_ANNOUNCE_SENT,
                                0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);
        }
    } else if (ctx->relay) {
        /* Direct send failed (peer address unknown) - try via relay */
        cyxchat_error_t relay_err = cyxchat_relay_send(ctx->relay, peer_id,
                                                        (uint8_t*)&announce, sizeof(announce));
        if (relay_err == CYXCHAT_OK) {
            CYXWIZ_INFO("Sent key exchange announce to peer %.16s... (via relay)", hex_id);
            /* Fire progress event: announce sent */
            cyxchat_peer_conn_t *conn = find_peer_conn(ctx, peer_id);
            uint8_t retry = conn ? conn->announce_retries : 0;
            if (retry == 0) {
                fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_ANNOUNCE_SENT,
                                    0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);
            }
        } else {
            CYXWIZ_INFO("Failed to send announce to %.16s... (direct err=%d, relay err=%d)",
                        hex_id, err, relay_err);
        }
    } else {
        CYXWIZ_INFO("Failed to send announce to %.16s... (err=%d, no relay)", hex_id, err);
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
        CYXWIZ_INFO("Setting bootstrap server: %s", bootstrap);
#ifdef _WIN32
        _putenv_s("CYXWIZ_BOOTSTRAP", bootstrap);
#else
        setenv("CYXWIZ_BOOTSTRAP", bootstrap, 1);
#endif
    } else {
        CYXWIZ_WARN("No bootstrap server provided (bootstrap=%s)", bootstrap ? bootstrap : "NULL");
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

    /* Note: cyxwiz_transport_create already calls init internally */

    /* Create peer table */
    err = cyxwiz_peer_table_create(&c->peer_table);
    if (err != CYXWIZ_OK) {
        c->transport->ops->shutdown(c->transport);
        cyxwiz_transport_destroy(c->transport);
        free(c);
        return CYXCHAT_ERR_MEMORY;
    }

    /* Create router */
    err = cyxwiz_router_create(&c->router, c->peer_table, c->transport, local_id);
    if (err != CYXWIZ_OK) {
        cyxwiz_peer_table_destroy(c->peer_table);
        c->transport->ops->shutdown(c->transport);
        cyxwiz_transport_destroy(c->transport);
        free(c);
        return CYXCHAT_ERR_MEMORY;
    }

    /* Start router for route discovery and message handling */
    err = cyxwiz_router_start(c->router);
    if (err != CYXWIZ_OK) {
        cyxwiz_router_destroy(c->router);
        cyxwiz_peer_table_destroy(c->peer_table);
        c->transport->ops->shutdown(c->transport);
        cyxwiz_transport_destroy(c->transport);
        free(c);
        return CYXCHAT_ERR_NETWORK;
    }

    /* Set router callback for direct P2P data (bypasses onion) */
    cyxwiz_router_set_callback(c->router, on_router_data, c);

    /* Create onion routing context */
    err = cyxwiz_onion_create(&c->onion, c->router, local_id);
    if (err != CYXWIZ_OK) {
        cyxwiz_router_destroy(c->router);
        cyxwiz_peer_table_destroy(c->peer_table);
        c->transport->ops->shutdown(c->transport);
        cyxwiz_transport_destroy(c->transport);
        free(c);
        return CYXCHAT_ERR_MEMORY;
    }

    /* Create discovery context for peer discovery and key exchange */
    CYXWIZ_INFO("Creating discovery context...");
    err = cyxwiz_discovery_create(&c->discovery, c->peer_table, c->transport, local_id);
    if (err != CYXWIZ_OK) {
        /* Discovery is critical for key exchange - fail if we can't create it */
        CYXWIZ_WARN("Failed to create discovery context: %d", err);
        c->discovery = NULL;
    } else {
        CYXWIZ_INFO("Discovery context created, getting onion pubkey...");
        /* Get onion's X25519 public key for announcements */
        uint8_t onion_pubkey[32];
        err = cyxwiz_onion_get_pubkey(c->onion, onion_pubkey);
        if (err == CYXWIZ_OK) {
            /* Verify pubkey is non-zero */
            int has_key = 0;
            for (int i = 0; i < 32; i++) {
                if (onion_pubkey[i] != 0) { has_key = 1; break; }
            }
            CYXWIZ_INFO("Got onion pubkey (has_key=%d, first bytes: %02x%02x%02x%02x)",
                       has_key, onion_pubkey[0], onion_pubkey[1], onion_pubkey[2], onion_pubkey[3]);

            /* Set public key for discovery announcements */
            cyxwiz_discovery_set_pubkey(c->discovery, onion_pubkey);

            /* Set callback for when peer public keys arrive */
            CYXWIZ_INFO("Setting key exchange callback on discovery context");
            cyxwiz_discovery_set_key_callback(c->discovery, on_peer_key_received, c);

            /* Start discovery */
            err = cyxwiz_discovery_start(c->discovery);
            if (err == CYXWIZ_OK) {
                CYXWIZ_INFO("Discovery started with key exchange enabled");
            } else {
                CYXWIZ_WARN("Failed to start discovery: %d", err);
            }
        } else {
            CYXWIZ_WARN("Failed to get onion public key for discovery: %d", err);
        }
    }

    /* Create DHT for decentralized peer discovery */
    err = cyxwiz_dht_create(&c->dht, c->router, local_id);
    if (err != CYXWIZ_OK) {
        /* DHT is optional - continue without it */
        c->dht = NULL;
    } else {
        /* Set DHT node discovery callback */
        cyxwiz_dht_set_node_callback(c->dht, on_dht_node_discovered, c);
    }

    /* Create relay context */
    cyxchat_relay_create(&c->relay, c->transport, local_id);

    /* Set relay callbacks */
    if (c->relay) {
        cyxchat_relay_set_on_data(c->relay, on_relay_data, c);
    }

    /* Create server registry for multi-server health tracking */
    {
    cyxchat_error_t reg_err = cyxchat_server_registry_create(&c->server_registry, c->transport, local_id);
    if (reg_err == CYXCHAT_OK) {
        /* Load seed servers */
        size_t seeds = cyxchat_server_registry_load_seeds(c->server_registry);
        CYXWIZ_INFO("Server registry created, loaded %zu seed servers", seeds);

        /* Also add the user-provided bootstrap server */
        if (bootstrap && strlen(bootstrap) > 0) {
            cyxchat_server_registry_add(c->server_registry, bootstrap, NULL);
        }
    } else {
        CYXWIZ_WARN("Failed to create server registry: %d", (int)reg_err);
        c->server_registry = NULL;
    }
    }

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

    /* Stop and destroy discovery */
    if (ctx->discovery) {
        cyxwiz_discovery_stop(ctx->discovery);
        cyxwiz_discovery_destroy(ctx->discovery);
    }

    /* Destroy DHT */
    if (ctx->dht) {
        cyxwiz_dht_destroy(ctx->dht);
    }

    /* Destroy onion context */
    if (ctx->onion) {
        cyxwiz_onion_destroy(ctx->onion);
    }

    /* Stop and destroy router */
    if (ctx->router) {
        cyxwiz_router_stop(ctx->router);
        cyxwiz_router_destroy(ctx->router);
    }

    /* Destroy server registry */
    if (ctx->server_registry) {
        cyxchat_server_registry_destroy(ctx->server_registry);
    }

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

    /* NOTE: Transport is polled via discovery_poll below - don't poll twice
     * as it causes duplicate packet processing and logging */

    /* Poll relay */
    if (ctx->relay) {
        events += cyxchat_relay_poll(ctx->relay, now_ms);
    }

    /* Poll router */
    if (ctx->router) {
        cyxwiz_router_poll(ctx->router, now_ms);
    }

    /* Poll onion */
    if (ctx->onion) {
        cyxwiz_onion_poll(ctx->onion, now_ms);
    }

    /* Poll DHT */
    if (ctx->dht) {
        cyxwiz_dht_poll(ctx->dht, now_ms);
    }

    /* Poll server registry (health pings, timeout checks) */
    if (ctx->server_registry) {
        events += cyxchat_server_registry_poll(ctx->server_registry, now_ms);
    }

    /* DHT server discovery (every 10 minutes) */
    #define CYXCHAT_SERVER_DISCOVERY_INTERVAL_MS 600000
    if (ctx->dht && ctx->server_registry &&
        (now_ms - ctx->last_server_discovery) >= CYXCHAT_SERVER_DISCOVERY_INTERVAL_MS) {
        ctx->last_server_discovery = now_ms;
        /* TODO: When DHT store/find_value API is available, lookup well-known
         * key SHA256("cyxchat-servers-v1") to discover server announcements.
         * For now, servers are discovered via seed list + manual addition. */
        CYXWIZ_DEBUG("Server discovery tick (DHT store API pending)");
    }

    /* Poll discovery for announcements and key exchange */
    if (ctx->discovery) {
        cyxwiz_discovery_poll(ctx->discovery, now_ms);
    }

    /* Update NAT info from transport */
    if (!ctx->stun_complete) {
        ctx->nat_type = cyxwiz_transport_get_nat_type(ctx->transport);
        if (ctx->nat_type != CYXWIZ_NAT_UNKNOWN) {
            ctx->stun_complete = 1;
        }
    }

    /* Update bootstrap connection status from transport every poll so the UI
     * reflects loss and recovery instead of keeping the first successful ACK. */
    ctx->bootstrap_connected = cyxwiz_transport_is_bootstrap_connected(ctx->transport) ? 1 : 0;

    /* Check pending connections for timeout */
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        cyxchat_pending_conn_t *pending = &ctx->pending[i];
        if (!pending->active) continue;

        uint64_t elapsed = now_ms - pending->start_time;

        if (elapsed >= CYXCHAT_HOLE_PUNCH_TIMEOUT_MS) {
            /* Hole punch timed out, try relay */
            cyxchat_peer_conn_t *peer = find_peer_conn(ctx, &pending->peer_id);
            if (peer) {
                /* Fire progress event: relay fallback */
                fire_progress_event(ctx, &pending->peer_id, CYXCHAT_CONN_EVENT_RELAY_FALLBACK,
                                    0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);

                /* Switch to relay */
                cyxchat_error_t relay_err = cyxchat_relay_connect(
                    ctx->relay, &pending->peer_id
                );

                if (relay_err == CYXCHAT_OK) {
                    peer->last_activity = now_ms;
                    set_peer_state(ctx, peer, CYXCHAT_CONN_RELAYING);
                    peer->is_relayed = 1;

                    /* Send announce via relay to complete key exchange */
                    if (ctx->onion) {
                        send_announce_to_peer(ctx, &pending->peer_id);
                        peer->last_announce_sent = get_time_ms();
                    }

                    if (pending->callback) {
                        pending->callback(ctx, &pending->peer_id, CYXCHAT_CONN_RELAYING,
                                         CYXCHAT_OK, pending->user_data);
                    }
                } else {
                    set_peer_state(ctx, peer, CYXCHAT_CONN_DISCONNECTED);

                    /* Fire progress event: connection failed */
                    fire_progress_event(ctx, &pending->peer_id, CYXCHAT_CONN_EVENT_FAILED,
                                        0, CYXCHAT_ANNOUNCE_MAX_RETRIES,
                                        CYXCHAT_CONN_FAIL_RELAY_UNAVAILABLE);

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

    /* Retry ANNOUNCE for peers that are connecting/relaying but haven't
     * completed key exchange yet (no pubkey). This is critical for mobile
     * networks where UDP packets are frequently dropped by carrier NAT. */
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        cyxchat_peer_conn_t *peer = &ctx->peers[i];
        if (!peer->active) continue;
        if (peer->has_pubkey) continue;  /* Key exchange already done */
        if (peer->state != CYXCHAT_CONN_CONNECTING &&
            peer->state != CYXCHAT_CONN_RELAYING &&
            peer->state != CYXCHAT_CONN_CONNECTED) continue;

        uint64_t since_announce = now_ms - peer->last_announce_sent;
        if (since_announce >= CYXCHAT_ANNOUNCE_RETRY_MS) {
            peer->announce_retries++;
            if (peer->announce_retries <= CYXCHAT_ANNOUNCE_MAX_RETRIES) {
                CYXWIZ_INFO("Retrying key exchange ANNOUNCE for peer (attempt %d/%d)",
                           peer->announce_retries, CYXCHAT_ANNOUNCE_MAX_RETRIES);
                /* Fire progress event: announce retry */
                fire_progress_event(ctx, &peer->peer_id, CYXCHAT_CONN_EVENT_ANNOUNCE_RETRY,
                                    peer->announce_retries, CYXCHAT_ANNOUNCE_MAX_RETRIES,
                                    CYXCHAT_CONN_FAIL_NONE);
                send_announce_to_peer(ctx, &peer->peer_id);
                peer->last_announce_sent = now_ms;
            } else {
                /* Fire progress event: key exchange failed */
                fire_progress_event(ctx, &peer->peer_id, CYXCHAT_CONN_EVENT_FAILED,
                                    peer->announce_retries, CYXCHAT_ANNOUNCE_MAX_RETRIES,
                                    CYXCHAT_CONN_FAIL_KEY_TIMEOUT);
                set_peer_state(ctx, peer, CYXCHAT_CONN_DISCONNECTED);
                peer->is_relayed = 0;
                peer->last_announce_sent = now_ms;
            }
        }
    }

    /* Check for peer timeouts */
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        cyxchat_peer_conn_t *peer = &ctx->peers[i];
        if (!peer->active) continue;

        if (peer->state == CYXCHAT_CONN_CONNECTED || peer->state == CYXCHAT_CONN_RELAYING) {
            uint64_t elapsed = now_ms - peer->last_activity;

            if (elapsed >= CYXCHAT_CONNECTION_TIMEOUT_MS) {
                /* Fire progress event: disconnected */
                fire_progress_event(ctx, &peer->peer_id, CYXCHAT_CONN_EVENT_DISCONNECTED,
                                    0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);
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
    peer->last_activity = pending->start_time;
    set_peer_state(ctx, peer, CYXCHAT_CONN_CONNECTING);

    /* Fire progress event: lookup started */
    fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_LOOKUP_STARTED,
                        0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);

    /* Start relay connection immediately (parallel with hole punch) so
     * the announce can be delivered even if peer address is unknown */
    if (ctx->relay) {
        cyxchat_relay_connect(ctx->relay, peer_id);
    }

    /* Fire progress event: hole punch start */
    fire_progress_event(ctx, peer_id, CYXCHAT_CONN_EVENT_HOLE_PUNCH_START,
                        0, CYXCHAT_ANNOUNCE_MAX_RETRIES, CYXCHAT_CONN_FAIL_NONE);

    /* Send announce immediately to initiate key exchange */
    if (ctx->onion) {
        send_announce_to_peer(ctx, peer_id);
        peer->last_announce_sent = get_time_ms();
    }

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

    /* Require a completed key exchange before application data is sent. */
    if (!peer->has_pubkey) {
        return CYXCHAT_ERR_NO_KEY;
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

    /* DHT status */
    status_out->dht_enabled = (ctx->dht != NULL);
    status_out->dht_nodes = 0;
    status_out->dht_active_buckets = 0;

    if (ctx->dht) {
        cyxwiz_dht_stats_t stats;
        cyxwiz_dht_get_stats(ctx->dht, &stats);
        status_out->dht_nodes = stats.total_nodes;
        status_out->dht_active_buckets = stats.active_buckets;
    }

    /* UPnP/NAT-PMP status */
    status_out->upnp_available = 0;
    status_out->upnp_mapping_active = 0;
    status_out->upnp_external_port = 0;
    status_out->upnp_lease_remaining_sec = 0;

#ifdef CYXWIZ_HAS_UPNP
    if (ctx->transport && ctx->transport->driver_data) {
        cyxwiz_upnp_status_t upnp_status;
        if (cyxwiz_udp_get_upnp_status(ctx->transport->driver_data, &upnp_status) == CYXWIZ_OK) {
            status_out->upnp_available = upnp_status.discovered ? 1 : 0;
            status_out->upnp_mapping_active = upnp_status.mapping_active ? 1 : 0;
            status_out->upnp_external_port = upnp_status.external_port;
            if (upnp_status.mapping_active && upnp_status.lease_expiry_ms > 0) {
                uint64_t now_ms = 0;
#ifdef _WIN32
                now_ms = GetTickCount64();
#else
                struct timeval tv;
                gettimeofday(&tv, NULL);
                now_ms = (uint64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
#endif
                if (upnp_status.lease_expiry_ms > now_ms) {
                    status_out->upnp_lease_remaining_sec =
                        (uint32_t)((upnp_status.lease_expiry_ms - now_ms) / 1000);
                }
            }
        }
    }
#endif
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

int cyxchat_conn_is_bootstrap_connected(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return 0;
    return ctx->bootstrap_connected;
}

int cyxchat_conn_is_upnp_available(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return 0;
#ifdef CYXWIZ_HAS_UPNP
    if (ctx->transport && ctx->transport->driver_data) {
        cyxwiz_upnp_status_t status;
        if (cyxwiz_udp_get_upnp_status(ctx->transport->driver_data, &status) == CYXWIZ_OK) {
            return status.discovered ? 1 : 0;
        }
    }
#endif
    return 0;
}

int cyxchat_conn_is_upnp_mapping_active(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return 0;
#ifdef CYXWIZ_HAS_UPNP
    if (ctx->transport && ctx->transport->driver_data) {
        return cyxwiz_udp_is_upnp_active(ctx->transport->driver_data) ? 1 : 0;
    }
#endif
    return 0;
}

uint16_t cyxchat_conn_get_upnp_external_port(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return 0;
#ifdef CYXWIZ_HAS_UPNP
    if (ctx->transport && ctx->transport->driver_data) {
        cyxwiz_upnp_status_t status;
        if (cyxwiz_udp_get_upnp_status(ctx->transport->driver_data, &status) == CYXWIZ_OK) {
            return status.external_port;
        }
    }
#endif
    return 0;
}

uint32_t cyxchat_conn_get_upnp_lease_remaining_sec(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return 0;
#ifdef CYXWIZ_HAS_UPNP
    if (ctx->transport && ctx->transport->driver_data) {
        cyxwiz_upnp_status_t status;
        if (cyxwiz_udp_get_upnp_status(ctx->transport->driver_data, &status) == CYXWIZ_OK) {
            if (status.mapping_active && status.lease_expiry_ms > 0) {
                uint64_t now_ms = 0;
#ifdef _WIN32
                now_ms = GetTickCount64();
#else
                struct timeval tv;
                gettimeofday(&tv, NULL);
                now_ms = (uint64_t)tv.tv_sec * 1000 + tv.tv_usec / 1000;
#endif
                if (status.lease_expiry_ms > now_ms) {
                    return (uint32_t)((status.lease_expiry_ms - now_ms) / 1000);
                }
            }
        }
    }
#endif
    return 0;
}

int cyxchat_conn_has_peer_key(cyxchat_conn_ctx_t *ctx, const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id || !ctx->onion) return 0;
    return cyxwiz_onion_has_key(ctx->onion, peer_id) ? 1 : 0;
}
cyxchat_error_t cyxchat_conn_get_peer_pubkey(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *peer_id,
    uint8_t *pubkey_out)
{
    if (!ctx || !peer_id || !pubkey_out) {
        return CYXCHAT_ERR_NULL;
    }

    char peer_hex[17] = {0};
    for (int i = 0; i < 8; i++) {
        snprintf(peer_hex + i*2, 3, "%02x", peer_id->bytes[i]);
    }

    /* Try exact match first */
    cyxchat_peer_conn_t *conn = find_peer_conn(ctx, peer_id);
    if (conn && conn->has_pubkey) {
        memcpy(pubkey_out, conn->pubkey, 32);
        CYXWIZ_INFO("Found pubkey for peer %.16s (exact match)", peer_hex);
        return CYXCHAT_OK;
    }

    /* Fallback: match by first 8 bytes only (for short node ID lookups).
     * This handles the case where user enters short ID like "cb1f012e1e7b4067"
     * but the connection context stores full 32-byte node IDs. */
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (ctx->peers[i].active &&
            memcmp(&ctx->peers[i].peer_id, peer_id, 8) == 0 &&
            ctx->peers[i].has_pubkey) {
            memcpy(pubkey_out, ctx->peers[i].pubkey, 32);
            CYXWIZ_INFO("Found pubkey for peer %.16s (prefix match)", peer_hex);
            return CYXCHAT_OK;
        }
    }

    CYXWIZ_INFO("No pubkey for peer %.16s (conn=%p)", peer_hex, (void*)conn);
    return CYXCHAT_ERR_NOT_FOUND;
}

cyxchat_error_t cyxchat_conn_get_full_node_id(
    cyxchat_conn_ctx_t *ctx,
    const cyxwiz_node_id_t *prefix_id,
    cyxwiz_node_id_t *full_id_out)
{
    if (!ctx || !prefix_id || !full_id_out) {
        return CYXCHAT_ERR_NULL;
    }

    char prefix_hex[17];
    for (int i = 0; i < 8; i++) {
        snprintf(prefix_hex + i*2, 3, "%02x", prefix_id->bytes[i]);
    }
    prefix_hex[16] = 0;

    /* First try exact match */
    cyxchat_peer_conn_t *conn = find_peer_conn(ctx, prefix_id);
    if (conn && conn->active) {
        memcpy(full_id_out, &conn->peer_id, sizeof(cyxwiz_node_id_t));
        CYXWIZ_INFO("Found full node ID for prefix %.16s (exact match)", prefix_hex);
        return CYXCHAT_OK;
    }

    /* Fallback: match by first 8 bytes only */
    for (size_t i = 0; i < CYXCHAT_MAX_PEER_CONNECTIONS; i++) {
        if (ctx->peers[i].active &&
            memcmp(&ctx->peers[i].peer_id, prefix_id, 8) == 0) {
            memcpy(full_id_out, &ctx->peers[i].peer_id, sizeof(cyxwiz_node_id_t));
            CYXWIZ_INFO("Found full node ID for prefix %.16s (prefix match)", prefix_hex);
            return CYXCHAT_OK;
        }
    }

    CYXWIZ_INFO("No full node ID for prefix %.16s", prefix_hex);
    return CYXCHAT_ERR_NOT_FOUND;
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

void* cyxchat_conn_get_router(cyxchat_conn_ctx_t *ctx)
{
    return ctx ? ctx->router : NULL;
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

void cyxchat_conn_set_on_progress(cyxchat_conn_ctx_t *ctx,
                                   cyxchat_conn_progress_callback_t callback,
                                   void *user_data)
{
    if (!ctx) return;
    ctx->on_progress = callback;
    ctx->progress_user_data = user_data;
    CYXWIZ_INFO("Progress callback registered: %p", (void*)callback);
}

void cyxchat_conn_set_file_ctx(cyxchat_conn_ctx_t *ctx, void *file_ctx)
{
    if (!ctx) return;
    ctx->file_ctx = file_ctx;
    CYXWIZ_INFO("Connection: file context set for direct mode routing");
}

/* ============================================================
 * Presence Query
 * ============================================================ */

void cyxchat_conn_set_presence_callback(cyxchat_conn_ctx_t *ctx,
                                        cyxchat_presence_callback_t callback,
                                        void *user_data)
{
    if (!ctx) return;
    ctx->on_presence = callback;
    ctx->presence_user_data = user_data;
    CYXWIZ_INFO("Presence callback registered: %p", (void*)callback);
}

cyxchat_error_t cyxchat_conn_query_presence(cyxchat_conn_ctx_t *ctx,
                                            const cyxwiz_node_id_t *peer_id)
{
    if (!ctx || !peer_id) {
        return CYXCHAT_ERR_NULL;
    }

    if (!ctx->transport || !ctx->server_registry) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Get best server to send to */
    cyxchat_server_info_t server;
    cyxchat_error_t srv_err = cyxchat_server_registry_get_best(ctx->server_registry, &server);
    if (srv_err != CYXCHAT_OK) {
        CYXWIZ_WARN("Presence query: no server available");
        return CYXCHAT_ERR_NETWORK;
    }

    /* Parse server address "ip:port" */
    char addr_copy[64];
    strncpy(addr_copy, server.addr, sizeof(addr_copy) - 1);
    addr_copy[sizeof(addr_copy) - 1] = '\0';

    char *colon = strchr(addr_copy, ':');
    if (!colon) {
        CYXWIZ_WARN("Presence query: invalid server address %s", server.addr);
        return CYXCHAT_ERR_INVALID;
    }
    *colon = '\0';
    uint16_t port = (uint16_t)atoi(colon + 1);

    /* Convert IP to network byte order */
    uint32_t ip_nbo;
    if (inet_pton(AF_INET, addr_copy, &ip_nbo) != 1) {
        CYXWIZ_WARN("Presence query: cannot parse IP %s", addr_copy);
        return CYXCHAT_ERR_INVALID;
    }
    uint16_t port_nbo = htons(port);

    /* Build node ID with IP:port and 0xFF marker */
    cyxwiz_node_id_t srv_id;
    memset(&srv_id, 0, sizeof(srv_id));
    memcpy(srv_id.bytes, &ip_nbo, 4);
    memcpy(srv_id.bytes + 4, &port_nbo, 2);
    srv_id.bytes[6] = 0xFF;  /* Server address marker */

    /* Build presence query message */
    uint8_t msg[1 + 32 + 32];  /* type + requester_id + peer_id */
    msg[0] = CYXCHAT_PRESENCE_QUERY;
    memcpy(&msg[1], &ctx->local_id, 32);
    memcpy(&msg[33], peer_id, 32);

    /* Send to server */
    cyxwiz_error_t err = ctx->transport->ops->send(
        ctx->transport, &srv_id, msg, sizeof(msg)
    );

    if (err != CYXWIZ_OK) {
        return CYXCHAT_ERR_NETWORK;
    }

    return CYXCHAT_OK;
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

cyxwiz_onion_ctx_t* cyxchat_conn_get_onion(cyxchat_conn_ctx_t *ctx)
{
    return ctx ? ctx->onion : NULL;
}

cyxwiz_dht_t* cyxchat_conn_get_dht(cyxchat_conn_ctx_t *ctx)
{
    return ctx ? ctx->dht : NULL;
}

/* ============================================================
 * DHT (Distributed Hash Table) for Peer Discovery
 * ============================================================ */

cyxchat_error_t cyxchat_conn_dht_bootstrap(cyxchat_conn_ctx_t *ctx,
                                            const cyxwiz_node_id_t *seed_nodes,
                                            size_t count)
{
    if (!ctx || !seed_nodes || count == 0) {
        return CYXCHAT_ERR_NULL;
    }

    if (!ctx->dht) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_error_t err = cyxwiz_dht_bootstrap(ctx->dht, seed_nodes, count);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_NETWORK;
}

cyxchat_error_t cyxchat_conn_dht_add_node(cyxchat_conn_ctx_t *ctx,
                                           const cyxwiz_node_id_t *node_id)
{
    if (!ctx || !node_id) {
        return CYXCHAT_ERR_NULL;
    }

    if (!ctx->dht) {
        return CYXCHAT_ERR_INVALID;
    }

    cyxwiz_error_t err = cyxwiz_dht_add_node(ctx->dht, node_id);
    return (err == CYXWIZ_OK) ? CYXCHAT_OK : CYXCHAT_ERR_FULL;
}

/* Wrapper callback for DHT find */
static void dht_find_wrapper_cb(const cyxwiz_node_id_t *target,
                                 bool found,
                                 const cyxwiz_node_id_t *result,
                                 void *user_data)
{
    (void)result;  /* We only care if found or not */
    cyxchat_dht_find_ctx_t *find_ctx = (cyxchat_dht_find_ctx_t*)user_data;
    if (!find_ctx) return;

    if (find_ctx->callback) {
        find_ctx->callback(find_ctx->ctx, target, found ? 1 : 0, find_ctx->user_data);
    }

    /* Free the wrapper context */
    free(find_ctx);
}

cyxchat_error_t cyxchat_conn_dht_find_node(cyxchat_conn_ctx_t *ctx,
                                            const cyxwiz_node_id_t *target,
                                            cyxchat_dht_find_callback_t callback,
                                            void *user_data)
{
    if (!ctx || !target) {
        return CYXCHAT_ERR_NULL;
    }

    if (!ctx->dht) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Allocate wrapper context for callback */
    cyxchat_dht_find_ctx_t *find_ctx = NULL;
    if (callback) {
        find_ctx = (cyxchat_dht_find_ctx_t*)malloc(sizeof(cyxchat_dht_find_ctx_t));
        if (!find_ctx) {
            return CYXCHAT_ERR_MEMORY;
        }
        find_ctx->ctx = ctx;
        find_ctx->callback = callback;
        find_ctx->user_data = user_data;
        find_ctx->target = *target;
    }

    cyxwiz_error_t err = cyxwiz_dht_find_node(ctx->dht, target,
        callback ? dht_find_wrapper_cb : NULL,
        callback ? find_ctx : NULL);

    if (err != CYXWIZ_OK) {
        free(find_ctx);
        return CYXCHAT_ERR_NETWORK;
    }

    return CYXCHAT_OK;
}

size_t cyxchat_conn_dht_get_closest(cyxchat_conn_ctx_t *ctx,
                                     const cyxwiz_node_id_t *target,
                                     cyxwiz_node_id_t *out_nodes,
                                     size_t max_nodes)
{
    if (!ctx || !target || !out_nodes || max_nodes == 0) {
        return 0;
    }

    if (!ctx->dht) {
        return 0;
    }

    return cyxwiz_dht_get_closest(ctx->dht, target, out_nodes, max_nodes);
}

void cyxchat_conn_dht_set_node_callback(cyxchat_conn_ctx_t *ctx,
                                         cyxchat_dht_node_callback_t callback,
                                         void *user_data)
{
    if (!ctx) return;

    ctx->on_dht_node = callback;
    ctx->dht_node_user_data = user_data;
}

void cyxchat_conn_dht_get_stats(cyxchat_conn_ctx_t *ctx,
                                 cyxwiz_dht_stats_t *stats_out)
{
    if (!ctx || !stats_out) return;

    memset(stats_out, 0, sizeof(cyxwiz_dht_stats_t));

    if (ctx->dht) {
        cyxwiz_dht_get_stats(ctx->dht, stats_out);
    }
}

int cyxchat_conn_dht_is_ready(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx || !ctx->dht) {
        return 0;
    }

    cyxwiz_dht_stats_t stats;
    cyxwiz_dht_get_stats(ctx->dht, &stats);

    /* Consider DHT ready if we have at least some nodes */
    return stats.total_nodes >= 1;
}

/* ============================================================
 * Manual Peer Addition
 * ============================================================ */

/* Internal UDP punch packet type */
#define CYXWIZ_UDP_PUNCH 0xF4

/* Socket error code macro */
#ifdef _WIN32
#define CONN_SOCKET_ERROR WSAGetLastError()
#else
#define CONN_SOCKET_ERROR errno
#endif

/* UDP punch packet structure (matches udp.c - packed for network) */
#ifdef _MSC_VER
#pragma pack(push, 1)
#endif
typedef struct {
    uint8_t type;
    cyxwiz_node_id_t sender_id;
    uint32_t punch_id;
}
#ifdef __GNUC__
__attribute__((packed))
#endif
cyxchat_punch_packet_t;
#ifdef _MSC_VER
#pragma pack(pop)
#endif

/* Note: cyxchat_udp_state_view_t is defined earlier in this file */

cyxchat_error_t cyxchat_conn_add_peer_addr(cyxchat_conn_ctx_t *ctx,
                                            const cyxwiz_node_id_t *node_id,
                                            const char *addr)
{
    if (!ctx || !node_id || !addr) {
        return CYXCHAT_ERR_NULL;
    }

    if (!ctx->transport) {
        return CYXCHAT_ERR_NETWORK;
    }

    /* Parse IP:port string */
    char ip_str[64];
    int port = 0;

    const char *colon = strchr(addr, ':');
    if (!colon) {
        CYXWIZ_WARN("Invalid address format (missing port): %s", addr);
        return CYXCHAT_ERR_INVALID;
    }

    size_t ip_len = (size_t)(colon - addr);
    if (ip_len >= sizeof(ip_str)) {
        return CYXCHAT_ERR_INVALID;
    }

    memcpy(ip_str, addr, ip_len);
    ip_str[ip_len] = '\0';
    port = atoi(colon + 1);

    if (port <= 0 || port > 65535) {
        CYXWIZ_WARN("Invalid port: %d", port);
        return CYXCHAT_ERR_INVALID;
    }

    /* Resolve IP address */
    struct sockaddr_in dest_addr;
    memset(&dest_addr, 0, sizeof(dest_addr));
    dest_addr.sin_family = AF_INET;
    dest_addr.sin_port = htons((uint16_t)port);

    if (inet_pton(AF_INET, ip_str, &dest_addr.sin_addr) != 1) {
        /* Try resolving as hostname */
        struct addrinfo hints, *result;
        memset(&hints, 0, sizeof(hints));
        hints.ai_family = AF_INET;
        hints.ai_socktype = SOCK_DGRAM;

        if (getaddrinfo(ip_str, NULL, &hints, &result) != 0) {
            CYXWIZ_WARN("Failed to resolve address: %s", ip_str);
            return CYXCHAT_ERR_NETWORK;
        }

        struct sockaddr_in *sin = (struct sockaddr_in *)result->ai_addr;
        dest_addr.sin_addr = sin->sin_addr;
        freeaddrinfo(result);
    }

    /* Add peer to peer table (ignore if already exists) */
    cyxwiz_peer_table_add(ctx->peer_table, node_id, CYXWIZ_TRANSPORT_UDP, 0);

    /* Get the transport's socket from driver_data */
    cyxchat_udp_state_view_t *udp_state =
        (cyxchat_udp_state_view_t *)ctx->transport->driver_data;
    if (!udp_state || !udp_state->initialized) {
        return CYXCHAT_ERR_NETWORK;  /* Transport not initialized */
    }

#ifdef _WIN32
    SOCKET sock = udp_state->socket_fd;
    if (sock == INVALID_SOCKET) {
        return CYXCHAT_ERR_NETWORK;
    }
#else
    int sock = udp_state->socket_fd;
    if (sock < 0) {
        return CYXCHAT_ERR_NETWORK;
    }
#endif

    /* Build punch packet */
    cyxchat_punch_packet_t punch;
    memset(&punch, 0, sizeof(punch));
    punch.type = CYXWIZ_UDP_PUNCH;
    memcpy(&punch.sender_id, &ctx->local_id, sizeof(cyxwiz_node_id_t));
    punch.punch_id = (uint32_t)(get_time_ms() & 0xFFFFFFFF);

    /* Send punch to peer */
    int sent = sendto(sock, (const char *)&punch, sizeof(punch), 0,
                      (struct sockaddr *)&dest_addr, sizeof(dest_addr));

    if (sent < 0) {
        CYXWIZ_WARN("Failed to send punch packet: %d", CONN_SOCKET_ERROR);
        return CYXCHAT_ERR_NETWORK;
    }

    CYXWIZ_INFO("Sent punch to %s:%d for peer discovery", ip_str, port);

    return CYXCHAT_OK;
}

/* ============================================================
 * Server Registry Access
 * ============================================================ */

cyxchat_server_registry_t* cyxchat_conn_get_server_registry(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx) return NULL;
    return ctx->server_registry;
}

cyxchat_error_t cyxchat_conn_add_server(cyxchat_conn_ctx_t *ctx,
                                         const char *addr,
                                         const uint8_t *pubkey)
{
    if (!ctx || !addr) return CYXCHAT_ERR_NULL;
    if (!ctx->server_registry) return CYXCHAT_ERR_INVALID;
    return cyxchat_server_registry_add(ctx->server_registry, addr, pubkey);
}

size_t cyxchat_conn_server_count(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx || !ctx->server_registry) return 0;
    return cyxchat_server_registry_count(ctx->server_registry);
}

size_t cyxchat_conn_healthy_server_count(cyxchat_conn_ctx_t *ctx)
{
    if (!ctx || !ctx->server_registry) return 0;
    return cyxchat_server_registry_healthy_count(ctx->server_registry);
}

int cyxchat_conn_get_servers_info(cyxchat_conn_ctx_t *ctx, char *buf, size_t buf_size)
{
    if (!ctx || !buf || buf_size == 0) return 0;
    if (!ctx->server_registry) {
        buf[0] = '\0';
        return 0;
    }

    cyxchat_server_info_t servers[CYXCHAT_MAX_SERVERS];
    size_t count = cyxchat_server_registry_get_all(ctx->server_registry, servers, CYXCHAT_MAX_SERVERS);

    int written = 0;
    for (size_t i = 0; i < count; i++) {
        const char *state_name = cyxchat_server_state_name(servers[i].state);
        int is_healthy = (servers[i].state == CYXCHAT_SERVER_HEALTHY) ? 1 : 0;
        int n = snprintf(buf + written, buf_size - (size_t)written,
                         "%s|%s|%u|%u|%d|%d\n",
                         servers[i].addr,
                         state_name,
                         servers[i].latency_ms,
                         servers[i].avg_latency_ms,
                         servers[i].is_seed,
                         is_healthy);
        if (n < 0 || (size_t)(written + n) >= buf_size) break;
        written += n;
    }
    return written;
}
