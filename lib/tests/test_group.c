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

    /* Test group media chunk receive hardening */
    {
        cyxchat_group_media_test_result_t result;
        int ok = cyxchat_group_test_media_chunk_flow(&result);

        TEST_ASSERT(ok == 1, "Group media chunk test helper should run");
        TEST_ASSERT(result.metadata_prepared == 1,
                    "Metadata should prepare chunk receive state");
        TEST_ASSERT(result.duplicate_ignored == 1,
                    "Duplicate media chunks should not advance progress");
        TEST_ASSERT(result.missing_request_count == 1,
                    "Stalled receive should request the first missing chunk");
        TEST_ASSERT(result.completed == 1,
                    "Chunk assembly should deliver the original payload");
        TEST_ASSERT(result.completed_len == (CYXCHAT_CHUNK_SIZE * 2) + 5,
                    "Completion callback should report the full payload length");
        TEST_ASSERT(result.media_callback_count == 2,
                    "Media callback should fire for metadata and completion");
        TEST_ASSERT(result.progress_callback_count == 4,
                    "Progress should fire for prepare and each unique chunk");
        TEST_ASSERT(result.last_progress_done == 3 &&
                    result.last_progress_total == 3,
                    "Final progress should report all chunks received");
        TEST_ASSERT(result.error_callback_count == 0,
                    "Successful chunk flow should not emit errors");
    }

    return errors;
}
