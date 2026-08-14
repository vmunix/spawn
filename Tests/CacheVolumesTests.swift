import Foundation
import Testing

@testable import spawn

/// Two unrelated workspaces, used throughout to prove that scoping actually
/// separates them. They deliberately share a last path component, so a
/// slug-only derivation would collide and be caught here.
private let workspaceA = URL(fileURLWithPath: "/Users/me/code/project")
private let workspaceB = URL(fileURLWithPath: "/Users/me/other/project")

/// Cache volumes for a toolchain in the default (private) scope.
private func privateCaches(_ toolchain: Toolchain, in workspace: URL = workspaceA) -> [CacheVolume] {
    CacheVolumes.forToolchain(toolchain, scope: .workspace, workspace: workspace)
}

/// Cache volumes for a toolchain in the opt-in shared scope. The workspace is
/// still passed — and must be ignored.
private func sharedCaches(_ toolchain: Toolchain, in workspace: URL = workspaceA) -> [CacheVolume] {
    CacheVolumes.forToolchain(toolchain, scope: .shared, workspace: workspace)
}

@Test func rustGetsCargoRegistryAndGitCaches() {
    let volumes = privateCaches(.rust)
    #expect(volumes.contains { $0.guestPath == "/opt/rust/cargo/registry" })
    #expect(volumes.contains { $0.guestPath == "/opt/rust/cargo/git" })
}

@Test func goGetsModuleCache() {
    #expect(privateCaches(.go).contains { $0.guestPath == "/opt/go/pkg/mod" })
}

@Test func jsGetsDenoAndNpmCaches() {
    let volumes = privateCaches(.js)
    #expect(volumes.contains { $0.guestPath == "/opt/js/deno-cache" })
    #expect(volumes.contains { $0.guestPath == "/home/coder/.npm" })
}

@Test func baseHasNoCacheVolumes() {
    #expect(privateCaches(.base).isEmpty)
    #expect(sharedCaches(.base).isEmpty)
}

@Test func cppHasNoCacheVolumes() {
    #expect(privateCaches(.cpp).isEmpty)
    #expect(sharedCaches(.cpp).isEmpty)
}

@Test func volumeNamesAreNamespacedAndStable() {
    for scope in CacheScope.allCases {
        for volume in CacheVolumes.forToolchain(.rust, scope: scope, workspace: workspaceA) {
            #expect(volume.name.hasPrefix("spawn-cache-"))
        }
    }
    #expect(privateCaches(.rust) == privateCaches(.rust))
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
// The security property this whole file exists for: a cache volume holds
// dependency sources fetched with one workspace's credentials (cargo's git
// cache can hold private repositories) and is mounted read-write, so under the
// default scope no two workspaces may ever be handed the same volume name.

@Test func twoWorkspacesNeverShareACacheVolumeUnderTheDefaultScope() {
    var seen: Set<String> = []
    var collided = false

    for toolchain in Toolchain.allCases {
        let namesA = privateCaches(toolchain, in: workspaceA).map(\.name)
        let namesB = privateCaches(toolchain, in: workspaceB).map(\.name)

        // Vacuity guard: an empty set of names would satisfy any disjointness
        // claim, so the toolchains that do declare caches must produce some.
        if toolchain == .rust || toolchain == .go || toolchain == .js {
            #expect(!namesA.isEmpty)
        }
        #expect(namesA.count == namesB.count)
        #expect(Set(namesA).isDisjoint(with: Set(namesB)))

        for name in namesA + namesB {
            collided = collided || !seen.insert(name).inserted
        }
    }

    #expect(!collided, "a cache volume name is reused across workspaces or toolchains")
}

@Test func workspaceScopedNamesAreStableAcrossCalls() {
    // Stability is what makes the cache a cache: a name that changed per call
    // would create a fresh empty volume on every run.
    for toolchain in Toolchain.allCases {
        #expect(privateCaches(toolchain, in: workspaceB) == privateCaches(toolchain, in: workspaceB))
    }
    #expect(privateCaches(.rust).map(\.name) == privateCaches(.rust).map(\.name))
}

@Test func workspaceScopedNamesIgnorePathSpellingDifferences() {
    // ~/code/app, ~/code/app/ and ~/code/./app are one workspace, so they must
    // reach one cache rather than quietly starting a second.
    let spellings = [
        URL(fileURLWithPath: "/Users/me/code/project"),
        URL(fileURLWithPath: "/Users/me/code/project/"),
        URL(fileURLWithPath: "/Users/me/code/./project"),
    ]
    let expected = privateCaches(.rust, in: workspaceA).map(\.name)
    for spelling in spellings {
        #expect(privateCaches(.rust, in: spelling).map(\.name) == expected)
    }
}

@Test func workspacesWithTheSameDirectoryNameStillGetDistinctCaches() {
    // The slug alone would collide here; the path hash is what separates them.
    let left = URL(fileURLWithPath: "/Users/me/work/api")
    let right = URL(fileURLWithPath: "/Users/me/personal/api")
    let leftNames = Set(privateCaches(.rust, in: left).map(\.name))
    let rightNames = Set(privateCaches(.rust, in: right).map(\.name))

    #expect(!leftNames.isEmpty)
    #expect(leftNames.isDisjoint(with: rightNames))
}

@Test func workspaceScopedNamesCarryTheSameIdentityAsTheWorkspaceImage() {
    // Reuse, not reimplementation: the cache key must be the key that names the
    // workspace runtime image, so both agree on what "this workspace" is.
    let key = WorkspaceIdentity.key(for: workspaceB.standardizedFileURL)
    #expect(WorkspaceImageRuntime.imageName(for: workspaceB).contains(key))
    for volume in privateCaches(.rust, in: workspaceB) {
        #expect(volume.name.hasSuffix("-" + key))
    }
}

// MARK: - Opt-in sharing

@Test func sharedScopeGivesEveryWorkspaceTheSameVolumes() {
    for toolchain in Toolchain.allCases {
        #expect(sharedCaches(toolchain, in: workspaceA) == sharedCaches(toolchain, in: workspaceB))
    }
    #expect(!sharedCaches(.rust).isEmpty)
}

@Test func sharedScopeKeepsTheHistoricalGlobalVolumeNames() {
    // Opting in must land on the volumes already on disk, or sharing would
    // silently start from an empty cache. Exact equality, so this cannot be
    // satisfied by a name that merely contains these strings.
    #expect(Set(sharedCaches(.rust).map(\.name)) == ["spawn-cache-cargo-registry", "spawn-cache-cargo-git"])
    #expect(Set(sharedCaches(.go).map(\.name)) == ["spawn-cache-go-mod"])
    #expect(Set(sharedCaches(.js).map(\.name)) == ["spawn-cache-deno", "spawn-cache-npm"])
}

@Test func aPrivateCacheIsNeverTheSharedCache() {
    for toolchain in Toolchain.allCases {
        let privateNames = Set(privateCaches(toolchain).map(\.name))
        let sharedNames = Set(sharedCaches(toolchain).map(\.name))
        #expect(privateNames.isDisjoint(with: sharedNames))
    }
}

@Test func anImageOverrideGetsNoCacheVolumes() {
    // Detection still reports a toolchain for `spawn --image ghcr.io/foo/bar` in
    // a Cargo workspace, but spawn does not build that image and cannot know its
    // layout: mounting /opt/rust/cargo/{registry,git} into it would shadow
    // whatever lives there, and creating the volumes would cost a
    // create-and-roll-back on every run for a cache nothing ever populates.
    #expect(
        CacheVolumes.forRun(
            toolchain: .rust, imageOverride: "ghcr.io/foo/bar", scope: .workspace, workspace: workspaceA
        ).isEmpty
    )
    for toolchain in Toolchain.allCases {
        for scope in CacheScope.allCases {
            #expect(
                CacheVolumes.forRun(
                    toolchain: toolchain, imageOverride: "custom:latest", scope: scope, workspace: workspaceA
                ).isEmpty
            )
        }
    }
}

@Test func aRunWithoutAnImageOverrideGetsTheToolchainCaches() {
    // The guard above must subtract only the override case, or spawn-managed
    // runs would silently stop caching — and the run must carry the scope and
    // workspace through, or a run would mount volumes no other code names.
    for toolchain in Toolchain.allCases {
        for scope in CacheScope.allCases {
            for workspace in [workspaceA, workspaceB] {
                #expect(
                    CacheVolumes.forRun(
                        toolchain: toolchain, imageOverride: nil, scope: scope, workspace: workspace
                    ) == CacheVolumes.forToolchain(toolchain, scope: scope, workspace: workspace)
                )
            }
        }
    }
    #expect(
        !CacheVolumes.forRun(toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspaceA).isEmpty
    )
    // And a run in one workspace never names another workspace's volumes.
    let runA = CacheVolumes.forRun(toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspaceA)
    let runB = CacheVolumes.forRun(toolchain: .rust, imageOverride: nil, scope: .workspace, workspace: workspaceB)
    #expect(Set(runA.map(\.name)).isDisjoint(with: Set(runB.map(\.name))))
}

@Test func cacheVolumeNamesAreUniqueAcrossToolchains() {
    for scope in CacheScope.allCases {
        let all = Toolchain.allCases.flatMap { CacheVolumes.forToolchain($0, scope: scope, workspace: workspaceA) }
        let names = all.map(\.name)
        #expect(Set(names).count == names.count)
    }
}

// MARK: - Volume preparation

@Test func chownArgsRunAsRootAndMountEveryVolume() {
    let volumes = privateCaches(.rust)
    let args = CacheVolumePreparation.chownArgs(image: "spawn-rust:latest", volumes: volumes)

    #expect(args.starts(with: ["run", "--rm", "--user", "root"]))
    let mounted = zip(args, args.dropFirst()).filter { $0.0 == "--volume" }.map(\.1)
    #expect(mounted.count == 2)
    #expect(mounted == volumes.map { "\($0.name):\($0.guestPath)" })
}

@Test func chownArgsGiveEveryVolumeToTheGuestUser() {
    let volumes = privateCaches(.rust)
    let args = CacheVolumePreparation.chownArgs(image: "spawn-rust:latest", volumes: volumes)

    guard let command = args.last else {
        Issue.record("chownArgs produced no command")
        return
    }
    // By name, not uid: `chown` to a numeric id that maps to no user exits 0,
    // so a uid drift in the base image would fail silently.
    #expect(command == "chown coder:coder /opt/rust/cargo/registry /opt/rust/cargo/git")
    #expect(!command.contains("1001"))
    #expect(args.contains("spawn-rust:latest"))
}

@Test func chownArgsCoverEveryToolchainCachePath() {
    for toolchain in Toolchain.allCases {
        let volumes = privateCaches(toolchain)
        guard !volumes.isEmpty else { continue }
        guard let command = CacheVolumePreparation.chownArgs(image: "img", volumes: volumes).last else {
            Issue.record("chownArgs produced no command for \(toolchain.rawValue)")
            continue
        }
        for volume in volumes {
            #expect(command.contains(volume.guestPath))
        }
    }
}

@Test func cacheVolumesNeverShadowASeededHomeMount() throws {
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
            for volume in CacheVolumes.forToolchain(toolchain, scope: scope, workspace: workspace) {
                #expect(!seeded.contains(volume.guestPath))
                #expect(!seeded.contains { volume.guestPath.hasPrefix($0 + "/") })
            }
        }
    }
}

// MARK: - Preparation failure paths
//
// `prepareCacheVolumes` upholds one invariant: a cache volume that exists on
// disk has been chowned. If a failure could leave a created-but-unchowned
// volume behind, the next run's existence check would call it prepared and
// mount it root-owned forever.

/// An always-free lock, for the tests that are about preparation rather than
/// serialization. Passed explicitly so the suite stays off the real state
/// directory: with the default `.hostFile()` lock every one of these calls takes
/// a genuine `flock` under `~/.local/state/spawn`, where a concurrent test run —
/// or a concurrent `spawn` — would sit in its bounded wait.
private var freeLock: CacheVolumeLock { FakeLock().lock }

/// Ordered record of what a run of `prepareCacheVolumes` did, shared by the
/// volume-store and lock fakes so their calls can be compared against each
/// other in time. Ordering is the only way to state "no volume was inspected
/// before the lock was held", which is the property the fix turns on.
private final class EventLog: @unchecked Sendable {
    private let mutex = NSLock()
    private var recorded: [String] = []

    func record(_ event: String) {
        mutex.lock()
        defer { mutex.unlock() }
        recorded.append(event)
    }

    var events: [String] {
        mutex.lock()
        defer { mutex.unlock() }
        return recorded
    }
}

/// In-memory stand-in for the `container volume` subcommands.
private final class FakeVolumeStore: @unchecked Sendable {
    private let lock = NSLock()
    private var existing: Set<String>
    private var chowned: Set<String> = []
    private var createFailures: Set<String> = []
    private var chownSucceeds = true
    private var deleteSucceeds = true
    private var chownImages: [String] = []
    private let log: EventLog?

    init(existing: [String] = [], log: EventLog? = nil) {
        self.existing = Set(existing)
        self.log = log
    }

    /// Mark volumes as fully prepared without recording the calls, standing in
    /// for a *different* spawn process that finished preparing them.
    func markPrepared(_ volumes: [CacheVolume]) {
        locked {
            for volume in volumes {
                existing.insert(volume.name)
                chowned.insert(volume.name)
            }
        }
    }

    private func locked<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    func failCreate(of name: String) { locked { createFailures.insert(name) } }
    func failChown() { locked { chownSucceeds = false } }
    func allowChown() { locked { chownSucceeds = true } }
    func failDelete() { locked { deleteSucceeds = false } }

    var volumeNames: Set<String> { locked { existing } }
    var chownedNames: Set<String> { locked { chowned } }
    var imagesUsedForChown: [String] { locked { chownImages } }

    var operations: CacheVolumeOperations {
        CacheVolumeOperations(
            exists: { [self] name in
                log?.record("volume.exists")
                return locked { existing.contains(name) }
            },
            create: { [self] name in
                log?.record("volume.create")
                return locked {
                    guard !createFailures.contains(name) else { return false }
                    // `container volume create` exits 1 on a volume that is
                    // already there — it is not idempotent — so a caller that
                    // acts on a stale "missing" list fails here rather than
                    // quietly re-creating what a peer just made.
                    guard !existing.contains(name) else { return false }
                    existing.insert(name)
                    return true
                }
            },
            delete: { [self] name in
                log?.record("volume.delete")
                return locked {
                    guard deleteSucceeds else { return false }
                    existing.remove(name)
                    chowned.remove(name)
                    return true
                }
            },
            chown: { [self] volumes, image in
                log?.record("volume.chown")
                return locked {
                    chownImages.append(image)
                    guard chownSucceeds else { return false }
                    for volume in volumes { chowned.insert(volume.name) }
                    return true
                }
            }
        )
    }
}

@Test func preparationCreatesAndChownsEveryMissingVolume() {
    let store = FakeVolumeStore()
    let volumes = privateCaches(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    #expect(usable == volumes)
    #expect(store.volumeNames == Set(volumes.map(\.name)))
    #expect(store.chownedNames == Set(volumes.map(\.name)))
    #expect(store.imagesUsedForChown == ["spawn-rust:latest"])
}

@Test func failedChownLeavesNoVolumeBehind() {
    // The critical case: a volume created but not chowned must not survive, or
    // the next run would mount it root-owned and every build would fail.
    let store = FakeVolumeStore()
    store.failChown()
    let volumes = privateCaches(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    #expect(usable.isEmpty)
    #expect(store.volumeNames.isEmpty)
    #expect(store.chownedNames.isEmpty)
}

@Test func aRunAfterAFailedChownStillPreparesTheCache() {
    // Self-healing follows from the invariant: because the failed run left no
    // volume behind, the next run sees them as missing and prepares them.
    let store = FakeVolumeStore()
    store.failChown()
    let volumes = privateCaches(.rust)

    _ = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )
    store.allowChown()
    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    #expect(usable == volumes)
    #expect(store.chownedNames == Set(volumes.map(\.name)))
}

@Test func failedCreateRollsBackTheVolumesAlreadyCreated() {
    let volumes = privateCaches(.rust)
    guard volumes.count == 2 else {
        Issue.record("expected rust to declare two cache volumes")
        return
    }
    let store = FakeVolumeStore()
    store.failCreate(of: volumes[1].name)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    #expect(usable.isEmpty)
    // The first volume was created before the second failed; it must not remain.
    #expect(store.volumeNames.isEmpty)
    #expect(store.imagesUsedForChown.isEmpty)
}

@Test func rollbackKeepsVolumesThatPredatedTheCall() {
    let volumes = privateCaches(.rust)
    guard volumes.count == 2 else {
        Issue.record("expected rust to declare two cache volumes")
        return
    }
    let store = FakeVolumeStore(existing: [volumes[0].name])
    store.failChown()

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    // The pre-existing volume was prepared by an earlier run, so it stays usable.
    #expect(usable == [volumes[0]])
    #expect(store.volumeNames == [volumes[0].name])
}

@Test func alreadyPreparedVolumesAreNotTouched() {
    let volumes = privateCaches(.rust)
    let store = FakeVolumeStore(existing: volumes.map(\.name))

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    #expect(usable == volumes)
    #expect(store.imagesUsedForChown.isEmpty, "an existing volume must not cost a container boot")
}

@Test func preparationRepairsOwnershipOfVolumesItDidNotCreate() {
    // Chowning the whole set, not just the new volumes, costs nothing extra in
    // the same container and repairs a volume whose ownership drifted.
    let volumes = privateCaches(.rust)
    guard volumes.count == 2 else {
        Issue.record("expected rust to declare two cache volumes")
        return
    }
    let store = FakeVolumeStore(existing: [volumes[0].name])

    _ = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    #expect(store.chownedNames == Set(volumes.map(\.name)))
}

@Test func anUndeletableVolumeIsStillDroppedFromTheRun() {
    // Rollback can itself fail. The volume is then left behind (the user is
    // warned), but it must not be handed to the run as if it were prepared.
    let store = FakeVolumeStore()
    store.failChown()
    store.failDelete()
    let volumes = privateCaches(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: freeLock
    )

    #expect(usable.isEmpty)
}

@Test func preparationWithNoVolumesDoesNothing() {
    let store = FakeVolumeStore()

    let usable = ContainerRunner.prepareCacheVolumes(
        privateCaches(.base), image: "spawn-base:latest", operations: store.operations, lock: freeLock
    )

    #expect(usable.isEmpty)
    #expect(store.volumeNames.isEmpty)
    #expect(store.imagesUsedForChown.isEmpty)
}

// MARK: - Serializing preparation against a concurrent spawn
//
// The invariant above ("a volume that exists has been chowned") is false for as
// long as some process is between `create` and `chown`. A second spawn that
// looks in that window either mounts root-owned volumes, or — if the first then
// rolls back — has its volumes deleted underneath it, after which `container
// run` re-creates them root-owned and every later run trusts them. Preparation
// therefore holds a host lock, and the decision it acts on must be made under
// that lock.

/// Stand-in for the host `flock`, recording when it is taken and released and
/// able to run a hook while held — which is how a peer's progress mid-wait is
/// simulated.
private final class FakeLock: @unchecked Sendable {
    private let mutex = NSLock()
    private var acquisitions: [String] = []
    private var releases = 0
    private let available: Bool
    private let log: EventLog?
    private let whileHeld: (@Sendable () -> Void)?

    init(available: Bool = true, log: EventLog? = nil, whileHeld: (@Sendable () -> Void)? = nil) {
        self.available = available
        self.log = log
        self.whileHeld = whileHeld
    }

    var keysRequested: [String] {
        mutex.lock()
        defer { mutex.unlock() }
        return acquisitions
    }

    var releaseCount: Int {
        mutex.lock()
        defer { mutex.unlock() }
        return releases
    }

    var lock: CacheVolumeLock {
        CacheVolumeLock { [self] key in
            mutex.lock()
            acquisitions.append(key)
            mutex.unlock()

            guard available else {
                log?.record("lock.unavailable")
                return nil
            }
            log?.record("lock.acquire")
            whileHeld?()
            return { [self] in
                log?.record("lock.release")
                mutex.lock()
                releases += 1
                mutex.unlock()
            }
        }
    }
}

@Test func preparationTakesTheLockBeforeItInspectsAnyVolume() {
    // Ordering, not just presence: a lock-free "are they all there?" fast path
    // would still observe a peer's half-prepared volumes and trust them, so no
    // volume may be looked at before the lock is held.
    let log = EventLog()
    let store = FakeVolumeStore(log: log)
    let lock = FakeLock(log: log)
    let volumes = privateCaches(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: lock.lock
    )

    #expect(usable == volumes)
    #expect(log.events.first == "lock.acquire")
    #expect(log.events.contains("volume.exists"), "the test is worthless if no volume was inspected at all")
    #expect(log.events.last == "lock.release")
    #expect(lock.keysRequested.count == 1, "one lock covers the whole volume set")
}

@Test func existenceIsRecheckedUnderTheLock() {
    // A peer prepared these volumes while this call waited for the lock. Acting
    // on the list gathered before the wait would try to create volumes that now
    // exist — which `container volume create` rejects — and roll back a cache
    // the peer correctly prepared.
    let store = FakeVolumeStore()
    let volumes = privateCaches(.rust)
    let lock = FakeLock(whileHeld: { store.markPrepared(volumes) })

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: lock.lock
    )

    #expect(usable == volumes)
    #expect(store.volumeNames == Set(volumes.map(\.name)), "the peer's volumes must survive")
    #expect(store.imagesUsedForChown.isEmpty, "volumes the peer already prepared need no second chown")
}

@Test func aVolumeCreatedByAPeerIsNeverRecreated() {
    // The narrower half of the same interleaving: the peer got one volume in
    // before this call took the lock. Re-checking finds one missing, not two.
    let volumes = privateCaches(.rust)
    guard let first = volumes.first, volumes.count == 2 else {
        Issue.record("expected rust to declare two cache volumes")
        return
    }
    let store = FakeVolumeStore()
    let lock = FakeLock(whileHeld: { store.markPrepared([first]) })

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: lock.lock
    )

    #expect(usable == volumes)
    #expect(store.volumeNames == Set(volumes.map(\.name)))
    #expect(store.chownedNames == Set(volumes.map(\.name)))
}

@Test func preparationProceedsWhenTheLockCannotBeTaken() {
    // Degrade, never hang: an unavailable lock leaves the old race, but a
    // launch that blocks forever behind a wedged peer is worse.
    let log = EventLog()
    let store = FakeVolumeStore(log: log)
    let lock = FakeLock(available: false, log: log)
    let volumes = privateCaches(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations, lock: lock.lock
    )

    #expect(usable == volumes)
    #expect(store.chownedNames == Set(volumes.map(\.name)))
    #expect(log.events.contains("lock.unavailable"))
    #expect(lock.releaseCount == 0)
}

@Test func theLockIsReleasedBeforePreparationReturns() {
    // The lock must not still be held when the caller goes on to `container
    // run`, which is the long part of a launch.
    let store = FakeVolumeStore()
    let lock = FakeLock()

    _ = ContainerRunner.prepareCacheVolumes(
        privateCaches(.rust), image: "spawn-rust:latest", operations: store.operations, lock: lock.lock
    )

    #expect(lock.releaseCount == 1)
}

@Test func theLockIsReleasedWhenPreparationFails() {
    let store = FakeVolumeStore()
    store.failChown()
    let lock = FakeLock()

    let usable = ContainerRunner.prepareCacheVolumes(
        privateCaches(.rust), image: "spawn-rust:latest", operations: store.operations, lock: lock.lock
    )

    #expect(usable.isEmpty)
    #expect(lock.releaseCount == 1, "a failed preparation must not strand the lock")
}

@Test func anEmptyVolumeSetTakesNoLock() {
    let store = FakeVolumeStore()
    let lock = FakeLock()

    _ = ContainerRunner.prepareCacheVolumes(
        privateCaches(.base), image: "spawn-base:latest", operations: store.operations, lock: lock.lock
    )

    #expect(lock.keysRequested.isEmpty)
}

// MARK: - Lock keys

@Test func theLockKeyFollowsTheVolumeSetNotItsOrder() {
    let volumes = privateCaches(.rust)
    #expect(CacheVolumeLock.key(for: volumes) == CacheVolumeLock.key(for: volumes.reversed()))
}

@Test func unrelatedWorkspacesDoNotShareALockKey() {
    // Workspace-scoped caches are per-workspace volumes, so two workspaces must
    // not serialize their launches against each other.
    #expect(CacheVolumeLock.key(for: privateCaches(.rust, in: workspaceA)) != CacheVolumeLock.key(for: privateCaches(.rust, in: workspaceB)))
    #expect(CacheVolumeLock.key(for: privateCaches(.rust)) != CacheVolumeLock.key(for: privateCaches(.go)))
}

@Test func sharedScopeCachesShareOneLockKeyAcrossWorkspaces() {
    // The inverse: `--cache shared` puts every workspace on the same global
    // volume names, so they must contend for the same lock.
    #expect(CacheVolumeLock.key(for: sharedCaches(.rust, in: workspaceA)) == CacheVolumeLock.key(for: sharedCaches(.rust, in: workspaceB)))
}

@Test func theLockKeyIsSafeAsAFileName() {
    for toolchain in [Toolchain.rust, .go, .js] {
        let key = CacheVolumeLock.key(for: privateCaches(toolchain))
        #expect(!key.isEmpty)
        #expect(!key.contains("/"))
        #expect(key == key.trimmingCharacters(in: .whitespacesAndNewlines))
        #expect(URL(fileURLWithPath: "/tmp").appendingPathComponent(key + ".lock").lastPathComponent == key + ".lock")
    }
}

// MARK: - The real host lock

@Test func theHostLockExcludesASecondHolder() throws {
    let directory = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("spawn-lock-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }

    // A short wait keeps the test quick; the contended path is the same one a
    // 30-second wait takes, just with fewer polls.
    let lock = CacheVolumeLock.hostFile(directory: directory, waitSeconds: 0.2, pollSeconds: 0.02)

    let held = try #require(lock.acquire("alpha"), "the first holder must get the lock")
    #expect(lock.acquire("alpha") == nil, "a second holder must not get a lock that is held")
    #expect(FileManager.default.fileExists(atPath: CacheVolumeLock.lockFilePath(in: directory, key: "alpha")))

    // A different key is a different lock, so unrelated workspaces do not wait.
    let other = try #require(lock.acquire("beta"), "an unrelated key must not be blocked")
    other()

    held()
    let reacquired = try #require(lock.acquire("alpha"), "releasing must let the next holder in")
    reacquired()
}

@Test func theHostLockDegradesWhenItsDirectoryCannotBeMade() {
    // A file where the lock directory should be: creating it fails, and
    // preparation must go on unserialized rather than throwing or hanging.
    let base = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("spawn-lock-tests-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: base) }
    FileManager.default.createFile(atPath: base.path, contents: Data())

    let lock = CacheVolumeLock.hostFile(directory: base.appendingPathComponent("locks"), waitSeconds: 0.2)
    #expect(lock.acquire("alpha") == nil)
}
