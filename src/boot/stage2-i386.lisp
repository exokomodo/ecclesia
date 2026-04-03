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
  `(;; ── 16-bit real mode ─────────────────────────────────────────────────────
    (bits 16)
    (org  #x8000)
    ,@(real-mode-init-forms)

    ;; ── Enable A20 ───────────────────────────────────────────────────────────
    ,@(a20-enable-forms)

    ;; ── Load GDT ─────────────────────────────────────────────────────────────
    (lgdt (gdt-descriptor))

    ;; ── Enter protected mode ──────────────────────────────────────────────────
    ,@(enter-protected-mode-forms)

    ;; ── GDT ──────────────────────────────────────────────────────────────────
    (label gdt-start)
    (dq #x0000000000000000)  ; null descriptor
    (dq #x00cf9a000000ffff)  ; 0x08: 32-bit code, base=0, limit=4GB
    (dq #x00cf92000000ffff)  ; 0x10: 32-bit data, base=0, limit=4GB
    (label gdt-end)

    (label gdt-descriptor)
    (dw (- gdt-end gdt-start 1))
    (dd gdt-start)

    ;; ── 32-bit protected mode ─────────────────────────────────────────────────
    (bits 32)
    (label pm-entry)
    ,@(setup-pm-segments-forms #x90000)

    ;; ── Clear screen ─────────────────────────────────────────────────────────
    ,@(vga-clear-forms)

    ;; ── Print OS header ──────────────────────────────────────────────────────
    ,@(vga-write "Ecclesia OS" :row 0 :col 0 :attr #x0e)

    ;; ── Boot status lines ────────────────────────────────────────────────────
    ,@(vga-status "A20 line enabled" :row 1 :ok t)
    ,@(vga-status "GDT loaded" :row 2 :ok t)
    ,@(vga-status "Entered 32-bit protected mode" :row 3 :ok t)
    ,@(vga-status "Segment registers configured" :row 4 :ok t)

    ;; ── Jump to i386 kernel ──────────────────────────────────────────────────
    ,@(vga-status "Jumping to kernel" :row 5 :ok t)
    (jmp abs #x20000)))

(defparameter *stage2-i386* (*stage2-i386*))
