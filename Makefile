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
setup/sbcl: ## Install SBCL and Common Lisp dependencies
ifeq ($(UNAME_S),Linux)
	sudo apt update && sudo apt install -y sbcl cl-ppcre
else ifeq ($(UNAME_S),Darwin)
	brew install sbcl
	echo "On macOS, install cl-ppcre via Quicklisp: (ql:quickload :cl-ppcre)"
else
	$(error "Unsupported OS: $(UNAME_S). Please install SBCL manually.")
endif

##@ Development Tasks

.PHONY: boot
boot: build
	@echo "[+] Launching in QEMU..."
	$(QEMU) -kernel $(KERNEL_BIN)

.PHONY: build
build:
	@echo "[+] Building kernel..."
	mkdir -p $(BUILD_DIR)
	gcc -ffreestanding -nostdlib -o $(KERNEL_BIN) $(SRC_DIR)/kernel.c

##@ Utilities

.PHONY: help
help: ## Show available targets
	awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n\n"} /^[a-zA-Z_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
