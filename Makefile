# Makefile for iconforge – https://github.com/villagealchemist/iconforge

# Paths
BIN_DIR := bin
TEST_DIR := tests
SRC := $(BIN_DIR)/iconforge.sh

# Default target
.PHONY: all
all: help

# Help text
.PHONY: help
help:
	@echo "🛠  iconforge Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make install       Install iconforge globally (via ./install.sh)"
	@echo "  make uninstall     Uninstall iconforge (via ./uninstall.sh)"
	@echo "  make test          Run the full test suite"
	@echo "  make test-verbose  Run all tests with full output"
	@echo "  make clean         Remove all tmp/ test artifacts"
	@echo "  make lint          Run basic lint checks"
	@echo "  make version       Show the script version"
	@echo ""

# Version output
.PHONY: version
version:
	@bash $(SRC) --version

# Install + Uninstall
.PHONY: install uninstall
install:
	@./install.sh

uninstall:
	@./uninstall.sh

# Run all tests with silent success logs
.PHONY: test
test:
	@echo "🧪 Running test suite..."
	@bash $(TEST_DIR)/test_all.sh

# Verbose mode: show logs inline
.PHONY: test-verbose
test-verbose:
	@echo "🧪 Running test suite (verbose)..."
	@for test in $(TEST_DIR)/test_*.sh; do \
		case $$test in \
			*test_common.sh|*test_all.sh) continue ;; \
		esac; \
		echo "▶️  $$test"; \
		bash $$test; \
		echo ""; \
	done

# Remove temp files
.PHONY: clean
clean:
	@echo "🧹 Cleaning test artifacts..."
	@rm -rf $(TEST_DIR)/tmp* tmp/

# Bump version inside the script (but don't commit or tag)
.PHONY: bump
bump:
	@read -p "Enter new version (e.g. 1.1.0): " RAW_VERSION; \
	FILE=bin/iconforge.sh; \
	echo "🔧 Updating version in $$FILE to $$RAW_VERSION..."; \
	sed -i '' "s/^VERSION=.*/VERSION=\"$$RAW_VERSION\"/" $$FILE; \
	echo "✅ Version bumped to $$RAW_VERSION (not committed)"

# Tag and push the current commit as a release
.PHONY: release
release:
	@read -p "Enter version tag (e.g. v1.1.0): " VERSION; \
	[[ "$$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$$ ]] || { echo "❌ Invalid tag format"; exit 1; }; \
	git diff --quiet || echo "⚠️ Warning: working directory has uncommitted changes"; \
	git tag -a "$$VERSION" -m "Release $$VERSION"; \
	git push origin "$$VERSION"; \
	echo "✅ Tagged and pushed $$VERSION"
