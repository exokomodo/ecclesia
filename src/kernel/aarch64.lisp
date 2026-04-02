;;;; aarch64.lisp — AArch64 kernel ISA implementation
;;;;
;;;; Target: QEMU virt machine, loaded at 0x40000000 via -kernel.
;;;; Output: PL011 UART at 0x09000000.
;;;; Input:  PL011 UART receive (polling).

(in-package #:ecclesia.kernel.aarch64)

(defclass aarch64 ()
  ((board :initarg :board :reader aarch64-board))
  (:documentation "AArch64 ISA instance — carries a board for hardware specifics."))

(defparameter *default-aarch64-board* :qemu-virt
  "Default board keyword used when no TARGET_BOARD env var is set.")

(defmethod ecclesia.kernel:make-kernel-isa ((target (eql :aarch64)))
  (let* ((board-key (intern (string-upcase
                              (or (sb-ext:posix-getenv "TARGET_BOARD")
                                  (symbol-name *default-aarch64-board*)))
                            :keyword))
         (board (make-board board-key)))
    (make-instance 'aarch64 :board board)))

;;; ── ISA metadata — delegate to board where appropriate ──────────────────────

(defmethod ecclesia.kernel:isa-bits          ((isa aarch64)) 64)
(defmethod ecclesia.kernel:isa-origin        ((isa aarch64))
  (board-kernel-load-address (aarch64-board isa)))
(defmethod ecclesia.kernel:isa-stack-pointer ((isa aarch64))
  (board-stack-top (aarch64-board isa)))

;;; ── Assembler prelude ────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:asm-prelude-forms ((isa aarch64))
  `((bits 64)
    (org  ,(ecclesia.kernel:isa-origin isa))))

;;; ── Entry prologue ───────────────────────────────────────────────────────────
;;; x19 = UART base (callee-saved, available throughout)

(defmethod ecclesia.kernel:isa-entry-prologue-forms ((isa aarch64))
  `(;; Load UART base into x19 (preserved across calls)
    (movx x19 ,(board-uart-base (aarch64-board isa)))
    ;; Set up stack pointer
    (movx x9 ,(ecclesia.kernel:isa-stack-pointer isa))
    (movsp x9)
    ;; ── OS banner (equivalent to Stage 2 status lines on x86) ──────────────
    ,@(uart-puts-forms "Ecclesia OS")
    ,@(uart-putc-forms 13)   ; CR
    ,@(uart-putc-forms 10)   ; LF
    ,@(uart-puts-forms "[ OK ] kernel loaded")
    ,@(uart-putc-forms 13)
    ,@(uart-putc-forms 10)))

;;; ── UART write helpers ───────────────────────────────────────────────────────
;;;
;;; uart-putc-forms: emit a single ASCII char (integer literal) to UART.
;;; uart-puts-forms: emit a string literal, one char at a time.

(defun uart-putc-forms (char-code)
  "Emit forms to write a single ASCII byte to UART (x19 = UART base)."
  `((movx x1 ,char-code)
    (strb w1 (mem x19))))

(defun uart-puts-forms (str)
  "Emit forms to write each character of STR to UART."
  (loop for c across str
        appending (uart-putc-forms (char-code c))))

;;; ── Prompt print ─────────────────────────────────────────────────────────────
;;; Called from make-kernel-main via vga-rdi-write dispatch.
;;; For AArch64 we override the whole prompt section.

(defmethod ecclesia.kernel:isa-entry-prologue-forms :after ((isa aarch64))
  ;; nothing extra — prompt printed by vga-write-char-forms override
  nil)

;;; ── Generics: UART replaces VGA ──────────────────────────────────────────────

;;; ps2-poll-forms → UART receive polling
;;; PL011 UARTFR (Flag Register) at base+0x18, bit 4 = RXFE (receive FIFO empty)
;;; PL011 UARTDR (Data Register) at base+0x00

(defmethod ecclesia.kernel:ps2-poll-forms ((isa aarch64))
  `((label kbd-poll)
    ;; Read UARTFR into w1
    (movx x2 #x18)           ; offset of UARTFR
    (add-imm x2 x19 #x18)    ; x2 = UART base + 0x18
    (ldrb w1 (mem x2))       ; w1 = UARTFR
    ;; Test RXFE (bit 4) — if set, no data yet
    (movx x3 16)              ; bit 4 = 0x10
    (tst-imm w1 #x10)
    (bne kbd-poll)
    ;; Read UARTDR (byte at base+0x00) into w0 (= al equivalent)
    (ldrb w0 (mem x19))))    ; w0 = received byte

;;; scancode-filter-forms → no scancode concept for UART, pass through
(defmethod ecclesia.kernel:scancode-filter-forms ((isa aarch64))
  '()) ; UART gives ASCII directly — no filtering needed

;;; scancode-translate-forms → identity (UART already gives ASCII in w0)
(defmethod ecclesia.kernel:scancode-translate-forms ((isa aarch64))
  '())

;;; dispatch-to-handler-forms → check for backspace (0x7f or 0x08)
(defmethod ecclesia.kernel:dispatch-to-handler-forms ((isa aarch64))
  `((movx x1 #x7f)
    (cmp-imm w0 #x7f)
    (beq kbd-backspace)
    (movx x1 #x08)
    (cmp-imm w0 #x08)
    (beq kbd-backspace)
    (b kbd-printable)))

;;; vga-write-char-forms → write w0 to UART, increment column counter
;;; x18 = address of uart-col byte (loaded once at start of printable handler)
(defmethod ecclesia.kernel:vga-write-char-forms ((isa aarch64))
  `(;; Write character to UART
    (strb w0 (mem x19))
    ;; Increment column counter at uart-col
    (movx x18 uart-col)
    (ldrb w1 (mem x18))
    (add-imm x1 x1 1)
    (strb w1 (mem x18))))

;;; vga-erase-char-forms → BS SP BS, only if column > 0
(defmethod ecclesia.kernel:vga-erase-char-forms ((isa aarch64))
  `(;; Check column counter — don't backspace past column 0
    (movx x18 uart-col)
    (ldrb w1 (mem x18))
    (cmp-imm w1 0)
    (beq uart-bs-done)
    ;; Decrement column
    (sub-imm x1 x1 1)
    (strb w1 (mem x18))
    ;; Emit BS SP BS
    ,@(uart-putc-forms 8)
    ,@(uart-putc-forms 32)
    ,@(uart-putc-forms 8)
    (label uart-bs-done)))

;;; vga-offset-forms → reset column on newline detection (not needed for basic echo)
(defmethod ecclesia.kernel:vga-offset-forms ((isa aarch64))
  '())

;;; cursor-advance-forms → reset column counter on newline
(defmethod ecclesia.kernel:cursor-advance-forms ((isa aarch64))
  '())

;;; screen-full-check-forms → UART has no screen limit
(defmethod ecclesia.kernel:screen-full-check-forms ((isa aarch64))
  '())

;;; backspace-forms → delegate to vga-erase-char-forms
(defmethod ecclesia.kernel:backspace-forms ((isa aarch64))
  (ecclesia.kernel:vga-erase-char-forms isa))

;;; save/restore/discard: w0 is never clobbered (no screen-full or VGA offset
;;; logic for UART), so these are all noops.
(defmethod ecclesia.kernel:save-char-forms    ((isa aarch64)) '())
(defmethod ecclesia.kernel:restore-char-forms ((isa aarch64)) '())
(defmethod ecclesia.kernel:discard-char-forms ((isa aarch64)) '())

;;; print-prompt-forms → write prompt string to UART, then reset column counter
(defmethod ecclesia.kernel:print-prompt-forms ((isa aarch64) str row)
  (declare (ignore row))
  (append (uart-puts-forms str)
          ;; Reset column counter to length of prompt string
          `((movx x18 uart-col)
            (movx x1 ,(length str))
            (strb w1 (mem x18)))))

;;; unconditional-jump-forms → AArch64 B label
(defmethod ecclesia.kernel:unconditional-jump-forms ((isa aarch64) label)
  `((b ,label)))

;;; embedded-data-forms → uart-col padded to 4-byte alignment
;;; AArch64 requires all instructions to be 4-byte aligned.
;;; The (db 0) is 1 byte; pad to 4 bytes so kbd-main-loop is aligned.
(defmethod ecclesia.kernel:embedded-data-forms ((isa aarch64) scancode-table-forms)
  (declare (ignore scancode-table-forms))
  `((label uart-col) (db 0) (db 0) (db 0) (db 0)))
