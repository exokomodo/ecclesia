;;;; kernel64.lisp — 64-bit kernel entry point (0x100000)
;;;;
;;;; At entry: 64-bit long mode, identity-mapped 2MB, stack at 0x200000.
;;;; No BIOS. VGA text buffer at 0xB8000.
;;;;
;;;; Boot sequence:
;;;;   1. Clear VGA screen
;;;;   2. Print banner
;;;;   3. Keyboard read loop (embryonic REPL)

(in-package #:ecclesia)

(defparameter *vga-base* #xb8000)
(defparameter *vga-cols* 80)
(defparameter *vga-rows* 25)

(defun vga-write-str-forms (row col str attr)
  "Emit forms to write STR to VGA at (ROW, COL) with ATTR byte."
  (loop for ch across str
        for c from col
        for addr = (+ *vga-base* (* 2 (+ (* row *vga-cols*) c)))
        collect `(mov (mem32 ,addr) ,(logior (char-code ch) (ash attr 8)))))

(defparameter *kernel64*
  `(;; ===== 64-bit kernel entry =====
    (bits 64)
    (org  #x100000)

    ;; Stack
    (mov  rsp #x200000)

    ;; ── Clear screen (80×25 spaces, grey on black = 0x0720) ─────────────
    ;; EDI = VGA base, EAX = fill word, ECX = cell count
    (mov  edi #xb8000)
    (mov  eax #x07200720)         ; two cells: space + grey attr
    (mov  ecx #x0fa0)             ; 80*25/2 = 1000 dwords... wait 80*25=2000 cells
    ;; Actually: 2000 cells × 2 bytes = 4000 bytes = 1000 dwords
    (mov  ecx #x03e8)             ; 1000 dwords
    (rep  stosd)

    ;; ── Print banner ─────────────────────────────────────────────────────
    ,@(vga-write-str-forms 1 1 "  ___         _           _     " #x0f)
    ,@(vga-write-str-forms 2 1 " | __| __ __ | | ___  ___(_) __ " #x0f)
    ,@(vga-write-str-forms 3 1 " | _|  \\ V / | |/ -_)(_-/| |/ _|" #x0f)
    ,@(vga-write-str-forms 4 1 " |___|  \\_/  |_|\\___|/__/|_|\\__|" #x0f)
    ,@(vga-write-str-forms 6 1 "  A Lisp OS for the ages." #x0f)
    ,@(vga-write-str-forms 8 0 "ecclesia> " #x0a)   ; green prompt

    ;; ── Keyboard polling loop ─────────────────────────────────────────
    ;; Wait until PS/2 output buffer is full (port 0x64 bit 0)
    (label kbd-wait)
    (in   al #x64)
    (test al #x01)
    (jz   kbd-wait)

    ;; Read scancode from port 0x60
    (in   al #x60)

    ;; Ignore key-release scancodes (bit 7 set)
    (test al #x80)
    (jnz  kbd-wait)

    ;; Halt — scancode→ASCII map and echo is next iteration
    (hlt)
    (jmp  abs #x100000)))
