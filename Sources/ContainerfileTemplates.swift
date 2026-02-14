/// Embedded Containerfile strings for each toolchain, so `spawn build` works without repo files.
enum ContainerfileTemplates: Sendable {
    /// The Go release version used in the go Containerfile template.
    private static let goVersion = "1.24.0"

    /// The host architecture mapped to Go's naming convention (`arm64` or `amd64`).
    private static let goArch: String = {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }()

    /// Returns the Containerfile content for the given toolchain.
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
            git curl wget ca-certificates sudo \\
            build-essential \\
            python3 python3-pip python3-venv \\
            nodejs npm \\
            ripgrep fd-find jq tree \\
            openssh-client \\
            && rm -rf /var/lib/apt/lists/*

        # Codex (OpenAI)
        RUN npm install -g @openai/codex

        # Non-root user with sudo access
        RUN useradd -m -s /bin/bash -G sudo coder \\
            && echo 'coder ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers

        # Claude Code (native installer, as coder so it lands in /home/coder/.local/bin)
        USER coder
        RUN curl -fsSL https://claude.ai/install.sh | bash
        ENV PATH="/home/coder/.local/bin:${PATH}"

        # Symlink config files into mounted directories.
        # VirtioFS doesn't support atomic rename on single-file bind mounts (EBUSY),
        # and preserves host uid/permissions making direct file mounts unreadable.
        RUN mkdir -p /home/coder/.claude-state /home/coder/.gitconfig-dir \\
            && rm -f /home/coder/.claude.json \\
            && ln -s /home/coder/.claude-state/claude.json /home/coder/.claude.json \\
            && ln -sf /home/coder/.gitconfig-dir/.gitconfig /home/coder/.gitconfig

        WORKDIR /workspace
        """

    /// The LLVM/Clang major version used in the cpp Containerfile template.
    private static let clangVersion = "21"

    static let cpp = """
        FROM spawn-base:latest

        USER root

        # Add LLVM apt repository for clang-\(clangVersion)
        RUN apt-get update && apt-get install -y --no-install-recommends \\
                ca-certificates wget gnupg \\
            && wget -qO- https://apt.llvm.org/llvm-snapshot.gpg.key \\
                | tee /etc/apt/trusted.gpg.d/apt.llvm.org.asc \\
            && echo "deb http://apt.llvm.org/noble/ llvm-toolchain-noble-\(clangVersion) main" \\
                > /etc/apt/sources.list.d/llvm.list \\
            && rm -rf /var/lib/apt/lists/*

        # Install clang-\(clangVersion) toolchain and dev tools
        RUN apt-get update && apt-get install -y --no-install-recommends \\
                clang-\(clangVersion) clang-format-\(clangVersion) clang-tidy-\(clangVersion) \\
                clang-tools-\(clangVersion) lld-\(clangVersion) \\
                libc++-\(clangVersion)-dev libc++abi-\(clangVersion)-dev \\
                cmake ninja-build \\
                gdb valgrind \\
            && rm -rf /var/lib/apt/lists/*

        # Set clang-\(clangVersion) as default via update-alternatives
        RUN update-alternatives --install /usr/bin/clang clang /usr/bin/clang-\(clangVersion) 200 \\
            && update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-\(clangVersion) 200 \\
            && update-alternatives --install /usr/bin/clang-format clang-format /usr/bin/clang-format-\(clangVersion) 100 \\
            && update-alternatives --install /usr/bin/clang-tidy clang-tidy /usr/bin/clang-tidy-\(clangVersion) 100 \\
            && update-alternatives --install /usr/bin/ld.lld ld.lld /usr/bin/ld.lld-\(clangVersion) 100

        USER coder
        """

    static let rust = """
        FROM spawn-base:latest

        USER root
        RUN su - coder -c "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y"
        ENV PATH="/home/coder/.cargo/bin:${PATH}"
        USER coder
        """

    static let go = """
        FROM spawn-base:latest

        USER root
        RUN curl -fsSL "https://go.dev/dl/go\(goVersion).linux-\(goArch).tar.gz" | tar -C /usr/local -xz
        ENV PATH="/usr/local/go/bin:/home/coder/go/bin:${PATH}"
        USER coder
        """
}
