# Permission Modes and Documentation Site — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add safe-mode permission gating (default) with `--yolo` opt-out, plus a Jekyll docs site on GitHub Pages.

**Architecture:** Safe mode uses Claude Code's native deny rules (seeded into settings.json) and git/gh wrapper scripts in the container image (for Codex). A new `--yolo` flag restores current full-auto behavior. Documentation moves from README to a Jekyll site in `docs/`.

**Tech Stack:** Swift 6.2, swift-testing, Jekyll (GitHub Pages), bash (wrapper scripts)

---

### Task 1: Split AgentProfile entrypoint into safe/yolo variants

**Files:**
- Modify: `Sources/Types.swift:38-68`
- Test: `Tests/TypesTests.swift:30-38`

**Step 1: Write the failing test**

Replace the existing `builtInAgentProfiles` test in `Tests/TypesTests.swift:30-38` with:

```swift
@Test func builtInAgentProfiles() {
    let claude = AgentProfile.claudeCode
    #expect(claude.name == "claude-code")
    #expect(claude.safeEntrypoint == ["claude"])
    #expect(claude.yoloEntrypoint == ["claude", "--dangerously-skip-permissions"])

    let codex = AgentProfile.codex
    #expect(codex.name == "codex")
    #expect(codex.safeEntrypoint == ["codex", "--full-auto"])
    #expect(codex.yoloEntrypoint == ["codex", "--full-auto"])
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter "builtInAgentProfiles"`
Expected: FAIL — `AgentProfile` has no `safeEntrypoint`/`yoloEntrypoint` properties

**Step 3: Write minimal implementation**

In `Sources/Types.swift`, replace the `AgentProfile` struct (lines 38-68) with:

```swift
/// Configuration for a supported AI coding agent (entrypoint, resource defaults).
struct AgentProfile: Sendable {
    let name: String
    let safeEntrypoint: [String]
    let yoloEntrypoint: [String]
    let requiredEnvVars: [String]
    let defaultCPUs: Int
    let defaultMemory: String

    static let claudeCode = AgentProfile(
        name: "claude-code",
        safeEntrypoint: ["claude"],
        yoloEntrypoint: ["claude", "--dangerously-skip-permissions"],
        requiredEnvVars: [],
        defaultCPUs: 4,
        defaultMemory: "8g",
    )

    static let codex = AgentProfile(
        name: "codex",
        safeEntrypoint: ["codex", "--full-auto"],
        yoloEntrypoint: ["codex", "--full-auto"],
        requiredEnvVars: [],
        defaultCPUs: 4,
        defaultMemory: "8g",
    )

    static func named(_ name: String) -> AgentProfile? {
        switch name {
        case "claude-code": return .claudeCode
        case "codex": return .codex
        default: return nil
        }
    }
}
```

Note: Codex `safeEntrypoint` and `yoloEntrypoint` are identical — Codex lacks granular permissions, so the wrapper scripts handle gating instead.

**Step 4: Run test to verify it passes**

Run: `swift test --filter "builtInAgentProfiles"`
Expected: PASS

**Step 5: Commit**

```bash
git add Sources/Types.swift Tests/TypesTests.swift
git commit -m "feat: split AgentProfile entrypoint into safe/yolo variants"
```

---

### Task 2: Add --yolo flag and entrypoint selection to RunCommand

**Files:**
- Modify: `Sources/RunCommand.swift:43-51,159-160`

**Step 1: Add the --yolo flag**

In `Sources/RunCommand.swift`, after the `--verbose` flag (line 50), add:

```swift
@Flag(name: .long, help: "Full auto mode — skip all permission gates.")
var yolo: Bool = false
```

**Step 2: Update entrypoint selection**

In `Sources/RunCommand.swift`, replace line 160:

```swift
let entrypoint = shell ? ["/bin/bash"] : profile.entrypoint
```

with:

```swift
let entrypoint = shell ? ["/bin/bash"] : (yolo ? profile.yoloEntrypoint : profile.safeEntrypoint)
```

**Step 3: Add SPAWN_SAFE_MODE env injection**

In `Sources/RunCommand.swift`, after the CLI `--env` overrides block (after line 153), add:

```swift
// Safe mode: activate wrapper scripts inside the container
if !yolo {
    environment["SPAWN_SAFE_MODE"] = "1"
}
```

**Step 4: Add mode visibility print**

In `Sources/RunCommand.swift`, after the toolchain detection print (after line 105), add:

```swift
// Print permission mode
if yolo {
    print("Yolo mode: all operations unrestricted")
} else {
    print("Safe mode: remote git operations require approval (use --yolo to disable)")
}
```

**Step 5: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

**Step 6: Commit**

```bash
git add Sources/RunCommand.swift
git commit -m "feat: add --yolo flag with safe mode as default"
```

---

### Task 3: Create SettingsSeeder module

**Files:**
- Create: `Sources/SettingsSeeder.swift`
- Create: `Tests/SettingsSeederTests.swift`

**Step 1: Write the failing tests**

Create `Tests/SettingsSeederTests.swift`:

```swift
import Foundation
import Testing

@testable import spawn

@Test func seedsFreshSettingsFile() throws {
    let dir = try makeTempDir(files: [:])
    let settingsFile = dir.appendingPathComponent("settings.json")

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: settingsFile)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]
    let allow = permissions?["allow"] as? [String]
    let deny = permissions?["deny"] as? [String]

    #expect(allow != nil)
    #expect(deny != nil)
    #expect(allow!.contains("Bash(git add:*)"))
    #expect(deny!.contains("Bash(git push:*)"))
}

@Test func preservesExistingPermissions() throws {
    let existing = """
        {"permissions": {"allow": ["Bash(custom:*)"], "deny": []}}
        """
    let dir = try makeTempDir(files: ["settings.json": existing])

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]
    let allow = permissions?["allow"] as? [String]

    #expect(allow == ["Bash(custom:*)"])
}

@Test func seedsWhenPermissionsKeyMissing() throws {
    let existing = """
        {"skipDangerousModePermissionPrompt": true}
        """
    let dir = try makeTempDir(files: ["settings.json": existing])

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]

    #expect(permissions != nil)
    #expect(json?["skipDangerousModePermissionPrompt"] as? Bool == true)
}

@Test func skipsOnMalformedJson() throws {
    let dir = try makeTempDir(files: ["settings.json": "not json {{{"])

    SettingsSeeder.seed(settingsDir: dir)

    let content = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
    #expect(content == "not json {{{")
}

@Test func emptyPermissionsCountsAsCustomized() throws {
    let existing = """
        {"permissions": {}}
        """
    let dir = try makeTempDir(files: ["settings.json": existing])

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]

    #expect(permissions?.isEmpty == true)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter "SettingsSeeder"`
Expected: FAIL — `SettingsSeeder` doesn't exist

**Step 3: Write the implementation**

Create `Sources/SettingsSeeder.swift`:

```swift
import Foundation

/// Seeds Claude Code's settings.json with safe-mode permission rules.
/// Reads the existing file, checks for a `permissions` key, and merges
/// seed rules only if permissions haven't been customized.
enum SettingsSeeder: Sendable {
    /// The default allow rules for safe mode — local git, build tools, file operations.
    static let seedAllow: [String] = [
        "Bash(git add:*)",
        "Bash(git commit:*)",
        "Bash(git diff:*)",
        "Bash(git status:*)",
        "Bash(git log:*)",
        "Bash(git branch:*)",
        "Bash(git checkout:*)",
        "Bash(git switch:*)",
        "Bash(git stash:*)",
        "Bash(git rebase:*)",
        "Bash(git reset:*)",
        "Bash(git restore:*)",
        "Bash(git show:*)",
        "Bash(git tag:*)",
        "Bash(git fetch:*)",
        "Bash(git pull:*)",
        "Bash(git merge:*)",
        "Bash(make:*)",
        "Bash(swift:*)",
        "Bash(cargo:*)",
        "Bash(go:*)",
        "Bash(cmake:*)",
        "Bash(ninja:*)",
        "Bash(npm:*)",
        "Bash(node:*)",
        "Bash(python:*)",
        "Bash(pip:*)",
    ]

    /// The default deny rules for safe mode — remote-write git/gh operations.
    static let seedDeny: [String] = [
        "Bash(git push:*)",
        "Bash(git remote add:*)",
        "Bash(git remote set-url:*)",
        "Bash(gh pr create:*)",
        "Bash(gh pr merge:*)",
        "Bash(gh pr close:*)",
        "Bash(gh issue create:*)",
        "Bash(gh issue close:*)",
        "Bash(gh release:*)",
        "Bash(gh repo:*)",
    ]

    /// Seed safe-mode permissions into the Claude Code settings directory.
    /// - Parameter settingsDir: The directory containing `settings.json` (e.g. `~/.claude/` inside the container,
    ///   which maps to `~/.local/state/spawn/claude-code/claude/` on the host).
    static func seed(settingsDir: URL) {
        let settingsFile = settingsDir.appendingPathComponent("settings.json")
        let fm = FileManager.default

        // Read existing settings if present
        var settings: [String: Any] = [:]
        if fm.fileExists(atPath: settingsFile.path) {
            guard let data = try? Data(contentsOf: settingsFile),
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                logger.warning("Malformed settings.json at \(settingsFile.path), skipping seed")
                return
            }
            settings = json
        }

        // If permissions key already exists (even empty), user has customized — leave it alone
        if settings["permissions"] != nil {
            return
        }

        // Merge seed permissions
        settings["permissions"] = [
            "allow": seedAllow,
            "deny": seedDeny,
        ]

        // Write back
        guard let data = try? JSONSerialization.data(
            withJSONObject: settings,
            options: [.prettyPrinted, .sortedKeys]
        ) else {
            logger.warning("Failed to serialize settings.json")
            return
        }

        do {
            try fm.createDirectory(at: settingsDir, withIntermediateDirectories: true)
            try data.write(to: settingsFile)
        } catch {
            logger.warning("Failed to write settings.json: \(error.localizedDescription)")
        }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter "SettingsSeeder"`
Expected: All 5 tests PASS

**Step 5: Run full test suite**

Run: `make test`
Expected: Lint + all tests pass

**Step 6: Commit**

```bash
git add Sources/SettingsSeeder.swift Tests/SettingsSeederTests.swift
git commit -m "feat: add SettingsSeeder for Claude Code safe-mode permissions"
```

---

### Task 4: Wire SettingsSeeder into RunCommand

**Files:**
- Modify: `Sources/RunCommand.swift`

**Step 1: Add settings seed call**

In `Sources/RunCommand.swift`, after the mode visibility print and before mount resolution, add:

```swift
// Seed Claude Code safe-mode permissions
if !yolo, agent == "claude-code" {
    let claudeSettingsDir = Paths.stateDir.appendingPathComponent(agent)
        .appendingPathComponent("claude")
    SettingsSeeder.seed(settingsDir: claudeSettingsDir)
}
```

**Step 2: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

**Step 3: Run full test suite**

Run: `make test`
Expected: All tests pass

**Step 4: Commit**

```bash
git add Sources/RunCommand.swift
git commit -m "feat: wire SettingsSeeder into RunCommand for safe mode"
```

---

### Task 5: Add git/gh wrapper scripts to container base image

**Files:**
- Modify: `Sources/ContainerfileTemplates.swift:25-66`

**Step 1: Add wrapper script constants**

In `Sources/ContainerfileTemplates.swift`, add before the `base` property (before line 25):

```swift
/// Git wrapper script that prompts before remote-write operations in safe mode.
private static let gitGuard = #"""
    #!/bin/bash
    REAL_GIT=/usr/bin/git

    # Pass through immediately if safe mode is not active
    if [[ "${SPAWN_SAFE_MODE:-}" != "1" ]]; then
        exec "$REAL_GIT" "$@"
    fi

    # Find the actual subcommand by skipping option flags
    subcmd=""
    i=1
    while [[ $i -le $# ]]; do
        arg="${!i}"
        case "$arg" in
            -c|--config|-C)
                # These flags take a following argument, skip both
                ((i+=2))
                ;;
            -*)
                ((i++))
                ;;
            *)
                subcmd="$arg"
                break
                ;;
        esac
    done

    case "$subcmd" in
        push)
            printf '\033[1;33mspawn:\033[0m agent wants to run: git %s\n' "$*" >/dev/tty 2>/dev/null
            printf 'allow? [y/N] ' >/dev/tty 2>/dev/null
            read -r answer </dev/tty 2>/dev/null || { echo "spawn: git push blocked — safe mode requires a TTY for approval" >&2; exit 1; }
            [[ "$answer" =~ ^[Yy]$ ]] || { echo "spawn: blocked by safe mode" >&2; exit 1; }
            ;;
        remote)
            # Check for mutating remote subcommands: add, set-url
            next_i=$((i + 1))
            remote_sub="${!next_i}"
            case "$remote_sub" in
                add|set-url)
                    printf '\033[1;33mspawn:\033[0m agent wants to run: git %s\n' "$*" >/dev/tty 2>/dev/null
                    printf 'allow? [y/N] ' >/dev/tty 2>/dev/null
                    read -r answer </dev/tty 2>/dev/null || { echo "spawn: git remote $remote_sub blocked — safe mode requires a TTY for approval" >&2; exit 1; }
                    [[ "$answer" =~ ^[Yy]$ ]] || { echo "spawn: blocked by safe mode" >&2; exit 1; }
                    ;;
            esac
            ;;
    esac

    exec "$REAL_GIT" "$@"
    """#

/// GitHub CLI wrapper script that prompts before mutating operations in safe mode.
private static let ghGuard = #"""
    #!/bin/bash
    REAL_GH=/usr/bin/gh

    # Pass through immediately if safe mode is not active
    if [[ "${SPAWN_SAFE_MODE:-}" != "1" ]]; then
        exec "$REAL_GH" "$@"
    fi

    prompt_user() {
        printf '\033[1;33mspawn:\033[0m agent wants to run: gh %s\n' "$*" >/dev/tty 2>/dev/null
        printf 'allow? [y/N] ' >/dev/tty 2>/dev/null
        read -r answer </dev/tty 2>/dev/null || { echo "spawn: gh command blocked — safe mode requires a TTY for approval" >&2; exit 1; }
        [[ "$answer" =~ ^[Yy]$ ]] || { echo "spawn: blocked by safe mode" >&2; exit 1; }
    }

    case "${1:-}" in
        pr)
            case "${2:-}" in
                create|merge|close) prompt_user "$@" ;;
            esac
            ;;
        issue)
            case "${2:-}" in
                create|close) prompt_user "$@" ;;
            esac
            ;;
        release|repo)
            prompt_user "$@"
            ;;
    esac

    exec "$REAL_GH" "$@"
    """#
```

**Step 2: Update the base Containerfile template**

In `Sources/ContainerfileTemplates.swift`, in the `base` string, after the symlink setup block (after the `ln -sf` line, before `WORKDIR /workspace`), add:

```swift
        # Safe-mode wrapper scripts for git/gh (activated by SPAWN_SAFE_MODE=1)
        RUN mkdir -p /usr/local/lib/spawn \\
            && cat > /usr/local/lib/spawn/git-guard.sh << 'GUARD_EOF'
        \(gitGuard)
        GUARD_EOF
            && cat > /usr/local/lib/spawn/gh-guard.sh << 'GUARD_EOF'
        \(ghGuard)
        GUARD_EOF
            && chmod +x /usr/local/lib/spawn/git-guard.sh /usr/local/lib/spawn/gh-guard.sh \\
            && ln -sf /usr/local/lib/spawn/git-guard.sh /usr/local/bin/git \\
            && ln -sf /usr/local/lib/spawn/gh-guard.sh /usr/local/bin/gh
```

Note: This runs as `USER coder` so the `ln -sf` to `/usr/local/bin/` will need `sudo`. Move the block before `USER coder` or add `sudo`. Check the Containerfile — the GitHub CLI install is as root, then `USER coder` is set. The wrapper install should happen while still root. Insert the wrapper block **before** `USER coder` (line 53) and **after** the GitHub CLI install.

**Step 3: Build to verify compilation**

Run: `swift build`
Expected: Build succeeds

**Step 4: Commit**

```bash
git add Sources/ContainerfileTemplates.swift
git commit -m "feat: add git/gh safe-mode wrapper scripts to base container image"
```

---

### Task 6: Add SPAWN_SAFE_MODE test to ContainerRunnerTests

**Files:**
- Modify: `Tests/ContainerRunnerTests.swift`

**Step 1: Write the test**

Add to `Tests/ContainerRunnerTests.swift`:

```swift
@Test func safeModeIncludesSafeEnvVar() {
    let args = ContainerRunner.buildArgs(
        image: "spawn-base:latest",
        mounts: [],
        env: ["SPAWN_SAFE_MODE": "1"],
        workdir: "/workspace/test",
        entrypoint: ["claude"],
        cpus: 4,
        memory: "8g",
    )

    // Find the --env flag followed by SPAWN_SAFE_MODE=1
    let envArgs = zip(args, args.dropFirst()).filter { $0.0 == "--env" }.map(\.1)
    #expect(envArgs.contains("SPAWN_SAFE_MODE=1"))
}

@Test func yoloModeOmitsSafeEnvVar() {
    let args = ContainerRunner.buildArgs(
        image: "spawn-base:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace/test",
        entrypoint: ["claude", "--dangerously-skip-permissions"],
        cpus: 4,
        memory: "8g",
    )

    let envArgs = zip(args, args.dropFirst()).filter { $0.0 == "--env" }.map(\.1)
    #expect(!envArgs.contains("SPAWN_SAFE_MODE=1"))
}
```

**Step 2: Run tests to verify they pass**

Run: `swift test --filter "safeMode\|yoloMode"`
Expected: Both PASS (these test the buildArgs pure function with env already set by RunCommand)

**Step 3: Run full test suite**

Run: `make test`
Expected: Lint + all tests pass

**Step 4: Commit**

```bash
git add Tests/ContainerRunnerTests.swift
git commit -m "test: add safe mode env var tests for ContainerRunner"
```

---

### Task 7: Update CLAUDE.md

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Update Key Design Decisions**

In `CLAUDE.md`, replace the line about agents running in sandbox mode (line 60):

```
- **Agents run in sandbox mode**: Claude Code gets `--dangerously-skip-permissions`, Codex gets `--full-auto` — the container is the sandbox.
```

with:

```
- **Safe mode is the default**: Claude Code runs without `--dangerously-skip-permissions` and gets a seeded settings.json with deny rules for remote-write git/gh operations. Codex keeps `--full-auto` but git/gh wrapper scripts in the container intercept and prompt for remote-write operations. The `--yolo` flag restores full-auto behavior for both agents.
```

**Step 2: Add SettingsSeeder to Module Reference**

Add row to the Module Reference table:

```
| `SettingsSeeder.swift` | Seeds Claude Code's settings.json with safe-mode permission rules (allow local ops, deny remote-write git/gh) |
```

**Step 3: Update Run Command Pipeline**

In the pipeline diagram, add the settings seed step after `AgentProfile.named()`:

```
RunCommand.run()
  → AgentProfile.named()          # Validate agent (claude-code/codex)
  → SettingsSeeder.seed()         # Seed safe-mode permissions (claude-code only)
  → ToolchainDetector.detect()    # Auto-detect or use override
  ...
```

**Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: update CLAUDE.md for safe mode and SettingsSeeder"
```

---

### Task 8: Slim down README.md and add docs link

**Files:**
- Modify: `README.md`

**Step 1: Add --yolo to spawn run options**

In the `spawn run` options block, add after `--verbose`:

```
  --yolo                Full auto mode — skip all permission gates
```

**Step 2: Replace detailed sections with docs link**

Remove these sections from README.md:
- Detailed `spawn run` options block (keep a one-liner mentioning `--help`)
- Toolchain detection table and details
- Authentication section
- Directory layout section
- Container images section

Replace them with a single link section after Quick start:

```markdown
## Documentation

For detailed usage, permissions, authentication, and configuration:
**[vmunix.github.io/spawn](https://vmunix.github.io/spawn/)**
```

Keep: one-liner + hero block, What it does, Requirements, Install, Quick start, the new Documentation link, Development, License.

**Step 3: Commit**

```bash
git add README.md
git commit -m "docs: slim README to landing page, link to docs site"
```

---

### Task 9: Set up Jekyll docs site structure

**Files:**
- Create: `docs/_config.yml`
- Create: `docs/index.md`
- Create: `docs/getting-started.md`
- Create: `docs/usage.md`
- Create: `docs/toolchains.md`
- Create: `docs/permissions.md`
- Create: `docs/authentication.md`
- Create: `docs/architecture.md`

**Step 1: Create `docs/_config.yml`**

```yaml
title: spawn
description: Sandboxed AI coding agents on macOS
remote_theme: just-the-docs/just-the-docs
url: https://vmunix.github.io/spawn

nav_order:
  - Home
  - Getting Started
  - Usage
  - Toolchains
  - Permissions
  - Authentication
  - Architecture

exclude:
  - plans/
```

**Step 2: Create `docs/index.md`**

Content: mirrors slimmed README — what it does, install (brew + source), quick start. Front matter with `title: Home`, `nav_order: 1`.

**Step 3: Create `docs/getting-started.md`**

Content: full install guide (brew, source, PATH), building images, first run walkthrough. Front matter with `title: Getting Started`, `nav_order: 2`.

**Step 4: Create `docs/usage.md`**

Content: full `spawn run` options table (moved from README), all subcommands, examples. Front matter with `title: Usage`, `nav_order: 3`.

**Step 5: Create `docs/toolchains.md`**

Content: detection logic, supported toolchains table, `.spawn.toml` format, devcontainer support, `--toolchain` override. Front matter with `title: Toolchains`, `nav_order: 4`.

**Step 6: Create `docs/permissions.md`**

Content: safe mode vs yolo, what's gated (table of allow/deny), how prompts work, customizing settings.json, per-repo overrides, known limitations. Front matter with `title: Permissions`, `nav_order: 5`.

**Step 7: Create `docs/authentication.md`**

Content: OAuth flow, gh auth, API keys, credential persistence, directory layout. Moved from README. Front matter with `title: Authentication`, `nav_order: 6`.

**Step 8: Create `docs/architecture.md`**

Content: directory layout table, container images, image layering, design decisions. Front matter with `title: Architecture`, `nav_order: 7`.

**Step 9: Commit**

```bash
git add docs/_config.yml docs/index.md docs/getting-started.md docs/usage.md \
    docs/toolchains.md docs/permissions.md docs/authentication.md docs/architecture.md
git commit -m "docs: add Jekyll docs site with full documentation"
```

---

### Task 10: Enable GitHub Pages

**Step 1: Enable Pages via gh CLI**

```bash
gh api repos/vmunix/spawn/pages -X POST -f source.branch=main -f source.path=/docs 2>/dev/null || \
gh api repos/vmunix/spawn/pages -X PUT -f source.branch=main -f source.path=/docs
```

**Step 2: Verify the site builds**

```bash
gh api repos/vmunix/spawn/pages --jq '.status'
```

Expected: `"built"` or `"building"`

**Step 3: Commit (nothing to commit — this is a repo setting)**

Push all previous commits:

```bash
git push
```

**Step 4: Verify the site is live**

Visit: `https://vmunix.github.io/spawn/`
Expected: Jekyll site with navigation and content

---

### Task 11: Final integration test

**Step 1: Run full test suite**

Run: `make test`
Expected: Lint + all tests pass

**Step 2: Verify --yolo flag is recognized**

Run: `swift run spawn --help`
Expected: `--yolo` appears in options

**Step 3: Rebuild base image with wrapper scripts**

Run: `spawn build base`
Expected: Build succeeds, wrapper scripts are installed in the image

**Step 4: Verify wrapper scripts in container**

```bash
echo 'ls -la /usr/local/bin/git /usr/local/bin/gh /usr/local/lib/spawn/' | spawn . --shell
```

Expected: Symlinks to git-guard.sh and gh-guard.sh visible

**Step 5: Commit any fixes**

If any fixes were needed, commit them with appropriate messages.
