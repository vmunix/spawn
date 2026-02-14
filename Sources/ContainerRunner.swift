import Foundation

enum ContainerRunner {
    static let containerPath: String = {
        for path in ["/opt/homebrew/bin/container", "/usr/local/bin/container"] {
            if FileManager.default.fileExists(atPath: path) { return path }
        }
        return "container"  // hope it's on PATH
    }()

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

    static func run(
        image: String,
        mounts: [Mount],
        env: [String: String],
        workdir: String,
        entrypoint: [String],
        cpus: Int,
        memory: String,
        verbose: Bool
    ) throws -> Int32 {
        let args = buildArgs(
            image: image, mounts: mounts, env: env,
            workdir: workdir, entrypoint: entrypoint,
            cpus: cpus, memory: memory
        )

        if verbose {
            let cmd = ([containerPath] + args).joined(separator: " ")
            FileHandle.standardError.write(Data("+ \(cmd)\n".utf8))
        }

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

    /// Run a raw command against the container CLI (for exec, list, stop, etc.)
    static func runRaw(args: [String]) throws -> Int32 {
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
}
