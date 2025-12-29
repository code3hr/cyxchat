/**
 * CyxChat - Privacy-First Messaging Library
 *
 * Main header file - includes all CyxChat APIs
 *
 * Usage:
 *   #include <cyxchat/cyxchat.h>
 *
 * Link with: -lcyxchat -lcyxwiz -lsodium
 */

#ifndef CYXCHAT_H
#define CYXCHAT_H

/* Core types and constants */
#include "types.h"

/* Chat API (direct messaging) */
#include "chat.h"

/* Contact management */
#include "contact.h"

/* Group chat */
#include "group.h"

/* File transfer */
#include "file.h"

/* Presence/status */
#include "presence.h"

#ifdef __cplusplus
extern "C" {
#endif

/* ============================================================
 * Library Version
 * ============================================================ */

#define CYXCHAT_VERSION_MAJOR   0
#define CYXCHAT_VERSION_MINOR   1
#define CYXCHAT_VERSION_PATCH   0
#define CYXCHAT_VERSION_STRING  "0.1.0"

/**
 * Get library version string
 */
CYXCHAT_API const char* cyxchat_version(void);

/**
 * Get library version components
 */
CYXCHAT_API void cyxchat_version_info(
    int *major,
    int *minor,
    int *patch
);

/* ============================================================
 * Library Initialization
 * ============================================================ */

/**
 * Initialize library (must be called first)
 *
 * @return CYXCHAT_OK on success
 */
CYXCHAT_API cyxchat_error_t cyxchat_init(void);

/**
 * Shutdown library (cleanup)
 */
CYXCHAT_API void cyxchat_shutdown(void);

/**
 * Check if library is initialized
 */
CYXCHAT_API int cyxchat_is_initialized(void);

/* ============================================================
 * Error Handling
 * ============================================================ */

/**
 * Get error message for error code
 */
CYXCHAT_API const char* cyxchat_error_string(cyxchat_error_t error);

/**
 * Get last error code
 */
CYXCHAT_API cyxchat_error_t cyxchat_last_error(void);

/**
 * Get last error message
 */
CYXCHAT_API const char* cyxchat_last_error_message(void);

#ifdef __cplusplus
}
#endif

#endif /* CYXCHAT_H */
