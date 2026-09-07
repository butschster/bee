# Workspace state and application restoration

This is the persistence contract to implement after the current shell pass.
The current workspace keeps preferences and layout in memory and supports live
presenter replacement. It does not yet create this database or restore apps after
runtime exit.

## Ownership and storage

Each workspace has a stable UUID and its own local `.bee/workspace.sqlite`
database, separate from Wippy registry/overlay history. The directory
binding locates that workspace; moving the directory should not change its
identity. The workspace owner is the sole writer of desktop state. Applications
request scoped checkpoint writes; they do not receive SQL access to desktop tables.
Use WAL with transactional migrations and a schema-version table. Do not open one
SQLite file concurrently from different machines as a mesh synchronization design.

Keep these records separate:

| Record | Persistent values |
|---|---|
| Workspace | UUID, directory binding, schema version |
| Preferences | Validated appearance record and its version |
| App instance | Stable instance UUID, admitted definition identity, definition version, restoration policy |
| Window | Instance UUID, tab order, geometry, mode, normal bounds, restore mode, focus |
| Checkpoint | Instance UUID, application schema version, sequence, structured payload, commit time |

PIDs, viewport grants, input capture, mouse drags and native terminal handles are
runtime values. They are recreated, never stored as authority to replay later.
Registry definitions and overlays remain the code/configuration plane. The
workspace database stores user/runtime state. A later shared catalog can supply
versioned application definitions without becoming a shared live workspace database.

## Application protocol

An application advertises restoration support in registry trait metadata. The
versioned contract distinguishes three policies: no automatic restoration,
recreate a view from saved launch state, or recreate it with an app checkpoint.
It does not promise to serialize an arbitrary running program's stack.

1. Bee opens an admitted application with its stable instance identity and an
   optional restore envelope: contract version, application checkpoint schema,
   checkpoint sequence and payload.
2. The app validates or migrates its own checkpoint, recreates resources, then
   reports ready or a typed restoration error. It can declare that a checkpoint
   version is unsupported without discarding it.
3. During operation the app submits replacement checkpoints, with a sequence and
   expected previous sequence. Bee validates sender ownership and commits the
   checkpoint transaction before acknowledging it as durable.
4. A restarted application is a new process with fresh terminal capabilities but
   the same logical instance identity. The restored window retains its position
   and tab order while the app becomes ready.

Keep checkpoint payloads structured and bounded. An app owns their schema;
workspace migrations must not rewrite opaque app data. An application update can
supply a checkpoint migration as part of its declared restoration implementation.
Retain the last committed checkpoint if migration or startup fails, and report the
failed instance without preventing the rest of the desktop from opening.

For native terminals, the terminal app can restore its view, working directory
and launch configuration. Restoring a shell process at an arbitrary instruction
requires a separate process/session retention mechanism; this protocol alone
cannot do that. Services and durable jobs also need a separate lifetime owner.

## Commit and restart behavior

Persist committed layout and preferences as they change, coalescing drag commits
rather than storing each pointer movement. Apps checkpoint at useful boundaries.
Exit must not depend on waiting seconds for every app: the normal recovery point
is the last acknowledged durable checkpoint, and checkpoint status is observable.

A transaction protects each update. It does not imply a synchronized snapshot of
all application processes. A future explicit workspace checkpoint can collect
per-app acknowledgements and report which instances could not participate.

On boot, migrate workspace tables transactionally, load the desktop snapshot,
resolve still-installed definitions through admission, recreate producer views,
and start eligible instances. Unsupported/newer database schemas fail explicitly;
there is no automatic database deletion or downgrade. Unavailable application
versions leave a recoverable instance record instead of silently launching a
substitute or installing code.

A migration test must cover a database from each supported version, rollback of
a failed migration, newer-version rejection, crash interruption and reopen.
Restoration tests must cover fresh PIDs/grants, stable instance IDs, mixed supported
and unsupported checkpoints, failed app startup, theme/layout restoration, and
closing/reopening one instance without affecting another.
