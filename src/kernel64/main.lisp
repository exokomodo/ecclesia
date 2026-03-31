;;;; main.lisp — 64-bit kernel entry point
;;;;
;;;; Wires together the ISA-agnostic kernel pipeline generics
;;;; (defined in ecclesia.kernel) with the x86-64 implementations
;;;; (defined in ecclesia.kernel.x86-64) to produce a flat assembler
;;;; form list for the 64-bit kernel image.

(in-package #:ecclesia)

;;; Configuration params are defined in ecclesia.kernel (pipeline.lisp)
;;; and imported via the package :use clause.

;;; ── Scancode table ──────────────────────────────────────────────────────────

;;; US QWERTY scancode set 1 → ASCII, unshifted (89 entries: 0x00–0x58)
(defparameter *scancode-ascii*
  #(  0  27  49  50  51  52  53  54  55  56  57  48  45  61   8   9
    113 119 101 114 116 121 117 105 111 112  91  93  13   0  97 115
    100 102 103 104 106 107 108  59  39  96   0  92 122 120  99 118
     98 110 109  44  46  47   0   0   0  32   0   0   0   0   0   0
      0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0
      0   0   0   0   0   0   0   0   0))

(defun scancode-db-forms ()
  "Emit one (db N) per entry in *scancode-ascii*."
  (loop for c across *scancode-ascii* collect `(db ,c)))

;;; ── Kernel image ─────────────────────────────────────────────────────────────

(let ((isa (make-instance 'ecclesia.kernel.x86-64:x86-64)))
  (defparameter *kernel64*
    `(;; ── Entry point ────────────────────────────────────────────────────────
      (bits 64)
      (org  #x100000)

      (mov  rsp #x200000)
      (mov  rdi ,+vga-base+)

      ;; Print the prompt
      ,@(vga-rdi-write *prompt-str* :row *prompt-row* :col 0 :attr #x0a)

      ;; Jump over embedded data tables
      (jmp abs kbd-main-loop)

      ;; ── Embedded data ──────────────────────────────────────────────────────
      (label kbd-ascii-table)
      ,@(scancode-db-forms)

      (label kbd-cursor-col) (db ,(length *prompt-str*))
      (label kbd-cursor-row) (db ,*prompt-row*)

      ;; ── Main loop ──────────────────────────────────────────────────────────
      (label kbd-main-loop)

      ;; 1. Wait for and read a scancode from PS/2
      ,@(ps2-poll-forms isa)

      ;; 2. Filter key releases and out-of-range scancodes
      ,@(scancode-filter-forms isa)

      ;; 3. Translate scancode → ASCII
      ,@(scancode-translate-forms isa)

      ;; 4. Route: backspace vs. printable character
      (cmp8  al #x08)
      (jz    kbd-backspace)
      (jmp   abs kbd-printable)

      ;; ── Backspace ──────────────────────────────────────────────────────────
      (label kbd-backspace)
      ,@(backspace-forms isa)
      (jmp   abs kbd-main-loop)

      ;; ── Printable character ────────────────────────────────────────────────
      (label kbd-printable)

      ;; 5. Save char; reject if screen is full
      (push-reg rax)
      ,@(screen-full-check-forms isa)

      ;; 6. Compute VGA offset and write the character
      ,@(vga-offset-forms isa)
      (pop-reg rax)
      ,@(vga-write-char-forms isa)

      ;; 7. Advance cursor
      ,@(cursor-advance-forms isa)
      (jmp   abs kbd-main-loop)

      ;; ── Screen full: discard char ──────────────────────────────────────────
      (label kbd-full)
      (pop-reg rax)
      (jmp   abs kbd-main-loop))))
