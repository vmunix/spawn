# Review Findings Remediation Plan

**Date:** 2026-04-03
**Status:** Proposed

## Goal

Address the highest-value code quality, security, and architecture findings in priority order, without losing the current momentum on workspace-first UX.

The first fixes should protect the front door and the default security posture:

- `spawn` should still work on a normal machine without surprising launch failures
- untrusted repos should not be able to silently widen host credential exposure
- the product should fail clearly when host prerequisites or auth setup are not usable

After that, we can tighten caching accuracy, reduce ambient coupling, and simplify the internals that now carry too much policy in one place.

## Priority Order

## Phase 1: Fix high-value correctness and security issues

### Objectives

- restore the documented `container` binary lookup behavior
- stop repo config from silently escalating host credential exposure
- stop fragile image-store state from blocking launches

### Checklist

- [ ] Make `ContainerRunner` resolve `container` through `PATH` for real, not just in docs/comments
- [ ] Add tests for PATH-only `container` discovery
- [ ] Change workspace config handling so `.spawn.toml` cannot raise `access` above the safe default without explicit user intent
- [ ] Decide the precise policy for repo defaults:
  - allow `.spawn.toml` to lower access only
  - or ignore repo-configured `access` entirely unless a trusted flag/setting is present
- [ ] Add tests proving untrusted repo config cannot silently opt users into `git` or `trusted`
- [ ] Stop treating unreadable image-store metadata as definitive “image missing”
- [ ] Replace that failure with one of:
  - a softer warning plus attempted launch
  - or a distinct runtime warning that does not claim the image is absent
- [ ] Add regression tests for image-store read failures

### Notes

These are the highest-value fixes because they directly affect whether `spawn` is safe and usable on first contact.

## Phase 2: Tighten auth and mount behavior

### Objectives

- avoid broken auth mounts on partial copy failure
- reduce unnecessary host secret exposure
- make terminal output less likely to leak secrets

### Checklist

- [ ] Change `MountResolver` so auth mounts are only appended when the copy step succeeds
- [ ] Surface partial-copy or empty-copy failures clearly to the user
- [ ] Narrow `trusted` SSH import behavior:
  - either selective key import
  - or an allowlist of expected SSH file names
- [ ] Decide whether `known_hosts`, `config`, cert material, and backup keys should be included by default
- [ ] Redact or truncate passthrough command display in launch summaries when arguments may contain secrets
- [ ] Add tests for failed git/gh/ssh copy behavior and secret-safe summary rendering

### Notes

This phase improves real security posture and reduces “it launched, but auth is mysteriously broken” failure modes.

## Phase 3: Make doctor a better first-stop diagnostic

### Objectives

- improve first-machine readiness diagnostics
- align `doctor` with the actual host/runtime failures users hit

### Checklist

- [ ] Extend `doctor` beyond `container system status`
- [ ] Detect and explain missing kernel/default-kernel scenarios
- [ ] Detect and explain other prerequisite failures that surfaced during smoke work
- [ ] Decide whether `doctor` should probe build/run readiness or remain purely diagnostic
- [ ] Keep `doctor --json` stable while adding the new fields
- [ ] Add tests for parsed/system readiness states and failure messaging

### Notes

The current `Container system` check is useful, but it does not yet fully justify the expectation that `spawn doctor` tells users why a machine is not ready.

## Phase 4: Fix workspace-image cache accuracy

### Objectives

- make cache invalidation match the real build boundary
- reduce noisy rebuilds and false cache confidence

### Checklist

- [ ] Teach workspace-image fingerprinting about `.dockerignore`
- [ ] Decide whether cache identity should be content-based, metadata-based, or mixed
- [ ] Exclude common non-build artifacts from cache invalidation when appropriate
- [ ] Revisit the cache messaging in `doctor` and runtime output so it matches the actual invalidation model
- [ ] Add tests for `.dockerignore`-excluded files and stable cache reuse

### Notes

This is important for trust. The feature is now prominent enough that misleading cache behavior will feel like product breakage.

## Phase 5: Remove ambient coupling from operational commands

### Objectives

- make managed-image commands less dependent on the caller’s current directory
- reduce accidental behavior changes from ambient filesystem context

### Checklist

- [ ] Make `spawn build` use a controlled build context instead of always using `.`
- [ ] Decide whether build context should be an empty temp dir or an explicit repo-owned context
- [ ] Add tests proving `spawn build` behavior does not depend on the caller’s current working tree

### Notes

This is mostly an architecture/correctness cleanup, but it will also make behavior easier to reason about.

## Phase 6: Simplify the CLI and run-path architecture

### Objectives

- reduce accidental complexity in root argument rewriting
- narrow the responsibilities currently concentrated in `RunCommand`

### Checklist

- [ ] Revisit the open-ended root rewrite behavior in `CLI.swift`
- [ ] Decide whether bare root rewriting should be limited to known agent shortcuts and obvious workspace-first forms only
- [ ] Extract launch-resolution policy out of `RunCommand`
- [ ] Extract image-availability policy out of `RunCommand`
- [ ] Extract summary rendering and runtime policy into narrower helpers/types
- [ ] Keep the workspace-first UX intact while making parser behavior less surprising

### Notes

This phase is less urgent than the earlier security/correctness work, but it will matter if `spawn` keeps growing.

## Recommended Execution Order

1. Phase 1
2. Phase 2
3. Phase 3
4. Phase 4
5. Phase 5
6. Phase 6

## Recommended First Slice

Start with these three fixes together:

- `.spawn.toml` must not be able to silently raise `access`
- `ContainerRunner` must perform real PATH lookup
- unreadable image-store metadata must stop producing false `image missing` errors

Reasoning:

- they address the two highest-severity findings
- they directly affect first-run trust and usability
- they are small enough to land as one focused hardening slice before broader refactors
