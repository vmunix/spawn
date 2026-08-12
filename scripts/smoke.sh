#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SPAWN_BIN="${ROOT}/.build/release/spawn"
CONTAINER_BIN="${CONTAINER_BIN:-container}"

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

  if ! printf '%s\n' "${haystack}" | grep -Eq "${pattern}"; then
    printf '%s\n' "${haystack}" >&2
    fail "${label} did not match ${pattern}"
  fi
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
expect_regex "${REPLY}" '"source"[[:space:]]*:[[:space:]]*"spawn-toml"' "rust doctor source"
expect_regex "${REPLY}" '"agent"[[:space:]]*:[[:space:]]*"codex"' "rust doctor agent default"
expect_regex "${REPLY}" '"access"[[:space:]]*:[[:space:]]*"minimal"' "rust doctor access default"
expect_contains "${REPLY}" "spawn-cache-cargo-registry" "rust doctor cache volumes"
expect_contains "${REPLY}" "spawn-cache-cargo-git" "rust doctor cache volumes"

run_and_capture "Rust fixture: cwd default + passthrough command" \
  /bin/bash -lc "cd \"${ROOT}/fixtures/rust-sample\" && \"${SPAWN_BIN}\" -- cargo test"
expect_contains "${REPLY}" "session: command (cargo, 1 arg)" "rust passthrough launch summary"

run_and_capture "Go fixture: explicit workspace + access profile" \
  "${SPAWN_BIN}" -C "${ROOT}/fixtures/go-sample" --access minimal -- /bin/bash -lc \
  'test ! -e /home/coder/.ssh && test ! -e /home/coder/.config/gh/hosts.yml && go version && go build ./... && go test -v ./... && echo "PASS: go-sample"'
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
home_file_count() {
  "${CONTAINER_BIN}" run --rm "$1" /bin/sh -c 'find /home/coder -type f | wc -l' | tr -d '[:space:]'
}

base_home_count="$(home_file_count spawn-base:latest)"
[[ "${base_home_count}" =~ ^[1-9][0-9]*$ ]] \
  || fail "could not count files under /home/coder in spawn-base:latest (got '${base_home_count}')"

for toolchain in cpp rust go js; do
  toolchain_home_count="$(home_file_count "spawn-${toolchain}:latest")"
  if [[ "${toolchain_home_count}" != "${base_home_count}" ]]; then
    fail "spawn-${toolchain} has ${toolchain_home_count} files under /home/coder, spawn-base has ${base_home_count}: toolchains must live under /opt, not in the home"
  fi
done
printf 'PASS: all toolchain images keep /home/coder identical to base (%s files)\n\n' "${base_home_count}"

printf '=== All smoke tests passed ===\n'
