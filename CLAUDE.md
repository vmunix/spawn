# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

```bash
swift build                          # Debug build
swift build -c release               # Release build
swift test                           # Run all 41 tests
swift test --filter ToolchainDetector  # Run tests in one file
swift test --filter "detectsRust"    # Run a single test by name
swift run ccc .                      # Run from source (defaults to claude-code agent)
swift run ccc . codex --verbose      # Run with verbose output showing container command
make build                           # Release build
make test                            # Run tests
make install                         # Install to /usr/local/bin
make images                          # Build all container images via Apple's container CLI
```

## Architecture

`ccc` is a Swift CLI that wraps Apple's `container` tool to run AI coding agents (Claude Code, Codex) in filesystem-isolated Linux VMs on macOS. The user runs `ccc .` from a repo directory; the tool auto-detects the toolchain, selects the right container image, mounts only the specified directories, and launches the agent.

### Run Command Pipeline

The `run` subcommand (default) orchestrates all modules in sequence:

```
RunCommand.run()
  → AgentProfile.named()          # Validate agent (claude-code/codex)
  → ToolchainDetector.detect()    # Auto-detect or use override
  → ImageResolver.resolve()       # Map toolchain to image name
  → MountResolver.resolve()       # Build mount list (workspace + git/SSH)
  → EnvLoader.load/loadDefault()  # Load API keys from ~/.ccc/env
  → EnvLoader.validateRequired()  # Check required vars per agent
  → ContainerRunner.run()         # Build args, exec process, forward signals
```

### Toolchain Detection Priority

`ToolchainDetector.detect(in:)` returns `Toolchain?` — `nil` means a Dockerfile was found and should be built directly:

1. `.ccc.toml` `[toolchain] base = "..."` — explicit config
2. `.devcontainer/devcontainer.json` — parsed by `DevcontainerParser`
3. `Dockerfile` / `Containerfile` in repo root — returns nil
4. Auto-detect from repo files (`Cargo.toml` → rust, `go.mod` → go, `CMakeLists.txt` → cpp)
5. Fallback → `.base`

### Key Design Decisions

- **All container interaction goes through Apple's `container` CLI** (`/usr/local/bin/container`). `ContainerRunner` constructs argument arrays and invokes it via `Foundation.Process`.
- **`ContainerRunner.buildArgs()` is a pure function** — takes all inputs, returns `[String]`. This is what tests verify. The actual process execution (`ContainerRunner.run()`) is not unit tested since it requires the container runtime.
- **Containerfile content is embedded in `ContainerfileTemplates.swift`** as string literals so `ccc build` works after installation (no dependency on repo file paths).
- **Signal forwarding**: `ContainerRunner.run()` uses `DispatchSource.makeSignalSource` to forward SIGINT/SIGTERM to the child container process, then restores default handlers.

## Testing

Tests use Apple's `swift-testing` framework (added as an explicit package dependency since Command Line Tools alone don't include the test runner).

- Tests use `@Test func` and `#expect()` — not XCTest
- `Tests/TestHelpers.swift` provides `makeTempDir(files:)` for creating temporary directory fixtures with specified file contents
- Temp directories are auto-cleaned on first `makeTempDir` call per test run
- `TestHelpers.swift` imports Foundation; test files import `Testing` and `@testable import ccc`

## Module Reference

| Module | Responsibility |
|--------|---------------|
| `Types.swift` | `Toolchain` enum, `Mount` struct (two initializers: auto-derive guest path, or custom), `AgentProfile` |
| `ToolchainDetector.swift` | Priority-ordered detection chain, delegates to `DevcontainerParser` |
| `DevcontainerParser.swift` | Parses devcontainer.json: image, build.dockerfile, features, containerEnv |
| `MountResolver.swift` | Builds mount list from target + additional + read-only + optional git/SSH |
| `EnvLoader.swift` | Parses KEY=VALUE files (comments, quotes), validates required vars |
| `ContainerRunner.swift` | `buildArgs()` pure function + `run()` with signal forwarding + `runRaw()` passthrough |
| `ImageResolver.swift` | `Toolchain` → `"ccc-{toolchain}:latest"`, with override support |
| `ContainerfileTemplates.swift` | Embedded Containerfile strings for base/cpp/rust/go |
| `BuildCommand.swift` | Writes embedded template to temp file, invokes `container build`, enforces base-first ordering |
