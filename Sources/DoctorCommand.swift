import ArgumentParser
import Foundation

extension Spawn {
    struct Doctor: ParsableCommand {
        struct SystemStatus: Sendable, Equatable {
            let status: String
            let appRoot: String?
        }

        enum Status: String, Codable, Sendable {
            case ok
            case warning
            case error

            var label: String {
                switch self {
                case .ok: "OK"
                case .warning: "WARN"
                case .error: "ERROR"
                }
            }
        }

        private struct Check: Sendable {
            let status: Status
            let title: String
            let detail: String
        }

        struct CheckReport: Codable, Sendable, Equatable {
            let status: Status
            let title: String
            let detail: String
        }

        struct WorkspaceDefaultsReport: Codable, Sendable, Equatable {
            let agent: String?
            let access: String?
        }

        struct WorkspaceRuntimeReport: Codable, Sendable, Equatable {
            let image: String
            let cacheStatus: String
            let cacheReason: String?
            let dockerfilePath: String
            let contextPath: String
            let configPath: String?
            let cacheRecordPath: String
        }

        struct WorkspaceReport: Codable, Sendable, Equatable {
            let path: String
            let source: String
            let detail: String
            let defaults: WorkspaceDefaultsReport?
            let runtime: WorkspaceRuntimeReport?
        }

        struct Report: Codable, Sendable, Equatable {
            let checks: [CheckReport]
            let workspace: WorkspaceReport
        }

        static let configuration = CommandConfiguration(
            abstract: "Check your spawn environment and current workspace.",
            discussion: """
                Examples:
                  spawn doctor
                  spawn doctor --json
                  spawn doctor -C ~/code/project
                  spawn doctor ~/code/project

                Human output covers:
                  container CLI availability
                  container system readiness
                  spawn-managed images
                  env file and persisted agent state
                  workspace detection, defaults, and runtime cache status

                JSON output adds:
                  checks[]               High-level health checks with status/title/detail
                  workspace              Structured workspace result
                  workspace.defaults     Configured workspace values from .spawn.toml
                  workspace.runtime      Workspace-image cache state and tracked paths
                """
        )

        @Option(name: [.customShort("C"), .long], help: "Directory to inspect as the workspace (default: current directory).")
        var cwd: String?

        @Argument(help: "Directory to inspect as the workspace (default: current directory).")
        var path: String?

        @Flag(name: .long, help: "Emit machine-readable JSON.")
        var json: Bool = false

        static func resolveWorkspacePath(
            cwd: String?,
            path: String?,
            currentDirectory: URL
        ) throws -> URL {
            if cwd != nil, path != nil {
                throw ValidationError("Use either '-C/--cwd' or a positional path with 'spawn doctor', not both.")
            }

            let selectedPath = cwd ?? path ?? currentDirectory.path
            return URL(fileURLWithPath: selectedPath).standardizedFileURL
        }

        static func parseSystemStatus(_ output: String) -> SystemStatus? {
            var fields: [String: String] = [:]

            for line in output.split(whereSeparator: \.isNewline) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty, !trimmed.hasPrefix("FIELD") else {
                    continue
                }

                let parts = trimmed.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
                guard let key = parts.first, parts.count == 2 else {
                    continue
                }
                fields[key] = parts[1].trimmingCharacters(in: CharacterSet.whitespaces)
            }

            guard let status = fields["status"], !status.isEmpty else {
                return nil
            }

            return SystemStatus(
                status: status,
                appRoot: fields["appRoot"]
            )
        }

        static func workspaceDetail(
            path: URL,
            inspection: ToolchainDetector.Inspection,
            workspaceConfig: WorkspaceConfig?,
            stateDir: URL = Paths.stateDir,
            storeRoot: URL? = nil
        ) -> String {
            let image = inspection.toolchain?.imageName ?? "spawn-base:latest"
            var detail: String

            switch inspection.source {
            case .spawnToml, .devcontainer:
                detail = "\(path.path) -> \(image) from \(inspection.source.detail)"
            case .devcontainerDockerfile:
                detail = workspaceRuntimeDetail(path: path, inspection: inspection, stateDir: stateDir, storeRoot: storeRoot)
            case .dockerfile:
                detail = workspaceRuntimeDetail(path: path, inspection: inspection, stateDir: stateDir, storeRoot: storeRoot)
            case .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
                detail = "\(path.path) -> \(image) (\(inspection.source.detail))"
            }

            var defaults: [String] = []
            if let agentName = workspaceConfig?.agentName {
                defaults.append("agent=\(agentName)")
            }
            if let accessName = workspaceConfig?.accessName {
                let explicitOptIn =
                    accessName == AccessProfile.minimal.rawValue
                    ? "access=\(accessName)"
                    : "access=\(accessName) (explicit --access required)"
                defaults.append(explicitOptIn)
            }

            if !defaults.isEmpty {
                detail += " [workspace config: \(defaults.joined(separator: ", "))]"
            }

            return detail
        }

        static func workspaceRuntimeCacheStatus(
            path: URL,
            inspection: ToolchainDetector.Inspection,
            stateDir: URL = Paths.stateDir,
            storeRoot: URL? = nil
        ) -> WorkspaceImageRuntime.CacheStatus? {
            guard
                inspection.source == .dockerfile || inspection.source == .devcontainerDockerfile,
                let plan = try? WorkspaceImageRuntime.plan(for: path, stateDir: stateDir)
            else {
                return nil
            }
            return WorkspaceImageRuntime.cacheStatus(for: plan, storeRoot: storeRoot)
        }

        static func workspaceRuntimeReport(
            path: URL,
            inspection: ToolchainDetector.Inspection,
            stateDir: URL = Paths.stateDir,
            storeRoot: URL? = nil
        ) -> WorkspaceRuntimeReport? {
            guard
                inspection.source == .dockerfile || inspection.source == .devcontainerDockerfile,
                let plan = try? WorkspaceImageRuntime.plan(for: path, stateDir: stateDir)
            else {
                return nil
            }

            let cacheStatus = WorkspaceImageRuntime.cacheStatus(for: plan, storeRoot: storeRoot)
            let cacheStatusName: String
            let cacheReason: String?
            switch cacheStatus {
            case .ready:
                cacheStatusName = "ready"
                cacheReason = nil
            case .notBuilt:
                cacheStatusName = "not_built"
                cacheReason = nil
            case .stale(let reason):
                cacheStatusName = "stale"
                cacheReason = reason
            }

            return WorkspaceRuntimeReport(
                image: plan.image,
                cacheStatus: cacheStatusName,
                cacheReason: cacheReason,
                dockerfilePath: plan.dockerfile.path,
                contextPath: plan.context.path,
                configPath: plan.configFile?.path,
                cacheRecordPath: plan.cacheRecord.path
            )
        }

        static func workspaceRuntimeDetail(
            path: URL,
            inspection: ToolchainDetector.Inspection,
            stateDir: URL = Paths.stateDir,
            storeRoot: URL? = nil
        ) -> String {
            guard let plan = try? WorkspaceImageRuntime.plan(for: path, stateDir: stateDir) else {
                switch inspection.source {
                case .devcontainerDockerfile:
                    return "\(path.path) uses .devcontainer/devcontainer.json with build.dockerfile, but spawn could not resolve the workspace-image build inputs."
                case .dockerfile:
                    return "\(path.path) has a Dockerfile/Containerfile, but spawn could not resolve the workspace-image build inputs."
                case .spawnToml, .devcontainer, .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
                    return "\(path.path) defines a workspace runtime, but spawn could not resolve it."
                }
            }

            let buildState: String
            switch WorkspaceImageRuntime.cacheStatus(for: plan, storeRoot: storeRoot) {
            case .ready:
                buildState = "cached, up to date"
            case .notBuilt:
                buildState = "not built yet"
            case .stale(let reason):
                buildState = "rebuild needed: \(reason)"
            }
            var trackedPaths = [
                "dockerfile=\(plan.dockerfile.path)",
                "context=\(plan.context.path)",
                "cache=\(plan.cacheRecord.path)",
            ]
            if let configFile = plan.configFile {
                trackedPaths.append("config=\(configFile.path)")
            }
            let trackedInputs = trackedPaths.joined(separator: "; ")

            switch inspection.source {
            case .devcontainerDockerfile:
                return
                    "\(path.path) uses .devcontainer/devcontainer.json with build.dockerfile -> \(plan.image) (\(buildState)); \(trackedInputs). "
                    + "Use '--runtime workspace-image' to build and run it directly, or '--runtime spawn' to use spawn-managed images."
            case .dockerfile:
                return
                    "\(path.path) has a Dockerfile/Containerfile -> \(plan.image) (\(buildState)); \(trackedInputs). "
                    + "Use '--runtime workspace-image' to build and run it directly, or '--runtime spawn' to use spawn-managed images."
            case .spawnToml, .devcontainer, .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
                return "\(path.path) defines a workspace runtime -> \(plan.image) (\(buildState)); \(trackedInputs)"
            }
        }

        private static func workspaceCheck(at path: URL) -> Check {
            let inspection = ToolchainDetector.inspect(in: path)
            let workspaceConfig = ToolchainDetector.loadWorkspaceConfig(in: path)

            switch inspection.source {
            case .spawnToml:
                return Check(
                    status: .ok,
                    title: "Workspace",
                    detail: workspaceDetail(path: path, inspection: inspection, workspaceConfig: workspaceConfig)
                )
            case .devcontainer:
                return Check(
                    status: .ok,
                    title: "Workspace",
                    detail: workspaceDetail(path: path, inspection: inspection, workspaceConfig: workspaceConfig)
                )
            case .devcontainerDockerfile:
                return Check(
                    status: workspaceRuntimeCacheStatus(path: path, inspection: inspection) == .ready ? .ok : .warning,
                    title: "Workspace",
                    detail: workspaceDetail(path: path, inspection: inspection, workspaceConfig: workspaceConfig)
                )
            case .dockerfile:
                return Check(
                    status: workspaceRuntimeCacheStatus(path: path, inspection: inspection) == .ready ? .ok : .warning,
                    title: "Workspace",
                    detail: workspaceDetail(path: path, inspection: inspection, workspaceConfig: workspaceConfig)
                )
            case .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
                return Check(
                    status: .ok,
                    title: "Workspace",
                    detail: workspaceDetail(path: path, inspection: inspection, workspaceConfig: workspaceConfig)
                )
            }
        }

        static func workspaceReport(
            path: URL,
            inspection: ToolchainDetector.Inspection,
            workspaceConfig: WorkspaceConfig?,
            stateDir: URL = Paths.stateDir,
            storeRoot: URL? = nil
        ) -> WorkspaceReport {
            let defaults: WorkspaceDefaultsReport?
            if workspaceConfig?.agentName != nil || workspaceConfig?.accessName != nil {
                defaults = WorkspaceDefaultsReport(
                    agent: workspaceConfig?.agentName,
                    access: workspaceConfig?.accessName
                )
            } else {
                defaults = nil
            }

            return WorkspaceReport(
                path: path.path,
                source: inspection.source.identifier,
                detail: workspaceDetail(
                    path: path,
                    inspection: inspection,
                    workspaceConfig: workspaceConfig,
                    stateDir: stateDir,
                    storeRoot: storeRoot
                ),
                defaults: defaults,
                runtime: workspaceRuntimeReport(
                    path: path,
                    inspection: inspection,
                    stateDir: stateDir,
                    storeRoot: storeRoot
                )
            )
        }

        private static func report(
            checks: [Check],
            workspace: WorkspaceReport
        ) -> Report {
            Report(
                checks: checks.map { check in
                    CheckReport(
                        status: check.status,
                        title: check.title,
                        detail: check.detail
                    )
                },
                workspace: workspace
            )
        }

        static func renderJSON(_ report: Report) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(report)
            guard let string = String(data: data, encoding: .utf8) else {
                throw SpawnError.runtimeError("Failed to encode doctor JSON output.")
            }
            return string
        }

        private static func imageCheck() -> Check {
            let images = ImageChecker.availableSpawnImages()
            if images.isEmpty {
                return Check(
                    status: .warning,
                    title: "Images",
                    detail: "No spawn images found. Run 'spawn build' to create them."
                )
            }

            return Check(
                status: .ok,
                title: "Images",
                detail: "\(images.count) spawn image\(images.count == 1 ? "" : "s") available: \(images.joined(separator: ", "))"
            )
        }

        private static func containerSystemCheck() -> Check {
            do {
                let (status, output) = try ContainerRunner.runCapture(args: ["system", "status"])
                if status != 0 {
                    return Check(
                        status: .warning,
                        title: "Container system",
                        detail: "Container services did not report healthy status. Try 'container system start --enable-kernel-install'."
                    )
                }

                guard let systemStatus = parseSystemStatus(output) else {
                    return Check(
                        status: .warning,
                        title: "Container system",
                        detail: "Container services responded, but spawn could not parse 'container system status'."
                    )
                }

                if systemStatus.status == "running" {
                    var detail = "running"
                    if let appRoot = systemStatus.appRoot, !appRoot.isEmpty {
                        detail += " (\(appRoot))"
                    }

                    return Check(
                        status: .ok,
                        title: "Container system",
                        detail: detail
                    )
                }

                return Check(
                    status: .warning,
                    title: "Container system",
                    detail: "status=\(systemStatus.status). Run 'container system start --enable-kernel-install' if this machine has not been initialized yet."
                )
            } catch {
                return Check(
                    status: .warning,
                    title: "Container system",
                    detail: "Unable to inspect container services: \(error)"
                )
            }
        }

        private static func envCheck() -> Check {
            let envPath = Paths.configDir.appendingPathComponent("env")
            guard FileManager.default.fileExists(atPath: envPath.path) else {
                return Check(
                    status: .warning,
                    title: "Env file",
                    detail: "No default env file at \(envPath.path)"
                )
            }

            let count = EnvLoader.loadDefault().count
            return Check(
                status: .ok,
                title: "Env file",
                detail: "\(envPath.path) (\(count) variable\(count == 1 ? "" : "s"))"
            )
        }

        private static func stateChecks() -> [Check] {
            ["claude-code", "codex"].map { agent in
                let statePath = Paths.stateDir.appendingPathComponent(agent)
                if FileManager.default.fileExists(atPath: statePath.path) {
                    return Check(
                        status: .ok,
                        title: "\(agent) state",
                        detail: statePath.path
                    )
                }

                return Check(
                    status: .warning,
                    title: "\(agent) state",
                    detail: "No persisted state at \(statePath.path) yet"
                )
            }
        }

        private static func validateDirectory(at path: String) throws {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
                throw ValidationError("Path does not exist: \(path)")
            }
            guard isDir.boolValue else {
                throw ValidationError("Path is not a directory: \(path)")
            }
        }

        private static func print(_ check: Check) {
            Swift.print("[\(check.status.label)] \(check.title): \(check.detail)")
        }

        mutating func run() throws {
            let workspace = try Self.resolveWorkspacePath(
                cwd: cwd,
                path: path,
                currentDirectory: URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL
            )
            try Self.validateDirectory(at: workspace.path)
            let inspection = ToolchainDetector.inspect(in: workspace)
            let workspaceConfig = ToolchainDetector.loadWorkspaceConfig(in: workspace)
            var checks: [Check] = []

            do {
                try ContainerRunner.preflight()
                let (status, output) = try ContainerRunner.runCapture(args: ["--version"])
                if status == 0 {
                    checks.append(
                        Check(
                            status: .ok,
                            title: "Container CLI",
                            detail: "\(ContainerRunner.containerPath) (\(output.trimmingCharacters(in: .whitespacesAndNewlines)))"
                        ))
                } else {
                    checks.append(
                        Check(
                            status: .warning,
                            title: "Container CLI",
                            detail: "\(ContainerRunner.containerPath) responded with status \(status)"
                        ))
                }
                checks.append(Self.containerSystemCheck())
            } catch {
                checks.append(
                    Check(
                        status: .error,
                        title: "Container CLI",
                        detail: String(describing: error)
                    ))
            }

            checks.append(Self.imageCheck())
            checks.append(Self.envCheck())
            checks.append(Self.workspaceCheck(at: workspace))
            checks.append(contentsOf: Self.stateChecks())

            let workspaceReport = Self.workspaceReport(
                path: workspace,
                inspection: inspection,
                workspaceConfig: workspaceConfig
            )

            if json {
                Swift.print(try Self.renderJSON(Self.report(checks: checks, workspace: workspaceReport)))
                return
            }

            for check in checks {
                Self.print(check)
            }
        }
    }
}
