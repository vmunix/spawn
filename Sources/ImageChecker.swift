import Foundation

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
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }
        return json[reference] != nil
    }

    /// The base image that all toolchain images derive from.
    private static let baseImage = "spawn-base:latest"

    /// Check whether a toolchain image is stale relative to `spawn-base:latest`.
    ///
    /// Compares `org.opencontainers.image.created` timestamps from the container
    /// CLI's state.json. Returns `true` when the toolchain image was built before
    /// the current base image, meaning it should be rebuilt.
    ///
    /// Returns `false` on any error (missing file, bad JSON, missing timestamps)
    /// so that a failed check never blocks the user.
    static func isStale(_ image: String, storeRoot: URL? = nil) -> Bool {
        // Base can't be stale relative to itself.
        guard image != baseImage else { return false }

        guard let root = storeRoot ?? defaultStoreRoot else { return false }

        let statePath = root.appendingPathComponent("state.json")
        guard let data = try? Data(contentsOf: statePath),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return false
        }

        guard let imageCreated = createdTimestamp(for: image, in: json),
            let baseCreated = createdTimestamp(for: baseImage, in: json)
        else {
            return false
        }

        return imageCreated < baseCreated
    }

    /// Extract the `org.opencontainers.image.created` timestamp from an image entry.
    private static func createdTimestamp(for image: String, in json: [String: Any]) -> Date? {
        guard let entry = json[image] as? [String: Any],
            let annotations = entry["annotations"] as? [String: Any],
            let created = annotations["org.opencontainers.image.created"] as? String
        else {
            return nil
        }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: created) {
            return date
        }
        // Retry without fractional seconds for simpler timestamps.
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: created)
    }
}
