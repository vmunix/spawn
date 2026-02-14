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
