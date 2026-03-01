import Foundation

/// Invokes Apple's `container` CLI to run, exec, and manage containers.
enum ContainerRunner: Sendable {
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
        let binary = path ?? containerPath

        // Skip re-checking the default path if it already passed.
        if path == nil, defaultPreflightPassed { return }

        // Phase 1: If the path is absolute, check that it exists and is executable.
        if binary.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: binary) else {
                throw SpawnError.containerNotFound
            }
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

    /// Build the argument array for `container run`. Pure function — no side effects.
    static func buildArgs(
        image: String,
        mounts: [Mount],
        env: [String: String],
        workdir: String,
        entrypoint: [String],
        cpus: Int,
        memory: String
    ) -> [String] {
        var args = ["run", "--rm", "-i"]

        // Allocate a TTY when stdin is a real terminal.
        // This is required for interactive use (unbuffered output, line editing).
        // Apple's container CLI v0.9.0 requires a real host TTY for -t to work.
        if isatty(STDIN_FILENO) != 0 {
            args.append("-t")
        }

        // Resources
        args += ["--cpus", "\(cpus)"]
        args += ["--memory", "\(memory)"]

        // Mounts
        for mount in mounts {
            let spec =
                mount.readOnly
                ? "\(mount.hostPath):\(mount.guestPath):ro"
                : "\(mount.hostPath):\(mount.guestPath)"
            args += ["--volume", spec]
        }

        // Environment (sorted for deterministic output)
        for (key, value) in env.sorted(by: { $0.key < $1.key }) {
            args += ["--env", "\(key)=\(value)"]
        }

        // Working directory
        args += ["--workdir", workdir]

        // Image
        args.append(image)

        // Entrypoint / command
        args += entrypoint

        return args
    }

    /// Launch a container. Uses `execv` when stdin is a TTY (for direct terminal access),
    /// falls back to `Foundation.Process` with signal forwarding otherwise.
    static func run(
        image: String,
        mounts: [Mount],
        env: [String: String],
        workdir: String,
        entrypoint: [String],
        cpus: Int,
        memory: String
    ) throws -> Int32 {
        try preflight()

        let args = buildArgs(
            image: image, mounts: mounts, env: env,
            workdir: workdir, entrypoint: entrypoint,
            cpus: cpus, memory: memory
        )

        let cmd = ([containerPath] + sanitizeForLogging(args)).joined(separator: " ")
        logger.debug("+ \(cmd)")

        // When stdin is a TTY, replace our process with `container` via execv.
        // This gives the container CLI direct terminal access (needed for -t flag,
        // raw mode, and proper interactive I/O). No intermediary process.
        if isatty(STDIN_FILENO) != 0 {
            let cArgs = [containerPath] + args
            let cStrings: [UnsafeMutablePointer<CChar>?] = cArgs.map { strdup($0) }
            let argv = cStrings + [nil]
            execv(containerPath, argv)
            // execv only returns on failure
            perror("execv")
            return 1
        }

        // Non-TTY path: use Foundation.Process with signal forwarding
        let process = Process()
        process.executableURL = URL(fileURLWithPath: containerPath)
        process.arguments = args
        process.standardInput = FileHandle.standardInput
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

        // Signal forwarding
        signal(SIGINT, SIG_IGN)
        signal(SIGTERM, SIG_IGN)

        let sigintSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
        sigintSource.setEventHandler {
            if process.isRunning { kill(process.processIdentifier, SIGINT) }
        }
        sigintSource.resume()

        let sigtermSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        sigtermSource.setEventHandler {
            if process.isRunning { kill(process.processIdentifier, SIGTERM) }
        }
        sigtermSource.resume()

        try process.run()
        process.waitUntilExit()

        sigintSource.cancel()
        sigtermSource.cancel()
        signal(SIGINT, SIG_DFL)
        signal(SIGTERM, SIG_DFL)

        return process.terminationStatus
    }

    /// Return a copy of the args array with `--env` values redacted for safe logging.
    /// Each `"--env"` flag is followed by `"KEY=VALUE"`; the value portion is replaced with `***`.
    private static func sanitizeForLogging(_ args: [String]) -> [String] {
        var sanitized: [String] = []
        var redactNext = false
        for arg in args {
            if redactNext {
                if let eqIndex = arg.firstIndex(of: "=") {
                    sanitized.append(String(arg[...eqIndex]) + "***")
                } else {
                    sanitized.append(arg)
                }
                redactNext = false
            } else {
                sanitized.append(arg)
                redactNext = (arg == "--env")
            }
        }
        return sanitized
    }

    /// Run a raw command against the container CLI (for exec, list, stop, etc.)
    static func runRaw(args: [String]) throws -> Int32 {
        try preflight()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: containerPath)
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

        let process = Process()
        process.executableURL = URL(fileURLWithPath: containerPath)
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
}
