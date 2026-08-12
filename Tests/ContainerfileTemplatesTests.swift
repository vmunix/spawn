import Testing

@testable import spawn

@Test func baseContainerfileContainsEssentials() {
    let content = ContainerfileTemplates.content(for: .base)
    #expect(content.contains("FROM ubuntu:24.04"))
    #expect(content.contains("claude.ai/install.sh"))
    #expect(content.contains("codex"))
    #expect(content.contains("ripgrep"))
}

@Test func cppContainerfileExtendsBase() {
    let content = ContainerfileTemplates.content(for: .cpp)
    #expect(content.contains("FROM spawn-base:latest"))
    #expect(content.contains("clang"))
    #expect(content.contains("cmake"))
}

@Test func rustContainerfileExtendsBase() {
    let content = ContainerfileTemplates.content(for: .rust)
    #expect(content.contains("FROM spawn-base:latest"))
    #expect(content.contains("rustup"))
}

@Test func rustToolchainLivesOutsideHome() {
    let content = ContainerfileTemplates.content(for: .rust)
    #expect(content.contains("RUSTUP_HOME=/opt/rust/rustup"))
    #expect(content.contains("CARGO_HOME=/opt/rust/cargo"))
    #expect(content.contains("/opt/rust/cargo/bin"))
    #expect(!content.contains("/home/coder/.cargo"), "rust must not put cargo in the home")
}

@Test func rustInstallerDoesNotEditShellRcFiles() {
    // rustup appends to ~/.bashrc and ~/.profile unless told not to; those edits are
    // toolchain state in a file the home will own and share across toolchains.
    // Assert the actual installer invocation carries the flag, not just that the
    // literal substring appears somewhere in the template (an explanatory comment
    // could contain it too, and would let a stripped flag pass silently).
    #expect(ContainerfileTemplates.content(for: .rust).contains("sh -s -- -y --no-modify-path"))
}

@Test func goContainerfileExtendsBase() {
    let content = ContainerfileTemplates.content(for: .go)
    #expect(content.contains("FROM spawn-base:latest"))
    #expect(content.contains("go.dev"))
}

@Test func goContainerfileContainsVersionedURL() {
    let content = ContainerfileTemplates.content(for: .go)
    #expect(content.contains("go1.24.0.linux-"))
}

@Test func goContainerfileContainsArchitecture() {
    let content = ContainerfileTemplates.content(for: .go)
    #expect(content.contains("linux-arm64") || content.contains("linux-amd64"))
}

@Test func goContainerfileDoesNotContainARGDirective() {
    let content = ContainerfileTemplates.content(for: .go)
    #expect(!content.contains("ARG GO_VERSION"))
}

@Test func jsContainerfileExtendsBase() {
    let content = ContainerfileTemplates.content(for: .js)
    #expect(content.contains("FROM spawn-base:latest"))
    #expect(content.contains("bun.sh/install"))
    #expect(content.contains("deno.land/install.sh"))
}

@Test func jsContainerfileEnablesCorepack() {
    let content = ContainerfileTemplates.content(for: .js)
    #expect(content.contains("corepack enable"))
}

@Test func jsContainerfilePinsNodeLTS() {
    let content = ContainerfileTemplates.content(for: .js)
    #expect(content.contains("nodejs.org/download/release/v22.22.1"))
    #expect(content.contains("linux-arm64") || content.contains("linux-x64"))
}

@Test func jsToolchainsLiveOutsideHome() {
    let content = ContainerfileTemplates.content(for: .js)
    #expect(content.contains("BUN_INSTALL=/opt/js/bun"))
    #expect(content.contains("DENO_INSTALL=/opt/js/deno"))
    #expect(content.contains("/opt/js/bun/bin"))
    #expect(content.contains("/opt/js/deno/bin"))
    #expect(!content.contains("/home/coder/.bun"), "bun must not live in the home")
    #expect(!content.contains("/home/coder/.deno"), "deno must not live in the home")
}

@Test func denoCacheLivesOutsideHome() {
    // Verified: deno writes ~/.cache/deno (dep analysis, v8 cache, fetched modules).
    #expect(ContainerfileTemplates.content(for: .js).contains("DENO_DIR=/opt/js/deno-cache"))
}

@Test func jsTemplateRestoresShellRcFiles() {
    // The bun/deno installers append to .bashrc/.profile; PATH comes from ENV instead.
    let content = ContainerfileTemplates.content(for: .js)
    #expect(content.contains("/etc/skel/.bashrc"))
    #expect(content.contains("/etc/skel/.profile"))
}

@Test func jsTemplateInstallsUnzipBeforeBun() {
    // Verified: the bun installer exits 1 without unzip.
    let content = ContainerfileTemplates.content(for: .js)
    guard let unzip = content.range(of: "unzip")?.lowerBound,
        let bun = content.range(of: "bun.sh/install")?.lowerBound
    else {
        Issue.record("Expected both unzip and the bun installer in the js template")
        return
    }
    #expect(unzip < bun)
}
