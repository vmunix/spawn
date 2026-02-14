import ContainerizationOCI
import Foundation

enum ImageChecker {
    /// Root of the container CLI's application data.
    /// The `container` CLI stores image state at:
    ///   ~/Library/Application Support/com.apple.container/state.json
    static let defaultStoreRoot: URL = {
        FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("com.apple.container")
    }()

    /// Check whether an image reference exists in the container CLI's image store.
    /// Returns false if the store can't be read (best-effort check).
    static func imageExists(_ reference: String, storeRoot: URL? = nil) -> Bool {
        let root = storeRoot ?? defaultStoreRoot
        let statePath = root.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: statePath),
              let state = try? JSONDecoder().decode([String: Descriptor].self, from: data) else {
            return false
        }
        return state[reference] != nil
    }
}
