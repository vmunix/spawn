---
title: Architecture
nav_order: 7
---

# Architecture

## Directory layout

spawn follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/latest/) for all configuration and state.

| Path | Purpose |
|------|---------|
| `~/.config/spawn/env` | Default environment variables |
| `~/.local/state/spawn/<agent>/` | Agent credentials and session state |
| `~/.local/state/spawn/git/` | Copied git config for `git`/`trusted` access profiles |
| `~/.local/state/spawn/ssh/` | Copied SSH keys for the `trusted` access profile |
| `~/.local/state/spawn/gh/` | Copied gh CLI config for `git`/`trusted` access profiles |
| `~/.local/state/spawn/native-runtime/containerization-<version>/` | Experimental native backend image, initfs, and rootfs artifacts |

These paths respect `XDG_CONFIG_HOME` and `XDG_STATE_HOME` environment variables. For example, if `XDG_STATE_HOME` is set to `/custom/state`, spawn stores state at `/custom/state/spawn/` instead of `~/.local/state/spawn/`.

## Container images

spawn uses layered container images. All toolchain images extend `spawn-base:latest`:

```
spawn-base:latest
  ├── spawn-cpp:latest
  ├── spawn-rust:latest
  └── spawn-go:latest
  └── spawn-js:latest
```

### Base image contents

The base image (`spawn-base:latest`) includes:
- Ubuntu 24.04
- Node.js, npm, Python 3
- Claude Code (native installer), Codex (npm)
- git, gh CLI, curl, wget
- ripgrep, fd-find, jq, tree
- Safe-mode wrapper scripts for git/gh
- Non-root `coder` user with sudo access

### JS/TS image contents

The JavaScript/TypeScript image (`spawn-js:latest`) extends the base image and adds:
- Node.js 22 LTS
- Corepack for pnpm/yarn workflows
- Bun
- Deno

### Image management

```bash
spawn build              # Build all images (4 CPUs, 8GB memory by default)
spawn build base         # Build base only
spawn build rust         # Build a toolchain image
spawn build js           # Build the JS/TS toolchain image
spawn build --memory 16g # Build with more memory if needed
spawn image list         # List spawn images
spawn image rm <name>    # Remove a spawn image
```

The builder container defaults to 4 CPUs and 8GB memory (`--cpus` and `--memory` flags). Apple's `container build` defaults to only 2GB, which is insufficient for the Claude Code installer.

Containerfile content is embedded in the `spawn` binary as string literals, so `spawn build` works after installation without depending on the source repository. It builds from an isolated temporary context instead of the caller's current directory.

## Run pipeline

When you run `spawn`, the following modules execute in sequence:

```
RunCommand.run()
  → ToolchainDetector.loadWorkspaceConfig()
                                  # Load `.spawn.toml` workspace defaults
  → AgentProfile.named()          # Validate resolved agent (CLI/config/default)
  → RunRuntimePolicy.resolveCacheSelection()
                                  # Reject an unusable --cache before any
                                  # container work; the value is discarded
  → SettingsSeeder.seed()         # Seed safe-mode permissions (claude-code only)
  → ToolchainDetector.detect()    # Auto-detect or use override
  → RuntimeMode.parse()           # Decide whether auto/spawn/workspace-image applies
  → WorkspaceImageRuntime.ensureBuilt()
                                  # Build or reuse a cached workspace image when requested
  → ImageResolver.resolve()       # Map toolchain to image name for spawn-managed runtimes
  → MountResolver.resolve()       # Build mount list
  → EnvLoader.load/loadDefault()  # Load env vars
  → Run.resolvedLaunch()          # Resolve cache scope, ignored repo config, and
                                  # the --image cache exclusion once, then keep the
                                  # mounts and their notices in one value
    → RunRuntimePolicy.CacheSelection.mounts()
                                  # Derive mount paths from the resolved policy
    → CacheMounts.prepare()       # mkdir each host cache directory (VirtioFS maps
                                  # it to the guest user, so no chown and no locking)
    → ResolvedLaunchPlan.workspace()
                                  # Freeze final backend-neutral launch inputs
    → RunLaunchSummary.cacheNotices()
                                  # Warn about exactly the scope just mounted
  → ContainerRuntimeFactory.makeRuntime(--backend)
    → AppleContainerCLIRuntime     # Default: render argv and launch with Apple's CLI
    or NativeContainerRuntime      # Experimental: launch with Containerization APIs
  → ContainerRuntime.launch(launch.plan)
```

## Design decisions

### Launch backends

Workspace launches cross the semantic `ContainerRuntime` boundary as one
backend-neutral `ResolvedLaunchPlan`. The default `AppleContainerCLIRuntime`
renders that plan as `container run`. `NativeContainerRuntime` is selected only
with `--backend native-experimental` and consumes the same plan through Apple's
Containerization APIs. Kernel, initfs, rootfs, and VM network details remain
private to the native adapter.

Build, image, list, stop, doctor, and existing-container exec/shell operations
remain raw CLI operations in `ContainerRunner`. The CLI is auto-detected at
`/opt/homebrew/bin/container` or `/usr/local/bin/container`, falling back to
PATH lookup. Override it with `CONTAINER_PATH`.

The native artifact boundary and current limitations are detailed in
[Native Containerization Backend](native-backend.md).

### TTY via execv

On the CLI backend, a real terminal uses `execv` to replace spawn with
`container`; piped input uses `Foundation.Process` with signal forwarding. The
native backend instead hands the current terminal to Containerization, forwards
resize and termination signals, and waits for the VM workload to exit.

### VirtioFS workaround

VirtioFS maps bind-mounted files owned by the macOS user to the container's `coder` user. When an access profile opts into host auth, spawn still copies selected material into state directories so it can filter symlinks, expose only supported files, and mount stable directories instead of sensitive host paths.

Single-file bind mounts also don't support atomic rename (EBUSY). `~/.claude.json` is handled via a symlink into a directory mount (`~/.claude-state/`) to work around this.

A future persistent-home design must keep access-controlled credentials ephemeral rather than copying them into the persistent home. The security and image-compatibility constraints are recorded in [Persistent Home Safety Constraints](plans/persistent-home-safety-constraints.md).

### Credential persistence

Agent credentials are stored on the host at `~/.local/state/spawn/<agent>/` and mounted into containers. This means users authenticate once and credentials survive container restarts. No API keys are required for Claude Pro/Max plan users who authenticate via OAuth.

### Access profiles

Host auth exposure is controlled by `AccessProfile`:

- `minimal` mounts no host git, `gh`, or SSH material
- `git` mounts copied git config and `gh` CLI auth
- `trusted` mounts copied git config, `gh` CLI auth, and selected SSH material

### SSH key handling

When the `trusted` access profile is selected, spawn copies standard SSH config files and top-level `id_*` key material (not mounted directly) to the state directory. Symlinks are filtered out to prevent exfiltrating files outside `~/.ssh/`. Private keys get `0600` permissions on the copies.
