.PHONY: build clean install

# Build the Go hook binary
build:
	cd .. && go build -o hooks/prompt-hook hooks/prompt-hook.go

# Build with optimizations
build-release:
	cd .. && go build -ldflags="-s -w" -o hooks/prompt-hook hooks/prompt-hook.go

# Clean build artifacts
clean:
	rm -f prompt-hook

# Build and make executable
install: build
	chmod +x prompt-hook
	@echo "Built hooks/prompt-hook"
	@echo "To use this hook, configure Claude Code with:"
	@echo "  \"hooks\": {"
	@echo "    \"PreToolUse\": \"$(PWD)/prompt-hook\""
	@echo "  }"
