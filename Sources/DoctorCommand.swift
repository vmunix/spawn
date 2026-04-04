import ArgumentParser
import Foundation

extension Spawn {
    struct Doctor: ParsableCommand {
        private enum Status: Sendable {
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

        static let configuration = CommandConfiguration(
            abstract: "Check your spawn environment and current workspace.",
            discussion: """
                Examples:
                  spawn doctor
                  spawn doctor ~/code/project

                Checks the container CLI, local images, default config paths, and the
                workspace detection result spawn would use for a run.
                """
        )

        @Argument(
            help: "Directory to inspect as the workspace (default: current directory).",
            transform: { URL(fileURLWithPath: $0).standardizedFileURL }
        )
        var path: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).standardizedFileURL

        static func workspaceDetail(
            path: URL,
            inspection: ToolchainDetector.Inspection,
            workspaceConfig: WorkspaceConfig?
        ) -> String {
            let image = inspection.toolchain?.imageName ?? "spawn-base:latest"
            var detail: String

            switch inspection.source {
            case .spawnToml, .devcontainer:
                detail = "\(path.path) -> \(image) from \(inspection.source.detail)"
            case .devcontainerDockerfile:
                detail = workspaceRuntimeDetail(path: path, inspection: inspection)
            case .dockerfile:
                detail = workspaceRuntimeDetail(path: path, inspection: inspection)
            case .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
                detail = "\(path.path) -> \(image) (\(inspection.source.detail))"
            }

            var defaults: [String] = []
            if let agentName = workspaceConfig?.agentName {
                defaults.append("agent=\(agentName)")
            }
            if let accessName = workspaceConfig?.accessName {
                defaults.append("access=\(accessName)")
            }

            if !defaults.isEmpty {
                detail += " [workspace defaults: \(defaults.joined(separator: ", "))]"
            }

            return detail
        }

        private static func workspaceRuntimeDetail(path: URL, inspection: ToolchainDetector.Inspection) -> String {
            guard let plan = try? WorkspaceImageRuntime.plan(for: path) else {
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
            switch WorkspaceImageRuntime.cacheStatus(for: plan) {
            case .ready:
                buildState = "cached, up to date"
            case .notBuilt:
                buildState = "not built yet"
            case .stale(let reason):
                buildState = "rebuild needed: \(reason)"
            }
            switch inspection.source {
            case .devcontainerDockerfile:
                return
                    "\(path.path) uses .devcontainer/devcontainer.json with build.dockerfile -> \(plan.image) (\(buildState)). "
                    + "Use '--runtime workspace-image' to build and run it directly, or '--runtime spawn' to use spawn-managed images."
            case .dockerfile:
                return
                    "\(path.path) has a Dockerfile/Containerfile -> \(plan.image) (\(buildState)). "
                    + "Use '--runtime workspace-image' to build and run it directly, or '--runtime spawn' to use spawn-managed images."
            case .spawnToml, .devcontainer, .cargo, .goMod, .cmake, .bunLock, .denoConfig, .denoLock, .pnpmLock, .yarnLock, .packageLock, .packageJSON, .fallback:
                return "\(path.path) defines a workspace runtime -> \(plan.image) (\(buildState))"
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
                    status: .warning,
                    title: "Workspace",
                    detail: workspaceDetail(path: path, inspection: inspection, workspaceConfig: workspaceConfig)
                )
            case .dockerfile:
                return Check(
                    status: .warning,
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
            try Self.validateDirectory(at: path.path)

            do {
                try ContainerRunner.preflight()
                let (status, output) = try ContainerRunner.runCapture(args: ["--version"])
                if status == 0 {
                    Self.print(
                        Check(
                            status: .ok,
                            title: "Container CLI",
                            detail: "\(ContainerRunner.containerPath) (\(output.trimmingCharacters(in: .whitespacesAndNewlines)))"
                        ))
                } else {
                    Self.print(
                        Check(
                            status: .warning,
                            title: "Container CLI",
                            detail: "\(ContainerRunner.containerPath) responded with status \(status)"
                        ))
                }
            } catch {
                Self.print(
                    Check(
                        status: .error,
                        title: "Container CLI",
                        detail: String(describing: error)
                    ))
            }

            Self.print(Self.imageCheck())
            Self.print(Self.envCheck())
            Self.print(Self.workspaceCheck(at: path))
            for check in Self.stateChecks() {
                Self.print(check)
            }
        }
    }
}
