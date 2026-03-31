;;;; main.lisp — 64-bit kernel entry point
;;;;
;;;; MVP: poll PS/2 keyboard, translate scancode→ASCII via embedded lookup table,
;;;; write characters to VGA at a tracked cursor position.

(in-package #:ecclesia)

(defparameter *prompt-str* "ecclesia> ")
(defparameter *prompt-row* 6)

;;; US QWERTY scancode set 1 → ASCII, unshifted (89 entries: 0x00–0x58)
(defparameter *scancode-ascii*
  #(  0  27  49  50  51  52  53  54  55  56  57  48  45  61   8   9
    113 119 101 114 116 121 117 105 111 112  91  93  13   0  97 115
    100 102 103 104 106 107 108  59  39  96   0  92 122 120  99 118
     98 110 109  44  46  47   0   0   0  32   0   0   0   0   0   0
      0   0   0   0   0   0   0   0   0   0   0   0   0   0   0   0
      0   0   0   0   0   0   0   0   0))

(defun scancode-db-forms ()
  (loop for c across *scancode-ascii* collect `(db ,c)))

(defparameter *kernel64*
  `(;; ===== 64-bit kernel entry =====
    (bits 64)
    (org  #x100000)

    (mov  rsp #x200000)
    (mov  rdi #xb8000)

    ;; Print prompt
    ,@(vga-rdi-write *prompt-str* :row *prompt-row* :col 0 :attr #x0a)

    ;; Jump over embedded data
    (jmp abs kbd-main-loop)

    ;; ── Embedded data ──────────────────────────────────────────────────────
    (label kbd-ascii-table)
    ,@(scancode-db-forms)

    (label kbd-cursor-col)  (db ,(length *prompt-str*))
    (label kbd-cursor-row)  (db ,*prompt-row*)

    ;; ── Main keyboard loop ───────────────────────────────────────────────────
    (label kbd-main-loop)
    (mov  rdi #xb8000)

    ;; Poll PS/2 port 0x64
    (label kbd-poll)
    (in   al #x64)
    (test al #x01)
    (jz   kbd-poll)

    ;; Read scancode
    (in   al #x60)

    ;; Skip key releases (bit 7 set)
    (test al #x80)
    (jnz  kbd-main-loop)

    ;; Skip scancodes ≥ 0x59
    (cmp8 al #x59)
    (jnc  kbd-main-loop)

    ;; Translate scancode → ASCII
    (movzx eax al)
    (mov   rbx kbd-ascii-table)
    (add   rbx rax)
    (byte-load-al-rbx)

    ;; Skip unmapped (ASCII = 0)
    (test  al al)
    (jz    kbd-main-loop)

    ;; ── Write char to VGA at cursor position ────────────────────────────────
    ;; Save char on the stack (RBX will be clobbered by cursor loads)
    (push-reg rax)

    ;; Load cursor position
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)              ; ECX = col
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)              ; EDX = row

    ;; VGA offset = (row*80 + col)*2
    (imul  edx #x50)
    (add   edx ecx)
    (imul  edx #x02)

    ;; Restore char
    (pop-reg rax)

    ;; Reload RDI (just in case)
    (mov   rdi #xb8000)

    ;; Write char + attr
    (store-rdi-edx-al 0)
    (store-rdi-edx-byte 1 #x0f)

    ;; ── Advance cursor ───────────────────────────────────────────────────────
    (mov   rbx kbd-cursor-col)
    (inc-byte-rbx)
    (byte-loadsx-ecx-rbx)
    (cmp8  cl #x50)
    (jnc   kbd-wrap)
    (jmp   abs kbd-main-loop)

    (label kbd-wrap)
    (store-zero-rbx)
    (mov   rbx kbd-cursor-row)
    (inc-byte-rbx)

    (jmp abs kbd-main-loop)))
