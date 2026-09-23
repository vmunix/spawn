import Foundation

/// Launches resolved workloads through Apple's `container` CLI.
struct AppleContainerCLIRuntime: ContainerRuntime {
    /// Render a launch plan as `container run` arguments. Pure and deterministic.
    static func buildArgs(for plan: ResolvedLaunchPlan) -> [String] {
        var args = ["run"]

        if plan.removeOnExit {
            args.append("--rm")
        }
        if plan.io.keepStandardInputOpen {
            args.append("-i")
        }
        if plan.io.allocateTerminal {
            args.append("-t")
        }

        args += ["--cpus", "\(plan.resources.cpus)"]
        args += ["--memory", plan.resources.memory]

        for mount in plan.mounts {
            let spec =
                mount.readOnly
                ? "\(mount.hostPath):\(mount.guestPath):ro"
                : "\(mount.hostPath):\(mount.guestPath)"
            args += ["--volume", spec]
        }

        for (key, value) in plan.environment.sorted(by: { $0.key < $1.key }) {
            args += ["--env", "\(key)=\(value)"]
        }

        args += ["--workdir", plan.workdir]
        args.append(plan.image)
        args += plan.entrypoint

        return args
    }

    /// Preserve direct terminal ownership for interactive launches and signal
    /// forwarding for child-process launches.
    func launch(_ plan: ResolvedLaunchPlan) async throws -> Int32 {
        try ContainerRunner.preflight()
        let binary = try ContainerRunner.resolvedContainerPath()
        let args = Self.buildArgs(for: plan)

        let cmd = ([binary] + Self.sanitizeForLogging(args)).joined(separator: " ")
        logger.debug("+ \(cmd)")

        if plan.io.allocateTerminal {
            let cArgs = [binary] + args
            let cStrings: [UnsafeMutablePointer<CChar>?] = cArgs.map { strdup($0) }
            let argv = cStrings + [nil]
            execv(binary, argv)
            perror("execv")
            return 1
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binary)
        process.arguments = args
        process.standardInput = plan.io.keepStandardInputOpen ? FileHandle.standardInput : FileHandle.nullDevice
        process.standardOutput = FileHandle.standardOutput
        process.standardError = FileHandle.standardError

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

    /// Redact environment values from verbose command logs.
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
}
