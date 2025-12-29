/**
 * CyxChat Test - Chat Module
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

int test_chat(void) {
    int errors = 0;

    /* Test message ID generation */
    {
        cyxchat_msg_id_t id1, id2;
        cyxchat_generate_msg_id(&id1);
        cyxchat_generate_msg_id(&id2);

        TEST_ASSERT(!cyxchat_msg_id_is_zero(&id1), "Generated ID should not be zero");
        TEST_ASSERT(!cyxchat_msg_id_is_zero(&id2), "Generated ID should not be zero");
        TEST_ASSERT(cyxchat_msg_id_cmp(&id1, &id2) != 0, "IDs should be unique");
    }

    /* Test message ID hex conversion */
    {
        cyxchat_msg_id_t id1, id2;
        char hex[32];

        cyxchat_generate_msg_id(&id1);
        cyxchat_msg_id_to_hex(&id1, hex);

        TEST_ASSERT(strlen(hex) == 16, "Hex should be 16 characters");

        cyxchat_error_t err = cyxchat_msg_id_from_hex(hex, &id2);
        TEST_ASSERT(err == CYXCHAT_OK, "Hex parse should succeed");
        TEST_ASSERT(cyxchat_msg_id_cmp(&id1, &id2) == 0, "Roundtrip should preserve ID");
    }

    /* Test node ID hex conversion */
    {
        cyxwiz_node_id_t id1, id2;
        char hex[128];

        memset(&id1, 0xAB, sizeof(id1));
        cyxchat_node_id_to_hex(&id1, hex);

        TEST_ASSERT(strlen(hex) == 64, "Node hex should be 64 characters");

        cyxchat_error_t err = cyxchat_node_id_from_hex(hex, &id2);
        TEST_ASSERT(err == CYXCHAT_OK, "Node hex parse should succeed");
        TEST_ASSERT(memcmp(&id1, &id2, sizeof(id1)) == 0, "Roundtrip should preserve node ID");
    }

    /* Test zero ID detection */
    {
        cyxchat_msg_id_t zero_id;
        memset(&zero_id, 0, sizeof(zero_id));

        TEST_ASSERT(cyxchat_msg_id_is_zero(&zero_id), "Zero ID should be detected");
    }

    /* Test timestamp */
    {
        uint64_t ts1 = cyxchat_timestamp_ms();
        TEST_ASSERT(ts1 > 0, "Timestamp should be positive");

        /* Small delay */
        for (volatile int i = 0; i < 100000; i++);

        uint64_t ts2 = cyxchat_timestamp_ms();
        TEST_ASSERT(ts2 >= ts1, "Timestamps should be monotonic");
    }

    return errors;
}
