/**
 * CyxChat Contact Management
 * Contact list and management API
 */

#ifndef CYXCHAT_CONTACT_H
#define CYXCHAT_CONTACT_H

#include "types.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Contact Structure
 * ============================================================ */

typedef struct {
    cyxwiz_node_id_t node_id;                   /* Contact's node ID */
    uint8_t public_key[32];                     /* X25519 public key */
    char display_name[CYXCHAT_MAX_DISPLAY_NAME];
    int verified;                                /* Key verified */
    int blocked;                                 /* Contact blocked */
    uint64_t added_at;                           /* When added */
    uint64_t last_seen;                          /* Last activity */
    cyxchat_presence_t presence;                /* Current presence */
    char status_text[CYXCHAT_MAX_STATUS_LEN];   /* Custom status */
} cyxchat_contact_t;

/* ============================================================
 * Contact List
 * ============================================================ */

typedef struct cyxchat_contact_list cyxchat_contact_list_t;

/**
 * Create contact list
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_list_create(
    cyxchat_contact_list_t **list
);

/**
 * Destroy contact list
 */
CYXCHAT_API void cyxchat_contact_list_destroy(cyxchat_contact_list_t *list);

/**
 * Add contact
 *
 * @param list          Contact list
 * @param node_id       Contact's node ID
 * @param public_key    Contact's public key (32 bytes)
 * @param display_name  Display name (can be NULL)
 * @return              CYXCHAT_OK or error
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_add(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    const uint8_t *public_key,
    const char *display_name
);

/**
 * Remove contact
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_remove(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

/**
 * Find contact by node ID
 *
 * @return Contact pointer or NULL if not found
 */
CYXCHAT_API cyxchat_contact_t* cyxchat_contact_find(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

/**
 * Update contact display name
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_set_name(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    const char *display_name
);

/**
 * Set contact blocked status
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_set_blocked(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int blocked
);

/**
 * Set contact verified status
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_set_verified(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    int verified
);

/**
 * Update contact presence
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_set_presence(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    cyxchat_presence_t presence,
    const char *status_text
);

/**
 * Update contact last seen
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_update_last_seen(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id,
    uint64_t timestamp
);

/**
 * Check if contact is blocked
 */
CYXCHAT_API int cyxchat_contact_is_blocked(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

/**
 * Check if contact exists
 */
CYXCHAT_API int cyxchat_contact_exists(
    cyxchat_contact_list_t *list,
    const cyxwiz_node_id_t *node_id
);

/**
 * Get contact count
 */
CYXCHAT_API size_t cyxchat_contact_count(cyxchat_contact_list_t *list);

/**
 * Get contact by index
 */
CYXCHAT_API cyxchat_contact_t* cyxchat_contact_get(
    cyxchat_contact_list_t *list,
    size_t index
);

/* ============================================================
 * Safety Numbers
 * ============================================================ */

/**
 * Compute safety number for key verification
 *
 * @param our_pubkey    Our public key (32 bytes)
 * @param their_pubkey  Their public key (32 bytes)
 * @param out           Output buffer (at least 60 bytes)
 * @param out_len       Output buffer length
 *
 * Output format: "12345 67890 12345 67890 12345 67890"
 */
CYXCHAT_API void cyxchat_compute_safety_number(
    const uint8_t *our_pubkey,
    const uint8_t *their_pubkey,
    char *out,
    size_t out_len
);

/* ============================================================
 * QR Code Data
 * ============================================================ */

/**
 * Generate QR code data for sharing contact
 *
 * @param node_id       Node ID to share
 * @param public_key    Public key to share (32 bytes)
 * @param out           Output buffer (at least 150 bytes)
 * @param out_len       Output buffer length
 * @return              Length of QR data or 0 on error
 *
 * Output format: "cyxchat://add/<node_id_hex>/<pubkey_hex>"
 */
CYXCHAT_API size_t cyxchat_contact_generate_qr(
    const cyxwiz_node_id_t *node_id,
    const uint8_t *public_key,
    char *out,
    size_t out_len
);

/**
 * Parse QR code data
 *
 * @param qr_data       QR code string
 * @param node_id_out   Output: parsed node ID
 * @param pubkey_out    Output: parsed public key (32 bytes)
 * @return              CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_contact_parse_qr(
    const char *qr_data,
    cyxwiz_node_id_t *node_id_out,
    uint8_t *pubkey_out
);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_CONTACT_H */
