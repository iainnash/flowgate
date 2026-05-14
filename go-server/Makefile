.PHONY: build run clean test lint fmt universal

# Build for current platform
build:
	go build -o flowgate-server

# Run linter
lint:
	golangci-lint run

# Format code
fmt:
	gofmt -s -w .
	goimports -w .

# Build with optimizations
build-release:
	go build -ldflags="-s -w" -o flowgate-server

# Run with verbose logging
run:
	VERBOSE=true go run main.go

# Run tests
test:
	go test ./...

# Clean build artifacts
clean:
	rm -f flowgate-server flowgate-server-*

# Build for macOS Intel
build-intel:
	GOOS=darwin GOARCH=amd64 go build -ldflags="-s -w" -o flowgate-server-intel

# Build for macOS Apple Silicon
build-arm64:
	GOOS=darwin GOARCH=arm64 go build -ldflags="-s -w" -o flowgate-server-arm64

# Build universal binary for macOS (requires macOS with lipo)
universal: build-intel build-arm64
	lipo -create -output flowgate-server flowgate-server-intel flowgate-server-arm64
	rm flowgate-server-intel flowgate-server-arm64
	@echo "Universal binary created: flowgate-server"
	@file flowgate-server
	@ls -lh flowgate-server

# Install locally
install: build-release
	cp flowgate-server /usr/local/bin/
