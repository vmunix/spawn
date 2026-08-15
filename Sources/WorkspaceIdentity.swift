import Foundation

/// A stable, filesystem-safe key derived from a workspace path.
///
/// Two things spawn names per workspace — the workspace runtime image and the
/// workspace-scoped build caches — must agree on what "this workspace" means,
/// so the derivation lives here rather than being reimplemented per call site.
/// The key pairs a readable slug (so a human can tell whose cache or image it
/// is) with a hash of the full path (so two directories with the same last
/// component do not collide).
enum WorkspaceIdentity: Sendable {
    /// `<slug>-<hash>` for a workspace directory.
    ///
    /// The URL is standardized here rather than by each caller, so `~/code/app`,
    /// `~/code/app/` and `~/code/./app` always land on one key. Leaving that to
    /// callers made every new call site a chance to fork a workspace's identity
    /// in two.
    static func key(for workspace: URL) -> String {
        let workspace = workspace.standardizedFileURL
        return sanitizedComponent(workspace.lastPathComponent) + "-" + fnv1a64Hex(workspace.path)
    }

    /// Lowercased, alphanumeric-with-dashes form of a single path component,
    /// bounded in length so a deep directory name cannot dominate a name.
    static func sanitizedComponent(_ value: String) -> String {
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

    /// FNV-1a 64-bit, hex. Not a security primitive: it exists to separate
    /// distinct paths whose last components collide, not to hide the path.
    static func fnv1a64Hex(_ value: String) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16, uppercase: false)
    }
}
