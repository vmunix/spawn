# spawn

Sandboxed AI coding agents on macOS. Built to run Claude Code or Codex in
filesystem-isolated Linux containers with a single command.

```bash
spawn build       # build container images (once)
spawn             # run Claude Code in current directory
spawn -- cargo test
spawn doctor      # check local runtime readiness, images, config, and workspace detection
spawn doctor -C ~/code/project
spawn doctor --json
```

spawn detects your project's language, picks the right container image, mounts
your code, and launches the agent. Your files are read/write inside the
container — everything else on your system is isolated.

## Status

`spawn` is a work in progress. PRs are welcome.

The goal is similar to [Jai](https://jai.scs.stanford.edu/) on Linux: a jail
for your agents that you'll actually use. On macOS we do not have the same
underlying isolation model, so `spawn` takes the pragmatic route and builds on
Apple's container and virtualization stack.

It's written in Swift so it can directly use Apple's Containerization and
Virtualization frameworks when that becomes the right boundary, instead of
being limited to a shell wrapper forever.

## What it does

`spawn` launches AI coding agents in lightweight Linux VMs. Apple's
[`container`](https://github.com/apple/containerization) CLI is the stable
default backend; an explicit experimental backend exercises Apple's
Containerization library directly.

- **Auto-detects toolchains** — Rust, Go, C++, and JS/TS projects (Node, Bun, Deno), or falls back to a base image
- **Safe mode by default** — prompts before `git push`, PR creation, and other remote-write operations
- **Uses explicit access profiles** — default `minimal`, with opt-in `git` and `trusted` host auth exposure
- **Persists OAuth credentials** across runs — authenticate once, not every session
- **No API keys required** — Pro/Max plan users authenticate via OAuth

## Requirements

- macOS 26+
- Apple's [`container`](https://github.com/apple/containerization) CLI: `brew install container`
- Swift 6.3+ (for building from source; `make test` prefers Xcode when installed)

## Install

### Homebrew (recommended)

```bash
brew install container
brew install vmunix/tap/spawn
```

### From source

```bash
git clone https://github.com/vmunix/spawn.git
cd spawn
make install    # builds release and installs to ~/.local/bin
```

Ensure `~/.local/bin` is in your `PATH`:

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Quick start

```bash
# Build all container images (required once)
spawn build

# Or build just what you need
spawn build rust    # also: base, cpp, go, js

# Run Claude Code in your project
spawn

# Run Codex instead
spawn codex

# Run an arbitrary command
spawn -- cargo test

# Run in another workspace
spawn -C ~/code/project

# Opt into git identity and gh auth without exposing SSH keys
spawn --access git

# Drop into a shell for debugging
spawn --shell

# Check local runtime readiness and the current workspace
spawn doctor
spawn doctor -C ~/code/project
spawn doctor --json
```

`spawn build` uses an isolated temporary build context, so it does not depend on whatever files happen to be in your current working directory.

## Usage

### Running agents

```bash
spawn [agent] [options]
spawn -- <command...>
spawn doctor [-C <dir>]
```

Use `spawn -- <command...>` for passthrough commands. `spawn cargo test` is rejected on purpose so the root CLI stays unambiguous.

| Option | Description |
|--------|-------------|
| `--yolo` | Skip permission gates (default: safe mode, prompts before git push) |
| `--shell` | Drop into a shell instead of running an agent |
| `-C, --cwd <dir>` | Directory to mount as workspace (default: current directory) |
| `--runtime <name>` | Runtime mode: `auto`, `spawn`, `workspace-image` |
| `--backend <name>` | Launch backend: `cli` (default), `native-experimental` |
| `--rebuild-workspace-image` | Force a rebuild when using `--runtime workspace-image` |
| `--access <name>` | Host access profile: `minimal`, `git`, `trusted` |
| `--toolchain <name>` | Override auto-detected toolchain: `base`, `cpp`, `rust`, `go`, `js` |
| `--image <name>` | Override auto-selected container image |
| `--mount <dir>` | Mount an additional directory (repeatable) |
| `--read-only <dir>` | Mount a directory read-only (repeatable) |
| `--cpus <n>` | CPU cores for the container (default: 4) |
| `--memory <size>` | Container memory (default: 8g) |
| `--env <KEY=VALUE>` | Set environment variable (repeatable) |
| `--env-file <path>` | Load environment variables from a file |
| `--verbose` | Show the container command being run |

Run an arbitrary command in the workspace container by passing it after `--`:

```bash
spawn -- cargo test
spawn -C ~/code/project -- swift test
```

Access profiles control host auth exposure:

- `minimal` mounts only the workspace, requested extra mounts, and persisted agent state
- `git` additionally mounts git config and `gh` CLI auth
- `trusted` additionally mounts selected SSH config and standard `id_*` key material copied from `~/.ssh`

Runtime mode controls how spawn reacts when a workspace defines its own runtime:

- `auto` is the default
- `spawn` opts into spawn-managed images explicitly
- `workspace-image` builds and runs the workspace-defined image directly

`workspace-image` reuses a cached workspace image when the tracked Dockerfile, optional `.dockerignore`, devcontainer config, and non-ignored build-context file contents and permissions have not changed.
Use `--rebuild-workspace-image` with `--runtime workspace-image` when you want to bypass the cache explicitly.

`spawn doctor` reports the experimental native backend's artifact paths and
approximate allocated size. `spawn cache clean --native` removes only the
current native backend cache after active native launches exit; the next launch
rebuilds it. Workspace build caches and older native cache layouts are untouched.

Launch backend is separate from runtime mode. `--backend cli` preserves the
existing `container run` path. `--backend native-experimental` launches new
workspace containers through the Containerization library, including
`spawn --shell`; it never silently falls back to the CLI. Existing-container
operations (`spawn exec`, `spawn shell <id>`, `spawn list`, and `spawn stop`),
image builds, and doctor probes remain CLI-backed. See
[Native Containerization Backend](docs/native-backend.md) for its artifact
ownership, limitations, and cleanup model.

If your repo has a root `Dockerfile` / `Containerfile`, or a `.devcontainer/devcontainer.json` with `build.dockerfile`, spawn currently requires an explicit choice:

```bash
spawn --runtime workspace-image
spawn --runtime workspace-image --rebuild-workspace-image
spawn --runtime spawn
```

### Building images

```bash
spawn build [toolchain] [options]
```

Omit the toolchain to build all images. Base is built first since other images depend on it.

| Option | Description |
|--------|-------------|
| `--cpus <n>` | CPU cores for the builder container (default: 4) |
| `--memory <size>` | Builder container memory (default: 8g) |

Language toolchains are installed under `/opt` (`/opt/rust`, `/opt/go`, `/opt/js`), never in the container's `/home/coder`. The home holds user state only.

> **Upgrading:** toolchains moved out of `/home/coder` into `/opt`, and the build caches mount at the new `/opt` paths. spawn cannot detect an image built before the move, so rebuild every image once with `spawn build`. Without the rebuild nothing fails loudly: spawn still creates and mounts the cache directories and `spawn doctor` still lists them, but a stale image writes to the old in-home paths, so the caches stay empty — and a stale `spawn-go:latest`, which never set `GOPATH`, does not persist its module cache at all. If you hardcoded `/home/coder/.cargo` or `/home/coder/go` in a script or `.spawn.toml`, update those paths to `/opt/rust/cargo` and `/opt/go`.

### Build caches

Build caches persist automatically in host directories under spawn's state directory, bind-mounted at run time, so downloads survive between runs without being baked into the image:

| Toolchain | Host directory (default, per workspace) | Guest path |
|-----------|-----------------------------------------|------------|
| `rust` | `caches/<workspace>/cargo-registry`, `caches/<workspace>/cargo-git` | `/opt/rust/cargo/registry`, `/opt/rust/cargo/git` |
| `go` | `caches/<workspace>/go-mod` | `/opt/go/pkg/mod` |
| `js` | `caches/<workspace>/deno`, `caches/<workspace>/npm` | `/opt/js/deno-cache`, `/home/coder/.npm` |
| `base`, `cpp` | *(none)* | |

They live under `$XDG_STATE_HOME/spawn/caches` (`~/.local/state/spawn/caches` by default). Caches are **per workspace by default**. `<workspace>` is a slug plus a hash of the workspace path, so each project gets its own directories and no workspace can read or rewrite another's cached dependency sources. spawn creates them on demand -- a `mkdir`, no container and no ownership fixup, because VirtioFS maps the mount to the guest user. `spawn doctor` lists the directories for the detected toolchain, including the scope in use.

Concurrent runs are safe: any number of runs may mount the same cache directory at once.

To trade workspace isolation for reuse, opt in with the flag:

```bash
spawn --cache shared            # this run uses caches/shared/...
```

**Only the flag can select `shared`.** A repo's `.spawn.toml` cannot: `cache = "shared"` there is ignored with a warning, and the run stays workspace-scoped. Repo config may narrow (`cache = "workspace"`) but never widen — the same rule that applies to `access`, because a repo you cloned should not be able to reach the caches you share elsewhere.

A shared cache is one set of directories (`caches/shared/cargo-registry`, etc.) mounted read-write into every workspace that opts in: each of them can read everything the others cached — including private dependency sources fetched by `cargo` into its git cache — and can modify what the others will build against next. Do not use `--cache shared` for untrusted repositories, or alongside workspaces with private dependencies.

There is no `spawn cache` command; a cache is a directory, so delete it and the next run recreates it empty:

```bash
ls ~/.local/state/spawn/caches
rm -rf ~/.local/state/spawn/caches/myproject-1a2b3c4d5e6f7890
```

> **Upgrading:** caches used to be named `container` volumes. Nothing reads those now, so delete them once — each is a 512 GB sparse disk image, so this is also what reclaims the space:
>
> ```bash
> container volume ls | grep spawn-cache-
> container volume delete spawn-cache-cargo-registry
> container volume delete spawn-cache-cargo-git
> container volume delete spawn-cache-go-mod
> container volume delete spawn-cache-deno
> container volume delete spawn-cache-npm
> ```
>
> Per-workspace volumes are named `spawn-cache-<cache>-<slug>-<hash>` and are deleted the same way. Contents are not migrated: the first run in each workspace repopulates the new host directory from scratch. See [docs/toolchains.md](docs/toolchains.md#build-caches) for why the mechanism changed.

### Managing containers

```bash
spawn list              # list running containers
spawn stop <id>         # stop a container
spawn exec <id> <cmd>   # run a command in a running container
spawn shell <id>        # open /bin/bash in a running container
spawn doctor            # check local runtime readiness, images, config, and workspace detection
spawn doctor -C ~/code/project
spawn doctor --json     # same report in machine-readable form
```

### Managing images

```bash
spawn image list        # list spawn images
spawn image list --all  # list all container images
spawn image rm <name>   # remove a spawn image
```

## Safe mode

By default, spawn runs agents in **safe mode**. Remote-write operations require approval:

- `git push`
- `git remote add` / `set-url`
- `gh pr create` / `merge` / `close`
- `gh issue create` / `close`
- `gh release`, `gh repo`

Use `--yolo` to skip all permission gates.

## Configuration

### Environment variables

Place a `KEY=VALUE` file at `~/.config/spawn/env` to set environment variables for every run. Lines starting with `#` are comments. Values can be quoted.

### Project-level config

Add a `.spawn.toml` to your repo root to set workspace defaults:

```toml
[workspace]
agent = "codex"

[toolchain]
base = "rust"
```

Valid values:

- `workspace.agent`: `claude-code`, `codex`
- `workspace.cache`: `workspace` (default, caches private to this workspace); `shared` is ignored here — it requires `--cache shared`
- `toolchain.base`: `base`, `cpp`, `rust`, `go`, `js`

Repo config can set the default agent and toolchain preference. Host access still requires an explicit `--access ...` at launch time, even if `.spawn.toml` contains an `access` value, and cross-workspace cache sharing likewise requires an explicit `--cache shared`.

spawn also reads `.devcontainer/devcontainer.json` to infer toolchains from images and features. If a viable devcontainer config is present, spawn prefers that explicit signal over repo-file heuristics. This makes existing VS Code devcontainer projects work with zero extra setup.

`spawn doctor` also checks local runtime readiness: whether the `container` services are running, whether a default kernel is installed, and whether Rosetta is available on Apple Silicon hosts. When something is missing, it points you at the most common first-machine fixes.

## Devcontainer support

If your project already uses `.devcontainer/devcontainer.json`, spawn treats that as the strongest project signal after `.spawn.toml`.

- devcontainer image/features are mapped to spawn toolchains
- the launch summary and `spawn doctor` show when `.devcontainer/devcontainer.json` drove the choice
- this makes spawn a good fit for projects already set up for VS Code Dev Containers

If `.devcontainer/devcontainer.json` uses `build.dockerfile`, `spawn --runtime workspace-image` builds and runs that workspace-defined image directly and reuses it until the tracked build inputs change. That cache respects a context-root `.dockerignore`, so ignored files do not force rebuilds. `spawn --runtime spawn` remains available when you want to ignore the workspace runtime and use spawn-managed images instead.

For JS/TS repos, `spawn-js:latest` bundles Node.js 22 LTS, Corepack, Bun, and Deno so the common runtime and package-manager paths work out of the box.

## Documentation

For detailed guides on permissions, authentication, and architecture, see the [documentation](https://vmunix.github.io/spawn/).

## Development

```bash
make build              # Debug build
make test               # Lint + tests (prefers Xcode's SwiftPM when available)
make smoke              # End-to-end workspace-first and workspace-image tests
make install            # Install to ~/.local/bin
```

## License

MIT
