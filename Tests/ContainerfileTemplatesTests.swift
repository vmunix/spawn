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
