---
title: Toolchains
nav_order: 4
---

# Toolchains

spawn auto-detects your project's toolchain and selects the right container image. You can also override the detection with a flag or config file.

## Auto-detection

Detection runs in priority order. The first match wins:

| Priority | Source | Toolchain |
|----------|--------|-----------|
| 1 | `.spawn.toml` | Explicit config (`[toolchain] base = "..."`) |
| 2 | `.devcontainer/devcontainer.json` | Parsed from image or features |
| 3 | `Dockerfile` / `Containerfile` | Returns nil (build directly) |
| 4 | Project files | See file detection table below |
| 5 | *(fallback)* | `base` (Ubuntu 24.04 + Node.js) |

### File detection

| File | Toolchain |
|------|-----------|
| `Cargo.toml` or `rust-toolchain.toml` | Rust |
| `go.mod` or `go.sum` | Go |
| `CMakeLists.txt` | C++ |
| *(none of the above)* | Base |

Note: `Makefile` alone does not trigger the C++ toolchain -- it is too common across languages.

## Available toolchains

| Toolchain | Image | Contents |
|-----------|-------|----------|
| `base` | `spawn-base:latest` | Ubuntu 24.04, Node.js, Python 3, Claude Code, Codex, gh CLI, ripgrep, fd |
| `cpp` | `spawn-cpp:latest` | Base + Clang 21, CMake, Ninja, GDB, Valgrind |
| `rust` | `spawn-rust:latest` | Base + Rust (via rustup) |
| `go` | `spawn-go:latest` | Base + Go 1.24 |

All toolchain images extend `spawn-base:latest`, so they include everything in the base image plus language-specific tools.

## Overriding detection

### CLI flag

```bash
spawn . --toolchain rust
```

### .spawn.toml

Create a `.spawn.toml` file in your project root:

```toml
[toolchain]
base = "rust"
```

Valid values: `base`, `cpp`, `rust`, `go`.

### Custom image

To use an entirely different image, bypassing toolchain detection:

```bash
spawn . --image my-custom-image:latest
```

## Devcontainer support

spawn reads `.devcontainer/devcontainer.json` and maps the image or features to a toolchain. This lets projects that already use devcontainers work with spawn without additional configuration.
