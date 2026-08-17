/// A fully resolved, backend-neutral container launch.
///
/// Policy, workspace inspection, image selection, cache preparation, and
/// command selection happen before this value is created. Runtime adapters
/// consume the resulting data without reaching back into CLI or repository
/// configuration.
struct ResolvedLaunchPlan: Sendable, Equatable {
    struct IOConfiguration: Sendable, Equatable {
        let keepStandardInputOpen: Bool
        let allocateTerminal: Bool
    }

    struct Resources: Sendable, Equatable {
        let cpus: Int
        let memory: String
    }

    let image: String
    let mounts: [Mount]
    let environment: [String: String]
    let workdir: String
    let entrypoint: [String]
    let resources: Resources
    let io: IOConfiguration
    let removeOnExit: Bool

    /// Resolve the final launch boundary for a workspace run.
    ///
    /// `resolvedMounts` starts with the primary workspace mount. Prepared build
    /// caches are appended here so the value handed to a runtime cannot report
    /// one mount set while launching with another.
    static func workspace(
        image: String,
        resolvedMounts: [Mount],
        preparedCacheMounts: [Mount],
        environment: [String: String],
        entrypoint: [String],
        cpus: Int,
        memory: String,
        allocateTerminal: Bool
    ) throws -> ResolvedLaunchPlan {
        guard let workspaceMount = resolvedMounts.first else {
            throw SpawnError.runtimeError("Cannot launch a workspace without a primary mount.")
        }

        return ResolvedLaunchPlan(
            image: image,
            mounts: resolvedMounts + preparedCacheMounts,
            environment: environment,
            workdir: workspaceMount.guestPath,
            entrypoint: entrypoint,
            resources: Resources(cpus: cpus, memory: memory),
            io: IOConfiguration(
                keepStandardInputOpen: true,
                allocateTerminal: allocateTerminal
            ),
            removeOnExit: true
        )
    }
}
