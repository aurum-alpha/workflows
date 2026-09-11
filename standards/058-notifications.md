# Notifications: the record, the pipeline, consent, and the provider at the boundary

## Why this exists

Every product tells people things: a receipt, a reset link, a mention, a
warning that someone signed in from a new device. Each has a cheapest
answer: a mail library called inside the request handler, the address taken
from the form, the copy in a string. And the vendor's key in the server's
environment. That answer fails as a set of general properties. Sending
inside the request makes every send a wait on a vendor and every timeout a
doubled send. A copied address goes stale and spreads personal data.

With no record, *did we tell them* is a question for the vendor's
dashboard. That dashboard is searched by address rather than by person,
retained as long as the vendor chooses, and empty the day the vendor is
swapped. One unsubscribe flag stops the password reset with the
newsletter, because one switch serves two classes of message. Copy in a
vendor's editor changes without a commit. A vendor SDK in the domain makes
a provider change a rewrite. It also puts a provider credential in the
process that answers the internet.

Two properties are external. A mailbox provider that sees complaints cross
a threshold or bounces ignored throttles the sender for every recipient at
once. And large mailbox providers filter bulk senders that offer no
one-click unsubscribe. This standard removes those decisions from every
repository. What remains for a repository is the set of categories it sends
and the templates it renders.

### The standards evaluated first, per PC2

**The messages are CloudEvents under 055**: the causing event, the request
to send and the provider's status reports are AM1 envelopes. The outbox
(AM4) carries the request, and AM8 admits the webhook. **The jobs are
057's**, in 035's pool. **Unsubscribe is
[RFC 8058](https://www.rfc-editor.org/rfc/rfc8058)**, one-click over
[RFC 2369](https://www.rfc-editor.org/rfc/rfc2369)'s `List-Unsubscribe`,
adopted whole for every optional email. Every notification email carries
**[RFC 3834](https://www.rfc-editor.org/rfc/rfc3834)**'s `Auto-Submitted`.
**Locale and zone are [BCP 47](https://www.rfc-editor.org/info/bcp47) and
the [IANA time zone database](https://www.iana.org/time-zones)**, as 090
WC4 requires of the browser.

**Unicode MessageFormat 2** (LDML, part 9) is recommended as the template
syntax, not required, because NF8 binds the artifact. **Browser push is
[RFC 8030](https://www.rfc-editor.org/rfc/rfc8030),
[RFC 8291](https://www.rfc-editor.org/rfc/rfc8291) and
[RFC 8292](https://www.rfc-editor.org/rfc/rfc8292)**. Native push is a
vendor protocol behind the NF11 adapter, and **Standard Webhooks** verifies
a status webhook where the provider signs that way (AM8). Set aside:
OpenTelemetry has no notification semantic convention, so NF3's metrics
take 040's shape. RFC 8417's Security Event Token is peer signalling,
placed by 080.

**Invented here**: the record (NF3), the class, category and preference
model (NF5), the floor (NF6), and suppression as address state (NF7). Also
invented: authorization at render time (NF9), and the adapter interface
(NF11).

## The rules

### NF1. A notification is a message to a person, through a channel, about an event

**The recipient is a person with an identity record, addressed by user
public id. The channel is one of five, and the cause is a 055 event**. A
recipient is never an address, a role or a list. An address is resolved
from the person (NF4). A role is enumerated to people by 070 before
deciding, and a list is a product feature over people. A notification is the
consequence of a recorded fact and never a side effect of a request
handler.

| Channel | The address | Who delivers | Receipts the provider reports |
|---|---|---|---|
| `email` | a verified email on the identity record | provider adapter | delivered, bounced, complained |
| `sms` | a verified E.164 number | provider adapter | delivered, failed |
| `push` | a device token per device, registered by the client | adapter: Web Push for browsers, the vendor's service for native | failed (token gone) |
| `in_app` | none: the record is the delivery (NF12) | the service | read, by the recipient |
| `chat` | a webhook destination the person or tenant configured | provider adapter | none: `2xx` is sent |

Chat is a kind of webhook: a configured address, an HTTP call through an
adapter, no receipt. **Operator alerts are not notifications**: a page about
a failing job goes to a rota through 040's alerting.

### NF2. The pipeline is three jobs and two messages, under 055 and 057

```
domain event (055 AM1)
   ▼
notify.decide          per_event · idempotent · key = event (source, id)
   │  one transaction: one record per recipient per channel (NF3),
   │  one notification.requested per queued record via the outbox (AM4)
   ▼
notify.send.<channel>  per_event · idempotent | at_most_once (JB2)
   │  resolves the address (NF4), checks authorization (NF9), renders
   │  (NF8), calls the adapter (NF11), writes sent + provider message id
   ▼
provider status webhook ──AM8──▶ notification.delivered | bounced |
                                 complained | failed ──▶ the record
```

**`notify.decide`** reads the category declaration (NF5) and resolves the
recipients the event names. For each recipient and declared channel it
applies three checks, in order. First, address usability (NF4, NF7).
Second, consent, unless the category is the floor (NF5, NF6). Third,
collapse, rate limit and quiet hours (NF10).

It writes a row for every channel considered and a message for every
queued one, in one transaction keyed on the event's `(source, id)`. So a
redelivery under AM3 produces no second row. An erased subject produces
nothing (NF7).

**`notify.send.<channel>`** is one job per channel, routed by
`data.channel`. It reads the record rather than the message, so the payload
travels once. Its policy follows JB2. It is `idempotent` where the provider
accepts an idempotency key, which is the notification id. It is
`at_most_once` otherwise, for plain SMTP or a gateway without one, with
`notification.reconcile` declared. `at_least_once` is admitted only for an
optional channel where the product states a repeat costs less than a miss,
never for transactional.

**Status webhooks** enter under AM8 and become the four events in
[`status-events.json`](../contracts/notifications/status-events.json). The
adapter is the `source`, the provider's event id the `id`, and the
notification id the `subject`. The consumer follows that file's transitions
and ignores the rest, because providers redeliver and reorder.

Two periodic jobs under JB8 complete the set. **`notification.release`**
(every five minutes, `single_flight`, `stale_after` fifteen minutes)
produces the message for deferred rows whose `not_before` has passed. It
re-checks consent and suppression first. **`notification.purge`** deletes
rows past their category's retention. All run in the pool or jobs image
(035 WK1), and no server image holds the provider credential (WK8).

### NF3. The record is the source of truth for *did we tell them*, and it is the service's

**One row per recipient per channel per notified event, in the service's
own database, shaped by
[`notification.schema.json`](../contracts/notifications/notification.schema.json)**.
It carries the recipient's public id, the causing event's identity, the
template id and version, locale and zone, and the payload after NF9. It
carries the status, the adapter and provider message id, the instant of
each transition, and the run's trace id. It never carries the address (NF4)
or the rendered body (NF8), and the schema closes the property set so
neither has a place to go.

The provider's dashboard is searched by address rather than by person,
retained as long as the vendor chooses, and lost when the vendor changes.
It is also silent about what was *not* sent. A suppressed channel here is a
row with a reason, so *why did they not get it* is a query. Only an erased
subject leaves no row.

The statuses split by writer. `queued`, `deferred` (with `not_before`),
`suppressed` (with a reason) and `collapsed` are `notify.decide`'s. `sent`
and `unknown` are `notify.send`'s; `unknown` is an `at_most_once` crash
between the call and the row. `delivered`, `bounced`, `complained` and
`failed` are the provider's.

Retention is declared per category, one year for transactional and ninety
days for optional by default. `notification.purge` deletes on it under
[`025-structured-data.md`](025-structured-data.md) SD12, and an erasure
deletes ahead of it under
[`082-data-subject-rights.md`](082-data-subject-rights.md). **The record is
not an audit event**: 080 AE5's event records the act, this row the
telling. Every log line the pipeline writes carries `notification.id`,
`.channel` and `.template` in the 040 OC4 block, and never the body or the
address. The pool exposes `notification.send.duration` by channel, provider
and outcome, `notification.delivery.latency` from `created_at` to
`delivered_at`, and `notification.outcomes` by status. A transactional row
reaching `failed`, `bounced`, or `suppressed` with no channel left is an
alert.

### NF4. The recipient is a public id, and the address is resolved at send time

**A notification names a person by user public id, and `notify.send`
resolves the channel's address from the identity record at the moment of
sending**. The address is 060 AU3's matching key and display attribute and
lives there. A copy would go stale on the next change and spread personal
data into a table that never needed it. It would also survive an erasure
that removed the original. Where a notification must reach an address other than the current
one, the record carries the address's public id. The previous address on a
contact change (NF6) is that case.

**An address is verified before optional notifications use it.**
Verification is itself a transactional message with a single-use token
(NF9). So transactional must reach an unverified address, or nothing ever
becomes verified. Optional never does, because an address nobody proved
they own could be somebody else's. Address id, verified state and
suppression state (NF7) are what the identity record's channel address
carries, as `channelAddress` in
[`preference.schema.json`](../contracts/notifications/preference.schema.json).

### NF5. Two classes, declared categories, and consent per category per channel

**Every notification is `transactional` or `optional`, and belongs to a
category the repository declares. An optional notification is sent only
where a preference permits it for that category on that channel**.
*Transactional* is what the relationship needs to operate: receipts,
credential resets, address verification, security notices (NF6), legal
notices. The test is whether the person could hold the product to account
for not sending it. *Optional* is everything else; *marketing* is optional
by definition and opt-in.

**Categories are declared** in
[`category-declaration.schema.json`](../contracts/notifications/category-declaration.schema.json)
beside the code: class, channels in order, default consent per channel,
collapse window, retention. `security` is reserved for the floor, required
and transactional. `marketing` is reserved, optional and false by default on
every channel. An undeclared category is refused, for 070 RB1's reason. The
closed set is what makes the settings screen, the unsubscribe page and
`notify.decide` agree.

**A preference** is one row per recipient per category per channel, with
`allowed` and how it came to be. Absent a row, the declared default applies.
For an optional category any preference is honoured. For a transactional
category a preference is a channel switch, honoured only while one channel
remains usable. That is because *cannot be unsubscribed* is only true if
honouring every preference cannot leave the person unreachable; for the
floor none is read (NF6). *Pause everything* is a preference on every
optional category, never a separate flag, because that flag is how a floor
gets muted.

**Every optional email carries RFC 8058 one-click unsubscribe**:
`List-Unsubscribe` with an HTTPS URI (a `mailto:` can accompany it) and
`List-Unsubscribe-Post: List-Unsubscribe=One-Click`. The endpoint withdraws
consent for that category on that channel on a `POST` whose body is
`List-Unsubscribe=One-Click`, with no login and no confirmation. A `GET`
renders a page a person finishes with a button and changes nothing, because
mail gateways fetch every link before the recipient sees it. The token
binds one recipient, category and channel, and grants nothing else. It
lives as long as the email can sit in an inbox, and its only power is to
reduce what the product sends. Transactional email carries neither header;
every notification email carries `Auto-Submitted: auto-generated`
(RFC 3834).

### NF6. The security floor notifies regardless of preference

**Some acts are told to the account holder whatever they have asked for. A
person told is the only detector for an act performed by an authorized
actor who was not the person**. They are category `security`,
transactional, sent on every channel the declaration lists. Preferences,
quiet hours and rate limits are not consulted; 080 AE5 records the act.

| Act | Told to | Also audited under 080 AE5 |
|---|---|---|
| A sign-in from a new device or location | the account holder | `auth.login` |
| A credential changed: password, passkey, second factor enrolled or removed, recovery codes regenerated | the account holder | items 1 and 5 |
| An email address or phone number changed | **the previous and the new address** | item 3 |
| A privileged role granted, one the product declares privileged | the grantee | item 2 |
| A personal-data export requested | the account holder | item 6 |
| Account deletion requested, and cancelled | the account holder | item 4 |

A contact change goes to the previous address because the person who can
read the new one could be the one who made the change. That row references
the old address by id (NF4). A hard bounce still stops a channel, and
alerts (NF3).

### NF7. Suppression is a state on the address, and erasure leaves nothing

**A hard bounce suppresses the address for every class. A complaint
suppresses optional on that address. An erasure removes the person from the
pipeline**. Suppression is state on the identity record's channel address
(NF4). The `notification.bounced` and `notification.complained` events set
it, and `notify.decide` and `notification.release` read it.

A hard bounce means the address does not exist, so sending again costs
sender reputation for every other recipient. A complaint means the person
said stop to what they did not need, and the relationship's own messages
continue. A soft bounce is retried under AM5 and suppresses nothing.
Suppression clears only on re-verification.

An erasure under [`082-data-subject-rights.md`](082-data-subject-rights.md)
deletes the person's records and preferences, and the identity's addresses
go with the identity (060 AU4), so `notify.decide` finds no recipient. No
address is retained to avoid mailing it later; that is holding personal
data. Marketing's opt-in default makes it unnecessary: a returning person
is a new identity whose optional consent starts at the declared defaults.

### NF8. Templates are files in the repository, rendered at send time in the recipient's locale and zone

**A template is a file tree in the repository, one file per template id,
locale and channel part, versioned with the code. `notify.send` renders it
from the record's template id, version, locale, zone and payload, and the
rendering is deterministic**. What was sent is reproducible without storing
it. A change to copy is a reviewed commit, and the template that ships is
the one that was tested. `version` is bumped when a template's meaning
changes. The format is the repository's choice; the rule binds the
artifact: no network call, no data fetch, no branch on anything but the
payload.

Locale is a BCP 47 tag from the recipient's stored preference, falling back
through the tag (`de-AT`, `de`, the product default). Zone is an IANA name
from the same place. Both are the recipient's, never the server's and never
inferred from an address, per 090 WC4. The renderer is the presentation
layer for these channels, formatting for one viewer. So it applies WC4's
two specifics: money by the currency's exponent, and an instant in the
recipient's zone with the zone named. The record keeps base
representations, so 020's rule is met.

| Channel | Limit the render enforces | Why that number |
|---|---|---|
| `email` | subject 78 characters; text and HTML parts both present | RFC 5322's line-length recommendation; the text part is what a plain client gets |
| `sms` | one segment by default: 160 GSM-7 or 70 UCS-2 characters; ceiling three segments | every segment is billed and reassembled; past three, order stops being reliable |
| `push` | title 50, body 150 characters, payload 4 096 bytes | the payload ceiling Web Push and native services share |
| `in_app` | title 120, body 500 characters | an inbox row, not a page |
| `chat` | 2 000 characters, or the adapter's limit | the smallest common ceiling |

A render past its limit fails in CI. There every template renders against a
fixture payload in every supported locale, and a missing locale fails the
build. Attachments are blob references under
[`026-blob-storage.md`](026-blob-storage.md), resolved by the send job under
the service's credential, never inline.

### NF9. Authorization is checked at render time, and links require authentication

**A notification carries no data the recipient could not read at the moment
it is sent**. Before rendering, `notify.send` runs 070's
`check(recipient, permission, scope)` against the event's subject. The
template declares the permission that gates the whole notification and, per
field, the permission that gates the field. A failed subject check produces
a row `suppressed` with reason `unauthorized`. A failed field check drops
the field, and a failed check on a required field drops the notification.
The check runs at send time because a grant revoked after decide time is
ordinary.

Links point at routes that require authentication under 060, carry public
ids only, and never carry a credential. A token in a link is single-use and
short-lived, one hour by default and one day at most. A link that itself
authenticates (a reset, a verification, a magic link) expires within one
hour and is otherwise 060's. The unsubscribe token is NF5's stated
exception. No secrets, and nothing beyond what the recipient already holds:
a card's last four digits, never its number.

### NF10. Repeats collapse, optional is rate-limited, and quiet hours are the recipient's

**A collapse key** on the event names the thing reported. Repeats of one
key to one recipient on one channel within the category's window (default
`PT15M`) produce one message, and the later rows are `collapsed`. **A rate
limit** bounds optional notifications per recipient per channel per rolling
day. The defaults are email 10, SMS 3, push 20, chat 20, and `in_app`
unbounded. The row past it is `suppressed` with reason `rate_limited`.
Transactional is exempt, because the limit exists to stop a product
nagging.

**Quiet hours** (default 22:00 to 08:00) are evaluated in the recipient's
zone for email, SMS, push and chat. An optional notification inside them is
`deferred` with `not_before` at the window's end in that zone, and
`notification.release` releases it. `in_app` rings nothing and
transactional is wanted at midnight, so neither is deferred. A **digest** is
a notification of its own optional category, produced by a periodic job in
the recipient's zone as 057 classifies `digest.schedule`. The categories it
summarises declare `in_app` alone for their immediate path.

### NF11. The provider is behind one adapter, and a vendor swap is configuration

**Every provider is an adapter behind one interface per channel, chosen by
configuration. Domain code imports no vendor SDK, and no server image holds
a provider credential.**

```
send(record, rendered)     -> { provider_message_id }
                             | PermanentFailure | TransientFailure
verify(raw_body, headers)  -> ProviderEvent { id, kind, provider_message_id,
                                              occurred_at, detail }
   kind: delivered | bounced(hard|soft) | complained | failed
```

`send` passes the notification id as the provider's idempotency key where
one exists. `attempts` counts every call across AM5's retries. A
`PermanentFailure` ends the row `failed` and a `TransientFailure` is
retried. `verify` is AM8's first step: Standard Webhooks where the provider
signs that way, the provider's own scheme otherwise. It lives inside the
adapter and nowhere else; the server's webhook endpoint does AM8's four
steps with it.

The adapter is selected by an environment variable per channel under 030
SC3. Failover is a second adapter and a routing rule. The credential is
configuration of the pool and jobs images only (035 WK8). The email adapter
sets NF5's headers; DKIM, SPF and DMARC are the platform's; `in_app` has
none.

### NF12. The in-app channel is the service's API, with cursor paging and SSE

**In-app notifications are the recipient's own `in_app` records, served by
the service under [`050-http.md`](050-http.md)**. `notify.send.in_app` marks
the row `delivered` on write and publishes to the live stream as a hint.
`GET /v1/notifications` returns the caller's records newest first by opaque
cursor (HA4), with an `unread_count`. `POST /v1/notifications/{id}/read`
sets `read_at`. `GET /v1/notifications/stream` is an SSE stream of the
caller's new records, chosen over a WebSocket per HA1. It is served over
HTTP/2 to the process and described in OpenAPI 3.2 (HA2).

The stream is a hint and the list is the truth: a client that reconnects
fetches the list. Title and body are rendered per request from the stored
payload in the viewer's locale and zone. That is WC4 met for one viewer at
a time. Records are tenant-scoped rows under 025 SD5 and SD6, and the API
scopes by the caller and the tenant context.

## The artifacts

Per PC3, under [`contracts/notifications/`](../contracts/notifications/):

- **`notification.schema.json`**: NF3's record, `$ref`-ing the identifiers
  and observability contracts, with the conditional rules. A suppressed row
  names its reason, and a deferred row its `not_before`. A sent row names
  its provider id, an `in_app` row no provider, and a `security` row no
  consent-shaped reason.
- **`preference.schema.json`**: NF5's consent row, which refuses
  `security`, and the `channelAddress` definition NF4 and NF7 need.
- **`category-declaration.schema.json`**: NF5's declaration, with
  `security` required and transactional, `marketing` opt-in, quiet hours,
  rate limits.
- **`status-events.json`**: NF2's five message types and the transitions.
- **`corpus.json`**: `records`, shapes each schema accepts and rejects.
  `decide`: the rows and message count `notify.decide` produces, with the
  floor detector. `unsubscribe`: header sets against the RFC 8058 and
  RFC 3834 profile and one-click requests, with the `GET` detector.
  `render_authorization`: the payload the send job is permitted to render.

## Decisions

- **The record is the source of truth, not the provider** (2026-09-02). A
  dashboard is searched by address, retained by the vendor, and silent
  about what was not sent. Relying on it answers *did we tell them* per
  vendor.
- **Two classes plus declared categories, not a flat list of topics**
  (2026-09-02). A flat list lets a preference mute the reset email. The
  class decides whether consent applies; the category is what it is held
  against. A transactional preference switches channel only while one
  remains. Ignoring it loses a wish for SMS over email; honouring it freely
  makes *cannot be unsubscribed* false.
- **The floor goes on every declared channel and reads no preference, quiet
  hours or rate limit** (2026-09-02). The channel the person muted could be
  the one that reaches the owner rather than the intruder. A limit that
  could suppress a security notice is a limit an attacker can fill.
- **Suppressed rows are written; erased subjects leave none** (2026-09-02).
  A row with a reason is a query. A row for an erased person is new data
  about them, and opt-in marketing makes a post-erasure suppression list
  unnecessary.
- **The send policy follows JB2 rather than being fixed** (2026-09-02). A
  provider with an idempotency key makes the send `idempotent`, one without
  makes it `at_most_once`; one fixed policy would misdeclare half the
  adapters.
- **Templates are files, versioned with the code; the format is open; `in_app`
  renders at read** (2026-09-02). Copy in a vendor's editor changes without
  review and cannot be re-rendered; deterministic rendering from stored
  inputs belongs to the artifact. The inbox is a screen the web client
  shows, so WC4's viewer-locale rule applies to it and the row stays in
  base representations.
- **Authorization at send time, not decide time** (2026-09-02). Grants
  change between the two and a deferral widens the gap; 070 RB7 makes the
  check pure.
- **`GET` never unsubscribes** (2026-09-02). Link scanners fetch every URI
  before delivery, so acting on `GET` unsubscribes everyone behind one.

## Out of scope, deliberately

- **The identity record and verification's mechanics.**
  [`060-auth.md`](060-auth.md) AU3 and AU4; this document reads the address
  state and does not own it.
- **The permission model and the audit trail.** [`070-rbac.md`](070-rbac.md),
  which NF9 calls; [`080-audit.md`](080-audit.md), whose AE5 records the act
  NF6 tells the person about.
- **Operator alerting.** [`040-observability.md`](040-observability.md).
- **Campaign audiences without an identity record, and sending-domain
  reputation.** A marketing platform's, and the platform's.
