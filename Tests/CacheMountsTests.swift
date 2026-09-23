import Foundation
import Testing

@testable import spawn

/// Two unrelated workspaces, used throughout to prove that scoping actually
/// separates them. They deliberately share a last path component, so a
/// slug-only derivation would collide and be caught here.
private let workspaceA = URL(fileURLWithPath: "/Users/me/code/project")
private let workspaceB = URL(fileURLWithPath: "/Users/me/other/project")

/// A fixed cache root. Never touched on disk by the naming tests: deriving a
/// cache path is pure.
private let cacheRoot = URL(fileURLWithPath: "/Users/me/.local/state/spawn/caches")

/// Build caches for a toolchain in the default (private) scope.
private func privateCaches(_ toolchain: Toolchain, in workspace: URL = workspaceA, root: URL = cacheRoot) -> [Mount] {
    CacheMounts.forToolchain(toolchain, scope: .workspace, workspace: workspace, root: root)
}

/// Build caches for a toolchain in the opt-in shared scope. The workspace is
/// still passed — and must be ignored.
private func sharedCaches(_ toolchain: Toolchain, in workspace: URL = workspaceA, root: URL = cacheRoot) -> [Mount] {
    CacheMounts.forToolchain(toolchain, scope: .shared, workspace: workspace, root: root)
}

@Test func rustGetsCargoRegistryAndGitCaches() {
    let caches = privateCaches(.rust)
    #expect(caches.contains { $0.guestPath == "/opt/rust/cargo/registry" })
    #expect(caches.contains { $0.guestPath == "/opt/rust/cargo/git" })
}

@Test func goGetsModuleCache() {
    #expect(privateCaches(.go).contains { $0.guestPath == "/opt/go/pkg/mod" })
}

@Test func jsGetsDenoAndNpmCaches() {
    let caches = privateCaches(.js)
    #expect(caches.contains { $0.guestPath == "/opt/js/deno-cache" })
    #expect(caches.contains { $0.guestPath == "/home/coder/.npm" })
}

@Test func baseHasNoCaches() {
    #expect(privateCaches(.base).isEmpty)
    #expect(sharedCaches(.base).isEmpty)
}

@Test func cppHasNoCaches() {
    #expect(privateCaches(.cpp).isEmpty)
    #expect(sharedCaches(.cpp).isEmpty)
}

@Test func cacheDirectoriesLiveUnderTheCacheRoot() {
    // Caches belong in spawn's state directory, not in the workspace and not in
    // the guest home: a path that escaped the root would be outside everything
    // that documents, inspects, or clears them.
    for scope in CacheScope.allCases {
        let caches = CacheMounts.forToolchain(.rust, scope: scope, workspace: workspaceA, root: cacheRoot)
        #expect(!caches.isEmpty)
        for cache in caches {
            #expect(cache.hostPath.hasPrefix(cacheRoot.path + "/"))
            #expect(!cache.hostPath.contains(".."))
        }
    }
}

@Test func cacheRootSitsUnderTheStateDirectory() {
    let state = URL(fileURLWithPath: "/tmp/spawn-state")
    #expect(CacheMounts.root(stateDir: state).path == "/tmp/spawn-state/caches")
}

@Test func cachesAreMountedReadWrite() {
    // A read-only cache mount would fail every fetch that tries to populate it.
    for toolchain in Toolchain.allCases {
        for scope in CacheScope.allCases {
            for cache in CacheMounts.forToolchain(toolchain, scope: scope, workspace: workspaceA, root: cacheRoot) {
                #expect(!cache.readOnly)
            }
        }
    }
    #expect(!privateCaches(.rust).isEmpty)
}

@Test func guestPathsAreTheSameWhicheverScopeIsUsed() {
    // Scope changes who may read a cache, never where it is mounted: the guest
    // paths are fixed by the toolchain templates.
    for toolchain in Toolchain.allCases {
        #expect(privateCaches(toolchain).map(\.guestPath) == sharedCaches(toolchain).map(\.guestPath))
        #expect(privateCaches(toolchain, in: workspaceB).map(\.guestPath) == sharedCaches(toolchain).map(\.guestPath))
    }
}

// MARK: - Cross-workspace isolation
//
// The security property this whole file exists for: a cache holds dependency
// sources fetched with one workspace's credentials (cargo's git cache can hold
// private repositories) and is mounted read-write, so under the default scope no
// two workspaces may ever be handed the same host directory.

@Test func twoWorkspacesNeverShareACacheDirectoryUnderTheDefaultScope() {
    var seen: Set<String> = []
    var collided = false

    for toolchain in Toolchain.allCases {
        let pathsA = privateCaches(toolchain, in: workspaceA).map(\.hostPath)
        let pathsB = privateCaches(toolchain, in: workspaceB).map(\.hostPath)

        // Vacuity guard: an empty set of paths would satisfy any disjointness
        // claim, so the toolchains that do declare caches must produce some.
        if toolchain == .rust || toolchain == .go || toolchain == .js {
            #expect(!pathsA.isEmpty)
        }
        #expect(pathsA.count == pathsB.count)
        #expect(Set(pathsA).isDisjoint(with: Set(pathsB)))

        // Nesting is sharing too: a workspace whose cache directory contained
        // another's would read and rewrite it through the parent mount.
        for left in pathsA {
            for right in pathsB {
                #expect(!left.hasPrefix(right + "/"))
                #expect(!right.hasPrefix(left + "/"))
            }
        }

        for path in pathsA + pathsB {
            collided = collided || !seen.insert(path).inserted
        }
    }

    #expect(!collided, "a cache directory is reused across workspaces or toolchains")
}

@Test func workspaceScopedPathsAreStableAcrossCalls() {
    // Stability is what makes the cache a cache: a path that changed per call
    // would start a fresh empty cache on every run.
    for toolchain in Toolchain.allCases {
        #expect(privateCaches(toolchain, in: workspaceB) == privateCaches(toolchain, in: workspaceB))
    }
    #expect(privateCaches(.rust).map(\.hostPath) == privateCaches(.rust).map(\.hostPath))
}

@Test func workspaceIdentityHasAStableKnownValueAcrossProcesses() {
    // A same-process equality check cannot catch Swift's randomized `hashValue`.
    // This value is the public FNV-1a identity contract for the canonical path.
    #expect(WorkspaceIdentity.key(for: workspaceA) == "project-1183064f02567d39")
}

@Test func workspaceScopedPathsIgnorePathSpellingDifferences() {
    // ~/code/app, ~/code/app/ and ~/code/./app are one workspace, so they must
    // reach one cache rather than quietly starting a second.
    let spellings = [
        URL(fileURLWithPath: "/Users/me/code/project"),
        URL(fileURLWithPath: "/Users/me/code/project/"),
        URL(fileURLWithPath: "/Users/me/code/./project"),
    ]
    let expected = privateCaches(.rust, in: workspaceA).map(\.hostPath)
    for spelling in spellings {
        #expect(privateCaches(.rust, in: spelling).map(\.hostPath) == expected)
    }
}

@Test func workspacesWithTheSameDirectoryNameStillGetDistinctCaches() {
    // The slug alone would collide here; the path hash is what separates them.
    let left = URL(fileURLWithPath: "/Users/me/work/api")
    let right = URL(fileURLWithPath: "/Users/me/personal/api")
    let leftPaths = Set(privateCaches(.rust, in: left).map(\.hostPath))
    let rightPaths = Set(privateCaches(.rust, in: right).map(\.hostPath))

    #expect(!leftPaths.isEmpty)
    #expect(leftPaths.isDisjoint(with: rightPaths))
}

@Test func workspaceScopedPathsCarryTheSameIdentityAsTheWorkspaceImage() {
    // Reuse, not reimplementation: the cache key must be the key that names the
    // workspace runtime image, so both agree on what "this workspace" is.
    let key = WorkspaceIdentity.key(for: workspaceB.standardizedFileURL)
    #expect(WorkspaceImageRuntime.imageName(for: workspaceB).contains(key))
    #expect(CacheMounts.scopeKey(scope: .workspace, workspace: workspaceB) == key)
    for cache in privateCaches(.rust, in: workspaceB) {
        #expect(URL(fileURLWithPath: cache.hostPath).deletingLastPathComponent().lastPathComponent == key)
    }
}

// MARK: - Opt-in sharing

@Test func sharedScopeGivesEveryWorkspaceTheSameCaches() {
    for toolchain in Toolchain.allCases {
        #expect(sharedCaches(toolchain, in: workspaceA) == sharedCaches(toolchain, in: workspaceB))
    }
    #expect(!sharedCaches(.rust).isEmpty)
}

@Test func sharedScopeUsesOneDirectoryNoWorkspaceKeyCanReach() {
    // Exact paths, so this cannot be satisfied by something that merely contains
    // the shared key.
    #expect(
        Set(sharedCaches(.rust).map(\.hostPath)) == [
            cacheRoot.path + "/shared/cargo-registry",
            cacheRoot.path + "/shared/cargo-git",
        ]
    )
    #expect(Set(sharedCaches(.go).map(\.hostPath)) == [cacheRoot.path + "/shared/go-mod"])
    #expect(
        Set(sharedCaches(.js).map(\.hostPath)) == [
            cacheRoot.path + "/shared/deno",
            cacheRoot.path + "/shared/npm",
        ]
    )

    // No workspace can be named into the shared directory: a workspace key is a
    // slug joined to a path hash, so it always contains a dash and "shared"
    // never does.
    for workspace in [workspaceA, workspaceB, URL(fileURLWithPath: "/shared"), URL(fileURLWithPath: "/x/shared")] {
        #expect(CacheMounts.scopeKey(scope: .workspace, workspace: workspace) != CacheMounts.sharedKey)
    }
}

@Test func aPrivateCacheIsNeverTheSharedCache() {
    for toolchain in Toolchain.allCases {
        let privatePaths = Set(privateCaches(toolchain).map(\.hostPath))
        let sharedPaths = Set(sharedCaches(toolchain).map(\.hostPath))
        #expect(privatePaths.isDisjoint(with: sharedPaths))
    }
}

@Test func anImageOverrideGetsNoCaches() {
    // Detection still reports a toolchain for `spawn --image ghcr.io/foo/bar` in
    // a Cargo workspace, but spawn does not build that image and cannot know its
    // layout: mounting /opt/rust/cargo/{registry,git} into it would shadow
    // whatever lives there.
    #expect(
        CacheMounts.forRun(
            toolchain: .rust, imageOverride: "ghcr.io/foo/bar", scope: .workspace, workspace: workspaceA,
            root: cacheRoot
        ).isEmpty
    )
    for toolchain in Toolchain.allCases {
        for scope in CacheScope.allCases {
            #expect(
                CacheMounts.forRun(
                    toolchain: toolchain, imageOverride: "custom:latest", scope: scope, workspace: workspaceA,
                    root: cacheRoot
                ).isEmpty
            )
        }
    }
}

@Test func aRunWithoutAnImageOverrideGetsTheToolchainCaches() {
    // The guard above must subtract only the override case, or spawn-managed
    // runs would silently stop caching — and the run must carry the scope and
    // workspace through, or a run would mount directories no other code names.
    for toolchain in Toolchain.allCases {
        for scope in CacheScope.allCases {
            for workspace in [workspaceA, workspaceB] {
                #expect(
                    CacheMounts.forRun(
                        toolchain: toolchain, imageOverride: nil, scope: scope, workspace: workspace, root: cacheRoot
                    ) == CacheMounts.forToolchain(toolchain, scope: scope, workspace: workspace, root: cacheRoot)
                )
            }
        }
    }
    #expect(
        !CacheMounts.forRun(
            toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspaceA, root: cacheRoot
        ).isEmpty
    )
    // And a run in one workspace never names another workspace's caches.
    let runA = CacheMounts.forRun(
        toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspaceA, root: cacheRoot
    )
    let runB = CacheMounts.forRun(
        toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspaceB, root: cacheRoot
    )
    #expect(Set(runA.map(\.hostPath)).isDisjoint(with: Set(runB.map(\.hostPath))))
}

@Test func cachePathsAreUniqueAcrossToolchains() {
    for scope in CacheScope.allCases {
        let all = Toolchain.allCases.flatMap {
            CacheMounts.forToolchain($0, scope: scope, workspace: workspaceA, root: cacheRoot)
        }
        let paths = all.map(\.hostPath)
        #expect(Set(paths).count == paths.count)
        let guestPaths = all.map(\.guestPath)
        #expect(Set(guestPaths).count == guestPaths.count)
    }
}

@Test func cachesNeverShadowASeededHomeMount() throws {
    // Caches must survive `spawn home rm`, so they must not sit on a path spawn
    // seeds. The seeded paths are derived from MountResolver rather than
    // hand-listed: a hand-copied literal silently goes stale as paths are added,
    // and a stale list cannot fail.
    let home = try makeTempDir(files: [
        ".gitconfig": "[user]\n\tname = Test\n",
        ".ssh/id_ed25519": "key",
        ".config/gh/hosts.yml": "github.com:\n",
    ])
    let stateDir = try makeTempDir(files: [:])
    let workspace = try makeTempDir(files: ["README.md": "hi"])

    var seeded: Set<String> = []
    for agent in ["claude-code", "codex"] {
        for access in AccessProfile.allCases {
            let mounts = MountResolver.resolve(
                target: workspace,
                additional: [],
                readOnly: [],
                access: access,
                agent: agent,
                stateDir: stateDir,
                homeDirectory: home
            )
            for mount in mounts {
                seeded.insert(mount.guestPath)
            }
        }
    }

    // Guard against a vacuous derivation: if MountResolver stopped producing
    // these, the loop below would pass against anything.
    for expected in [
        "/home/coder/.claude", "/home/coder/.claude-state", "/home/coder/.codex",
        "/home/coder/.ssh", "/home/coder/.gitconfig-dir", "/home/coder/.config/gh",
    ] {
        #expect(seeded.contains(expected), "MountResolver no longer seeds \(expected)")
    }

    for toolchain in Toolchain.allCases {
        for scope in CacheScope.allCases {
            for cache in CacheMounts.forToolchain(
                toolchain, scope: scope, workspace: workspace, root: CacheMounts.root(stateDir: stateDir)
            ) {
                #expect(!seeded.contains(cache.guestPath))
                #expect(!seeded.contains { cache.guestPath.hasPrefix($0 + "/") })
            }
        }
    }
}

// MARK: - Preparing the host directories
//
// Preparation is now one `createDirectory` per cache: a bind-mounted host
// directory is mapped to the guest user by VirtioFS, so there is nothing to
// chown, nothing to roll back, and no lock to take.

@Test func preparationCreatesEveryCacheDirectory() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("caches")
    let caches = privateCaches(.rust, root: root)

    let usable = CacheMounts.prepare(caches)

    #expect(usable == caches)
    #expect(!caches.isEmpty)
    for cache in caches {
        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: cache.hostPath, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }
}

@Test func preparationIsIdempotentAndKeepsWhatIsAlreadyCached() throws {
    // The second run of a workspace must reuse the directory it filled, not
    // replace it: that is the entire value of a cache.
    let root = try makeTempDir(files: [:]).appendingPathComponent("caches")
    let caches = privateCaches(.go, root: root)
    guard let cache = caches.first else {
        Issue.record("expected go to declare a cache")
        return
    }

    _ = CacheMounts.prepare(caches)
    let marker = URL(fileURLWithPath: cache.hostPath).appendingPathComponent("downloaded.crate")
    try Data("cached".utf8).write(to: marker)

    let usable = CacheMounts.prepare(caches)

    #expect(usable == caches)
    #expect(try String(contentsOf: marker, encoding: .utf8) == "cached")
}

@Test func aCacheDirectoryThatCannotBeMadeIsDroppedNotMounted() throws {
    // A file where a cache directory should be. The run must lose that one cache
    // and keep the rest, rather than handing the container a path it cannot use.
    let root = try makeTempDir(files: [:]).appendingPathComponent("caches")
    let caches = privateCaches(.rust, root: root)
    guard let blocked = caches.first, caches.count == 2 else {
        Issue.record("expected rust to declare two caches")
        return
    }
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: blocked.hostPath).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    #expect(FileManager.default.createFile(atPath: blocked.hostPath, contents: Data()))

    let usable = CacheMounts.prepare(caches)

    #expect(usable == Array(caches.dropFirst()))
    #expect(!usable.contains(blocked))
}

@Test func aPreexistingUnwritableCacheDirectoryIsDroppedNotMounted() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("caches")
    let caches = privateCaches(.go, root: root)
    let cache = try #require(caches.first)
    try FileManager.default.createDirectory(
        atPath: cache.hostPath,
        withIntermediateDirectories: true
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o500],
        ofItemAtPath: cache.hostPath
    )
    defer {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: cache.hostPath
        )
    }

    #expect(CacheMounts.directoryStatus(at: cache.hostPath) == .notWritable)
    #expect(CacheMounts.prepare(caches).isEmpty)
}

@Test func aPreexistingNonTraversableCacheDirectoryIsDroppedNotMounted() throws {
    // Mode 0o200 is the case that separates traversable from writable: the
    // directory is writable, so a writability check alone passes it, but nothing
    // inside can be reached, so every cache read through the bind mount fails.
    // `createDirectory(withIntermediateDirectories:)` succeeds on a directory
    // that already exists whatever its mode, so `prepare` reaches the status
    // check rather than being rejected earlier by the create.
    let root = try makeTempDir(files: [:]).appendingPathComponent("caches")
    let caches = privateCaches(.go, root: root)
    let cache = try #require(caches.first)
    try FileManager.default.createDirectory(
        atPath: cache.hostPath,
        withIntermediateDirectories: true
    )
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o200],
        ofItemAtPath: cache.hostPath
    )
    defer {
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: cache.hostPath
        )
    }

    // Guard the premise: a mode that failed the writability check too would
    // leave the traversability check unexercised.
    #expect(FileManager.default.isWritableFile(atPath: cache.hostPath))
    #expect(!FileManager.default.isExecutableFile(atPath: cache.hostPath))

    #expect(CacheMounts.directoryStatus(at: cache.hostPath) == .notWritable)
    #expect(CacheMounts.prepare(caches).isEmpty)
}

@Test func preparingNoCachesTouchesNothing() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("caches")

    #expect(CacheMounts.prepare(privateCaches(.base, root: root)).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: root.path))
}
