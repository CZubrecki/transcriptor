.DEFAULT_GOAL := help
.PHONY: help build release test run clean

BINARY := transcriptor

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-8s\033[0m %s\n", $$1, $$2}'

build: ## Build the debug binary
	swift build

release: ## Build the optimized release binary
	swift build -c release

test: ## Run the test suite
	swift test

run: ## Run the CLI. Pass flags with ARGS="videos/session.mp4 --force"
	swift run $(BINARY) $(ARGS)

clean: ## Remove build artifacts
	swift package clean
