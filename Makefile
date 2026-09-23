PREFIX ?= $(HOME)/.local
BINARY = spawn
XCODE_DEVELOPER_DIR := /Applications/Xcode.app/Contents/Developer

ifneq ($(wildcard $(XCODE_DEVELOPER_DIR)),)
DEVELOPER_DIR ?= $(XCODE_DEVELOPER_DIR)
export DEVELOPER_DIR
endif

.PHONY: build install uninstall clean test lint format smoke

build:
	swift build -c release
	codesign --force --sign - --timestamp=none --entitlements spawn.entitlements .build/release/$(BINARY)

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
