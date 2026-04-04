# AGENTS.md

This file is the authoritative repository guidance for coding agents working in this repo.

Keep [CLAUDE.md](CLAUDE.md) aligned with this file. Prefer updating this file first and keeping any agent-specific wrapper minimal.

Use [README.md](README.md) as the user-facing overview and `docs/` as the user documentation set.

## CLI Discovery

For CLI behavior, treat the built-in help surface as a first-class contract.

- Start with `spawn --help` and `spawn help <subcommand>` to understand the current user-facing shape
- Prefer the rendered help output over stale assumptions from older docs or commits
- When changing CLI behavior, update the relevant `abstract`, `discussion`, option help text, and usage examples in the command source
- Keep help accurate for both humans and LLMs: front-door workflows first, operational commands second, caveats explicit
- Preserve coverage in `Tests/CLIHelpTests.swift` when the discovery surface changes

## Build And Test

```bash
swift build                              # Debug build
swift build -c release                   # Release build
swift test                               # Run all tests
swift test --filter ToolchainDetector    # Run one test file
swift test --filter "detectsRust"        # Run one test by name
swift run spawn                          # Run from source in current directory
swift run spawn codex --verbose          # Run Codex with verbose logging
swift run spawn doctor --json            # Machine-readable doctor output
make build                               # Release build
make test                                # Lint + full test suite
make lint                                # swift-format lint
make format                              # Auto-format in place
make smoke                               # End-to-end fixture runs in containers
make install                             # Install to ~/.local/bin
```

Always run `make test` before `git commit` or `git push`.

## Product Shape

`spawn` is a Swift CLI that wraps Apple's `container` CLI to run coding agents and arbitrary commands in macOS-hosted Linux containers.

Current front-door UX:

- `spawn` runs the default agent from the current directory
- `spawn codex` switches agents
- `spawn -- <command...>` runs an arbitrary command in the workspace container
- `spawn -C <dir>` selects another workspace
- `spawn --shell` opens a shell
- `spawn doctor` checks the local environment and workspace resolution
- `spawn doctor --json` emits the same information in machine-readable form

Important runtime controls:

- `--access minimal|git|trusted`
- `--runtime auto|spawn|workspace-image`
- `--rebuild-workspace-image` only with `--runtime workspace-image`
- `.spawn.toml` may define `[workspace] agent/access` and `[toolchain] base`

## Runtime Resolution

`RunCommand` is workspace-first and follows this high-level flow:

```text
RunCommand.run()
  → resolveLaunchRequest()               # workspace + agent defaults
  → AgentProfile.named()                 # validate agent
  → validateRuntimeOptions()             # runtime / image / toolchain consistency
  → ToolchainDetector.inspect()          # detect toolchain or workspace runtime
  → WorkspaceImageRuntime.ensureBuilt()  # when using --runtime workspace-image
    or ImageResolver.resolve()           # when using spawn-managed runtimes
  → MountResolver.resolve()              # workspace, auth, agent state
  → EnvLoader.load/loadDefault()         # env file / defaults
  → ContainerRunner.run()                # execv for TTY, Process otherwise
```

Toolchain detection priority:

1. `.spawn.toml` `[toolchain] base = "..."`
2. `.devcontainer/devcontainer.json` image or features
3. `.devcontainer/devcontainer.json` with `build.dockerfile`, or root `Dockerfile` / `Containerfile`
4. file heuristics: `Cargo.toml`, `go.mod`, `CMakeLists.txt`, `bun.lock`, `deno.json`, `package.json`, etc.
5. fallback to `base`

Interpretation:

- `--runtime auto` refuses to guess for workspace-defined runtimes
- `--runtime spawn` ignores the workspace runtime and uses spawn-managed images
- `--runtime workspace-image` builds or reuses a deterministic workspace image

## Workspace-Image Runtime

`WorkspaceImageRuntime` handles workspaces with a root `Dockerfile` / `Containerfile` or `.devcontainer/devcontainer.json` using `build.dockerfile`.

Current behavior:

- image names are deterministic per workspace path
- cache metadata is stored under spawn state
- cached workspace images are reused until tracked inputs change
- tracked inputs include the Dockerfile, optional devcontainer config, and build-context file metadata
- `--rebuild-workspace-image` forces a rebuild even if the cache is current

`spawn doctor` should make these decisions inspectable. `spawn doctor --json` exposes a stable structured `workspace.runtime` payload with cache fields and tracked paths.

## Access And Safety

Access profiles and action permissions are separate concerns.

- `minimal` mounts workspace, requested mounts, and persisted agent state only
- `git` additionally mounts copied git config and `gh` config
- `trusted` additionally mounts copied SSH material
- safe mode remains the default
- `--yolo` disables permission gates

Do not broaden default secret exposure casually. The current direction is explicit, opt-in host auth exposure.

## Important Design Constraints

- All container interaction goes through `ContainerRunner`
- `ContainerRunner.buildArgs()` is pure and heavily tested
- Interactive TTY runs use `execv`; non-TTY runs use `Foundation.Process`
- Agent auth state is persisted under `~/.local/state/spawn/<agent>/`
- Single-file bind mounts are avoided where VirtioFS rename behavior is problematic
- Embedded `ContainerfileTemplates.swift` keeps `spawn build` self-contained after installation

## Testing

Tests use Swift 6's `Testing` framework, not XCTest.

- Use `@Test` and `#expect`
- `Tests/TestHelpers.swift` provides `makeTempDir(files:)`
- `make test` prefers Xcode when available because CLT Swift can be incomplete for this setup
- `make smoke` exercises the fixture workspaces under `fixtures/`

Favor pure-function tests when possible:

- parser and launch-request resolution
- image/runtime resolution
- mount/env construction
- doctor reporting and JSON rendering
- workspace-image cache decisions

## Module Map

Key files:

- `Sources/RunCommand.swift`: primary CLI flow
- `Sources/DoctorCommand.swift`: environment/workspace diagnostics, human + JSON output
- `Sources/WorkspaceImageRuntime.swift`: workspace-image planning, cache status, rebuild logic
- `Sources/ToolchainDetector.swift`: detection and `.spawn.toml` loading
- `Sources/MountResolver.swift`: workspace/auth/agent mounts
- `Sources/ContainerRunner.swift`: container CLI boundary
- `Sources/BuildCommand.swift`: spawn-managed image builds
- `Sources/DevcontainerParser.swift`: devcontainer parsing
- `Sources/Types.swift`: `Toolchain`, `AccessProfile`, `RuntimeMode`, `AgentProfile`, `Mount`

## Coding Conventions

- Use `.swift-format`
- Keep imports ordered
- Prefer `guard` to deep nesting
- Never force unwrap or force try
- Mark types `Sendable`
- Use `SpawnError` for runtime failures and `ValidationError` for CLI validation
- Use `logger.debug()` for diagnostics and `print()` for user-facing status
- Redact env values in verbose command logs

## Release And Distribution

- Homebrew formula lives in `vmunix/homebrew-tap`
- `make install` installs to `~/.local/bin`
- Version is set in `Sources/CLI.swift`
- Release flow: update version, tag, create GitHub release, update Homebrew formula checksum

## Editing Guidance

- Keep this file concise and operational
- Prefer updating facts over adding process prose
- When product shape changes, update this file, `CLAUDE.md`, `README.md`, and relevant `docs/` pages in the same slice
