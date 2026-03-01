---
title: Home
nav_order: 1
---

# spawn

Sandboxed AI coding agents on macOS. Run Claude Code or Codex in filesystem-isolated Linux containers with a single command.

```bash
spawn build       # build container images (once)
spawn .           # run Claude Code in current directory
```

spawn detects your project's language, picks the right container image, mounts your code, and launches the agent. Your files are read/write inside the container -- everything else on your system is isolated.

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

# Full auto mode (no permission prompts)
spawn . --yolo

# Drop into a shell for debugging
spawn . --shell
```

## What it does

`spawn` wraps Apple's [`container`](https://github.com/apple/containerization) CLI to launch AI coding agents in lightweight Linux VMs.

- **Auto-detects your project's toolchain** (C++, Rust, Go) and picks the right container image
- **Safe mode by default** -- prompts before `git push`, PR creation, and other remote-write operations
- **Mounts git config and SSH keys** so the agent can commit and push
- **Persists OAuth credentials** across runs -- authenticate once, not every session
- **No API keys required** -- Pro/Max plan users authenticate via OAuth
