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
    // uid/gid 1001 is the guest `coder` user; a root-owned volume is unwritable.
    #expect(command == "chown 1001:1001 /opt/rust/cargo/registry /opt/rust/cargo/git")
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

@Test func cacheVolumesNeverLiveInSeededHomeState() {
    // Caches must survive `spawn home rm`, so they must not sit under the
    // directories spawn seeds or migrates. `~/.npm` is npm's own default and
    // is not spawn-managed state.
    let seededHomePaths = ["/home/coder/.claude", "/home/coder/.config", "/home/coder/.local/state"]
    for toolchain in Toolchain.allCases {
        for volume in CacheVolumes.forToolchain(toolchain) {
            #expect(!seededHomePaths.contains { volume.guestPath.hasPrefix($0) })
        }
    }
}
