# XDG Base Directory Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace hardcoded `~/.spawn` paths with XDG Base Directory standard paths, respecting `XDG_CONFIG_HOME` and `XDG_STATE_HOME` environment variables.

**Architecture:** New `Paths` enum centralizes XDG path resolution. `MountResolver` and `EnvLoader` consume `Paths` instead of constructing paths themselves. Tests verify both default and custom XDG paths.

**Tech Stack:** Swift, swift-testing framework

---

### Task 1: Create `Paths.swift` with tests (TDD)

**Files:**
- Create: `Sources/Paths.swift`
- Create: `Tests/PathsTests.swift`

**Step 1: Write the failing tests**

In `Tests/PathsTests.swift`:

```swift
import Testing
import Foundation
@testable import spawn

@Test func defaultConfigDir() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(Paths.configDir.path == "\(home)/.config/spawn")
}

@Test func defaultStateDir() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(Paths.stateDir.path == "\(home)/.local/state/spawn")
}

@Test func configDirRespectsXDGEnv() {
    let custom = Paths.configDir(xdgConfigHome: "/tmp/myconfig")
    #expect(custom.path == "/tmp/myconfig/spawn")
}

@Test func stateDirRespectsXDGEnv() {
    let custom = Paths.stateDir(xdgStateHome: "/tmp/mystate")
    #expect(custom.path == "/tmp/mystate/spawn")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter Paths 2>&1`
Expected: Compilation error — `Paths` not defined.

**Step 3: Write minimal implementation**

In `Sources/Paths.swift`:

```swift
import Foundation

enum Paths {
    static var configDir: URL {
        configDir(xdgConfigHome: ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"])
    }

    static var stateDir: URL {
        stateDir(xdgStateHome: ProcessInfo.processInfo.environment["XDG_STATE_HOME"])
    }

    static func configDir(xdgConfigHome: String?) -> URL {
        let base: URL
        if let custom = xdgConfigHome {
            base = URL(fileURLWithPath: custom)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let dir = base.appendingPathComponent("spawn")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func stateDir(xdgStateHome: String?) -> URL {
        let base: URL
        if let custom = xdgStateHome {
            base = URL(fileURLWithPath: custom)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local")
                .appendingPathComponent("state")
        }
        let dir = base.appendingPathComponent("spawn")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter Paths 2>&1`
Expected: All 4 tests PASS.

**Step 5: Commit**

```bash
git add Sources/Paths.swift Tests/PathsTests.swift
git commit -m "feat: add Paths module with XDG base directory support"
```

---

### Task 2: Migrate `MountResolver` to use `Paths.stateDir`

**Files:**
- Modify: `Sources/MountResolver.swift:5-11` (remove `stateDir` property, use `Paths.stateDir`)
- Modify: `Sources/MountResolver.swift:38,73` (update comments)

**Step 1: Run existing tests to confirm green baseline**

Run: `swift test --filter MountResolver 2>&1`
Expected: All pass.

**Step 2: Replace `stateDir` property with `Paths.stateDir`**

In `Sources/MountResolver.swift`, remove lines 4-11 (the `stateDir` static property) and replace all references to `stateDir` with `Paths.stateDir`. Update the comments that reference `~/.spawn/state/`.

The full resulting file:

```swift
import Foundation

enum MountResolver {
    static func resolve(
        target: URL,
        additional: [String],
        readOnly: [String],
        includeGit: Bool,
        agent: String
    ) -> [Mount] {
        var mounts: [Mount] = []

        // Primary target
        mounts.append(Mount(hostPath: target.path, readOnly: false))

        // Additional read-write mounts
        for path in additional {
            mounts.append(Mount(hostPath: path, readOnly: false))
        }

        // Read-only mounts
        for path in readOnly {
            mounts.append(Mount(hostPath: path, readOnly: true))
        }

        // Git/SSH mounts
        // VirtioFS preserves host file ownership/permissions, so files owned by the
        // macOS user (uid 501) with 600 permissions are unreadable by the container's
        // coder user (uid 1001). We copy to the XDG state dir where we control
        // permissions, and mount the copies.
        if includeGit {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default

            let gitconfig = home.appendingPathComponent(".gitconfig")
            if fm.fileExists(atPath: gitconfig.path) {
                let gitDir = Paths.stateDir.appendingPathComponent("git")
                try? fm.createDirectory(at: gitDir, withIntermediateDirectories: true)
                let dest = gitDir.appendingPathComponent(".gitconfig")
                try? fm.removeItem(at: dest)
                try? fm.copyItem(at: gitconfig, to: dest)
                mounts.append(Mount(
                    hostPath: gitDir.path,
                    guestPath: "/home/coder/.gitconfig-dir",
                    readOnly: true
                ))
            }

            let sshDir = home.appendingPathComponent(".ssh")
            if fm.fileExists(atPath: sshDir.path) {
                let sshCopy = Paths.stateDir.appendingPathComponent("ssh")
                try? fm.removeItem(at: sshCopy)
                try? fm.copyItem(at: sshDir, to: sshCopy)
                mounts.append(Mount(
                    hostPath: sshCopy.path,
                    guestPath: "/home/coder/.ssh",
                    readOnly: true
                ))
            }
        }

        // Persistent agent credential state → /home/coder/.<agent-config-dir>
        // This lets OAuth tokens survive container restarts so users only auth once.
        let agentStateDir = Paths.stateDir.appendingPathComponent(agent)
        try? FileManager.default.createDirectory(at: agentStateDir, withIntermediateDirectories: true)

        switch agent {
        case "claude-code":
            let claudeDir = agentStateDir.appendingPathComponent("claude")
            try? FileManager.default.createDirectory(at: claudeDir, withIntermediateDirectories: true)
            mounts.append(Mount(
                hostPath: claudeDir.path,
                guestPath: "/home/coder/.claude",
                readOnly: false
            ))
            let claudeStateDir = agentStateDir.appendingPathComponent("claude-state")
            try? FileManager.default.createDirectory(at: claudeStateDir, withIntermediateDirectories: true)
            mounts.append(Mount(
                hostPath: claudeStateDir.path,
                guestPath: "/home/coder/.claude-state",
                readOnly: false
            ))
        case "codex":
            let codexDir = agentStateDir.appendingPathComponent("codex")
            try? FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
            mounts.append(Mount(
                hostPath: codexDir.path,
                guestPath: "/home/coder/.codex",
                readOnly: false
            ))
        default:
            break
        }

        return mounts
    }
}
```

**Step 3: Run tests**

Run: `swift test --filter MountResolver 2>&1`
Expected: All pass (mount paths changed but tests check guest paths, not host paths).

**Step 4: Commit**

```bash
git add Sources/MountResolver.swift
git commit -m "refactor: use Paths.stateDir in MountResolver"
```

---

### Task 3: Migrate `EnvLoader` to use `Paths.configDir`

**Files:**
- Modify: `Sources/EnvLoader.swift:10-11`

**Step 1: Run existing tests to confirm green baseline**

Run: `swift test --filter EnvLoader 2>&1`
Expected: All pass.

**Step 2: Replace hardcoded path**

In `Sources/EnvLoader.swift`, change `loadDefault()` from:

```swift
let defaultPath = home.appendingPathComponent(".spawn/env").path
```

to:

```swift
let defaultPath = Paths.configDir.appendingPathComponent("env").path
```

Also remove the now-unused `let home = ...` line.

**Step 3: Run tests**

Run: `swift test --filter EnvLoader 2>&1`
Expected: All pass (existing tests use `parse()` directly, not `loadDefault()`).

**Step 4: Commit**

```bash
git add Sources/EnvLoader.swift
git commit -m "refactor: use Paths.configDir in EnvLoader"
```

---

### Task 4: Update comments and documentation

**Files:**
- Modify: `Sources/RunCommand.swift:104` (update comment)
- Modify: `CLAUDE.md` (update path references)

**Step 1: Update RunCommand comment**

In `Sources/RunCommand.swift`, change line 104 from:
```
// Credentials are persisted in ~/.spawn/state/<agent>/ across runs.
```
to:
```
// Credentials are persisted in $XDG_STATE_HOME/spawn/<agent>/ across runs.
```

**Step 2: Update CLAUDE.md**

Replace references to `~/.spawn/env` with `~/.config/spawn/env` and `~/.spawn/state/` with `~/.local/state/spawn/`. Update the module reference table to include `Paths.swift`.

**Step 3: Run full test suite**

Run: `swift test 2>&1`
Expected: All tests pass.

**Step 4: Commit**

```bash
git add Sources/RunCommand.swift CLAUDE.md
git commit -m "docs: update path references to XDG locations"
```
