# Makefile for iconforge

PROCESSOR_DIR := iconforge-processor
PROCESSOR_BIN := iconforge-processor
SCRIPT_NAME := iconforge.sh
TEST_DIR := tests
VERSION := $(shell tr -d '[:space:]' < VERSION)
GO_LDFLAGS := -s -w -X main.version=$(VERSION)

.PHONY: all
all: build

.PHONY: help
help:
	@echo "iconforge Makefile"
	@echo ""
	@echo "Available targets:"
	@echo "  make build            Build the bundled Go image processor"
	@echo "  make build-all        Build processor binaries for multiple platforms"
	@echo "  make install          Install iconforge into /usr/local"
	@echo "  make uninstall        Remove the installed runtime"
	@echo "  make test             Run shell + Go tests"
	@echo "  make test-verbose     Run shell tests inline"
	@echo "  make test-go          Run Go tests only"
	@echo "  make lint             Run shellcheck/go vet/go fmt"
	@echo "  make clean            Remove build artifacts and tmp files"
	@echo "  make version          Print iconforge version"

.PHONY: deps
deps:
	@cd $(PROCESSOR_DIR) && go mod download

.PHONY: build
build: deps
	@echo "Building $(PROCESSOR_BIN)..."
	@cd $(PROCESSOR_DIR) && go build -ldflags="$(GO_LDFLAGS)" -o $(PROCESSOR_BIN)

.PHONY: build-all
build-all: deps
	@cd $(PROCESSOR_DIR) && \
		GOOS=darwin GOARCH=amd64 go build -ldflags="$(GO_LDFLAGS)" -o ../$(PROCESSOR_BIN)-darwin-amd64 && \
		GOOS=darwin GOARCH=arm64 go build -ldflags="$(GO_LDFLAGS)" -o ../$(PROCESSOR_BIN)-darwin-arm64 && \
		GOOS=linux GOARCH=amd64 go build -ldflags="$(GO_LDFLAGS)" -o ../$(PROCESSOR_BIN)-linux-amd64

.PHONY: install
install: build
	@./install.sh

.PHONY: uninstall
uninstall:
	@./uninstall.sh

.PHONY: version
version:
	@./$(SCRIPT_NAME) --version

.PHONY: test-go
test-go:
	@cd $(PROCESSOR_DIR) && go test -v ./...

.PHONY: test
test: build test-go
	@bash $(TEST_DIR)/test_all.sh

.PHONY: test-verbose
test-verbose: build
	@for test in $(TEST_DIR)/test_*.sh; do \
		case $$test in \
			*test_all.sh|*test_common.sh) continue ;; \
		esac; \
		echo "Running $$test"; \
		bash $$test; \
		echo ""; \
	done

.PHONY: lint
lint:
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck $(SCRIPT_NAME) iconforge.sh lib/iconforge/*.sh tests/test_*.sh; \
	else \
		echo "shellcheck not installed; skipping shell lint"; \
	fi
	@cd $(PROCESSOR_DIR) && go vet ./...
	@cd $(PROCESSOR_DIR) && go fmt ./...

.PHONY: clean
clean:
	@rm -rf tmp tests/tmp*
	@rm -f $(PROCESSOR_DIR)/$(PROCESSOR_BIN) $(PROCESSOR_BIN)-*
	@cd $(PROCESSOR_DIR) && go clean
