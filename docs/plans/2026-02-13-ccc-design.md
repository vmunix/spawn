# ccc — Containerized Claude Code

Dead-simple sandboxed AI coding agents on macOS via Apple's Virtualization framework.

## Problem

Running AI coding agents (Claude Code, OpenAI Codex) directly on your machine gives them access to your entire filesystem. You want filesystem isolation — the agent should only see the repos you explicitly grant access to — without sacrificing ergonomics.

## Solution

A Swift CLI (`ccc`) that wraps Apple's `container` tool to run agents inside lightweight Linux VMs with only specified directories mounted via VirtioFS.

```bash
cd ~/code/my-project
ccc .                    # auto-detect toolchain, start claude-code
ccc . codex              # use codex instead
ccc . --shell            # drop into a shell for debugging
```

## Architecture

```
+-------------------------------------+
|  ccc CLI                            |  <- This tool
|  (Swift, ArgumentParser)            |
+-----------+-------------------------+
|  Toolchain Detection                |  <- .ccc.toml, devcontainer, auto-detect
|  Agent Profiles                     |  <- claude-code, codex, custom
+-----------+-------------------------+
|  container CLI (Apple)              |  <- Orchestration
|  (OCI images, VirtioFS, vmnet)      |
+-----------+-------------------------+
|  Virtualization.framework           |  <- VM runtime
|  (macOS 26, Apple Silicon)          |
+-------------------------------------+
```

`ccc` owns the UX and agent-specific logic. Apple's `container` CLI handles all VM/container mechanics.

## Requirements

- macOS 26 (Tahoe) on Apple Silicon
- Apple's `container` CLI installed

## CLI Interface

```
ccc <path> [agent] [options]

Arguments:
  <path>                   Directory to mount (typically ".")
  [agent]                  Agent to run: claude-code (default), codex, or custom profile name

Options:
  --mount <host-path>      Additional directory to mount (repeatable)
  --read-only <host-path>  Mount additional directory read-only (repeatable)
  --env <KEY=VALUE>        Pass environment variable (repeatable)
  --env-file <path>        Load env vars from file (default: ~/.ccc/env)
  --image <oci-image>      Override the base image
  --toolchain <name>       Override auto-detected toolchain (base, cpp, rust, go)
  --cpus <n>               CPU cores (default: 4)
  --memory <size>          Memory (default: 8G)
  --shell                  Drop into shell instead of running agent
  --hook <script>          Run script inside container before starting agent
  --no-git                 Don't mount ~/.gitconfig or SSH agent
  --verbose                Show container commands being executed

ccc build [agent]          Build/pull base images
ccc list                   List running containers
ccc stop <id>              Stop a running container
ccc exec <id> <cmd>        Execute command in running container
```

### Examples

```bash
# Simplest: auto-detect everything, run claude-code
cd ~/code/burrow && ccc .

# Use codex instead
cd ~/code/sdk_rs && ccc . codex

# Mount additional reference code read-only
ccc . --mount ~/code/shared-lib --read-only ~/code/docs

# Override toolchain detection
ccc . --toolchain cpp

# Debug the container environment
ccc . --shell

# Extra setup before agent starts
ccc . --hook ./scripts/install-deps.sh
```

## Toolchain Detection

When `ccc .` is invoked, the toolchain is resolved in priority order:

1. **`.ccc.toml`** in repo root — explicit configuration, highest priority
2. **`.devcontainer/devcontainer.json`** — parse image/build/features fields
3. **`Dockerfile` or `Containerfile`** in repo root — build and use directly
4. **Auto-detect from repo files:**
   - `Cargo.toml` / `rust-toolchain.toml` -> rust
   - `go.mod` / `go.sum` -> go
   - `CMakeLists.txt` / `Makefile` / `*.cpp` / `*.c` -> cpp
   - `package.json` / `tsconfig.json` -> base (node already included)
   - `pyproject.toml` / `requirements.txt` -> base (python already included)
5. **Fallback** -> `ccc-base`

### .ccc.toml format

```toml
[toolchain]
base = "cpp"                              # base, cpp, rust, go, or custom image
packages = ["clang-18", "libboost-dev"]   # extra apt packages
setup = "./scripts/setup-dev.sh"          # run after container start

[agent]
default = "claude-code"                   # default agent
```

### .devcontainer support

Read from `.devcontainer/devcontainer.json`:
- `image` — use as base image directly
- `build.dockerfile` — build with `container build`
- `features` — map to toolchain (e.g., rust feature -> ccc-rust)
- `containerEnv` — pass as environment variables
- `mounts` — respect additional mount specifications

### Dockerfile support

If a `Dockerfile` or `Containerfile` exists in the repo root (and no higher-priority config is found), `ccc` builds it with `container build`, caches the result, and runs the agent inside it. The agent CLI (claude-code/codex) is injected at runtime if not already present in the image.

## Agent Profiles

Built-in profiles define how each agent is configured:

```swift
struct AgentProfile {
    let name: String              // "claude-code"
    let defaultImage: String      // "ghcr.io/owner/ccc-claude-code:latest"
    let entrypoint: [String]      // ["claude"]
    let requiredEnvVars: [String] // ["ANTHROPIC_API_KEY"]
    let defaultMounts: [Mount]    // ~/.gitconfig, SSH agent
    let defaultCPUs: Int
    let defaultMemory: UInt64
}
```

Built-in: `claude-code`, `codex`. Custom profiles can be added as JSON files in `~/.ccc/profiles/`.

## Base Images

Layered Containerfiles:

### ccc-base
```dockerfile
FROM ubuntu:24.04
RUN apt-get update && apt-get install -y \
    git curl wget build-essential \
    python3 python3-pip python3-venv \
    nodejs npm \
    ripgrep fd-find jq tree \
    openssh-client ca-certificates
RUN npm install -g @anthropic-ai/claude-code
```

### ccc-cpp (extends base)
```dockerfile
FROM ccc-base:latest
RUN apt-get install -y \
    clang clang-format clang-tidy \
    cmake ninja-build gdb valgrind
```

### ccc-rust (extends base)
```dockerfile
FROM ccc-base:latest
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
```

### ccc-go (extends base)
```dockerfile
FROM ccc-base:latest
RUN curl -fsSL https://go.dev/dl/go1.23.linux-arm64.tar.gz | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
```

## Directory Mounting

| Source | Guest Path | Mode |
|--------|-----------|------|
| Target directory (positional arg) | `/workspace/<dirname>` (cwd) | read-write |
| `--mount` directories | `/workspace/<dirname>` | read-write |
| `--read-only` directories | `/workspace/<dirname>` | read-only |
| `~/.gitconfig` | `/root/.gitconfig` | read-only |
| SSH agent socket | `$SSH_AUTH_SOCK` | read-write |

Working directory inside the container is set to `/workspace/<target-dirname>`.

**Isolation guarantee:** Only explicitly specified directories and git/SSH config are visible inside the VM. The host filesystem is otherwise inaccessible.

## Environment & Secrets

API keys loaded from `~/.ccc/env` by default (overridable with `--env-file`):

```
ANTHROPIC_API_KEY=sk-ant-...
OPENAI_API_KEY=sk-...
```

`ccc` validates required env vars per agent profile before starting the container. Clear error message if missing.

## Implementation: ContainerRunner

Core logic wraps `container` CLI invocations:

```swift
func run(profile: AgentProfile, target: URL, mounts: [Mount], env: [String: String]) async throws {
    var args = ["run", "--rm"]

    // Resources
    args += ["--cpus", "\(profile.defaultCPUs)"]
    args += ["--memory", "\(profile.defaultMemory)"]

    // Mounts
    args += ["--volume", "\(target.path):/workspace/\(target.lastPathComponent)"]
    for mount in mounts {
        args += [mount.readOnly ? "--mount" : "--volume",
                 "\(mount.hostPath):/workspace/\(mount.name)\(mount.readOnly ? ":ro" : "")"]
    }

    // Environment
    for (key, value) in env {
        args += ["--env", "\(key)=\(value)"]
    }

    // Working directory and entrypoint
    args += ["--workdir", "/workspace/\(target.lastPathComponent)"]
    args += [profile.defaultImage]
    args += profile.entrypoint

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/local/bin/container")
    process.arguments = args
    // Forward stdio, handle signals...
    try process.run()
    process.waitUntilExit()
}
```

## Project Structure

```
ccc/
├── Package.swift
├── Sources/
│   └── ccc/
│       ├── CLI.swift                # ArgumentParser: run, build, list, stop, exec
│       ├── AgentProfile.swift       # Built-in + custom agent profiles
│       ├── ToolchainDetector.swift   # Priority-ordered detection chain
│       ├── DevcontainerParser.swift  # .devcontainer/devcontainer.json support
│       ├── ContainerRunner.swift     # Wraps `container` CLI process execution
│       ├── ImageManager.swift        # Build, pull, cache image variants
│       ├── Config.swift              # .ccc.toml parsing, ~/.ccc/ management
│       └── MountResolver.swift       # Resolve paths, handle defaults (git, ssh)
├── Images/
│   ├── base/Containerfile
│   ├── cpp/Containerfile
│   ├── rust/Containerfile
│   └── go/Containerfile
├── Tests/
│   ├── ToolchainDetectorTests.swift
│   ├── ConfigTests.swift
│   └── MountResolverTests.swift
└── docs/
    └── plans/
```

## Out of Scope

- Network isolation / firewall rules
- Multi-container orchestration (compose)
- Persistent named volumes
- GPU passthrough
- GUI
- Image registry hosting
- Cross-architecture support (Intel Macs)
