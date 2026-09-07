# Foundation status

The next implementation boundary is specified in
[Local desktop](LOCAL_DESKTOP.md): workspace bindings and attachment ownership,
then the maintained shell and a standalone native Terminal. It distinguishes
the target design from the current core-only checkpoint below.

The production composition is the desktop core plus standalone **Settings** and **Process Manager** applications. Default boot opens no applications.
This supersedes earlier checkpoints that bundled Welcome and Colors or started
Welcome automatically. The large desktop design remains a roadmap, not a claim
that every subsystem already exists.

## Production boundary

`wippy.lock` loads only `src/` and has no external module dependencies. Settings and Process Manager are the bundled applications; both launch on demand.
The loaded registry includes pure UI libraries, scoped process definitions,
policies and explicit hosts; these are not application instances.

The workspace starts a private desktop session, broker and replaceable presenter.
The session and broker own layout and application lifecycle respectively. The
workspace retains the physical terminal lease. No fixture, AI, MCP, chat, HTTP,
SQL, exec provider, workflow, or domain subsystem is installed or started by default.
The terminal host is an explicit native core resource, not an implicit dependency
on a test or utility package.

Every subsequently admitted app runs as its own process. The current admission
list contains Settings and Process Manager and supports only view-owned apps; it is a protected host declaration,
not a second application catalog. The broker validates metadata after admission.
It does not admit an arbitrary process merely because it declares app metadata.

Child scopes are replaced explicitly. Fixture app scopes deny ambient actions;
their own terminals work through assigned producer capabilities. Presenter mounts
are bound to its PID. The bootstrap owner argument is trusted only because private
core entries are spawned by the trusted workspace entry. The presenter cannot
spawn processes or create scopes. Before admitting arbitrary code,
restrict spawn targets and bind attachment creation to authenticated bootstrap
context. Later sender checks alone do not authenticate a caller-supplied owner.

The pure model contains no PID, grant, terminal handle, registry or application
code. The session owns committed geometry and focus; the presenter previews drags
and routes input to a requested focus while its session acknowledgement is pending.
The model supports minimize/restore, collapse and left/right snap through session
commands, exposed through title controls, shortcuts and window context menus. Window
messages retain restoration mode, and the decoder rejects minimized focus as
well as malformed, sparse and duplicate window records. View revocation
is handled without indexing missing snapshots.

Rendering receives only value snapshots and cannot launch, message or resize
applications. The layout library supplies both drawing and pointer geometry;
the bindings library classifies press and release consistently. Cursor mapping
respects the focused viewport's content bounds. Collapsed windows retain the
producer's dimensions instead of shrinking a live application's terminal.

F12 performs an acknowledged presenter retirement and fresh-PID attachment.
The broker revokes the previous mounts before granting new ones. Application
processes, producer viewports, session state and stable tab order survive. The
physical output holds its last frame until a hydrated presenter draws. Unexpected
presenter exit has a bounded retry path. Exhaustion or readiness timeout keeps
the applications and last screen, with F12 to retry and Ctrl+Q to exit. Core
service failure still ends the workspace.
This is live rejoin, not disk persistence or a native release update mechanism.

## Tests and archive isolation

The old implementation and local state live outside the repo at `../bee-legacy/`.
All 246 previously tracked paths were checked after the move. There are no source
or package references to that archive. Shells that were already inside it can
retain a stale logical working-directory prompt; launching their `run.sh` still
starts the old `casha-shell`. Use the new repository root launcher explicitly.

`tests/lua/` contains unit entries and `examples/fixtures/` contains Welcome and
Colors. A temporary test workspace composes those with a copy of the core and an
explicit fixture admission list. Its pinned test dependency is isolated from the
production lock and pack. These files are never part of default registry loading.

`make check` verifies the actual source and packed registries match the declared
core and bundled-app entries, with no fixture/test/legacy definitions. It tests empty
source and pack boot, plus the optional fixture source/pack interaction suite:
independent state, scope denial, immediate post-focus key delivery, Tab passthrough,
active-tab fullscreen preservation, four resize corners, color semantics, shrink
and growth through 1×1, close and clean exit. Unit cases cover model and decoder
invariants. The fixture presenter has an injected incarnation marker and crash
trigger, excluded from core source and pack. Tests prove six explicit rejoins
and crash recovery, including retry exhaustion and manual retry, preserve
content, app PID, geometry and tab order without
releasing the physical screen. The PTY harness applies synchronized output as
complete frames. Tests use temporary registry stores, not user state.

The local `.wippy/registry.db` inspected during cleanup contained only an empty
version-0 changeset, so no saved app changes were being replayed there. The reported
old sixteen-app UI was launched explicitly as `casha-shell` from the moved POC
working directory. No user registry data was deleted to address it.

## Remaining gates

Durable workspace identity, filesystem bindings, persistence, external attachment,
service/run ownership, application installation, user overlays and native release
updates are not implemented yet. The broker is not a production untrusted-code admission
service. The presenter polls cached viewport revisions every 33 ms; load and latency
need measurement before choosing a different invalidation mechanism.

Native releases update the protected runtime/core. A future single executable
embeds the same core pack; user data and overlays remain external. The desired
`bee <application>` path opens the chosen app directly without a dashboard or
provider wizard. Provider drivers, hooks, threads and MCP remain independent.

The shell now has a cell-native Bee wordmark, one application/status bar, bounded
Start menu and standalone Settings with 14 themes and 11 backgrounds. Shell
appearance is retained across presenter replacement. The next persistence boundary
is durable workspace preferences. Filesystem bindings and an independently installed Terminal follow
those boundaries. Shared UI libraries are not a mandatory application framework.

## Native startup

The local runtime includes a CLI startup fix: lint/pack progress no longer imports
a UI dependency that queried terminal background from package initialization.
That query could block before Bee could draw its boot frame. A native regression
uses a controlling PTY that never answers queries; the Bee acceptance suite also
launches the real `run.sh` from another directory without answering terminal queries.
The runtime change lives in the native checkout; copying the Bee pack alone does
not upgrade an older executable.

## Latest shell refinement

Start is a compact hierarchical launcher: Tools contains Settings and Process
Manager. Window actions are contextual, menus support hover without activation,
and nested levels have a back control instead of an instruction legend. Drag
previews remain visible until the session commits placement, preventing the old
bounds from flashing after a drop.

Process Manager samples host processes, supervised services, heap, GC, goroutines
and scheduler counters once a second while running. Histories retain 60 samples;
unavailable data and counter resets produce gaps. Scheduler steps are not CPU
utilization. The broker authenticates its end-app requests and permits only
workspace-owned app instances. Supervisor inspection does not grant service
control. Inspection covers processes exposed by runtime hosts, not an OS-wide
process inventory. Pause suspends sampling; closing the app ends its sampler.

The source now separates `src/core`, `src/ui` and `src/apps` without changing
registry identities. See PACKAGE_BOUNDARIES.md for the planned multi-package,
runtime installation and complete authorized self-edit requirements.
