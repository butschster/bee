<p align="center">
  <img src="docs/assets/banner.svg" alt="Bee terminal workspace logo with the terminal bee mark and Bee wordmark" width="1200">
</p>

<p align="center"><strong>A persistent terminal workspace for people, agents, and the tools they build together.</strong></p>

<p align="center">
  <a href="docs/README.md">Documentation</a> ·
  <a href="CONTRIBUTING.md">Contributing</a> ·
  <a href="LICENSE">MIT license</a> ·
  <a href="https://github.com/wippyai/runtime">Wippy</a>
</p>

Bee is a terminal desktop for coding. It keeps shells, managed coding agents,
standalone applications, approvals and durable threads in one workspace. The
executable includes the desktop and default apps, so a local session can start
offline. Hub access is optional and is used to inspect or install components.

![Bee terminal desktop showing Settings, Terminal, and Process Manager](docs/assets/desktop.gif)

## Run

From a project directory:

```sh
bee
bee claude
bee codex
bee agy
bee grok
bee muse
```

A named command opens the selected managed profile through the same admission
path as the Agent picker. The host admits its reviewed options, instructions,
MCP scope, hooks, placement and recovery behavior.

Use a second terminal for a read-only retained display:

```sh
bee observe
bee desktops
bee attach WORKSPACE DISPLAY
bee observe WORKSPACE DISPLAY
```

These commands address the Bee selected by `--state-dir`. An occupied display
has one controller; observation is separate and cannot send input. Detaching a
controller leaves admitted applications running.

## Workspace surfaces

| Surface | Behavior |
|---|---|
| Desktop | Independent client layouts, retained application execution, controller and observer attachment, presenter replacement, themes, resize, mouse and keyboard input |
| Terminal | Native interactive programs with the operating-system user's authority |
| Agents | Claude, Codex, Agy, Grok and Muse profiles with scoped MCP, driver hooks, durable threads and qualified recovery |
| Overlays | Agent-authored declarative applications staged, frozen, reviewed, approved and applied by Governance |
| Modules | Read-only Hub inspection plus host-authorized local plan and apply with requirements, migrations and receipts |
| Coordination | Durable Threads and Timeline, subscriptions, Approvals, Inbox projection and scoped agent-to-agent launch |
| Operations | Settings, Process Manager, Modules, Overlays, Approvals, Timeline, Hive Manager, About and the UI Guide |

Press **F1** for Start, **Alt+Tab** to switch apps, **F11** to maximize and
**Ctrl+Q** to detach. Drag by a window title and resize from a corner. **F12**
replaces the presenter while applications continue running. Supported
application state can recover after restart; a native terminal is not made
portable by the workspace.

## Boundaries

An admitted component may define services, functions, owned databases and
migrations, drivers, traits, agents and an optional UI. Bee governs the exact
definitions, target permissions, lifecycle and receipts. Component services own
their protocol and state. Registry metadata describes capabilities; it never
grants authority.

The implemented local boundary includes desktop/client attachment and
observation, Hub inspection and installation, governed application overlays,
managed agents, and policy-routed Hive operations. Hive Manager reports
admitted catalog state; it is not general remote control. Public Hive
enrollment and discovery, remote workspace composition, destination Hub
transfer/install, and managed headless launch are not callable operations.

## Install from source

Native builds target Linux and macOS on amd64 and arm64. Build with Git, Go
1.27.0 and a C compiler:

```sh
make setup
make standalone
mkdir -p "$HOME/.local/bin"
install -m755 dist/bee "$HOME/.local/bin/bee"
export PATH="$HOME/.local/bin:$PATH"
```

See [native distribution](docs/operations/native.md) and
[releasing](docs/operations/releasing.md) for installation and release procedures.

## Development

Start with the [agent guide](docs/development/agent-guide.md) and
[development conventions](docs/development/conventions.md). Production loads only `src/`;
tests and development tools are not runtime dependencies.

```sh
make lint
make check
make pack
make standalone
```

| Code | Purpose |
|---|---|
| [src/core](src/core) | Workspace host, applications, desktop, client and storage |
| [src/ui](src/ui) | Shared appearance and application helpers |
| [src/apps](src/apps) | Bundled standalone application processes |
| [src/hub](src/hub) | Local package planning, apply and receipts |
| [src/governance](src/governance) | Overlay authoring, review, activation and recovery |
| [src/hive](src/hive) | Authenticated cross-node operation contracts |
| [src/threads](src/threads) | Durable records, subscriptions and delivery |
| [tests](tests) | Model, source/pack and native acceptance |

[Application contracts](docs/reference/applications.md) ·
[Package boundaries](docs/development/package-boundaries.md) ·
[System map](docs/development/ownership.md)

## License

Bee-owned code and artwork are [MIT](LICENSE). Wippy retains MPL-2.0;
dependencies retain their own licenses.

[Code of conduct](https://github.com/wippyai/.github/blob/main/.github/CODE_OF_CONDUCT.md) · [Security](SECURITY.md)
