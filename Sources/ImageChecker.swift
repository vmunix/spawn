import ContainerizationOCI
import Foundation
import Logging

/// Pre-flight check against the `container` CLI's local image store.
enum ImageChecker: Sendable {
    /// Root of the container CLI's application data.
    /// The `container` CLI stores image state at:
    ///   ~/Library/Application Support/com.apple.container/state.json
    /// Returns `nil` if the Application Support directory cannot be resolved.
    static let defaultStoreRoot: URL? = {
        guard
            let appSupport = FileManager.default.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first
        else {
            return nil
        }
        return appSupport.appendingPathComponent("com.apple.container")
    }()

    /// Check whether an image reference exists in the container CLI's image store.
    /// Returns false if the store can't be read (best-effort check).
    static func imageExists(_ reference: String, storeRoot: URL? = nil) -> Bool {
        guard let root = storeRoot ?? defaultStoreRoot else {
            logger.warning("Unable to resolve Application Support directory; skipping image existence check")
            return false
        }
        let statePath = root.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: statePath),
            let state = try? JSONDecoder().decode([String: Descriptor].self, from: data)
        else {
            return false
        }
        return state[reference] != nil
    }
}
