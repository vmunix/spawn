import Foundation

enum Paths {
    static var configDir: URL {
        configDir(xdgConfigHome: ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"])
    }

    static var stateDir: URL {
        stateDir(xdgStateHome: ProcessInfo.processInfo.environment["XDG_STATE_HOME"])
    }

    static func configDir(xdgConfigHome: String?) -> URL {
        let base: URL
        if let custom = xdgConfigHome {
            base = URL(fileURLWithPath: custom)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config")
        }
        let dir = base.appendingPathComponent("spawn")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func stateDir(xdgStateHome: String?) -> URL {
        let base: URL
        if let custom = xdgStateHome {
            base = URL(fileURLWithPath: custom)
        } else {
            base = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(".local")
                .appendingPathComponent("state")
        }
        let dir = base.appendingPathComponent("spawn")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}
