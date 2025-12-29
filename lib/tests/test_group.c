/**
 * CyxChat Test - Group Module
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

int test_group(void) {
    int errors = 0;

    /* Test group ID hex conversion */
    {
        cyxchat_group_id_t id1, id2;
        char hex[32];

        memset(&id1, 0xAB, sizeof(id1));
        cyxchat_group_id_to_hex(&id1, hex);

        TEST_ASSERT(strlen(hex) == 16, "Group hex should be 16 characters");

        cyxchat_error_t err = cyxchat_group_id_from_hex(hex, &id2);
        TEST_ASSERT(err == CYXCHAT_OK, "Hex parse should succeed");
        TEST_ASSERT(memcmp(&id1, &id2, sizeof(id1)) == 0, "Roundtrip should preserve ID");
    }

    /* Test invalid hex parsing */
    {
        cyxchat_group_id_t id;

        cyxchat_error_t err = cyxchat_group_id_from_hex("invalid", &id);
        TEST_ASSERT(err == CYXCHAT_ERR_INVALID, "Invalid hex should fail");

        err = cyxchat_group_id_from_hex("gggggggggggggggg", &id);
        TEST_ASSERT(err == CYXCHAT_ERR_INVALID, "Invalid hex chars should fail");
    }

    /* Note: Full group tests require cyxchat_ctx_t which needs onion context */
    /* These tests would be integration tests */

    printf("    (Group context tests require full integration)\n");

    return errors;
}
