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

@Test func cppHasNoCacheVolumes() {
    #expect(CacheVolumes.forToolchain(.cpp).isEmpty)
}

@Test func volumeNamesAreNamespacedAndStable() {
    for volume in CacheVolumes.forToolchain(.rust) {
        #expect(volume.name.hasPrefix("spawn-cache-"))
    }
    #expect(CacheVolumes.forToolchain(.rust) == CacheVolumes.forToolchain(.rust))
}

@Test func anImageOverrideGetsNoCacheVolumes() {
    // Detection still reports a toolchain for `spawn --image ghcr.io/foo/bar` in
    // a Cargo workspace, but spawn does not build that image and cannot know its
    // layout: mounting /opt/rust/cargo/{registry,git} into it would shadow
    // whatever lives there, and creating the volumes would cost a
    // create-and-roll-back on every run for a cache nothing ever populates.
    #expect(CacheVolumes.forRun(toolchain: .rust, imageOverride: "ghcr.io/foo/bar").isEmpty)
    for toolchain in Toolchain.allCases {
        #expect(CacheVolumes.forRun(toolchain: toolchain, imageOverride: "custom:latest").isEmpty)
    }
}

@Test func aRunWithoutAnImageOverrideGetsTheToolchainCaches() {
    // The guard above must subtract only the override case, or spawn-managed
    // runs would silently stop caching.
    for toolchain in Toolchain.allCases {
        #expect(
            CacheVolumes.forRun(toolchain: toolchain, imageOverride: nil)
                == CacheVolumes.forToolchain(toolchain)
        )
    }
    #expect(!CacheVolumes.forRun(toolchain: .rust, imageOverride: nil).isEmpty)
}

@Test func cacheVolumeNamesAreUniqueAcrossToolchains() {
    let all = Toolchain.allCases.flatMap { CacheVolumes.forToolchain($0) }
    let names = all.map(\.name)
    #expect(Set(names).count == names.count)
}

// MARK: - Volume preparation

@Test func chownArgsRunAsRootAndMountEveryVolume() {
    let volumes = CacheVolumes.forToolchain(.rust)
    let args = CacheVolumePreparation.chownArgs(image: "spawn-rust:latest", volumes: volumes)

    #expect(args.starts(with: ["run", "--rm", "--user", "root"]))
    let mounted = zip(args, args.dropFirst()).filter { $0.0 == "--volume" }.map(\.1)
    #expect(
        mounted == [
            "spawn-cache-cargo-registry:/opt/rust/cargo/registry",
            "spawn-cache-cargo-git:/opt/rust/cargo/git",
        ]
    )
}

@Test func chownArgsGiveEveryVolumeToTheGuestUser() {
    let volumes = CacheVolumes.forToolchain(.rust)
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
        let volumes = CacheVolumes.forToolchain(toolchain)
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
        for volume in CacheVolumes.forToolchain(toolchain) {
            #expect(!seeded.contains(volume.guestPath))
            #expect(!seeded.contains { volume.guestPath.hasPrefix($0 + "/") })
        }
    }
}

// MARK: - Preparation failure paths
//
// `prepareCacheVolumes` upholds one invariant: a cache volume that exists on
// disk has been chowned. If a failure could leave a created-but-unchowned
// volume behind, the next run's existence check would call it prepared and
// mount it root-owned forever.

/// In-memory stand-in for the `container volume` subcommands.
private final class FakeVolumeStore: @unchecked Sendable {
    private let lock = NSLock()
    private var existing: Set<String>
    private var chowned: Set<String> = []
    private var createFailures: Set<String> = []
    private var chownSucceeds = true
    private var deleteSucceeds = true
    private var chownImages: [String] = []

    init(existing: [String] = []) {
        self.existing = Set(existing)
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
            exists: { [self] name in locked { existing.contains(name) } },
            create: { [self] name in
                locked {
                    guard !createFailures.contains(name) else { return false }
                    existing.insert(name)
                    return true
                }
            },
            delete: { [self] name in
                locked {
                    guard deleteSucceeds else { return false }
                    existing.remove(name)
                    chowned.remove(name)
                    return true
                }
            },
            chown: { [self] volumes, image in
                locked {
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
    let volumes = CacheVolumes.forToolchain(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
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
    let volumes = CacheVolumes.forToolchain(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
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
    let volumes = CacheVolumes.forToolchain(.rust)

    _ = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
    )
    store.allowChown()
    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
    )

    #expect(usable == volumes)
    #expect(store.chownedNames == Set(volumes.map(\.name)))
}

@Test func failedCreateRollsBackTheVolumesAlreadyCreated() {
    let volumes = CacheVolumes.forToolchain(.rust)
    guard volumes.count == 2 else {
        Issue.record("expected rust to declare two cache volumes")
        return
    }
    let store = FakeVolumeStore()
    store.failCreate(of: volumes[1].name)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
    )

    #expect(usable.isEmpty)
    // The first volume was created before the second failed; it must not remain.
    #expect(store.volumeNames.isEmpty)
    #expect(store.imagesUsedForChown.isEmpty)
}

@Test func rollbackKeepsVolumesThatPredatedTheCall() {
    let volumes = CacheVolumes.forToolchain(.rust)
    guard volumes.count == 2 else {
        Issue.record("expected rust to declare two cache volumes")
        return
    }
    let store = FakeVolumeStore(existing: [volumes[0].name])
    store.failChown()

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
    )

    // The pre-existing volume was prepared by an earlier run, so it stays usable.
    #expect(usable == [volumes[0]])
    #expect(store.volumeNames == [volumes[0].name])
}

@Test func alreadyPreparedVolumesAreNotTouched() {
    let volumes = CacheVolumes.forToolchain(.rust)
    let store = FakeVolumeStore(existing: volumes.map(\.name))

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
    )

    #expect(usable == volumes)
    #expect(store.imagesUsedForChown.isEmpty, "an existing volume must not cost a container boot")
}

@Test func preparationRepairsOwnershipOfVolumesItDidNotCreate() {
    // Chowning the whole set, not just the new volumes, costs nothing extra in
    // the same container and repairs a volume whose ownership drifted.
    let volumes = CacheVolumes.forToolchain(.rust)
    guard volumes.count == 2 else {
        Issue.record("expected rust to declare two cache volumes")
        return
    }
    let store = FakeVolumeStore(existing: [volumes[0].name])

    _ = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
    )

    #expect(store.chownedNames == Set(volumes.map(\.name)))
}

@Test func anUndeletableVolumeIsStillDroppedFromTheRun() {
    // Rollback can itself fail. The volume is then left behind (the user is
    // warned), but it must not be handed to the run as if it were prepared.
    let store = FakeVolumeStore()
    store.failChown()
    store.failDelete()
    let volumes = CacheVolumes.forToolchain(.rust)

    let usable = ContainerRunner.prepareCacheVolumes(
        volumes, image: "spawn-rust:latest", operations: store.operations
    )

    #expect(usable.isEmpty)
}

@Test func preparationWithNoVolumesDoesNothing() {
    let store = FakeVolumeStore()

    let usable = ContainerRunner.prepareCacheVolumes(
        CacheVolumes.forToolchain(.base), image: "spawn-base:latest", operations: store.operations
    )

    #expect(usable.isEmpty)
    #expect(store.volumeNames.isEmpty)
    #expect(store.imagesUsedForChown.isEmpty)
}
