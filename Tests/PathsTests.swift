import Testing
import Foundation
@testable import spawn

@Test func defaultConfigDir() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(Paths.configDir.path == "\(home)/.config/spawn")
}

@Test func defaultStateDir() {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    #expect(Paths.stateDir.path == "\(home)/.local/state/spawn")
}

@Test func configDirRespectsXDGEnv() {
    let custom = Paths.configDir(xdgConfigHome: "/tmp/myconfig")
    #expect(custom.path == "/tmp/myconfig/spawn")
}

@Test func stateDirRespectsXDGEnv() {
    let custom = Paths.stateDir(xdgStateHome: "/tmp/mystate")
    #expect(custom.path == "/tmp/mystate/spawn")
}
