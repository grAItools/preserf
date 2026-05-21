.PHONY: help test test-all lint fmt verify dev clean

help:  ## Show this help
	@awk 'BEGIN {FS = ":.*##"; printf "Usage: make \033[36m<target>\033[0m\n\nTargets:\n"} \
	/^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

test:  ## Run fast unit tests
	pixi run -e dev pytest

test-all: test  ## Run the full suite (override to add integration/e2e)
	@echo "test-all: extend this target with integration suites as needed"

lint:  ## Run static checks (does not auto-fix)
	pixi run -e dev lint

fmt:  ## Auto-format the codebase
	pixi run -e dev fmt

verify:  ## What the agent runs before claiming done
	@./scripts/verify.sh

dev:  ## Run the local dev workflow (override per-project)
	@echo "dev: override this target to start your dev server / watcher"

clean:  ## Remove generated artefacts (override per-project)
	@echo "clean: override this target to remove build/ dist/ etc."
