---
title: Usage
nav_order: 3
---

# Usage

## Subcommands

| Command | Description |
|---------|-------------|
| `spawn run` (default) | Run an AI coding agent in a sandboxed container |
| `spawn build` | Build container images |
| `spawn image list` | List available spawn images |
| `spawn image rm` | Remove one or more spawn images |
| `spawn list` | List running containers |
| `spawn stop` | Stop a running container |
| `spawn exec` | Execute a command in a running container |

`run` is the default subcommand, so `spawn .` is equivalent to `spawn run .`.

## spawn run

```
USAGE: spawn run <path> [<agent>] [options]
```

### Arguments

| Argument | Description |
|----------|-------------|
| `path` | Directory to mount as workspace (e.g., `.`) |
| `agent` | Agent to run: `claude-code` (default), `codex` |

### Options

| Option | Description |
|--------|-------------|
| `--yolo` | Skip permission gates (default: safe mode, prompts before git push) |
| `--shell` | Drop into shell instead of running agent |
| `--no-git` | Don't mount git/SSH config into the container |
| `--toolchain <name>` | Override auto-detected toolchain: `base`, `cpp`, `rust`, `go` |
| `--image <name>` | Override auto-selected container image |
| `--mount <dir>` | Additional directory to mount (repeatable) |
| `--read-only <dir>` | Mount directory read-only (repeatable) |
| `--cpus <n>` | CPU cores for the container (default: 4) |
| `--memory <size>` | Container memory (default: 8g) |
| `--env <KEY=VALUE>` | Set environment variable (repeatable) |
| `--env-file <path>` | Load environment variables from a file |
| `--verbose` | Show the container command being run |

### Examples

```bash
# Run Claude Code with auto-detected toolchain
spawn .

# Run Codex instead
spawn . codex

# Full auto mode (no permission prompts)
spawn . --yolo

# Mount additional directories
spawn . --mount ~/shared-libs --mount ~/data

# Mount a directory read-only
spawn . --read-only ~/reference-docs

# Pass environment variables
spawn . --env ANTHROPIC_API_KEY=sk-ant-...

# Use an env file
spawn . --env-file ~/.config/spawn/env

# Override the auto-detected toolchain
spawn . --toolchain rust

# Override the container image entirely
spawn . --image my-custom-image:latest

# Allocate more resources
spawn . --cpus 8 --memory 16g

# Debug: drop into a shell
spawn . --shell

# See what container command spawn is running
spawn . --verbose
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
```
