SHELL := /bin/bash
.SHELLFLAGS = -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:
MAKEFLAGS += --no-print-directory

UNAME_S := $(shell uname -s)
AVAILABLE_ARCHITECTURES := x86_64 aarch64 i386

# Variables
TARGET_ARCH ?= x86_64
QEMU        ?= qemu-system-$(TARGET_ARCH)
FLOPPY      ?= ecclesia-$(TARGET_ARCH).img
WRITER      ?= scripts/write-kernel.lisp

# Conditional variables
ifeq ($(TARGET_ARCH),aarch64)
QEMU_MACHINE_ARGS ?= -machine virt -nographic
QEMU_MONITOR_ARGS ?=
QEMU_BOOT_ARGS    ?= -drive file=$(FLOPPY),format=raw,if=none,id=bootdisk -device virtio-blk-device,drive=bootdisk
else
QEMU_MACHINE_ARGS ?=
QEMU_MONITOR_ARGS ?= -monitor stdio
QEMU_BOOT_ARGS    ?= -drive file=$(FLOPPY),if=floppy,format=raw
endif

# Preconditions
ifeq ($(filter $(TARGET_ARCH),$(AVAILABLE_ARCHITECTURES)),)
$(error Unsupported TARGET_ARCH '$(TARGET_ARCH)'. Available: $(AVAILABLE_ARCHITECTURES))
endif

# Default exports
export TARGET_ARCH

# Source files
SOURCES   := ecclesia.asd $(wildcard src/*.lisp src/*.asm) $(WRITER)

##@ Environment Setup

.PHONY: setup
setup: setup/hooks setup/sbcl setup/qemu ## Install all development dependencies

.PHONY: setup/hooks
setup/hooks: ## Install git hooks
	ln -sf "$(PWD)/git/hooks/pre-commit" .git/hooks/pre-commit
	@echo "✅ Git hooks installed"

.PHONY: setup/sbcl
setup/sbcl: ## Install SBCL
ifeq ($(UNAME_S),Linux)
	sudo apt update && sudo apt install -y sbcl
else ifeq ($(UNAME_S),Darwin)
	brew install sbcl
else
	$(error "Unsupported OS: $(UNAME_S). Please install SBCL manually.")
endif

.PHONY: setup/qemu
setup/qemu: ## Install QEMU
ifeq ($(UNAME_S),Linux)
	sudo apt update && sudo apt install -y qemu-system-x86
else ifeq ($(UNAME_S),Darwin)
	brew install qemu
else
	$(error "Unsupported OS: $(UNAME_S). Please install QEMU manually.")
endif

##@ Development Tasks

$(FLOPPY): $(SOURCES)
	echo "[+] Building floppy image..."
	./$(WRITER)

.PHONY: boot
boot: build ## Build and boot in QEMU
	echo "[+] Launching in QEMU..."
	$(QEMU) $(QEMU_MACHINE_ARGS) $(QEMU_BOOT_ARGS) $(QEMU_MONITOR_ARGS) -m 32

.PHONY: boot-once
boot-once: build ## Boot in QEMU, halt instead of reboot on triple fault
	echo "[+] Launching in QEMU (no-reboot)..."
	$(QEMU) $(QEMU_MACHINE_ARGS) $(QEMU_BOOT_ARGS) $(QEMU_MONITOR_ARGS) -m 32 -no-reboot -no-shutdown

.PHONY: build
build: $(FLOPPY) ## Assemble kernel image via SBCL
	:

.PHONY: build/all
build/all:
	for arch in $(AVAILABLE_ARCHITECTURES); do
		TARGET_ARCH=$${arch} $(MAKE) build
	done

.PHONY: clean
clean: clean/floppy clean/lisp ## Remove build artifacts

.PHONY: clean/floppy
clean/floppy:
	rm -f *.img

.PHONY: clean/lisp
clean/lisp: ## Force ASDF to recompile all Lisp sources on next build
	rm -rf ~/.cache/common-lisp

.PHONY: debug
debug: build ## Build and boot in QEMU with GDB support
	echo "[+] Launching in QEMU (GDB on :1234)..."
	$(QEMU) $(QEMU_MACHINE_ARGS) $(QEMU_BOOT_ARGS) $(QEMU_MONITOR_ARGS) -m 32 -s -S

.PHONY: debug-log
debug-log: build ## Boot with CPU exception logging to /tmp/qemu.log
	echo "[+] Launching in QEMU (logging to /tmp/qemu.log)..."
	$(QEMU) $(QEMU_MACHINE_ARGS) $(QEMU_BOOT_ARGS) -m 32 -no-reboot -no-shutdown \
	        -d int,cpu_reset,cpu -D /tmp/qemu.log 2>/dev/null & \
	sleep 3 && kill %1 2>/dev/null; \
	echo "[+] Last entries in /tmp/qemu.log:"; \
	tail -60 /tmp/qemu.log

.PHONY: test
test: test/unit ## Run tests

.PHONY: test/unit
test/unit: ## Run unit tests
	./scripts/run-tests.lisp

##@ Utilities

.PHONY: help
help: ## Show available targets
	awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\n"} /^[a-zA-Z_0-9/-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
