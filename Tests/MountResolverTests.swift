import Testing
@testable import ccc

@Test func resolvesTargetDirectory() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: [],
        readOnly: [],
        includeGit: false
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/project" && !$0.readOnly })
}

@Test func includesAdditionalMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: ["/Users/me/code/lib"],
        readOnly: [],
        includeGit: false
    )
    #expect(mounts.count == 2)
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/lib" && !$0.readOnly })
}

@Test func includesReadOnlyMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/Users/me/code/project"),
        additional: [],
        readOnly: ["/Users/me/code/docs"],
        includeGit: false
    )
    #expect(mounts.contains { $0.hostPath == "/Users/me/code/docs" && $0.readOnly })
}

@Test func noGitExcludesGitMounts() {
    let mounts = MountResolver.resolve(
        target: fileURL("/tmp/project"),
        additional: [],
        readOnly: [],
        includeGit: false
    )
    let gitMounts = mounts.filter { $0.guestPath.contains(".git") || $0.guestPath.contains(".ssh") }
    #expect(gitMounts.isEmpty)
}
