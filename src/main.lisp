;;;; main.lisp — kernel entry point (ISA-agnostic)
;;;;
;;;; Constructs the kernel image by calling the pipeline generics on the
;;;; ISA instance selected by ecclesia.kernel:*build-target*.
;;;;
;;;; To build for a different ISA:
;;;;   (setf ecclesia.kernel:*build-target* :arm64)  ; (once arm64 is implemented)
;;;;   (setf ecclesia:*kernel-main* (ecclesia:make-kernel-main))

(in-package #:ecclesia)

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

;;; ── Kernel image builder ─────────────────────────────────────────────────────

(defun make-kernel-main (&optional (isa (resolve-build-target)))
  "Return the kernel assembler form list for ISA (default: *build-target*).
   The same structural description is used for every target; only the
   ISA-specific generic implementations change."
  `(;; ── Entry point ──────────────────────────────────────────────────────────
    (bits ,(isa-bits isa))
    (org  ,(isa-origin isa))

    ;; ISA-specific prologue (stack pointer, baseline registers, etc.)
    ,@(isa-entry-prologue-forms isa)

    ;; Print the prompt
    ,@(vga-rdi-write *prompt-str* :row *prompt-row* :col 0 :attr #x0a)

    ;; Jump over embedded data tables
    (jmp abs kbd-main-loop)

    ;; ── Embedded data ────────────────────────────────────────────────────────
    (label kbd-ascii-table)
    ,@(scancode-db-forms)

    (label kbd-cursor-col) (db ,(length *prompt-str*))
    (label kbd-cursor-row) (db ,*prompt-row*)

    ;; ── Main loop ────────────────────────────────────────────────────────────
    (label kbd-main-loop)

    ;; 1. Wait for and read a scancode
    ,@(ps2-poll-forms isa)

    ;; 2. Filter key releases and out-of-range scancodes
    ,@(scancode-filter-forms isa)

    ;; 3. Translate scancode → ASCII
    ,@(scancode-translate-forms isa)

    ;; 4. Route: backspace vs. printable character
    (cmp8  al #x08)
    (jz    kbd-backspace)
    (jmp   abs kbd-printable)

    ;; ── Backspace ────────────────────────────────────────────────────────────
    (label kbd-backspace)
    ,@(backspace-forms isa)
    (jmp   abs kbd-main-loop)

    ;; ── Printable character ──────────────────────────────────────────────────
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

    ;; ── Screen full: discard char ─────────────────────────────────────────────
    (label kbd-full)
    (pop-reg rax)
    (jmp   abs kbd-main-loop)))

;;; Eagerly build the kernel image for the default build target.
(defparameter *kernel-main* (make-kernel-main))
