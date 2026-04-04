import Testing

@testable import spawn

@Test func rootHelpCoversWorkspaceFirstLaunchModel() {
    let help = Spawn.helpMessage(columns: 100)

    #expect(help.contains("Quick start:"))
    #expect(help.contains("spawn -- cargo test"))
    #expect(help.contains("Runtime selection:"))
    #expect(help.contains("--runtime workspace-image"))
    #expect(help.contains("Workspace defaults:"))
    #expect(help.contains(".spawn.toml [workspace]"))
    #expect(help.contains("spawn help run"))
}

@Test func runHelpExplainsAccessRuntimeAndWorkspaceDefaults() {
    let help = Spawn.helpMessage(for: Spawn.Run.self, columns: 100)

    #expect(help.contains("Launch forms:"))
    #expect(help.contains("--access minimal"))
    #expect(help.contains("--runtime workspace-image"))
    #expect(help.contains("--rebuild-workspace-image"))
    #expect(help.contains(".spawn.toml [workspace]"))
    #expect(help.contains("Safe mode is the default."))
}

@Test func doctorHelpExplainsHumanAndJSONOutputs() {
    let help = Spawn.helpMessage(for: Spawn.Doctor.self, columns: 100)

    #expect(help.contains("Human output covers:"))
    #expect(help.contains("workspace.defaults"))
    #expect(help.contains("workspace.runtime"))
}

@Test func imageAndBuildHelpExplainManagedImageScope() {
    let buildHelp = Spawn.helpMessage(for: Spawn.Build.self, columns: 100)
    #expect(buildHelp.contains("spawn-managed"))
    #expect(buildHelp.contains("spawn --runtime workspace-image"))

    let imageHelp = Spawn.helpMessage(for: Spawn.Image.self, columns: 100)
    #expect(imageHelp.contains("Workspace-image caches"))
}
