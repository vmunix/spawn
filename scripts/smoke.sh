#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPAWN_BIN="${ROOT}/.build/release/spawn"
CONTAINER_BIN="${CONTAINER_BIN:-${CONTAINER_PATH:-container}}"

section() {
  printf '=== %s ===\n' "$1"
}

fail() {
  printf 'smoke failure: %s\n' "$1" >&2
  exit 1
}

fail_for_container_prereq() {
  local output="$1"

  if [[ "${output}" == *"default kernel not configured"* ]]; then
    printf '%s\n' "${output}" >&2
    fail "Apple's container runtime does not have a default kernel configured. Run 'container system kernel set --recommended' once, then rerun 'make smoke'."
  fi

  if [[ "${output}" == *"Rosetta is not installed"* ]]; then
    printf '%s\n' "${output}" >&2
    fail "Rosetta is not installed. Install it with 'softwareupdate --install-rosetta --agree-to-license', then rerun 'make smoke'."
  fi
}

expect_contains() {
  local haystack="$1"
  local needle="$2"
  local label="$3"

  if [[ "${haystack}" != *"${needle}"* ]]; then
    printf '%s\n' "${haystack}" >&2
    fail "${label} missing '${needle}'"
  fi
}

expect_regex() {
  local haystack="$1"
  local pattern="$2"
  local label="$3"

  # The `--` is load-bearing: without it grep reads a pattern starting with `-`
  # (every --volume assertion below) as an unknown option and exits 2 before
  # reading stdin. That reads as "no match" here, so a correct run hard-fails,
  # and as "matched" in expect_not_regex, so a regression passes silently.
  if ! printf '%s\n' "${haystack}" | grep -Eq -- "${pattern}"; then
    printf '%s\n' "${haystack}" >&2
    fail "${label} did not match ${pattern}"
  fi
}

expect_not_regex() {
  local haystack="$1"
  local pattern="$2"
  local label="$3"

  if printf '%s\n' "${haystack}" | grep -Eq -- "${pattern}"; then
    printf '%s\n' "${haystack}" >&2
    fail "${label} unexpectedly matched ${pattern}"
  fi
}

# Doctor's JSON escapes every forward slash (`\/`), so host paths only match
# after unescaping. Applied to REPLY right after each doctor --json capture the
# cache assertions read, never to run output, which is already plain text.
unescape_json_slashes() {
  printf '%s\n' "$1" | sed 's|\\/|/|g'
}

# First cargo-registry cache directory named in doctor output, or empty.
cargo_registry_cache() {
  printf '%s\n' "$1" | grep -Eo '/[^" ,]*/caches/[^" ,]+/cargo-registry' | head -1
}

run_and_capture() {
  local label="$1"
  shift

  section "${label}"
  local output
  if ! output="$("$@" 2>&1)"; then
    fail_for_container_prereq "${output}"
    printf '%s\n' "${output}" >&2
    exit 1
  fi
  printf '%s\n\n' "${output}"
  REPLY="${output}"
}

[[ -x "${SPAWN_BIN}" ]] || fail "release binary not found at ${SPAWN_BIN}; run 'make build' first"

run_and_capture "Build spawn-managed images" "${SPAWN_BIN}" build

run_and_capture "List spawn-managed images" "${SPAWN_BIN}" image list
expect_contains "${REPLY}" "spawn-base" "spawn image list"
expect_contains "${REPLY}" "spawn-rust" "spawn image list"
expect_contains "${REPLY}" "spawn-go" "spawn image list"
expect_contains "${REPLY}" "spawn-cpp" "spawn image list"
expect_contains "${REPLY}" "spawn-js" "spawn image list"

run_and_capture "Doctor JSON reports workspace defaults" "${SPAWN_BIN}" doctor "${ROOT}/fixtures/rust-sample" --json
REPLY="$(unescape_json_slashes "${REPLY}")"
expect_regex "${REPLY}" '"source"[[:space:]]*:[[:space:]]*"spawn-toml"' "rust doctor source"
expect_regex "${REPLY}" '"agent"[[:space:]]*:[[:space:]]*"codex"' "rust doctor agent default"
expect_regex "${REPLY}" '"access"[[:space:]]*:[[:space:]]*"minimal"' "rust doctor access default"
expect_regex "${REPLY}" 'rust \[workspace scope\]' "rust doctor cache scope"
expect_regex "${REPLY}" '/caches/rust-sample-[0-9a-f]+/cargo-registry' "rust doctor cache directories"
expect_regex "${REPLY}" '/caches/rust-sample-[0-9a-f]+/cargo-git' "rust doctor cache directories"
# The shared directory belongs to '--cache shared' only: a default run must
# never be told it uses it.
expect_not_regex "${REPLY}" '/caches/shared/' "rust doctor default cache scope"
RUST_FIXTURE_CACHE="$(cargo_registry_cache "${REPLY}")"
[[ -n "${RUST_FIXTURE_CACHE}" ]] || fail "rust doctor named no cargo registry cache directory"
# <state>/caches/shared, derived rather than hardcoded so this follows
# XDG_STATE_HOME wherever the run puts it.
SHARED_CACHE_DIR="$(dirname "$(dirname "${RUST_FIXTURE_CACHE}")")/shared"

# Same project contents at another path: the caches must not be the same
# directories, or one workspace could read and rewrite another's dependency
# sources.
CACHE_PROBE_DIR="$(mktemp -d)"
# The shared cache directory is removed on the way out only if this run created
# it: a user who has really opted into '--cache shared' has content there, and
# smoke must not wipe it. In the trap, so a failing assertion between here and
# the end does not leak it either.
SMOKE_CREATED_SHARED_CACHE=0
cleanup_cache_probe() {
  rm -rf "${CACHE_PROBE_DIR}"
  if [[ "${SMOKE_CREATED_SHARED_CACHE}" == "1" && "${SHARED_CACHE_DIR}" == */caches/shared ]]; then
    rm -rf "${SHARED_CACHE_DIR}"
  fi
}
trap cleanup_cache_probe EXIT
cp -R "${ROOT}/fixtures/rust-sample" "${CACHE_PROBE_DIR}/rust-sample"

run_and_capture "Doctor JSON scopes caches to the workspace path" \
  "${SPAWN_BIN}" doctor "${CACHE_PROBE_DIR}/rust-sample" --json
REPLY="$(unescape_json_slashes "${REPLY}")"
PROBE_CACHE="$(cargo_registry_cache "${REPLY}")"
[[ -n "${PROBE_CACHE}" ]] || fail "probe doctor named no cargo registry cache directory"
[[ "${PROBE_CACHE}" != "${RUST_FIXTURE_CACHE}" ]] \
  || fail "two workspaces were handed the same cache directory ${PROBE_CACHE}"

# A repo cannot widen its own cache reach: only '--cache shared' may do that.
printf '[workspace]\ncache = "shared"\n\n[toolchain]\nbase = "rust"\n' \
  >"${CACHE_PROBE_DIR}/rust-sample/.spawn.toml"
run_and_capture "Doctor JSON ignores a repo-configured shared cache" \
  "${SPAWN_BIN}" doctor "${CACHE_PROBE_DIR}/rust-sample" --json
REPLY="$(unescape_json_slashes "${REPLY}")"
expect_regex "${REPLY}" 'rust \[workspace scope\]' "repo-configured sharing must not change the scope"
expect_not_regex "${REPLY}" '/caches/shared/' "repo-configured sharing must not name the shared cache"
expect_regex "${REPLY}" 'cache=shared ignored' "doctor must report the ignored cache scope"

run_and_capture "Rust fixture: cwd default + passthrough command" \
  /bin/bash -lc "cd \"${ROOT}/fixtures/rust-sample\" && \"${SPAWN_BIN}\" -- cargo test"
expect_contains "${REPLY}" "session: command (cargo, 1 arg)" "rust passthrough launch summary"

# The real argv, not doctor's report of it: --verbose logs the container command
# spawn execs, so this is the only check that proves what a run actually mounts.
run_and_capture "Rust fixture: run argv mounts workspace-scoped caches" \
  /bin/bash -lc "cd \"${ROOT}/fixtures/rust-sample\" && \"${SPAWN_BIN}\" --verbose -- true"
expect_regex "${REPLY}" \
  "--volume ${RUST_FIXTURE_CACHE}:/opt/rust/cargo/registry" "run must mount this workspace's cargo registry cache"
expect_not_regex "${REPLY}" \
  '--volume [^ ]*/caches/shared/' "a default run must not mount the shared cache"
expect_not_regex "${REPLY}" \
  "--volume ${PROBE_CACHE}:" "a run must not mount another workspace's cache directory"
# The mount is only real if the host directory is: spawn creates it before the
# launch, and the guest writes into it.
[[ -d "${RUST_FIXTURE_CACHE}" ]] \
  || fail "spawn mounted ${RUST_FIXTURE_CACHE} without creating it on the host"

# The flag is the only way to reach the shared cache, and it must still work.
# Record whether it is absent first: if so, this run creates it and is therefore
# allowed to delete it afterwards.
if [[ ! -d "${SHARED_CACHE_DIR}" ]]; then
  SMOKE_CREATED_SHARED_CACHE=1
fi

run_and_capture "Rust fixture: --cache shared mounts the shared caches" \
  /bin/bash -lc "cd \"${ROOT}/fixtures/rust-sample\" && \"${SPAWN_BIN}\" --verbose --cache shared -- true"
expect_regex "${REPLY}" \
  "--volume ${SHARED_CACHE_DIR}/cargo-registry:/opt/rust/cargo/registry" "--cache shared must mount the shared cache"
expect_contains "${REPLY}" "readable and writable" "--cache shared must warn about the sharing"
expect_not_regex "${REPLY}" \
  "--volume ${RUST_FIXTURE_CACHE}:" "--cache shared must not also mount the private cache"
[[ -d "${SHARED_CACHE_DIR}/cargo-registry" ]] \
  || fail "spawn mounted ${SHARED_CACHE_DIR}/cargo-registry without creating it on the host"

run_and_capture "Go fixture: explicit workspace + access profile" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/go-sample" --access minimal -- /bin/bash -lc \
  'test ! -e /home/coder/.ssh && test ! -e /home/coder/.config/gh/hosts.yml && go version && go build ./... && go test -v ./... && echo "PASS: go-sample" && test -w /opt/go/pkg/mod && touch /opt/go/pkg/sumdb-probe'
expect_contains "${REPLY}" "access: minimal" "go access profile"
expect_contains "${REPLY}" "PASS: go-sample" "go fixture output"

run_and_capture "C++ fixture: explicit runtime selection" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/cpp-sample" --runtime spawn -- /bin/bash -lc \
  'clang --version | head -1 && mkdir -p build && cd build && cmake -G Ninja .. && ninja && ctest --output-on-failure && echo "PASS: cpp-sample"'
expect_contains "${REPLY}" "runtime: spawn" "cpp runtime selection"
expect_contains "${REPLY}" "PASS: cpp-sample" "cpp fixture output"

section "Node fixture: explicit runtime selection"
"${SPAWN_BIN}" -C "${ROOT}/fixtures/node-sample" --runtime spawn -- /bin/bash -lc \
  'node --version && npm --version && node --test && echo "PASS: node-sample"'
printf '\n'

section "Bun fixture: shell mode"
printf '%s\n' \
  'set -e' \
  'bun --version' \
  'bun test' \
  'echo "PASS: bun-sample"' \
  | "${SPAWN_BIN}" -C "${ROOT}/fixtures/bun-sample" --shell
printf '\n'

run_and_capture "Deno fixture: toolchain override" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/deno-sample" --toolchain js -- /bin/bash -lc \
  'deno --version && deno test && echo "PASS: deno-sample"'
expect_contains "${REPLY}" "toolchain: js (--toolchain override)" "deno toolchain override"
expect_contains "${REPLY}" "PASS: deno-sample" "deno fixture output"

run_and_capture "Workspace-image fixture: root Dockerfile build" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/workspace-image-sample" --runtime workspace-image -- workspace-image-smoke
expect_contains "${REPLY}" "workspace-image-ok" "workspace-image command output"
expect_contains "${REPLY}" "runtime: workspace-image" "workspace-image launch summary"

run_and_capture "Workspace-image fixture: cached reuse" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/workspace-image-sample" --runtime workspace-image -- workspace-image-smoke
expect_contains "${REPLY}" "Using cached workspace image" "workspace-image cache reuse"

run_and_capture "Workspace-image fixture: forced rebuild" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/workspace-image-sample" --runtime workspace-image --rebuild-workspace-image -- workspace-image-smoke
expect_contains "${REPLY}" "Rebuilding workspace image" "workspace-image forced rebuild"

run_and_capture "Workspace-image fixture: explicit spawn runtime" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/workspace-image-sample" --runtime spawn -- /bin/bash -lc \
  'test -f message.txt && echo "PASS: workspace-image-sample spawn runtime"'
expect_contains "${REPLY}" "PASS: workspace-image-sample spawn runtime" "workspace-image explicit spawn runtime"

run_and_capture "Doctor JSON reports Dockerfile workspace-image cache" \
  "${SPAWN_BIN}" doctor "${ROOT}/fixtures/workspace-image-sample" --json
expect_regex "${REPLY}" '"source"[[:space:]]*:[[:space:]]*"dockerfile"' "workspace-image doctor source"
expect_regex "${REPLY}" '"cacheStatus"[[:space:]]*:[[:space:]]*"ready"' "workspace-image doctor cache"

run_and_capture "Workspace-image fixture: devcontainer build" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/devcontainer-sample" --runtime workspace-image -- devcontainer-smoke
expect_contains "${REPLY}" "devcontainer-workspace-image-ok" "devcontainer workspace-image command output"

run_and_capture "Doctor JSON reports devcontainer workspace-image cache" \
  "${SPAWN_BIN}" doctor "${ROOT}/fixtures/devcontainer-sample" --json
expect_regex "${REPLY}" '"source"[[:space:]]*:[[:space:]]*"devcontainer-dockerfile"' "devcontainer doctor source"
expect_regex "${REPLY}" '"cacheStatus"[[:space:]]*:[[:space:]]*"ready"' "devcontainer doctor cache"

section "Toolchain images keep /home/coder identical to base"
# The invariant this slice exists to establish: a toolchain image must not add
# anything to /home/coder. If this fails, a toolchain is leaking into the home,
# which mixes build state with user state and makes the home expensive to copy.
#
# Compare sorted listings of every entry plus the content of every file, not
# file counts: the base home is built largely from symlinks (.claude.json,
# .gitconfig) and directories (.claude-state, .gitconfig-dir, .local/bin), so
# counting only `-type f` would wave through a compatibility symlink such as
# `ln -s /opt/rust/cargo /home/coder/.cargo`, a directory-only leak, or a
# one-added-one-removed swap.
#
# The listing carries type and symlink target (`%y %l`) as well as the path, so
# a retargeted symlink is caught even though `.claude.json` is dangling and thus
# invisible to `-type f`; the md5sums catch a same-path content change, such as
# a `.bashrc` that regained the bun/deno installer's `export` lines because the
# `/etc/skel` restore moved above the installers. `find -printf` is GNU find,
# which is what these Ubuntu images ship — this runs inside the container.
home_listing() {
  "${CONTAINER_BIN}" run --rm "$1" /bin/sh -c '
    find /home/coder -mindepth 1 -printf "%p %y %l\n" | LC_ALL=C sort
    find /home/coder -type f -exec md5sum {} + | LC_ALL=C sort
  '
}

base_home_listing="$(home_listing spawn-base:latest)"
[[ -n "${base_home_listing}" ]] \
  || fail "could not list /home/coder in spawn-base:latest (empty listing)"

for toolchain in cpp rust go js; do
  toolchain_home_listing="$(home_listing "spawn-${toolchain}:latest")"
  [[ -n "${toolchain_home_listing}" ]] \
    || fail "could not list /home/coder in spawn-${toolchain}:latest (empty listing)"

  if [[ "${toolchain_home_listing}" != "${base_home_listing}" ]]; then
    printf 'differences under /home/coder ("<" only in spawn-%s, ">" only in spawn-base):\n' "${toolchain}" >&2
    diff <(printf '%s\n' "${toolchain_home_listing}") <(printf '%s\n' "${base_home_listing}") >&2 || true
    fail "spawn-${toolchain} does not keep /home/coder identical to spawn-base: toolchains must live under /opt, not in the home — or, if the differences are only timestamped names (.claude/backups, .npm/_logs), the images were built from different spawn-base layers, so rebuild all images with 'spawn build'"
  fi
done
# Entry lines start with the path; md5sum lines start with a hash, so counting
# the former reports entries rather than entries-plus-checksums.
printf 'PASS: all toolchain images keep /home/coder identical to base (%s entries, contents included)\n\n' \
  "$(printf '%s\n' "${base_home_listing}" | grep -c '^/home/coder' | tr -d '[:space:]')"

printf '=== All smoke tests passed ===\n'
