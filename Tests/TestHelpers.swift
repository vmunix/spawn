import Foundation

/// Helper: create a file URL from a path string
func fileURL(_ path: String) -> URL {
    URL(fileURLWithPath: path)
}

nonisolated(unsafe) private var hasCleanedUp = false

/// Helper: create a temp directory with specified files
func makeTempDir(files: [String: String]) throws -> URL {
    // Clean up old test directories on first call per test run
    if !hasCleanedUp {
        hasCleanedUp = true
        let tmpDir = URL(fileURLWithPath: NSTemporaryDirectory())
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpDir, includingPropertiesForKeys: nil
        ) {
            for item in contents where item.lastPathComponent.hasPrefix("ccc-test-") {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    let base = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("ccc-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
    for (path, content) in files {
        let fileURL = base.appendingPathComponent(path)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try content.write(to: fileURL, atomically: true, encoding: .utf8)
    }
    return base
}
