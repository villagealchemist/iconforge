# Makefile for iconforge

PROCESSOR_DIR := iconforge-processor
PROCESSOR_BIN := iconforge-processor
NATIVE_ICON_DIR := iconforge-native-icon
NATIVE_ICON_BIN := iconforge-native-icon
NATIVE_ICON_SOURCE := $(NATIVE_ICON_DIR)/main.m
SCRIPT_NAME := iconforge.sh
TEST_DIR := tests
VERSION := $(shell tr -d '[:space:]' < VERSION)
GO_LDFLAGS := -s -w -X main.version=$(VERSION)
PREFIX ?= $(HOME)/.local
SHELL_TESTS := $(filter-out $(TEST_DIR)/test-all.sh $(TEST_DIR)/test-common.sh $(TEST_DIR)/test-env.sh,$(wildcard $(TEST_DIR)/test-*.sh))

.PHONY: all
all: build

.PHONY: help
help:
	@echo "iconforge Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make build            Build the bundled Go processor and native icon helper"
	@echo "  make build-all        Build release binaries for supported macOS architectures"
	@echo "  make install          Install iconforge into $(PREFIX)"
	@echo "  make uninstall        Remove iconforge from $(PREFIX)"
	@echo "  make test             Run shell + Go tests"
	@echo "  make test-verbose     Run shell tests inline"
	@echo "  make test-go          Run Go tests only"
	@echo "  make lint             Run shellcheck/go vet/go fmt"
	@echo "  make clean            Remove build artifacts and tmp files"
	@echo "  make version          Print iconforge version"

.PHONY: deps
deps:
	@cd $(PROCESSOR_DIR) && go mod download

.PHONY: build build-processor build-native-icon
build: build-processor build-native-icon

build-processor: deps
	@echo "Building $(PROCESSOR_BIN)..."
	@cd $(PROCESSOR_DIR) && go build -ldflags="$(GO_LDFLAGS)" -o $(PROCESSOR_BIN)

build-native-icon:
	@echo "Building $(NATIVE_ICON_BIN)..."
	@xcrun clang -fobjc-arc -Wall -Wextra -framework AppKit -framework Foundation \
		$(NATIVE_ICON_SOURCE) -o $(NATIVE_ICON_DIR)/$(NATIVE_ICON_BIN)

.PHONY: build-all
build-all: deps
	@cd $(PROCESSOR_DIR) && \
		GOOS=darwin GOARCH=amd64 go build -ldflags="$(GO_LDFLAGS)" -o ../$(PROCESSOR_BIN)-darwin-amd64 && \
		GOOS=darwin GOARCH=arm64 go build -ldflags="$(GO_LDFLAGS)" -o ../$(PROCESSOR_BIN)-darwin-arm64
	@xcrun clang -fobjc-arc -Wall -Wextra -arch x86_64 -framework AppKit -framework Foundation \
		$(NATIVE_ICON_SOURCE) -o $(NATIVE_ICON_BIN)-darwin-amd64
	@xcrun clang -fobjc-arc -Wall -Wextra -arch arm64 -framework AppKit -framework Foundation \
		$(NATIVE_ICON_SOURCE) -o $(NATIVE_ICON_BIN)-darwin-arm64

.PHONY: install
install: build
	@PREFIX="$(PREFIX)" ./install.sh

.PHONY: uninstall
uninstall:
	@PREFIX="$(PREFIX)" ./uninstall.sh

.PHONY: version
version:
	@./$(SCRIPT_NAME) --version

.PHONY: test-go
test-go:
	@cd $(PROCESSOR_DIR) && go test -v ./...

.PHONY: test
test: build test-go
	@bash $(TEST_DIR)/test-all.sh

.PHONY: test-verbose
test-verbose: build
	@bash -c 'set -euo pipefail; \
		TEST_NAME="verbose test suite"; \
		source $(TEST_DIR)/test-common.sh; \
		for test in $(TEST_DIR)/test-*.sh; do \
			case $$test in \
				*test-all.sh|*test-common.sh|*test-env.sh) continue ;; \
			esac; \
			test_run "$$test"; \
			bash "$$test"; \
			printf "\n"; \
		done'

.PHONY: lint
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck --external-sources $(SCRIPT_NAME) $(SHELL_TESTS); \
	else \
		echo "shellcheck not installed; skipping shell lint"; \
	fi
	@cd $(PROCESSOR_DIR) && go vet ./...
	@unformatted="$$(gofmt -l $(PROCESSOR_DIR)/*.go)"; \
		if [ -n "$$unformatted" ]; then \
			echo "Go files need formatting:"; \
			echo "$$unformatted"; \
			exit 1; \
		fi

.PHONY: clean
clean:
	@rm -rf tmp tests/tmp*
	@rm -f $(PROCESSOR_DIR)/$(PROCESSOR_BIN) $(PROCESSOR_BIN)-*
	@rm -f $(NATIVE_ICON_DIR)/$(NATIVE_ICON_BIN) $(NATIVE_ICON_BIN)-darwin-*
	@cd $(PROCESSOR_DIR) && go clean
