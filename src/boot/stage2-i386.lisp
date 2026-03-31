;;;; stage2-i386.lisp — Stage 2 for i386: real mode → 32-bit protected mode
;;;;
;;;; Steps:
;;;;   1. Enable A20 line
;;;;   2. Load a flat 32-bit GDT
;;;;   3. Set CR0.PE, far jump to 32-bit code segment
;;;;   4. Set up 32-bit segment registers
;;;;   5. Print [  OK  ] status via VGA
;;;;   6. Jump to kernel at 0x10000

(in-package #:ecclesia.boot)

(defun *stage2-i386* ()
  `(;; ── 16-bit real mode entry ───────────────────────────────────────────────
    (bits 16)
    (org  #x8000)
    (cli)
    (xor  ax ax)
    (mov  ds ax)
    (mov  es ax)
    (mov  ss ax)
    (mov  sp #x7c00)

    ;; ── Enable A20 via keyboard controller ──────────────────────────────────
    (in   al #x92)
    (or   al #x02)
    (out  #x92 al)

    ;; ── Load GDT ────────────────────────────────────────────────────────────
    (lgdt (gdt-descriptor))

    ;; ── Enter protected mode ─────────────────────────────────────────────────
    (mov  eax cr0)
    (or   eax #x01)
    (mov  cr0 eax)

    ;; Far jump to flush prefetch queue and enter 32-bit segment
    (jmp  far #x08 pm-entry)

    ;; ── GDT ─────────────────────────────────────────────────────────────────
    (label gdt-start)
    (dq #x0000000000000000)  ; null descriptor
    (dq #x00cf9a000000ffff)  ; 0x08: 32-bit code, base=0, limit=4GB
    (dq #x00cf92000000ffff)  ; 0x10: 32-bit data, base=0, limit=4GB
    (label gdt-end)

    (label gdt-descriptor)
    (dw (- gdt-end gdt-start 1))  ; limit
    (dd gdt-start)                ; base

    ;; ── 32-bit protected mode ─────────────────────────────────────────────────
    (bits 32)
    (label pm-entry)
    (mov  ax #x10)
    (mov  ds ax)
    (mov  es ax)
    (mov  fs ax)
    (mov  gs ax)
    (mov  ss ax)
    (mov  esp #x90000)

    ;; ── Print [  OK  ] Protected Mode ───────────────────────────────────────
    ,@(vga-status "Protected mode" :row 0 :ok t)

    ;; ── Jump to i386 kernel ──────────────────────────────────────────────────
    ,@(vga-status "Jumping to kernel" :row 1 :ok t)
    (jmp abs #x20000)))

(defparameter *stage2-i386* (*stage2-i386*))
