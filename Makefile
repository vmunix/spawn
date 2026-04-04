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
	./scripts/smoke.sh

images:
	container build -t spawn-base:latest -f Images/base/Containerfile .
	container build -t spawn-cpp:latest -f Images/cpp/Containerfile .
	container build -t spawn-rust:latest -f Images/rust/Containerfile .
	container build -t spawn-go:latest -f Images/go/Containerfile .
	container build -t spawn-js:latest -f Images/js/Containerfile .
