---
title: Getting Started
nav_order: 2
---

# Getting Started

## Requirements

- **macOS 26+** (Tahoe or later)
- Apple's [`container`](https://github.com/apple/containerization) CLI: `brew install container`
- **Swift 6.2+** (only for building from source)

## Installing

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

Add `~/.local/bin` to your `PATH` if it isn't already:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

Add that line to your shell profile (`~/.zshrc` or `~/.bashrc`) to make it permanent.

## Building container images

spawn uses layered container images. The base image must be built first, then toolchain-specific images extend it.

```bash
# Build the base image (Ubuntu 24.04 + Node.js + Claude Code + Codex)
spawn build base

# Build toolchain images for your projects
spawn build rust
spawn build cpp
spawn build go

# Or build all images at once
spawn build
```

## First run

Navigate to a project directory and run spawn:

```bash
cd ~/code/my-project
spawn .
```

spawn will:

1. Detect your project's toolchain from files like `Cargo.toml`, `go.mod`, or `CMakeLists.txt`
2. Select the matching container image (e.g., `spawn-rust:latest`)
3. Mount your project directory read/write into the container
4. Copy your git config and SSH keys into the container
5. Launch Claude Code in the container

On first run, Claude Code will prompt you to authenticate via OAuth. Your credentials are persisted in `~/.local/state/spawn/claude-code/` so you only need to authenticate once.

To use Codex instead:

```bash
spawn . codex
```

To drop into a bash shell inside the container (useful for debugging):

```bash
spawn . --shell
```
