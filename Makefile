SHELL := /bin/bash
.SHELLFLAGS = -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:
MAKEFLAGS += --no-print-directory

UNAME_S := $(shell uname -s)

# Variables
QEMU := qemu-system-x86_64
BUILD_DIR := build
SRC_DIR := src
KERNEL_BIN := $(BUILD_DIR)/kernel.bin

##@ Environment Setup

.PHONY: setup
setup: setup/sbcl ## Install all development dependencies

.PHONY: setup/sbcl
setup/sbcl: ## Install SBCL, NASM, QEMU and Common Lisp dependencies
ifeq ($(UNAME_S),Linux)
	sudo apt update && sudo apt install -y sbcl nasm qemu-system-x86
else ifeq ($(UNAME_S),Darwin)
	brew install sbcl nasm qemu
else
	$(error "Unsupported OS: $(UNAME_S). Please install SBCL, NASM, and QEMU manually.")
endif

##@ Development Tasks

.PHONY: boot
boot: build ## Build and launch in QEMU
	@echo "[+] Launching in QEMU..."
	$(QEMU) -kernel $(KERNEL_BIN) -serial stdio -display none

.PHONY: build
build: ## Build the kernel image (SBCL runtime + boot stub)
	@echo "[+] Assembling boot stub..."
	mkdir -p $(BUILD_DIR)
	nasm -f elf64 $(SRC_DIR)/boot.asm -o $(BUILD_DIR)/boot.o
	@echo "[+] Building SBCL bare-metal image..."
	sbcl --noinform \
	     --no-userinit \
	     --no-sysinit \
	     --load $(SRC_DIR)/boot.lisp \
	     --save-lisp-and-die $(KERNEL_BIN) \
	     --executable

##@ Utilities

.PHONY: help
help: ## Show available targets
	awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
