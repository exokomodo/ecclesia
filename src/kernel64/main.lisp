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

    ;; ── Handle backspace (ASCII 8) ───────────────────────────────────────────
    (cmp8  al #x08)
    (jz    kbd-backspace)
    (jmp   abs kbd-printable)

    (label kbd-backspace)

    ;; Backspace: check if col > 0 first
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)              ; ECX = current col
    (test  cl cl)
    (jnz   kbd-bs-same-row)

    ;; Col is 0 — need to go back to previous row
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)              ; EDX = current row
    (cmp8  cl ,*prompt-row*)           ; on prompt row? (CL=0 here, but check row)
    ;; Actually check row: if row <= prompt-row AND col <= prompt-len, reject
    ;; For now: if row == prompt-row, col is already 0, reject
    ;; (can't backspace past start of prompt row)

    ;; Compare row to prompt row — need to use DL not CL
    ;; DL holds row from byte-loadsx-edx-rbx... but cmp8 only does AL/CL.
    ;; Workaround: copy EDX to EAX, compare AL
    (mov   eax edx)
    (cmp8  al ,*prompt-row*)
    (jbe   kbd-main-loop)              ; row <= prompt row with col 0 — ignore

    ;; Go to end of previous row
    (mov   rbx kbd-cursor-row)
    (dec-byte-rbx)
    (mov   rbx kbd-cursor-col)
    (store-byte-rbx ,(1- +vga-cols+))  ; col = 79

    ;; Erase char at new position (previous row, col 79)
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (imul  edx ,(* 2 +vga-cols+))
    (mov   ecx ,(* 2 (1- +vga-cols+))) ; col 79 * 2
    (add   edx ecx)
    (mov   rdi ,+vga-base+)
    (store-rdi-edx-byte 0 #x20)
    (store-rdi-edx-byte 1 #x0f)
    (jmp   abs kbd-main-loop)

    (label kbd-bs-same-row)
    ;; Check prompt clamp (only on prompt row)
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,*prompt-row*)
    (jnz   kbd-bs-do-it)               ; not prompt row — no clamp

    ;; On prompt row: check col <= prompt length
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)
    (cmp8  cl ,(length *prompt-str*))
    (jbe   kbd-main-loop)              ; at/before prompt — ignore

    (label kbd-bs-do-it)
    (mov   rbx kbd-cursor-col)
    (dec-byte-rbx)

    ;; Compute VGA offset for the cell we just backed into
    (byte-loadsx-ecx-rbx)              ; ECX = new col (after dec)
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)              ; EDX = row
    (imul  edx ,(* 2 +vga-cols+))
    (imul  ecx #x02)
    (add   edx ecx)

    ;; Write space to erase
    (mov   rdi ,+vga-base+)
    (store-rdi-edx-byte 0 #x20)
    (store-rdi-edx-byte 1 #x0f)

    (jmp   abs kbd-main-loop)

    ;; ── Printable char ──────────────────────────────────────────────────────
    (label kbd-printable)
    ;; Save char before we clobber AL for the row check
    (push-reg rax)

    ;; Reject if screen full (row >= 25)
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al #x19)                    ; row >= 25?
    (jc    kbd-do-print)               ; row < 25 — proceed

    ;; Screen full — discard char and loop
    (pop-reg rax)
    (jmp   abs kbd-main-loop)

    (label kbd-do-print)
    ;; Load cursor col
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)              ; ECX = col

    ;; VGA offset = (row * 80 + col) * 2
    (imul  edx ,(* 2 +vga-cols+))      ; EDX = row * 160
    (imul  ecx #x02)                   ; ECX = col * 2
    (add   edx ecx)                    ; EDX = byte offset

    ;; Restore char into AL
    (pop-reg rax)

    ;; Write char + attr
    (mov   rdi ,+vga-base+)
    (store-rdi-edx-al 0)
    (store-rdi-edx-byte 1 #x0f)

    ;; ── Advance cursor col ───────────────────────────────────────────────────
    (mov   rbx kbd-cursor-col)
    (inc-byte-rbx)
    (byte-loadsx-ecx-rbx)              ; ECX = new col
    (cmp8  cl ,+vga-cols+)             ; col >= 80?
    (jc    kbd-no-wrap)                ; no — skip wrap

    ;; Col overflow: wrap to col 0, advance row (let it go to 25)
    (store-zero-rbx)                   ; col = 0
    (mov   rbx kbd-cursor-row)
    (inc-byte-rbx)

    (label kbd-no-wrap)
    (jmp   abs kbd-main-loop)))
