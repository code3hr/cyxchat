/**
 * CyxChat Test - DNS Module
 */

#include <stdio.h>
#include <string.h>
#include <cyxchat/cyxchat.h>
#include <cyxchat/dns.h>

#define TEST_ASSERT(cond, msg) do { \
    if (!(cond)) { \
        printf("    ASSERT FAILED: %s\n", msg); \
        errors++; \
    } \
} while(0)

int test_dns(void) {
    int errors = 0;

    /* Test name validation - valid names */
    {
        TEST_ASSERT(cyxchat_dns_validate_name("alice") == 1, "Simple name should be valid");
        TEST_ASSERT(cyxchat_dns_validate_name("bob123") == 1, "Name with numbers should be valid");
        TEST_ASSERT(cyxchat_dns_validate_name("charlie_smith") == 1, "Name with underscore should be valid");
        TEST_ASSERT(cyxchat_dns_validate_name("abc") == 1, "3-char name should be valid");
        TEST_ASSERT(cyxchat_dns_validate_name("Alice") == 1, "Uppercase should be valid (will normalize)");
    }

    /* Test name validation - invalid names */
    {
        TEST_ASSERT(cyxchat_dns_validate_name("ab") == 0, "2-char name should be invalid");
        TEST_ASSERT(cyxchat_dns_validate_name("123abc") == 0, "Name starting with number should be invalid");
        TEST_ASSERT(cyxchat_dns_validate_name("_alice") == 0, "Name starting with underscore should be invalid");
        TEST_ASSERT(cyxchat_dns_validate_name("alice_") == 0, "Name ending with underscore should be invalid");
        TEST_ASSERT(cyxchat_dns_validate_name("alice__bob") == 0, "Consecutive underscores should be invalid");
        TEST_ASSERT(cyxchat_dns_validate_name("alice@bob") == 0, "Special chars should be invalid");
        TEST_ASSERT(cyxchat_dns_validate_name("") == 0, "Empty name should be invalid");
        TEST_ASSERT(cyxchat_dns_validate_name(NULL) == 0, "NULL name should be invalid");
    }

    /* Test name validation with .cyx suffix */
    {
        TEST_ASSERT(cyxchat_dns_validate_name("alice.cyx") == 1, "Name with .cyx suffix should be valid");
        TEST_ASSERT(cyxchat_dns_validate_name("bob123.cyx") == 1, "Name with suffix and numbers should be valid");
    }

    /* Test name normalization */
    {
        char out[64];
        cyxchat_error_t err;

        err = cyxchat_dns_normalize_name("Alice", out, sizeof(out));
        TEST_ASSERT(err == CYXCHAT_OK, "Normalize should succeed");
        TEST_ASSERT(strcmp(out, "alice") == 0, "Should lowercase");

        err = cyxchat_dns_normalize_name("BOB.cyx", out, sizeof(out));
        TEST_ASSERT(err == CYXCHAT_OK, "Normalize with suffix should succeed");
        TEST_ASSERT(strcmp(out, "bob") == 0, "Should strip suffix and lowercase");

        err = cyxchat_dns_normalize_name("CHARLIE.CYX", out, sizeof(out));
        TEST_ASSERT(err == CYXCHAT_OK, "Normalize with uppercase suffix should succeed");
        TEST_ASSERT(strcmp(out, "charlie") == 0, "Should strip suffix and lowercase");
    }

    /* Test crypto-name detection */
    /* Note: Base32 uses a-z and 2-7 (no 0, 1, 8, 9) */
    {
        TEST_ASSERT(cyxchat_dns_is_crypto_name("abcd2345") == 1, "8-char base32 should be crypto-name");
        TEST_ASSERT(cyxchat_dns_is_crypto_name("abcd2345.cyx") == 1, "Crypto-name with suffix should match");
        TEST_ASSERT(cyxchat_dns_is_crypto_name("k5xq3v7b") == 1, "Valid base32 should be crypto-name");
        TEST_ASSERT(cyxchat_dns_is_crypto_name("alice") == 0, "5-char name should not be crypto-name");
        TEST_ASSERT(cyxchat_dns_is_crypto_name("alice_bob") == 0, "Name with underscore should not be crypto-name");
        TEST_ASSERT(cyxchat_dns_is_crypto_name("abcd23456") == 0, "9-char name should not be crypto-name");
        TEST_ASSERT(cyxchat_dns_is_crypto_name("abcd234") == 0, "7-char name should not be crypto-name");
        TEST_ASSERT(cyxchat_dns_is_crypto_name("abcd1234") == 0, "Name with 1 should not be crypto-name (1 not in base32)");
    }

    /* Test crypto-name generation */
    {
        uint8_t pubkey1[32] = {0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
                               0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F, 0x10,
                               0x11, 0x12, 0x13, 0x14, 0x15, 0x16, 0x17, 0x18,
                               0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F, 0x20};
        uint8_t pubkey2[32] = {0xFF, 0xFE, 0xFD, 0xFC, 0xFB, 0xFA, 0xF9, 0xF8,
                               0xF7, 0xF6, 0xF5, 0xF4, 0xF3, 0xF2, 0xF1, 0xF0,
                               0xEF, 0xEE, 0xED, 0xEC, 0xEB, 0xEA, 0xE9, 0xE8,
                               0xE7, 0xE6, 0xE5, 0xE4, 0xE3, 0xE2, 0xE1, 0xE0};
        char name1[20], name2[20], name1b[20];

        cyxchat_dns_crypto_name(pubkey1, name1);
        cyxchat_dns_crypto_name(pubkey2, name2);
        cyxchat_dns_crypto_name(pubkey1, name1b);

        TEST_ASSERT(strlen(name1) == 8, "Crypto-name should be 8 chars");
        TEST_ASSERT(strlen(name2) == 8, "Crypto-name should be 8 chars");
        TEST_ASSERT(strcmp(name1, name2) != 0, "Different keys should give different names");
        TEST_ASSERT(strcmp(name1, name1b) == 0, "Same key should give same name");
        TEST_ASSERT(cyxchat_dns_is_crypto_name(name1) == 1, "Generated name should be valid crypto-name");
    }

    /* Test DNS context creation and destruction */
    {
        cyxchat_dns_ctx_t *ctx = NULL;
        cyxwiz_node_id_t local_id;
        memset(&local_id, 0xAB, sizeof(local_id));

        cyxchat_error_t err = cyxchat_dns_create(&ctx, NULL, &local_id, NULL);
        TEST_ASSERT(err == CYXCHAT_OK, "DNS create should succeed");
        TEST_ASSERT(ctx != NULL, "Context should not be NULL");

        /* Should have no registered name initially */
        const char *name = cyxchat_dns_get_registered_name(ctx);
        TEST_ASSERT(name == NULL, "Should have no registered name initially");

        cyxchat_dns_destroy(ctx);
    }

    /* Test DNS context with NULL parameters */
    {
        cyxchat_dns_ctx_t *ctx = NULL;
        cyxwiz_node_id_t local_id;

        cyxchat_error_t err = cyxchat_dns_create(NULL, NULL, &local_id, NULL);
        TEST_ASSERT(err == CYXCHAT_ERR_NULL, "NULL ctx_out should fail");

        err = cyxchat_dns_create(&ctx, NULL, NULL, NULL);
        TEST_ASSERT(err == CYXCHAT_ERR_NULL, "NULL local_id should fail");
    }

    /* Test petname management */
    {
        cyxchat_dns_ctx_t *ctx = NULL;
        cyxwiz_node_id_t local_id, peer_id1, peer_id2;
        memset(&local_id, 0xAA, sizeof(local_id));
        memset(&peer_id1, 0xBB, sizeof(peer_id1));
        memset(&peer_id2, 0xCC, sizeof(peer_id2));

        cyxchat_error_t err = cyxchat_dns_create(&ctx, NULL, &local_id, NULL);
        TEST_ASSERT(err == CYXCHAT_OK, "DNS create should succeed");

        /* Set petname */
        err = cyxchat_dns_set_petname(ctx, &peer_id1, "friend1");
        TEST_ASSERT(err == CYXCHAT_OK, "Set petname should succeed");

        err = cyxchat_dns_set_petname(ctx, &peer_id2, "friend2");
        TEST_ASSERT(err == CYXCHAT_OK, "Set second petname should succeed");

        /* Get petname */
        const char *pet1 = cyxchat_dns_get_petname(ctx, &peer_id1);
        TEST_ASSERT(pet1 != NULL, "Should get petname for peer1");
        TEST_ASSERT(strcmp(pet1, "friend1") == 0, "Petname should match");

        const char *pet2 = cyxchat_dns_get_petname(ctx, &peer_id2);
        TEST_ASSERT(pet2 != NULL, "Should get petname for peer2");
        TEST_ASSERT(strcmp(pet2, "friend2") == 0, "Petname should match");

        /* Resolve petname to node ID */
        cyxwiz_node_id_t resolved;
        err = cyxchat_dns_resolve_petname(ctx, "friend1", &resolved);
        TEST_ASSERT(err == CYXCHAT_OK, "Resolve petname should succeed");
        TEST_ASSERT(memcmp(&resolved, &peer_id1, sizeof(cyxwiz_node_id_t)) == 0, "Resolved ID should match");

        /* Non-existent petname */
        err = cyxchat_dns_resolve_petname(ctx, "unknown", &resolved);
        TEST_ASSERT(err == CYXCHAT_ERR_NOT_FOUND, "Non-existent petname should fail");

        /* Remove petname */
        err = cyxchat_dns_set_petname(ctx, &peer_id1, NULL);
        TEST_ASSERT(err == CYXCHAT_OK, "Remove petname should succeed");

        pet1 = cyxchat_dns_get_petname(ctx, &peer_id1);
        TEST_ASSERT(pet1 == NULL, "Removed petname should be NULL");

        cyxchat_dns_destroy(ctx);
    }

    /* Test cache operations */
    {
        cyxchat_dns_ctx_t *ctx = NULL;
        cyxwiz_node_id_t local_id;
        memset(&local_id, 0xDD, sizeof(local_id));

        cyxchat_error_t err = cyxchat_dns_create(&ctx, NULL, &local_id, NULL);
        TEST_ASSERT(err == CYXCHAT_OK, "DNS create should succeed");

        /* Check cache for non-existent name */
        TEST_ASSERT(cyxchat_dns_is_cached(ctx, "unknown") == 0, "Unknown name should not be cached");

        /* Resolve non-existent name */
        cyxchat_dns_record_t record;
        err = cyxchat_dns_resolve(ctx, "unknown", &record);
        TEST_ASSERT(err == CYXCHAT_ERR_NOT_FOUND, "Resolve unknown should fail");

        /* Invalidate non-existent cache entry (should not crash) */
        cyxchat_dns_invalidate(ctx, "unknown");

        cyxchat_dns_destroy(ctx);
    }

    /* Test DNS statistics */
    {
        cyxchat_dns_ctx_t *ctx = NULL;
        cyxwiz_node_id_t local_id;
        memset(&local_id, 0xEE, sizeof(local_id));

        cyxchat_error_t err = cyxchat_dns_create(&ctx, NULL, &local_id, NULL);
        TEST_ASSERT(err == CYXCHAT_OK, "DNS create should succeed");

        cyxchat_dns_stats_t stats;
        cyxchat_dns_get_stats(ctx, &stats);

        TEST_ASSERT(stats.cache_entries == 0, "Initial cache should be empty");
        TEST_ASSERT(stats.cache_hits == 0, "Initial cache hits should be 0");
        TEST_ASSERT(stats.lookups_sent == 0, "Initial lookups should be 0");

        cyxchat_dns_destroy(ctx);
    }

    /* Test DNS poll (should not crash with no transport) */
    {
        cyxchat_dns_ctx_t *ctx = NULL;
        cyxwiz_node_id_t local_id;
        memset(&local_id, 0xFF, sizeof(local_id));

        cyxchat_error_t err = cyxchat_dns_create(&ctx, NULL, &local_id, NULL);
        TEST_ASSERT(err == CYXCHAT_OK, "DNS create should succeed");

        /* Poll should work even without transport */
        err = cyxchat_dns_poll(ctx, 1000);
        TEST_ASSERT(err == CYXCHAT_OK, "Poll should succeed");

        err = cyxchat_dns_poll(ctx, 2000);
        TEST_ASSERT(err == CYXCHAT_OK, "Poll should succeed again");

        cyxchat_dns_destroy(ctx);
    }

    /* Test crypto-name parsing */
    {
        cyxwiz_node_id_t id1, id2;

        cyxchat_error_t err = cyxchat_dns_parse_crypto_name("abcd2345", &id1);
        TEST_ASSERT(err == CYXCHAT_OK, "Parse valid crypto-name should succeed");

        err = cyxchat_dns_parse_crypto_name("abcd2345.cyx", &id2);
        TEST_ASSERT(err == CYXCHAT_OK, "Parse crypto-name with suffix should succeed");

        /* Same name should give same ID */
        err = cyxchat_dns_parse_crypto_name("abcd2345", &id2);
        TEST_ASSERT(err == CYXCHAT_OK, "Parse should succeed");
        TEST_ASSERT(memcmp(&id1, &id2, sizeof(cyxwiz_node_id_t)) == 0, "Same name should give same ID");

        /* Invalid crypto-name should fail */
        err = cyxchat_dns_parse_crypto_name("alice", &id1);
        TEST_ASSERT(err == CYXCHAT_ERR_INVALID, "Parse non-crypto-name should fail");
    }

    return errors;
}
