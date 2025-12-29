# CyxMail Gateway - Bridging to Traditional Email

## Overview

CyxMail can interoperate with traditional email (Gmail, Outlook, etc.) through a **gateway** that translates between protocols.

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   CyxWiz Network                              Internet Email    │
│                                                                 │
│   alice.cyx ◄────────►  GATEWAY  ◄────────► bob@gmail.com     │
│                                                                 │
│   CyxMail Protocol        │          SMTP/IMAP Protocol        │
│   Decentralized           │          Centralized               │
│   Always E2E              │          Usually plaintext         │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## How It Works

### Gateway Node

A gateway is a CyxWiz node that also runs a traditional mail server:

```
┌─────────────────────────────────────────────────────────────────┐
│  Gateway Components                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌───────────────────────────────────────────────────────────┐ │
│  │                    GATEWAY NODE                           │ │
│  ├───────────────────────────────────────────────────────────┤ │
│  │                                                           │ │
│  │  ┌─────────────────┐       ┌─────────────────┐           │ │
│  │  │   CyxWiz Node   │◄─────►│   Mail Server   │           │ │
│  │  │                 │       │   (Postfix/etc) │           │ │
│  │  │  • Receives     │       │                 │           │ │
│  │  │    CyxMail      │       │  • SMTP (25)    │           │ │
│  │  │  • Sends        │       │  • IMAP (993)   │           │ │
│  │  │    CyxMail      │       │                 │           │ │
│  │  └─────────────────┘       └─────────────────┘           │ │
│  │           │                         │                     │ │
│  │           └─────────┬───────────────┘                     │ │
│  │                     │                                     │ │
│  │              ┌──────┴──────┐                              │ │
│  │              │  Translator │                              │ │
│  │              │             │                              │ │
│  │              │ CyxMail ◄──►│ MIME                        │ │
│  │              └─────────────┘                              │ │
│  │                                                           │ │
│  └───────────────────────────────────────────────────────────┘ │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Address Mapping

### CyxMail → External Address

Each CyxMail user gets an external email address through the gateway:

```
CyxMail Username     External Email Address
────────────────     ─────────────────────
alice.cyx            alice@cyxbridge.com
bob.cyx              bob@cyxbridge.com
charlie.cyx          charlie@cyxbridge.com
```

### Mapping Formats

```
Option A: Simple mapping
  alice.cyx → alice@gateway-domain.com

Option B: Subdomain
  alice.cyx → alice@cyx.gateway-domain.com

Option C: Plus addressing
  alice.cyx → cyx+alice@gateway-domain.com

Option D: Full preservation
  alice.cyx → alice.cyx@gateway-domain.com
```

### Registration

Users register their external address with the gateway:

```
1. Alice sends to gateway.cyx:
   REGISTER {
     cyxmail: "alice.cyx",
     external: "alice@cyxbridge.com",
     signature: sign(data, alice_privkey)
   }

2. Gateway verifies signature (proves ownership of alice.cyx)

3. Gateway adds mapping:
   alice@cyxbridge.com ↔ alice.cyx

4. Alice can now receive external email
```

---

## Outbound Flow (CyxMail → Gmail)

```
┌─────────────────────────────────────────────────────────────────┐
│  Alice (alice.cyx) sends to Bob (bob@gmail.com)                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. COMPOSE                                                     │
│     Alice writes email in CyxMail client                       │
│     To: bob@gmail.com (external address detected)              │
│                                                                 │
│  2. ROUTE TO GATEWAY                                           │
│     Client detects external address                            │
│     Looks up configured gateway: gateway.cyx                   │
│     Sends CyxMail message to gateway                           │
│                                                                 │
│  3. GATEWAY RECEIVES                                           │
│     Decrypts CyxMail message                                   │
│     Extracts: from, to, subject, body, attachments             │
│                                                                 │
│  4. CONVERT TO MIME                                            │
│     From: alice@cyxbridge.com                                  │
│     Reply-To: alice@cyxbridge.com                              │
│     To: bob@gmail.com                                          │
│     Subject: (preserved)                                        │
│     Body: (converted to MIME multipart if attachments)         │
│                                                                 │
│  5. SEND VIA SMTP                                              │
│     Gateway's mail server sends to Gmail's MX                  │
│                                                                 │
│  6. CONFIRM                                                     │
│     Gateway sends delivery confirmation to Alice               │
│     (or bounce if failed)                                      │
│                                                                 │
│  7. BOB RECEIVES                                               │
│     Normal email in Gmail inbox                                │
│     From: alice@cyxbridge.com                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Inbound Flow (Gmail → CyxMail)

```
┌─────────────────────────────────────────────────────────────────┐
│  Bob (bob@gmail.com) replies to Alice (alice@cyxbridge.com)    │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. BOB REPLIES                                                 │
│     Clicks reply in Gmail                                      │
│     To: alice@cyxbridge.com                                    │
│                                                                 │
│  2. SMTP DELIVERY                                              │
│     Gmail sends to cyxbridge.com MX server                     │
│     Gateway's mail server receives                             │
│                                                                 │
│  3. GATEWAY PROCESSES                                          │
│     Looks up: alice@cyxbridge.com → alice.cyx                  │
│     Parses MIME message                                        │
│     Extracts: from, subject, body, attachments                 │
│                                                                 │
│  4. CONVERT TO CYXMAIL                                         │
│     Creates CyxMail message                                    │
│     From: bob@gmail.com (external marker)                      │
│     To: alice.cyx                                              │
│     Encrypts for Alice's public key                            │
│                                                                 │
│  5. DELIVER VIA CYXWIZ                                         │
│     If Alice online: direct delivery                           │
│     If Alice offline: store in her mailbox                     │
│                                                                 │
│  6. ALICE RECEIVES                                             │
│     Normal CyxMail message in inbox                            │
│     From shows: bob@gmail.com (external)                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Gateway Options

### Option 1: Community Gateway

```
┌─────────────────────────────────────────────────────────────────┐
│  PUBLIC GATEWAY                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Operated by: CyxWiz community / organization                  │
│  Domain: cyxbridge.com (example)                               │
│                                                                 │
│  Pros:                                                          │
│  + No setup required for users                                 │
│  + Works immediately                                           │
│  + Shared infrastructure costs                                 │
│                                                                 │
│  Cons:                                                          │
│  - Must trust gateway operator                                 │
│  - Single point of failure                                     │
│  - Gateway sees external email content                         │
│  - Potential for censorship                                    │
│                                                                 │
│  Best for: Casual users, getting started                       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Option 2: Self-Hosted Gateway

```
┌─────────────────────────────────────────────────────────────────┐
│  SELF-HOSTED GATEWAY                                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  You run your own gateway:                                      │
│  • Your domain: mail.yourdomain.com                            │
│  • Your server: VPS running CyxWiz + Postfix                   │
│                                                                 │
│  Pros:                                                          │
│  + Full control over your data                                 │
│  + No third-party trust                                        │
│  + Your own domain                                             │
│  + Can customize filtering/rules                               │
│                                                                 │
│  Cons:                                                          │
│  - Requires server + domain                                    │
│  - Technical setup (DNS, TLS, etc.)                            │
│  - Ongoing maintenance                                         │
│  - IP reputation management                                    │
│                                                                 │
│  Best for: Technical users, organizations, privacy-focused     │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Option 3: Federated Gateways

```
┌─────────────────────────────────────────────────────────────────┐
│  FEDERATED GATEWAYS                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Multiple independent gateways:                                 │
│                                                                 │
│  gateway-us.cyx     → @cyx-us.org                              │
│  gateway-eu.cyx     → @cyx-eu.org                              │
│  gateway-asia.cyx   → @cyx-asia.org                            │
│                                                                 │
│  User chooses their gateway:                                   │
│  alice.cyx registers with gateway-eu.cyx                       │
│  → alice@cyx-eu.org                                            │
│                                                                 │
│  DNS record includes gateway preference:                       │
│  alice.cyx → {                                                 │
│    node_id: ...,                                               │
│    email_gateway: "gateway-eu.cyx",                            │
│    external_email: "alice@cyx-eu.org"                          │
│  }                                                              │
│                                                                 │
│  Pros:                                                          │
│  + Redundancy (if one fails, use another)                      │
│  + Geographic distribution                                     │
│  + User choice                                                 │
│  + Competition improves quality                                │
│                                                                 │
│  Cons:                                                          │
│  - Still trust chosen gateway                                  │
│  - Address changes if switching gateways                       │
│                                                                 │
│  Best for: Production deployment, resilience                   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Privacy & Security

### Encryption Status

```
┌─────────────────────────────────────────────────────────────────┐
│  ENCRYPTION BY PATH                                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  PATH                          ENCRYPTION STATUS                │
│  ────                          ─────────────────                │
│                                                                 │
│  CyxMail → CyxMail             ✓ End-to-end encrypted          │
│  (internal)                      Gateway never involved         │
│                                                                 │
│  CyxMail → Gateway             ✓ Encrypted (CyxWiz transport)  │
│  (first hop)                     Gateway decrypts to process   │
│                                                                 │
│  Gateway → External            ◐ TLS in transit (STARTTLS)     │
│  (SMTP)                          Content visible to gateway    │
│                                  and recipient's mail server   │
│                                                                 │
│  External → Gateway            ◐ TLS in transit                │
│  (inbound SMTP)                  Content visible to gateway    │
│                                                                 │
│  Gateway → CyxMail             ✓ Encrypted for recipient       │
│  (delivery)                      Only recipient can read       │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Key insight: External email is rarely encrypted anyway.
The gateway doesn't make security worse than normal email.
```

### What Gateway Sees

```
Gateway operator CAN see:
  • External email content (already unencrypted)
  • Sender/recipient metadata
  • Subject lines
  • Attachment contents

Gateway operator CANNOT see:
  • CyxMail-to-CyxMail messages (never touch gateway)
  • Content after delivery to CyxMail user
  • User's private keys

Mitigation:
  • Choose trusted gateway
  • Self-host for sensitive use
  • Use PGP for external E2E
```

### PGP Integration

For end-to-end encryption with external users:

```
┌─────────────────────────────────────────────────────────────────┐
│  PGP ENHANCEMENT                                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  OUTBOUND (Alice → External):                                  │
│                                                                 │
│  1. Alice's client checks: does recipient have PGP key?        │
│     (via keyserver, DNS, or local keyring)                     │
│                                                                 │
│  2. If yes:                                                     │
│     • Encrypt body with recipient's PGP key                    │
│     • Sign with Alice's PGP key                                │
│     • Send to gateway (double encrypted: PGP + CyxMail)        │
│                                                                 │
│  3. Gateway sends PGP-encrypted email via SMTP                 │
│     Gateway sees PGP blob, not plaintext                       │
│                                                                 │
│  4. Recipient decrypts with their PGP key                      │
│                                                                 │
│  INBOUND (External → Alice):                                   │
│                                                                 │
│  1. External user sends PGP-encrypted email                    │
│  2. Gateway receives encrypted blob                            │
│  3. Gateway wraps in CyxMail (still encrypted)                 │
│  4. Alice decrypts PGP layer                                   │
│                                                                 │
│  Result: True E2E even through gateway                         │
│  Limitation: Both parties need PGP (rare)                      │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Message Conversion

### CyxMail → MIME

```
CyxMail Message:
{
  message_id: "abc123@cyx",
  from: "alice.cyx",
  to: ["bob@gmail.com"],
  subject: "Hello",
  timestamp: 1703849600,
  body: "Hi Bob!",
  attachments: [
    {name: "doc.pdf", size: 1024, data: ...}
  ]
}

Converts to MIME:
─────────────────
From: alice@cyxbridge.com
To: bob@gmail.com
Subject: Hello
Date: Fri, 29 Dec 2024 12:00:00 +0000
Message-ID: <abc123@cyx.cyxbridge.com>
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="----=_Part_1"
X-CyxMail-Origin: alice.cyx
X-CyxMail-Gateway: gateway.cyx

------=_Part_1
Content-Type: text/plain; charset=utf-8

Hi Bob!

------=_Part_1
Content-Type: application/pdf; name="doc.pdf"
Content-Disposition: attachment; filename="doc.pdf"
Content-Transfer-Encoding: base64

JVBERi0xLjQKJeLjz9...
------=_Part_1--
```

### MIME → CyxMail

```
Incoming MIME:
─────────────
From: bob@gmail.com
To: alice@cyxbridge.com
Subject: Re: Hello
Date: Fri, 29 Dec 2024 13:00:00 +0000
Content-Type: text/plain

Thanks Alice!

Converts to CyxMail:
{
  message_id: "xyz789@cyx",
  from: "bob@gmail.com",      // Marked as external
  from_type: "external",
  to: ["alice.cyx"],
  subject: "Re: Hello",
  timestamp: 1703853600,
  in_reply_to: "abc123@cyx",
  body: "Thanks Alice!",
  attachments: [],
  gateway: "gateway.cyx",
  external_headers: {         // Preserved for debugging
    "Message-ID": "<original@gmail.com>",
    "Received": [...]
  }
}
```

---

## Spam Handling

### Inbound Spam

```
┌─────────────────────────────────────────────────────────────────┐
│  SPAM FILTERING                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Gateway runs spam filter (SpamAssassin, rspamd, etc.)         │
│                                                                 │
│  Options:                                                       │
│                                                                 │
│  1. DROP                                                        │
│     High-confidence spam silently dropped                      │
│     Never reaches user                                         │
│                                                                 │
│  2. MARK                                                        │
│     Add header: X-Spam-Score: 8.5                              │
│     User's client filters to spam folder                       │
│                                                                 │
│  3. QUARANTINE                                                  │
│     Store at gateway                                           │
│     User can review quarantine via web interface               │
│                                                                 │
│  4. PASS-THROUGH                                                │
│     Let user's client handle filtering                         │
│     Gateway just marks, doesn't filter                         │
│                                                                 │
│  Recommended: MARK + user-side filtering                       │
│  Preserves user control while providing signal                 │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Outbound Spam Prevention

```
Gateway must prevent abuse:

1. RATE LIMITING
   • Max emails per user per hour
   • Prevents compromised accounts spamming

2. REPUTATION CHECK
   • Require minimum CyxWiz reputation to send
   • New users have sending limits

3. CONTENT FILTERING
   • Check for obvious spam patterns
   • Block known malicious links

4. DKIM/SPF/DMARC
   • Properly authenticate outbound email
   • Maintain domain reputation
```

---

## Gateway Protocol

### Message Types

```c
/* Gateway Message Types (0xF0-0xFF) */

/* Outbound (CyxMail → External) */
#define CYXGATE_MSG_SEND           0xF0  /* Send to external */
#define CYXGATE_MSG_SEND_ACK       0xF1  /* Accepted for delivery */
#define CYXGATE_MSG_SENT           0xF2  /* Successfully sent */
#define CYXGATE_MSG_BOUNCE         0xF3  /* Delivery failed */

/* Inbound (External → CyxMail) */
#define CYXGATE_MSG_INCOMING       0xF4  /* New external email */
#define CYXGATE_MSG_INCOMING_ACK   0xF5  /* Received confirmation */

/* Registration */
#define CYXGATE_MSG_REGISTER       0xF6  /* Register external address */
#define CYXGATE_MSG_REGISTER_ACK   0xF7  /* Registration confirmed */
#define CYXGATE_MSG_UNREGISTER     0xF8  /* Remove registration */

/* Status */
#define CYXGATE_MSG_STATUS         0xF9  /* Query gateway status */
#define CYXGATE_MSG_STATUS_RESP    0xFA  /* Gateway status response */
```

### Registration Message

```c
typedef struct {
    uint8_t type;              /* CYXGATE_MSG_REGISTER */
    uint8_t cyxmail_name_len;
    /* char cyxmail_name[] - e.g., "alice" (without .cyx) */
    uint8_t external_addr_len;
    /* char external_addr[] - e.g., "alice@cyxbridge.com" */
    uint8_t pubkey[32];        /* User's public key */
    uint64_t timestamp;
    uint8_t signature[64];     /* Proves ownership */
} cyxgate_register_t;
```

### Outbound Message

```c
typedef struct {
    uint8_t type;              /* CYXGATE_MSG_SEND */
    uint32_t message_id;       /* For tracking */
    uint8_t to_count;
    /* external addresses follow */
    uint8_t cc_count;
    /* cc addresses follow */
    uint16_t subject_len;
    /* subject follows */
    uint32_t body_len;
    /* body follows */
    uint8_t attachment_count;
    /* attachment manifests follow */
    uint8_t signature[64];     /* Sender's signature */
} cyxgate_send_t;
```

---

## Self-Hosting Guide

### Requirements

```
1. Domain name (e.g., mail.yourdomain.com)
2. VPS with public IP
3. DNS control for:
   - MX records (mail routing)
   - SPF record (sender verification)
   - DKIM keys (email signing)
   - DMARC policy
4. TLS certificate (Let's Encrypt)
```

### Components

```
┌─────────────────────────────────────────────────────────────────┐
│  SELF-HOSTED GATEWAY STACK                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CyxWiz Node                                            │   │
│  │  • Connects to CyxWiz network                          │   │
│  │  • Handles CyxMail protocol                            │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Gateway Service                                        │   │
│  │  • Translates CyxMail ↔ MIME                           │   │
│  │  • Manages address mappings                            │   │
│  │  • Handles attachments                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Postfix (SMTP)                                         │   │
│  │  • Sends outbound email                                │   │
│  │  • Receives inbound email                              │   │
│  │  • TLS, DKIM signing                                   │   │
│  └─────────────────────────────────────────────────────────┘   │
│                          │                                      │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  Rspamd (optional)                                      │   │
│  │  • Spam filtering                                       │   │
│  │  • Reputation checking                                  │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### DNS Records

```
; MX record - where to deliver email
yourdomain.com.    IN  MX  10 mail.yourdomain.com.

; A record - mail server IP
mail.yourdomain.com.  IN  A   203.0.113.1

; SPF - authorized senders
yourdomain.com.    IN  TXT "v=spf1 mx -all"

; DKIM - email signing
selector._domainkey.yourdomain.com. IN TXT "v=DKIM1; k=rsa; p=MIGf..."

; DMARC - policy
_dmarc.yourdomain.com. IN TXT "v=DMARC1; p=reject; rua=mailto:dmarc@yourdomain.com"
```

---

## User Experience

### Sending to External

```
┌─────────────────────────────────────────────────────────────────┐
│  CyxMail Compose                                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  To: bob@gmail.com, carol.cyx                                  │
│       ───────────────  ─────────                               │
│       │                └── Internal (direct, E2E encrypted)    │
│       └── External (via gateway)                               │
│                                                                 │
│  Subject: Meeting Tomorrow                                      │
│                                                                 │
│  [Attach files...]                                              │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ Hi all,                                                  │  │
│  │                                                          │  │
│  │ Let's meet tomorrow at 3pm.                             │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
│  [Send]                                                         │
│                                                                 │
│  ┌──────────────────────────────────────────────────────────┐  │
│  │ ⚠ External recipient: bob@gmail.com                     │  │
│  │   Will be sent via gateway.cyx                          │  │
│  │   Gateway can see message content                       │  │
│  │   [Send anyway] [Cancel]                                │  │
│  └──────────────────────────────────────────────────────────┘  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Receiving from External

```
┌─────────────────────────────────────────────────────────────────┐
│  Inbox                                                          │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ● bob@gmail.com              Re: Meeting Tomorrow    2m ago   │
│    └── [External] via gateway.cyx                              │
│                                                                 │
│  ● carol.cyx                  Project Update          1h ago   │
│    └── [E2E Encrypted]                                         │
│                                                                 │
│  ○ dave.cyx                   Quick question          3h ago   │
│    └── [E2E Encrypted]                                         │
│                                                                 │
│  ● newsletter@company.com     Weekly Digest           1d ago   │
│    └── [External] via gateway.cyx                              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Visual indicators show:
• Which messages are external (less private)
• Which messages are E2E encrypted (internal)
• Which gateway was used
```

---

## Limitations

```
┌─────────────────────────────────────────────────────────────────┐
│  WHAT GATEWAY CANNOT DO                                         │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. Provide E2E encryption for external email                  │
│     (Unless both parties use PGP)                              │
│                                                                 │
│  2. Hide metadata from external mail servers                   │
│     (Subject, sender, recipient visible in SMTP)               │
│                                                                 │
│  3. Guarantee delivery                                          │
│     (Recipient's server might reject)                          │
│                                                                 │
│  4. Prevent gateway operator from reading                      │
│     (Trust is required for external email)                     │
│                                                                 │
│  5. Make external email as private as CyxMail                  │
│     (Different threat models)                                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

Bottom line: Gateway enables interoperability, not privacy.
For privacy, encourage contacts to use CyxMail directly.
```

---

## Implementation Roadmap

### Phase 1: Basic Gateway
- [ ] Address registration/mapping
- [ ] Outbound SMTP sending
- [ ] Inbound SMTP receiving
- [ ] Basic message conversion

### Phase 2: Features
- [ ] Attachment handling (large files)
- [ ] Spam filtering
- [ ] Rate limiting
- [ ] Delivery status notifications

### Phase 3: Security
- [ ] DKIM signing
- [ ] SPF/DMARC compliance
- [ ] PGP integration
- [ ] Reputation system

### Phase 4: Federation
- [ ] Multiple gateway support
- [ ] Gateway discovery
- [ ] Failover handling
- [ ] Load balancing
