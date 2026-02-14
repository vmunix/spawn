import Foundation

enum ContainerRunner {
    static let containerPath = "/usr/local/bin/container"

    static func buildArgs(
        image: String,
        mounts: [Mount],
        env: [String: String],
        workdir: String,
        entrypoint: [String],
        cpus: Int,
        memory: String
    ) -> [String] {
        var args = ["run", "--rm"]

        // Resources
        args += ["--cpus", "\(cpus)"]
        args += ["--memory", "\(memory)"]

        // Mounts
        for mount in mounts {
            let spec = mount.readOnly
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
