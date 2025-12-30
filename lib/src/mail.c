/**
 * CyxChat Mail Implementation
 * Decentralized email functionality (CyxMail)
 */

#ifdef _MSC_VER
#define _CRT_SECURE_NO_WARNINGS
#endif

#include <cyxchat/mail.h>
#include <cyxchat/chat.h>
#include <cyxwiz/memory.h>
#include <cyxwiz/log.h>
#include <cyxwiz/types.h>

#include <string.h>
#include <stdlib.h>
#include <stdio.h>

#ifdef CYXWIZ_HAS_CRYPTO
#include <sodium.h>
#endif

#include <time.h>

#ifdef _WIN32
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#endif

/* ============================================================
 * Internal Constants
 * ============================================================ */

#define MAIL_MAX_STORED         256     /* Max stored emails */
#define MAIL_MAX_PENDING        16      /* Max pending sends */
#define MAIL_RETRY_INTERVAL_MS  30000   /* Retry interval */
#define MAIL_RETRY_MAX          3       /* Max retries */

/* ============================================================
 * Internal Types
 * ============================================================ */

/* Pending send */
typedef struct {
    cyxchat_mail_t *mail;
    uint64_t start_time;
    uint64_t last_retry;
    int retries;
    int active;
} mail_pending_send_t;

/* Mail context */
struct cyxchat_mail_ctx {
    cyxchat_ctx_t *chat_ctx;
    cyxwiz_node_id_t local_id;
    uint8_t signing_key[64];        /* Ed25519 secret + public */

    /* Stored mail */
    cyxchat_mail_t *stored[MAIL_MAX_STORED];
    size_t stored_count;

    /* Pending sends */
    mail_pending_send_t pending[MAIL_MAX_PENDING];

    /* Callbacks */
    cyxchat_on_mail_received_t on_received;
    void *on_received_data;

    cyxchat_on_mail_sent_t on_sent;
    void *on_sent_data;

    cyxchat_on_mail_read_t on_read;
    void *on_read_data;

    cyxchat_on_mail_bounce_t on_bounce;
    void *on_bounce_data;
};

/* ============================================================
 * Helper Functions
 * ============================================================ */

static uint64_t get_time_ms(void)
{
#ifdef _WIN32
    return GetTickCount64();
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

static uint64_t get_unix_time_ms(void)
{
#ifdef _WIN32
    FILETIME ft;
    GetSystemTimeAsFileTime(&ft);
    uint64_t t = ((uint64_t)ft.dwHighDateTime << 32) | ft.dwLowDateTime;
    return (t - 116444736000000000ULL) / 10000;
#else
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    return (uint64_t)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
#endif
}

/* Find stored mail by ID */
static cyxchat_mail_t* find_mail(cyxchat_mail_ctx_t *ctx, const cyxchat_mail_id_t *mail_id)
{
    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i] &&
            memcmp(ctx->stored[i]->mail_id.bytes, mail_id->bytes, CYXCHAT_MAIL_ID_SIZE) == 0) {
            return ctx->stored[i];
        }
    }
    return NULL;
}

/* Find free storage slot */
static size_t find_free_slot(cyxchat_mail_ctx_t *ctx)
{
    for (size_t i = 0; i < MAIL_MAX_STORED; i++) {
        if (!ctx->stored[i]) {
            return i;
        }
    }
    return MAIL_MAX_STORED; /* No free slot */
}

/* Store mail internally */
static cyxchat_error_t store_mail(cyxchat_mail_ctx_t *ctx, cyxchat_mail_t *mail)
{
    size_t slot = find_free_slot(ctx);
    if (slot >= MAIL_MAX_STORED) {
        return CYXCHAT_ERR_FULL;
    }

    ctx->stored[slot] = mail;
    if (slot >= ctx->stored_count) {
        ctx->stored_count = slot + 1;
    }
    return CYXCHAT_OK;
}

/* Remove mail from storage */
static void remove_mail(cyxchat_mail_ctx_t *ctx, const cyxchat_mail_id_t *mail_id)
{
    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i] &&
            memcmp(ctx->stored[i]->mail_id.bytes, mail_id->bytes, CYXCHAT_MAIL_ID_SIZE) == 0) {
            cyxchat_mail_free(ctx->stored[i]);
            ctx->stored[i] = NULL;
            break;
        }
    }
}

/* Find pending send slot */
static mail_pending_send_t* find_pending_slot(cyxchat_mail_ctx_t *ctx)
{
    for (size_t i = 0; i < MAIL_MAX_PENDING; i++) {
        if (!ctx->pending[i].active) {
            return &ctx->pending[i];
        }
    }
    return NULL;
}

/* Sign mail */
static cyxchat_error_t sign_mail(cyxchat_mail_ctx_t *ctx, cyxchat_mail_t *mail)
{
#ifdef CYXWIZ_HAS_CRYPTO
    /* Build message for signing: mail_id + subject + body */
    uint8_t to_sign[CYXCHAT_MAIL_ID_SIZE + CYXCHAT_MAX_SUBJECT_LEN + 256];
    size_t to_sign_len = 0;

    memcpy(to_sign + to_sign_len, mail->mail_id.bytes, CYXCHAT_MAIL_ID_SIZE);
    to_sign_len += CYXCHAT_MAIL_ID_SIZE;

    size_t subj_len = strlen(mail->subject);
    memcpy(to_sign + to_sign_len, mail->subject, subj_len);
    to_sign_len += subj_len;

    /* Include first 256 bytes of body */
    size_t body_preview = mail->body_len > 256 ? 256 : mail->body_len;
    if (mail->body && body_preview > 0) {
        memcpy(to_sign + to_sign_len, mail->body, body_preview);
        to_sign_len += body_preview;
    }

    /* Sign with Ed25519 */
    if (crypto_sign_detached(mail->signature, NULL, to_sign, to_sign_len,
                             ctx->signing_key) != 0) {
        return CYXCHAT_ERR_CRYPTO;
    }
    return CYXCHAT_OK;
#else
    CYXWIZ_UNUSED(ctx);
    memset(mail->signature, 0, 64);
    return CYXCHAT_OK;
#endif
}

/* Verify mail signature */
static int verify_mail_signature(const cyxchat_mail_t *mail)
{
#ifdef CYXWIZ_HAS_CRYPTO
    /* Build message for verification */
    uint8_t to_verify[CYXCHAT_MAIL_ID_SIZE + CYXCHAT_MAX_SUBJECT_LEN + 256];
    size_t to_verify_len = 0;

    memcpy(to_verify + to_verify_len, mail->mail_id.bytes, CYXCHAT_MAIL_ID_SIZE);
    to_verify_len += CYXCHAT_MAIL_ID_SIZE;

    size_t subj_len = strlen(mail->subject);
    memcpy(to_verify + to_verify_len, mail->subject, subj_len);
    to_verify_len += subj_len;

    size_t body_preview = mail->body_len > 256 ? 256 : mail->body_len;
    if (mail->body && body_preview > 0) {
        memcpy(to_verify + to_verify_len, mail->body, body_preview);
        to_verify_len += body_preview;
    }

    /* Verify Ed25519 signature against sender's public key */
    return crypto_sign_verify_detached(mail->signature, to_verify, to_verify_len,
                                       mail->from.node_id.bytes) == 0;
#else
    CYXWIZ_UNUSED(mail);
    return 1;  /* No crypto, assume valid */
#endif
}

/* ============================================================
 * Initialization
 * ============================================================ */

cyxchat_error_t cyxchat_mail_ctx_create(
    cyxchat_mail_ctx_t **ctx,
    cyxchat_ctx_t *chat_ctx
) {
    if (!ctx || !chat_ctx) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_ctx_t *c = calloc(1, sizeof(cyxchat_mail_ctx_t));
    if (!c) {
        return CYXCHAT_ERR_MEMORY;
    }

    c->chat_ctx = chat_ctx;

    /* Copy local ID from chat context */
    const cyxwiz_node_id_t *local_id = cyxchat_get_local_id(chat_ctx);
    if (local_id) {
        memcpy(&c->local_id, local_id, sizeof(cyxwiz_node_id_t));
    }

#ifdef CYXWIZ_HAS_CRYPTO
    /* Generate signing keypair */
    crypto_sign_keypair(c->signing_key + 32, c->signing_key);
#endif

    *ctx = c;
    return CYXCHAT_OK;
}

void cyxchat_mail_ctx_destroy(cyxchat_mail_ctx_t *ctx)
{
    if (!ctx) return;

    /* Free stored mail */
    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i]) {
            cyxchat_mail_free(ctx->stored[i]);
        }
    }

    /* Free pending sends */
    for (size_t i = 0; i < MAIL_MAX_PENDING; i++) {
        if (ctx->pending[i].active && ctx->pending[i].mail) {
            cyxchat_mail_free(ctx->pending[i].mail);
        }
    }

    /* Secure zero and free */
    cyxwiz_secure_zero(ctx, sizeof(cyxchat_mail_ctx_t));
    free(ctx);
}

int cyxchat_mail_poll(cyxchat_mail_ctx_t *ctx, uint64_t now_ms)
{
    if (!ctx) return 0;

    int events = 0;

    /* Check pending sends for retries */
    for (size_t i = 0; i < MAIL_MAX_PENDING; i++) {
        mail_pending_send_t *pending = &ctx->pending[i];
        if (!pending->active) continue;

        /* Check for timeout/retry */
        if (now_ms - pending->last_retry > MAIL_RETRY_INTERVAL_MS) {
            if (pending->retries >= MAIL_RETRY_MAX) {
                /* Max retries exceeded - bounce */
                if (pending->mail) {
                    pending->mail->status = CYXCHAT_MAIL_STATUS_FAILED;

                    if (ctx->on_bounce) {
                        ctx->on_bounce(ctx, &pending->mail->mail_id,
                                       CYXCHAT_BOUNCE_TIMEOUT,
                                       "Max retries exceeded",
                                       ctx->on_bounce_data);
                    }

                    /* Move to sent folder with failed status */
                    pending->mail->folder_type = CYXCHAT_FOLDER_SENT;
                    store_mail(ctx, pending->mail);
                    pending->mail = NULL;
                }

                pending->active = 0;
                events++;
            } else {
                /* Retry send */
                pending->retries++;
                pending->last_retry = now_ms;
                /* TODO: Actually resend via onion */
                events++;
            }
        }
    }

    return events;
}

/* ============================================================
 * Composing Mail
 * ============================================================ */

cyxchat_error_t cyxchat_mail_create(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_mail_t **mail_out
) {
    if (!ctx || !mail_out) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *mail = calloc(1, sizeof(cyxchat_mail_t));
    if (!mail) {
        return CYXCHAT_ERR_MEMORY;
    }

    /* Generate mail ID */
    cyxchat_mail_generate_id(&mail->mail_id);

    /* Set from address */
    memcpy(&mail->from.node_id, &ctx->local_id, sizeof(cyxwiz_node_id_t));

    /* Initialize as draft */
    mail->status = CYXCHAT_MAIL_STATUS_DRAFT;
    mail->folder_type = CYXCHAT_FOLDER_DRAFTS;
    mail->timestamp = get_unix_time_ms();

    *mail_out = mail;
    return CYXCHAT_OK;
}

void cyxchat_mail_free(cyxchat_mail_t *mail)
{
    if (!mail) return;

    /* Free body */
    if (mail->body) {
        cyxwiz_secure_zero(mail->body, mail->body_len);
        free(mail->body);
    }

    /* Free attachments */
    if (mail->attachments) {
        for (int i = 0; i < mail->attachment_count; i++) {
            if (mail->attachments[i].inline_data) {
                cyxwiz_secure_zero(mail->attachments[i].inline_data,
                                   mail->attachments[i].inline_len);
                free(mail->attachments[i].inline_data);
            }
        }
        free(mail->attachments);
    }

    /* Secure zero and free */
    cyxwiz_secure_zero(mail, sizeof(cyxchat_mail_t));
    free(mail);
}

cyxchat_error_t cyxchat_mail_add_to(
    cyxchat_mail_t *mail,
    const cyxwiz_node_id_t *to,
    const char *display_name
) {
    if (!mail || !to) {
        return CYXCHAT_ERR_NULL;
    }

    if (mail->to_count >= CYXCHAT_MAX_RECIPIENTS) {
        return CYXCHAT_ERR_FULL;
    }

    cyxchat_mail_addr_t *addr = &mail->to[mail->to_count];
    memcpy(&addr->node_id, to, sizeof(cyxwiz_node_id_t));

    if (display_name) {
        strncpy(addr->display_name, display_name, CYXCHAT_MAX_DISPLAY_NAME - 1);
        addr->display_name[CYXCHAT_MAX_DISPLAY_NAME - 1] = '\0';
    }

    mail->to_count++;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_add_cc(
    cyxchat_mail_t *mail,
    const cyxwiz_node_id_t *cc,
    const char *display_name
) {
    if (!mail || !cc) {
        return CYXCHAT_ERR_NULL;
    }

    if (mail->cc_count >= CYXCHAT_MAX_RECIPIENTS) {
        return CYXCHAT_ERR_FULL;
    }

    cyxchat_mail_addr_t *addr = &mail->cc[mail->cc_count];
    memcpy(&addr->node_id, cc, sizeof(cyxwiz_node_id_t));

    if (display_name) {
        strncpy(addr->display_name, display_name, CYXCHAT_MAX_DISPLAY_NAME - 1);
        addr->display_name[CYXCHAT_MAX_DISPLAY_NAME - 1] = '\0';
    }

    mail->cc_count++;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_set_subject(
    cyxchat_mail_t *mail,
    const char *subject
) {
    if (!mail || !subject) {
        return CYXCHAT_ERR_NULL;
    }

    strncpy(mail->subject, subject, CYXCHAT_MAX_SUBJECT_LEN - 1);
    mail->subject[CYXCHAT_MAX_SUBJECT_LEN - 1] = '\0';
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_set_body(
    cyxchat_mail_t *mail,
    const char *body,
    size_t body_len
) {
    if (!mail || !body) {
        return CYXCHAT_ERR_NULL;
    }

    if (body_len > CYXCHAT_MAX_MAIL_BODY_LEN) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Free existing body */
    if (mail->body) {
        cyxwiz_secure_zero(mail->body, mail->body_len);
        free(mail->body);
    }

    mail->body = malloc(body_len + 1);
    if (!mail->body) {
        return CYXCHAT_ERR_MEMORY;
    }

    memcpy(mail->body, body, body_len);
    mail->body[body_len] = '\0';
    mail->body_len = body_len;

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_set_reply_to(
    cyxchat_mail_t *mail,
    const cyxchat_mail_id_t *in_reply_to
) {
    if (!mail || !in_reply_to) {
        return CYXCHAT_ERR_NULL;
    }

    memcpy(&mail->in_reply_to, in_reply_to, sizeof(cyxchat_mail_id_t));

    /* Thread ID is the original mail's thread ID or mail ID */
    if (cyxchat_mail_id_is_null(&mail->thread_id)) {
        memcpy(&mail->thread_id, in_reply_to, sizeof(cyxchat_mail_id_t));
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_add_attachment(
    cyxchat_mail_t *mail,
    const char *filename,
    const char *mime_type,
    const uint8_t *data,
    size_t data_len,
    cyxchat_attach_disposition_t disposition,
    const char *content_id
) {
    if (!mail || !filename || !data) {
        return CYXCHAT_ERR_NULL;
    }

    if (mail->attachment_count >= CYXCHAT_MAX_ATTACHMENTS) {
        return CYXCHAT_ERR_FULL;
    }

    /* Allocate attachments array if needed */
    if (!mail->attachments) {
        mail->attachments = calloc(CYXCHAT_MAX_ATTACHMENTS,
                                   sizeof(cyxchat_mail_attachment_t));
        if (!mail->attachments) {
            return CYXCHAT_ERR_MEMORY;
        }
    }

    cyxchat_mail_attachment_t *attach = &mail->attachments[mail->attachment_count];

    /* Generate file ID */
#ifdef CYXWIZ_HAS_CRYPTO
    randombytes_buf(attach->file_id.bytes, CYXCHAT_FILE_ID_SIZE);
#else
    for (int i = 0; i < CYXCHAT_FILE_ID_SIZE; i++) {
        attach->file_id.bytes[i] = (uint8_t)(rand() & 0xFF);
    }
#endif

    strncpy(attach->filename, filename, CYXCHAT_MAX_FILENAME - 1);
    attach->filename[CYXCHAT_MAX_FILENAME - 1] = '\0';

    if (mime_type) {
        strncpy(attach->mime_type, mime_type, sizeof(attach->mime_type) - 1);
    } else {
        strcpy(attach->mime_type, "application/octet-stream");
    }

    attach->size = (uint32_t)data_len;
    attach->disposition = (uint8_t)disposition;

    if (content_id) {
        strncpy(attach->content_id, content_id, sizeof(attach->content_id) - 1);
    }

    /* Compute hash */
#ifdef CYXWIZ_HAS_CRYPTO
    crypto_generichash(attach->file_hash, 32, data, data_len, NULL, 0);
#else
    memset(attach->file_hash, 0, 32);
#endif

    /* Determine storage type and store data */
    if (data_len <= CYXCHAT_ATTACHMENT_INLINE_MAX) {
        /* Inline storage */
        attach->storage_type = CYXCHAT_ATTACH_STORAGE_INLINE;
        attach->inline_data = malloc(data_len);
        if (!attach->inline_data) {
            return CYXCHAT_ERR_MEMORY;
        }
        memcpy(attach->inline_data, data, data_len);
        attach->inline_len = data_len;
    } else {
        /* Chunked transfer will be used */
        attach->storage_type = CYXCHAT_ATTACH_STORAGE_CHUNKED;
        /* Data will be sent via file transfer protocol */
    }

    mail->attachment_count++;
    mail->flags |= CYXCHAT_MAIL_FLAG_ATTACHMENT;

    return CYXCHAT_OK;
}

/* ============================================================
 * Sending Mail
 * ============================================================ */

cyxchat_error_t cyxchat_mail_send(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_mail_t *mail
) {
    if (!ctx || !mail) {
        return CYXCHAT_ERR_NULL;
    }

    if (mail->to_count == 0) {
        return CYXCHAT_ERR_INVALID;
    }

    /* Sign mail */
    cyxchat_error_t err = sign_mail(ctx, mail);
    if (err != CYXCHAT_OK) {
        return err;
    }

    /* Update status */
    mail->status = CYXCHAT_MAIL_STATUS_QUEUED;
    mail->timestamp = get_unix_time_ms();

    /* Find pending slot */
    mail_pending_send_t *pending = find_pending_slot(ctx);
    if (!pending) {
        return CYXCHAT_ERR_FULL;
    }

    /* Queue for sending */
    pending->mail = mail;
    pending->start_time = get_time_ms();
    pending->last_retry = pending->start_time;
    pending->retries = 0;
    pending->active = 1;

    /* TODO: Actually send via onion routing */
    /* For now, simulate immediate send */
    mail->status = CYXCHAT_MAIL_STATUS_SENT;
    mail->folder_type = CYXCHAT_FOLDER_SENT;

    /* Notify callback */
    if (ctx->on_sent) {
        ctx->on_sent(ctx, &mail->mail_id, mail->status, ctx->on_sent_data);
    }

    /* Move to sent folder */
    pending->active = 0;
    store_mail(ctx, mail);

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_send_simple(
    cyxchat_mail_ctx_t *ctx,
    const cyxwiz_node_id_t *to,
    const char *subject,
    const char *body,
    const cyxchat_mail_id_t *in_reply_to,
    cyxchat_mail_id_t *mail_id_out
) {
    if (!ctx || !to || !subject || !body) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *mail;
    cyxchat_error_t err = cyxchat_mail_create(ctx, &mail);
    if (err != CYXCHAT_OK) {
        return err;
    }

    err = cyxchat_mail_add_to(mail, to, NULL);
    if (err != CYXCHAT_OK) {
        cyxchat_mail_free(mail);
        return err;
    }

    err = cyxchat_mail_set_subject(mail, subject);
    if (err != CYXCHAT_OK) {
        cyxchat_mail_free(mail);
        return err;
    }

    err = cyxchat_mail_set_body(mail, body, strlen(body));
    if (err != CYXCHAT_OK) {
        cyxchat_mail_free(mail);
        return err;
    }

    if (in_reply_to) {
        cyxchat_mail_set_reply_to(mail, in_reply_to);
    }

    if (mail_id_out) {
        memcpy(mail_id_out, &mail->mail_id, sizeof(cyxchat_mail_id_t));
    }

    return cyxchat_mail_send(ctx, mail);
}

cyxchat_error_t cyxchat_mail_save_draft(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_mail_t *mail
) {
    if (!ctx || !mail) {
        return CYXCHAT_ERR_NULL;
    }

    mail->status = CYXCHAT_MAIL_STATUS_DRAFT;
    mail->folder_type = CYXCHAT_FOLDER_DRAFTS;
    mail->flags |= CYXCHAT_MAIL_FLAG_DRAFT;

    return store_mail(ctx, mail);
}

/* ============================================================
 * Receiving/Querying Mail
 * ============================================================ */

cyxchat_error_t cyxchat_mail_get(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    cyxchat_mail_t **mail_out
) {
    if (!ctx || !mail_id || !mail_out) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *found = find_mail(ctx, mail_id);
    if (!found) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* Return pointer to stored mail */
    *mail_out = found;
    return CYXCHAT_OK;
}

size_t cyxchat_mail_count(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_folder_type_t folder
) {
    if (!ctx) return 0;

    size_t count = 0;
    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i] && ctx->stored[i]->folder_type == folder) {
            count++;
        }
    }
    return count;
}

size_t cyxchat_mail_unread_count(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_folder_type_t folder
) {
    if (!ctx) return 0;

    size_t count = 0;
    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i] &&
            ctx->stored[i]->folder_type == folder &&
            !(ctx->stored[i]->flags & CYXCHAT_MAIL_FLAG_SEEN)) {
            count++;
        }
    }
    return count;
}

cyxchat_error_t cyxchat_mail_list(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_folder_type_t folder,
    size_t offset,
    size_t limit,
    cyxchat_mail_t ***mail_out,
    size_t *count_out
) {
    if (!ctx || !mail_out || !count_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Count matching mails */
    size_t total = cyxchat_mail_count(ctx, folder);

    if (offset >= total) {
        *mail_out = NULL;
        *count_out = 0;
        return CYXCHAT_OK;
    }

    size_t available = total - offset;
    size_t result_count = available < limit ? available : limit;

    /* Allocate result array */
    cyxchat_mail_t **results = calloc(result_count, sizeof(cyxchat_mail_t*));
    if (!results) {
        return CYXCHAT_ERR_MEMORY;
    }

    /* Fill results */
    size_t matched = 0;
    size_t added = 0;
    for (size_t i = 0; i < ctx->stored_count && added < result_count; i++) {
        if (ctx->stored[i] && ctx->stored[i]->folder_type == folder) {
            if (matched >= offset) {
                results[added++] = ctx->stored[i];
            }
            matched++;
        }
    }

    *mail_out = results;
    *count_out = added;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_get_thread(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *thread_id,
    cyxchat_mail_t ***mail_out,
    size_t *count_out
) {
    if (!ctx || !thread_id || !mail_out || !count_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Count thread messages */
    size_t thread_count = 0;
    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i]) {
            if (memcmp(ctx->stored[i]->thread_id.bytes, thread_id->bytes,
                       CYXCHAT_MAIL_ID_SIZE) == 0 ||
                memcmp(ctx->stored[i]->mail_id.bytes, thread_id->bytes,
                       CYXCHAT_MAIL_ID_SIZE) == 0) {
                thread_count++;
            }
        }
    }

    if (thread_count == 0) {
        *mail_out = NULL;
        *count_out = 0;
        return CYXCHAT_OK;
    }

    /* Allocate result array */
    cyxchat_mail_t **results = calloc(thread_count, sizeof(cyxchat_mail_t*));
    if (!results) {
        return CYXCHAT_ERR_MEMORY;
    }

    /* Fill results */
    size_t added = 0;
    for (size_t i = 0; i < ctx->stored_count && added < thread_count; i++) {
        if (ctx->stored[i]) {
            if (memcmp(ctx->stored[i]->thread_id.bytes, thread_id->bytes,
                       CYXCHAT_MAIL_ID_SIZE) == 0 ||
                memcmp(ctx->stored[i]->mail_id.bytes, thread_id->bytes,
                       CYXCHAT_MAIL_ID_SIZE) == 0) {
                results[added++] = ctx->stored[i];
            }
        }
    }

    *mail_out = results;
    *count_out = added;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_search(
    cyxchat_mail_ctx_t *ctx,
    const char *query,
    cyxchat_mail_t ***mail_out,
    size_t *count_out
) {
    if (!ctx || !query || !mail_out || !count_out) {
        return CYXCHAT_ERR_NULL;
    }

    /* Count matches */
    size_t match_count = 0;
    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i]) {
            /* Search in subject */
            if (strstr(ctx->stored[i]->subject, query)) {
                match_count++;
                continue;
            }
            /* Search in body */
            if (ctx->stored[i]->body && strstr(ctx->stored[i]->body, query)) {
                match_count++;
            }
        }
    }

    if (match_count == 0) {
        *mail_out = NULL;
        *count_out = 0;
        return CYXCHAT_OK;
    }

    /* Allocate result array */
    cyxchat_mail_t **results = calloc(match_count, sizeof(cyxchat_mail_t*));
    if (!results) {
        return CYXCHAT_ERR_MEMORY;
    }

    /* Fill results */
    size_t added = 0;
    for (size_t i = 0; i < ctx->stored_count && added < match_count; i++) {
        if (ctx->stored[i]) {
            if (strstr(ctx->stored[i]->subject, query) ||
                (ctx->stored[i]->body && strstr(ctx->stored[i]->body, query))) {
                results[added++] = ctx->stored[i];
            }
        }
    }

    *mail_out = results;
    *count_out = added;
    return CYXCHAT_OK;
}

/* ============================================================
 * Mail Actions
 * ============================================================ */

cyxchat_error_t cyxchat_mail_mark_read(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    int send_receipt
) {
    if (!ctx || !mail_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *mail = find_mail(ctx, mail_id);
    if (!mail) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    mail->flags |= CYXCHAT_MAIL_FLAG_SEEN;

    if (send_receipt) {
        /* TODO: Send read receipt via onion */
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_mark_unread(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id
) {
    if (!ctx || !mail_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *mail = find_mail(ctx, mail_id);
    if (!mail) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    mail->flags &= ~CYXCHAT_MAIL_FLAG_SEEN;
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_set_flagged(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    int flagged
) {
    if (!ctx || !mail_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *mail = find_mail(ctx, mail_id);
    if (!mail) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    if (flagged) {
        mail->flags |= CYXCHAT_MAIL_FLAG_FLAGGED;
    } else {
        mail->flags &= ~CYXCHAT_MAIL_FLAG_FLAGGED;
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_move(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id,
    cyxchat_folder_type_t folder
) {
    if (!ctx || !mail_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *mail = find_mail(ctx, mail_id);
    if (!mail) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    mail->folder_type = (uint8_t)folder;

    /* Clear draft flag if moving out of drafts */
    if (folder != CYXCHAT_FOLDER_DRAFTS) {
        mail->flags &= ~CYXCHAT_MAIL_FLAG_DRAFT;
    }

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_delete(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id
) {
    if (!ctx || !mail_id) {
        return CYXCHAT_ERR_NULL;
    }

    cyxchat_mail_t *mail = find_mail(ctx, mail_id);
    if (!mail) {
        return CYXCHAT_ERR_NOT_FOUND;
    }

    /* If already in trash, delete permanently */
    if (mail->folder_type == CYXCHAT_FOLDER_TRASH) {
        return cyxchat_mail_delete_permanent(ctx, mail_id);
    }

    /* Move to trash */
    mail->folder_type = CYXCHAT_FOLDER_TRASH;
    mail->flags |= CYXCHAT_MAIL_FLAG_DELETED;

    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_delete_permanent(
    cyxchat_mail_ctx_t *ctx,
    const cyxchat_mail_id_t *mail_id
) {
    if (!ctx || !mail_id) {
        return CYXCHAT_ERR_NULL;
    }

    remove_mail(ctx, mail_id);
    return CYXCHAT_OK;
}

cyxchat_error_t cyxchat_mail_empty_trash(cyxchat_mail_ctx_t *ctx)
{
    if (!ctx) {
        return CYXCHAT_ERR_NULL;
    }

    for (size_t i = 0; i < ctx->stored_count; i++) {
        if (ctx->stored[i] && ctx->stored[i]->folder_type == CYXCHAT_FOLDER_TRASH) {
            cyxchat_mail_free(ctx->stored[i]);
            ctx->stored[i] = NULL;
        }
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Callbacks
 * ============================================================ */

void cyxchat_mail_set_on_received(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_received_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_received = callback;
        ctx->on_received_data = user_data;
    }
}

void cyxchat_mail_set_on_sent(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_sent_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_sent = callback;
        ctx->on_sent_data = user_data;
    }
}

void cyxchat_mail_set_on_read(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_read_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_read = callback;
        ctx->on_read_data = user_data;
    }
}

void cyxchat_mail_set_on_bounce(
    cyxchat_mail_ctx_t *ctx,
    cyxchat_on_mail_bounce_t callback,
    void *user_data
) {
    if (ctx) {
        ctx->on_bounce = callback;
        ctx->on_bounce_data = user_data;
    }
}

/* ============================================================
 * Message Handling
 * ============================================================ */

cyxchat_error_t cyxchat_mail_handle_message(
    cyxchat_mail_ctx_t *ctx,
    const cyxwiz_node_id_t *from,
    const uint8_t *data,
    size_t len
) {
    if (!ctx || !from || !data || len == 0) {
        return CYXCHAT_ERR_NULL;
    }

    /* Parse message type */
    if (len < sizeof(cyxchat_msg_header_t)) {
        return CYXCHAT_ERR_INVALID;
    }

    const cyxchat_msg_header_t *header = (const cyxchat_msg_header_t*)data;

    switch (header->type) {
        case CYXCHAT_MSG_MAIL_SEND: {
            /* Parse incoming mail */
            /* TODO: Implement full parsing */
            cyxchat_mail_t *mail = calloc(1, sizeof(cyxchat_mail_t));
            if (!mail) {
                return CYXCHAT_ERR_MEMORY;
            }

            /* Copy sender */
            memcpy(&mail->from.node_id, from, sizeof(cyxwiz_node_id_t));

            /* Parse mail ID from message */
            if (len >= sizeof(cyxchat_msg_header_t) + CYXCHAT_MAIL_ID_SIZE) {
                memcpy(mail->mail_id.bytes,
                       data + sizeof(cyxchat_msg_header_t),
                       CYXCHAT_MAIL_ID_SIZE);
            }

            mail->timestamp = header->timestamp;
            mail->folder_type = CYXCHAT_FOLDER_INBOX;
            mail->status = CYXCHAT_MAIL_STATUS_DELIVERED;

            /* Verify signature */
            mail->signature_valid = verify_mail_signature(mail);

            /* Store mail */
            store_mail(ctx, mail);

            /* Notify callback */
            if (ctx->on_received) {
                ctx->on_received(ctx, mail, ctx->on_received_data);
            }

            /* TODO: Send ACK */
            break;
        }

        case CYXCHAT_MSG_MAIL_ACK: {
            if (len < sizeof(cyxchat_mail_ack_msg_t)) {
                return CYXCHAT_ERR_INVALID;
            }

            const cyxchat_mail_ack_msg_t *ack = (const cyxchat_mail_ack_msg_t*)data;

            /* Find pending send */
            for (size_t i = 0; i < MAIL_MAX_PENDING; i++) {
                if (ctx->pending[i].active && ctx->pending[i].mail &&
                    memcmp(ctx->pending[i].mail->mail_id.bytes,
                           ack->mail_id.bytes, CYXCHAT_MAIL_ID_SIZE) == 0) {

                    ctx->pending[i].mail->status = ack->status == 0 ?
                        CYXCHAT_MAIL_STATUS_DELIVERED : CYXCHAT_MAIL_STATUS_FAILED;

                    if (ctx->on_sent) {
                        ctx->on_sent(ctx, &ack->mail_id,
                                     ctx->pending[i].mail->status,
                                     ctx->on_sent_data);
                    }

                    /* Move to sent folder */
                    ctx->pending[i].mail->folder_type = CYXCHAT_FOLDER_SENT;
                    store_mail(ctx, ctx->pending[i].mail);
                    ctx->pending[i].mail = NULL;
                    ctx->pending[i].active = 0;
                    break;
                }
            }
            break;
        }

        case CYXCHAT_MSG_MAIL_READ_RECEIPT: {
            if (len < sizeof(cyxchat_mail_read_receipt_msg_t)) {
                return CYXCHAT_ERR_INVALID;
            }

            const cyxchat_mail_read_receipt_msg_t *receipt =
                (const cyxchat_mail_read_receipt_msg_t*)data;

            if (ctx->on_read) {
                ctx->on_read(ctx, &receipt->mail_id, receipt->read_at,
                             ctx->on_read_data);
            }
            break;
        }

        case CYXCHAT_MSG_MAIL_BOUNCE: {
            if (len < sizeof(cyxchat_mail_bounce_msg_t)) {
                return CYXCHAT_ERR_INVALID;
            }

            const cyxchat_mail_bounce_msg_t *bounce =
                (const cyxchat_mail_bounce_msg_t*)data;

            if (ctx->on_bounce) {
                ctx->on_bounce(ctx, &bounce->mail_id, bounce->reason,
                               bounce->details, ctx->on_bounce_data);
            }
            break;
        }

        default:
            return CYXCHAT_ERR_INVALID;
    }

    return CYXCHAT_OK;
}

/* ============================================================
 * Utilities
 * ============================================================ */

void cyxchat_mail_generate_id(cyxchat_mail_id_t *id)
{
    if (!id) return;

#ifdef CYXWIZ_HAS_CRYPTO
    randombytes_buf(id->bytes, CYXCHAT_MAIL_ID_SIZE);
#else
    for (int i = 0; i < CYXCHAT_MAIL_ID_SIZE; i++) {
        id->bytes[i] = (uint8_t)(rand() & 0xFF);
    }
#endif
}

void cyxchat_mail_id_to_hex(const cyxchat_mail_id_t *id, char *hex_out)
{
    if (!id || !hex_out) return;

    static const char hex_chars[] = "0123456789abcdef";
    for (int i = 0; i < CYXCHAT_MAIL_ID_SIZE; i++) {
        hex_out[i * 2] = hex_chars[(id->bytes[i] >> 4) & 0x0F];
        hex_out[i * 2 + 1] = hex_chars[id->bytes[i] & 0x0F];
    }
    hex_out[CYXCHAT_MAIL_ID_SIZE * 2] = '\0';
}

cyxchat_error_t cyxchat_mail_id_from_hex(const char *hex, cyxchat_mail_id_t *id_out)
{
    if (!hex || !id_out) {
        return CYXCHAT_ERR_NULL;
    }

    if (strlen(hex) != CYXCHAT_MAIL_ID_SIZE * 2) {
        return CYXCHAT_ERR_INVALID;
    }

    for (int i = 0; i < CYXCHAT_MAIL_ID_SIZE; i++) {
        char high = hex[i * 2];
        char low = hex[i * 2 + 1];

        uint8_t byte = 0;

        if (high >= '0' && high <= '9') byte = (high - '0') << 4;
        else if (high >= 'a' && high <= 'f') byte = (high - 'a' + 10) << 4;
        else if (high >= 'A' && high <= 'F') byte = (high - 'A' + 10) << 4;
        else return CYXCHAT_ERR_INVALID;

        if (low >= '0' && low <= '9') byte |= (low - '0');
        else if (low >= 'a' && low <= 'f') byte |= (low - 'a' + 10);
        else if (low >= 'A' && low <= 'F') byte |= (low - 'A' + 10);
        else return CYXCHAT_ERR_INVALID;

        id_out->bytes[i] = byte;
    }

    return CYXCHAT_OK;
}

int cyxchat_mail_id_cmp(const cyxchat_mail_id_t *a, const cyxchat_mail_id_t *b)
{
    if (!a || !b) return a ? 1 : (b ? -1 : 0);
    return memcmp(a->bytes, b->bytes, CYXCHAT_MAIL_ID_SIZE);
}

int cyxchat_mail_id_is_null(const cyxchat_mail_id_t *id)
{
    if (!id) return 1;

    for (int i = 0; i < CYXCHAT_MAIL_ID_SIZE; i++) {
        if (id->bytes[i] != 0) return 0;
    }
    return 1;
}

const char* cyxchat_mail_folder_name(cyxchat_folder_type_t folder)
{
    switch (folder) {
        case CYXCHAT_FOLDER_INBOX:   return "Inbox";
        case CYXCHAT_FOLDER_SENT:    return "Sent";
        case CYXCHAT_FOLDER_DRAFTS:  return "Drafts";
        case CYXCHAT_FOLDER_ARCHIVE: return "Archive";
        case CYXCHAT_FOLDER_TRASH:   return "Trash";
        case CYXCHAT_FOLDER_SPAM:    return "Spam";
        case CYXCHAT_FOLDER_CUSTOM:  return "Custom";
        default:                     return "Unknown";
    }
}

const char* cyxchat_mail_status_name(cyxchat_mail_status_t status)
{
    switch (status) {
        case CYXCHAT_MAIL_STATUS_DRAFT:     return "Draft";
        case CYXCHAT_MAIL_STATUS_QUEUED:    return "Queued";
        case CYXCHAT_MAIL_STATUS_SENT:      return "Sent";
        case CYXCHAT_MAIL_STATUS_DELIVERED: return "Delivered";
        case CYXCHAT_MAIL_STATUS_FAILED:    return "Failed";
        default:                            return "Unknown";
    }
}

void cyxchat_mail_format_date(uint64_t timestamp_ms, char *out, size_t out_len)
{
    if (!out || out_len < 20) return;

    time_t t = (time_t)(timestamp_ms / 1000);
    struct tm *tm_info;

#ifdef _WIN32
    struct tm tm_buf;
    localtime_s(&tm_buf, &t);
    tm_info = &tm_buf;
#else
    tm_info = localtime(&t);
#endif

    if (tm_info) {
        strftime(out, out_len, "%Y-%m-%d %H:%M", tm_info);
    } else {
        snprintf(out, out_len, "Unknown");
    }
}
