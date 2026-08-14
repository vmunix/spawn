import Foundation

/// Exclusive, host-side preparation rights for one set of cache volumes.
///
/// Preparing a cache volume is create-then-chown, and only the pair together
/// satisfies the invariant `prepareCacheVolumes` rests on — *a `spawn-cache-*`
/// volume that exists on disk has been chowned*. Two spawn processes launching
/// the same workspace at once can interleave inside that window, and both ways
/// it can go are damaging:
///
/// - The observer sees the creator's volumes after `create` and before `chown`,
///   finds nothing missing, and mounts them root-owned: every cache write in
///   that run fails with `EACCES`.
/// - Worse, the creator then fails its chown and rolls back, deleting volumes
///   the observer has already decided to mount. `container run` silently
///   re-creates a missing named volume **root-owned**, so the invariant is now
///   false on disk and every later run keeps trusting it — permanent `EACCES`
///   with no self-heal.
///
/// Serializing preparation on a host lock file closes both, and costs no
/// container boot: a per-run readiness probe inside the guest would add one or
/// two seconds to every launch, while `flock(2)` costs an `open` and a syscall.
/// The kernel drops the lock when the holder dies, so there is no stale lock to
/// reap.
///
/// Injectable so the contended, unavailable, and re-checked paths can be
/// exercised without real files or a container runtime, mirroring
/// `CacheVolumeOperations`.
struct CacheVolumeLock: Sendable {
    /// Take exclusive preparation rights for `key` and return the closure that
    /// releases them.
    ///
    /// `nil` means the rights could not be taken — no lock directory, no file
    /// descriptor, or a peer still holding it when the bounded wait ran out.
    /// The caller then proceeds unserialized: a launch that hangs behind a
    /// wedged peer is worse than one that races, and the race is what this
    /// process was doing before the lock existed.
    var acquire: @Sendable (_ key: String) -> (@Sendable () -> Void)?
}

extension CacheVolumeLock {
    /// How long to wait for a peer that is already preparing. Long enough to
    /// cover the peer's chown container boot, short enough that a wedged peer
    /// delays a launch rather than owning it.
    static let defaultWaitSeconds: Double = 30

    /// Poll interval for the bounded wait. `flock` has no timed variant, so the
    /// wait is a non-blocking retry loop.
    static let defaultPollSeconds: Double = 0.05

    /// The lock file for a volume set, named after the volumes themselves.
    ///
    /// Keying on the volume names — not on the workspace — is what keeps
    /// unrelated workspaces from serializing against each other while still
    /// serializing the ones that share volumes. Under the default `.workspace`
    /// scope the names already carry the workspace identity, so two workspaces
    /// get two locks; under `--cache shared` every workspace uses the same
    /// global names, and they correctly land on one lock.
    ///
    /// Sorted before hashing so the key follows the set, not the order the
    /// caller happened to list it in. The hash is `WorkspaceIdentity`'s, reused
    /// rather than reinvented, and the hex output needs no path sanitizing.
    static func key(for volumes: [CacheVolume]) -> String {
        let names = volumes.map(\.name).sorted().joined(separator: "\n")
        return "cache-" + WorkspaceIdentity.fnv1a64Hex(names)
    }

    /// Advisory `flock(2)` on a file under spawn's state directory.
    ///
    /// - Parameters:
    ///   - directory: Where lock files live. `nil` resolves spawn's state
    ///     directory at acquisition time, so merely building the lock — which
    ///     the default argument of `prepareCacheVolumes` does — touches no
    ///     filesystem.
    ///   - waitSeconds: Upper bound on waiting for a peer before degrading to
    ///     unserialized preparation.
    ///   - pollSeconds: Retry interval while waiting.
    /// - Returns: a lock whose `acquire` yields a release closure, or `nil` when
    ///   the lock file is unusable or the wait ran out.
    static func hostFile(
        directory: URL? = nil,
        waitSeconds: Double = defaultWaitSeconds,
        pollSeconds: Double = defaultPollSeconds
    ) -> CacheVolumeLock {
        CacheVolumeLock { key in
            let lockDirectory = directory ?? Paths.stateDir.appendingPathComponent("locks")
            let path = lockFilePath(in: lockDirectory, key: key)
            guard let descriptor = openLockFile(at: path, in: lockDirectory) else { return nil }

            let deadline = Date().addingTimeInterval(max(0, waitSeconds))
            var warnedAboutWaiting = false
            while true {
                if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
                    return { close(descriptor) }
                }

                let failure = errno
                guard failure == EWOULDBLOCK || failure == EINTR else {
                    logger.warning("Could not lock \(path) (errno \(failure))")
                    close(descriptor)
                    return nil
                }
                guard Date() < deadline else {
                    logger.warning(
                        "Another spawn process has been preparing these cache volumes for more than \(String(format: "%g", waitSeconds))s; continuing without waiting."
                    )
                    close(descriptor)
                    return nil
                }
                if !warnedAboutWaiting {
                    warnedAboutWaiting = true
                    logger.debug("Waiting for another spawn process to finish preparing cache volumes")
                }
                Thread.sleep(forTimeInterval: max(0, pollSeconds))
            }
        }
    }

    /// The file a given key locks on. Exposed so a test can assert the lock
    /// lands where it claims to.
    static func lockFilePath(in directory: URL, key: String) -> String {
        directory.appendingPathComponent(key + ".lock").path
    }

    /// Open (creating if absent) the lock file, or `nil` if it cannot be
    /// opened. The file's contents are never read or written: only the lock the
    /// kernel attaches to it matters.
    private static func openLockFile(at path: String, in directory: URL) -> Int32? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            logger.warning("Could not create the lock directory \(directory.path): \(error.localizedDescription)")
            return nil
        }

        let descriptor = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            logger.warning("Could not open the lock file \(path) (errno \(errno))")
            return nil
        }
        return descriptor
    }
}
