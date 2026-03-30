;;;; kernel64.lisp — 64-bit kernel entry point (0x100000)
;;;;
;;;; At entry: 64-bit long mode, identity-mapped 2MB, stack at 0x200000.
;;;; No BIOS. VGA text buffer at 0xB8000.
;;;;
;;;; VGA writes use register-indirect addressing (safe in 64-bit mode).
;;;; We load VGA base into RDI and use (mem-rdi offset) form.

(in-package #:ecclesia)

(defparameter *vga-base-addr* #xb8000)
(defparameter *vga-cols*      80)

;;; Emit a word (char + attr) to VGA at RDI + offset
;;; We encode as: MOV WORD PTR [RDI + offset], imm16
;;; Encoding: 0x66 0xC7 0x87 <offset32> <imm16>  (ModRM: mod=10,reg=0,r/m=7=rdi)
(defun vga-rdi-word-forms (offset char attr)
  (let ((word (logior char (ash attr 8))))
    `((mov-rdi-word ,offset ,word))))

(defun vga-write-str-forms (row col str attr)
  "Emit forms to write STR to VGA at (ROW, COL), using RDI as VGA base."
  (loop for ch across str
        for c from col
        for offset = (* 2 (+ (* row *vga-cols*) c))
        append (vga-rdi-word-forms offset (char-code ch) attr)))

(defparameter *kernel64*
  `(;; ===== 64-bit kernel entry =====
    (bits 64)
    (org  #x100000)

    ;; Set up stack
    (mov  rsp #x200000)

    ;; Load VGA base into RDI
    (mov  rdi #xb8000)

    ;; ── Clear screen: 80×25 cells, space (0x20) + grey attr (0x07) ───────
    ;; Each cell = 2 bytes. 80×25 = 2000 cells. Fill with 0x0720.
    ;; We write 4 bytes at a time (two cells) using STOSD.
    ;; EDI already = 0xB8000. EAX = 0x07200720, ECX = 1000.
    (mov  eax #x07200720)
    (mov  ecx #x03e8)
    (rep  stosd)               ; RDI advances; restore it after

    ;; Restore RDI to VGA base
    (mov  rdi #xb8000)

    ;; ── Print banner ─────────────────────────────────────────────────────
    ,@(vga-write-str-forms 1 1 "  ___         _           _     " #x0f)
    ,@(vga-write-str-forms 2 1 " | __| __ __ | | ___  ___(_) __ " #x0f)
    ,@(vga-write-str-forms 3 1 " | _|  \\ V / | |/ -_)(_-/| |/ _|" #x0f)
    ,@(vga-write-str-forms 4 1 " |___|  \\_/  |_|\\___|/__/|_|\\__|" #x0f)
    ,@(vga-write-str-forms 6 1 "  A Lisp OS for the ages." #x0f)
    ,@(vga-write-str-forms 8 0 "ecclesia> " #x0a)   ; bright green prompt

    ;; ── Keyboard polling loop ─────────────────────────────────────────────
    (label kbd-wait)
    (in   al #x64)           ; read PS/2 status
    (test al #x01)           ; output buffer full?
    (jz   kbd-wait)

    (in   al #x60)           ; read scancode
    (test al #x80)           ; key-release?
    (jnz  kbd-wait)

    ;; Halt on keypress — echo loop is next PR
    (hlt)
    (jmp  abs #x100000)))
