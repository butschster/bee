# Gateway

bee.gateway gives an admitted managed agent a bounded MCP surface over a
host-owned HTTP listener. The listener is normally 127.0.0.1:0; it is not a
public service. The host selects the endpoint, tool set, hook events and
credential environment names. The gateway owns bindings, credential hashes and
hook intake. The carrier, placement service and runner own the launch
lifecycle.

## Component boundary

Gateway is the `bee/gateway` component, loaded from `modules/gateway/src`.
Its root namespace keeps shared resources and values. Lifecycle and hook queue
calls use `bee.gateway.binding:*`; HTTP route handlers use
`bee.gateway.api:*`; endpoint discovery uses
`bee.gateway.registry:address`. The root namespace has no forwarding functions
for those calls.

A host composes the component and selects the database, listener, endpoint
configuration, harness executable storage, approval policies, and the policies
for admitted built-in tools. The host also owns the HTTP service, router, and
routes that call the API handlers. An endpoint selection describes where the
listener runs; it does not give a caller network authority. Tool, caller, and
listener permissions remain host-selected policies.

## Connection and credentials

The listener accepts loopback and explicitly selected RFC1918 IPv4 addresses.
Wildcard, public, link-local and hostname addresses are refused. Requests must
use the selected Host address and port; localhost is accepted only for the same
127.0.0.1 endpoint. Browser origins are refused.

Every admitted attempt has one revocable binding for its subject, action,
attempt, thread, owner incarnation, carrier epoch, expiry and exact tool set.
The binding is created after durable launch preparation and before placement
starts. It is not created by a plan, and the carrier cannot choose its subject
or thread. A replacement carrier may inherit the current binding for its child;
older epochs cannot replace it.

admit returns an identity, never token bytes. Placement obtains a one-time
materialization key for the carrier-recorded binding, and only its runner can
exchange that key for the current credential generation. The gateway stores
credential hashes and presentation metadata. Tokens are delivered only in the
selected child environment, never in URLs, command arguments, records, evidence
or logs. Reissue is compare-and-set and invalidates the prior generation.
Revocation, expiry, listener replacement and failed startup refuse later use.

Readiness makes a loopback request with a fresh nonce and verifies the current
listener generation. A drain rejects new admissions, releases waits with
released/draining, and stops the listener at its recorded deadline.

## Gateway operations

| Operation | Caller | Purpose |
|---|---|---|
| open | managed host | Records a listener address and advances its epoch. |
| admit, reissue, revoke, check | carrier or authorized manager | Manage one bound attempt and its credential generation. |
| authorize_materialization, materialize | placement service and its runner | Deliver one credential to the authenticated child process. |
| revoke_attempt | placement supervision | Retire bindings after a fenced attempt failure or loss. |
| ready, drain | carrier or managed host | Verify listener readiness or begin controlled shutdown. |
| mcp | authenticated child | Serve JSON-RPC initialize, tools/list and tools/call. |
| hook operations | authenticated child and carrier | Accept and drain lifecycle observations as described in [Gateway hooks](hooks.md). |

An MCP tool name maps to one existing owner operation. Tool annotations and
driver flags describe behavior; the binding and target owner still enforce
authority.

## Agent tools

The host may admit thread_read, thread_wait, thread_message, thread_launch,
Governance overlay, Hub components, delivery and docs. Each tool receives only
bounded arguments. The binding supplies thread, subject, action, attempt and
context.

thread_message always writes a message record through the bound thread owner.
Callers cannot choose sender, thread, record family or context. thread_wait is
read-only and does not create an obligation. thread_launch starts only a
definition named in the caller's launch-policy allow-list; its child is
admitted through the ordinary carrier path with its own policy.

application_open is available only through the active, approval-granted
bee.application:runtime trait. It accepts definition_id, literal arguments and
an idempotency key, then routes only an already applied, admitted definition
through the workspace host and applications broker. It cannot publish, activate,
write the registry or apply an overlay. The trusted binding supplies the
workspace, thread, durable approval receipt and, for a window agent, the
originating display. Its result names the workspace, view, instance, definition,
title, reuse state and assigned display when one exists. A retry has one bounded
in-flight operation; an uncertain reply does not start another application.

## Configuration and limits

Drivers render provider configuration into the selected private home and use
the host-selected credential environment variables. They do not receive token
bytes in configuration. Claude and Codex support the rendered MCP setup and
hook adapters; a provider that cannot accept the required configuration cannot
be admitted for those features.

Gateway HTTP uses bounded bodies, exact Host checks, bearer authentication and
no CORS. The runtime HTTP client does not expose redirect refusal, so readiness
is limited to the controlled loopback acceptance path.

Run the relevant checks with:

    make gateway-check
    make managed-launch-fixture-check
    make app-journey-check

## Harness inbox queue (proposed 2026-09-21)

**Status: proposed. The transport facts below are measured against the real
harnesses (Claude Code 2.1.278, Codex 0.155.1) on a level-0 stand with a
provider stand-in; no Bee implementation and no acceptance check exists yet.**

Today a managed child learns of a thread record only by asking: `thread_wait`
blocks on the head until its transport budget runs out, `thread_read` pages
what already landed. Both cost the child a tool round, and between them it is
deaf — a record committed while the model is working waits until the model
chooses to look. `claims.CHANNELS` already names a non-pull channel (`push`),
and the recipient delivery contract in [threads](../threads.md) already fixes the rule that matters (dispatch intent
before bytes leave, uncertainty when acceptance is unknown), but nothing sets
that channel and no transport carries it.

### What the harnesses actually do

Measured, not inferred. The stand holds a turn open (Claude: a tool call that
waits on a flag; Codex: the provider answer itself is held) and injects in
that window, then reads the next provider request.

| | Claude Code 2.1.278 | Codex 0.155.1 |
|---|---|---|
| In-turn delivery | **Yes**, through its cross-session inbox: the injected text arrived in the *same provider request as the held tool's `tool_result`* | **Yes**, through `turn/steer` on the app server: the marker arrived in the next provider request of the **same** turn, which then completed as one turn |
| Address | `--messaging-socket-path <abs path>`, validated before start, **socket path capped at 103 bytes** | `codex app-server --stdio` (the `--listen unix://` socket accepted a connection but never answered `initialize` on this host) |
| Credential | The harness **mints its own** and publishes it in `<config>/sessions/<pid>.<sha256>.key`. `CLAUDE_CODE_MESSAGING_TOKEN` is the *sender's* variable and does not set the inbox token, so the host reads the key file it isolated rather than minting one | none on stdio; the pipe is the boundary |
| Entrypoint requirement | **Interactive only.** The headless `-p` entrypoint binds the socket, publishes a key and accepts the frames without error, then delivers nothing to the model and publishes no `<pid>.json` registry entry | any app-server thread |
| Acceptance signal | `peer_message_status` (`delivered`/`held`/`declined`/`expired`/`dropped`) | the JSON-RPC result `{turnId}`; `expectedTurnId` is a required active-turn precondition, so a stale steer fails instead of landing in the wrong turn |
| Idempotency handle | none — the recipient does not deduplicate an injected message | `clientUserMessageId` on both `turn/start` and `turn/steer` |
| Between turns | The inbox exists for the life of the process | `turn/steer` refuses; `codex queue --thread <id> --message <text>` accepts and answers `Queued message <uuid>`, but **delivers only after the running turn completes** — measured against a busy session: every tool call stayed in the running turn, then a new turn opened with the message |

Two consequences the contract must carry:

1. **The session carrier cannot use this channel for Claude.** Session mode is
   one headless process per turn, and a headless inbox drops what it accepts.
   In-turn delivery to Claude exists only under the window carrier. A session
   carrier keeps `wait`.
2. **The two harnesses differ by a whole turn when idle.** Claude's inbox takes
   a message at any time; Codex takes one into a live turn only through steer,
   and otherwise only at the next turn boundary. A durable queue between the
   thread and the adapter is therefore not an optimisation — it is what makes
   one channel out of two different timings.

### Channel

`claims.CHANNELS` gains `queue`; `bee_thread_deliveries.channel` is
`TEXT NOT NULL` with no CHECK, so no thread migration is required, and
`bee.threads:capabilities` reports the new channel from the same copy. `push`
stays declared and unused for a future direct transport. A delivery claimed on
`queue` asserts one thing: the bytes for this obligation travel through a
binding's inbox row, and the acceptance that settles it is the harness's own
answer, never the enqueue.

### Store

`bee_gateway_inbox` in the gateway store, beside `bee_gateway_hooks` — the
symmetric twin of the hook intake: hooks are the child's observations
travelling up and committed by the carrier, inbox rows are the thread's
messages travelling down and accepted by the child.

| column | meaning |
|---|---|
| `message_id` | PK, minted at enqueue |
| `binding_id` | destination binding; attempt, action, thread and owner incarnation come from it, never from a payload |
| `carrier_epoch` | the epoch that enqueued the row |
| `delivery_id`, `thread_message_id`, `record_id`, `sequence` | the thread delivery this row carries |
| `body_json`, `digest` | the bounded rendered message and a sha256 over its canonical form |
| `status` | `queued`, `claimed`, `dispatched`, `accepted`, `refused`, `rejected` |
| `claimed_epoch`, `claimed_at`, `dispatched_at`, `accepted_at` | fence and evidence |
| `client_message_id` | the idempotency handle the harness accepts, where it has one (Codex); NULL for Claude |
| `refused_reason`, `rejected_reason` | the harness's refusal, or why nothing will carry the row |
| `created_at`, `updated_at` | |

`dispatched` is the durable form of the dispatch intent that contract requires: it
commits **before** any byte reaches the child, in its own gateway-store
transaction, separate from the thread commit.

### Lifecycle

| Rule | Definition |
|---|---|
| Enqueue | **The gateway fills the queue, not the carrier.** Obligations belong to the child, and claims are self-service: that contract leaves delegation out deliberately, so no second actor may claim what the child owes. The gateway already runs every thread tool *as the bound subject* (`funcs.new():with_context(...):with_actor(security.new_actor(binding.subject)):with_scope(...)`), and `inbox_fill` uses that same executor to call `bee.threads.delivery:claim` with channel `queue`, renders each claimed obligation to a bounded body and inserts one `queued` row. The child's own actor therefore claims its own obligations, exactly as when it calls `thread_read`; the carrier never impersonates it and the contract needs no delegation operation. Enqueue is not delivery: the thread delivery stays `claimed`. A claim that cannot be enqueued (bounds, sealed intake) is released at once, returning the obligation to `pending`. |
| Claim | The carrier drains the queue on the same tick as `drain_hooks` through `inbox_claim {binding_id, carrier_epoch, limit}`: sequence order, takeover of lower epochs, never a higher epoch, refusal below the highest admitted epoch. |
| Dispatch | Mark `dispatched`, then hand the body to the adapter. Between those two the row is the only durable evidence that bytes may have left. |
| Accept | The adapter returns the harness's acceptance, and `inbox_settle` records it. The thread acknowledgment travels the same subject executor as the claim did: `bee.threads.delivery:ack` for an acceptance, so the obligation becomes `delivered` by the existing path, and `release` for a refusal, returning it to `pending`. Marking the row and answering the thread commit in the same operation keeps the two stores from disagreeing about one delivery without a carrier in between. A refusal settles nothing. |
| Not steerable yet | For Codex, `turn/steer` outside a live turn and `NonSteerableTurnKind` (`review`, `compact`) are **not** refusals: the row stays `queued` and drains at the next turn, or the carrier places it through `codex queue`, whose `Queued message <uuid>` becomes the row's `client_message_id`. A row waiting for a turn boundary is never `uncertain`. |
| No silent redelivery | A row left `dispatched` by a lost carrier is not redispatched where the harness has no idempotency handle, because a second dispatch would put the same text in the model's context twice. Claude has none, so the replacement leaves the row `dispatched`, lets the thread claim expire into `uncertain`, and reconciliation decides (redeliver through a fresh row, or abandon). Codex has `clientUserMessageId`: a replacement may re-steer under the same handle, and the harness deduplicates. |
| Seal and revoke | `seal` stops enqueue; `revoke` rejects unclaimed rows. At close the carrier seals, drains within `drain_ms`, rejects unclaimed rows (`attempt settled`) and revokes. A `dispatched` row is never rejected automatically — that would assert an outcome the gateway cannot prove. |
| Settles nothing | An inbox row never settles a turn, never extends an ended attempt, never creates an action, approval or grant, and never answers a request on the thread. A reply is a record the child writes through `thread_message`. |
| Bounds | Per binding at most 64 rows in `queued`/`claimed`/`dispatched` together, body at most 32 KiB; past either, enqueue refuses and the claim is released, so backpressure reaches the thread as an unclaimed obligation rather than a lost message. |

### Per-harness adapters

| Harness | Carrier | Transport | Acceptance |
|---|---|---|---|
| Claude Code | **window only** | `{"type":"auth","token":…}` then `{"type":"user","message":{"role":"user","content":…}}`, one NDJSON line each, on the socket the host assigned with `--messaging-socket-path`, authenticated with the token the child published in its isolated `CLAUDE_CONFIG_DIR` | `peer_message_status`; `delivered` accepts, the other states refuse with their reason |
| Codex | window or session | `turn/steer {threadId, expectedTurnId, input, clientUserMessageId}` over `app-server --stdio` | the JSON-RPC result `{turnId}`; an error refuses with its code |

The socket path must be short: Claude Code refuses a Unix path over 103 bytes,
which a workspace-relative path under a long state directory will exceed, so
the host allocates it in a short runtime directory it owns.

Claude Code's frame set, its `--messaging-socket-path` flag and its key file
are undocumented and were read from the 2.1.278 binary and confirmed on the
stand. They are pinned exactly as Codex hook trust hashes are pinned: the
adapter binds to a measured executable version, and a new version needs renewed
validation before the channel is admitted.

### What this makes possible: a parent and the agents it launches

The pieces then compose without anything further:

1. A parent agent calls `thread_launch` with a definition its launch policy
   names and a brief. Placement starts the child under its own binding, with
   its own gateway tools, on the same thread.
2. The child works and writes `thread_message` records. Each commit creates one
   obligation per recipient — the existing authority path, unchanged.
3. The parent's carrier claims its obligations on `queue`, enqueues them and
   dispatches: into the parent's live turn if it is a window carrier, at its
   next turn otherwise. The parent learns what the child said **while it is
   working**, without polling and without spending a tool round on
   `thread_wait`.
4. The parent answers with its own `thread_message`, which reaches the child by
   the same path through the child's binding.
5. Timeline shows the whole exchange with its delivery marks; Approvals decides
   anything that needs a human; the thread remains the durable record after
   every process involved has exited.

Mixed harnesses need no special case: a Claude parent and a Codex child (or the
reverse) differ only in which adapter their carriers use, because both accept a
message into a live turn and both report an acceptance the queue can settle on.

### Proof order

1. Channel: a delivery claimed on `queue` is accepted, reported by capabilities, refused with an unknown channel; no thread migration runs.
2. Queue rules, pure: enqueue bounds and release-on-refusal, claim ordering and epoch takeover, the six statuses, retention, and that `dispatched` is never auto-rejected.
3. Claude adapter, window carrier, real harness: a record committed while a tool is running reaches the model **in the same provider request as that tool's result** — the stand's own trap is that a message arriving as a *new* turn also looks like success, so the assertion must name the `tool_result`. `peer_message_status` marks the row `accepted` and the obligation `delivered`; a refusing recipient marks `refused` and returns the obligation to `pending`.
4. Claude, session carrier: the headless entrypoint accepts the frames and delivers nothing, so the session carrier must refuse channel `queue` and keep `wait`. This is a proof that the refusal exists, not that delivery works.
5. Codex adapter, real harness: `turn/steer` during a live turn puts the marker in the next provider request of the **same** turn, which completes as one turn; a steer with a stale `expectedTurnId` fails; a row enqueued while idle stays `queued` and drains at the next turn without ever becoming `uncertain`.
6. Carrier loss: a carrier held after `dispatched` and replaced leaves exactly one row and no second dispatch for Claude (reconciliation decides), and exactly one delivered message for Codex under the same `clientUserMessageId`.
7. Lifecycle: seal stops enqueue while dispatched rows drain, revoke rejects unclaimed rows, close rejects `attempt settled`, a sealed binding's queue is still its carrier's to drain.
8. Cross-model, end to end: a Claude parent launches a Codex child through `thread_launch`, the child writes `thread_message`, the parent receives it inside a running turn and answers on the thread, and Timeline shows both records with their delivery marks.

### What Bee must add on its side

The Lua surface has no socket client (`exec`, `fs`, `http_client`, `process`,
`sql` and the driver kit are what a carrier has), so the two adapters do not
cost the same:

| Adapter | What it needs |
|---|---|
| Codex | Nothing new: the app server speaks JSON-RPC over stdio, which the driver kit and the native executor already do. `initialize` answers there; the `--listen unix://` socket did not answer it on the probe host, so stdio is the surface to build on |
| Claude Code | **A native unix-socket client.** Writing two NDJSON lines to the child's inbox and reading its `peer_message_status` back is not expressible in the current Lua surface, and shelling out to `socat` would put an external binary on a delivery path. This is a Bee-side gap of the same kind the inventory already records for process-group signalling and `inherit_env` |

Until that native piece exists, the Claude adapter cannot be implemented, and a
window carrier for Claude keeps `wait` exactly like a session carrier.

### Implementation status (2026-09-22)

| Piece | State |
|---|---|
| Channel `queue` in `claims.CHANNELS`, error text, capabilities test | written |
| Migration 13 `bee_gateway_inbox` (unique on `binding_id, delivery_id`) | written |
| `inbox_enqueue`, `inbox_claim`, `inbox_dispatched`, `inbox_settle`, `inbox_reject`, `inbox_queue` and their registry entries | written |
| Carrier and window drain: claiming on `queue`, enqueueing, dispatch intent and settlement | written |
| Native `peerinbox` client and the Claude adapter | written; the package is not yet registered in `wippy.build.json` |
| Lint | clean, 510 entries, 0 errors |
| Live delivery | **never observed.** No message has reached a child through this queue: the table has held no row and every obligation stays `pending` |

Downward delivery is therefore unproven. The contract above is settled and the
code is written, but nothing has yet been carried to a child by it. `gateway_inbox`
is enabled only for the Claude window policy on purpose: Codex has no adapter,
because Bee starts its TUI rather than an app-server and there is nothing to
deliver through, so enabling the flag there would only spend an empty tick a
second.
