import Foundation

enum MountResolver {
    static func resolve(
        target: URL,
        additional: [String],
        readOnly: [String],
        includeGit: Bool
    ) -> [Mount] {
        var mounts: [Mount] = []

        // Primary target
        mounts.append(Mount(hostPath: target.path, readOnly: false))

        // Additional read-write mounts
        for path in additional {
            mounts.append(Mount(hostPath: path, readOnly: false))
        }

        // Read-only mounts
        for path in readOnly {
            mounts.append(Mount(hostPath: path, readOnly: true))
        }

        // Git/SSH mounts
        if includeGit {
            let home = FileManager.default.homeDirectoryForCurrentUser
            let fm = FileManager.default

            let gitconfig = home.appendingPathComponent(".gitconfig").path
            if fm.fileExists(atPath: gitconfig) {
                mounts.append(Mount(
                    hostPath: gitconfig,
                    guestPath: "/home/coder/.gitconfig",
                    readOnly: true
                ))
            }

            let sshDir = home.appendingPathComponent(".ssh").path
            if fm.fileExists(atPath: sshDir) {
                mounts.append(Mount(
                    hostPath: sshDir,
                    guestPath: "/home/coder/.ssh",
                    readOnly: true
                ))
            }
        }

        return mounts
    }
}
