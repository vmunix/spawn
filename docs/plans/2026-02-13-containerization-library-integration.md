# Containerization Library Integration Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add `ContainerizationOCI` as a dependency, use it for OCI reference validation in ImageResolver and pre-flight image existence checks before `container run`.

**Architecture:** Add Apple's `containerization` package as a local dependency, import only `ContainerizationOCI` (lightweight — no gRPC/VM stack). Use `Reference.parse()` for image name validation in ImageResolver. Add `ImageChecker` module that reads the `container` CLI's `state.json` file (at `~/Library/Application Support/com.apple.container/state.json`) using `ContainerizationOCI.Descriptor` as the Codable type to verify images exist before launching.

**Tech Stack:** Swift, ContainerizationOCI, swift-testing

---

### Task 1: Add `containerization` package dependency

**Files:**
- Modify: `Package.swift`

**Step 1: Bump swift-tools-version and add dependency**

In `Package.swift`, make three changes:

1. Change line 1 from `swift-tools-version: 6.1` to `swift-tools-version: 6.2`
2. Add the containerization dependency (local path for development):
3. Add `ContainerizationOCI` to the spawn target's dependencies

The full file should become:

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "spawn",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.12.0"),
        .package(path: "../containerization"),
    ],
    targets: [
        .executableTarget(
            name: "spawn",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "ContainerizationOCI", package: "containerization"),
            ],
            path: "Sources"
        ),
        .testTarget(
            name: "spawnTests",
            dependencies: [
                "spawn",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests"
        ),
    ]
)
```

**Step 2: Verify it compiles**

Run: `swift build 2>&1`
Expected: Build succeeds (will take longer on first build due to new dependencies).

**Step 3: Verify tests still pass**

Run: `swift test 2>&1`
Expected: All 47 tests pass.

**Step 4: Commit**

```bash
git add Package.swift
git commit -m "build: add ContainerizationOCI dependency from apple/containerization"
```

---

### Task 2: Use OCI Reference parsing in ImageResolver

**Files:**
- Modify: `Sources/ImageResolver.swift`
- Modify: `Tests/ImageResolverTests.swift`

**Step 1: Write failing tests for invalid references**

Add a test to `Tests/ImageResolverTests.swift` that verifies invalid image names are caught:

```swift
@Test func rejectsInvalidImageReference() {
    // OCI references cannot be bare 64-char hex strings
    let hex64 = String(repeating: "a", count: 64)
    #expect(throws: Error.self) {
        try ImageResolver.resolve(toolchain: .base, imageOverride: hex64)
    }
}

@Test func acceptsRegistryOverride() throws {
    let image = try ImageResolver.resolve(toolchain: .base, imageOverride: "ghcr.io/myorg/myimage:v1")
    #expect(image == "ghcr.io/myorg/myimage:v1")
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ImageResolver 2>&1`
Expected: Compilation error — `resolve` doesn't throw.

**Step 3: Update ImageResolver to use Reference.parse()**

Change `Sources/ImageResolver.swift` to:

```swift
import ContainerizationOCI

enum ImageResolver {
    static func resolve(toolchain: Toolchain, imageOverride: String?) throws -> String {
        let name = imageOverride ?? "spawn-\(toolchain.rawValue):latest"
        // Validate the image reference is well-formed OCI
        let _ = try Reference.parse(name)
        return name
    }
}
```

**Step 4: Update existing tests to use `try`**

Update `Tests/ImageResolverTests.swift`. The full file:

```swift
import Testing
@testable import spawn

@Test func resolvesImageFromToolchain() throws {
    let image = try ImageResolver.resolve(toolchain: .rust, imageOverride: nil)
    #expect(image == "spawn-rust:latest")
}

@Test func resolvesBaseImage() throws {
    let image = try ImageResolver.resolve(toolchain: .base, imageOverride: nil)
    #expect(image == "spawn-base:latest")
}

@Test func overrideWins() throws {
    let image = try ImageResolver.resolve(toolchain: .rust, imageOverride: "my-custom:v1")
    #expect(image == "my-custom:v1")
}

@Test func cppImage() throws {
    let image = try ImageResolver.resolve(toolchain: .cpp, imageOverride: nil)
    #expect(image == "spawn-cpp:latest")
}

@Test func rejectsInvalidImageReference() {
    let hex64 = String(repeating: "a", count: 64)
    #expect(throws: Error.self) {
        try ImageResolver.resolve(toolchain: .base, imageOverride: hex64)
    }
}

@Test func acceptsRegistryOverride() throws {
    let image = try ImageResolver.resolve(toolchain: .base, imageOverride: "ghcr.io/myorg/myimage:v1")
    #expect(image == "ghcr.io/myorg/myimage:v1")
}
```

**Step 5: Update RunCommand callsite to use `try`**

In `Sources/RunCommand.swift`, change line 70-73 from:

```swift
let resolvedImage = ImageResolver.resolve(
    toolchain: resolvedToolchain,
    imageOverride: image
)
```

to:

```swift
let resolvedImage = try ImageResolver.resolve(
    toolchain: resolvedToolchain,
    imageOverride: image
)
```

**Step 6: Update IntegrationTests if they call ImageResolver**

Check `Tests/IntegrationTests.swift` — if it calls `ImageResolver.resolve()`, add `try`.

**Step 7: Run all tests**

Run: `swift test 2>&1`
Expected: All tests pass (47 existing + 2 new = 49).

**Step 8: Commit**

```bash
git add Sources/ImageResolver.swift Tests/ImageResolverTests.swift Sources/RunCommand.swift
git commit -m "feat: validate image references using ContainerizationOCI"
```

---

### Task 3: Add ImageChecker for pre-flight image validation

**Files:**
- Create: `Sources/ImageChecker.swift`
- Create: `Tests/ImageCheckerTests.swift`

**Step 1: Write failing tests**

Create `Tests/ImageCheckerTests.swift`:

```swift
import Testing
import Foundation
@testable import spawn

@Test func findsExistingImage() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "digest": "sha256:abc123",
                "size": 375
            }
        }
        """
    ])
    let exists = ImageChecker.imageExists("spawn-base:latest", storeRoot: dir)
    #expect(exists == true)
}

@Test func returnsFalseForMissingImage() throws {
    let dir = try makeTempDir(files: [
        "state.json": """
        {
            "spawn-base:latest": {
                "mediaType": "application/vnd.oci.image.index.v1+json",
                "digest": "sha256:abc123",
                "size": 375
            }
        }
        """
    ])
    let exists = ImageChecker.imageExists("spawn-rust:latest", storeRoot: dir)
    #expect(exists == false)
}

@Test func returnsFalseWhenNoStateFile() throws {
    let dir = try makeTempDir(files: [:])
    let exists = ImageChecker.imageExists("spawn-base:latest", storeRoot: dir)
    #expect(exists == false)
}

@Test func returnsFalseForCorruptStateFile() throws {
    let dir = try makeTempDir(files: [
        "state.json": "not json"
    ])
    let exists = ImageChecker.imageExists("spawn-base:latest", storeRoot: dir)
    #expect(exists == false)
}
```

**Step 2: Run tests to verify they fail**

Run: `swift test --filter ImageChecker 2>&1`
Expected: Compilation error — `ImageChecker` not defined.

**Step 3: Write ImageChecker implementation**

Create `Sources/ImageChecker.swift`:

```swift
import ContainerizationOCI
import Foundation

enum ImageChecker {
    /// Root of the container CLI's application data.
    /// The `container` CLI stores image state at:
    ///   ~/Library/Application Support/com.apple.container/state.json
    static let defaultStoreRoot: URL = {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("com.apple.container")
    }()

    /// Check whether an image reference exists in the container CLI's image store.
    /// Returns false if the store can't be read (best-effort check).
    static func imageExists(_ reference: String, storeRoot: URL? = nil) -> Bool {
        let root = storeRoot ?? defaultStoreRoot
        let statePath = root.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: statePath),
              let state = try? JSONDecoder().decode([String: Descriptor].self, from: data) else {
            return false
        }
        return state[reference] != nil
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ImageChecker 2>&1`
Expected: All 4 tests pass.

**Step 5: Commit**

```bash
git add Sources/ImageChecker.swift Tests/ImageCheckerTests.swift
git commit -m "feat: add ImageChecker for pre-flight image validation"
```

---

### Task 4: Wire ImageChecker into RunCommand

**Files:**
- Modify: `Sources/RunCommand.swift:69-73`

**Step 1: Run existing tests to confirm green baseline**

Run: `swift test 2>&1`
Expected: All pass.

**Step 2: Add pre-flight check after image resolution**

In `Sources/RunCommand.swift`, after the `// Resolve image` block (after line 73), add:

```swift
            // Pre-flight: check if image exists locally
            if !ImageChecker.imageExists(resolvedImage) {
                // Extract toolchain name for the hint
                let buildHint = image != nil
                    ? "Pull or build the image first."
                    : "Run 'spawn build \(resolvedToolchain.rawValue)' first."
                throw ValidationError("Image '\(resolvedImage)' not found. \(buildHint)")
            }
```

**Step 3: Run tests**

Run: `swift test 2>&1`
Expected: All tests pass. The pre-flight check uses the real image store path by default. In CI or environments without the container CLI, the check returns false — but existing tests don't exercise RunCommand.run() directly (they test the pure functions).

Note: The integration tests in `IntegrationTests.swift` test the full pipeline argument construction, not actual container execution. Verify they still pass.

**Step 4: Commit**

```bash
git add Sources/RunCommand.swift
git commit -m "feat: check image exists before launching container"
```

---

### Task 5: Update CLAUDE.md with migration notes and module reference

**Files:**
- Modify: `CLAUDE.md`

**Step 1: Add Migration Path section and update module table**

Add a `## Migration Path` section after the Module Reference table:

```markdown
## Migration Path

spawn is gradually migrating from shelling out to Apple's `container` CLI toward using the `containerization` Swift library directly.

- **Current state:** `ContainerizationOCI` used for image reference validation and pre-flight image checks.
- **Seam:** `ContainerRunner` is the boundary where all `container` CLI interaction happens. Future library integration replaces its internals without changing callers.
- **Domain types:** spawn's `Mount`, `Toolchain`, etc. remain the domain model. Adapt to library types at the boundary only.
- **Next steps:** Add `Containerization` module to replace `container run` (VM lifecycle, VirtioFS, process I/O).
```

Add `ImageChecker.swift` and update `ImageResolver.swift` in the Module Reference table:

| Module | Responsibility |
|--------|---------------|
| `ImageResolver.swift` | `Toolchain` → `"spawn-{toolchain}:latest"`, with override support, validates via OCI Reference |
| `ImageChecker.swift` | Pre-flight image existence check against container CLI's image store |

**Step 2: Run full test suite**

Run: `swift test 2>&1`
Expected: All tests pass.

**Step 3: Commit**

```bash
git add CLAUDE.md
git commit -m "docs: add migration path notes and update module reference"
```
