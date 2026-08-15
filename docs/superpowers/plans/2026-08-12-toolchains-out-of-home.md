# Toolchains Out Of $HOME Implementation Plan

> **Historical record. Partly superseded:** this plan's build-cache design — named `container` volumes, with the create/chown/rollback/lock machinery that follows from them — was replaced by host-directory bind mounts. A named volume is a raw ext4 image on a virtio block device that `container` treats as exclusively owned, so concurrent runs sharing one corrupt or fail; the write-performance advantage noted below is real and measured but is not decisive against that. The `/opt` relocation, which is the rest of this plan, stands. See `docs/toolchains.md` for the current mechanism.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move every language toolchain out of `/home/coder` and into `/opt`, so a spawn container's home holds only user state — and persist the build caches in named volumes so they survive between runs.

**Architecture:** Each toolchain image currently installs into the `coder` user's home (`~/.rustup` 1.3G, `~/.deno` 108M, `~/.bun` 90M), because the upstream installers default there. Relocating them via their documented env vars (`RUSTUP_HOME`, `CARGO_HOME`, `BUN_INSTALL`, `DENO_INSTALL`, `DENO_DIR`, `GOPATH`) puts them in `/opt`, owned by `coder`, still on `PATH` via the existing `ENV PATH` lines. The installers must additionally be stopped from appending to `.bashrc`/`.profile`, since those edits are toolchain-specific state in a shared file. Build caches — which genuinely should persist and genuinely should not live in an image — move to named `container` volumes.

**Tech Stack:** Swift 6.3, Swift `Testing` framework (`@Test`/`#expect`), Apple `container` CLI 1.2.2 (`container volume` subcommands).

**Spec:** This document. Design settled interactively on 2026-08-12 from measurements taken on this machine; see "Measured Baseline" and "The Invariant" below.

## Global Constraints

- Minimum Apple `container` CLI version: **1.2.2** (named volumes via `container volume create`).
- Guest user stays `coder` (uid 1001); guest home stays `/home/coder`. This plan does not change either.
- `/opt/<toolchain>` must be owned by `coder` so the installers can write there as a non-root user.
- Toolchain binaries must remain on `PATH` via `ENV PATH` in the Containerfile — never via shell rc files.
- Swift style per `.swift-format`: no force unwrap, no force try, types marked `Sendable`, `guard` over deep nesting.
- Always run `make test` before commit; `make smoke` before the final commit.

## Measured Baseline

Taken on 2026-08-12 against `container` 1.2.2. Re-measure after Task 4 to confirm the win.

| image | `/home/coder` size | files | `cp -a --update=none` first seed | no-op reseed |
|---|---|---|---|---|
| `spawn-base` | 218M | 7 | 431 ms | 2 ms |
| `spawn-js` | 416M | 9 | — | — |
| `spawn-rust` | 1.5G | 49,650 | 23,599 ms | 2,676 ms |

Home contents by size:

- **rust:** `.rustup` 1.3G, `.local` 218M, `.cargo` 19M
- **js:** `.local` 218M, `.deno` 108M, `.bun` 90M
- **base:** `.local` 218M (the Claude Code native install — present in every image, and correctly so)

The cost driver is **file count, not bytes**: 218M across 7 files seeds in 431ms; 1.5G across 49,650 files takes 23.6s. This is why relocation fixes the problem and compression or pruning would not.

## The Invariant

This plan's acceptance criterion, and the property Task 5 enforces mechanically:

> **Every toolchain image's `/home/coder` must contain the same set of files as `spawn-base`'s.**

A toolchain image that adds anything to the home has leaked state into a directory that is about to become user-owned and persistent. Task 5 asserts this in `make smoke` so it cannot regress.

## Verified Facts

Confirmed by building probe images on 2026-08-12. Do not re-derive.

1. **Rust relocation works.** `RUSTUP_HOME=/opt/rust/rustup CARGO_HOME=/opt/rust/cargo` with `rustup-init -y --no-modify-path` yields a working `rustc 1.97.1` / `cargo 1.97.1`, `/opt/rust` at 1.5G, and `/home/coder` back to **218M / 7 files** — byte-identical in count to `spawn-base`. `claude` remains at `/home/coder/.local/bin/claude`.
2. **JS relocation works.** `BUN_INSTALL=/opt/js/bun DENO_INSTALL=/opt/js/deno` yields working `bun 1.3.14` and `deno 2.9.5`, `/opt/js` at 169M.
3. **The bun installer requires `unzip`**, which the js template already installs as root before switching to `coder`. A probe that skipped it failed with `exit code: 1`. Keep that ordering.
4. **The installers modify shell rc files.** After a js probe build, `/home/coder/.bashrc` contained `export BUN_INSTALL="/opt/js/bun"`, `export PATH="$BUN_INSTALL/bin:$PATH"`, and `. "/opt/js/deno/env"`; `/home/coder/.profile` contained `. "/opt/js/deno/env"`. These must be suppressed or reverted — see Task 2.
5. **Deno caches into `~/.cache/deno`.** A js probe's home held 14 files under `.cache/deno/` (dep analysis, v8 code cache, fetched jsr.io modules). `DENO_DIR` relocates it.

---

### Task 1: Relocate the Rust toolchain

**Files:**
- Modify: `Sources/ContainerfileTemplates.swift:215-222` (the `rust` template)
- Test: `Tests/ContainerfileTemplatesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `spawn-rust:latest` with `RUSTUP_HOME=/opt/rust/rustup`, `CARGO_HOME=/opt/rust/cargo`, and `PATH` containing `/opt/rust/cargo/bin`.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ContainerfileTemplatesTests.swift`:

```swift
@Test func rustToolchainLivesOutsideHome() {
    let content = ContainerfileTemplates.content(for: .rust)
    #expect(content.contains("RUSTUP_HOME=/opt/rust/rustup"))
    #expect(content.contains("CARGO_HOME=/opt/rust/cargo"))
    #expect(content.contains("/opt/rust/cargo/bin"))
    #expect(!content.contains("/home/coder/.cargo"), "rust must not put cargo in the home")
}

@Test func rustInstallerDoesNotEditShellRcFiles() {
    // rustup appends to ~/.bashrc and ~/.profile unless told not to; those edits are
    // toolchain state in a file the home will own and share across toolchains.
    #expect(ContainerfileTemplates.content(for: .rust).contains("--no-modify-path"))
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContainerfileTemplates`
Expected: FAIL — `rust must not put cargo in the home` (the template currently has `ENV PATH="/home/coder/.cargo/bin:${PATH}"`).

- [ ] **Step 3: Write minimal implementation**

Replace the `rust` template in `Sources/ContainerfileTemplates.swift` (currently lines 215-222):

```swift
static let rust = """
    FROM spawn-base:latest

    USER root
    # Toolchains live in /opt, not $HOME: the home becomes user-owned and
    # persistent, and 1.3G of .rustup across ~49k files makes that expensive.
    RUN mkdir -p /opt/rust && chown -R coder:coder /opt/rust

    USER coder
    ENV RUSTUP_HOME=/opt/rust/rustup CARGO_HOME=/opt/rust/cargo
    # --no-modify-path: PATH comes from ENV below, not from ~/.bashrc.
    RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \\
        | sh -s -- -y --no-modify-path
    ENV PATH="/opt/rust/cargo/bin:${PATH}"
    """
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContainerfileTemplates`
Expected: PASS.

- [ ] **Step 5: Rebuild and verify empirically**

```bash
swift run spawn build rust
container run --rm spawn-rust:latest /bin/sh -c \
  'rustc --version && cargo --version && du -sh /opt/rust && find /home/coder -type f | wc -l'
```

Expected: a working `rustc`/`cargo`, `/opt/rust` around 1.5G, and a home file count of **7** — matching `spawn-base`. Before this task the count was 49,650.

- [ ] **Step 6: Commit**

```bash
git add Sources/ContainerfileTemplates.swift Tests/ContainerfileTemplatesTests.swift
git commit -m "refactor: move rust toolchain out of \$HOME into /opt/rust"
```

---

### Task 2: Relocate the JS toolchains and stop rc-file edits

**Files:**
- Modify: `Sources/ContainerfileTemplates.swift:233-257` (the `js` template)
- Test: `Tests/ContainerfileTemplatesTests.swift`

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `spawn-js:latest` with `BUN_INSTALL=/opt/js/bun`, `DENO_INSTALL=/opt/js/deno`, `DENO_DIR=/opt/js/deno-cache`, and a home matching base.

**Why the rc restore:** verified fact 4 — the bun and deno installers append `export BUN_INSTALL=…`, `export PATH=…`, and `. "/opt/js/deno/env"` to `.bashrc`/`.profile`. Neither installer offers a reliable no-modify flag, so the template restores both files from `/etc/skel` after installing. `ENV PATH` already provides everything those lines did.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ContainerfileTemplatesTests.swift`:

```swift
@Test func jsToolchainsLiveOutsideHome() {
    let content = ContainerfileTemplates.content(for: .js)
    #expect(content.contains("BUN_INSTALL=/opt/js/bun"))
    #expect(content.contains("DENO_INSTALL=/opt/js/deno"))
    #expect(content.contains("/opt/js/bun/bin"))
    #expect(content.contains("/opt/js/deno/bin"))
    #expect(!content.contains("/home/coder/.bun"), "bun must not live in the home")
    #expect(!content.contains("/home/coder/.deno"), "deno must not live in the home")
}

@Test func denoCacheLivesOutsideHome() {
    // Verified: deno writes ~/.cache/deno (dep analysis, v8 cache, fetched modules).
    #expect(ContainerfileTemplates.content(for: .js).contains("DENO_DIR=/opt/js/deno-cache"))
}

@Test func jsTemplateRestoresShellRcFiles() {
    // The bun/deno installers append to .bashrc/.profile; PATH comes from ENV instead.
    let content = ContainerfileTemplates.content(for: .js)
    #expect(content.contains("/etc/skel/.bashrc"))
    #expect(content.contains("/etc/skel/.profile"))
}

@Test func jsTemplateInstallsUnzipBeforeBun() {
    // Verified: the bun installer exits 1 without unzip.
    let content = ContainerfileTemplates.content(for: .js)
    guard let unzip = content.range(of: "unzip")?.lowerBound,
        let bun = content.range(of: "bun.sh/install")?.lowerBound
    else {
        Issue.record("Expected both unzip and the bun installer in the js template")
        return
    }
    #expect(unzip < bun)
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContainerfileTemplates`
Expected: FAIL — `bun must not live in the home`.

- [ ] **Step 3: Write minimal implementation**

Replace the `js` template in `Sources/ContainerfileTemplates.swift` (currently lines 233-257):

```swift
static let js = """
    FROM spawn-base:latest

    USER root

    # unzip is required by the bun installer — it exits 1 without it.
    RUN apt-get update && apt-get install -y --no-install-recommends unzip \\
        && rm -rf /var/lib/apt/lists/*

    # Install a modern Node LTS release so npm/corepack are current.
    RUN curl -fsSL "https://nodejs.org/download/release/v\(nodeVersion)/node-v\(nodeVersion)-linux-\(nodeArch).tar.gz" \\
        | tar -C /usr/local --strip-components=1 -xz

    # Corepack gives first-class pnpm/yarn support for Node projects.
    RUN corepack enable

    # Toolchains live in /opt, not $HOME — see the rust template.
    RUN mkdir -p /opt/js && chown -R coder:coder /opt/js

    USER coder
    ENV BUN_INSTALL=/opt/js/bun DENO_INSTALL=/opt/js/deno DENO_DIR=/opt/js/deno-cache

    # Bun
    RUN curl -fsSL https://bun.sh/install | bash -s "bun-v\(bunVersion)"

    # Deno
    RUN curl -fsSL https://deno.land/install.sh | sh -s -- -y

    # Both installers append PATH lines to the shell rc files. PATH comes from
    # ENV below, and the home must stay identical to spawn-base's, so revert them.
    RUN cp /etc/skel/.bashrc /home/coder/.bashrc \\
        && cp /etc/skel/.profile /home/coder/.profile

    ENV PATH="/opt/js/bun/bin:/opt/js/deno/bin:${PATH}"
    """
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContainerfileTemplates`
Expected: PASS.

- [ ] **Step 5: Rebuild and verify empirically**

```bash
swift run spawn build js
container run --rm spawn-js:latest /bin/sh -c \
  'bun --version && deno --version | head -1 && find /home/coder -type f | wc -l && grep -cE "bun|deno" /home/coder/.bashrc'
```

Expected: working `bun`/`deno`, a home file count of **7**, and `grep -c` reporting **0** matches in `.bashrc`.

- [ ] **Step 6: Commit**

```bash
git add Sources/ContainerfileTemplates.swift Tests/ContainerfileTemplatesTests.swift
git commit -m "refactor: move bun/deno out of \$HOME and revert installer rc edits"
```

---

### Task 3: Relocate the Go workspace

**Files:**
- Modify: `Sources/ContainerfileTemplates.swift:224-231` (the `go` template)
- Test: `Tests/ContainerfileTemplatesTests.swift`

**Interfaces:**
- Consumes: nothing.
- Produces: `spawn-go:latest` with `GOPATH=/opt/go` and `PATH` containing `/opt/go/bin`.

**Why:** the current template puts `/home/coder/go/bin` on `PATH`, so `go install` writes binaries and `GOMODCACHE` into the home the first time anyone uses it. The home looks clean today only because nothing has run yet.

- [ ] **Step 1: Write the failing test**

Append to `Tests/ContainerfileTemplatesTests.swift`:

```swift
@Test func goWorkspaceLivesOutsideHome() {
    let content = ContainerfileTemplates.content(for: .go)
    #expect(content.contains("GOPATH=/opt/go"))
    #expect(content.contains("/opt/go/bin"))
    #expect(!content.contains("/home/coder/go"), "GOPATH must not be in the home")
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter ContainerfileTemplates`
Expected: FAIL — `GOPATH must not be in the home`.

- [ ] **Step 3: Write minimal implementation**

Replace the `go` template in `Sources/ContainerfileTemplates.swift` (currently lines 224-231):

```swift
static let go = """
    FROM spawn-base:latest

    USER root
    RUN curl -fsSL "https://go.dev/dl/go\(goVersion).linux-\(goArch).tar.gz" | tar -C /usr/local -xz
    # GOPATH in /opt, not $HOME — `go install` and GOMODCACHE would otherwise
    # fill the user's persistent home with build artifacts.
    RUN mkdir -p /opt/go && chown -R coder:coder /opt/go

    USER coder
    ENV GOPATH=/opt/go
    ENV PATH="/usr/local/go/bin:/opt/go/bin:${PATH}"
    """
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter ContainerfileTemplates`
Expected: PASS.

- [ ] **Step 5: Rebuild and verify empirically**

```bash
swift run spawn build go
container run --rm spawn-go:latest /bin/sh -c \
  'go version && go env GOPATH GOMODCACHE && find /home/coder -type f | wc -l'
```

Expected: `GOPATH=/opt/go`, `GOMODCACHE=/opt/go/pkg/mod`, home file count **7**.

- [ ] **Step 6: Commit**

```bash
git add Sources/ContainerfileTemplates.swift Tests/ContainerfileTemplatesTests.swift
git commit -m "refactor: move GOPATH out of \$HOME into /opt/go"
```

---

### Task 4: Persist build caches in named volumes

**Files:**
- Create: `Sources/CacheVolumes.swift`
- Modify: `Sources/ContainerRunner.swift:88-135` (`buildArgs`)
- Modify: `Sources/RunCommand.swift:213` area (pass the toolchain through)
- Test: `Tests/CacheVolumesTests.swift`, `Tests/ContainerRunnerTests.swift`

**Interfaces:**
- Consumes: `Toolchain` (`Sources/Types.swift:5`).
- Produces:
  - `CacheVolumes.forToolchain(_ toolchain: Toolchain) -> [CacheVolume]`
  - `struct CacheVolume: Sendable, Equatable { let name: String; let guestPath: String }`
  - `ContainerRunner.buildArgs(...)` gains a `cacheVolumes: [CacheVolume]` parameter, emitting `--volume <name>:<guestPath>` for each.

**Why volumes and not the home:** these are caches, not user state. They should survive between runs (so `cargo build` doesn't re-download the index every time) but must not sit in a directory that gets seeded, migrated, or deleted with `spawn home rm`. `container volume` (1.2.2) is the right primitive, and named volumes have better write performance than VirtioFS bind mounts.

- [ ] **Step 1: Write the failing test**

Create `Tests/CacheVolumesTests.swift`:

```swift
import Foundation
import Testing

@testable import spawn

@Test func rustGetsCargoRegistryAndGitCaches() {
    let volumes = CacheVolumes.forToolchain(.rust)
    #expect(volumes.contains { $0.guestPath == "/opt/rust/cargo/registry" })
    #expect(volumes.contains { $0.guestPath == "/opt/rust/cargo/git" })
}

@Test func goGetsModuleCache() {
    #expect(CacheVolumes.forToolchain(.go).contains { $0.guestPath == "/opt/go/pkg/mod" })
}

@Test func jsGetsDenoAndNpmCaches() {
    let volumes = CacheVolumes.forToolchain(.js)
    #expect(volumes.contains { $0.guestPath == "/opt/js/deno-cache" })
    #expect(volumes.contains { $0.guestPath == "/home/coder/.npm" })
}

@Test func baseHasNoCacheVolumes() {
    #expect(CacheVolumes.forToolchain(.base).isEmpty)
}

@Test func volumeNamesAreNamespacedAndStable() {
    for volume in CacheVolumes.forToolchain(.rust) {
        #expect(volume.name.hasPrefix("spawn-cache-"))
    }
    #expect(CacheVolumes.forToolchain(.rust) == CacheVolumes.forToolchain(.rust))
}
```

Append to `Tests/ContainerRunnerTests.swift`:

```swift
@Test func buildArgsEmitsCacheVolumes() {
    let args = ContainerRunner.buildArgs(
        image: "spawn-rust:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace",
        entrypoint: ["true"],
        cpus: 4,
        memory: "8g",
        cacheVolumes: [CacheVolume(name: "spawn-cache-cargo-registry", guestPath: "/opt/rust/cargo/registry")]
    )
    #expect(args.contains("spawn-cache-cargo-registry:/opt/rust/cargo/registry"))
}

@Test func buildArgsWithNoCacheVolumesIsUnchanged() {
    let args = ContainerRunner.buildArgs(
        image: "spawn-base:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace",
        entrypoint: ["true"],
        cpus: 4,
        memory: "8g",
        cacheVolumes: []
    )
    #expect(!args.contains { $0.hasPrefix("spawn-cache-") })
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter "CacheVolumes|buildArgsEmitsCacheVolumes"`
Expected: FAIL — `cannot find 'CacheVolumes' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/CacheVolumes.swift`:

```swift
import Foundation

/// A named `container` volume holding a build cache.
///
/// Caches are deliberately kept out of both the image and the user's home: they
/// should survive between runs, but they are not user state and must not be
/// seeded, migrated, or removed along with a home.
struct CacheVolume: Sendable, Equatable {
    let name: String
    let guestPath: String
}

enum CacheVolumes: Sendable {
    private static let prefix = "spawn-cache-"

    /// Build caches for a toolchain. Paths must match the toolchain locations
    /// set in `ContainerfileTemplates`.
    static func forToolchain(_ toolchain: Toolchain) -> [CacheVolume] {
        switch toolchain {
        case .base, .cpp:
            return []
        case .rust:
            return [
                CacheVolume(name: prefix + "cargo-registry", guestPath: "/opt/rust/cargo/registry"),
                CacheVolume(name: prefix + "cargo-git", guestPath: "/opt/rust/cargo/git"),
            ]
        case .go:
            return [CacheVolume(name: prefix + "go-mod", guestPath: "/opt/go/pkg/mod")]
        case .js:
            return [
                CacheVolume(name: prefix + "deno", guestPath: "/opt/js/deno-cache"),
                CacheVolume(name: prefix + "npm", guestPath: "/home/coder/.npm"),
            ]
        }
    }
}
```

In `Sources/ContainerRunner.swift`, add `cacheVolumes: [CacheVolume] = []` to both `buildArgs` and `run`, and emit them right after the existing mounts loop (currently line 118):

```swift
// Named cache volumes. `container` creates a missing volume on first use.
for volume in cacheVolumes {
    args += ["--volume", "\(volume.name):\(volume.guestPath)"]
}
```

Thread it through `run` into `buildArgs`, and at `Sources/RunCommand.swift` pass `cacheVolumes: CacheVolumes.forToolchain(resolvedToolchain)`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test`
Expected: PASS, whole suite. The default `= []` keeps every existing `buildArgs` call site compiling.

- [ ] **Step 5: Verify the cache actually persists**

```bash
swift run spawn build rust
cd fixtures/rust-sample
swift run spawn -- cargo fetch          # populates the volume
container volume list | grep spawn-cache
time swift run spawn -- cargo fetch     # should be markedly faster
```

Expected: `spawn-cache-cargo-registry` and `spawn-cache-cargo-git` appear in `container volume list`, and the second fetch is faster than the first.

- [ ] **Step 6: Commit**

```bash
git add Sources/CacheVolumes.swift Sources/ContainerRunner.swift Sources/RunCommand.swift Tests/
git commit -m "feat: persist build caches in named container volumes"
```

---

### Task 5: Enforce the invariant, report, and document

**Files:**
- Modify: `scripts/smoke.sh`
- Modify: `Sources/DoctorCommand.swift`
- Modify: `AGENTS.md`, `README.md`, `docs/`
- Modify: `Images/*/Containerfile` (regenerate or delete — see below)
- Test: `Tests/DoctorCommandTests.swift`

**Interfaces:**
- Consumes: `CacheVolumes.forToolchain` (Task 4).
- Produces: a smoke assertion that every toolchain image's home matches base's, and a doctor line listing cache volumes.

- [ ] **Step 1: Write the failing smoke assertion**

Add to `scripts/smoke.sh`, after the existing fixture cases:

```bash
# The invariant this slice exists to establish: toolchain images must not add
# anything to /home/coder. If this fails, a toolchain is leaking into the home
# and the copy-on-write home slice will be slow and wrong.
base_home_count=$("${CONTAINER_BIN}" run --rm spawn-base:latest \
    /bin/sh -c 'find /home/coder -type f | wc -l' | tr -d '[:space:]')
for tc in rust go js cpp; do
    tc_home_count=$("${CONTAINER_BIN}" run --rm "spawn-${tc}:latest" \
        /bin/sh -c 'find /home/coder -type f | wc -l' | tr -d '[:space:]')
    if [ "${tc_home_count}" != "${base_home_count}" ]; then
        echo "FAIL: spawn-${tc} home has ${tc_home_count} files, base has ${base_home_count}"
        exit 1
    fi
done
echo "PASS: all toolchain images keep /home/coder identical to base (${base_home_count} files)"
```

- [ ] **Step 2: Run it to verify it fails on unrebuilt images**

Run: `make smoke`
Expected: FAIL for `rust` (49,650 vs 7) if images predate Tasks 1-3 — which is the point. Rebuild with `swift run spawn build`, then it passes.

- [ ] **Step 3: Add the doctor check**

In `Sources/DoctorCommand.swift`, add a pure formatter beside the existing status-line helpers, following the file's established `Check` pattern rather than printing directly:

```swift
/// Human-readable status line for a toolchain's build cache volumes.
static func cacheVolumeStatusLine(toolchain: Toolchain, volumes: [CacheVolume]) -> String {
    guard !volumes.isEmpty else {
        return "[OK] Cache volumes (\(toolchain.rawValue)): none needed"
    }
    return "[OK] Cache volumes (\(toolchain.rawValue)): " + volumes.map(\.name).joined(separator: ", ")
}
```

Append to `Tests/DoctorCommandTests.swift`:

```swift
@Test func doctorReportsCacheVolumes() {
    let line = Spawn.Doctor.cacheVolumeStatusLine(
        toolchain: .rust,
        volumes: CacheVolumes.forToolchain(.rust)
    )
    #expect(line.contains("spawn-cache-cargo-registry"))
}

@Test func doctorReportsNoCacheVolumesForBase() {
    let line = Spawn.Doctor.cacheVolumeStatusLine(toolchain: .base, volumes: [])
    #expect(line.contains("none needed"))
}
```

Note the type is `Spawn.Doctor`, not `DoctorCommand` — the file declares `extension Spawn { struct Doctor: ParsableCommand }`.

- [ ] **Step 4: Run tests**

Run: `swift test`
Expected: PASS, whole suite.

- [ ] **Step 5: Reconcile the checked-in Containerfiles**

`Images/*/Containerfile` are built by `make images` (Makefile) and have already drifted from `ContainerfileTemplates` — they lack a `js` variant, the gh-cli install, and the guard scripts. They would now also lack the toolchain relocation, producing images that violate the Task 5 invariant.

Delete them and the `make images` target, since `ContainerfileTemplates.swift` is the single source of truth and `spawn build` is the supported path:

```bash
git rm -r Images/
```

Then remove the `images` target from the `Makefile`. If you would rather keep them, regenerate each from `ContainerfileTemplates.content(for:)` instead — but do not leave them stale.

- [ ] **Step 6: Update documentation**

- `AGENTS.md` — under "Important Design Constraints", add: `- language toolchains live under /opt (/opt/rust, /opt/go, /opt/js), never in /home/coder; build caches are named container volumes (see Sources/CacheVolumes.swift)`. Add `Sources/CacheVolumes.swift` to the Module Map. Note the invariant that toolchain images keep `/home/coder` identical to base's.
- `README.md` — document that build caches persist automatically in named volumes, and how to clear them (`container volume delete spawn-cache-cargo-registry`).
- `docs/` — same, on the images/toolchains page.

- [ ] **Step 7: Full verification and commit**

```bash
make test
make smoke
swift run spawn build
container run --rm spawn-rust:latest /bin/sh -c 'find /home/coder -type f | wc -l'   # expect 7
git add -A
git commit -m "test: enforce toolchain-free home, report cache volumes, drop stale Images/"
```

---

## Self-Review

**Spec coverage.** The invariant is established by Tasks 1-3 (rust, js, go) and enforced by Task 5. Cache persistence — the second half of the goal — is Task 4. `cpp` needs no change: it installs clang via apt into system paths and adds nothing to the home, which Task 5's loop verifies rather than assumes.

**Placeholder scan.** No TBDs. Every code step carries real code; every verification step names the command and the expected number.

**Type consistency.** `CacheVolume(name:guestPath:)` and `CacheVolumes.forToolchain(_:)` are defined in Task 4 and used with those exact names in Tasks 4 and 5. `Toolchain` and its `.base/.cpp/.rust/.go/.js` cases match `Sources/Types.swift:5-13`. `Spawn.Doctor` is the real type name (verified — `DoctorCommand.swift:4-5` declares `extension Spawn { struct Doctor }`), corrected from an earlier draft that used `DoctorCommand`.

**Known risks.**
1. Tasks 1-3 each require an image rebuild before their verification step passes; each task's Step 5 rebuilds only its own toolchain to keep failures attributable.
2. Task 4 changes a `buildArgs` signature. The `= []` default keeps all existing call sites compiling, so no task leaves the tree broken — this was a defect in the superseded COW-home plan and is deliberately avoided here.
3. Relocating `GOPATH` and `CARGO_HOME` changes paths a user's `.spawn.toml` or scripts might reference. Task 5's docs update calls this out; it is a breaking change for anyone who hardcoded `/home/coder/.cargo`.

## Relationship To The COW Home Slice

This plan is the prerequisite for `2026-08-12-cow-home.md`, which is **superseded pending revision** and must not be executed as written (it has compile errors, a credential-leak design flaw, and a measured 2.7s-per-start regression). Once this plan lands, the COW home's seed cost drops from 2,676ms to roughly 2ms — the measured `spawn-base` figure — and its "first writer wins across toolchain skels" problem disappears entirely, because every toolchain image will have the same home.
