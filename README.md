# spawn

Sandboxed AI coding agents on macOS. Run Claude Code or Codex in filesystem-isolated Linux containers with a single command.

```bash
spawn build       # build container images (once)
spawn .           # run Claude Code in current directory
```

spawn detects your project's language, picks the right container image, mounts your code, and launches the agent. Your files are read/write inside the container — everything else on your system is isolated.

## What it does

`spawn` wraps Apple's [`container`](https://github.com/apple/containerization) CLI to launch AI coding agents in lightweight Linux VMs.

- **Auto-detects toolchains** — Rust (`Cargo.toml`), Go (`go.mod`), C++ (`CMakeLists.txt`), or falls back to a base image
- **Safe mode by default** — prompts before `git push`, PR creation, and other remote-write operations
- **Mounts git config and SSH keys** so the agent can commit and push
- **Persists OAuth credentials** across runs — authenticate once, not every session
- **No API keys required** — Pro/Max plan users authenticate via OAuth

## Requirements

- macOS 26+
- Apple's [`container`](https://github.com/apple/containerization) CLI: `brew install container`
- Swift 6.2+ (for building from source)

## Install

### Homebrew (recommended)

```bash
brew tap vmunix/tap
brew install spawn
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
spawn build rust    # also: base, cpp, go

# Run Claude Code in your project
spawn .

# Run Codex instead
spawn . codex

# Drop into a shell for debugging
spawn . --shell
```

## Usage

### Running agents

```bash
spawn <path> [agent] [options]
```

| Option | Description |
|--------|-------------|
| `--yolo` | Skip permission gates (default: safe mode, prompts before git push) |
| `--shell` | Drop into a shell instead of running an agent |
| `--no-git` | Don't mount git/SSH config into the container |
| `--toolchain <name>` | Override auto-detected toolchain: `base`, `cpp`, `rust`, `go` |
| `--image <name>` | Override auto-selected container image |
| `--mount <dir>` | Mount an additional directory (repeatable) |
| `--read-only <dir>` | Mount a directory read-only (repeatable) |
| `--cpus <n>` | CPU cores for the container (default: 4) |
| `--memory <size>` | Container memory (default: 8g) |
| `--env <KEY=VALUE>` | Set environment variable (repeatable) |
| `--env-file <path>` | Load environment variables from a file |
| `--verbose` | Show the container command being run |

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

Add a `.spawn.toml` to your repo root to pin a toolchain:

```toml
[toolchain]
base = "rust"
```

spawn also reads `.devcontainer/devcontainer.json` to infer toolchains from images and features.

## Documentation

For detailed guides on permissions, authentication, and architecture, see the [documentation](https://vmunix.github.io/spawn/).

## Development

```bash
make build              # Debug build
make test               # Lint + tests
make smoke              # End-to-end tests against real containers
make install            # Install to ~/.local/bin
```

## License

MIT
