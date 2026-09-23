import Containerization
import ContainerizationArchive
import ContainerizationEXT4
import ContainerizationError
import ContainerizationOS
import Darwin
import Foundation
import Security

/// Experimental launch adapter backed directly by Apple's Containerization
/// library. Operational commands remain on `ContainerRunner`; the one CLI use
/// here is an explicit OCI export bridge for spawn-managed local images.
struct NativeContainerRuntime: ContainerRuntime {
    static let libraryVersion = "0.45.0"
    static let initfsReference = "ghcr.io/apple/containerization/vminit:\(libraryVersion)"
    static let rootfsCapacity: UInt64 = 512 * 1024 * 1024 * 1024

    let stateRoot: URL
    let cliStateRoot: URL

    /// `ContainerManager` reuses `initfs.ext4` in its image store even when
    /// `initfsReference` changes. Keep artifacts from different library/initfs
    /// versions separate so an upgrade never boots an older initfs by accident.
    var artifactRoot: URL {
        stateRoot.appendingPathComponent("containerization-\(Self.libraryVersion)")
    }

    @discardableResult
    func prepareArtifactRoot() throws -> URL {
        let fileManager = FileManager.default
        for directory in [stateRoot, artifactRoot] {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
        }
        return artifactRoot
    }

    init(
        stateRoot: URL,
        cliStateRoot: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/com.apple.container")
    ) {
        self.stateRoot = stateRoot
        self.cliStateRoot = cliStateRoot
    }

    func launch(_ plan: ResolvedLaunchPlan) async throws -> Int32 {
        let launch = try NativeLaunchConfiguration(plan: plan)
        guard launch.removeOnExit else {
            throw SpawnError.runtimeError(
                "The native-experimental backend does not support retained containers."
            )
        }
        guard #available(macOS 26, *) else {
            throw SpawnError.runtimeError(
                "The native-experimental backend requires macOS 26 or newer."
            )
        }
        guard Self.hasVirtualizationEntitlement() else {
            throw SpawnError.runtimeError(
                "The native-experimental backend requires a binary signed with the com.apple.security.virtualization entitlement. Build it with 'make build' or 'make install'."
            )
        }

        let terminal = try launch.allocateTerminal ? Terminal.current : nil
        let id = Self.containerID()
        var prepared: PreparedContainer?

        do {
            var active = try await prepareContainer(
                id: id,
                launch: launch,
                terminal: terminal
            )
            prepared = active
            try terminal?.setraw()
            defer { terminal?.tryReset() }

            try await active.container.create()
            try await active.container.start()
            if let terminal {
                try? await active.container.resize(to: try terminal.size)
            }

            let exit = try await waitForExit(
                of: active.container,
                terminal: terminal
            )
            logger.debug("Native workload exited with status \(exit.exitCode); stopping VM")
            try await active.container.stop()
            logger.debug("Native VM stopped; deleting launch artifacts")
            try active.manager.delete(id)
            prepared = nil
            return exit.exitCode
        } catch {
            if var active = prepared {
                try? await active.container.stop()
                try? active.manager.delete(id)
            }
            if let spawnError = error as? SpawnError {
                throw spawnError
            }
            throw SpawnError.runtimeError(
                "Native experimental launch failed: \(String(describing: error))"
            )
        }
    }

    @available(macOS 26, *)
    private func prepareContainer(
        id: String,
        launch: NativeLaunchConfiguration,
        terminal: Terminal?
    ) async throws -> PreparedContainer {
        let artifactRoot = try prepareArtifactRoot()

        // Image import, initfs materialization, and rootfs cache creation all
        // mutate the spawn-owned native store. Serialize them across processes;
        // running VMs use independent cloned root filesystems after this scope.
        let artifactLock = try NativeArtifactLock(
            path: artifactRoot.appendingPathComponent("artifacts.lock")
        )
        defer { _ = artifactLock }

        let imageStoreRoot = artifactRoot.appendingPathComponent("images")
        let imageStore = try ImageStore(path: imageStoreRoot)
        let image = try await NativeImageBridge(imageStore: imageStore).resolve(
            reference: launch.image
        )
        let kernelPath = try newestKernel(in: cliStateRoot.appendingPathComponent("kernels"))
        let network = try VmnetNetwork()
        var manager = try await ContainerManager(
            kernel: Kernel(path: kernelPath, platform: .linuxArm),
            initfsReference: Self.initfsReference,
            imageStore: imageStore,
            network: network
        )

        let cachedRootfs = try await cacheRootfs(for: image)
        let containerDirectory =
            imageStoreRoot
            .appendingPathComponent("containers")
            .appendingPathComponent(id)
        try FileManager.default.createDirectory(
            at: containerDirectory,
            withIntermediateDirectories: false
        )
        let rootfs: Containerization.Mount
        do {
            rootfs = try cachedRootfs.clone(
                to: containerDirectory.appendingPathComponent("rootfs.ext4").path
            )
        } catch {
            try? FileManager.default.removeItem(at: containerDirectory)
            throw error
        }

        let container: LinuxContainer
        do {
            container = try await manager.create(
                id,
                image: image,
                rootfs: rootfs,
                networking: true
            ) { config in
                launch.apply(to: &config, terminal: terminal)
            }
        } catch {
            try? manager.releaseNetwork(id)
            try? FileManager.default.removeItem(at: containerDirectory)
            throw error
        }

        return PreparedContainer(manager: manager, container: container)
    }

    private func cacheRootfs(for image: Containerization.Image) async throws -> Containerization.Mount {
        let cacheDirectory = artifactRoot.appendingPathComponent("rootfs")
        try FileManager.default.createDirectory(
            at: cacheDirectory,
            withIntermediateDirectories: true
        )
        let digestKey = image.digest.replacingOccurrences(of: ":", with: "-")
        let path = cacheDirectory.appendingPathComponent("\(digestKey).ext4")

        if !FileManager.default.fileExists(atPath: path.path) {
            do {
                let unpacker = EXT4Unpacker(capacityInBytes: Self.rootfsCapacity)
                _ = try await unpacker.unpack(image, for: .current, at: path)
            } catch {
                try? FileManager.default.removeItem(at: path)
                throw error
            }
        }

        return .block(
            format: "ext4",
            source: path.path,
            destination: "/",
            options: [],
            runtimeOptions: ["vzDiskImageSynchronizationMode=fsync"]
        )
    }

    private func newestKernel(in directory: URL) throws -> URL {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .isRegularFileKey,
        ]
        let candidates = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent.hasPrefix("vmlinux-") else { return false }
            return (try? url.resourceValues(forKeys: keys).isRegularFile) == true
        }
        let sorted = try candidates.sorted { left, right in
            let leftDate = try left.resourceValues(forKeys: keys).contentModificationDate ?? .distantPast
            let rightDate = try right.resourceValues(forKeys: keys).contentModificationDate ?? .distantPast
            return leftDate > rightDate
        }
        guard let kernel = sorted.first else {
            throw SpawnError.runtimeError(
                "The native-experimental backend could not find an installed container kernel in \(directory.path)."
            )
        }
        return kernel
    }

    private func waitForExit(
        of container: LinuxContainer,
        terminal: Terminal?
    ) async throws -> ExitStatus {
        let signalForwarder = NativeSignalForwarder(
            container: container,
            terminal: terminal
        )
        defer { signalForwarder.cancel() }
        return try await container.wait()
    }

    static func mergedEnvironment(
        base: [String],
        overrides: [String: String]
    ) -> [String] {
        let overriddenKeys = Set(overrides.keys)
        let preserved = base.filter { item in
            guard let separator = item.firstIndex(of: "=") else { return true }
            return !overriddenKeys.contains(String(item[..<separator]))
        }
        return preserved
            + overrides.sorted(by: { $0.key < $1.key }).map {
                "\($0.key)=\($0.value)"
            }
    }

    static func parseMemory(_ value: String) throws -> UInt64 {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard !normalized.isEmpty else {
            throw SpawnError.runtimeError("Invalid native backend memory value: '\(value)'.")
        }

        let suffix = normalized.last
        let multiplier: UInt64
        let number: Substring
        switch suffix {
        case "k":
            multiplier = 1024
            number = normalized.dropLast()
        case "m":
            multiplier = 1024 * 1024
            number = normalized.dropLast()
        case "g":
            multiplier = 1024 * 1024 * 1024
            number = normalized.dropLast()
        case "t":
            multiplier = 1024 * 1024 * 1024 * 1024
            number = normalized.dropLast()
        default:
            multiplier = 1
            number = normalized[...]
        }

        guard let quantity = UInt64(number) else {
            throw SpawnError.runtimeError("Invalid native backend memory value: '\(value)'.")
        }
        let result = quantity.multipliedReportingOverflow(by: multiplier)
        guard !result.overflow, result.partialValue > 0 else {
            throw SpawnError.runtimeError("Invalid native backend memory value: '\(value)'.")
        }
        return result.partialValue
    }

    static func hasVirtualizationEntitlement() -> Bool {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.security.virtualization" as CFString,
            nil
        )
        return value as? Bool == true
    }

    private static func containerID() -> String {
        let nonce = UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "")
        return "spawn-\(ProcessInfo.processInfo.processIdentifier)-\(nonce.prefix(16))"
    }
}

/// Adapter-side representation used to prove every semantic plan field is
/// consumed before the native library is invoked. VM artifacts remain private
/// to `NativeContainerRuntime`, not part of the cross-backend launch plan.
struct NativeLaunchConfiguration: Sendable, Equatable {
    let image: String
    let mounts: [Mount]
    let environment: [String: String]
    let workdir: String
    let entrypoint: [String]
    let cpus: Int
    let memoryInBytes: UInt64
    let keepStandardInputOpen: Bool
    let allocateTerminal: Bool
    let removeOnExit: Bool
    let useInit: Bool

    init(
        image: String,
        mounts: [Mount],
        environment: [String: String],
        workdir: String,
        entrypoint: [String],
        cpus: Int,
        memoryInBytes: UInt64,
        keepStandardInputOpen: Bool,
        allocateTerminal: Bool,
        removeOnExit: Bool,
        useInit: Bool
    ) {
        self.image = image
        self.mounts = mounts
        self.environment = environment
        self.workdir = workdir
        self.entrypoint = entrypoint
        self.cpus = cpus
        self.memoryInBytes = memoryInBytes
        self.keepStandardInputOpen = keepStandardInputOpen
        self.allocateTerminal = allocateTerminal
        self.removeOnExit = removeOnExit
        self.useInit = useInit
    }

    init(plan: ResolvedLaunchPlan) throws {
        image = plan.image
        mounts = plan.mounts
        environment = plan.environment
        workdir = plan.workdir
        entrypoint = plan.entrypoint
        cpus = plan.resources.cpus
        memoryInBytes = try NativeContainerRuntime.parseMemory(plan.resources.memory)
        keepStandardInputOpen = plan.io.keepStandardInputOpen
        allocateTerminal = plan.io.allocateTerminal
        removeOnExit = plan.removeOnExit
        useInit = true
    }

    /// Applies the semantic launch fields to the library's actual container
    /// configuration. The manager's creation closure and adapter tests call
    /// this same path, so config assignments are not a second untested map.
    func apply(to config: inout LinuxContainer.Configuration, terminal: Terminal?) {
        config.cpus = cpus
        config.memoryInBytes = memoryInBytes
        config.process.arguments = entrypoint
        config.process.workingDirectory = workdir

        if let terminal {
            config.process.setTerminalIO(terminal: terminal)
        } else {
            if keepStandardInputOpen {
                config.process.stdin = NativeFileHandleReader(handle: .standardInput)
            }
            config.process.stdout = NativeFileHandleWriter(handle: .standardOutput)
            config.process.stderr = NativeFileHandleWriter(handle: .standardError)
        }

        config.process.environmentVariables = NativeContainerRuntime.mergedEnvironment(
            base: config.process.environmentVariables,
            overrides: environment
        )
        for mount in mounts {
            config.mounts.append(
                Containerization.Mount.share(
                    source: mount.hostPath,
                    destination: mount.guestPath,
                    options: mount.readOnly ? ["ro"] : []
                )
            )
        }

        // Init forwards signals to the workload and reaps orphaned children.
        config.useInit = useInit
    }
}

private struct PreparedContainer {
    var manager: ContainerManager
    let container: LinuxContainer
}

/// Copies a CLI-owned image through the public OCI archive contract into the
/// native runtime's independent content store. Digest comparison keeps rebuilds
/// visible without re-exporting unchanged images on every launch.
private struct NativeImageBridge {
    struct Inspection: Decodable {
        struct Configuration: Decodable {
            struct Descriptor: Decodable {
                let digest: String
            }

            let descriptor: Descriptor
        }

        let configuration: Configuration
    }

    let imageStore: ImageStore

    func resolve(reference: String) async throws -> Containerization.Image {
        let inspected = try ContainerRunner.runCapture(
            args: ["image", "inspect", reference]
        )
        guard inspected.status == 0 else {
            throw SpawnError.runtimeError(
                "The native-experimental backend could not inspect local image '\(reference)'."
            )
        }
        let inspections: [Inspection]
        do {
            inspections = try JSONDecoder().decode(
                [Inspection].self,
                from: Data(inspected.output.utf8)
            )
        } catch {
            throw SpawnError.runtimeError(
                "The native-experimental backend could not decode image metadata for '\(reference)'."
            )
        }
        guard let digest = inspections.first?.configuration.descriptor.digest else {
            throw SpawnError.runtimeError(
                "The native-experimental backend found no metadata for image '\(reference)'."
            )
        }

        if let cached = try? await imageStore.get(reference: reference),
            cached.digest == digest
        {
            return cached
        }

        print("Native backend: importing \(reference) into the spawn-owned image cache...")
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("spawn-native-\(UUID().uuidString)")
        let archive = temporaryDirectory.appendingPathComponent("image.tar")
        let layout = temporaryDirectory.appendingPathComponent("oci")
        try FileManager.default.createDirectory(
            at: temporaryDirectory,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        defer { try? FileManager.default.removeItem(at: temporaryDirectory) }
        try FileManager.default.createDirectory(
            at: layout,
            withIntermediateDirectories: false
        )

        let exported = try ContainerRunner.runCapture(args: [
            "image",
            "save",
            "--platform",
            "linux/arm64",
            "--output",
            archive.path,
            reference,
        ])
        guard exported.status == 0 else {
            throw SpawnError.runtimeError(
                "The native-experimental backend could not export local image '\(reference)'."
            )
        }

        let rejectedPaths = try ArchiveReader(file: archive).extractContents(to: layout)
        guard rejectedPaths.isEmpty else {
            throw SpawnError.runtimeError(
                "The native-experimental backend rejected unsafe paths in the OCI archive for '\(reference)'."
            )
        }
        let imported = try await imageStore.load(from: layout)
        guard let image = imported.first(where: { $0.reference == reference }),
            image.digest == digest
        else {
            throw SpawnError.runtimeError(
                "The native-experimental backend imported an unexpected artifact for '\(reference)'."
            )
        }
        return image
    }
}

private final class NativeArtifactLock {
    private let descriptor: Int32

    init(path: URL) throws {
        let descriptor = open(path.path, O_CREAT | O_RDWR, 0o600)
        guard descriptor >= 0 else {
            throw SpawnError.runtimeError(
                "Cannot open native artifact lock at \(path.path): \(String(cString: strerror(errno)))"
            )
        }
        guard flock(descriptor, LOCK_EX) == 0 else {
            let message = String(cString: strerror(errno))
            close(descriptor)
            throw SpawnError.runtimeError(
                "Cannot lock native artifact cache at \(path.path): \(message)"
            )
        }
        self.descriptor = descriptor
    }

    deinit {
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
    }
}

private final class NativeFileHandleReader: ReaderStream, @unchecked Sendable {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func stream() -> AsyncStream<Data> {
        AsyncStream { continuation in
            handle.readabilityHandler = { readable in
                let data = readable.availableData
                if data.isEmpty {
                    continuation.finish()
                } else {
                    continuation.yield(data)
                }
            }
            continuation.onTermination = { [handle] _ in
                handle.readabilityHandler = nil
            }
        }
    }
}

private struct NativeFileHandleWriter: Writer, @unchecked Sendable {
    let handle: FileHandle

    func write(_ data: Data) throws {
        try handle.write(contentsOf: data)
    }

    /// Standard output and error belong to the spawn process, not an individual
    /// container stream.
    func close() throws {}
}

/// Containerization 0.45.0's `AsyncSignalHandler.cancel()` finishes its stream
/// while holding the same mutex that the stream termination callback re-enters.
/// Use dispatch sources until that recursive-lock crash is fixed upstream.
private final class NativeSignalForwarder: @unchecked Sendable {
    nonisolated(unsafe) private var sources: [any DispatchSourceSignal] = []
    private let handledSignals: [Int32]

    init(container: LinuxContainer, terminal: Terminal?) {
        handledSignals = [SIGINT, SIGTERM] + (terminal == nil ? [] : [SIGWINCH])
        for rawSignal in handledSignals {
            signal(rawSignal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: rawSignal)
            source.setEventHandler {
                Task {
                    if rawSignal == SIGWINCH, let terminal {
                        try? await container.resize(to: try terminal.size)
                    } else {
                        try? await container.kill(Signal(rawValue: rawSignal))
                    }
                }
            }
            source.resume()
            sources.append(source)
        }
    }

    func cancel() {
        for source in sources {
            source.cancel()
        }
        sources.removeAll()
        for rawSignal in handledSignals {
            signal(rawSignal, SIG_DFL)
        }
    }
}
