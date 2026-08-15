import Foundation

/// Build caches, as host directories bind-mounted into the guest.
///
/// Caches are deliberately kept out of the image: they should survive between
/// runs, but they are not image content and must not be seeded, migrated, or
/// removed along with a home. They also stay off the paths spawn seeds into
/// `/home/coder`, so `spawn home rm` cannot take a cache with it — though a
/// cache may still mount inside the home where a tool hardcodes its location
/// (npm's `$HOME/.npm`).
///
/// They are host directories rather than named `container` volumes because a
/// named volume is a raw ext4 image attached as a virtio block device, and ext4
/// is not a cluster filesystem: `container` itself treats a volume as
/// exclusively owned (`volumeInUse`), and three concurrent runs sharing one
/// measurably fail with "The storage device attachment is invalid." A bind
/// mount is served by VirtioFS, which maps ownership to the guest user and
/// tolerates concurrent runs, so the create/chown/rollback/lock machinery the
/// block device needed is gone with it.
enum CacheMounts: Sendable {
    /// The scope key every shared cache lives under.
    ///
    /// It cannot collide with a workspace key: `WorkspaceIdentity.key` is a slug
    /// joined to a path hash by a `-`, so every workspace key contains one.
    static let sharedKey = "shared"

    /// Where cache directories live: `<state>/caches`.
    static func root(stateDir: URL = Paths.stateDir) -> URL {
        stateDir.appendingPathComponent("caches")
    }

    /// The directory holding every cache of one scope.
    ///
    /// Under `.workspace` — the default everywhere a user has not asked
    /// otherwise — the workspace identity keys the directory, so an unrelated
    /// workspace, including one running under `--access minimal`, cannot read
    /// the dependency sources this one cached or write the cache it will read
    /// next. Under `.shared` every workspace lands on one directory, which is
    /// the whole point of opting in.
    ///
    /// The identity comes from `WorkspaceIdentity`, the same derivation that
    /// names workspace runtime images, so a workspace's image and its caches
    /// agree on what "this workspace" is — including its standardization, so
    /// `~/code/app` and `~/code/app/` share one cache rather than silently
    /// starting a second.
    static func directory(scope: CacheScope, workspace: URL, root: URL) -> URL {
        root.appendingPathComponent(scopeKey(scope: scope, workspace: workspace))
    }

    /// The scope-dependent directory name of a cache set.
    static func scopeKey(scope: CacheScope, workspace: URL) -> String {
        switch scope {
        case .shared:
            return sharedKey
        case .workspace:
            return WorkspaceIdentity.key(for: workspace)
        }
    }

    /// Build caches for a toolchain. Guest paths must match the toolchain
    /// locations set in `ContainerfileTemplates`.
    static func forToolchain(_ toolchain: Toolchain, scope: CacheScope, workspace: URL, root: URL) -> [Mount] {
        let directory = directory(scope: scope, workspace: workspace, root: root)
        switch toolchain {
        case .base, .cpp:
            return []
        case .rust:
            // CARGO_HOME=/opt/rust/cargo
            return [
                mount(in: directory, named: "cargo-registry", at: "/opt/rust/cargo/registry"),
                mount(in: directory, named: "cargo-git", at: "/opt/rust/cargo/git"),
            ]
        case .go:
            // GOPATH=/opt/go
            return [mount(in: directory, named: "go-mod", at: "/opt/go/pkg/mod")]
        case .js:
            // DENO_DIR=/opt/js/deno-cache; npm keeps its default $HOME/.npm cache.
            return [
                mount(in: directory, named: "deno", at: "/opt/js/deno-cache"),
                mount(in: directory, named: "npm", at: "/home/coder/.npm"),
            ]
        }
    }

    /// Build caches for one run.
    ///
    /// An `--image` override runs an image spawn neither builds nor inspects,
    /// so its layout is unknown: the toolchain's cache paths may hold something
    /// else entirely, and mounting over them would shadow it. Detection still
    /// reports a toolchain for such a run, so the override — not the detected
    /// toolchain — decides.
    static func forRun(
        toolchain: Toolchain,
        imageOverride: String?,
        scope: CacheScope,
        workspace: URL,
        root: URL
    ) -> [Mount] {
        guard imageOverride == nil else { return [] }
        return forToolchain(toolchain, scope: scope, workspace: workspace, root: root)
    }

    /// Create the host directory behind every cache mount, dropping the ones
    /// that cannot be made.
    ///
    /// Creating a cache is exactly this: `container` bind-mounts the directory
    /// through VirtioFS, which maps it to the guest user, so there is nothing to
    /// chown and nothing to roll back. An unmakeable directory is dropped rather
    /// than mounted, so a run degrades to "no cache" instead of failing on a
    /// path the guest cannot use.
    static func prepare(_ mounts: [Mount], fileManager: FileManager = .default) -> [Mount] {
        mounts.filter { mount in
            do {
                try fileManager.createDirectory(
                    atPath: mount.hostPath,
                    withIntermediateDirectories: true
                )
                return true
            } catch {
                logger.warning(
                    "Could not create the build cache directory \(mount.hostPath): \(error.localizedDescription). Continuing without it."
                )
                return false
            }
        }
    }

    private static func mount(in directory: URL, named name: String, at guestPath: String) -> Mount {
        Mount(
            hostPath: directory.appendingPathComponent(name).path,
            guestPath: guestPath,
            readOnly: false
        )
    }
}
