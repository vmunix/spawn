import Containerization
import Foundation
import Testing

@testable import spawn

@Test func nativeArtifactsAreVersionedWithTheInitfs() {
    let runtime = NativeContainerRuntime(
        stateRoot: URL(fileURLWithPath: "/state/native-runtime")
    )
    #expect(NativeContainerRuntime.initfsReference == "ghcr.io/apple/containerization/vminit:0.45.0")
    #expect(
        runtime.artifactRoot.path == "/state/native-runtime/containerization-0.45.0"
    )
}

@Test func nativeArtifactDirectoryIsPrivateAndReusable() throws {
    let root = try makeTempDir(files: [:]).appendingPathComponent("native-runtime")
    let runtime = NativeContainerRuntime(stateRoot: root)

    let first = try runtime.prepareArtifactRoot()
    let second = try runtime.prepareArtifactRoot()

    #expect(first == second)
    #expect(first.path == root.appendingPathComponent("containerization-0.45.0").path)
    let rootMode =
        try FileManager.default.attributesOfItem(atPath: root.path)[.posixPermissions]
        as? NSNumber
    let artifactMode =
        try FileManager.default.attributesOfItem(atPath: first.path)[
            .posixPermissions
        ] as? NSNumber
    #expect(rootMode?.intValue == 0o700)
    #expect(artifactMode?.intValue == 0o700)
}

@Test func nativeAdapterConsumesEveryLaunchPlanFieldExactly() throws {
    let plan = makeLaunchPlan(
        image: "registry.example/spawn:native",
        mounts: [
            Mount(hostPath: "/host/work", guestPath: "/workspace/work", readOnly: false),
            Mount(hostPath: "/host/config", guestPath: "/container/config", readOnly: true),
        ],
        env: ["Z_LAST": "two words", "A_FIRST": "one"],
        workdir: "/workspace/work/subdir",
        entrypoint: ["/bin/sh", "-lc", "printf done"],
        cpus: 7,
        memory: "13g",
        keepStandardInputOpen: false,
        allocateTerminal: true,
        removeOnExit: false
    )

    #expect(
        try NativeLaunchConfiguration(plan: plan)
            == NativeLaunchConfiguration(
                image: "registry.example/spawn:native",
                mounts: [
                    Mount(hostPath: "/host/work", guestPath: "/workspace/work", readOnly: false),
                    Mount(hostPath: "/host/config", guestPath: "/container/config", readOnly: true),
                ],
                environment: ["Z_LAST": "two words", "A_FIRST": "one"],
                workdir: "/workspace/work/subdir",
                entrypoint: ["/bin/sh", "-lc", "printf done"],
                cpus: 7,
                memoryInBytes: 13 * 1024 * 1024 * 1024,
                keepStandardInputOpen: false,
                allocateTerminal: true,
                removeOnExit: false,
                useInit: true
            )
    )
}

@Test func nativeAdapterAppliesEveryLaunchFieldToLibraryConfiguration() throws {
    let plan = makeLaunchPlan(
        image: "spawn-base:latest",
        mounts: [
            Mount(hostPath: "/host/work", guestPath: "/workspace/work", readOnly: false),
            Mount(hostPath: "/host/config", guestPath: "/container/config", readOnly: true),
        ],
        env: ["TERM": "xterm-256color", "EXTRA": "value"],
        workdir: "/workspace/work/subdir",
        entrypoint: ["/bin/sh", "-lc", "exit 23"],
        cpus: 7,
        memory: "13g",
        keepStandardInputOpen: true,
        allocateTerminal: false
    )
    let launch = try NativeLaunchConfiguration(plan: plan)
    var config = LinuxContainer.Configuration()
    config.process.environmentVariables = ["PATH=/image/bin", "TERM=image-term"]
    let defaultMountCount = config.mounts.count

    launch.apply(to: &config, terminal: nil)

    #expect(config.cpus == 7)
    #expect(config.memoryInBytes == 13 * 1024 * 1024 * 1024)
    #expect(config.process.arguments == ["/bin/sh", "-lc", "exit 23"])
    #expect(config.process.workingDirectory == "/workspace/work/subdir")
    #expect(
        config.process.environmentVariables == [
            "PATH=/image/bin", "EXTRA=value", "TERM=xterm-256color",
        ]
    )
    #expect(config.process.stdin != nil)
    #expect(config.process.stdout != nil)
    #expect(config.process.stderr != nil)
    #expect(config.useInit)
    #expect(config.mounts.count == defaultMountCount + 2)
    let workMount = config.mounts[defaultMountCount]
    #expect(workMount.type == "virtiofs")
    #expect(workMount.source == "/host/work")
    #expect(workMount.destination == "/workspace/work")
    #expect(workMount.options == [])
    let configMount = config.mounts[defaultMountCount + 1]
    #expect(configMount.type == "virtiofs")
    #expect(configMount.source == "/host/config")
    #expect(configMount.destination == "/container/config")
    #expect(configMount.options == ["ro"])
}

@Test func nativeAdapterClosesStdinWhenPlanDoesNotKeepItOpen() throws {
    let plan = makeLaunchPlan(
        image: "spawn-base:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace/test",
        entrypoint: ["true"],
        cpus: 1,
        memory: "1g",
        keepStandardInputOpen: false,
        allocateTerminal: false
    )
    var config = LinuxContainer.Configuration()
    try NativeLaunchConfiguration(plan: plan).apply(to: &config, terminal: nil)
    #expect(config.process.stdin == nil)
    #expect(config.process.stdout != nil)
    #expect(config.process.stderr != nil)
}

@Test func nativeMemoryParserAcceptsCliStyleUnitsAndRejectsInvalidValues() throws {
    #expect(try NativeContainerRuntime.parseMemory("4096") == 4096)
    #expect(try NativeContainerRuntime.parseMemory("512m") == 512 * 1024 * 1024)
    #expect(try NativeContainerRuntime.parseMemory("8G") == 8 * 1024 * 1024 * 1024)

    for invalid in ["", "0", "eight-g", "18446744073709551615t"] {
        #expect(throws: SpawnError.self) {
            _ = try NativeContainerRuntime.parseMemory(invalid)
        }
    }
}

@Test func nativeEnvironmentKeepsImageDefaultsAndAppliesSortedOverrides() {
    let merged = NativeContainerRuntime.mergedEnvironment(
        base: [
            "PATH=/image/bin",
            "HOME=/home/coder",
            "TERM=image-term",
            "MALFORMED",
        ],
        overrides: [
            "TERM": "xterm-256color",
            "ALPHA": "first",
        ]
    )

    #expect(
        merged == [
            "PATH=/image/bin",
            "HOME=/home/coder",
            "MALFORMED",
            "ALPHA=first",
            "TERM=xterm-256color",
        ]
    )
}

@Test func nativeBackendRefusesRetainedContainersBeforeArtifactWork() async throws {
    let runtime = NativeContainerRuntime(
        stateRoot: URL(fileURLWithPath: "/unreachable/native-state")
    )
    let plan = makeLaunchPlan(
        image: "spawn-base:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace/test",
        entrypoint: ["true"],
        cpus: 1,
        memory: "1g",
        removeOnExit: false
    )

    await #expect(throws: SpawnError.self) {
        _ = try await runtime.launch(plan)
    }
}

@Test func nativeBackendExplainsTheRequiredVirtualizationEntitlement() async throws {
    // Release builds produced by `make build` are signed; the test host is not.
    // If a future test runner supplies the entitlement, this precondition is no
    // longer available to exercise in-process.
    guard !NativeContainerRuntime.hasVirtualizationEntitlement() else { return }

    let runtime = NativeContainerRuntime(
        stateRoot: URL(fileURLWithPath: "/unreachable/native-state")
    )
    let plan = makeLaunchPlan(
        image: "spawn-base:latest",
        mounts: [],
        env: [:],
        workdir: "/workspace/test",
        entrypoint: ["true"],
        cpus: 1,
        memory: "1g"
    )

    do {
        _ = try await runtime.launch(plan)
        Issue.record("Expected an unsigned native launch to fail before artifact access")
    } catch let SpawnError.runtimeError(message) {
        #expect(
            message
                == "The native-experimental backend requires a binary signed with the com.apple.security.virtualization entitlement. Build it with 'make build' or 'make install'."
        )
    } catch {
        Issue.record("Unexpected error: \(error)")
    }
}
