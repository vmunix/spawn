---
title: Home
nav_order: 1
---

# spawn

Sandboxed AI coding agents on macOS. Run Claude Code or Codex in filesystem-isolated Linux containers with a single command.

```bash
cd ~/code/my-project
spawn .           # Claude Code, auto-detected toolchain
spawn . codex     # or Codex
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
# Build the base container image (required once)
spawn build base

# Build a toolchain image for your project
spawn build rust    # or: cpp, go

# Run Claude Code against your project
spawn ~/code/my-project

# Run Codex instead
spawn ~/code/my-project codex

# Drop into a shell for debugging
spawn ~/code/my-project --shell
```

## What it does

`spawn` wraps Apple's [`container`](https://github.com/apple/containerization) CLI to launch AI coding agents in lightweight Linux VMs.

- **Auto-detects your project's toolchain** (C++, Rust, Go) and picks the right container image
- **Mounts git config and SSH keys** so the agent can commit and push
- **Persists OAuth credentials** across runs -- authenticate once, not every session
- **Safe mode by default** -- remote git operations require approval (use `--yolo` to disable)
- **Drop into a shell** with `--shell` for manual debugging
