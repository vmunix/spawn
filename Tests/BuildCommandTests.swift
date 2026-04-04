import Foundation
import Testing

@testable import spawn

@Test func prepareBuildWorkspaceUsesIsolatedTemporaryContext() throws {
    let tempRoot = try makeTempDir(files: [:])

    let workspace = try Spawn.Build.prepareBuildWorkspace(
        for: .rust,
        temporaryDirectory: tempRoot
    )

    #expect(workspace.imageName == "spawn-rust:latest")
    #expect(workspace.contextURL.deletingLastPathComponent().path == tempRoot.path)
    #expect(workspace.containerfileURL == workspace.contextURL.appendingPathComponent("Containerfile"))
    #expect(workspace.contextURL.path != FileManager.default.currentDirectoryPath)
    #expect(FileManager.default.fileExists(atPath: workspace.containerfileURL.path))

    let containerfile = try String(contentsOf: workspace.containerfileURL, encoding: .utf8)
    #expect(containerfile == ContainerfileTemplates.content(for: .rust))
}

@Test func buildArgsUsePreparedContextInsteadOfCurrentDirectory() {
    let args = Spawn.Build.buildArgs(
        imageName: "spawn-rust:latest",
        containerfileURL: fileURL("/tmp/spawn-build-rust/Containerfile"),
        contextURL: fileURL("/tmp/spawn-build-rust"),
        cpus: 6,
        memory: "12g"
    )

    let expected = [
        "build",
        "-c", "6",
        "-m", "12g",
        "-t", "spawn-rust:latest",
        "-f", "/tmp/spawn-build-rust/Containerfile",
        "/tmp/spawn-build-rust",
    ]

    #expect(args == expected)
    #expect(!args.contains("."))
}
