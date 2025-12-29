/**
 * CyxChat Library Main
 * Library initialization and error handling
 */

#include <cyxchat/cyxchat.h>
#include <cyxwiz/crypto.h>
#include <cyxwiz/memory.h>
#include <string.h>
#include <stdlib.h>
#include <stdio.h>

/* ============================================================
 * Global State
 * ============================================================ */

static int g_initialized = 0;
static cyxchat_error_t g_last_error = CYXCHAT_OK;
static char g_last_error_msg[256] = {0};

/* ============================================================
 * Version Info
 * ============================================================ */

const char* cyxchat_version(void) {
    return CYXCHAT_VERSION_STRING;
}

void cyxchat_version_info(int *major, int *minor, int *patch) {
    if (major) *major = CYXCHAT_VERSION_MAJOR;
    if (minor) *minor = CYXCHAT_VERSION_MINOR;
    if (patch) *patch = CYXCHAT_VERSION_PATCH;
}

/* ============================================================
 * Library Initialization
 * ============================================================ */

cyxchat_error_t cyxchat_init(void) {
    if (g_initialized) {
        return CYXCHAT_OK;
    }

    /* Initialize libsodium via cyxwiz */
    if (cyxwiz_crypto_init() != 0) {
        g_last_error = CYXCHAT_ERR_CRYPTO;
        snprintf(g_last_error_msg, sizeof(g_last_error_msg),
                 "Failed to initialize crypto library");
        return CYXCHAT_ERR_CRYPTO;
    }

    g_initialized = 1;
    return CYXCHAT_OK;
}

void cyxchat_shutdown(void) {
    if (!g_initialized) {
        return;
    }

    /* Clear global state */
    g_last_error = CYXCHAT_OK;
    memset(g_last_error_msg, 0, sizeof(g_last_error_msg));

    g_initialized = 0;
}

int cyxchat_is_initialized(void) {
    return g_initialized;
}

/* ============================================================
 * Error Handling
 * ============================================================ */

static const char* error_strings[] = {
    "Success",                          /* CYXCHAT_OK = 0 */
    "Null pointer",                     /* CYXCHAT_ERR_NULL = -1 */
    "Memory allocation failed",         /* CYXCHAT_ERR_MEMORY = -2 */
    "Invalid parameter",                /* CYXCHAT_ERR_INVALID = -3 */
    "Not found",                        /* CYXCHAT_ERR_NOT_FOUND = -4 */
    "Already exists",                   /* CYXCHAT_ERR_EXISTS = -5 */
    "Container full",                   /* CYXCHAT_ERR_FULL = -6 */
    "Crypto operation failed",          /* CYXCHAT_ERR_CRYPTO = -7 */
    "Network error",                    /* CYXCHAT_ERR_NETWORK = -8 */
    "Operation timed out",              /* CYXCHAT_ERR_TIMEOUT = -9 */
    "User is blocked",                  /* CYXCHAT_ERR_BLOCKED = -10 */
    "Not a group member",               /* CYXCHAT_ERR_NOT_MEMBER = -11 */
    "Not a group admin",                /* CYXCHAT_ERR_NOT_ADMIN = -12 */
    "File too large",                   /* CYXCHAT_ERR_FILE_TOO_LARGE = -13 */
    "File transfer error"               /* CYXCHAT_ERR_TRANSFER = -14 */
};

const char* cyxchat_error_string(cyxchat_error_t error) {
    if (error == CYXCHAT_OK) {
        return error_strings[0];
    }

    int idx = -error;
    if (idx > 0 && idx <= 14) {
        return error_strings[idx];
    }

    return "Unknown error";
}

cyxchat_error_t cyxchat_last_error(void) {
    return g_last_error;
}

const char* cyxchat_last_error_message(void) {
    if (g_last_error_msg[0]) {
        return g_last_error_msg;
    }
    return cyxchat_error_string(g_last_error);
}

/* ============================================================
 * Internal Error Setter (used by other modules)
 * ============================================================ */

void cyxchat_set_error(cyxchat_error_t error, const char *msg) {
    g_last_error = error;
    if (msg) {
        strncpy(g_last_error_msg, msg, sizeof(g_last_error_msg) - 1);
        g_last_error_msg[sizeof(g_last_error_msg) - 1] = '\0';
    } else {
        g_last_error_msg[0] = '\0';
    }
}
