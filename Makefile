PREFIX ?= $(HOME)/.local
BINARY = spawn
XCODE_DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

ifneq ($(wildcard $(XCODE_DEVELOPER_DIR)),)
DEVELOPER_DIR ?= $(XCODE_DEVELOPER_DIR)
export DEVELOPER_DIR
endif

.PHONY: build install uninstall clean test lint format images smoke

build:
	swift build -c release

lint:
	swift format lint --strict -r Sources Tests

format:
	swift format format --in-place -r Sources Tests

test: lint
	swift test

install: build
	install -d $(PREFIX)/bin
	install .build/release/$(BINARY) $(PREFIX)/bin/$(BINARY)

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)

clean:
	swift package clean

smoke: build
	@echo "=== C++ fixture: build + test ==="
	echo 'set -e && clang --version | head -1 && mkdir -p build && cd build && cmake -G Ninja .. 2>&1 && ninja 2>&1 && ctest --output-on-failure 2>&1 && echo "PASS: cpp-sample"' | \
		.build/release/$(BINARY) fixtures/cpp-sample --shell
	@echo ""
	@echo "=== Go fixture: build + test ==="
	echo 'set -e && go version && go build ./... && go test -v ./... && echo "PASS: go-sample"' | \
		.build/release/$(BINARY) fixtures/go-sample --shell
	@echo ""
	@echo "=== Rust fixture: build + test ==="
	echo 'set -e && rustc --version && cargo build 2>&1 && cargo test 2>&1 && echo "PASS: rust-sample"' | \
		.build/release/$(BINARY) fixtures/rust-sample --shell
	@echo ""
	@echo "=== Node fixture: build + test ==="
	echo 'set -e && node --version && npm --version && node --test && echo "PASS: node-sample"' | \
		.build/release/$(BINARY) fixtures/node-sample --shell
	@echo ""
	@echo "=== Bun fixture: build + test ==="
	echo 'set -e && bun --version && bun test && echo "PASS: bun-sample"' | \
		.build/release/$(BINARY) fixtures/bun-sample --shell
	@echo ""
	@echo "=== Deno fixture: build + test ==="
	echo 'set -e && deno --version && deno test && echo "PASS: deno-sample"' | \
		.build/release/$(BINARY) fixtures/deno-sample --shell
	@echo ""
	@echo "=== All smoke tests passed ==="

images:
	container build -t spawn-base:latest -f Images/base/Containerfile .
	container build -t spawn-cpp:latest -f Images/cpp/Containerfile .
	container build -t spawn-rust:latest -f Images/rust/Containerfile .
	container build -t spawn-go:latest -f Images/go/Containerfile .
	container build -t spawn-js:latest -f Images/js/Containerfile .
