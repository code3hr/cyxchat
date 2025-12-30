/**
 * CyxChat Test Suite - Main Entry Point
 */

#include <stdio.h>
#include <string.h>
#include <cyxchat/cyxchat.h>

/* Test declarations */
int test_chat(void);
int test_contact(void);
int test_group(void);
int test_dns(void);

/* Test runner */
typedef struct {
    const char *name;
    int (*func)(void);
} test_case_t;

static test_case_t tests[] = {
    { "chat",    test_chat },
    { "contact", test_contact },
    { "group",   test_group },
    { "dns",     test_dns },
    { NULL, NULL }
};

int main(int argc, char **argv) {
    printf("CyxChat Test Suite v%s\n", cyxchat_version());
    printf("================================\n\n");

    /* Initialize library */
    cyxchat_error_t err = cyxchat_init();
    if (err != CYXCHAT_OK) {
        printf("FATAL: Failed to initialize: %s\n", cyxchat_error_string(err));
        return 1;
    }

    int passed = 0;
    int failed = 0;

    /* Run specific test if provided */
    const char *filter = argc > 1 ? argv[1] : NULL;

    for (test_case_t *t = tests; t->name; t++) {
        if (filter && strcmp(filter, t->name) != 0) {
            continue;
        }

        printf("Running: %s\n", t->name);
        int result = t->func();

        if (result == 0) {
            printf("  PASSED\n\n");
            passed++;
        } else {
            printf("  FAILED (%d errors)\n\n", result);
            failed++;
        }
    }

    printf("================================\n");
    printf("Results: %d passed, %d failed\n", passed, failed);

    cyxchat_shutdown();

    return failed > 0 ? 1 : 0;
}
