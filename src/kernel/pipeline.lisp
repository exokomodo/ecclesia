;;;; pipeline.lisp — ISA-agnostic kernel pipeline generics
;;;;
;;;; Each generic takes an ISA designator (a keyword or struct) as its first
;;;; argument and returns a list of assembler forms that implement that step.
;;;;
;;;; To port Ecclesia to a new ISA:
;;;;   1. Define a class or struct for the new ISA (e.g. DEFCLASS ARM64 ())
;;;;   2. Implement each method below for that class
;;;;   3. Call the generics in your *kernel<ISA>* parameter
;;;;
;;;; No methods are defined here — see kernel/x86-64.lisp for the x86-64
;;;; implementations.

(in-package #:ecclesia.kernel)

;;; ── Kernel configuration ────────────────────────────────────────────────────

(defparameter *prompt-str*       "ecclesia> ")
(defparameter *prompt-row*       23)
(defparameter *vga-screen-rows*  25)
(defparameter *vga-char-attr*    #x0f)   ; white on black

;;; ── ISA descriptor protocol ─────────────────────────────────────────────────
;;;
;;; An ISA class carries build-target metadata alongside the pipeline methods.
;;; This lets make-kernel-forms select the right implementation and emit
;;; correct entry-point prologue (origin address, stack, etc.) without
;;; the caller having to know ISA details.

(defgeneric isa-origin (isa)
  (:documentation "Physical load address of the kernel image."))

(defgeneric isa-stack-pointer (isa)
  (:documentation "Initial stack pointer value."))

(defgeneric isa-bits (isa)
  (:documentation "Assembler bit width directive value (16, 32, or 64)."))

(defgeneric isa-entry-prologue-forms (isa)
  (:documentation
   "Return forms that set up the minimal runtime environment before the kernel
    main loop — stack pointer, any baseline register state, etc."))

;;; ── Pipeline generics ───────────────────────────────────────────────────────

(defgeneric ps2-poll-forms (isa)
  (:documentation
   "Return forms that spin until PS/2 has a byte ready, then read it into
    a scratch register.  On x86-64 this polls port 0x64 and reads port 0x60."))

(defgeneric scancode-filter-forms (isa)
  (:documentation
   "Return forms that discard key-release events and scancodes outside the
    supported translation table.  Filtered events branch to KBD-MAIN-LOOP."))

(defgeneric scancode-translate-forms (isa)
  (:documentation
   "Return forms that translate the raw scancode (from PS2-POLL-FORMS) to an
    ASCII code using the embedded lookup table.  Unmapped scancodes (value 0)
    branch to KBD-MAIN-LOOP."))

(defgeneric vga-offset-forms (isa)
  (:documentation
   "Return forms that compute the VGA text buffer byte offset for the current
    cursor position (row, col).  Result left in a scratch register (EDX on
    x86-64).  Clobbers ISA-specific scratch registers."))

(defgeneric vga-write-char-forms (isa)
  (:documentation
   "Return forms that write the current character and its video attribute to
    the VGA buffer at the offset produced by VGA-OFFSET-FORMS."))

(defgeneric vga-erase-char-forms (isa)
  (:documentation
   "Return forms that write a space and the video attribute to the VGA buffer
    at the offset produced by VGA-OFFSET-FORMS (used by backspace)."))

(defgeneric cursor-advance-forms (isa)
  (:documentation
   "Return forms that increment the cursor column.  When the column reaches
    the screen width, wrap to column 0 and increment the row."))

(defgeneric screen-full-check-forms (isa)
  (:documentation
   "Return forms that branch to KBD-FULL when the cursor row is >= the number
    of screen rows (i.e. the display is full and no more input should print)."))

(defgeneric backspace-forms (isa)
  (:documentation
   "Return forms that handle a backspace keypress:
    - If cursor is off-screen, snap back to the last visible cell.
    - If cursor is at or before the prompt edge, ignore the keypress.
    - Otherwise decrement the column and erase the vacated cell."))

;;; ── Build-target selection ──────────────────────────────────────────────────

(defparameter *build-target* :x86-64
  "Keyword identifying the target ISA for the current build.
   Supported values: :x86-64
   Set this before calling resolve-build-target to select the implementation.")

(defgeneric make-kernel-isa (target)
  (:documentation
   "Return a fresh ISA instance for TARGET (a keyword such as :x86-64).
    Each ISA package provides an EQL-specialised method for its own keyword."))

(defun resolve-build-target ()
  "Return an ISA instance for the current *build-target*."
  (make-kernel-isa *build-target*))

;;; ── Higher-level structural generics ────────────────────────────────────────
;;;
;;; These cover the parts of make-kernel-main that still depend on ISA:
;;; dispatch between handlers, saving/restoring registers, and embedded data.

(defgeneric embedded-data-forms (isa scancode-table-forms)
  (:documentation
   "Return forms for any data embedded within the kernel image — the scancode
    table and cursor position bytes.  The exact layout may differ by ISA."))

(defgeneric dispatch-to-handler-forms (isa)
  (:documentation
   "Return forms that inspect the translated ASCII value and branch to either
    KBD-BACKSPACE or KBD-PRINTABLE.  The comparison and branch instructions
    are ISA-specific."))

(defgeneric save-char-forms (isa)
  (:documentation
   "Return forms that save the current character value before operations that
    would clobber it (e.g. the screen-full check)."))

(defgeneric restore-char-forms (isa)
  (:documentation
   "Return forms that restore the character value saved by save-char-forms."))

(defgeneric discard-char-forms (isa)
  (:documentation
   "Return forms that discard a previously saved character (used on the
    screen-full and other bail-out paths)."))
