;;;; i386.lisp — i386 (32-bit x86) implementations of the kernel generics
;;;;
;;;; The i386 target shares the x86 BIOS/VGA/PS2 hardware model with x86_64
;;;; but operates entirely in 32-bit protected mode.  Register names change
;;;; (rsp→esp, rbx→ebx, rdi→edi, rax→eax) and 64-bit-specific REX prefixes
;;;; are absent, but the ModRM encodings for [EBX]/[EDI+EDX+disp8] are
;;;; identical to their 64-bit counterparts, so most assembler instructions
;;;; emit the same bytes.

(in-package #:ecclesia.kernel.i386)

;;; ISA designator
(defclass i386 () ())

;;; ── PS/2 polling ─────────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:ps2-poll-forms ((isa i386))
  "Same PS/2 polling as x86_64 — port I/O is identical."
  '((label kbd-poll)
    (in   al #x64)
    (test al #x01)
    (jz   kbd-poll)
    (in   al #x60)))

;;; ── Scancode filtering ───────────────────────────────────────────────────────

(defmethod ecclesia.kernel:scancode-filter-forms ((isa i386))
  '((test al #x80)
    (jnz  kbd-main-loop)
    (cmp8 al #x59)
    (jnc  kbd-main-loop)))

;;; ── Scancode → ASCII translation ─────────────────────────────────────────────

(defmethod ecclesia.kernel:scancode-translate-forms ((isa i386))
  "Same as x86_64 but uses EBX instead of RBX (same ModRM bytes in 32-bit)."
  '((movzx eax al)
    (mov   ebx kbd-ascii-table)
    (add   ebx eax)
    (byte-load-al-rbx)          ; ModRM [EBX] = [RBX] in 32-bit mode
    (test  al al)
    (jz    kbd-main-loop)))

;;; ── VGA offset computation ───────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-offset-forms ((isa i386))
  "Compute VGA byte offset for cursor (row, col) using 32-bit registers."
  `((mov   ebx kbd-cursor-row)
    (byte-loadsx-edx-rbx)       ; EDX = row  (ModRM [EBX] same as [RBX])
    (mov   ebx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)       ; ECX = col
    (imul  edx ,(* 2 +vga-cols+))
    (imul  ecx #x02)
    (add   edx ecx)))

;;; ── VGA character write ───────────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-write-char-forms ((isa i386))
  "Write char + attribute to VGA at EDX offset.  EDI = +vga-base+."
  `((mov   edi ,+vga-base+)
    (store-rdi-edx-al 0)        ; MOV [EDI+EDX+0], AL  (same bytes as 64-bit)
    (store-rdi-edx-byte 1 ,ecclesia.kernel:*vga-char-attr*)))

;;; ── VGA character erase ──────────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-erase-char-forms ((isa i386))
  `((mov   edi ,+vga-base+)
    (store-rdi-edx-byte 0 #x20)
    (store-rdi-edx-byte 1 ,ecclesia.kernel:*vga-char-attr*)))

;;; ── Cursor advance ───────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:cursor-advance-forms ((isa i386))
  `((mov   ebx kbd-cursor-col)
    (inc-byte-rbx)
    (byte-loadsx-ecx-rbx)
    (cmp8  cl ,+vga-cols+)
    (jc    kbd-no-wrap)
    (store-zero-rbx)
    (mov   ebx kbd-cursor-row)
    (inc-byte-rbx)
    (label kbd-no-wrap)))

;;; ── Screen-full check ────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:screen-full-check-forms ((isa i386))
  `((mov   ebx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,ecclesia.kernel:*vga-screen-rows*)
    (jnc   kbd-full)))

;;; ── Backspace ────────────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:backspace-forms ((isa i386))
  `((mov   ebx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,ecclesia.kernel:*vga-screen-rows*)
    (jc    kbd-bs-on-screen)

    (store-byte-rbx ,(1- ecclesia.kernel:*vga-screen-rows*))
    (mov   ebx kbd-cursor-col)
    (store-byte-rbx ,(1- +vga-cols+))
    (jmp   abs kbd-bs-erase)

    (label kbd-bs-on-screen)
    (mov   ebx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)
    (cmp8  cl ,(length ecclesia.kernel:*prompt-str*))
    (jbe   kbd-main-loop)
    (dec-byte-rbx)

    (label kbd-bs-erase)
    ,@(ecclesia.kernel:vga-offset-forms isa)
    ,@(ecclesia.kernel:vga-erase-char-forms isa)))

;;; ── ISA descriptor ───────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:make-kernel-isa ((target (eql :i386)))
  (make-instance 'i386))

(defmethod ecclesia.kernel:isa-bits ((isa i386))          32)
(defmethod ecclesia.kernel:isa-origin ((isa i386))        #x20000)
(defmethod ecclesia.kernel:isa-stack-pointer ((isa i386)) #x90000)

(defmethod ecclesia.kernel:isa-entry-prologue-forms ((isa i386))
  "i386 kernel prologue: set ESP and load VGA base into EDI."
  `((mov esp ,(ecclesia.kernel:isa-stack-pointer isa))
    (mov edi ,+vga-base+)))

;;; ── Structural generics ──────────────────────────────────────────────────────

(defmethod ecclesia.kernel:asm-prelude-forms ((isa i386))
  `((bits ,(ecclesia.kernel:isa-bits isa))
    (org  ,(ecclesia.kernel:isa-origin isa))))

(defmethod ecclesia.kernel:unconditional-jump-forms ((isa i386) label)
  `((jmp abs ,label)))

(defmethod ecclesia.kernel:embedded-data-forms ((isa i386) scancode-table-forms)
  `((label kbd-ascii-table)
    ,@scancode-table-forms
    (label kbd-cursor-col) (db ,(length ecclesia.kernel:*prompt-str*))
    (label kbd-cursor-row) (db ,ecclesia.kernel:*prompt-row*)))

(defmethod ecclesia.kernel:dispatch-to-handler-forms ((isa i386))
  '((cmp8 al #x08)
    (jz   kbd-backspace)
    (jmp  abs kbd-printable)))

(defmethod ecclesia.kernel:save-char-forms ((isa i386))
  '((push-reg eax)))

(defmethod ecclesia.kernel:restore-char-forms ((isa i386))
  '((pop-reg eax)))

(defmethod ecclesia.kernel:discard-char-forms ((isa i386))
  '((pop-reg eax)))
