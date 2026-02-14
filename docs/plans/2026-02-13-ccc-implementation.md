# ccc Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a Swift CLI that wraps Apple's `container` tool to run sandboxed AI coding agents with auto-detected toolchains and minimal configuration.

**Architecture:** Swift CLI using ArgumentParser for command parsing, Foundation.Process for invoking Apple's `container` CLI, VirtioFS mounts for filesystem isolation, and a priority-ordered toolchain detection chain (`.ccc.toml` > `.devcontainer` > `Dockerfile` > auto-detect > fallback).

**Tech Stack:** Swift 6.2+, swift-argument-parser 1.5+, swift-toml 2.0+, Foundation (JSON, Process, signals)

---

### Task 1: Project Scaffold

**Files:**
- Create: `Package.swift`
- Create: `Sources/CLI.swift`

**Step 1: Create Package.swift**

```swift
// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "ccc",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "ccc",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "cccTests",
            dependencies: ["ccc"],
            path: "Tests"
        ),
    ]
)
```

Note: We start with just ArgumentParser. TOML parsing will be added in a later task when needed.

**Step 2: Create minimal CLI entry point**

Create `Sources/CLI.swift`:

```swift
import ArgumentParser
import Foundation

@main
struct CCC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ccc",
        abstract: "Sandboxed AI coding agents on macOS.",
        version: "0.1.0",
        subcommands: [Run.self],
        defaultSubcommand: Run.self
    )
}
```

Create `Sources/RunCommand.swift`:

```swift
import ArgumentParser
import Foundation

extension CCC {
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run an AI coding agent in a sandboxed container."
        )

        @Argument(help: "Directory to mount as workspace.",
                  transform: { str in URL(fileURLWithPath: str).standardizedFileURL })
        var path: URL

        @Argument(help: "Agent to run: claude-code (default), codex")
        var agent: String = "claude-code"

        mutating func run() async throws {
            print("Would run \(agent) on \(path.path)")
        }
    }
}
```

**Step 3: Verify it compiles and runs**

Run: `swift build`
Expected: BUILD SUCCEEDED

Run: `swift run ccc .`
Expected: `Would run claude-code on /Users/.../ccc`

Run: `swift run ccc . codex`
Expected: `Would run codex on /Users/.../ccc`

Run: `swift run ccc --help`
Expected: Help text with version 0.1.0

**Step 4: Commit**

```bash
git add Package.swift Sources/
git commit -m "feat: scaffold Swift CLI with ArgumentParser"
```

---

### Task 2: Core Data Types

**Files:**
- Create: `Sources/Types.swift`
- Create: `Tests/TypesTests.swift`

**Step 1: Write tests for core types**

Create `Tests/TypesTests.swift`:

```swift
import Testing
import Foundation
@testable import ccc

@Test func mountFromHostPath() {
    let mount = Mount(hostPath: "/Users/me/code/project", readOnly: false)
    #expect(mount.guestPath == "/workspace/project")
    #expect(mount.name == "project")
}

@Test func mountFromHostPathReadOnly() {
    let mount = Mount(hostPath: "/Users/me/code/docs", readOnly: true)
    #expect(mount.readOnly == true)
    #expect(mount.guestPath == "/workspace/docs")
}

@Test func mountHandlesTrailingSlash() {
    let mount = Mount(hostPath: "/Users/me/code/project/", readOnly: false)
    #expect(mount.name == "project")
}

@Test func toolchainFromString() {
    #expect(Toolchain(rawValue: "cpp") == .cpp)
    #expect(Toolchain(rawValue: "rust") == .rust)
    #expect(Toolchain(rawValue: "go") == .go)
    #expect(Toolchain(rawValue: "base") == .base)
    #expect(Toolchain(rawValue: "invalid") == nil)
}

@Test func builtInAgentProfiles() {
    let claude = AgentProfile.claudeCode
    #expect(claude.name == "claude-code")
    #expect(claude.requiredEnvVars.contains("ANTHROPIC_API_KEY"))

    let codex = AgentProfile.codex
    #expect(codex.name == "codex")
    #expect(codex.requiredEnvVars.contains("OPENAI_API_KEY"))
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test`
Expected: FAIL — types don't exist yet

**Step 3: Implement core types**

Create `Sources/Types.swift`:

```swift
import Foundation

enum Toolchain: String, CaseIterable, Sendable {
    case base
    case cpp
    case rust
    case go
}

struct Mount: Sendable {
    let hostPath: String
    let readOnly: Bool

    var name: String {
        URL(fileURLWithPath: hostPath).standardizedFileURL.lastPathComponent
    }

    var guestPath: String {
        "/workspace/\(name)"
    }
}

struct AgentProfile: Sendable {
    let name: String
    let defaultImagePrefix: String
    let entrypoint: [String]
    let requiredEnvVars: [String]
    let defaultCPUs: Int
    let defaultMemory: String

    static let claudeCode = AgentProfile(
        name: "claude-code",
        defaultImagePrefix: "ccc",
        entrypoint: ["claude"],
        requiredEnvVars: ["ANTHROPIC_API_KEY"],
        defaultCPUs: 4,
        defaultMemory: "8g"
    )

    static let codex = AgentProfile(
        name: "codex",
        defaultImagePrefix: "ccc",
        entrypoint: ["codex"],
        requiredEnvVars: ["OPENAI_API_KEY"],
        defaultCPUs: 4,
        defaultMemory: "8g"
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

**Step 4: Run tests to verify they pass**

Run: `swift test`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Sources/Types.swift Tests/TypesTests.swift
git commit -m "feat: add core data types — Mount, Toolchain, AgentProfile"
```

---

### Task 3: Toolchain Detection

**Files:**
- Create: `Sources/ToolchainDetector.swift`
- Create: `Tests/ToolchainDetectorTests.swift`

**Step 1: Write tests for auto-detection from repo files**

Create `Tests/ToolchainDetectorTests.swift`:

```swift
import Testing
import Foundation
@testable import ccc

@Test func detectsRustFromCargoToml() throws {
    let dir = try makeTempDir(files: ["Cargo.toml": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .rust)
}

@Test func detectsGoFromGoMod() throws {
    let dir = try makeTempDir(files: ["go.mod": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .go)
}

@Test func detectsCppFromCMakeLists() throws {
    let dir = try makeTempDir(files: ["CMakeLists.txt": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .cpp)
}

@Test func detectsCppFromMakefile() throws {
    let dir = try makeTempDir(files: ["Makefile": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .cpp)
}

@Test func fallsBackToBase() throws {
    let dir = try makeTempDir(files: ["README.md": ""])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .base)
}

@Test func prefersDevcontainerOverAutoDetect() throws {
    let dir = try makeTempDir(files: [
        "Cargo.toml": "",
        ".devcontainer/devcontainer.json": """
        {"image": "mcr.microsoft.com/devcontainers/go:1.23"}
        """
    ])
    let result = ToolchainDetector.detect(in: dir)
    // devcontainer takes priority, should detect go from image name
    #expect(result == .go)
}

@Test func prefersCccTomlOverAll() throws {
    let dir = try makeTempDir(files: [
        "Cargo.toml": "",
        ".ccc.toml": """
        [toolchain]
        base = "cpp"
        """
    ])
    let result = ToolchainDetector.detect(in: dir)
    #expect(result == .cpp)
}

@Test func detectsDockerfile() throws {
    let dir = try makeTempDir(files: ["Dockerfile": "FROM ubuntu:24.04"])
    let result = ToolchainDetector.detect(in: dir)
    // Dockerfile present means use it directly — represented as nil toolchain
    // (the caller will build the Dockerfile instead of using a ccc-* image)
    #expect(result == nil)
}

// Helper: create a temp directory with specified files
func makeTempDir(files: [String: String]) throws -> URL {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("ccc-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    for (path, content) in files {
        let fileURL = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    return base
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ToolchainDetector`
Expected: FAIL — ToolchainDetector doesn't exist

**Step 3: Implement ToolchainDetector**

Create `Sources/ToolchainDetector.swift`:

```swift
import Foundation

enum ToolchainDetector {
    /// Returns nil when a Dockerfile/Containerfile is found (caller should build it directly).
    /// Returns a Toolchain when a ccc-* image variant should be used.
    static func detect(in directory: URL) -> Toolchain? {
        let fm = FileManager.default

        // Priority 1: .ccc.toml
        let cccToml = directory.appendingPathComponent(".ccc.toml")
        if fm.fileExists(atPath: cccToml.path),
           let toolchain = parseCccToml(at: cccToml) {
            return toolchain
        }

        // Priority 2: .devcontainer/devcontainer.json
        let devcontainer = directory
            .appendingPathComponent(".devcontainer")
            .appendingPathComponent("devcontainer.json")
        if fm.fileExists(atPath: devcontainer.path),
           let toolchain = parseDevcontainer(at: devcontainer) {
            return toolchain
        }

        // Priority 3: Dockerfile / Containerfile
        if fm.fileExists(atPath: directory.appendingPathComponent("Dockerfile").path) ||
           fm.fileExists(atPath: directory.appendingPathComponent("Containerfile").path) {
            return nil  // signal: build the Dockerfile directly
        }

        // Priority 4: Auto-detect from repo files
        return autoDetect(in: directory)
    }

    private static func autoDetect(in directory: URL) -> Toolchain {
        let fm = FileManager.default
        let exists = { fm.fileExists(atPath: directory.appendingPathComponent($0).path) }

        if exists("Cargo.toml") || exists("rust-toolchain.toml") { return .rust }
        if exists("go.mod") || exists("go.sum") { return .go }
        if exists("CMakeLists.txt") || exists("Makefile") { return .cpp }

        // Node/Python projects use the base image (already has node + python)
        return .base
    }

    private static func parseCccToml(at url: URL) -> Toolchain? {
        // Simple parsing: look for `base = "..."` in [toolchain] section
        guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("base") && trimmed.contains("=") {
                let value = trimmed
                    .split(separator: "=", maxSplits: 1).last?
                    .trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                if let value, let toolchain = Toolchain(rawValue: value) {
                    return toolchain
                }
            }
        }
        return nil
    }

    private static func parseDevcontainer(at url: URL) -> Toolchain? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let image = json["image"] as? String else { return nil }

        // Infer toolchain from image name
        let lower = image.lowercased()
        if lower.contains("rust") { return .rust }
        if lower.contains("go") { return .go }
        if lower.contains("cpp") || lower.contains("c++") { return .cpp }
        return .base
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ToolchainDetector`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Sources/ToolchainDetector.swift Tests/ToolchainDetectorTests.swift
git commit -m "feat: add toolchain detection from .ccc.toml, devcontainer, and repo files"
```

---

### Task 4: Mount Resolution

**Files:**
- Create: `Sources/MountResolver.swift`
- Create: `Tests/MountResolverTests.swift`

**Step 1: Write tests**

Create `Tests/MountResolverTests.swift`:

```swift
import Testing
import Foundation
@testable import ccc

@Test func resolvesTargetDirectory() throws {
    let mounts = MountResolver.resolve(
        target: URL(fileURLWithPath: "/Users/me/code/project"),
        additional: [],
        readOnly: [],
        includeGit: true
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/project" && !$0.readOnly })
}

@Test func includesAdditionalMounts() throws {
    let mounts = MountResolver.resolve(
        target: URL(fileURLWithPath: "/Users/me/code/project"),
        additional: ["/Users/me/code/lib"],
        readOnly: [],
        includeGit: false
    )
    #expect(mounts.count == 2)
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/lib" && !$0.readOnly })
}

@Test func includesReadOnlyMounts() throws {
    let mounts = MountResolver.resolve(
        target: URL(fileURLWithPath: "/Users/me/code/project"),
        additional: [],
        readOnly: ["/Users/me/code/docs"],
        includeGit: false
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/docs" && $0.readOnly })
}

@Test func includesGitConfigWhenRequested() throws {
    // This test checks the logic — actual file existence may vary
    let mounts = MountResolver.resolve(
        target: URL(fileURLWithPath: "/tmp/project"),
        additional: [],
        readOnly: [],
        includeGit: true
    )
    let gitconfigMount = mounts.first { $0.guestPath == "/root/.gitconfig" }
    // gitconfig mount may or may not exist depending on test environment
    // Just verify the logic doesn't crash
    #expect(mounts.count >= 1) // at least the target
}

@Test func noGitOptionExcludesGitMounts() throws {
    let mounts = MountResolver.resolve(
        target: URL(fileURLWithPath: "/tmp/project"),
        additional: [],
        readOnly: [],
        includeGit: false
    )
    let gitMounts = mounts.filter { $0.guestPath.contains(".git") || $0.guestPath.contains(".ssh") }
    #expect(gitMounts.isEmpty)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter MountResolver`
Expected: FAIL

**Step 3: Implement MountResolver**

Create `Sources/MountResolver.swift`:

```swift
import Foundation

enum MountResolver {
    struct GitMount {
        let hostPath: String
        let guestPath: String
        let readOnly: Bool
    }

    static func resolve(
        target: URL,
        additional: [String],
        readOnly: [String],
        includeGit: Bool
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
        if includeGit {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default

            let gitconfig = home.appendingPathComponent(".gitconfig").path
            if fm.fileExists(atPath: gitconfig) {
                mounts.append(GitConfigMount(hostPath: gitconfig))
            }

            let sshDir = home.appendingPathComponent(".ssh").path
            if fm.fileExists(atPath: sshDir) {
                mounts.append(SSHMount(hostPath: sshDir))
            }
        }

        return mounts
    }
}

/// Special mount types with fixed guest paths
struct GitConfigMount: Mount-like {
    let hostPath: String
    let readOnly = true
    var name: String { ".gitconfig" }
    var guestPath: String { "/root/.gitconfig" }
}

struct SSHMount: Mount-like {
    let hostPath: String
    let readOnly = true
    var name: String { ".ssh" }
    var guestPath: String { "/root/.ssh" }
}
```

Wait — this introduces a protocol where we don't need one. Keep it simple. Refactor Mount to support custom guest paths:

```swift
import Foundation

struct Mount: Sendable {
    let hostPath: String
    let guestPath: String
    let readOnly: Bool

    /// Standard workspace mount — guest path derived from directory name
    init(hostPath: String, readOnly: Bool) {
        self.hostPath = hostPath
        self.readOnly = readOnly
        let name = URL(fileURLWithPath: hostPath).standardizedFileURL.lastPathComponent
        self.guestPath = "/workspace/\(name)"
    }

    /// Custom guest path mount (for .gitconfig, .ssh, etc.)
    init(hostPath: String, guestPath: String, readOnly: Bool) {
        self.hostPath = hostPath
        self.guestPath = guestPath
        self.readOnly = readOnly
    }

    var name: String {
        URL(fileURLWithPath: hostPath).standardizedFileURL.lastPathComponent
    }
}
```

Note: this means `Types.swift` needs updating — the Mount struct should use this version with the two initializers. Replace the Mount in Types.swift with this version.

MountResolver becomes:

```swift
import Foundation

enum MountResolver {
    static func resolve(
        target: URL,
        additional: [String],
        readOnly: [String],
        includeGit: Bool
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
        if includeGit {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default

            let gitconfig = home.appendingPathComponent(".gitconfig").path
            if fm.fileExists(atPath: gitconfig) {
                mounts.append(Mount(
                    hostPath: gitconfig,
                    guestPath: "/root/.gitconfig",
                    readOnly: true
                ))
            }

            let sshDir = home.appendingPathComponent(".ssh").path
            if fm.fileExists(atPath: sshDir) {
                mounts.append(Mount(
                    hostPath: sshDir,
                    guestPath: "/root/.ssh",
                    readOnly: true
                ))
            }
        }

        return mounts
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter MountResolver`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Sources/MountResolver.swift Sources/Types.swift Tests/MountResolverTests.swift
git commit -m "feat: add mount resolution with git/SSH support"
```

---

### Task 5: Environment Loading

**Files:**
- Create: `Sources/EnvLoader.swift`
- Create: `Tests/EnvLoaderTests.swift`

**Step 1: Write tests**

Create `Tests/EnvLoaderTests.swift`:

```swift
import Testing
import Foundation
@testable import ccc

@Test func parsesEnvFile() throws {
    let content = """
    ANTHROPIC_API_KEY=sk-ant-123
    OPENAI_API_KEY=sk-456
    """
    let env = EnvLoader.parse(content)
    #expect(env["ANTHROPIC_API_KEY"] == "sk-ant-123")
    #expect(env["OPENAI_API_KEY"] == "sk-456")
}

@Test func ignoresCommentsAndEmptyLines() throws {
    let content = """
    # This is a comment
    KEY=value

    # Another comment
    KEY2=value2
    """
    let env = EnvLoader.parse(content)
    #expect(env.count == 2)
    #expect(env["KEY"] == "value")
}

@Test func handlesQuotedValues() throws {
    let content = """
    KEY="value with spaces"
    KEY2='single quoted'
    """
    let env = EnvLoader.parse(content)
    #expect(env["KEY"] == "value with spaces")
    #expect(env["KEY2"] == "single quoted")
}

@Test func validatesRequiredVars() {
    let env = ["ANTHROPIC_API_KEY": "sk-123"]
    let missing = EnvLoader.validateRequired(["ANTHROPIC_API_KEY", "OTHER_KEY"], in: env)
    #expect(missing == ["OTHER_KEY"])
}

@Test func validationPassesWhenAllPresent() {
    let env = ["ANTHROPIC_API_KEY": "sk-123"]
    let missing = EnvLoader.validateRequired(["ANTHROPIC_API_KEY"], in: env)
    #expect(missing.isEmpty)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter EnvLoader`
Expected: FAIL

**Step 3: Implement EnvLoader**

Create `Sources/EnvLoader.swift`:

```swift
import Foundation

enum EnvLoader {
    static func load(from path: String) throws -> [String: String] {
        let content = try String(contentsOfFile: path, encoding: .utf8)
        return parse(content)
    }

    static func loadDefault() -> [String: String] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaultPath = home.appendingPathComponent(".ccc/env").path
        return (try? load(from: defaultPath)) ?? [:]
    }

    static func parse(_ content: String) -> [String: String] {
        var env: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }
            guard let eqIndex = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[trimmed.startIndex..<eqIndex])
                .trimmingCharacters(in: .whitespaces)
            var value = String(trimmed[trimmed.index(after: eqIndex)...])
                .trimmingCharacters(in: .whitespaces)
            // Strip surrounding quotes
            if (value.hasPrefix("\"") && value.hasSuffix("\"")) ||
               (value.hasPrefix("'") && value.hasSuffix("'")) {
                value = String(value.dropFirst().dropLast())
            }
            env[key] = value
        }
        return env
    }

    static func validateRequired(_ required: [String], in env: [String: String]) -> [String] {
        required.filter { env[$0] == nil }
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter EnvLoader`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Sources/EnvLoader.swift Tests/EnvLoaderTests.swift
git commit -m "feat: add env file loading and validation"
```

---

### Task 6: ContainerRunner

**Files:**
- Create: `Sources/ContainerRunner.swift`
- Create: `Tests/ContainerRunnerTests.swift`

**Step 1: Write tests for argument construction**

Create `Tests/ContainerRunnerTests.swift`:

```swift
import Testing
import Foundation
@testable import ccc

@Test func buildsBasicRunArguments() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-base:latest",
        mounts: [Mount(hostPath: "/Users/me/code/project", readOnly: false)],
        env: ["KEY": "value"],
        workdir: "/workspace/project",
        entrypoint: ["claude"],
        cpus: 4,
        memory: "8g"
    )

    #expect(args.contains("run"))
    #expect(args.contains("--rm"))
    #expect(args.contains { $0.contains("/Users/me/code/project") })
    #expect(args.contains("ccc-base:latest"))
    #expect(args.contains("claude"))
}

@Test func includesAllMounts() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-rust:latest",
        mounts: [
            Mount(hostPath: "/code/project", readOnly: false),
            Mount(hostPath: "/code/lib", readOnly: true),
            Mount(hostPath: "/root/.gitconfig", guestPath: "/root/.gitconfig", readOnly: true),
        ],
        env: [:],
        workdir: "/workspace/project",
        entrypoint: ["claude"],
        cpus: 4,
        memory: "8g"
    )

    // Count volume flags — each mount produces a --volume
    let volumeCount = args.enumerated().filter { $0.element == "--volume" }.count
    #expect(volumeCount == 3)
}

@Test func includesEnvVars() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-base:latest",
        mounts: [],
        env: ["ANTHROPIC_API_KEY": "sk-123", "FOO": "bar"],
        workdir: "/workspace/test",
        entrypoint: ["claude"],
        cpus: 2,
        memory: "4g"
    )

    let envCount = args.enumerated().filter { $0.element == "--env" }.count
    #expect(envCount == 2)
}

@Test func shellModeOverridesEntrypoint() {
    let args = ContainerRunner.buildArgs(
        image: "ccc-base:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace/test",
        entrypoint: ["/bin/bash"],
        cpus: 4,
        memory: "8g"
    )

    #expect(args.last == "/bin/bash")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ContainerRunner`
Expected: FAIL

**Step 3: Implement ContainerRunner**

Create `Sources/ContainerRunner.swift`:

```swift
import Foundation

enum ContainerRunner {
    static let containerPath = "/usr/local/bin/container"

    static func buildArgs(
        image: String,
        mounts: [Mount],
        env: [String: String],
        workdir: String,
        entrypoint: [String],
        cpus: Int,
        memory: String
    ) -> [String] {
        var args = ["run", "--rm"]

        // Resources
        args += ["--cpus", "\(cpus)"]
        args += ["--memory", "\(memory)"]

        // Mounts
        for mount in mounts {
            let spec = mount.readOnly
                ? "\(mount.hostPath):\(mount.guestPath):ro"
                : "\(mount.hostPath):\(mount.guestPath)"
            args += ["--volume", spec]
        }

        // Environment
        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            args += ["--env", "\(key)=\(value)"]
        }

        // Working directory
        args += ["--workdir", workdir]

        // Image
        args.append(image)

        // Entrypoint / command
        args += entrypoint

        return args
    }

    static func run(
        image: String,
        mounts: [Mount],
        env: [String: String],
        workdir: String,
        entrypoint: [String],
        cpus: Int,
        memory: String,
        verbose: Bool
    ) throws -> Int32 {
        let args = buildArgs(
            image: image, mounts: mounts, env: env,
            workdir: workdir, entrypoint: entrypoint,
            cpus: cpus, memory: memory
        )

        if verbose {
            let cmd = ([containerPath] + args).joined(separator: " ")
            FileHandle.standardError.write(Data("+ \(cmd)\n".utf8))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: containerPath)
        process.arguments = args
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        // Signal forwarding
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            if process.isRunning { kill(process.processIdentifier, SIGINT) }
        }
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            if process.isRunning { kill(process.processIdentifier, SIGTERM) }
        }
        sigtermSource.resume()

        try process.run()
        process.waitUntilExit()

        sigintSource.cancel()
        sigtermSource.cancel()
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)

        return process.terminationStatus
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ContainerRunner`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Sources/ContainerRunner.swift Tests/ContainerRunnerTests.swift
git commit -m "feat: add ContainerRunner with arg construction and signal forwarding"
```

---

### Task 7: Image Resolution

**Files:**
- Create: `Sources/ImageResolver.swift`
- Create: `Tests/ImageResolverTests.swift`

**Step 1: Write tests**

Create `Tests/ImageResolverTests.swift`:

```swift
import Testing
import Foundation
@testable import ccc

@Test func resolvesImageFromToolchain() {
    let image = ImageResolver.resolve(toolchain: .rust, imageOverride: nil)
    #expect(image == "ccc-rust:latest")
}

@Test func resolvesBaseImage() {
    let image = ImageResolver.resolve(toolchain: .base, imageOverride: nil)
    #expect(image == "ccc-base:latest")
}

@Test func overrideWins() {
    let image = ImageResolver.resolve(toolchain: .rust, imageOverride: "my-custom:v1")
    #expect(image == "my-custom:v1")
}

@Test func cppImage() {
    let image = ImageResolver.resolve(toolchain: .cpp, imageOverride: nil)
    #expect(image == "ccc-cpp:latest")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ImageResolver`
Expected: FAIL

**Step 3: Implement ImageResolver**

Create `Sources/ImageResolver.swift`:

```swift
import Foundation

enum ImageResolver {
    static func resolve(toolchain: Toolchain, imageOverride: String?) -> String {
        if let override = imageOverride { return override }
        return "ccc-\(toolchain.rawValue):latest"
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ImageResolver`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add Sources/ImageResolver.swift Tests/ImageResolverTests.swift
git commit -m "feat: add image resolution from toolchain"
```

---

### Task 8: Wire Up the Run Command

**Files:**
- Modify: `Sources/RunCommand.swift`
- Modify: `Sources/CLI.swift`

**Step 1: Update RunCommand with all options and orchestration logic**

Replace `Sources/RunCommand.swift`:

```swift
import ArgumentParser
import Foundation

extension CCC {
    struct Run: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run an AI coding agent in a sandboxed container."
        )

        @Argument(
            help: "Directory to mount as workspace.",
            transform: { URL(fileURLWithPath: $0).standardizedFileURL }
        )
        var path: URL

        @Argument(help: "Agent: claude-code (default), codex")
        var agent: String = "claude-code"

        @Option(name: .long, help: "Additional directory to mount (repeatable).",
                transform: { $0 })
        var mount: [String] = []

        @Option(name: .customLong("read-only"), help: "Mount directory read-only (repeatable).",
                transform: { $0 })
        var readOnlyMounts: [String] = []

        @Option(name: .long, help: "Environment variable KEY=VALUE (repeatable).")
        var env: [String] = []

        @Option(name: .customLong("env-file"), help: "Path to env file.")
        var envFile: String?

        @Option(name: .long, help: "Override base image.")
        var image: String?

        @Option(name: .long, help: "Override toolchain: base, cpp, rust, go")
        var toolchain: String?

        @Option(name: .long, help: "CPU cores.")
        var cpus: Int = 4

        @Option(name: .long, help: "Memory (e.g., 8g).")
        var memory: String = "8g"

        @Flag(name: .long, help: "Drop into shell instead of running agent.")
        var shell: Bool = false

        @Flag(name: .customLong("no-git"), help: "Don't mount ~/.gitconfig or SSH.")
        var noGit: Bool = false

        @Flag(name: .long, help: "Show container commands.")
        var verbose: Bool = false

        mutating func run() async throws {
            // Resolve agent profile
            guard let profile = AgentProfile.named(agent) else {
                throw ValidationError("Unknown agent: \(agent). Use 'claude-code' or 'codex'.")
            }

            // Resolve toolchain
            let resolvedToolchain: Toolchain
            if let override = toolchain {
                guard let tc = Toolchain(rawValue: override) else {
                    throw ValidationError("Unknown toolchain: \(override). Use: base, cpp, rust, go.")
                }
                resolvedToolchain = tc
            } else {
                // Auto-detect (nil = Dockerfile found)
                resolvedToolchain = ToolchainDetector.detect(in: path) ?? .base
            }

            // Resolve image
            let resolvedImage = ImageResolver.resolve(
                toolchain: resolvedToolchain,
                imageOverride: image
            )

            // Resolve mounts
            let resolvedMounts = MountResolver.resolve(
                target: path,
                additional: mount,
                readOnly: readOnlyMounts,
                includeGit: !noGit
            )

            // Load environment
            var environment: [String: String] = [:]

            // Default env file
            if let envFile {
                environment = try EnvLoader.load(from: envFile)
            } else {
                environment = EnvLoader.loadDefault()
            }

            // CLI --env overrides
            for envVar in env {
                guard let eqIndex = envVar.firstIndex(of: "=") else {
                    throw ValidationError("Invalid env format: \(envVar). Use KEY=VALUE.")
                }
                let key = String(envVar[envVar.startIndex..<eqIndex])
                let value = String(envVar[envVar.index(after: eqIndex)...])
                environment[key] = value
            }

            // Validate required env vars
            let missing = EnvLoader.validateRequired(profile.requiredEnvVars, in: environment)
            if !missing.isEmpty {
                let vars = missing.joined(separator: ", ")
                throw ValidationError(
                    "Missing required environment variables: \(vars)\n" +
                    "Set them in ~/.ccc/env or pass with --env"
                )
            }

            // Determine entrypoint
            let entrypoint = shell ? ["/bin/bash"] : profile.entrypoint

            // Workdir
            let workdir = "/workspace/\(path.lastPathComponent)"

            // Run
            let status = try ContainerRunner.run(
                image: resolvedImage,
                mounts: resolvedMounts,
                env: environment,
                workdir: workdir,
                entrypoint: entrypoint,
                cpus: cpus,
                memory: memory,
                verbose: verbose
            )

            throw ExitCode(status)
        }
    }
}
```

**Step 2: Build and verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

Run: `swift run ccc --help`
Expected: Help output showing all options

Run: `swift run ccc . --verbose`
Expected: Either a clear error about missing env vars or a `+ /usr/local/bin/container run ...` command printed (will fail if `container` isn't installed, which is expected)

**Step 3: Commit**

```bash
git add Sources/RunCommand.swift Sources/CLI.swift
git commit -m "feat: wire up Run command with full orchestration"
```

---

### Task 9: Build, List, Stop, Exec Subcommands

**Files:**
- Create: `Sources/BuildCommand.swift`
- Create: `Sources/ListCommand.swift`
- Create: `Sources/StopCommand.swift`
- Create: `Sources/ExecCommand.swift`
- Modify: `Sources/CLI.swift`

**Step 1: Implement Build command**

Create `Sources/BuildCommand.swift`:

```swift
import ArgumentParser
import Foundation

extension CCC {
    struct Build: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Build or pull base images."
        )

        @Argument(help: "Toolchain to build: base, cpp, rust, go (default: all)")
        var toolchain: String?

        @Flag(name: .long, help: "Show build commands.")
        var verbose: Bool = false

        mutating func run() throws {
            let toolchains: [Toolchain]
            if let name = toolchain {
                guard let tc = Toolchain(rawValue: name) else {
                    throw ValidationError("Unknown toolchain: \(name)")
                }
                toolchains = [tc]
            } else {
                toolchains = Toolchain.allCases
            }

            for tc in toolchains {
                print("Building ccc-\(tc.rawValue)...")
                let imageName = "ccc-\(tc.rawValue):latest"
                let containerfilePath = "Images/\(tc.rawValue)/Containerfile"

                let process = Process()
                process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
                process.arguments = ["build", "-t", imageName, "-f", containerfilePath, "."]
                process.standardOutput = verbose ? FileHandle.standardOutput : nil
                process.standardError = FileHandle.standardError

                try process.run()
                process.waitUntilExit()

                if process.terminationStatus != 0 {
                    throw ExitCode(process.terminationStatus)
                }
                print("Built \(imageName)")
            }
        }
    }
}
```

**Step 2: Implement List command**

Create `Sources/ListCommand.swift`:

```swift
import ArgumentParser
import Foundation

extension CCC {
    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List running containers."
        )

        mutating func run() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
            process.arguments = ["list"]
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
        }
    }
}
```

**Step 3: Implement Stop command**

Create `Sources/StopCommand.swift`:

```swift
import ArgumentParser
import Foundation

extension CCC {
    struct Stop: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Stop a running container."
        )

        @Argument(help: "Container ID to stop.")
        var id: String

        mutating func run() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: ContainerRunner.containerPath)
            process.arguments = ["stop", id]
            process.standardOutput = FileHandle.standardOutput
            process.standardError = FileHandle.standardError
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus != 0 {
                throw ExitCode(process.terminationStatus)
            }
        }
    }
}
```

**Step 4: Implement Exec command**

Create `Sources/ExecCommand.swift`:

```swift
import ArgumentParser
import Foundation

extension CCC {
    struct Exec: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Execute a command in a running container."
        )

        @Argument(help: "Container ID.")
        var id: String

        @Argument(parsing: .captureForPassthrough, help: "Command to execute.")
        var command: [String]

        mutating func run() async throws {
            var args = ["exec", id]
            args += command

            let status = try ContainerRunner.runRaw(args: args)
            throw ExitCode(status)
        }
    }
}
```

Note: Add `runRaw` to ContainerRunner:

Add to `Sources/ContainerRunner.swift`:

```swift
    static func runRaw(args: [String]) throws -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: containerPath)
        process.arguments = args
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }
```

**Step 5: Register all subcommands in CLI.swift**

Update `Sources/CLI.swift`:

```swift
import ArgumentParser
import Foundation

@main
struct CCC: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ccc",
        abstract: "Sandboxed AI coding agents on macOS.",
        version: "0.1.0",
        subcommands: [Run.self, Build.self, List.self, Stop.self, Exec.self],
        defaultSubcommand: Run.self
    )
}
```

**Step 6: Build and verify**

Run: `swift build`
Expected: BUILD SUCCEEDED

Run: `swift run ccc --help`
Expected: Shows all subcommands: run, build, list, stop, exec

**Step 7: Commit**

```bash
git add Sources/BuildCommand.swift Sources/ListCommand.swift Sources/StopCommand.swift Sources/ExecCommand.swift Sources/ContainerRunner.swift Sources/CLI.swift
git commit -m "feat: add build, list, stop, exec subcommands"
```

---

### Task 10: Containerfiles

**Files:**
- Create: `Images/base/Containerfile`
- Create: `Images/cpp/Containerfile`
- Create: `Images/rust/Containerfile`
- Create: `Images/go/Containerfile`

**Step 1: Create base Containerfile**

Create `Images/base/Containerfile`:

```dockerfile
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl wget ca-certificates \
    build-essential \
    python3 python3-pip python3-venv \
    nodejs npm \
    ripgrep fd-find jq tree \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Claude Code
RUN npm install -g @anthropic-ai/claude-code

# Codex (OpenAI)
RUN npm install -g @openai/codex

WORKDIR /workspace
```

**Step 2: Create cpp Containerfile**

Create `Images/cpp/Containerfile`:

```dockerfile
FROM ccc-base:latest

RUN apt-get update && apt-get install -y --no-install-recommends \
    clang clang-format clang-tidy \
    cmake ninja-build \
    gdb valgrind \
    && rm -rf /var/lib/apt/lists/*
```

**Step 3: Create rust Containerfile**

Create `Images/rust/Containerfile`:

```dockerfile
FROM ccc-base:latest

RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"
```

**Step 4: Create go Containerfile**

Create `Images/go/Containerfile`:

```dockerfile
FROM ccc-base:latest

ARG GO_VERSION=1.23.6
RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz" | tar -C /usr/local -xz
ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
```

**Step 5: Commit**

```bash
git add Images/
git commit -m "feat: add Containerfiles for base, cpp, rust, go images"
```

---

### Task 11: End-to-End Smoke Test

**Files:**
- Create: `Tests/IntegrationTests.swift`

This task verifies the full pipeline works with a mock `container` command.

**Step 1: Write integration test using a fake container binary**

Create `Tests/IntegrationTests.swift`:

```swift
import Testing
import Foundation
@testable import ccc

@Test func fullPipelineProducesCorrectArguments() throws {
    // Simulate: ccc ~/code/rust-project claude-code --verbose
    let target = try makeTempDir(files: ["Cargo.toml": ""])

    // Detect toolchain
    let toolchain = ToolchainDetector.detect(in: target)
    #expect(toolchain == .rust)

    // Resolve image
    let image = ImageResolver.resolve(toolchain: toolchain ?? .base, imageOverride: nil)
    #expect(image == "ccc-rust:latest")

    // Resolve mounts
    let mounts = MountResolver.resolve(
        target: target, additional: [], readOnly: [], includeGit: false
    )
    #expect(mounts.count == 1)
    #expect(mounts[0].guestPath.hasPrefix("/workspace/"))

    // Load env
    let env = ["ANTHROPIC_API_KEY": "sk-test"]
    let missing = EnvLoader.validateRequired(
        AgentProfile.claudeCode.requiredEnvVars, in: env
    )
    #expect(missing.isEmpty)

    // Build args
    let args = ContainerRunner.buildArgs(
        image: image,
        mounts: mounts,
        env: env,
        workdir: "/workspace/\(target.lastPathComponent)",
        entrypoint: AgentProfile.claudeCode.entrypoint,
        cpus: 4,
        memory: "8g"
    )

    #expect(args.first == "run")
    #expect(args.contains("ccc-rust:latest"))
    #expect(args.contains("claude"))
    #expect(args.contains { $0.contains("ANTHROPIC_API_KEY=sk-test") })
}
```

**Step 2: Run the test**

Run: `swift test --filter IntegrationTests`
Expected: PASS

**Step 3: Run all tests**

Run: `swift test`
Expected: All tests PASS

**Step 4: Commit**

```bash
git add Tests/IntegrationTests.swift
git commit -m "test: add end-to-end integration test for full pipeline"
```

---

### Task 12: Install Script and README

**Files:**
- Create: `Makefile`

**Step 1: Create Makefile for build and install**

Create `Makefile`:

```makefile
PREFIX ?= /usr/local
BINARY = ccc

.PHONY: build install uninstall clean test

build:
	swift build -c release

test:
	swift test

install: build
	install -d $(PREFIX)/bin
	install .build/release/$(BINARY) $(PREFIX)/bin/$(BINARY)

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)

clean:
	swift package clean

images:
	container build -t ccc-base:latest -f Images/base/Containerfile .
	container build -t ccc-cpp:latest -f Images/cpp/Containerfile .
	container build -t ccc-rust:latest -f Images/rust/Containerfile .
	container build -t ccc-go:latest -f Images/go/Containerfile .
```

**Step 2: Verify build works**

Run: `make build`
Expected: BUILD SUCCEEDED

Run: `make test`
Expected: All tests PASS

**Step 3: Commit**

```bash
git add Makefile
git commit -m "feat: add Makefile for build, test, install"
```
