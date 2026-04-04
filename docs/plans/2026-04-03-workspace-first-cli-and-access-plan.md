# Workspace-First CLI and Access Model — Plan

**Date:** 2026-04-03
**Status:** Proposed

## Goal

Evolve `spawn` from an agent-first launcher into a workspace-first container runner for macOS, while preserving its strongest advantages:

- toolchain autodetection
- image-backed reproducibility
- persisted agent auth state
- safe-by-default execution for remote-write actions

The desired front door is: "run something useful from the current directory in a contained environment" rather than "choose a subcommand for a container tool."

## Product Direction

### Primary UX

The primary entrypoint should become:

```bash
spawn
spawn codex
spawn --shell
spawn -- cargo test
spawn -- swift test
spawn -C ~/code/project
```

Key behavior:

- current working directory is the default workspace
- an omitted command launches the default agent
- `spawn -- <cmd...>` runs an arbitrary command inside the resolved workspace container
- `-C` or `--cwd` selects a different workspace without requiring a positional path

### Secondary UX

Administrative and inspection actions remain subcommands:

- `spawn image ...`
- `spawn list`
- `spawn stop`
- `spawn exec`

`build` and `doctor` remain available as subcommands, but should also gain workspace-first entrypoints:

- `spawn --build`
- `spawn --doctor`
- `spawn --shell`

These flags should be treated as convenience aliases for the common "from here" workflow, not as the only interface.

## Principles

1. `spawn` should optimize for "from this repo, do the obvious thing."
2. Toolchain autodetection stays on by default and remains a core differentiator.
3. Permission mode and secret exposure are separate concerns and must be modeled separately.
4. Host credential exposure should require more intent than it does today.
5. The front-door UX should optimize for the ideal shape first; compatibility is secondary and should not preserve confusing syntax.

## Current Gaps

### CLI shape

Today the default command is still `spawn <path> [agent] [options]`, which keeps the mental model centered on a positional workspace path and an agent launch flow.

### Dockerfile behavior drift

The code and docs historically disagreed about what a workspace-local `Dockerfile` or `Containerfile` means. The short-term fix is to stop guessing: `auto` now refuses to proceed for workspace-defined runtimes and requires explicit `--runtime spawn` until true workspace-image support exists.

### Access model

Safe mode currently gates selected remote-write `git` and `gh` operations, but the default mount behavior still exposes copied host git config, SSH material, and `gh` auth when `--no-git` is not set.

This is convenient, but it conflates:

- action permissions
- credential availability
- host secret exposure

## Target Model

### Two independent axes

#### Execution mode

- `safe` default
- `yolo` opt-in

This controls whether remote-write operations are gated.

#### Access profile

- `minimal`
- `git`
- `trusted`

This controls what host identity and credential material is made available inside the container.

Suggested defaults:

- default access profile: `minimal`
- default execution mode: `safe`

### Access profiles

#### `minimal`

- workspace mount
- user-requested extra mounts
- persisted agent state
- no copied host SSH keys
- no copied host `gh` auth
- no copied host git config unless explicitly requested

Use for most agent sessions and arbitrary command execution.

#### `git`

- everything in `minimal`
- host git config
- optional `gh` auth
- still no blanket import of all private SSH keys

Use for workflows that need git identity and common HTTPS-based GitHub operations.

#### `trusted`

- everything in `git`
- selected SSH keys or explicit host-auth import

Use when the user intentionally wants push-over-SSH or equivalent trusted workflows.

## Configuration Evolution

Expand `.spawn.toml` from a toolchain pin into a workspace profile.

Potential shape:

```toml
[workspace]
agent = "claude-code"
mode = "safe"
access = "minimal"

[toolchain]
base = "rust"

[mounts]
read_write = ["../shared-lib"]
read_only = ["~/docs/reference"]
```

Future additions may include:

- default arbitrary command
- resource defaults
- image override
- named profiles

## Phased Implementation

## Phase 1: Workspace-first front door

### Objectives

- make cwd the default workspace
- prepare the parser for arbitrary command execution
- keep the launch syntax unambiguous

### Changes

- add `-C` / `--cwd`
- make path optional for the default launch flow
- allow `spawn`, `spawn codex`, and `spawn --shell`
- keep `spawn run` as an explicit spelling of the same flow
- update launch summary and help text to speak in terms of workspace resolution

### Notes

Do not preserve positional workspace-path syntax if it makes the CLI ambiguous. Workspace selection should move to `-C/--cwd`.

## Phase 2: Arbitrary command execution in the workspace container

### Objectives

- support `spawn -- <cmd...>`
- reuse the same workspace, image, mount, env, and permission plumbing as agent launches

### Changes

- generalize run entrypoint selection from "agent or shell" to "agent, shell, or passthrough command"
- ensure TTY behavior still works for interactive commands
- make summary output clearly distinguish agent launch versus command launch

### Notes

This is the step that fully realizes the "run anything from cwd" model.

## Phase 3: Access profiles and explicit credential mounting

### Objectives

- stop treating host git/SSH exposure as a binary on/off mount set
- separate remote-write gating from secret availability

### Changes

- replace `--no-git` with a richer access setting while keeping `--no-git` as a compatibility alias for one release
- add `--access minimal|git|trusted`
- add targeted auth options such as `--ssh-key <name>` or `--auth gh`
- refactor mount resolution to import only the credential material required by the selected access profile

### Notes

This phase changes real security posture and should include clear docs and migration notes.

## Phase 4: Correct Dockerfile and devcontainer semantics

### Objectives

- make workspace-local container definitions first-class
- align code, docs, and diagnostics

### Changes

- short term: make `auto` refuse to guess for workspace-defined runtimes and require an explicit `--runtime spawn` opt-in
- short term: reserve `--runtime workspace-image` as the future direct-build/runtime path
- treat `.devcontainer/devcontainer.json` with `build.dockerfile` the same way as a root `Dockerfile` / `Containerfile`
- long term: implement true workspace-image build/run support
- update `doctor` to explain the exact resolution path

### Notes

This matters much more once `spawn` is also a generic command runner, not just an agent wrapper.

## Phase 5: Config and documentation consolidation

### Objectives

- make `.spawn.toml` the stable place for workspace defaults
- simplify the README front page around the new mental model

### Changes

- extend config parsing
- add docs for access profiles and arbitrary command mode
- update help, README, and docs site examples

## Recommended First Slice

Land Phase 1 before touching access profiles.

Reasoning:

- it delivers the most visible UX improvement immediately
- it preserves the repo's best current differentiator, autodetection
- it avoids mixing parser changes with security model changes
- it sets up a clean path to arbitrary command execution next

Concrete first implementation target:

1. `spawn` launches the default agent from cwd
2. `spawn codex` launches Codex from cwd
3. `spawn --shell` opens a shell from cwd
4. `spawn -C <dir>` selects another workspace
5. positional workspace-path syntax is no longer part of the primary interface

## Risks

- Swift ArgumentParser may make arbitrary command passthrough interact awkwardly with subcommand parsing.
- Access-profile changes could break users who implicitly rely on SSH-backed push flows.
- Dockerfile semantics need a crisp decision before command mode is broadly documented.
- Documentation drift will reappear quickly if code and docs are updated in separate passes.

## Acceptance Criteria

- The primary examples in help and README no longer require a positional workspace path.
- Workspace resolution defaults to cwd across run and doctor-style flows.
- Arbitrary command mode has a clear implementation path without duplicating launch logic.
- Secret exposure is described explicitly and independently from safe/yolo action gating.
- The primary interface is unambiguous: optional agent only, workspace via cwd or `-C/--cwd`.
