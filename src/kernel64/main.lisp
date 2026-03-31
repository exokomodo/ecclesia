;;;; main.lisp — 64-bit kernel entry point
;;;;
;;;; The kernel is structured as a set of named code-generation functions, each
;;;; responsible for one semantic step in the keyboard/VGA pipeline.  The top-level
;;;; *kernel64* stitches them together into a flat instruction sequence at
;;;; macro-expansion time.
;;;;
;;;; To port to a new ISA: implement each defgeneric below for the new target
;;;; and produce an equivalent *kernel<ISA>* parameter.

(in-package #:ecclesia)

;;; ── Configuration ───────────────────────────────────────────────────────────

(defparameter *prompt-str*       "ecclesia> ")
(defparameter *prompt-row*       23)
(defparameter *vga-screen-rows*  25)
(defparameter *vga-char-attr*    #x0f)   ; white on black

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

;;; ── ISA protocol (generic interface) ───────────────────────────────────────
;;;
;;; Each function below returns a list of assembler forms implementing one
;;; semantic step.  The x86-64 implementations follow.  A future ARM or RISC-V
;;; port would provide its own methods, keeping the top-level kernel logic
;;; identical.
;;;
;;; Naming convention: <isa>-<step>-forms
;;;   e.g. x86-64-ps2-poll-forms, arm64-ps2-poll-forms, …

;;; --- PS/2 polling ---

(defun x86-64-ps2-poll-forms ()
  "Spin on PS/2 status port 0x64 until a byte is ready (bit 0), then read it
   into AL from data port 0x60.  Clobbers: AL."
  `((label kbd-poll)
    (in   al #x64)          ; read PS/2 status register
    (test al #x01)          ; output-buffer-full bit
    (jz   kbd-poll)         ; not ready — keep spinning
    (in   al #x60)))        ; read scancode into AL

;;; --- Scancode filtering ---

(defun x86-64-scancode-filter-forms ()
  "Skip key-release events (bit 7) and out-of-table scancodes (>= 0x59).
   Jumps to KBD-MAIN-LOOP for ignored scancodes.  Clobbers: flags."
  `((test al #x80)          ; bit 7 = key release
    (jnz  kbd-main-loop)
    (cmp8 al #x59)          ; beyond our table?
    (jnc  kbd-main-loop)))

;;; --- Scancode → ASCII translation ---

(defun x86-64-scancode-translate-forms ()
  "Translate scancode in AL to ASCII via the embedded lookup table.
   Result in AL; jumps to KBD-MAIN-LOOP if the entry is 0 (unmapped).
   Clobbers: EAX, RBX."
  `((movzx eax al)                 ; zero-extend scancode
    (mov   rbx kbd-ascii-table)    ; table base address
    (add   rbx rax)                ; index into table
    (byte-load-al-rbx)             ; AL = ascii[scancode]
    (test  al al)                  ; unmapped?
    (jz    kbd-main-loop)))

;;; --- VGA offset computation ---

(defun x86-64-vga-offset-forms ()
  "Compute the VGA byte offset for the current cursor position.
   Loads cursor-row into EDX and cursor-col into ECX, then computes:
     EDX = (row * cols * 2) + (col * 2)
   Result in EDX.  Clobbers: RBX, ECX, EDX."
  `((mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)          ; EDX = row
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)          ; ECX = col
    (imul  edx ,(* 2 +vga-cols+))  ; EDX = row * 160
    (imul  ecx #x02)               ; ECX = col * 2
    (add   edx ecx)))              ; EDX = byte offset

;;; --- Write character to VGA ---

(defun x86-64-vga-write-char-forms ()
  "Write AL (char) and *vga-char-attr* to VGA at the offset in EDX.
   Requires RDI = +vga-base+.  Clobbers: nothing beyond RDI/EDX already set."
  `((mov   rdi ,+vga-base+)
    (store-rdi-edx-al 0)
    (store-rdi-edx-byte 1 ,*vga-char-attr*)))

;;; --- Erase character at cursor (write space) ---

(defun x86-64-vga-erase-char-forms ()
  "Write a space with *vga-char-attr* to VGA at the offset in EDX.
   Requires RDI = +vga-base+."
  `((mov   rdi ,+vga-base+)
    (store-rdi-edx-byte 0 #x20)
    (store-rdi-edx-byte 1 ,*vga-char-attr*)))

;;; --- Cursor advance ---

(defun x86-64-cursor-advance-forms ()
  "Increment cursor col.  If col reaches +vga-cols+, wrap to 0 and increment
   row.  Clobbers: RBX, ECX."
  `((mov   rbx kbd-cursor-col)
    (inc-byte-rbx)
    (byte-loadsx-ecx-rbx)           ; ECX = new col
    (cmp8  cl ,+vga-cols+)          ; col >= 80?
    (jc    kbd-no-wrap)             ; no — done

    ;; Wrap: col → 0, row++
    (store-zero-rbx)
    (mov   rbx kbd-cursor-row)
    (inc-byte-rbx)

    (label kbd-no-wrap)))

;;; --- Screen-full check ---

(defun x86-64-screen-full-check-forms ()
  "Check whether the cursor row has gone off-screen (>= *vga-screen-rows*).
   Loads row into EAX (via EDX).  Jumps to KBD-FULL if screen is full.
   Clobbers: RBX, EDX, EAX."
  `((mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,*vga-screen-rows*)
    (jnc   kbd-full)))

;;; --- Backspace handler ---

(defun x86-64-backspace-forms ()
  "Handle backspace.  If cursor is off-screen, snaps back to last visible cell.
   If cursor is at/before the prompt edge, the backspace is ignored.
   Otherwise decrements col and erases the vacated cell.
   Clobbers: RBX, EAX, ECX, EDX."
  `(;; Off-screen check: row >= *vga-screen-rows*?
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,*vga-screen-rows*)
    (jc    kbd-bs-on-screen)

    ;; Off-screen → snap to last visible cell (row 24, col 79)
    (store-byte-rbx ,(1- *vga-screen-rows*))
    (mov   rbx kbd-cursor-col)
    (store-byte-rbx ,(1- +vga-cols+))
    (jmp   abs kbd-bs-erase)

    (label kbd-bs-on-screen)
    ;; Prompt-edge clamp: don't erase the prompt
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)
    (cmp8  cl ,(length *prompt-str*))
    (jbe   kbd-main-loop)           ; at/before prompt — ignore
    (dec-byte-rbx)                  ; col--

    (label kbd-bs-erase)
    ,@(x86-64-vga-offset-forms)
    ,@(x86-64-vga-erase-char-forms)))

;;; ── Top-level kernel definition ─────────────────────────────────────────────

(defparameter *kernel64*
  `(;; ── Entry point ──────────────────────────────────────────────────────────
    (bits 64)
    (org  #x100000)

    (mov  rsp #x200000)
    (mov  rdi ,+vga-base+)

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

    ;; 1. Wait for and read a scancode from PS/2
    ,@(x86-64-ps2-poll-forms)

    ;; 2. Filter releases and out-of-range codes
    ,@(x86-64-scancode-filter-forms)

    ;; 3. Translate scancode → ASCII
    ,@(x86-64-scancode-translate-forms)

    ;; 4. Route: backspace vs. printable
    (cmp8  al #x08)
    (jz    kbd-backspace)
    (jmp   abs kbd-printable)

    ;; ── Backspace handler ────────────────────────────────────────────────────
    (label kbd-backspace)
    ,@(x86-64-backspace-forms)
    (jmp   abs kbd-main-loop)

    ;; ── Printable character handler ──────────────────────────────────────────
    (label kbd-printable)

    ;; 5. Reject if screen is full
    (push-reg rax)                  ; save char before check clobbers AL
    ,@(x86-64-screen-full-check-forms)

    ;; 6. Compute VGA offset and write the character
    ,@(x86-64-vga-offset-forms)
    (pop-reg rax)
    ,@(x86-64-vga-write-char-forms)

    ;; 7. Advance cursor
    ,@(x86-64-cursor-advance-forms)
    (jmp   abs kbd-main-loop)

    ;; ── Screen-full: discard char and loop ───────────────────────────────────
    (label kbd-full)
    (pop-reg rax)
    (jmp   abs kbd-main-loop)))
