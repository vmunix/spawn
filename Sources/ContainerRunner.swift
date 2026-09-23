import Foundation

/// Owns Apple `container` CLI discovery, preflight, and raw operational commands.
enum ContainerRunner: Sendable {
    static func resolveExecutablePath(
        _ nameOrPath: String,
        searchPath: String? = ProcessInfo.processInfo.environment["PATH"]
    ) -> String? {
        if nameOrPath.contains("/") {
            return FileManager.default.isExecutableFile(atPath: nameOrPath) ? nameOrPath : nil
        }

        guard let searchPath, !searchPath.isEmpty else { return nil }
        for directory in searchPath.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(directory))
                .appendingPathComponent(nameOrPath)
                .path
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }

        return nil
    }

    static let containerPath: String = {
        if let envPath = ProcessInfo.processInfo.environment["CONTAINER_PATH"] {
            logger.debug("Using container path from CONTAINER_PATH: \(envPath)")
            return envPath
        }
        for path in ["/opt/homebrew/bin/container", "/usr/local/bin/container"] {
            if FileManager.default.fileExists(atPath: path) {
                logger.debug("Found container CLI at \(path)")
                return path
            }
        }
        logger.debug("Container CLI not found at known paths, falling back to PATH lookup")
        return "container"
    }()

    /// Tracks whether the default container path has passed preflight.
    private nonisolated(unsafe) static var defaultPreflightPassed = false

    /// Verify the container CLI binary exists and responds before any container operation.
    ///
    /// Two-phase check:
    /// 1. If the path is absolute, verify `FileManager.isExecutableFile(atPath:)`.
    /// 2. Run `<binary> --version` and check for a zero exit code.
    ///
    /// - Parameter path: Override for the container binary path (defaults to `Self.containerPath`).
    ///   Accepts a custom path for testing, matching the `storeRoot` pattern in `ImageChecker`.
    /// - Throws: `SpawnError.containerNotFound` if the binary is missing or not executable,
    ///   `SpawnError.runtimeError` if the binary exits non-zero.
    static func preflight(containerPath path: String? = nil) throws {
        let configuredBinary = path ?? containerPath

        // Skip re-checking the default path if it already passed.
        if path == nil, defaultPreflightPassed { return }

        guard let binary = resolveExecutablePath(configuredBinary) else {
            throw SpawnError.containerNotFound
        }

        // Phase 2: Run `container --version` to verify the runtime responds.
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = ["--version"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
        } catch {
            throw SpawnError.containerNotFound
        }
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw SpawnError.runtimeError(
                "Container CLI at '\(binary)' exited with status \(process.terminationStatus). "
                    + "Reinstall Apple's container tool or check your CONTAINER_PATH setting."
            )
        }

        if path == nil { defaultPreflightPassed = true }
    }

    /// Run a raw command against the container CLI (for exec, list, stop, etc.)
    static func runRaw(args: [String]) throws -> Int32 {
        try preflight()
        let binary = try resolvedContainerPath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError
        try process.run()
        process.waitUntilExit()
        return process.terminationStatus
    }

    /// Run a command against the container CLI and capture its stdout.
    static func runCapture(args: [String]) throws -> (status: Int32, output: String) {
        try preflight()
        let binary = try resolvedContainerPath()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.standardError
        try process.run()

        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let output = String(data: data, encoding: .utf8) ?? ""
        return (process.terminationStatus, output)
    }

    static func resolvedContainerPath() throws -> String {
        guard let binary = resolveExecutablePath(containerPath) else {
            throw SpawnError.containerNotFound
        }
        return binary
    }
}
