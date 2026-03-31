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
;;; Defined here so all ISA implementations can reference them without
;;; depending on the ecclesia package (which loads after them).

(defparameter *prompt-str*       "ecclesia> ")
(defparameter *prompt-row*       23)
(defparameter *vga-screen-rows*  25)
(defparameter *vga-char-attr*    #x0f)   ; white on black

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
