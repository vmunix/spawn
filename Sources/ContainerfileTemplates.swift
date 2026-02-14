enum ContainerfileTemplates {
    static func content(for toolchain: Toolchain) -> String {
        switch toolchain {
        case .base: return base
        case .cpp: return cpp
        case .rust: return rust
        case .go: return go
        }
    }

    static let base = """
    FROM ubuntu:24.04

    RUN apt-get update && apt-get install -y --no-install-recommends \\
        git curl wget ca-certificates \\
        build-essential \\
        python3 python3-pip python3-venv \\
        nodejs npm \\
        ripgrep fd-find jq tree \\
        openssh-client \\
        && rm -rf /var/lib/apt/lists/*

    # Claude Code
    RUN npm install -g @anthropic-ai/claude-code

    # Codex (OpenAI)
    RUN npm install -g @openai/codex

    WORKDIR /workspace
    """

    static let cpp = """
    FROM ccc-base:latest

    RUN apt-get update && apt-get install -y --no-install-recommends \\
        clang clang-format clang-tidy \\
        cmake ninja-build \\
        gdb valgrind \\
        && rm -rf /var/lib/apt/lists/*
    """

    static let rust = """
    FROM ccc-base:latest

    RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    ENV PATH="/root/.cargo/bin:${PATH}"
    """

    static let go = """
    FROM ccc-base:latest

    ARG GO_VERSION=1.23.6
    RUN curl -fsSL "https://go.dev/dl/go${GO_VERSION}.linux-arm64.tar.gz" | tar -C /usr/local -xz
    ENV PATH="/usr/local/go/bin:/root/go/bin:${PATH}"
    """
}
