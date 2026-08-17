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
make smoke                               # End-to-end workspace-first and workspace-image coverage
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
  → ResolvedLaunchPlan.workspace()       # one backend-neutral launch value
  → ContainerRuntime.launch(plan)        # semantic launch boundary
    → AppleContainerCLIRuntime            # execv for TTY, Process otherwise
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
- build caches are scoped to the workspace by default, so no profile leaks one workspace's cached dependency sources into another

Do not broaden default secret exposure casually. The current direction is explicit, opt-in host auth exposure.

## Build Cache Scope

Build caches are host directories under `<state>/caches/<scope-key>/<cache>`, bind-mounted read-write. They hold dependency sources fetched with the workspace's own credentials (`cargo`'s git cache can hold private repositories), so the scope key carries workspace identity by default.

- `workspace` (default): the key is `WorkspaceIdentity.key(for:)` — the same slug-plus-path-hash that names a workspace-image — so two workspaces never share a directory
- `shared`: one `shared` directory for every workspace that opts in
- only `--cache shared` may select `shared`; `.spawn.toml [workspace] cache = "shared"` is ignored with a warning, exactly as a repo-supplied `access` elevation is. Repo config may narrow (`cache = "workspace"`), never widen
- a shared cache is readable and writable by every workspace using it; a run that uses one says so

`spawn doctor` must name the directories the workspace would actually mount, resolving the scope the way a run does. Anything that names a cache path goes through `CacheMounts`, never by string-building a path.

## Important Design Constraints

- Workspace launches cross `ContainerRuntime` as a `ResolvedLaunchPlan`; CLI arguments and process details stay in runtime adapters
- Raw operational `container` CLI commands remain in `ContainerRunner` and are intentionally outside `ContainerRuntime`
- `RunCommand` resolves one `ResolvedLaunchPlan`; runtime adapters consume it without re-reading CLI or workspace config
- `AppleContainerCLIRuntime.buildArgs(for:)` is pure and heavily tested
- Interactive TTY runs use `execv`; non-TTY runs use `Foundation.Process`
- Agent auth state is persisted under `~/.local/state/spawn/<agent>/`
- Single-file bind mounts are avoided where VirtioFS rename behavior is problematic
- Embedded `ContainerfileTemplates.swift` keeps `spawn build` self-contained after installation
- Language toolchains live under `/opt` (`/opt/rust`, `/opt/go`, `/opt/js`), never in `/home/coder`
- Toolchain images must keep `/home/coder` identical to `spawn-base`'s; `scripts/smoke.sh` compares each image's full home listing — every entry with its type, mode, numeric owner/group, and symlink target, plus a checksum of every file — and fails if a toolchain leaks into the home or changes a file already there
- Build caches are host directories bind-mounted at run time, never baked into an image (see `Sources/CacheMounts.swift`). They are not named `container` volumes: a volume is a raw ext4 image on a virtio block device, which `container` treats as exclusively owned, and concurrent runs sharing one fail with `VZErrorDomain Code=2`. A bind mount is served by VirtioFS, which maps ownership to the guest user — so preparing a cache is one `mkdir` plus a readiness check, with no chown, no rollback and no locking, and concurrent runs are safe
- Cache directories are workspace-scoped unless the user opts into `--cache shared`; workspace identity comes from `WorkspaceIdentity`, which also names workspace-images — do not duplicate that derivation
- `ContainerfileTemplates.swift` is the only source of Containerfile content; `spawn build` is the only supported way to build spawn-managed images

## Testing

Tests use Swift 6's `Testing` framework, not XCTest.

- Use `@Test` and `#expect`
- `Tests/TestHelpers.swift` provides `makeTempDir(files:)`
- `make test` prefers Xcode when available because CLT Swift can be incomplete for this setup
- `make smoke` exercises the front-door CLI across the fixture workspaces under `fixtures/`, including `doctor --json` and workspace-image runtimes

Favor pure-function tests when possible:

- parser and launch-request resolution
- image/runtime resolution
- mount/env construction
- doctor reporting and JSON rendering
- workspace-image cache decisions

### Prove a test can fail

Before claiming coverage, break the implementation, verify the intended test
fails, then restore it and verify it passes. Report both results.

- Assert structured or exact behavior, not substrings that may also occur in comments
- Compare identities when identity matters; counts alone miss substitutions
- Pair negative assertions with a positive premise so they cannot pass vacuously
- Isolate each clause of a compound guard with a discriminating test input
- Test the final composition handed across a boundary, not only its components
- Pass `--` before shell patterns that may begin with `-`
- Under `pipefail`, verify the command that establishes the premise, not a later consumer
- Unescape `doctor --json` slashes before matching host paths in smoke tests

## Module Map

Key files:

- `Sources/RunCommand.swift`: primary CLI flow
- `Sources/DoctorCommand.swift`: environment/workspace diagnostics, human + JSON output
- `Sources/WorkspaceImageRuntime.swift`: workspace-image planning, cache status, rebuild logic
- `Sources/ToolchainDetector.swift`: detection and `.spawn.toml` loading
- `Sources/MountResolver.swift`: workspace/auth/agent mounts
- `Sources/ResolvedLaunchPlan.swift`: backend-neutral final image, mounts, environment, command, and resources
- `Sources/ContainerRuntime.swift`: semantic workspace-launch boundary
- `Sources/AppleContainerCLIRuntime.swift`: `container run` adapter and execution behavior
- `Sources/ContainerRunner.swift`: `container` CLI discovery, preflight, and raw operational commands
- `Sources/BuildCommand.swift`: spawn-managed image builds
- `Sources/CacheMounts.swift`: per-toolchain build-cache host paths, scope, guest paths, and directory creation
- `Sources/WorkspaceIdentity.swift`: the slug-plus-path-hash key shared by workspace-image names and workspace-scoped caches
- `Sources/DevcontainerParser.swift`: devcontainer parsing
- `Sources/Types.swift`: `Toolchain`, `AccessProfile`, `CacheScope`, `RuntimeMode`, `AgentProfile`, `Mount`

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
