import Foundation
import Testing

@testable import spawn

@Test func nativeCacheSnapshotDoesNotCreateStateAndUsesAllocatedSize() throws {
    let parent = try makeTempDir(files: [:])
    let root = parent.appendingPathComponent("native-runtime")
    let store = NativeCacheStore(stateRoot: root)

    #expect(try store.snapshot() == NativeCacheStore.Snapshot(path: root.path, entries: []))
    #expect(!FileManager.default.fileExists(atPath: root.path))

    let current = store.currentRoot
    try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
    let sparse = current.appendingPathComponent("sparse.ext4")
    #expect(FileManager.default.createFile(atPath: sparse.path, contents: Data([42])))
    let handle = try FileHandle(forWritingTo: sparse)
    try handle.truncate(atOffset: 64 * 1024 * 1024)
    try handle.close()

    let snapshot = try store.snapshot()
    #expect(snapshot.entries.count == 1)
    #expect(snapshot.entries.first?.name == "containerization-0.45.0")
    #expect(snapshot.entries.first?.isCurrent == true)
    #expect(snapshot.entries.first?.isPendingDeletion == false)
    #expect(snapshot.allocatedBytes > 0)
    #expect(snapshot.allocatedBytes < 64 * 1024 * 1024)
}

@Test func nativeCacheCleanRefusesWhileLaunchLeaseIsHeld() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("native-runtime")
    let store = NativeCacheStore(stateRoot: root)
    var lease: NativeCacheFileLock? = try store.acquireLaunchLease()
    try FileManager.default.createDirectory(at: store.currentRoot, withIntermediateDirectories: false)

    #expect(lease != nil)
    #expect(throws: SpawnError.self) {
        _ = try store.cleanCurrent()
    }
    #expect(FileManager.default.fileExists(atPath: store.currentRoot.path))

    lease = nil
    _ = try store.cleanCurrent()
    #expect(!FileManager.default.fileExists(atPath: store.currentRoot.path))
}

@Test func nativeCacheCleanRemovesOnlyTheCurrentVersion() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("native-runtime")
    let store = NativeCacheStore(stateRoot: root)
    try store.prepareRoot()
    let olderVersion = root.appendingPathComponent("containerization-0.41.0")
    let legacyImages = root.appendingPathComponent("images")
    for directory in [store.currentRoot, olderVersion, legacyImages] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        try Data(repeating: 42, count: 4096).write(
            to: directory.appendingPathComponent("content")
        )
    }

    let removedBytes = try store.cleanCurrent()

    #expect(removedBytes > 0)
    #expect(!FileManager.default.fileExists(atPath: store.currentRoot.path))
    #expect(FileManager.default.fileExists(atPath: olderVersion.path))
    #expect(FileManager.default.fileExists(atPath: legacyImages.path))
    #expect(FileManager.default.fileExists(atPath: root.appendingPathComponent("lifecycle.lock").path))
}

@Test func nativeCacheCleanDryRunMeasuresWithoutRemovingArtifacts() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("native-runtime")
    let store = NativeCacheStore(stateRoot: root)
    try FileManager.default.createDirectory(at: store.currentRoot, withIntermediateDirectories: true)
    try Data(repeating: 42, count: 4096).write(
        to: store.currentRoot.appendingPathComponent("content")
    )
    let before = try store.snapshot()

    #expect(try store.cleanCurrent(dryRun: true) == before.allocatedBytes)
    #expect(try store.snapshot() == before)
    #expect(FileManager.default.fileExists(atPath: store.currentRoot.path))
}

@Test func nativeCacheCleanRetriesAnInterruptedRemoval() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("native-runtime")
    let store = NativeCacheStore(stateRoot: root)
    try store.prepareRoot()
    let pending = root.appendingPathComponent(
        store.currentRoot.lastPathComponent + ".deleting-interrupted"
    )
    try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: false)
    try Data(repeating: 42, count: 4096).write(to: pending.appendingPathComponent("content"))

    let before = try store.snapshot()
    #expect(before.entries.first?.isPendingDeletion == true)
    #expect(try store.cleanCurrent() > 0)
    #expect(!FileManager.default.fileExists(atPath: pending.path))
}

@Test func nativeCacheCleanRefusesToFollowAReplacedCurrentDirectory() throws {
    let parent = try makeTempDir(files: [:])
    let root = parent.appendingPathComponent("native-runtime")
    let outside = parent.appendingPathComponent("outside")
    let store = NativeCacheStore(stateRoot: root)
    try store.prepareRoot()
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
    try FileManager.default.createSymbolicLink(at: store.currentRoot, withDestinationURL: outside)

    #expect(throws: SpawnError.self) {
        _ = try store.cleanCurrent()
    }
    #expect(FileManager.default.fileExists(atPath: outside.path))
}
