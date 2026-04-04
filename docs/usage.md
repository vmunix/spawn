---
title: Usage
nav_order: 3
---

# Usage

## Subcommands

| Command | Description |
|---------|-------------|
| `spawn run` (default) | Run an AI coding agent or arbitrary command in a sandboxed container |
| `spawn build` | Build container images |
| `spawn image list` | List available spawn images |
| `spawn image rm` | Remove one or more spawn images |
| `spawn list` | List running containers |
| `spawn stop` | Stop a running container |
| `spawn exec` | Execute a command in a running container |
| `spawn shell` | Open a shell in a running container |
| `spawn doctor` | Check local images, config, and workspace detection |

`run` is the default subcommand, so `spawn` is equivalent to `spawn run`.

## spawn run

```
USAGE: spawn run [<agent>] [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `agent` | Optional agent to run: `claude-code` (default), `codex` |

### Options

| Option | Description |
|--------|-------------|
| `--yolo` | Skip permission gates (default: safe mode, prompts before git push) |
| `--shell` | Drop into shell instead of running agent |
| `-C, --cwd <dir>` | Directory to mount as workspace (default: current directory) |
| `--runtime <name>` | Runtime mode: `auto`, `spawn`, `workspace-image` |
| `--rebuild-workspace-image` | Force a rebuild when using `--runtime workspace-image` |
| `--access <name>` | Host access profile: `minimal`, `git`, `trusted` |
| `--toolchain <name>` | Override auto-detected toolchain: `base`, `cpp`, `rust`, `go`, `js` |
| `--image <name>` | Override auto-selected container image |
| `--mount <dir>` | Additional directory to mount (repeatable) |
| `--read-only <dir>` | Mount directory read-only (repeatable) |
| `--cpus <n>` | CPU cores for the container (default: 4) |
| `--memory <size>` | Container memory (default: 8g) |
| `--env <KEY=VALUE>` | Set environment variable (repeatable) |
| `--env-file <path>` | Load environment variables from a file |
| `--verbose` | Show the container command being run |

To run an arbitrary command instead of an agent, pass it after `--`:

```bash
spawn -- cargo test
spawn -C ~/code/project -- swift test
```

Access profiles control host auth exposure:

- `minimal` mounts only the workspace, requested extra mounts, and persisted agent state
- `git` additionally mounts git config and `gh` CLI auth
- `trusted` additionally mounts copied SSH material

Runtime mode controls how spawn handles workspaces that define their own runtime:

- `auto` is the default
- `spawn` opts into spawn-managed images explicitly
- `workspace-image` builds and runs the workspace-defined image directly

`workspace-image` reuses a cached workspace image when the tracked Dockerfile, devcontainer config, and build-context file metadata have not changed.
Use `--rebuild-workspace-image` with `--runtime workspace-image` when you want to bypass the cache explicitly.

If your repo has a root `Dockerfile` / `Containerfile`, or a `.devcontainer/devcontainer.json` with `build.dockerfile`, use:

```bash
spawn --runtime workspace-image
spawn --runtime workspace-image --rebuild-workspace-image
spawn --runtime spawn
```

### Examples

```bash
# Run Claude Code with auto-detected toolchain in the current directory
spawn

# Run Codex instead
spawn codex

# Run an arbitrary command in the workspace container
spawn -- cargo test

# Pick another workspace
spawn -C ~/code/project

# Build and run the workspace-defined image directly
spawn --runtime workspace-image

# Force a rebuild of the workspace-defined image
spawn --runtime workspace-image --rebuild-workspace-image

# Opt into spawn-managed images for a Dockerfile-based workspace
spawn --runtime spawn

# Opt into git identity and gh auth without exposing SSH keys
spawn --access git

# Run a command in another workspace
spawn -C ~/code/project -- swift test

# Full auto mode (no permission prompts)
spawn --yolo

# Mount additional directories
spawn --mount ~/shared-libs --mount ~/data

# Mount a directory read-only
spawn --read-only ~/reference-docs

# Pass environment variables
spawn --env ANTHROPIC_API_KEY=sk-ant-...

# Use an env file
spawn --env-file ~/.config/spawn/env

# Override the auto-detected toolchain
spawn --toolchain rust
spawn --toolchain js

# Override the container image entirely
spawn --image my-custom-image:latest

# Allocate more resources
spawn --cpus 8 --memory 16g

# Debug: drop into a shell
spawn --shell

# See what container command spawn is running
spawn --verbose
```

## spawn build

```
USAGE: spawn build [<toolchain>] [--cpus <cpus>] [--memory <memory>] [--verbose]
```

Build container images. Omit the toolchain to build all images (base is built first automatically since other images depend on it).

```bash
spawn build            # Build all images
spawn build base       # Build the base image
spawn build rust       # Build the Rust toolchain image
spawn build cpp        # Build the C++ toolchain image
spawn build go         # Build the Go toolchain image
spawn build js         # Build the JS/TS toolchain image
```

### Options

| Option | Description |
|--------|-------------|
| `--cpus <n>` | CPU cores for the builder container (default: 4) |
| `--memory <size>` | Builder container memory (default: 8g) |
| `--verbose` | Show build commands |

## spawn image

```bash
spawn image list       # List spawn-* images
spawn image list --all # List all images including non-spawn ones
spawn image rm spawn-rust:latest spawn-go:latest  # Remove images
```

`spawn image rm` only removes `spawn-*` images and refuses to remove `spawn-base` (since other images depend on it).

## spawn list / stop / exec

```bash
spawn list              # List running containers
spawn stop <id>         # Stop a running container
spawn exec <id> -- ls   # Run a command in a running container
spawn shell <id>        # Open /bin/bash in a running container
spawn doctor            # Check local setup and workspace detection
spawn doctor --json     # Same report in machine-readable form
```

`spawn doctor` reports the workspace image resolution and, when `.spawn.toml` is present, the configured workspace defaults such as `agent` and `access`.
For workspace-image runtimes it also shows cache state plus the tracked Dockerfile, context, config, and cache-record paths.
`spawn doctor --json` emits a `checks` array together with a structured `workspace` object for automation.
