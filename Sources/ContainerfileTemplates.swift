import Foundation

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

    /// Git wrapper script that prompts before remote-write operations in safe mode.
    private static let gitGuard = #"""
        #!/bin/bash
        REAL_GIT=/usr/bin/git

        # Pass through immediately if safe mode is not active
        if [[ "${SPAWN_SAFE_MODE:-}" != "1" ]]; then
            exec "$REAL_GIT" "$@"
        fi

        # Find the actual subcommand by skipping option flags
        subcmd=""
        i=1
        while [[ $i -le $# ]]; do
            arg="${!i}"
            case "$arg" in
                -c|--config|-C)
                    ((i+=2))
                    ;;
                -*)
                    ((i++))
                    ;;
                *)
                    subcmd="$arg"
                    break
                    ;;
            esac
        done

        case "$subcmd" in
            push)
                printf '\033[1;33mspawn:\033[0m agent wants to run: git %s\n' "$*" >/dev/tty 2>/dev/null
                printf 'allow? [y/N] ' >/dev/tty 2>/dev/null
                read -r answer </dev/tty 2>/dev/null || { echo "spawn: git push blocked — safe mode requires a TTY for approval" >&2; exit 1; }
                [[ "$answer" =~ ^[Yy]$ ]] || { echo "spawn: blocked by safe mode" >&2; exit 1; }
                ;;
            remote)
                next_i=$((i + 1))
                remote_sub="${!next_i}"
                case "$remote_sub" in
                    add|set-url)
                        printf '\033[1;33mspawn:\033[0m agent wants to run: git %s\n' "$*" >/dev/tty 2>/dev/null
                        printf 'allow? [y/N] ' >/dev/tty 2>/dev/null
                        read -r answer </dev/tty 2>/dev/null || { echo "spawn: git remote $remote_sub blocked — safe mode requires a TTY for approval" >&2; exit 1; }
                        [[ "$answer" =~ ^[Yy]$ ]] || { echo "spawn: blocked by safe mode" >&2; exit 1; }
                        ;;
                esac
                ;;
        esac

        exec "$REAL_GIT" "$@"
        """#

    /// GitHub CLI wrapper script that prompts before mutating operations in safe mode.
    private static let ghGuard = #"""
        #!/bin/bash
        REAL_GH=/usr/bin/gh

        # Pass through immediately if safe mode is not active
        if [[ "${SPAWN_SAFE_MODE:-}" != "1" ]]; then
            exec "$REAL_GH" "$@"
        fi

        prompt_user() {
            printf '\033[1;33mspawn:\033[0m agent wants to run: gh %s\n' "$*" >/dev/tty 2>/dev/null
            printf 'allow? [y/N] ' >/dev/tty 2>/dev/null
            read -r answer </dev/tty 2>/dev/null || { echo "spawn: gh command blocked — safe mode requires a TTY for approval" >&2; exit 1; }
            [[ "$answer" =~ ^[Yy]$ ]] || { echo "spawn: blocked by safe mode" >&2; exit 1; }
        }

        case "${1:-}" in
            pr)
                case "${2:-}" in
                    create|merge|close) prompt_user "$@" ;;
                esac
                ;;
            issue)
                case "${2:-}" in
                    create|close) prompt_user "$@" ;;
                esac
                ;;
            release|repo)
                prompt_user "$@"
                ;;
        esac

        exec "$REAL_GH" "$@"
        """#

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
            git curl wget ca-certificates sudo gpg \\
            build-essential \\
            python3 python3-pip python3-venv \\
            nodejs npm \\
            ripgrep fd-find jq tree \\
            openssh-client \\
            && rm -rf /var/lib/apt/lists/*

        # GitHub CLI
        RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \\
                | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \\
            && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \\
                > /etc/apt/sources.list.d/github-cli.list \\
            && apt-get update && apt-get install -y --no-install-recommends gh \\
            && rm -rf /var/lib/apt/lists/*

        # Safe-mode wrapper scripts for git/gh (activated by SPAWN_SAFE_MODE=1)
        RUN mkdir -p /usr/local/lib/spawn \\
            && echo '\(Data(gitGuard.utf8).base64EncodedString())' | base64 -d > /usr/local/lib/spawn/git-guard.sh \\
            && echo '\(Data(ghGuard.utf8).base64EncodedString())' | base64 -d > /usr/local/lib/spawn/gh-guard.sh \\
            && chmod +x /usr/local/lib/spawn/git-guard.sh /usr/local/lib/spawn/gh-guard.sh \\
            && ln -sf /usr/local/lib/spawn/git-guard.sh /usr/local/bin/git \\
            && ln -sf /usr/local/lib/spawn/gh-guard.sh /usr/local/bin/gh

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
