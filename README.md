# spawn

Sandboxed AI coding agents on macOS. Built to run Claude Code or Codex in
filesystem-isolated Linux containers with a single command.

```bash
spawn build       # build container images (once)
spawn             # run Claude Code in current directory
spawn -- cargo test
spawn doctor      # check local images, config, and workspace detection
spawn doctor -C ~/code/project
spawn doctor --json
```

spawn detects your project's language, picks the right container image, mounts
your code, and launches the agent. Your files are read/write inside the
container — everything else on your system is isolated.

## Status

`spawn` is a work in progress. PRs are welcome.

The goal is similar to [Jai](https://jai.scs.stanford.edu/) on Linux: a jail
for your agents that you'll actually use. On macOS we do not have the same
underlying isolation model, so `spawn` takes the pragmatic route and builds on
Apple's container and virtualization stack.

It's written in Swift so it can directly use Apple's Containerization and
Virtualization frameworks when that becomes the right boundary, instead of
being limited to a shell wrapper forever.

## What it does

`spawn` wraps Apple's [`container`](https://github.com/apple/containerization) CLI to launch AI coding agents in lightweight Linux VMs.

- **Auto-detects toolchains** — Rust, Go, C++, and JS/TS projects (Node, Bun, Deno), or falls back to a base image
- **Safe mode by default** — prompts before `git push`, PR creation, and other remote-write operations
- **Uses explicit access profiles** — default `minimal`, with opt-in `git` and `trusted` host auth exposure
- **Persists OAuth credentials** across runs — authenticate once, not every session
- **No API keys required** — Pro/Max plan users authenticate via OAuth

## Requirements

- macOS 26+
- Apple's [`container`](https://github.com/apple/containerization) CLI: `brew install container`
- Swift 6.3+ (for building from source; `make test` prefers Xcode when installed)

## Install

### Homebrew (recommended)

```bash
brew install container
brew install vmunix/tap/spawn
```

### From source

```bash
git clone https://github.com/vmunix/spawn.git
cd spawn
make install    # builds release and installs to ~/.local/bin
```

Ensure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Quick start

```bash
# Build all container images (required once)
spawn build

# Or build just what you need
spawn build rust    # also: base, cpp, go, js

# Run Claude Code in your project
spawn

# Run Codex instead
spawn codex

# Run an arbitrary command
spawn -- cargo test

# Run in another workspace
spawn -C ~/code/project

# Opt into git identity and gh auth without exposing SSH keys
spawn --access git

# Drop into a shell for debugging
spawn --shell

# Check your local setup and current workspace
spawn doctor
spawn doctor -C ~/code/project
spawn doctor --json
```

## Usage

### Running agents

```bash
spawn [agent] [options]
spawn -- <command...>
spawn doctor [-C <dir>]
```

| Option | Description |
|--------|-------------|
| `--yolo` | Skip permission gates (default: safe mode, prompts before git push) |
| `--shell` | Drop into a shell instead of running an agent |
| `-C, --cwd <dir>` | Directory to mount as workspace (default: current directory) |
| `--runtime <name>` | Runtime mode: `auto`, `spawn`, `workspace-image` |
| `--rebuild-workspace-image` | Force a rebuild when using `--runtime workspace-image` |
| `--access <name>` | Host access profile: `minimal`, `git`, `trusted` |
| `--toolchain <name>` | Override auto-detected toolchain: `base`, `cpp`, `rust`, `go`, `js` |
| `--image <name>` | Override auto-selected container image |
| `--mount <dir>` | Mount an additional directory (repeatable) |
| `--read-only <dir>` | Mount a directory read-only (repeatable) |
| `--cpus <n>` | CPU cores for the container (default: 4) |
| `--memory <size>` | Container memory (default: 8g) |
| `--env <KEY=VALUE>` | Set environment variable (repeatable) |
| `--env-file <path>` | Load environment variables from a file |
| `--verbose` | Show the container command being run |

Run an arbitrary command in the workspace container by passing it after `--`:

```bash
spawn -- cargo test
spawn -C ~/code/project -- swift test
```

Access profiles control host auth exposure:

- `minimal` mounts only the workspace, requested extra mounts, and persisted agent state
- `git` additionally mounts git config and `gh` CLI auth
- `trusted` additionally mounts selected SSH config and standard `id_*` key material copied from `~/.ssh`

Runtime mode controls how spawn reacts when a workspace defines its own runtime:

- `auto` is the default
- `spawn` opts into spawn-managed images explicitly
- `workspace-image` builds and runs the workspace-defined image directly

`workspace-image` reuses a cached workspace image when the tracked Dockerfile, devcontainer config, and build-context file metadata have not changed.
Use `--rebuild-workspace-image` with `--runtime workspace-image` when you want to bypass the cache explicitly.

If your repo has a root `Dockerfile` / `Containerfile`, or a `.devcontainer/devcontainer.json` with `build.dockerfile`, spawn currently requires an explicit choice:

```bash
spawn --runtime workspace-image
spawn --runtime workspace-image --rebuild-workspace-image
spawn --runtime spawn
```

### Building images

```bash
spawn build [toolchain] [options]
```

Omit the toolchain to build all images. Base is built first since other images depend on it.

| Option | Description |
|--------|-------------|
| `--cpus <n>` | CPU cores for the builder container (default: 4) |
| `--memory <size>` | Builder container memory (default: 8g) |

### Managing containers

```bash
spawn list              # list running containers
spawn stop <id>         # stop a container
spawn exec <id> <cmd>   # run a command in a running container
spawn shell <id>        # open /bin/bash in a running container
spawn doctor            # check local images, config, and workspace detection
spawn doctor -C ~/code/project
spawn doctor --json     # same report in machine-readable form
```

### Managing images

```bash
spawn image list        # list spawn images
spawn image list --all  # list all container images
spawn image rm <name>   # remove a spawn image
```

## Safe mode

By default, spawn runs agents in **safe mode**. Remote-write operations require approval:

- `git push`
- `git remote add` / `set-url`
- `gh pr create` / `merge` / `close`
- `gh issue create` / `close`
- `gh release`, `gh repo`

Use `--yolo` to skip all permission gates.

## Configuration

### Environment variables

Place a `KEY=VALUE` file at `~/.config/spawn/env` to set environment variables for every run. Lines starting with `#` are comments. Values can be quoted.

### Project-level config

Add a `.spawn.toml` to your repo root to set workspace defaults:

```toml
[workspace]
agent = "codex"

[toolchain]
base = "rust"
```

Valid values:

- `workspace.agent`: `claude-code`, `codex`
- `toolchain.base`: `base`, `cpp`, `rust`, `go`, `js`

Repo config can set the default agent and toolchain preference. Host access still requires an explicit `--access ...` at launch time, even if `.spawn.toml` contains an `access` value.

spawn also reads `.devcontainer/devcontainer.json` to infer toolchains from images and features. If a viable devcontainer config is present, spawn prefers that explicit signal over repo-file heuristics. This makes existing VS Code devcontainer projects work with zero extra setup.

`spawn doctor` also checks whether the local `container` services are running. If they are not, it points you at `container system start --enable-kernel-install`, which is the most common first-machine fix.

## Devcontainer support

If your project already uses `.devcontainer/devcontainer.json`, spawn treats that as the strongest project signal after `.spawn.toml`.

- devcontainer image/features are mapped to spawn toolchains
- the launch summary and `spawn doctor` show when `.devcontainer/devcontainer.json` drove the choice
- this makes spawn a good fit for projects already set up for VS Code Dev Containers

If `.devcontainer/devcontainer.json` uses `build.dockerfile`, `spawn --runtime workspace-image` builds and runs that workspace-defined image directly and reuses it until the tracked build inputs change. `spawn --runtime spawn` remains available when you want to ignore the workspace runtime and use spawn-managed images instead.

For JS/TS repos, `spawn-js:latest` bundles Node.js 22 LTS, Corepack, Bun, and Deno so the common runtime and package-manager paths work out of the box.

## Documentation

For detailed guides on permissions, authentication, and architecture, see the [documentation](https://vmunix.github.io/spawn/).

## Development

```bash
make build              # Debug build
make test               # Lint + tests (prefers Xcode's SwiftPM when available)
make smoke              # End-to-end workspace-first and workspace-image tests
make install            # Install to ~/.local/bin
```

## License

MIT
