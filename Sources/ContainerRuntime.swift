/// A backend capable of launching a fully resolved container workload.
///
/// This boundary deliberately contains only semantic launch data. Operational
/// commands and backend-specific process or argument representations stay in
/// their adapters.
protocol ContainerRuntime: Sendable {
    /// A runtime may replace the current process and never return. Callers must
    /// not rely on code after this method executing.
    func launch(_ plan: ResolvedLaunchPlan) throws -> Int32
}

/// Owns production runtime selection so command resolution depends only on the
/// semantic protocol.
enum ContainerRuntimes: Sendable {
    static func defaultRuntime() -> any ContainerRuntime {
        AppleContainerCLIRuntime()
    }
}
