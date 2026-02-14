# Containerization Library Integration

## Summary

Begin integrating Apple's `containerization` Swift library to reduce and eventually eliminate the dependency on the `container` CLI. Start with `ContainerizationOCI` module for image reference parsing and pre-flight image validation.

## Architecture Notes

- **Seam:** `ContainerRunner` is the boundary where all `container` CLI interaction happens. Future library integration replaces its internals without changing callers.
- **Domain types stay:** spawn's `Mount`, `Toolchain`, etc. remain the domain model. Adapt to library types at the boundary only.
- **Modular adoption:** Start with `ContainerizationOCI` (no gRPC/VM stack). Add `Containerization` later when replacing `container run`.
- **Shared image store:** The `container` CLI stores images at `~/Library/Application Support/com.apple.container/`. Image state is a JSON file (`state.json`) mapping references to OCI descriptors.

## Changes

### Package.swift

- Bump `swift-tools-version` from `6.1` to `6.2`
- Add `containerization` package dependency (local path `../containerization` for dev, git URL for release)
- Add `ContainerizationOCI` product dependency to the spawn target

### Feature B: OCI reference parsing in ImageResolver

Use `ContainerizationOCI.Reference.parse()` to validate image references in `ImageResolver.resolve()`. Continue returning `String` for backward compat. Validates that image names are well-formed OCI references.

### Feature A: Pre-flight image check

New `ImageChecker` module that reads the `container` CLI's `state.json` directly, using `ContainerizationOCI.Descriptor` as the Codable value type. Checks whether the resolved image exists before calling `container run`. On miss, prints actionable error: `Image 'spawn-rust:latest' not found. Run 'spawn build rust' first.`

Slots into `RunCommand.run()` after `ImageResolver.resolve()`, before `ContainerRunner.run()`.

## Decisions

- Use local path dependency during development (`../containerization`)
- Read `state.json` directly rather than using `ImageStore` (which requires full `Containerization` module)
- `ImageResolver` keeps returning `String` — no callsite changes
- Pre-flight check is best-effort: if the image store can't be read, silently proceed (let `container run` handle the error)
