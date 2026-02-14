# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build                          # Debug build
swift build -c release               # Release build
swift test                           # Run all tests
swift test --filter ToolchainDetector  # Run tests in one file
swift test --filter "detectsRust"    # Run a single test by name
swift run spawn .                      # Run from source (defaults to claude-code agent)
swift run spawn . codex --verbose      # Run with verbose output showing container command
make build                           # Release build
make test                            # Lint + run tests
make lint                            # Run swift-format linter
make format                          # Auto-fix formatting in-place
make smoke                           # End-to-end smoke tests (cpp/go/rust fixtures in containers)
make install                         # Install to /usr/local/bin
```

## Architecture

`spawn` is a Swift CLI that wraps Apple's `container` tool to run AI coding agents (Claude Code, Codex) in filesystem-isolated Linux VMs on macOS. The user runs `spawn .` from a repo directory; the tool auto-detects the toolchain, selects the right container image, mounts only the specified directories, and launches the agent.

### Run Command Pipeline

The `run` subcommand (default) orchestrates all modules in sequence:

```
RunCommand.run()
  → AgentProfile.named()          # Validate agent (claude-code/codex)
  → ToolchainDetector.detect()    # Auto-detect or use override
  → ImageResolver.resolve()       # Map toolchain to image name
  → MountResolver.resolve()       # Build mount list (workspace + git/SSH + agent state)
  → EnvLoader.load/loadDefault()  # Load env vars from ~/.config/spawn/env
  → ContainerRunner.run()         # Build args, execv (TTY) or Process (pipe)
```

### Toolchain Detection Priority

`ToolchainDetector.detect(in:)` returns `Toolchain?` — `nil` means a Dockerfile was found and should be built directly:

1. `.spawn.toml` `[toolchain] base = "..."` — explicit config
2. `.devcontainer/devcontainer.json` — parsed by `DevcontainerParser`
3. `Dockerfile` / `Containerfile` in repo root — returns nil
4. Auto-detect from repo files (`Cargo.toml` → rust, `go.mod` → go, `CMakeLists.txt` → cpp). Note: `Makefile` alone does not trigger cpp — it's too common across languages.
5. Fallback → `.base`

### Key Design Decisions

- **All container interaction goes through Apple's `container` CLI** (auto-detected at `/opt/homebrew/bin/container` or `/usr/local/bin/container`, falling back to PATH; overridable via `CONTAINER_PATH` env var). `ContainerRunner` constructs argument arrays and invokes it.
- **`ContainerRunner.buildArgs()` is a pure function** — takes all inputs, returns `[String]`. This is what tests verify. The actual process execution (`ContainerRunner.run()`) is not unit tested since it requires the container runtime.
- **TTY via `execv`**: When stdin is a real terminal, `ContainerRunner.run()` uses `execv` to replace the spawn process with `container`, giving it direct TTY access (required for `-t` flag and interactive I/O). When stdin is a pipe, it falls back to `Foundation.Process` with signal forwarding.
- **Agents run in sandbox mode**: Claude Code gets `--dangerously-skip-permissions`, Codex gets `--full-auto` — the container is the sandbox.
- **OAuth credential persistence**: Agent credentials are stored in `~/.local/state/spawn/<agent>/` on the host, mounted into containers so users authenticate once. No API keys required for Pro/Max plan users.
- **VirtioFS limitation**: Single-file bind mounts don't support atomic rename (EBUSY). `~/.claude.json` is a symlink into a directory mount (`~/.claude-state/`) to work around this.
- **Containerfile content is embedded in `ContainerfileTemplates.swift`** as string literals so `spawn build` works after installation (no dependency on repo file paths).
- **Claude Code uses the native installer** (not npm) — installed as `coder` user at `/home/coder/.local/bin/claude`.

## Testing

Tests use Apple's `swift-testing` framework (added as an explicit package dependency since Command Line Tools alone don't include the test runner).

- Tests use `@Test func` and `#expect()` — not XCTest
- `Tests/TestHelpers.swift` provides `makeTempDir(files:)` for creating temporary directory fixtures with specified file contents
- Temp directories are auto-cleaned on first `makeTempDir` call per test run
- `TestHelpers.swift` imports Foundation; test files import `Testing` and `@testable import spawn`

### Smoke Tests

`make smoke` runs end-to-end tests using fixture projects in `fixtures/`:

| Fixture | Toolchain | What it tests |
|---------|-----------|---------------|
| `fixtures/cpp-sample/` | cpp (clang-21) | CMake + Ninja build, ctest |
| `fixtures/go-sample/` | go | `go build` + `go test` |
| `fixtures/rust-sample/` | rust | `cargo build` + `cargo test` |

Each fixture is a minimal but buildable/testable project. Spawn auto-detects the toolchain, selects the image, and runs build+test inside the container. Requires images to be built first (`spawn build`).

## Module Reference

| Module | Responsibility |
|--------|---------------|
| `BuildCommand.swift` | Writes embedded template to temp file, invokes `container build`, enforces base-first ordering |
| `CLI.swift` | `@main` entry point, `Spawn` root command with subcommand registration |
| `ContainerRunner.swift` | `buildArgs()` pure function + `run()` via execv/Process + `runRaw()` passthrough; redacts env vars in debug logs |
| `ContainerfileTemplates.swift` | Embedded Containerfile strings for base/cpp (clang-21)/rust/go; parameterized version constants |
| `DevcontainerParser.swift` | Parses devcontainer.json: image, build.dockerfile, features, containerEnv |
| `EnvLoader.swift` | Parses KEY=VALUE files (comments, quotes), validates required vars, `parseKeyValue(_:)` utility |
| `ImageChecker.swift` | Pre-flight image existence check against container CLI's image store |
| `ImageCommand.swift` | `spawn image` group: `list` (default, filters to spawn-*), `rm` (safety-validated, spawn-* only) |
| `ImageResolver.swift` | `Toolchain` → `"spawn-{toolchain}:latest"`, validates via OCI Reference |
| `Log.swift` | Shared `Logger` instance (swift-log), bootstrapped to stderr, default level `.warning` |
| `MountResolver.swift` | Builds mount list; copies git/SSH with symlink filtering and 0600 permissions on private keys |
| `Paths.swift` | XDG Base Directory path resolution (configDir, stateDir) |
| `SpawnError.swift` | Structured runtime error type (containerFailed, containerNotFound, imageNotFound, runtimeError) |
| `ToolchainDetector.swift` | Priority-ordered detection chain, delegates to `DevcontainerParser` |
| `Types.swift` | `Toolchain` enum, `Mount` struct (two initializers: auto-derive guest path, or custom), `AgentProfile` |

## Coding Conventions

Aligned with Apple's `container` and `containerization` repos for consistency as we integrate the library.

### Formatting

Use `.swift-format` (config in repo root). Key rules:
- **Import ordering:** alphabetical, enforced by formatter
- **Trailing commas:** always, for cleaner diffs
- **Early exits:** prefer `guard` over nested `if`
- **Never force unwrap or force try** — use `guard let`, `try?`, or propagate errors
- **File-scoped privacy:** default to `private` for file-scoped declarations, explicit `public` on APIs
- **Line length:** 180 characters max

### Sendable

Mark all types `Sendable` explicitly. Structs with `Sendable` members get it automatically, but declare it anyway for clarity. When wrapping non-Sendable resources, use `nonisolated(unsafe)` with `NSLock` protection.

### Error Handling

Use a structured error type with code classification rather than bare `ValidationError` from ArgumentParser:
- Runtime errors (image not found, container failure) should use a dedicated `SpawnError` type
- `ValidationError` is reserved for CLI argument validation only
- Include context: error code, message, and optional cause

### Documentation

Document public types and non-obvious functions with `///` comments. Focus on:
- Protocol requirements (parameter docs, throws/returns)
- Non-obvious behavior or workarounds
- Module-level type descriptions
- Skip trivial getters/setters and self-evident code

### Logging

Uses [swift-log](https://github.com/apple/swift-log) with `StreamLogHandler.standardError`. A shared `logger` (in `Log.swift`) defaults to `.warning` (silent); commands set `.debug` when `--verbose` is passed. Use `logger.debug()` for diagnostic output (container commands, internal state). Keep `print()` for user-facing status messages (build progress, etc.). Environment variable values are redacted in debug output (`KEY=***`).

### Security

- **Mount paths are validated** — `--mount` and `--read-only` paths must exist and be directories
- **SSH keys are copied, not mounted directly** — copied to XDG state dir with symlink filtering and 0600 permissions on private keys
- **`spawn image rm` only removes `spawn-*` images** — protects base OS images and `spawn-base` (which other images depend on)
- **Env var values are redacted in `--verbose` output** — prevents credential leakage in logs

### Future Patterns

As spawn grows, adopt these patterns from the containerization library:
- **Configuration structs with builder closures** for complex initialization (e.g., container config)
- **Private state enums** with associated values for lifecycle management (e.g., VM states)

## Migration Path

spawn is gradually migrating from shelling out to Apple's `container` CLI toward using the `containerization` Swift library directly.

- **Current state:** `ContainerizationOCI` used for image reference validation and pre-flight image checks.
- **Seam:** `ContainerRunner` is the boundary where all `container` CLI interaction happens. Future library integration replaces its internals without changing callers.
- **Domain types:** spawn's `Mount`, `Toolchain`, etc. remain the domain model. Adapt to library types at the boundary only.
- **Next steps:** Add `Containerization` module to replace `container run` (VM lifecycle, VirtioFS, process I/O).
