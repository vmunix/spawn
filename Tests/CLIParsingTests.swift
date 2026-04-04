import Foundation
import Testing

@testable import spawn

@Test func rewrittenArgumentsPreserveDirectSubcommands() {
    #expect(Spawn.rewrittenArguments(["doctor", "--json"]) == ["doctor", "--json"])
    #expect(Spawn.rewrittenArguments(["run", "--", "cargo", "test"]) == ["run", "--", "cargo", "test"])
}

@Test func rewrittenArgumentsRouteBareInvocationToRun() {
    #expect(Spawn.rewrittenArguments([]) == ["run"])
}

@Test func rewrittenArgumentsConvertAgentShortcutIntoRunOption() {
    #expect(Spawn.rewrittenArguments(["codex"]) == ["run", "--agent", "codex"])
    #expect(Spawn.rewrittenArguments(["claude-code", "--verbose"]) == ["run", "--agent", "claude-code", "--verbose"])
}

@Test func rewrittenArgumentsLeaveWorkspaceFirstPassthroughAlone() {
    #expect(Spawn.rewrittenArguments(["--", "cargo", "test"]) == ["run", "--", "cargo", "test"])
    #expect(Spawn.rewrittenArguments(["-C", "/tmp/project", "--", "swift", "test"]) == ["run", "-C", "/tmp/project", "--", "swift", "test"])
}

@Test func rewrittenArgumentsPreserveRootHelpAndVersionFlags() {
    #expect(Spawn.rewrittenArguments(["--help"]) == ["--help"])
    #expect(Spawn.rewrittenArguments(["-h"]) == ["-h"])
    #expect(Spawn.rewrittenArguments(["--version"]) == ["--version"])
}

@Test func rootRoutingRejectsImplicitWorkspaceCommands() {
    let error = Spawn.rootRoutingError(for: ["cargo", "test"])

    #expect(error?.message.contains("spawn -- <command...>") == true)
}

@Test func rootRoutingGuidesWorkspacePathsToCwdFlag() throws {
    let workspace = try makeTempDir(files: [:])
    let error = Spawn.rootRoutingError(for: [workspace.path])

    #expect(error?.message.contains("Workspace paths are selected with -C/--cwd") == true)
}

@Test func runParserAcceptsUppercaseCwdShortOption() throws {
    let command = try Spawn.Run.parseAsRoot(["-C", "/tmp/project", "--shell"])
    guard let parsed = command as? Spawn.Run else {
        Issue.record("Expected Spawn.Run from parseAsRoot")
        return
    }

    #expect(parsed.cwd == "/tmp/project")
    #expect(parsed.shell == true)
}

@Test func rootRoutingDefaultsToRunCommand() throws {
    let command = try Spawn.parseAsRoot(Spawn.rewrittenArguments([]))
    #expect(command is Spawn.Run)
}

@Test func rootRoutingParsesBarePassthroughCommand() throws {
    let command = try Spawn.parseAsRoot(Spawn.rewrittenArguments(["--", "cargo", "test"]))
    guard var parsed = command as? Spawn.Run else {
        Issue.record("Expected Spawn.Run from parseAsRoot")
        return
    }
    parsed.command = Spawn.Run.normalizedCommand(parsed.command)

    #expect(parsed.command == ["cargo", "test"])
    #expect(parsed.agent == nil)
    #expect(parsed.cwd == nil)
}

@Test func rootRoutingParsesAgentShortcutAndCwdPassthrough() throws {
    let command = try Spawn.parseAsRoot(Spawn.rewrittenArguments(["codex", "-C", "/tmp/project", "--", "swift", "test"]))
    guard var parsed = command as? Spawn.Run else {
        Issue.record("Expected Spawn.Run from parseAsRoot")
        return
    }
    parsed.command = Spawn.Run.normalizedCommand(parsed.command)

    #expect(parsed.agent == "codex")
    #expect(parsed.cwd == "/tmp/project")
    #expect(parsed.command == ["swift", "test"])
}
