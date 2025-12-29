/**
 * CyxChat Test - Contact Module
 */

#include <stdio.h>
#include <string.h>
#include <cyxchat/cyxchat.h>

#define TEST_ASSERT(cond, msg) do { \
    if (!(cond)) { \
        printf("    ASSERT FAILED: %s\n", msg); \
        errors++; \
    } \
} while(0)

int test_contact(void) {
    int errors = 0;

    /* Test contact list creation */
    {
        cyxchat_contact_list_t *list = NULL;
        cyxchat_error_t err = cyxchat_contact_list_create(&list);

        TEST_ASSERT(err == CYXCHAT_OK, "Contact list creation should succeed");
        TEST_ASSERT(list != NULL, "Contact list should not be NULL");
        TEST_ASSERT(cyxchat_contact_count(list) == 0, "New list should be empty");

        cyxchat_contact_list_destroy(list);
    }

    /* Test adding contacts */
    {
        cyxchat_contact_list_t *list = NULL;
        cyxchat_contact_list_create(&list);

        cyxwiz_node_id_t id1, id2;
        uint8_t key1[32], key2[32];

        memset(&id1, 0x11, sizeof(id1));
        memset(&id2, 0x22, sizeof(id2));
        memset(key1, 0xAA, sizeof(key1));
        memset(key2, 0xBB, sizeof(key2));

        cyxchat_error_t err = cyxchat_contact_add(list, &id1, key1, "Alice");
        TEST_ASSERT(err == CYXCHAT_OK, "Adding first contact should succeed");

        err = cyxchat_contact_add(list, &id2, key2, "Bob");
        TEST_ASSERT(err == CYXCHAT_OK, "Adding second contact should succeed");

        TEST_ASSERT(cyxchat_contact_count(list) == 2, "List should have 2 contacts");

        /* Test duplicate detection */
        err = cyxchat_contact_add(list, &id1, key1, "Alice Duplicate");
        TEST_ASSERT(err == CYXCHAT_ERR_EXISTS, "Duplicate should fail");

        cyxchat_contact_list_destroy(list);
    }

    /* Test finding contacts */
    {
        cyxchat_contact_list_t *list = NULL;
        cyxchat_contact_list_create(&list);

        cyxwiz_node_id_t id;
        uint8_t key[32];

        memset(&id, 0x33, sizeof(id));
        memset(key, 0xCC, sizeof(key));

        cyxchat_contact_add(list, &id, key, "Charlie");

        cyxchat_contact_t *contact = cyxchat_contact_find(list, &id);
        TEST_ASSERT(contact != NULL, "Should find added contact");
        TEST_ASSERT(strcmp(contact->display_name, "Charlie") == 0, "Name should match");

        /* Test not found */
        cyxwiz_node_id_t unknown;
        memset(&unknown, 0xFF, sizeof(unknown));
        contact = cyxchat_contact_find(list, &unknown);
        TEST_ASSERT(contact == NULL, "Unknown contact should not be found");

        cyxchat_contact_list_destroy(list);
    }

    /* Test contact updates */
    {
        cyxchat_contact_list_t *list = NULL;
        cyxchat_contact_list_create(&list);

        cyxwiz_node_id_t id;
        uint8_t key[32];
        memset(&id, 0x44, sizeof(id));
        memset(key, 0xDD, sizeof(key));

        cyxchat_contact_add(list, &id, key, "Dave");

        cyxchat_error_t err = cyxchat_contact_set_name(list, &id, "David");
        TEST_ASSERT(err == CYXCHAT_OK, "Rename should succeed");

        cyxchat_contact_t *contact = cyxchat_contact_find(list, &id);
        TEST_ASSERT(strcmp(contact->display_name, "David") == 0, "Name should be updated");

        err = cyxchat_contact_set_blocked(list, &id, 1);
        TEST_ASSERT(err == CYXCHAT_OK, "Block should succeed");
        TEST_ASSERT(cyxchat_contact_is_blocked(list, &id) == 1, "Should be blocked");

        cyxchat_contact_list_destroy(list);
    }

    /* Test contact removal */
    {
        cyxchat_contact_list_t *list = NULL;
        cyxchat_contact_list_create(&list);

        cyxwiz_node_id_t id1, id2;
        uint8_t key[32];

        memset(&id1, 0x55, sizeof(id1));
        memset(&id2, 0x66, sizeof(id2));
        memset(key, 0xEE, sizeof(key));

        cyxchat_contact_add(list, &id1, key, "Eve");
        cyxchat_contact_add(list, &id2, key, "Frank");

        TEST_ASSERT(cyxchat_contact_count(list) == 2, "Should have 2 contacts");

        cyxchat_error_t err = cyxchat_contact_remove(list, &id1);
        TEST_ASSERT(err == CYXCHAT_OK, "Remove should succeed");
        TEST_ASSERT(cyxchat_contact_count(list) == 1, "Should have 1 contact");
        TEST_ASSERT(cyxchat_contact_find(list, &id1) == NULL, "Removed contact not found");
        TEST_ASSERT(cyxchat_contact_find(list, &id2) != NULL, "Other contact still exists");

        cyxchat_contact_list_destroy(list);
    }

    /* Test QR code generation/parsing */
    {
        cyxwiz_node_id_t id, parsed_id;
        uint8_t key[32], parsed_key[32];
        char qr[256];

        memset(&id, 0x77, sizeof(id));
        memset(key, 0x88, sizeof(key));

        size_t len = cyxchat_contact_generate_qr(&id, key, qr, sizeof(qr));
        TEST_ASSERT(len > 0, "QR generation should succeed");
        TEST_ASSERT(strstr(qr, "cyxchat://add/") == qr, "QR should have correct prefix");

        cyxchat_error_t err = cyxchat_contact_parse_qr(qr, &parsed_id, parsed_key);
        TEST_ASSERT(err == CYXCHAT_OK, "QR parse should succeed");
        TEST_ASSERT(memcmp(&id, &parsed_id, sizeof(id)) == 0, "Node ID should match");
        TEST_ASSERT(memcmp(key, parsed_key, sizeof(key)) == 0, "Key should match");
    }

    /* Test safety number computation */
    {
        uint8_t key1[32], key2[32];
        char safety1[64], safety2[64];

        memset(key1, 0x11, sizeof(key1));
        memset(key2, 0x22, sizeof(key2));

        cyxchat_compute_safety_number(key1, key2, safety1, sizeof(safety1));
        cyxchat_compute_safety_number(key2, key1, safety2, sizeof(safety2));

        TEST_ASSERT(strlen(safety1) > 0, "Safety number should be generated");
        TEST_ASSERT(strcmp(safety1, safety2) == 0, "Safety number should be symmetric");
    }

    return errors;
}
