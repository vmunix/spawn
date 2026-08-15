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

## Where toolchains live

Language toolchains are installed under `/opt`, never in the container's home:

| Toolchain | Location | Environment |
|-----------|----------|-------------|
| `rust` | `/opt/rust` | `RUSTUP_HOME=/opt/rust/rustup`, `CARGO_HOME=/opt/rust/cargo` |
| `go` | `/opt/go`, `/usr/local/go` | `GOPATH=/opt/go` |
| `js` | `/opt/js` | `BUN_INSTALL=/opt/js/bun`, `DENO_INSTALL=/opt/js/deno`, `DENO_DIR=/opt/js/deno-cache` |
| `cpp` | system paths (apt) | -- |

`/home/coder` therefore holds user state only: a toolchain image adds nothing to it, and its contents stay identical to `spawn-base:latest`. `make smoke` enforces that -- it lists every entry under `/home/coder` in each image with its type and symlink target, checksums every file, and fails if a toolchain image differs from base in either the entries it has or the content of any file.

All of these are already on `PATH` inside the container, so no setup is needed. If you hardcoded the old locations (`/home/coder/.cargo`, `/home/coder/.rustup`, `/home/coder/go`, `/home/coder/.bun`, `/home/coder/.deno`) in a script or in `.spawn.toml`, point them at the `/opt` paths above.

## Build caches

Build caches persist automatically between runs in host directories under spawn's state directory, bind-mounted at run time. They are deliberately not baked into the image and not part of its home: they should survive between runs, but they are not user state. (`npm` is the exception to the path rule -- its cache keeps npm's default `$HOME/.npm` location inside the guest, but it is still a mounted host directory, not image content.)

Every cache lives at `$XDG_STATE_HOME/spawn/caches/<scope>/<cache>` (`~/.local/state/spawn/caches/...` by default):

| Toolchain | Host directory (default scope) | Mounted at |
|-----------|--------------------------------|------------|
| `rust` | `caches/<workspace>/cargo-registry` | `/opt/rust/cargo/registry` |
| `rust` | `caches/<workspace>/cargo-git` | `/opt/rust/cargo/git` |
| `go` | `caches/<workspace>/go-mod` | `/opt/go/pkg/mod` |
| `js` | `caches/<workspace>/deno` | `/opt/js/deno-cache` |
| `js` | `caches/<workspace>/npm` | `/home/coder/.npm` |
| `base`, `cpp` | *(none)* | |

spawn creates a missing directory on demand -- one `mkdir`, no container, no ownership fixup: VirtioFS maps the mount to the guest `coder` user, so the guest can write into a directory your host account owns. `spawn doctor` lists the directories for the detected toolchain and the scope they use, and `spawn doctor --json` includes the same line as a `checks[]` entry titled `Build caches`.

**Concurrent runs are safe.** Any number of runs -- in the same workspace, or in different workspaces under `--cache shared` -- can mount one cache directory at once. This is why caches are host directories rather than named `container` volumes: a named volume is a raw ext4 image attached as a virtio block device, and ext4 is not a cluster filesystem. Apple's `container` treats a volume as exclusively owned (it has a `volumeInUse` error for exactly this), and three concurrent runs sharing one volume reliably failed with `VZErrorDomain Code=2 "The storage device attachment is invalid."` -- while two "succeeded", which is the silent-corruption case rather than a safe one.

The trade is write throughput: VirtioFS is slower than a block device for many small writes. On a 111-crate `cargo fetch` (105 MB unpacked into the cache) the cold fetch took ~3.5s on a bind mount against ~1.0s on a named volume; a warm fetch, 0.33s against 0.25s; `cargo build --offline`, which reads the cache and writes into the workspace, ~11.2s against ~10.9s. First population of a cache is the case that pays; everyday runs barely notice, and no run can now be corrupted by another.

## Cache scope

A cache is mounted read-write and holds dependency sources fetched with the workspace's own credentials -- `cargo`'s git cache can contain private repositories. Caches are therefore **scoped to one workspace by default**: `<workspace>` above is a slug of the directory name plus a hash of its full path, the same identity that names a `--runtime workspace-image` image, so two projects never meet in one directory. Path spelling does not matter: `~/code/app`, `~/code/app/` and `~/code/./app` are one workspace.

| Scope | Directory | Who can read and write it | How to select it |
|-------|-----------|---------------------------|------------------|
| `workspace` (default) | `caches/app-1a2b3c4d5e6f7890/cargo-registry` | only runs in that workspace | default; `--cache workspace`; `.spawn.toml` |
| `shared` | `caches/shared/cargo-registry` | every workspace that opts in | `--cache shared` only |

Opt into sharing per run:

```bash
spawn --cache shared
```

**Only the flag can select `shared`.** Repo config may narrow but never widen, the same rule `access` follows: a `.spawn.toml` with

```toml
[workspace]
cache = "shared"
```

is ignored, the run stays workspace-scoped, and spawn says so:

```
Warning: ignoring .spawn.toml cache=shared. Pass '--cache shared' explicitly to opt into cross-workspace cache sharing.
```

`spawn doctor` reports the same, annotating the build-caches line with `.spawn.toml cache=shared ignored`. Otherwise a repository you cloned could set the key itself and reach caches you had opted into sharing elsewhere -- a narrowed version of the very channel scoping exists to close. `cache = "workspace"` is a narrowing, so it is honoured silently.

**A shared cache is a two-way channel.** Every workspace using it can read what the others cached -- including private dependency sources -- and can modify what they will build against on their next run. Use it only across projects you trust equally; never for an untrusted repository, and not alongside workspaces with private dependencies. spawn prints a note on every run that uses one.

### Clearing a cache

There is no `spawn cache` command. A cache is a directory, so remove it -- spawn recreates it, empty, on the next run:

```bash
ls ~/.local/state/spawn/caches                                       # inspect
rm -rf ~/.local/state/spawn/caches/app-1a2b3c4d5e6f7890/cargo-registry  # clear one
rm -rf ~/.local/state/spawn/caches                                   # clear everything
```

Copy the exact path from `spawn doctor`, which prints what this workspace's runs actually mount.

Removing a cache is also the recovery path when one is left unwritable -- a directory that ended up mode `0555`, or owned by another account on this machine. spawn only ensures the directory exists, so it mounts such a directory as-is and the build then fails with "permission denied" writing a cache path inside the container. `rm -rf` the directory `spawn doctor` names and rerun; the next run recreates it owned by you.

### Removing the old cache volumes

Caches used to be named `container` volumes. Nothing reads those now, so delete them once:

```bash
container volume ls | grep spawn-cache-              # find them
container volume delete spawn-cache-cargo-registry   # the unscoped set
container volume delete spawn-cache-cargo-git
container volume delete spawn-cache-go-mod
container volume delete spawn-cache-deno
container volume delete spawn-cache-npm
```

Per-workspace volumes are named `spawn-cache-<cache>-<slug>-<hash>` (for example `spawn-cache-cargo-registry-app-1a2b3c4d5e6f7890`); `container volume ls` lists them all, and each is deleted the same way. Their contents are not migrated: the first run in each workspace repopulates the new host directory from scratch. Each volume is a 512 GB sparse ext4 image under `~/Library/Application Support/com.apple.container/volumes/`, so deleting them is also the one action here that reclaims real disk.

### Upgrading existing images

Toolchains moved out of `/home/coder` into `/opt` in this release, and the caches mount at the new `/opt` paths. An image built before the move still sets the old locations -- or, for `go`, no `GOPATH` at all -- so the caches mount onto paths that image never reads.

spawn cannot detect this: it only warns when a toolchain image is older than `spawn-base:latest`, which this change did not touch. **After upgrading spawn, rebuild every image once:**

```bash
spawn build
```

Without the rebuild nothing fails loudly -- and that is the hazard. spawn still creates and mounts the cache directories, and `spawn doctor` still lists them as present, but a stale image leaves `CARGO_HOME`/`DENO_DIR` unset, so `cargo` and `deno` keep writing to their old in-home paths and nothing lands in the caches -- and a stale `go` image, which never set `GOPATH`, does not persist its module cache at all. You are told the cache is on while nothing accumulates in it. (`npm` is unaffected: its `$HOME/.npm` location did not change.)

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
