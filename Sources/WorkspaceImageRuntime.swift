import ArgumentParser
import Darwin
import Foundation

/// Resolves and builds workspace-defined container runtimes.
enum WorkspaceImageRuntime: Sendable {
    struct Plan: Sendable, Equatable {
        let image: String
        let dockerfile: URL
        let context: URL
        let source: ToolchainDetector.Source
        let configFile: URL?
        let dockerignore: URL?
        let env: [String: String]
        let fingerprint: String
        let cacheRecord: URL
    }

    struct CacheRecord: Codable, Sendable, Equatable {
        let image: String
        let fingerprint: String
        let source: String
        let dockerfilePath: String
        let contextPath: String
    }

    enum CacheStatus: Sendable, Equatable {
        case ready
        case notBuilt
        case stale(reason: String)
    }

    struct BuildResult: Sendable, Equatable {
        let plan: Plan
        let cacheStatus: CacheStatus
        let built: Bool
    }

    private struct DockerignoreRule: Sendable, Equatable {
        let pattern: String
        let isNegated: Bool
        let directoryOnly: Bool
        let basenameOnly: Bool
        let hasGlob: Bool

        func matches(relativePath: String, isDirectory: Bool) -> Bool {
            let candidate = relativePath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard !candidate.isEmpty else {
                return false
            }

            if basenameOnly {
                let components = candidate.split(separator: "/").map(String.init)
                if directoryOnly {
                    return components.contains { component in
                        Self.globMatches(pattern: pattern, value: component)
                    }
                }

                return components.contains { component in
                    Self.globMatches(pattern: pattern, value: component)
                }
            }

            if directoryOnly {
                let prefixes = Self.pathPrefixes(of: candidate, includeSelf: isDirectory)
                if hasGlob {
                    return prefixes.contains { prefix in
                        Self.globMatches(pattern: pattern, value: prefix)
                    }
                }

                return prefixes.contains(pattern)
            }

            return Self.globMatches(pattern: pattern, value: candidate)
        }

        private static func pathPrefixes(of path: String, includeSelf: Bool) -> [String] {
            let components = path.split(separator: "/").map(String.init)
            guard !components.isEmpty else {
                return []
            }

            let lastIndex = includeSelf ? components.count : components.count - 1
            guard lastIndex > 0 else {
                return []
            }

            return (1...lastIndex).map { components.prefix($0).joined(separator: "/") }
        }

        private static func globMatches(pattern: String, value: String) -> Bool {
            guard let regex = try? NSRegularExpression(pattern: regexPattern(for: pattern)) else {
                return pattern == value
            }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.firstMatch(in: value, options: [], range: range) != nil
        }

        private static func regexPattern(for pattern: String) -> String {
            var result = "^"
            let characters = Array(pattern)
            var index = 0

            while index < characters.count {
                let character = characters[index]
                if character == "*" {
                    if index + 1 < characters.count, characters[index + 1] == "*" {
                        result += ".*"
                        index += 2
                        continue
                    }
                    result += "[^/]*"
                    index += 1
                    continue
                }
                if character == "?" {
                    result += "[^/]"
                    index += 1
                    continue
                }

                result += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }

            result += "$"
            return result
        }
    }

    private struct Dockerignore: Sendable, Equatable {
        let rules: [DockerignoreRule]

        static func load(from url: URL?) throws -> Dockerignore? {
            guard let url else {
                return nil
            }

            let contents = try String(contentsOf: url, encoding: .utf8)
            let lines = contents.split(whereSeparator: \.isNewline)
            let rules = lines.compactMap { parseRule(String($0)) }

            return Dockerignore(rules: rules)
        }

        func ignores(relativePath: String, isDirectory: Bool) -> Bool {
            var ignored = false

            for rule in rules where rule.matches(relativePath: relativePath, isDirectory: isDirectory) {
                ignored = !rule.isNegated
            }

            return ignored
        }

        private static func parseRule(_ rawLine: String) -> DockerignoreRule? {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else {
                return nil
            }

            if line.hasPrefix("\\#") || line.hasPrefix("\\!") {
                line.removeFirst()
            } else if line.hasPrefix("#") {
                return nil
            }

            var isNegated = false
            if line.hasPrefix("!") {
                isNegated = true
                line.removeFirst()
            }

            line = normalizePattern(line)
            guard !line.isEmpty, line != "." else {
                return nil
            }

            let directoryOnly = line.hasSuffix("/")
            if directoryOnly {
                line.removeLast()
            }

            let basenameOnly = !line.contains("/")
            let hasGlob = line.contains("*") || line.contains("?")
            return DockerignoreRule(
                pattern: line,
                isNegated: isNegated,
                directoryOnly: directoryOnly,
                basenameOnly: basenameOnly,
                hasGlob: hasGlob
            )
        }

        private static func normalizePattern(_ pattern: String) -> String {
            var normalized = pattern
            while normalized.hasPrefix("./") {
                normalized.removeFirst(2)
            }
            while normalized.hasPrefix("/") {
                normalized.removeFirst()
            }
            return normalized
        }
    }

    static func plan(for workspace: URL, stateDir: URL = Paths.stateDir) throws -> Plan {
        let workspace = workspace.standardizedFileURL
        let fm = FileManager.default
        let image = imageName(for: workspace)
        let cacheRecord = cacheRecordURL(for: workspace, stateDir: stateDir)

        let devcontainerURL =
            workspace
            .appendingPathComponent(".devcontainer")
            .appendingPathComponent("devcontainer.json")

        if fm.fileExists(atPath: devcontainerURL.path),
            let config = DevcontainerConfig.parse(at: devcontainerURL),
            let dockerfile = config.dockerfile
        {
            let baseDir = devcontainerURL.deletingLastPathComponent()
            let dockerfileURL = baseDir.appendingPathComponent(dockerfile).standardizedFileURL
            let contextURL = baseDir.appendingPathComponent(config.buildContext ?? ".").standardizedFileURL
            let dockerignoreURL = dockerignoreURL(in: contextURL)
            try validateBuildInputs(dockerfile: dockerfileURL, context: contextURL)
            let fingerprint = try fingerprint(
                source: .devcontainerDockerfile,
                dockerfile: dockerfileURL,
                context: contextURL,
                configFile: devcontainerURL,
                dockerignoreFile: dockerignoreURL
            )
            return Plan(
                image: image,
                dockerfile: dockerfileURL,
                context: contextURL,
                source: .devcontainerDockerfile,
                configFile: devcontainerURL,
                dockerignore: dockerignoreURL,
                env: config.env,
                fingerprint: fingerprint,
                cacheRecord: cacheRecord
            )
        }

        let dockerfileCandidates = ["Dockerfile", "Containerfile"]
        for candidate in dockerfileCandidates {
            let dockerfileURL = workspace.appendingPathComponent(candidate)
            if fm.fileExists(atPath: dockerfileURL.path) {
                let dockerignoreURL = dockerignoreURL(in: workspace)
                try validateBuildInputs(dockerfile: dockerfileURL, context: workspace)
                let fingerprint = try fingerprint(
                    source: .dockerfile,
                    dockerfile: dockerfileURL,
                    context: workspace,
                    configFile: nil,
                    dockerignoreFile: dockerignoreURL
                )
                return Plan(
                    image: image,
                    dockerfile: dockerfileURL,
                    context: workspace,
                    source: .dockerfile,
                    configFile: nil,
                    dockerignore: dockerignoreURL,
                    env: [:],
                    fingerprint: fingerprint,
                    cacheRecord: cacheRecord
                )
            }
        }

        throw SpawnError.runtimeError(
            "Workspace-image runtime requires a root Dockerfile/Containerfile or .devcontainer/devcontainer.json with build.dockerfile."
        )
    }

    static func buildArgs(plan: Plan, cpus: Int, memory: String) -> [String] {
        [
            "build",
            "-c", "\(cpus)",
            "-m", memory,
            "-t", plan.image,
            "-f", plan.dockerfile.path,
            plan.context.path,
        ]
    }

    @discardableResult
    static func build(plan: Plan, cpus: Int, memory: String) throws -> Plan {
        print("Building workspace image \(plan.image)...")
        let status = try ContainerRunner.runRaw(args: buildArgs(plan: plan, cpus: cpus, memory: memory))
        if status != 0 {
            throw ExitCode(status)
        }
        return plan
    }

    static func ensureBuilt(
        plan: Plan,
        cpus: Int,
        memory: String,
        forceRebuild: Bool = false,
        storeRoot: URL? = nil
    ) throws -> BuildResult {
        let status = requestedCacheStatus(
            for: plan,
            forceRebuild: forceRebuild,
            storeRoot: storeRoot
        )
        switch status {
        case .ready:
            print("Using cached workspace image \(plan.image)")
            return BuildResult(plan: plan, cacheStatus: status, built: false)
        case .notBuilt:
            print("Workspace image \(plan.image) is not built yet.")
        case .stale(let reason):
            print("Rebuilding workspace image \(plan.image) (\(reason)).")
        }

        _ = try build(plan: plan, cpus: cpus, memory: memory)
        try writeCacheRecord(for: plan)
        return BuildResult(plan: plan, cacheStatus: status, built: true)
    }

    static func imageName(for workspace: URL) -> String {
        let workspace = workspace.standardizedFileURL
        let slug = sanitizedComponent(workspace.lastPathComponent)
        let hash = fnv1a64Hex(workspace.path)
        return "spawn-workspace-\(slug)-\(hash):latest"
    }

    static func requestedCacheStatus(
        for plan: Plan,
        forceRebuild: Bool,
        storeRoot: URL? = nil
    ) -> CacheStatus {
        if forceRebuild {
            return .stale(reason: "forced rebuild requested")
        }
        return cacheStatus(for: plan, storeRoot: storeRoot)
    }

    static func cacheStatus(for plan: Plan, storeRoot: URL? = nil) -> CacheStatus {
        let imageStatus = ImageChecker.imageStatus(plan.image, storeRoot: storeRoot)
        guard let record = loadCacheRecord(at: plan.cacheRecord) else {
            switch imageStatus {
            case .present:
                return .stale(reason: "cache metadata missing")
            case .missing:
                return .notBuilt
            case .unknown:
                return .stale(reason: "unable to verify cached image state")
            }
        }

        guard record.image == plan.image else {
            return .stale(reason: "cached image identity changed")
        }
        guard record.source == plan.source.identifier else {
            return .stale(reason: "runtime source changed")
        }
        guard record.dockerfilePath == plan.dockerfile.path else {
            return .stale(reason: "Dockerfile location changed")
        }
        guard record.contextPath == plan.context.path else {
            return .stale(reason: "build context changed")
        }
        switch imageStatus {
        case .present:
            break
        case .missing:
            return .stale(reason: "cached image is missing")
        case .unknown:
            return .stale(reason: "unable to verify cached image state")
        }
        guard record.fingerprint == plan.fingerprint else {
            return .stale(reason: "build inputs changed")
        }

        return .ready
    }

    private static func cacheRecordURL(for workspace: URL, stateDir: URL) -> URL {
        let dir = stateDir.appendingPathComponent("workspace-images")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let key = sanitizedComponent(workspace.lastPathComponent) + "-" + fnv1a64Hex(workspace.path)
        return dir.appendingPathComponent("\(key).json")
    }

    private static func validateBuildInputs(dockerfile: URL, context: URL) throws {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: dockerfile.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            throw ValidationError("Workspace Dockerfile does not exist: \(dockerfile.path)")
        }

        isDirectory = false
        guard FileManager.default.fileExists(atPath: context.path, isDirectory: &isDirectory) else {
            throw ValidationError("Workspace build context does not exist: \(context.path)")
        }
        guard isDirectory.boolValue else {
            throw ValidationError("Workspace build context is not a directory: \(context.path)")
        }
    }

    private static func dockerignoreURL(in context: URL) -> URL? {
        let url = context.appendingPathComponent(".dockerignore")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
            return nil
        }
        return url
    }

    private static func fingerprint(
        source: ToolchainDetector.Source,
        dockerfile: URL,
        context: URL,
        configFile: URL?,
        dockerignoreFile: URL?
    ) throws -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325

        mix("source:\(source.identifier)", into: &hash)
        try mixFileMetadata(at: dockerfile, label: "dockerfile", into: &hash)
        if let configFile {
            try mixFileMetadata(at: configFile, label: "config", into: &hash)
        }
        if let dockerignoreFile {
            try mixFileMetadata(at: dockerignoreFile, label: "dockerignore", into: &hash)
        }
        let dockerignore = try Dockerignore.load(from: dockerignoreFile)
        try mixDirectoryTree(at: context, dockerignore: dockerignore, into: &hash)

        return String(hash, radix: 16, uppercase: false)
    }

    private static func mixDirectoryTree(
        at root: URL,
        dockerignore: Dockerignore?,
        into hash: inout UInt64
    ) throws {
        let keys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey,
            .isSymbolicLinkKey,
        ]
        guard
            let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: keys,
                options: [],
                errorHandler: nil
            )
        else {
            throw ValidationError("Workspace build context is not readable: \(root.path)")
        }

        for case let url as URL in enumerator {
            let relativePath = relativePath(of: url, under: root)
            if relativePath == ".git" || relativePath.hasPrefix(".git/") {
                enumerator.skipDescendants()
                continue
            }

            let values = try url.resourceValues(forKeys: Set(keys))
            let isDirectory = values.isDirectory == true
            if dockerignore?.ignores(relativePath: relativePath, isDirectory: isDirectory) == true {
                continue
            }

            if values.isDirectory == true {
                mix("dir:\(relativePath)", into: &hash)
                continue
            }
            if values.isSymbolicLink == true {
                let destination = (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) ?? ""
                mix("symlink:\(relativePath):\(destination)", into: &hash)
                continue
            }
            if values.isRegularFile == true {
                let permissions = posixPermissions(at: url)
                mix("file:\(relativePath):\(permissions)", into: &hash)
                try mixFileContents(at: url, into: &hash)
                continue
            }
            mix("other:\(relativePath)", into: &hash)
        }
    }

    private static func mixFileMetadata(at url: URL, label: String, into hash: inout UInt64) throws {
        let permissions = posixPermissions(at: url)
        mix("\(label):\(url.path):\(permissions)", into: &hash)
        try mixFileContents(at: url, into: &hash)
    }

    private static func posixPermissions(at url: URL) -> Int {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.posixPermissions] as? Int ?? 0
    }

    private static func relativePath(of url: URL, under root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath) else { return url.lastPathComponent }
        let start = path.index(path.startIndex, offsetBy: rootPath.count)
        let suffix = path[start...]
        return suffix.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    private static func mix(_ string: String, into hash: inout UInt64) {
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        mixTerminator(into: &hash)
    }

    private static func mixFileContents(at url: URL, into hash: inout UInt64) throws {
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        for byte in data {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        mixTerminator(into: &hash)
    }

    private static func mixTerminator(into hash: inout UInt64) {
        hash ^= 0x0000_0000_0000_000a
        hash &*= 0x0000_0100_0000_01b3
    }

    private static func loadCacheRecord(at url: URL) -> CacheRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(CacheRecord.self, from: data)
    }

    private static func writeCacheRecord(for plan: Plan) throws {
        let record = CacheRecord(
            image: plan.image,
            fingerprint: plan.fingerprint,
            source: plan.source.identifier,
            dockerfilePath: plan.dockerfile.path,
            contextPath: plan.context.path
        )
        let data = try JSONEncoder().encode(record)
        try data.write(to: plan.cacheRecord, options: Data.WritingOptions.atomic)
    }

    private static func sanitizedComponent(_ value: String) -> String {
        let lowercased = value.lowercased()
        var result = ""
        var previousWasDash = false

        for scalar in lowercased.unicodeScalars {
            let isAlphaNumeric =
                (scalar.value >= 48 && scalar.value <= 57)
                || (scalar.value >= 97 && scalar.value <= 122)
            if isAlphaNumeric {
                result.append(Character(scalar))
                previousWasDash = false
            } else if !previousWasDash {
                result.append("-")
                previousWasDash = true
            }
        }

        let trimmed = result.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if trimmed.isEmpty { return "workspace" }
        return String(trimmed.prefix(40))
    }

    private static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
