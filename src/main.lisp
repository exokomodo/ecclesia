;;;; main.lisp — kernel entry point (ISA-agnostic)
;;;;
;;;; This file contains NO ISA-specific instructions, directives, or encodings.
;;;; Every construct delegates to an ecclesia.kernel generic dispatched on
;;;; the ISA instance produced by (resolve-build-target).
;;;;
;;;; To build for a different ISA:
;;;;   (setf ecclesia.kernel:*build-target* :arm64)
;;;;   (make-kernel-main)

(in-package #:ecclesia)

;;; ── Scancode table data ──────────────────────────────────────────────────────
;;;
;;; The keyboard layout is an application-level concern, not an ISA concern.
;;; The embedded-data-forms generic decides how it is laid out in memory.

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
   Every line is a generic call — no ISA assumptions in this function."
  `(;; ── Assembler prelude (bit width, origin) ─────────────────────────────────
    ,@(asm-prelude-forms isa)

    ;; ── ISA-specific runtime setup ────────────────────────────────────────────
    ,@(isa-entry-prologue-forms isa)

    ;; ── Print the prompt ──────────────────────────────────────────────────────
    ,@(print-prompt-forms isa *prompt-str* *prompt-row*)

    ;; ── Jump over embedded data ───────────────────────────────────────────────
    ,@(unconditional-jump-forms isa 'kbd-main-loop)

    ;; ── Embedded data (layout determined by ISA) ──────────────────────────────
    ,@(embedded-data-forms isa (scancode-db-forms))

    ;; ── Main loop ────────────────────────────────────────────────────────────
    (label kbd-main-loop)

    ;; 1. Wait for and read a scancode
    ,@(ps2-poll-forms isa)

    ;; 2. Filter releases and out-of-range codes
    ,@(scancode-filter-forms isa)

    ;; 3. Translate scancode → ASCII
    ,@(scancode-translate-forms isa)

    ;; 4. Dispatch to backspace or printable handler
    ,@(dispatch-to-handler-forms isa)

    ;; ── Backspace handler ─────────────────────────────────────────────────────
    (label kbd-backspace)
    ,@(backspace-forms isa)
    ,@(unconditional-jump-forms isa 'kbd-main-loop)

    ;; ── Printable character handler ───────────────────────────────────────────
    (label kbd-printable)

    ;; 5. Save char across the screen-full check
    ,@(save-char-forms isa)

    ;; 6. Reject if screen is full
    ,@(screen-full-check-forms isa)

    ;; 7. Compute VGA offset and write the character
    ,@(vga-offset-forms isa)
    ,@(restore-char-forms isa)
    ,@(vga-write-char-forms isa)

    ;; 8. Advance cursor
    ,@(cursor-advance-forms isa)
    ,@(unconditional-jump-forms isa 'kbd-main-loop)

    ;; ── Screen full: discard saved char and loop ───────────────────────────────
    (label kbd-full)
    ,@(discard-char-forms isa)
    ,@(unconditional-jump-forms isa 'kbd-main-loop)

    ;; ── Escape: invoke ELF loader (x86_64 only) ────────────────────────────
    (label kbd-escape)
    ,@(let ((loader (make-elf-loader isa)))
        (if loader
            loader
            (unconditional-jump-forms isa 'kbd-main-loop)))))

;;; ── ELF loader stub ──────────────────────────────────────────────────────────

(defun make-elf-loader (&optional (isa (resolve-build-target))
                                  (elf-load-addr #x300000))
  "Return assembly forms for the static ELF loader for ISA.
   ELF-LOAD-ADDR is the physical address where the ELF binary is pre-loaded.
   Returns NIL if the ISA doesn't support the ELF loader yet."
  (when (ecclesia.kernel:isa-supports-elf-loader-p isa)
    (ecclesia.loader:load-elf-forms isa elf-load-addr)))

;;; Eagerly build the kernel image for the default build target.
(defparameter *kernel-main* (make-kernel-main))
