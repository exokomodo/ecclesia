;;;; stage2.lisp — Stage 2 bootloader
;;;;
;;;; Loaded at 0x8000 by Stage 1. Transitions the CPU:
;;;;   16-bit real mode → 32-bit protected mode → 64-bit long mode
;;;;
;;;; Then calls into the Lisp kernel entry point.
;;;;
;;;; References:
;;;;   AMD64 Architecture Programmer's Manual Vol.2, Section 14.8
;;;;   OSDev wiki: https://wiki.osdev.org/Setting_Up_Long_Mode

(in-package #:ecclesia)

;;; GDT entries (Global Descriptor Table)
;;; We need three entries:
;;;   0: null descriptor
;;;   1: 64-bit code segment (ring 0)
;;;   2: 64-bit data segment (ring 0)

(defparameter *stage2*
  '(;; ===== Stage 2: 16-bit real mode entry =====
    (bits 16)
    (org  #x8000)

    ;; Disable interrupts while we reconfigure
    (cli)

    ;; Load GDT
    (lgdt (gdt-descriptor))

    ;; Enable protected mode: set CR0.PE bit
    (mov  eax cr0)
    (or   eax #x01)
    (mov  cr0 eax)

    ;; Far jump to flush the prefetch queue and enter 32-bit protected mode
    ;; Selector 0x08 = GDT entry 1 (code segment)
    (jmp  far #x0008 pm-entry)

    ;; ===== GDT =====
    (label gdt-start)

    ;; Entry 0: null descriptor (required)
    (dq #x0000000000000000)

    ;; Entry 1: 64-bit code segment
    ;; Base=0, Limit=0xFFFFF, G=1, L=1 (64-bit), P=1, DPL=0, S=1, Type=0xA (exec/read)
    (dq #x00af9a000000ffff)

    ;; Entry 2: 64-bit data segment
    ;; Base=0, Limit=0xFFFFF, G=1, D/B=1, P=1, DPL=0, S=1, Type=0x2 (r/w)
    (dq #x00cf92000000ffff)

    (label gdt-end)

    ;; GDT descriptor (limit + base address)
    (label gdt-descriptor)
    (dw (- gdt-end gdt-start 1))   ; limit = size - 1
    (dd gdt-start)                 ; base address (32-bit)

    ;; ===== 32-bit protected mode =====
    (bits 32)
    (label pm-entry)

    ;; Set up data segments
    (mov  ax #x0010)        ; data segment selector
    (mov  ds ax)
    (mov  es ax)
    (mov  fs ax)
    (mov  gs ax)
    (mov  ss ax)
    (mov  esp #x90000)      ; set up stack

    ;; Enable PAE (Physical Address Extension) for long mode
    (mov  eax cr4)
    (or   eax #x20)
    (mov  cr4 eax)

    ;; Load PML4 (page table) address into CR3
    ;; We place our minimal identity-mapped page table at 0x1000
    (mov  eax #x1000)
    (mov  cr3 eax)

    ;; Set EFER.LME to enable long mode
    (mov  ecx #xc0000080)   ; EFER MSR
    (rdmsr)
    (or   eax #x100)        ; set LME bit
    (wrmsr)

    ;; Enable paging to activate long mode (CR0.PG | CR0.PE)
    (mov  eax cr0)
    (or   eax #x80000001)
    (mov  cr0 eax)

    ;; Far jump into 64-bit long mode
    ;; Selector 0x08 = 64-bit code segment
    (jmp  far #x0008 lm-entry)

    ;; ===== 64-bit long mode =====
    (bits 64)
    (label lm-entry)

    ;; Set up 64-bit data segments
    (mov  ax #x0010)
    (mov  ds ax)
    (mov  es ax)
    (mov  ss ax)

    ;; Jump to the Lisp kernel entry point
    ;; (will be linked/loaded at a fixed address by the kernel builder)
    (jmp  abs #x100000)))

(defun stage2-size ()
  (length (assemble *stage2*)))
