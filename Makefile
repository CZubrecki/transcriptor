.DEFAULT_GOAL := help
.PHONY: help build release test run clean format lint check-tools

BINARY := transcriptor

# Local tooling must match CI. Bump both here and in .github/workflows/ci.yml.
SWIFTFORMAT_VERSION := 0.62.1
SWIFTLINT_VERSION := 0.65.0

help: ## List available targets
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) \
		| awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Build the debug binary
	swift build

release: ## Build the optimized release binary
	swift build -c release

test: ## Run the test suite
	swift test

run: ## Run the CLI. Pass flags with ARGS="videos/session.mp4 --force"
	swift run $(BINARY) $(ARGS)

format: ## Format the sources in place
	swiftformat Sources Tests

lint: ## Check formatting and lint without changing anything
	swiftformat Sources Tests --lint
	swiftlint lint --quiet --strict Sources Tests

check-tools: ## Verify the formatting tools are installed at the pinned versions
	@command -v swiftformat >/dev/null || { echo "swiftformat missing: brew install swiftformat"; exit 1; }
	@command -v swiftlint >/dev/null || { echo "swiftlint missing: brew install swiftlint"; exit 1; }
	@[ "$$(swiftformat --version)" = "$(SWIFTFORMAT_VERSION)" ] || echo "warning: swiftformat $$(swiftformat --version) differs from pinned $(SWIFTFORMAT_VERSION)"
	@[ "$$(swiftlint version)" = "$(SWIFTLINT_VERSION)" ] || echo "warning: swiftlint $$(swiftlint version) differs from pinned $(SWIFTLINT_VERSION)"

clean: ## Remove build artifacts
	swift package clean
