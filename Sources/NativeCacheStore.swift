import Darwin
import Foundation

/// Spawn-owned artifacts for the experimental library backend. A launch holds
/// the lifecycle lock shared until its VM and per-launch clone are gone;
/// explicit cleanup needs the lock exclusively and fails instead of waiting.
struct NativeCacheStore: Sendable {
    struct Entry: Codable, Equatable, Sendable {
        let name: String
        let path: String
        let allocatedBytes: UInt64
        let isCurrent: Bool
        let isPendingDeletion: Bool
    }

    struct Snapshot: Codable, Equatable, Sendable {
        let path: String
        let entries: [Entry]
        let allocatedBytes: UInt64

        init(path: String, entries: [Entry]) {
            self.path = path
            self.entries = entries
            allocatedBytes = entries.reduce(0) { total, entry in
                let (sum, overflow) = total.addingReportingOverflow(entry.allocatedBytes)
                return overflow ? UInt64.max : sum
            }
        }
    }

    let stateRoot: URL

    var currentRoot: URL {
        stateRoot.appendingPathComponent("containerization-\(NativeContainerRuntime.libraryVersion)")
    }

    private var lifecycleLockPath: URL {
        stateRoot.appendingPathComponent("lifecycle.lock")
    }

    private var deletionPrefix: String {
        currentRoot.lastPathComponent + ".deleting-"
    }

    func prepareRoot() throws {
        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: stateRoot,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: stateRoot.path
        )
    }

    func acquireLaunchLease() throws -> NativeCacheFileLock {
        try prepareRoot()
        return try NativeCacheFileLock(path: lifecycleLockPath, operation: LOCK_SH)
    }

    /// Read-only, approximate allocated size. Sparse file logical lengths are
    /// deliberately not used; APFS clones can still share physical blocks.
    func snapshot() throws -> Snapshot {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: stateRoot.path) else {
            return Snapshot(path: stateRoot.path, entries: [])
        }

        let candidates = try fileManager.contentsOfDirectory(
            at: stateRoot,
            includingPropertiesForKeys: nil
        ).filter { url in
            url.lastPathComponent.hasPrefix("containerization-")
                || url.lastPathComponent == "images"
                || url.lastPathComponent == "rootfs"
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }

        let entries = try candidates.map { url in
            Entry(
                name: url.lastPathComponent,
                path: url.path,
                allocatedBytes: try Self.allocatedBytes(at: url),
                isCurrent: url.lastPathComponent == currentRoot.lastPathComponent,
                isPendingDeletion: url.lastPathComponent.hasPrefix(deletionPrefix)
            )
        }
        return Snapshot(path: stateRoot.path, entries: entries)
    }

    /// Reset only artifacts written by this version. Older binaries never held
    /// the lifecycle lock, so their unversioned cache cannot be safely removed
    /// by this command while one of those binaries might still be running.
    func cleanCurrent(dryRun: Bool = false) throws -> UInt64 {
        try prepareRoot()
        let lock = try NativeCacheFileLock(
            path: lifecycleLockPath,
            operation: LOCK_EX | LOCK_NB
        )
        defer { _ = lock }

        let fileManager = FileManager.default
        var deletionPaths = try fileManager.contentsOfDirectory(
            at: stateRoot,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix(deletionPrefix) }

        var info = stat()
        var currentExists = false
        if lstat(currentRoot.path, &info) == 0 {
            guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
                throw SpawnError.runtimeError(
                    "Refusing to clean native cache because \(currentRoot.path) is not a directory."
                )
            }
            currentExists = true
        } else if errno != ENOENT {
            throw Self.filesystemError("Cannot inspect native cache", at: currentRoot)
        }

        let measuredPaths = deletionPaths + (currentExists ? [currentRoot] : [])
        var allocatedBytes: UInt64 = 0
        for path in measuredPaths {
            let bytes = try Self.allocatedBytes(at: path)
            let (sum, overflow) = allocatedBytes.addingReportingOverflow(bytes)
            allocatedBytes = overflow ? UInt64.max : sum
        }
        if dryRun { return allocatedBytes }

        if currentExists {
            // Move first: an interrupted recursive removal cannot leave a
            // partially deleted cache at the path the next launch reuses.
            let deletionPath = stateRoot.appendingPathComponent(
                deletionPrefix + UUID().uuidString.lowercased()
            )
            try fileManager.moveItem(at: currentRoot, to: deletionPath)
            deletionPaths.append(deletionPath)
        }

        for path in deletionPaths {
            try fileManager.removeItem(at: path)
        }
        return allocatedBytes
    }

    private static func allocatedBytes(at url: URL) throws -> UInt64 {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw filesystemError("Cannot inspect native cache", at: url)
        }
        let blocks = UInt64(max(info.st_blocks, 0))
        let (ownBytes, overflow) = blocks.multipliedReportingOverflow(by: 512)
        if overflow { return UInt64.max }
        guard (info.st_mode & mode_t(S_IFMT)) == mode_t(S_IFDIR) else {
            return ownBytes
        }

        let children = try FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil
        )
        return try children.reduce(ownBytes) { total, child in
            let childBytes = try allocatedBytes(at: child)
            let (sum, overflow) = total.addingReportingOverflow(childBytes)
            return overflow ? UInt64.max : sum
        }
    }

    private static func filesystemError(_ message: String, at url: URL) -> SpawnError {
        SpawnError.runtimeError("\(message) at \(url.path): \(String(cString: strerror(errno)))")
    }
}

/// A POSIX advisory lock kept on disk outside versioned cache directories.
/// The descriptor's lifetime, rather than an unlock call, bounds the lease.
final class NativeCacheFileLock {
    private let descriptor: Int32

    init(path: URL, operation: Int32) throws {
        let descriptor = open(path.path, O_CREAT | O_RDWR | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else {
            throw SpawnError.runtimeError(
                "Cannot open native cache lock at \(path.path): \(String(cString: strerror(errno)))"
            )
        }
        guard flock(descriptor, operation) == 0 else {
            let failedBecauseBusy = errno == EWOULDBLOCK
            let message = String(cString: strerror(errno))
            close(descriptor)
            if failedBecauseBusy {
                throw SpawnError.runtimeError(
                    "Native cache is in use by an active launch; retry cleanup after it exits."
                )
            }
            throw SpawnError.runtimeError(
                "Cannot lock native cache at \(path.path): \(message)"
            )
        }
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}
