import Foundation

/// A backend capable of launching a fully resolved container workload.
///
/// This boundary deliberately contains only semantic launch data. Operational
/// commands and backend-specific process or argument representations stay in
/// their adapters.
protocol ContainerRuntime: Sendable {
    /// A runtime may replace the current process and never return. Callers must
    /// not rely on code after this method executing.
    func launch(_ plan: ResolvedLaunchPlan) async throws -> Int32
}

/// Constructs runtimes after CLI policy has selected a backend. Keeping this
/// seam injectable makes the selector-to-launch wiring independently testable.
protocol ContainerRuntimeFactory: Sendable {
    func makeRuntime(
        for backend: ContainerBackend,
        stateDir: URL
    ) throws -> any ContainerRuntime
}

struct ProductionContainerRuntimeFactory: ContainerRuntimeFactory {
    func makeRuntime(
        for backend: ContainerBackend,
        stateDir: URL
    ) throws -> any ContainerRuntime {
        switch backend {
        case .cli:
            AppleContainerCLIRuntime()
        case .nativeExperimental:
            NativeContainerRuntime(stateRoot: stateDir.appendingPathComponent("native-runtime"))
        }
    }
}
