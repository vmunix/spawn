---
title: Getting Started
nav_order: 2
---

# Getting Started

## Requirements

- **macOS 26+** (Tahoe or later)
- Apple's [`container`](https://github.com/apple/containerization) CLI: `brew install container`
- **Swift 6.3+** (only for building from source; `make test` prefers Xcode when installed)

## Installing

### Homebrew (recommended)

```bash
brew install vmunix/tap/spawn
```

### From source

```bash
git clone https://github.com/vmunix/spawn.git
cd spawn
make install    # builds release and installs to ~/.local/bin
```

Add `~/.local/bin` to your `PATH` if it isn't already:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that line to your shell profile (`~/.zshrc` or `~/.bashrc`) to make it permanent.

## Building container images

spawn uses layered container images. The base image must be built first, then toolchain-specific images extend it.

```bash
# Build all images at once (base is built first automatically)
spawn build

# Or build individually
spawn build base
spawn build rust
spawn build cpp
spawn build go
spawn build js
```

The builder container defaults to 4 CPUs and 8GB memory. If a build fails with an out-of-memory error, increase the allocation:

```bash
spawn build --memory 16g --cpus 8
```

## First run

Navigate to a project directory and run spawn:

```bash
cd ~/code/my-project
spawn
```

spawn will:

1. Detect your project's toolchain from files like `Cargo.toml`, `go.mod`, `CMakeLists.txt`, `package.json`, `bun.lock`, or `deno.json`
2. Select the matching container image (e.g., `spawn-rust:latest`)
3. Mount your project directory read/write into the container
4. Use the default `minimal` access profile unless you opt into host auth
5. Launch Claude Code in safe mode

On first run, Claude Code will prompt you to authenticate via OAuth. Your credentials are persisted in `~/.local/state/spawn/claude-code/` so you only need to authenticate once.

To use Codex instead:

```bash
spawn codex
```

To skip all permission prompts:

```bash
spawn --yolo
```

To drop into a bash shell inside the container (useful for debugging):

```bash
spawn --shell
```

To reuse host git identity and `gh` auth without exposing SSH keys:

```bash
spawn --access git
```

If the repo defines its own runtime with a root `Dockerfile` / `Containerfile`, or a devcontainer `build.dockerfile`, spawn currently requires an explicit runtime choice:

```bash
spawn --runtime workspace-image
spawn --runtime spawn
```

`spawn --runtime workspace-image` reuses the built workspace image until the tracked build inputs change.
Context-root `.dockerignore` rules are respected, so ignored files do not trigger rebuilds.
Add `--rebuild-workspace-image` when you want to force a rebuild.
Use `spawn doctor` to inspect the current cache state and the tracked workspace-image inputs.

If your project already has a `.devcontainer/devcontainer.json`, spawn uses that as an explicit signal before falling back to file-based heuristics. This makes existing VS Code devcontainer projects work nicely with spawn.
