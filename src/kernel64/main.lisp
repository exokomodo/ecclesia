;;;; main.lisp — 64-bit kernel entry point
;;;;
;;;; MVP: poll PS/2 keyboard, translate scancode→ASCII via embedded lookup table,
;;;; write characters to VGA at a tracked cursor position.
;;;;
;;;; Addressing strategy: all mutable state (cursor, table) is at known absolute
;;;; addresses within the kernel image. RBX is used as a pointer register for
;;;; byte-level access via [RBX].

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

    ;; Print banner and prompt (Stage 2 has already cleared screen)
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

    ;; Debug: '*' at row 5 col 1 = we reached loop top
    (mov-rdi-word #x322 ,(logior (char-code #\*) #x0c00))

    ;; Poll PS/2 port 0x64, wait for output buffer full (bit 0)
    (label kbd-poll)
    (in   al #x64)
    (test al #x01)
    (jz   kbd-poll)

    ;; Read scancode from port 0x60
    (in   al #x60)

    ;; Debug: write '!' immediately on ANY byte from keyboard
    (mov-rdi-word #x320 ,(logior (char-code #\!) #x0f00))

    ;; Skip key releases (bit 7 set)
    (test al #x80)
    (jnz  kbd-main-loop)

    ;; Skip scancodes ≥ 0x59 (out of table range)
    (cmp8 al #x59)
    (jnc  kbd-main-loop)

    ;; Translate scancode → ASCII via table
    ;; RBX = kbd-ascii-table + scancode
    (movzx eax al)
    (mov   rbx kbd-ascii-table)        ; MOV RBX, imm64 (absolute address)
    (add   rbx rax)                    ; RBX = &table[scancode]
    (byte-load-al-rbx)                 ; AL = table[scancode]

    ;; Skip unmapped (ASCII = 0)
    (test  al al)
    (jz    kbd-main-loop)

    ;; Debug: write the translated char at a fixed position (row 5 col 2)
    ;; so we can see what the table returned. EDX = 0x326 (row5 col2 offset).
    (mov   edx #x326)
    (store-rdi-edx-al 0)    ; write char at row 5 col 2
    (store-rdi-edx-byte 1 #x0e)  ; yellow attr

    ;; Save ASCII char in BL (survives the cursor loads below)
    (mov   bl al)

    ;; ── Compute VGA offset: (row*80 + col)*2 ─────────────────────────────
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)              ; ECX = col
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)              ; EDX = row

    ;; Restore RBX for cursor col address (needed after char write)
    (mov   rbx kbd-cursor-col)

    (imul  edx #x50)                   ; EDX = row * 80
    (add   edx ecx)                    ; EDX = row*80 + col
    (imul  edx #x02)                   ; EDX = byte offset

    ;; Move char from BL → AL for store-rdi-edx-al
    (mov   al bl)

    ;; Write char and attr to [RDI + EDX + 0] and [RDI + EDX + 1]
    (store-rdi-edx-al 0)               ; [RDI+EDX] = char
    (store-rdi-edx-byte 1 #x0f)        ; [RDI+EDX+1] = attr (white)

    ;; ── Advance cursor ───────────────────────────────────────────────────────
    (mov   rbx kbd-cursor-col)
    (inc-byte-rbx)                     ; col++
    (byte-loadsx-ecx-rbx)             ; ECX = new col
    (cmp8  cl #x50)                    ; col >= 80?
    (jnc   kbd-wrap)
    (jmp   abs kbd-main-loop)

    (label kbd-wrap)
    (store-zero-rbx)                   ; col = 0  (RBX still = &col)
    (mov   rbx kbd-cursor-row)
    (inc-byte-rbx)                     ; row++
    ;; TODO: scroll when row >= 25

    (jmp abs kbd-main-loop)))
