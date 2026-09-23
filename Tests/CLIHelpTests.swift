import Testing

@testable import spawn

@Test func rootHelpCoversWorkspaceFirstLaunchModel() {
    let help = Spawn.helpMessage(columns: 100)

    #expect(help.contains("Quick start:"))
    #expect(help.contains("spawn codex"))
    #expect(help.contains("spawn -C ~/code/project"))
    #expect(help.contains("spawn -- cargo test"))
    #expect(help.contains("Runtime selection:"))
    #expect(help.contains("--runtime workspace-image"))
    #expect(help.contains("--backend native-experimental"))
    #expect(help.contains("Workspace defaults:"))
    #expect(help.contains(".spawn.toml [workspace]   Default agent; access and cache sharing require flags"))
    // Every run option a user is likely to reach for must be discoverable from
    // the front door, not only from `spawn help run`.
    #expect(help.contains("Common run options:"))
    for option in ["--yolo", "--access", "--cache", "--shell", "--toolchain"] {
        #expect(help.contains(option), "root help no longer lists \(option)")
    }
    #expect(help.contains("--cache <scope>"))
    #expect(help.contains("Bare invocations and run-style options route to `spawn run`."))
    #expect(help.contains("Use `spawn -- <command...>` for passthrough workspace commands."))
    #expect(help.contains("spawn help run"))
}

@Test func runHelpExplainsAccessRuntimeAndWorkspaceDefaults() {
    let help = Spawn.helpMessage(for: Spawn.Run.self, columns: 100)

    #expect(help.contains("Launch forms:"))
    #expect(help.contains("--access minimal"))
    #expect(help.contains("--runtime workspace-image"))
    #expect(help.contains("--rebuild-workspace-image"))
    #expect(help.contains("--backend cli"))
    #expect(help.contains("--backend native-experimental"))
    #expect(help.contains(".spawn.toml [workspace]        Default agent; access and cache sharing require flags"))
    #expect(help.contains("Safe mode is the default."))
    // Both scopes must be discoverable from help: the default is the safe one,
    // and a user cannot opt into sharing they were never told about.
    for scope in CacheScope.allCases {
        #expect(help.contains("--cache \(scope.rawValue)"))
    }
}

@Test func doctorHelpExplainsHumanAndJSONOutputs() {
    let help = Spawn.helpMessage(for: Spawn.Doctor.self, columns: 100)

    #expect(help.contains("spawn doctor -C ~/code/project"))
    #expect(help.contains("Human output covers:"))
    #expect(help.contains("container system readiness"))
    #expect(help.contains("default kernel and Rosetta readiness"))
    #expect(help.contains("workspace.defaults"))
    #expect(help.contains("workspace.runtime"))
    #expect(help.contains("-C, --cwd"))
}

@Test func imageAndBuildHelpExplainManagedImageScope() {
    let buildHelp = Spawn.helpMessage(for: Spawn.Build.self, columns: 100)
    #expect(buildHelp.contains("spawn-managed"))
    #expect(buildHelp.contains("spawn --runtime workspace-image"))

    let imageHelp = Spawn.helpMessage(for: Spawn.Image.self, columns: 100)
    #expect(imageHelp.contains("Workspace-image caches"))
}
