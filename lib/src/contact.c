/**
 * CyxChat Contact Management Implementation
 */

#include <cyxchat/contact.h>
#include <cyxchat/chat.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/memory.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ============================================================
 * Internal Structures
 * ============================================================ */

struct cyxchat_contact_list {
    cyxchat_contact_t contacts[CYXCHAT_MAX_CONTACTS];
    size_t count;
};

/* ============================================================
 * Contact List Management
 * ============================================================ */

cyxchat_error_t cyxchat_contact_list_create(cyxchat_contact_list_t **list) {
    if (!list) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_contact_list_t *l = calloc(1, sizeof(cyxchat_contact_list_t));
    if (!l) {
        return CYXCHAT_ERR_MEMORY;
    }

    *list = l;
    return CYXCHAT_OK;
}

void cyxchat_contact_list_destroy(cyxchat_contact_list_t *list) {
    if (list) {
        cyxwiz_secure_zero(list, sizeof(cyxchat_contact_list_t));
        free(list);
    }
}

cyxchat_error_t cyxchat_contact_add(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    const uint8_t *public_key,
    const char *display_name
) {
    if (!list || !node_id || !public_key) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check if already exists */
    if (cyxchat_contact_find(list, node_id)) {
        return CYXCHAT_ERR_EXISTS;
    }

    if (list->count >= CYXCHAT_MAX_CONTACTS) {
        return CYXCHAT_ERR_FULL;
    }

    cyxchat_contact_t *contact = &list->contacts[list->count];
    memset(contact, 0, sizeof(cyxchat_contact_t));

    memcpy(&contact->node_id, node_id, sizeof(cyxwiz_node_id_t));
    memcpy(contact->public_key, public_key, 32);

    if (display_name) {
        strncpy(contact->display_name, display_name, CYXCHAT_MAX_DISPLAY_NAME - 1);
    }

    contact->added_at = cyxchat_timestamp_ms();
    contact->presence = CYXCHAT_PRESENCE_OFFLINE;

    list->count++;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_contact_remove(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
) {
    if (!list || !node_id) {
        return CYXCHAT_ERR_NULL;
    }

    for (size_t i = 0; i < list->count; i++) {
        if (memcmp(list->contacts[i].node_id.bytes, node_id->bytes, 32) == 0) {
            /* Move last contact to this slot */
            if (i < list->count - 1) {
                memcpy(&list->contacts[i],
                       &list->contacts[list->count - 1],
                       sizeof(cyxchat_contact_t));
            }

            /* Clear last slot */
            memset(&list->contacts[list->count - 1], 0, sizeof(cyxchat_contact_t));
            list->count--;

            return CYXCHAT_OK;
        }
    }

    return CYXCHAT_ERR_NOT_FOUND;
}

cyxchat_contact_t* cyxchat_contact_find(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
) {
    if (!list || !node_id) {
        return NULL;
    }

    for (size_t i = 0; i < list->count; i++) {
        if (memcmp(list->contacts[i].node_id.bytes, node_id->bytes, 32) == 0) {
            return &list->contacts[i];
        }
    }

    return NULL;
}

cyxchat_error_t cyxchat_contact_set_name(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    const char *display_name
) {
    cyxchat_contact_t *contact = cyxchat_contact_find(list, node_id);
    if (!contact) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    memset(contact->display_name, 0, CYXCHAT_MAX_DISPLAY_NAME);
    if (display_name) {
        strncpy(contact->display_name, display_name, CYXCHAT_MAX_DISPLAY_NAME - 1);
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_contact_set_blocked(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int blocked
) {
    cyxchat_contact_t *contact = cyxchat_contact_find(list, node_id);
    if (!contact) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    contact->blocked = blocked ? 1 : 0;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_contact_set_verified(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int verified
) {
    cyxchat_contact_t *contact = cyxchat_contact_find(list, node_id);
    if (!contact) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    contact->verified = verified ? 1 : 0;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_contact_set_presence(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    cyxchat_presence_t presence,
    const char *status_text
) {
    cyxchat_contact_t *contact = cyxchat_contact_find(list, node_id);
    if (!contact) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    contact->presence = presence;

    memset(contact->status_text, 0, CYXCHAT_MAX_STATUS_LEN);
    if (status_text) {
        strncpy(contact->status_text, status_text, CYXCHAT_MAX_STATUS_LEN - 1);
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_contact_update_last_seen(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    uint64_t timestamp
) {
    cyxchat_contact_t *contact = cyxchat_contact_find(list, node_id);
    if (!contact) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    contact->last_seen = timestamp;
    return CYXCHAT_OK;
}

int cyxchat_contact_is_blocked(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
) {
    cyxchat_contact_t *contact = cyxchat_contact_find(list, node_id);
    return contact ? contact->blocked : 0;
}

int cyxchat_contact_exists(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
) {
    return cyxchat_contact_find(list, node_id) != NULL;
}

size_t cyxchat_contact_count(cyxchat_contact_list_t *list) {
    return list ? list->count : 0;
}

cyxchat_contact_t* cyxchat_contact_get(
    cyxchat_contact_list_t *list,
    size_t index
) {
    if (!list || index >= list->count) {
        return NULL;
    }
    return &list->contacts[index];
}

/* ============================================================
 * Safety Numbers
 * ============================================================ */

void cyxchat_compute_safety_number(
    const uint8_t *our_pubkey,
    const uint8_t *their_pubkey,
    char *out,
    size_t out_len
) {
    if (!our_pubkey || !their_pubkey || !out || out_len < 60) {
        return;
    }

    /* Combine keys in consistent order (lower key first) */
    uint8_t combined[64];
    int cmp = memcmp(our_pubkey, their_pubkey, 32);
    if (cmp <= 0) {
        memcpy(combined, our_pubkey, 32);
        memcpy(combined + 32, their_pubkey, 32);
    } else {
        memcpy(combined, their_pubkey, 32);
        memcpy(combined + 32, our_pubkey, 32);
    }

    /* Hash to get safety number seed */
    uint8_t hash[32];
    cyxwiz_crypto_hash(combined, 64, hash, 32);

    /* Convert to 6 groups of 5 digits */
    char *p = out;
    for (int group = 0; group < 6; group++) {
        /* Use 5 bytes per group */
        uint32_t val = 0;
        for (int i = 0; i < 5 && (group * 5 + i) < 32; i++) {
            val = (val << 8) | hash[group * 5 + i];
        }

        /* Format as 5 digits */
        int n = snprintf(p, 6, "%05u", val % 100000);
        p += n;

        if (group < 5) {
            *p++ = ' ';
        }
    }
    *p = '\0';
}

/* ============================================================
 * QR Code Data
 * ============================================================ */

size_t cyxchat_contact_generate_qr(
    const cyxwiz_node_id_t *node_id,
    const uint8_t *public_key,
    char *out,
    size_t out_len
) {
    if (!node_id || !public_key || !out || out_len < 150) {
        return 0;
    }

    /* Format: cyxchat://add/<node_id_hex>/<pubkey_hex> */
    char node_hex[65];
    char key_hex[65];

    /* Convert node ID to hex */
    for (int i = 0; i < 32; i++) {
        snprintf(node_hex + i * 2, 3, "%02x", node_id->bytes[i]);
    }
    node_hex[64] = '\0';

    /* Convert public key to hex */
    for (int i = 0; i < 32; i++) {
        snprintf(key_hex + i * 2, 3, "%02x", public_key[i]);
    }
    key_hex[64] = '\0';

    size_t len = snprintf(out, out_len, "cyxchat://add/%s/%s", node_hex, key_hex);
    return len;
}

static int hex_char_to_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

cyxchat_error_t cyxchat_contact_parse_qr(
    const char *qr_data,
    cyxwiz_node_id_t *node_id_out,
    uint8_t *pubkey_out
) {
    if (!qr_data || !node_id_out || !pubkey_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Check prefix */
    const char *prefix = "cyxchat://add/";
    size_t prefix_len = strlen(prefix);

    if (strncmp(qr_data, prefix, prefix_len) != 0) {
        return CYXCHAT_ERR_INVALID;
    }

    const char *data = qr_data + prefix_len;

    /* Parse node ID (64 hex chars) */
    if (strlen(data) < 64) {
        return CYXCHAT_ERR_INVALID;
    }

    for (int i = 0; i < 32; i++) {
        int hi = hex_char_to_nibble(data[i * 2]);
        int lo = hex_char_to_nibble(data[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            return CYXCHAT_ERR_INVALID;
        }
        node_id_out->bytes[i] = (uint8_t)((hi << 4) | lo);
    }

    /* Skip separator */
    data += 64;
    if (*data != '/') {
        return CYXCHAT_ERR_INVALID;
    }
    data++;

    /* Parse public key (64 hex chars) */
    if (strlen(data) < 64) {
        return CYXCHAT_ERR_INVALID;
    }

    for (int i = 0; i < 32; i++) {
        int hi = hex_char_to_nibble(data[i * 2]);
        int lo = hex_char_to_nibble(data[i * 2 + 1]);
        if (hi < 0 || lo < 0) {
            return CYXCHAT_ERR_INVALID;
        }
        pubkey_out[i] = (uint8_t)((hi << 4) | lo);
    }

    return CYXCHAT_OK;
}

