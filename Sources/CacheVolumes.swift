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
            // CARGO_HOME=/opt/rust/cargo
            return [
                CacheVolume(name: prefix + "cargo-registry", guestPath: "/opt/rust/cargo/registry"),
                CacheVolume(name: prefix + "cargo-git", guestPath: "/opt/rust/cargo/git"),
            ]
        case .go:
            // GOPATH=/opt/go
            return [CacheVolume(name: prefix + "go-mod", guestPath: "/opt/go/pkg/mod")]
        case .js:
            // DENO_DIR=/opt/js/deno-cache; npm keeps its default $HOME/.npm cache.
            return [
                CacheVolume(name: prefix + "deno", guestPath: "/opt/js/deno-cache"),
                CacheVolume(name: prefix + "npm", guestPath: "/home/coder/.npm"),
            ]
        }
    }
}

/// Pure argument construction for handing a freshly created cache volume to the
/// guest user.
///
/// `container` creates a named volume root-owned and mode 0755, so the guest
/// user (`coder`, uid 1001) cannot write into it. Left alone, `cargo fetch`
/// fails with "Permission denied" instead of populating the cache. Each volume
/// is therefore chowned once, at creation, from a throwaway root container.
enum CacheVolumePreparation: Sendable {
    static let guestUID = 1001
    static let guestGID = 1001

    /// `container run` arguments for a throwaway root container that chowns
    /// every given volume to the guest user.
    static func chownArgs(image: String, volumes: [CacheVolume]) -> [String] {
        var args = ["run", "--rm", "--user", "root"]
        for volume in volumes {
            args += ["--volume", "\(volume.name):\(volume.guestPath)"]
        }
        let paths = volumes.map(\.guestPath).joined(separator: " ")
        args += [image, "sh", "-c", "chown \(guestUID):\(guestGID) \(paths)"]
        return args
    }
}
