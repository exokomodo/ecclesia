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

;;; vga-write-char-forms → write w0 to UART, track column and row
;;;
;;; After writing, increment uart-col.
;;; If uart-col reaches 80, save it to uart-prev-col, reset to 0, increment uart-row.
(defmethod ecclesia.kernel:vga-write-char-forms ((isa aarch64))
  `(;; Write character to UART
    (strb w0 (mem x19))
    ;; Increment column counter
    (movx x18 uart-col)
    (ldrb w1 (mem x18))
    (add-imm x1 x1 1)
    ;; Check if col hit terminal width (80)
    (cmp-imm w1 80)
    (bne uart-write-col-done)
    ;; Wrap: save col-1 (=79, last written position) to uart-prev-col
    (movx x18 uart-prev-col)
    (sub-imm w2 w1 1)
    (strb w2 (mem x18))
    (movx x18 uart-row)
    (ldrb w2 (mem x18))
    (add-imm x2 x2 1)
    (strb w2 (mem x18))
    (movx x1 0)
    (label uart-write-col-done)
    (movx x18 uart-col)
    (strb w1 (mem x18))))

;;; vga-erase-char-forms
;;;
;;; Two cases:
;;;   col > 0  → simple BS SP BS
;;;   col = 0  → we wrapped; go up one row via ANSI ESC[A, then move
;;;               to column uart-prev-col-at-wrap via BS-chain or ESC[nG
;;;
;;; We use ANSI escape sequences:
;;;   ESC [ A        — cursor up 1 line
;;;   ESC [ <n> G    — cursor to column n (1-based)
;;;
;;; uart-prev-col holds the column value at the last newline/wrap.
;;; uart-row holds the current row (0 = at or above prompt row, no up allowed).

(defun uart-ansi-cursor-up-forms ()
  "Emit ESC [ A — cursor up one line."
  (append (uart-putc-forms 27)   ; ESC
          (uart-putc-forms 91)   ; [
          (uart-putc-forms 65))) ; A

(defun uart-ansi-cursor-col-forms ()
  "Emit ESC [ <col+1> G — move cursor to 1-based column.
   Input: x4 = 0-based column. Uses x5,x6,x7,x8 as scratch."
  `(;; ESC [
    ,@(uart-putc-forms 27)
    ,@(uart-putc-forms 91)
    ;; x5 = x4 + 1 (1-based column)
    (add-imm x5 x4 1)
    ;; x6 = 10 (divisor)
    (movx x6 10)
    ;; x7 = x5 / 10 (tens digit)
    (udiv w7 w5 w6)
    ;; skip leading zero if tens=0
    (cmp-imm w7 0)
    (beq uart-col-ones)
    (add-imm x8 x7 48)        ; ASCII digit
    (strb w8 (mem x19))
    (label uart-col-ones)
    ;; x8 = x5 - x7*10 (ones digit) via MSUB
    (msub w8 w7 w6 w5)
    (add-imm x8 x8 48)
    (strb w8 (mem x19))
    ;; 'G'
    ,@(uart-putc-forms 71)))

(defmethod ecclesia.kernel:vga-erase-char-forms ((isa aarch64))
  `(;; Load current column into w1
    (movx x18 uart-col)
    (ldrb w1 (mem x18))
    (cmp-imm w1 0)
    (bne uart-bs-simple)     ; col > 0: simple backspace

    ;; col = 0: check row — if row = 0, nothing to do (prompt protection)
    (movx x18 uart-row)
    (ldrb w2 (mem x18))
    (cmp-imm w2 0)
    (beq uart-bs-done)

    ;; Also guard row 0: if row=0 and col <= prompt length, stop
    ;; (col=0 here, and row>0, so we're safe to go up)

    ;; Move up: decrement row
    (sub-imm w2 w2 1)
    (movx x18 uart-row)
    (strb w2 (mem x18))

    ;; Restore col to uart-prev-col
    (movx x18 uart-prev-col)
    (ldrb w1 (mem x18))
    (movx x18 uart-col)
    (strb w1 (mem x18))

    ;; Emit ESC[A (cursor up)
    ,@(uart-ansi-cursor-up-forms)

    ;; Emit ESC[nG (cursor to column uart-prev-col, 1-based)
    ;; x4 = x1 (already the column)
    (add-imm x4 x1 0)
    ,@(uart-ansi-cursor-col-forms)

    ;; Erase the char at this position: SP then back
    ,@(uart-putc-forms 32)
    ,@(uart-putc-forms 8)
    (b uart-bs-done)

    ;; Simple case: col > 0
    ;; But on row 0, don't go below prompt length
    (label uart-bs-simple)
    (movx x18 uart-row)
    (ldrb w3 (mem x18))
    (cmp-imm w3 0)
    (bne uart-bs-do)            ; not row 0, always allow
    ;; row 0: check col > prompt-len
    (movx x18 uart-prompt-len)
    (ldrb w3 (mem x18))
    (cmp-reg w1 w3)
    (bls uart-bs-done)          ; col <= prompt-len, refuse
    (label uart-bs-do)
    (sub-imm w1 w1 1)
    (movx x18 uart-col)
    (strb w1 (mem x18))
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
          ;; Set uart-col and uart-prompt-len to length of prompt string
          `((movx x18 uart-col)
            (movx x1 ,(length str))
            (strb w1 (mem x18))
            (movx x18 uart-prompt-len)
            (strb w1 (mem x18)))))

;;; unconditional-jump-forms → AArch64 B label
(defmethod ecclesia.kernel:unconditional-jump-forms ((isa aarch64) label)
  `((b ,label)))

;;; embedded-data-forms — 4-byte-aligned data block
;;;   uart-col      — current column (0-79)
;;;   uart-row      — current row relative to prompt (0 = first line)
;;;   uart-prev-col — column count before the last wrap (for backspace recovery)
;;; Each label gets 4 bytes to maintain alignment.
(defmethod ecclesia.kernel:embedded-data-forms ((isa aarch64) scancode-table-forms)
  (declare (ignore scancode-table-forms))
  `((label uart-col)        (db 0) (db 0) (db 0) (db 0)
    (label uart-row)        (db 0) (db 0) (db 0) (db 0)
    (label uart-prev-col)   (db 0) (db 0) (db 0) (db 0)
    (label uart-prompt-len) (db 0) (db 0) (db 0) (db 0)))
