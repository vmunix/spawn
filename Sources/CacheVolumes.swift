import Foundation

/// A named `container` volume holding a build cache.
///
/// Caches are deliberately kept out of the image: they should survive between
/// runs, but they are not image content and must not be seeded, migrated, or
/// removed along with a home. They also stay off the paths spawn seeds into
/// `/home/coder`, so `spawn home rm` cannot take a cache with it — though a
/// cache may still mount inside the home where a tool hardcodes its location
/// (npm's `$HOME/.npm`).
struct CacheVolume: Sendable, Equatable {
    let name: String
    let guestPath: String
}

enum CacheVolumes: Sendable {
    private static let prefix = "spawn-cache-"

    /// Build caches for a toolchain. Paths must match the toolchain locations
    /// set in `ContainerfileTemplates`.
    ///
    /// Every mount point's *parent* must already exist, coder-owned, in the
    /// image: `container` creates the missing parents of a volume mount root-
    /// owned, and the tool then cannot write its siblings. rust satisfies this
    /// because rustup creates `/opt/rust/cargo`, and js because `/opt/js` is
    /// chowned; go needed an explicit `mkdir -p /opt/go/pkg/mod`, without which
    /// a root-owned `/opt/go/pkg` blocked `go` from writing `sumdb`. A new
    /// toolchain's template must satisfy this before its cache is added here.
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

    /// Build caches for one run.
    ///
    /// An `--image` override runs an image spawn neither builds nor inspects,
    /// so its layout is unknown: the toolchain's cache paths may hold something
    /// else entirely, and mounting over them would shadow it. Detection still
    /// reports a toolchain for such a run, so the override — not the detected
    /// toolchain — decides. No volume is created either, which keeps a run that
    /// never populates a cache from paying create-and-roll-back every time.
    static func forRun(toolchain: Toolchain, imageOverride: String?) -> [CacheVolume] {
        guard imageOverride == nil else { return [] }
        return forToolchain(toolchain)
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
    /// The guest user, by name. Deliberately not the numeric uid: `useradd` in
    /// the base image assigns it implicitly, and `chown` to a numeric id that no
    /// longer maps to a user still exits 0, so drift would go unnoticed.
    static let guestUser = "coder"

    /// `container run` arguments for a throwaway root container that chowns
    /// every given volume to the guest user.
    static func chownArgs(image: String, volumes: [CacheVolume]) -> [String] {
        var args = ["run", "--rm", "--user", "root"]
        for volume in volumes {
            args += ["--volume", "\(volume.name):\(volume.guestPath)"]
        }
        let paths = volumes.map(\.guestPath).joined(separator: " ")
        args += [image, "sh", "-c", "chown \(guestUser):\(guestUser) \(paths)"]
        return args
    }
}

/// The `container volume` operations that preparation needs.
///
/// Injectable so the failure paths — which must leave no half-prepared volume
/// behind — can be exercised without a container runtime, mirroring the
/// `containerPath:` override on `ContainerRunner.preflight`.
struct CacheVolumeOperations: Sendable {
    /// Whether a named volume already exists.
    var exists: @Sendable (String) -> Bool
    /// Create a named volume. Returns whether it succeeded.
    var create: @Sendable (String) -> Bool
    /// Delete a named volume. Returns whether it succeeded.
    var delete: @Sendable (String) -> Bool
    /// Chown the given volumes to the guest user, from a throwaway root
    /// container built on `image`. Returns whether it succeeded.
    var chown: @Sendable (_ volumes: [CacheVolume], _ image: String) -> Bool
}
