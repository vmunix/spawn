PREFIX ?= /usr/local
BINARY = spawn

.PHONY: build install uninstall clean test images

build:
	swift build -c release

test:
	swift test

install: build
	install -d $(PREFIX)/bin
	install .build/release/$(BINARY) $(PREFIX)/bin/$(BINARY)

uninstall:
	rm -f $(PREFIX)/bin/$(BINARY)

clean:
	swift package clean

images:
	container build -t spawn-base:latest -f Images/base/Containerfile .
	container build -t spawn-cpp:latest -f Images/cpp/Containerfile .
	container build -t spawn-rust:latest -f Images/rust/Containerfile .
	container build -t spawn-go:latest -f Images/go/Containerfile .
