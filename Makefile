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
WRITER      ?= scripts/write-kernel.lisp

# Per-arch image name and boot style
# AArch64 target board.
# Supported: qemu-virt, raspi4b, raspi3b
# Default: qemu-virt (safe for QEMU testing without real hardware)
TARGET_BOARD ?= qemu-virt
export TARGET_BOARD

# Map TARGET_BOARD → QEMU -machine and -cpu args
ifeq ($(TARGET_BOARD),qemu-virt)
  QEMU_BOARD_MACHINE ?= virt
  QEMU_BOARD_CPU     ?= -cpu cortex-a57
else ifeq ($(TARGET_BOARD),raspi4b)
  QEMU_BOARD_MACHINE ?= raspi4b
  QEMU_BOARD_CPU     ?=
else ifeq ($(TARGET_BOARD),raspi3b)
  QEMU_BOARD_MACHINE ?= raspi3b
  QEMU_BOARD_CPU     ?=
else
  $(error Unsupported TARGET_BOARD '$(TARGET_BOARD)'. Supported: qemu-virt raspi4b raspi3b)
endif

ifeq ($(TARGET_ARCH),aarch64)
IMAGE             ?= build/ecclesia-$(TARGET_ARCH).bin
QEMU_MACHINE_ARGS ?= -machine $(QEMU_BOARD_MACHINE) $(QEMU_BOARD_CPU)
QEMU_MONITOR_ARGS ?= -monitor stdio
QEMU_BOOT_ARGS    ?= -kernel $(IMAGE)
else
IMAGE             ?= build/ecclesia-$(TARGET_ARCH).img
QEMU_MACHINE_ARGS ?=
QEMU_MONITOR_ARGS ?= -monitor stdio
QEMU_BOOT_ARGS    ?= -drive file=$(IMAGE),if=floppy,format=raw
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
setup: setup/hooks setup/sbcl setup/qemu setup/toolchain ## Install all development dependencies

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
	sudo apt update && sudo apt install -y qemu-system-x86 qemu-system-arm
else ifeq ($(UNAME_S),Darwin)
	brew install qemu
else
	$(error "Unsupported OS: $(UNAME_S). Please install QEMU manually.")
endif

.PHONY: setup/toolchain
setup/toolchain: ## Install cross-compilers for all supported architectures
ifeq ($(UNAME_S),Linux)
	sudo apt update && sudo apt install -y \
	    gcc \
	    gcc-x86-64-linux-gnu \
	    gcc-i686-linux-gnu \
	    gcc-aarch64-linux-gnu \
	    binutils-x86-64-linux-gnu \
	    binutils-i686-linux-gnu \
	    binutils-aarch64-linux-gnu
	@echo "✅ Cross-compilers installed"
else ifeq ($(UNAME_S),Darwin)
	brew install x86_64-elf-gcc i686-elf-gcc aarch64-elf-gcc 2>/dev/null || \
	brew install x86_64-elf-binutils i686-elf-binutils aarch64-elf-binutils
	@echo "✅ Cross-compilers installed (via Homebrew)"
else
	$(error "Unsupported OS: $(UNAME_S). Please install cross-compilers manually.")
endif

##@ Development Tasks

$(IMAGE): userland $(SOURCES)
	echo "[+] Building image..."
	mkdir -p $$(dirname $(IMAGE))
	IMAGE="$(IMAGE)" ./$(WRITER)

.PHONY: boot
boot: build ## Build and boot in QEMU
	echo "[+] Launching in QEMU..."
	$(QEMU) $(QEMU_MACHINE_ARGS) $(QEMU_BOOT_ARGS) $(QEMU_MONITOR_ARGS) -m 32

.PHONY: boot-once
boot-once: build ## Boot in QEMU, halt instead of reboot on triple fault
	echo "[+] Launching in QEMU (no-reboot)..."
	$(QEMU) $(QEMU_MACHINE_ARGS) $(QEMU_BOOT_ARGS) $(QEMU_MONITOR_ARGS) -m 32 -no-reboot -no-shutdown

.PHONY: build
build: $(IMAGE) ## Assemble kernel image via SBCL
	:

.PHONY: build/all
build/all:
	for arch in $(AVAILABLE_ARCHITECTURES); do
		$(MAKE) build TARGET_ARCH=$${arch} 
	done

.PHONY: clean
clean: clean/images clean/lisp clean/userland ## Remove build artifacts

.PHONY: clean/images
clean/images:
	rm -f build/*.img build/*.bin *.img *.bin

.PHONY: clean/lisp
clean/lisp: ## Force ASDF to recompile all Lisp sources on next build
	rm -rf ~/.cache/common-lisp

.PHONY: clean/userland
clean/userland: ## Remove compiled userland binaries
	rm -f build/*.elf

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

##@ Userland

# Cross-compiler selection per arch (prefer elf toolchains, fall back to linux-gnu)
CC_x86_64  ?= $(or $(shell command -v x86_64-elf-gcc 2>/dev/null), \
                   $(shell command -v x86_64-linux-gnu-gcc 2>/dev/null), \
                   gcc)
CC_i386    ?= $(or $(shell command -v i686-elf-gcc 2>/dev/null), \
                   $(shell command -v i686-linux-gnu-gcc 2>/dev/null), \
                   gcc -m32)
CC_aarch64 ?= $(or $(shell command -v aarch64-elf-gcc 2>/dev/null), \
                   $(shell command -v aarch64-linux-gnu-gcc 2>/dev/null))

USERLAND_CFLAGS := -ffreestanding -nostdlib -static -O2

.PHONY: userland
userland: build/hello-$(TARGET_ARCH).elf ## Compile userland for current TARGET_ARCH

.PHONY: userland/all
userland/all: build/hello-x86_64.elf build/hello-i386.elf build/hello-aarch64.elf \
              ## Compile userland programs for all architectures

build/hello-x86_64.elf: src/userland/hello/hello.c src/userland/hello/hello-x86_64.ld
	mkdir -p build
	@if [ -z "$(CC_x86_64)" ] || ! $(CC_x86_64) --target-help 2>&1 | grep -q x86_64 2>/dev/null; then \
	    if ! $(CC_x86_64) -ffreestanding -nostdlib -static -O2 -T src/userland/hello/hello-x86_64.ld -o $@ $< 2>/dev/null; then \
	        echo "[ecclesia] Skipping x86_64 userland — no suitable cross-compiler"; \
	        echo "[ecclesia] Run 'make setup/toolchain' to install x86_64-linux-gnu-gcc"; \
	        exit 0; \
	    fi; \
	else \
	    $(CC_x86_64) $(USERLAND_CFLAGS) -T src/userland/hello/hello-x86_64.ld -o $@ $<; \
	fi
	@test -f $@ && echo "[ecclesia] Compiled $@ ($$(wc -c < $@) bytes)" || true

build/hello-i386.elf: src/userland/hello/hello.c src/userland/hello/hello-i386.ld
	mkdir -p build
	@if ! $(CC_i386) $(USERLAND_CFLAGS) -T src/userland/hello/hello-i386.ld -o $@ $< 2>/dev/null; then \
	    echo "[ecclesia] Skipping i386 userland — no suitable cross-compiler"; \
	    echo "[ecclesia] Run 'make setup/toolchain' to install i686-linux-gnu-gcc"; \
	fi
	@test -f $@ && echo "[ecclesia] Compiled $@ ($$(wc -c < $@) bytes)" || true

build/hello-aarch64.elf: src/userland/hello/hello.c src/userland/hello/hello-aarch64.ld
	mkdir -p build
	@if [ -z "$(CC_aarch64)" ]; then \
	    echo "[ecclesia] Skipping aarch64 userland — no cross-compiler found"; \
	    echo "[ecclesia] Run 'make setup/toolchain' to install gcc-aarch64-linux-gnu"; \
	elif ! $(CC_aarch64) $(USERLAND_CFLAGS) -T src/userland/hello/hello-aarch64.ld -o $@ $< 2>/dev/null; then \
	    echo "[ecclesia] Skipping aarch64 userland — compilation failed"; \
	fi
	@test -f $@ && echo "[ecclesia] Compiled $@ ($$(wc -c < $@) bytes)" || true

##@ Utilities

.PHONY: help
help: ## Show available targets
	awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\n"} /^[a-zA-Z_0-9/-]+:.*?##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)
