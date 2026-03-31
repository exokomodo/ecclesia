;;;; x86_base.lisp — Shared kernel generics for all x86 variants (i386, x86_64)
;;;;
;;;; These methods produce identical bytes regardless of 32-bit or 64-bit mode
;;;; because they only use AL, byte-width instructions, or mode-neutral forms.
;;;; ISA-specific subclasses inherit these automatically.

(in-package #:ecclesia.kernel.x86-base)

(defclass x86-base () ())

;;; ── PS/2 polling ─────────────────────────────────────────────────────────────
;;; Port I/O is identical on all x86 variants — AL, port 0x64, port 0x60.

(defmethod ecclesia.kernel:ps2-poll-forms ((isa x86-base))
  '((label kbd-poll)
    (in   al #x64)          ; read PS/2 status register
    (test al #x01)          ; output-buffer-full?
    (jz   kbd-poll)         ; not ready — spin
    (in   al #x60)))        ; read scancode → AL

;;; ── Scancode filtering ───────────────────────────────────────────────────────
;;; AL comparisons and flag-based branches are mode-neutral.

(defmethod ecclesia.kernel:scancode-filter-forms ((isa x86-base))
  '((test al #x80)          ; bit 7 = key release
    (jnz  kbd-main-loop)
    (cmp8 al #x59)          ; beyond translation table?
    (jnc  kbd-main-loop)))

;;; ── Dispatch to handler ──────────────────────────────────────────────────────
;;; Compares AL to ASCII 8; branches are mode-neutral.

(defmethod ecclesia.kernel:dispatch-to-handler-forms ((isa x86-base))
  '((cmp8 al #x08)
    (jz   kbd-backspace)
    (jmp  abs kbd-printable)))

;;; ── Unconditional jump ───────────────────────────────────────────────────────
;;; jmp abs emits rel32 in both 32-bit and 64-bit mode.

(defmethod ecclesia.kernel:unconditional-jump-forms ((isa x86-base) label)
  `((jmp abs ,label)))

;;; ── Embedded data layout ─────────────────────────────────────────────────────
;;; db directives are mode-neutral.

(defmethod ecclesia.kernel:embedded-data-forms ((isa x86-base) scancode-table-forms)
  `((label kbd-ascii-table)
    ,@scancode-table-forms
    (label kbd-cursor-col) (db ,(length ecclesia.kernel:*prompt-str*))
    (label kbd-cursor-row) (db ,ecclesia.kernel:*prompt-row*)))
