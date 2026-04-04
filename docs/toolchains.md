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
| 1 | `.spawn.toml` | Explicit config (`[workspace]`, `[toolchain]`) |
| 2 | `.devcontainer/devcontainer.json` | Parsed from image or features |
| 3 | `.devcontainer/devcontainer.json` with `build.dockerfile` or root `Dockerfile` / `Containerfile` | Requires explicit runtime selection |
| 4 | Project files | See file detection table below |
| 5 | *(fallback)* | `base` (Ubuntu 24.04 + Node.js) |

### File detection

| File | Toolchain |
|------|-----------|
| `Cargo.toml` or `rust-toolchain.toml` | Rust |
| `go.mod` or `go.sum` | Go |
| `CMakeLists.txt` | C++ |
| `bun.lock` or `bun.lockb` | JS/TS (`js`) |
| `deno.json` or `deno.jsonc` | JS/TS (`js`) |
| `deno.lock` | JS/TS (`js`) |
| `pnpm-lock.yaml` | JS/TS (`js`) |
| `yarn.lock` | JS/TS (`js`) |
| `package-lock.json` or `npm-shrinkwrap.json` | JS/TS (`js`) |
| `package.json` | JS/TS (`js`) |
| *(none of the above)* | Base |

Note: `Makefile` alone does not trigger the C++ toolchain -- it is too common across languages.

## Available toolchains

| Toolchain | Image | Contents |
|-----------|-------|----------|
| `base` | `spawn-base:latest` | Ubuntu 24.04, Node.js, Python 3, Claude Code, Codex, gh CLI, ripgrep, fd |
| `cpp` | `spawn-cpp:latest` | Base + Clang 21, CMake, Ninja, GDB, Valgrind |
| `rust` | `spawn-rust:latest` | Base + Rust (via rustup) |
| `go` | `spawn-go:latest` | Base + Go 1.24 |
| `js` | `spawn-js:latest` | Base + Node.js 22 LTS, Corepack, Bun, Deno |

All toolchain images extend `spawn-base:latest`, so they include everything in the base image plus language-specific tools.

## Overriding detection

### CLI flag

```bash
spawn --toolchain rust
```

### .spawn.toml

Create a `.spawn.toml` file in your project root:

```toml
[workspace]
agent = "codex"

[toolchain]
base = "rust"
```

Valid values:

- `workspace.agent`: `claude-code`, `codex`
- `toolchain.base`: `base`, `cpp`, `rust`, `go`, `js`

`.spawn.toml` can set the default agent and toolchain preference. Host access still requires an explicit `--access ...` at launch time.

### Custom image

To use an entirely different image, bypassing toolchain detection:

```bash
spawn --image my-custom-image:latest
```

### Workspace-defined runtimes

If a workspace defines its own runtime with a root `Dockerfile` / `Containerfile`, or with `.devcontainer/devcontainer.json` and `build.dockerfile`, `spawn` keeps `auto` conservative and requires an explicit runtime choice.

Build and run the workspace-defined image directly:

```bash
spawn --runtime workspace-image
```

Or opt into spawn-managed images explicitly:

```bash
spawn --runtime spawn
```

When you use `--runtime workspace-image`, spawn stores cache metadata in its state directory and reuses the built image until the tracked Dockerfile, optional `.dockerignore`, devcontainer config, or non-ignored build-context file contents or permissions change.
Pass `--rebuild-workspace-image` alongside `--runtime workspace-image` to force a rebuild even when the cache is up to date.
`spawn doctor` reports that cache state and the tracked input paths, including `.dockerignore` when present, so rebuild decisions are inspectable.

## Devcontainer support

spawn reads `.devcontainer/devcontainer.json` and maps the image or features to a toolchain. This lets projects that already use devcontainers work with spawn without additional configuration.

If a viable `.devcontainer/devcontainer.json` is present, spawn prefers it over file-based heuristics. The launch summary and `spawn doctor` output tell you when that config drove the selection.

When a devcontainer uses `build.dockerfile`, spawn treats that as a workspace-defined runtime. Use `--runtime workspace-image` to build and run it directly with cache reuse, or `--runtime spawn` to ignore it and use spawn-managed images.
