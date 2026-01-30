.PHONY: build run clean test lint fmt universal

# Build for current platform
build:
	go build -o claude-prompt-server

# Run linter
lint:
	golangci-lint run

# Format code
fmt:
	gofmt -s -w .
	goimports -w .

# Build with optimizations
build-release:
	go build -ldflags="-s -w" -o claude-prompt-server

# Run with verbose logging
run:
	VERBOSE=true go run main.go

# Run tests
test:
	go test ./...

# Clean build artifacts
clean:
	rm -f claude-prompt-server claude-prompt-server-*

# Build for macOS Intel
build-intel:
	GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o claude-prompt-server-intel

# Build for macOS Apple Silicon
build-arm64:
	GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o claude-prompt-server-arm64

# Build universal binary for macOS (requires macOS with lipo)
universal: build-intel build-arm64
	lipo -create -output claude-prompt-server claude-prompt-server-intel claude-prompt-server-arm64
	rm claude-prompt-server-intel claude-prompt-server-arm64
	@echo "Universal binary created: claude-prompt-server"
	@file claude-prompt-server
	@ls -lh claude-prompt-server

# Install locally
install: build-release
	cp claude-prompt-server /usr/local/bin/
