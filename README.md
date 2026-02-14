# spawn

Sandboxed AI coding agents on macOS. Run Claude Code or Codex in filesystem-isolated Linux containers with a single command.

## What it does

`spawn` wraps Apple's [`container`](https://github.com/apple/containerization) CLI to launch AI coding agents in lightweight Linux VMs. Your project directory is mounted into the container — the agent can read and write your code, but nothing else on your system is accessible.

- Auto-detects your project's toolchain (C++, Rust, Go) and picks the right container image
- Mounts git config and SSH keys so the agent can commit and push
- Persists OAuth credentials across runs — authenticate once, not every session
- Drops into a shell with `--shell` for manual debugging

## Requirements

- macOS 26+
- Apple's [`container`](https://github.com/apple/containerization) CLI installed
- Swift 6.2+ (for building from source)

## Install

```bash
git clone https://github.com/vmunix/spawn.git
cd spawn
make install    # builds release and copies to /usr/local/bin
```

## Quick start

```bash
# Build the base container image (required once)
spawn build base

# Build a toolchain image for your project
spawn build rust    # or: cpp, go

# Run from repo directly
cd ~/code/my-project; spawn . 

# Run Claude Code against your project
spawn ~/code/my-project

# Run Codex instead
spawn ~/code/my-project codex

# Drop into a shell for debugging
spawn ~/code/my-project --shell
```

## Usage

```
USAGE: spawn <subcommand>

SUBCOMMANDS:
  run (default)     Run an AI coding agent in a sandboxed container
  build             Build container images
  image             Manage spawn images (list, rm)
  list              List running containers
  stop              Stop a running container
  exec              Execute a command in a running container
```

### `spawn run` (default)

```
spawn <path> [agent] [options]

ARGUMENTS:
  path              Directory to mount as workspace
  agent             claude-code (default), codex

OPTIONS:
  --mount <dir>           Additional directory to mount (repeatable)
  --read-only <dir>       Mount directory read-only (repeatable)
  --env <KEY=VALUE>       Environment variable (repeatable)
  --env-file <path>       Path to env file
  --image <name>          Override base image
  --toolchain <name>      Override toolchain: base, cpp, rust, go
  --cpus <n>              CPU cores (default: 4)
  --memory <size>         Memory (default: 8g)
  --shell                 Drop into shell instead of running agent
  --no-git                Don't mount ~/.gitconfig or SSH keys
  --verbose               Show container commands
```

## Toolchain detection

spawn auto-detects your project's language:

| File | Toolchain |
|------|-----------|
| `.spawn.toml` | Explicit config |
| `devcontainer.json` | Parsed from image/features |
| `Cargo.toml` | Rust |
| `go.mod` | Go |
| `CMakeLists.txt` | C++ |
| *(fallback)* | Base (Ubuntu 24.04 + Node.js) |

Override with `--toolchain rust` or set `[toolchain] base = "rust"` in `.spawn.toml`.

## Authentication

On first run, you'll need to authenticate Claude Code and the GitHub CLI inside the container. Each only needs to be done once — credentials are persisted across runs.

```bash
# First run: Claude Code will prompt you to authenticate via OAuth
spawn ~/code/my-project

# To authenticate gh, drop into a shell and run the login flow
spawn ~/code/my-project --shell
# then inside the container:
gh auth login
```

Claude Code credentials are persisted in `~/.local/state/spawn/<agent>/`. The `gh` CLI config from your host (`~/.config/gh/`) is mounted into the container, but tokens stored in the macOS keychain don't transfer — so the in-container `gh auth login` is needed once.

Alternatively, you can pass API keys directly:

```bash
spawn . --env ANTHROPIC_API_KEY=sk-...
spawn . --env GH_TOKEN=ghp_...
spawn . --env-file ~/secrets/env
```

Environment variables are also loaded from `~/.config/spawn/env` (KEY=VALUE format).

## Container images

```bash
spawn build              # Build all images (base + toolchains)
spawn build rust         # Build just one
spawn image list         # List spawn images
spawn image rm spawn-rust:latest  # Remove an image
```

Images are layered: toolchain images extend `spawn-base`, which provides Ubuntu 24.04, Node.js, git, and the agent CLIs.

## Development

```bash
swift build              # Debug build
swift test               # Run all 76 tests
make test                # Lint + tests
make smoke               # End-to-end tests against real containers
```

## License

MIT
