# Package boundaries

Native assembly is now implemented as described in [native distribution](NATIVE_DISTRIBUTION.md).
The scoped local Hub read/plan/apply path and governed overlay
author/freeze/review/apply/recovery path are implemented. Public enrollment,
headless-node launch and destination Hub package transfer/install remain
unfinished; independent package extraction and the alternate overlay operations
below remain proposals.
[System map](SYSTEM_MAP.md) records their relationship to service-owned editable
applications, governance, portable sharing and the distributed inbox.

Normal governed Hub components retain the full Wippy substrate. A component may
define ordinary services and functions, its owned database and migrations,
drivers, traits, agents and optional UI. Bee governs the exact resolved
definitions, destination host-selected permissions and resources, lifecycle and
receipts; registry metadata describes capabilities and does not authorize them.

The shell is the current delivery boundary. Directories distinguish ownership;
separate Hub releases and dependency manifests will follow once the contracts
are stable. Moving a file must not change an application's registry identity.

| Layer | Owns | Depends on |
|---|---|---|
| Core | Desktop/session lifetime, composition, focus, geometry, admission, app lifecycle and workspace persistence | Runtime primitives and shared UI values |
| Shared UI | Appearance, wallpaper and reusable presentation helpers | Value contracts; no application authority |
| Default apps | Terminal, Settings and local Process Manager | Explicit grants and core protocols |
| Optional packages | Lookout, coding tools, harnesses, models and other installed apps or services | Published capability/trait contracts |
| Independent subsystems | Threads, Hub reads/planning/local apply, governed overlay authoring/review/apply/recovery, scoped MCP surfaces | Runtime services and authenticated operation contracts; public enrollment/headless nodes and destination package transfer/install remain future |
| Native Bee extensions | Future coding-specific I/O, file watching and adapters | Native runtime module registration |

Core does not import a default application's implementation. A launcher can name
an admitted definition; this does not couple the renderer or model to its logic.
Every app is a standalone process. Services are separate from windows and must
not acquire a view-owned lifetime merely to appear in navigation.

## Current and future subsystem contracts

The local Hub owner resolves dependencies, verifies package provenance, reviews
capabilities, applies exact plans and records recoverable receipts. Hub search
supports keyword discovery without treating a search match as admission or
authorization. Carrying that request to another Bee remains a destination-owned
operation: that Bee must resolve its own bindings, policy and resources and
produce its own plan and receipt.

Governed authoring already stages bounded files in a durable overlay, freezes an
immutable candidate, shows its definitions and capability effects, obtains an
exact approval and applies the destination-owned runtime overlay with a receipt
and restart recovery. Broader self-edit of the core shell, default applications
and shared libraries remains a maintenance workflow. A baseline bundled in the
binary must remain recoverable. Core source changes belong to the host-selected
maintenance boundary; not every component permits runtime editing or activation.
Being an application actor must not imply core-publication permission.

Edits to a replaceable presenter use the existing live rejoin boundary. Admitted
applications have opt-in checkpoint/restore and compatible live replacement. Stable
workspace/session changes need a coordinated restart and recovery contract; F12
alone does not replace those processes. The native binary has its own build and
restart boundary. These distinctions must be visible to the edit subsystem.

Bee may carry native coding modules before they are mature enough to move into
generic Wippy. Such modules are built into a native release; registry package
installation cannot manufacture a new Go module in an already running process.

Agent-facing operations must continue to ship with exact receipts and recovery
instructions. Descriptive registry entries never grant the permissions they name.

## Native distribution

The native Bee executable embeds the application pack, carries its build and
runtime provenance and can recover its bundled deployment. Hub references retain
their own cache, dependency and installation lifecycle. Registry packages can
install definitions and resources supported by the running executable; they
cannot add a new Go module to that process.

The next distribution slice reuses the existing Hub request, plan and receipt at
an explicitly selected destination Bee. It does not add another installer or
derive authority from Hive membership. Publication remains a separate authority
even when its requests and receipts are carried on threads.

Bee must remain self-sufficient. Kickside components are optional later extensions,
not a prerequisite or current compatibility milestone. Domain adapters should
preserve explicit resource and authorization boundaries so integration remains
possible without coupling the desktop to a web host or external platform.
