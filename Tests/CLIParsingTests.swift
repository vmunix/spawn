import Foundation
import Testing

@testable import spawn

@Test func rewrittenArgumentsPreserveDirectSubcommands() {
    #expect(Spawn.rewrittenArguments(["doctor", "--json"]) == ["doctor", "--json"])
    #expect(Spawn.rewrittenArguments(["run", "--", "cargo", "test"]) == ["run", "--", "cargo", "test"])
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

@Test func runParserAcceptsUppercaseCwdShortOption() throws {
    let command = try Spawn.Run.parseAsRoot(["-C", "/tmp/project", "--shell"])
    guard let parsed = command as? Spawn.Run else {
        Issue.record("Expected Spawn.Run from parseAsRoot")
        return
    }

    #expect(parsed.cwd == "/tmp/project")
    #expect(parsed.shell == true)
}
