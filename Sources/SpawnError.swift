import Foundation

/// Structured error type for spawn runtime errors.
///
/// `ValidationError` (from ArgumentParser) is reserved for CLI argument validation only.
/// Runtime errors — image lookup failures, container exits, missing binaries — use this type.
enum SpawnError: Error, CustomStringConvertible, Sendable {
    /// Container process exited with non-zero status.
    case containerFailed(status: Int32)

    /// Container CLI binary not found at any expected path.
    case containerNotFound

    /// Container image not found in the local image store.
    case imageNotFound(image: String, hint: String)

    /// General runtime error with a contextual message.
    case runtimeError(String)

    var description: String {
        switch self {
        case .containerFailed(let status):
            return "Container exited with status \(status)"
        case .containerNotFound:
            return "Container CLI not found. Install Apple's container tool first."
        case .imageNotFound(let image, let hint):
            return "Image '\(image)' not found. \(hint)"
        case .runtimeError(let message):
            return message
        }
    }
}
