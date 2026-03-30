; boot.asm — Ecclesia x86-64 bootstrap stub
;
; Multiboot2-compliant header. GRUB loads this, sets up a minimal
; environment, then hands off to the SBCL bare-metal runtime which
; in turn loads boot.lisp.
;
; Assemble with: nasm -f elf64 boot.asm -o boot.o

BITS 32

MULTIBOOT2_MAGIC    equ 0xe85250d6
MULTIBOOT2_ARCH     equ 0           ; i386/x86-64 protected mode
MULTIBOOT2_HEADER_LEN equ (multiboot2_header_end - multiboot2_header_start)
MULTIBOOT2_CHECKSUM equ -(MULTIBOOT2_MAGIC + MULTIBOOT2_ARCH + MULTIBOOT2_HEADER_LEN)

section .multiboot2
align 8
multiboot2_header_start:
    dd MULTIBOOT2_MAGIC
    dd MULTIBOOT2_ARCH
    dd MULTIBOOT2_HEADER_LEN
    dd MULTIBOOT2_CHECKSUM

    ; End tag
    dw 0    ; type
    dw 0    ; flags
    dd 8    ; size
multiboot2_header_end:

section .bss
align 16
stack_bottom:
    resb 65536          ; 64 KiB initial stack
stack_top:

section .text
global _start
extern sbcl_main        ; provided by SBCL bare-metal runtime

_start:
    ; Set up the stack
    mov esp, stack_top

    ; Clear the direction flag
    cld

    ; Push Multiboot2 info pointer and magic for SBCL runtime
    push ebx            ; multiboot info pointer
    push eax            ; multiboot magic

    ; Transfer control to SBCL
    call sbcl_main

    ; Should never return — halt if it does
.hang:
    cli
    hlt
    jmp .hang
