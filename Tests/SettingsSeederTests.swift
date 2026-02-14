import Foundation
import Testing

@testable import spawn

@Test func seedsFreshSettingsFile() throws {
    let dir = try makeTempDir(files: [:])
    let settingsFile = dir.appendingPathComponent("settings.json")

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: settingsFile)
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]
    let allow = permissions?["allow"] as? [String]
    let deny = permissions?["deny"] as? [String]

    #expect(allow != nil)
    #expect(deny != nil)
    #expect(allow!.contains("Bash(git add:*)"))
    #expect(deny!.contains("Bash(git push:*)"))
}

@Test func preservesExistingPermissions() throws {
    let existing = """
        {"permissions": {"allow": ["Bash(custom:*)"], "deny": []}}
        """
    let dir = try makeTempDir(files: ["settings.json": existing])

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]
    let allow = permissions?["allow"] as? [String]

    #expect(allow == ["Bash(custom:*)"])
}

@Test func seedsWhenPermissionsKeyMissing() throws {
    let existing = """
        {"skipDangerousModePermissionPrompt": true}
        """
    let dir = try makeTempDir(files: ["settings.json": existing])

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]

    #expect(permissions != nil)
    #expect(json?["skipDangerousModePermissionPrompt"] as? Bool == true)
}

@Test func skipsOnMalformedJson() throws {
    let dir = try makeTempDir(files: ["settings.json": "not json {{{"])

    SettingsSeeder.seed(settingsDir: dir)

    let content = try String(contentsOf: dir.appendingPathComponent("settings.json"), encoding: .utf8)
    #expect(content == "not json {{{")
}

@Test func emptyPermissionsCountsAsCustomized() throws {
    let existing = """
        {"permissions": {}}
        """
    let dir = try makeTempDir(files: ["settings.json": existing])

    SettingsSeeder.seed(settingsDir: dir)

    let data = try Data(contentsOf: dir.appendingPathComponent("settings.json"))
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let permissions = json?["permissions"] as? [String: Any]

    #expect(permissions?.isEmpty == true)
}
