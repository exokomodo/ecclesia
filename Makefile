# Makefile for Ecclesia Project

# Variables
QEMU=qemu-system-x86_64
BUILD_DIR=build
SRC_DIR=src
KERNEL_BIN=$(BUILD_DIR)/kernel.bin

all: boot

boot: kernel
	@echo "[+] Launching in QEMU..."
	$(QEMU) -kernel $(KERNEL_BIN)

kernel:
	@echo "[+] Building kernel..."
	mkdir -p $(BUILD_DIR)
	gcc -ffreestanding -nostdlib -o $(KERNEL_BIN) $(SRC_DIR)/kernel.c

clean:
	@echo "[+] Cleaning build artifacts..."
	rm -rf $(BUILD_DIR)

.PHONY: all boot kernel clean