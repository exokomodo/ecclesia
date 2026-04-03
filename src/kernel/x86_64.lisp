;;;; x86_64.lisp — x86_64 implementations of the kernel generics
;;;;
;;;; Each method specializes on the x86_64 class and returns a list of
;;;; x86_64 assembler forms understood by ecclesia.assembler:assemble.

(in-package #:ecclesia.kernel.x86_64)

;;; ISA designator — pass (make-instance 'x86_64) to each generic.
(defclass x86_64 () ())

;;; ── PS/2 polling ─────────────────────────────────────────────────────────────
;;; Port I/O: AL, port 0x64 (status), port 0x60 (data).

(defmethod ecclesia.kernel:ps2-poll-forms ((isa x86_64))
  '((label kbd-poll)
    (in   al #x64)
    (test al #x01)
    (jz   kbd-poll)
    (in   al #x60)))

;;; ── Scancode filtering ───────────────────────────────────────────────────────

(defmethod ecclesia.kernel:scancode-filter-forms ((isa x86_64))
  '((test al #x80)
    (jnz  kbd-main-loop)
    (cmp8 al #x59)
    (jnc  kbd-main-loop)))

;;; ── Dispatch to handler ──────────────────────────────────────────────────────

(defmethod ecclesia.kernel:dispatch-to-handler-forms ((isa x86_64))
  '((cmp8 al #x08)
    (jz   kbd-backspace)
    (cmp8 al #x1b)
    (jz   kbd-escape)
    (jmp  abs kbd-printable)))

;;; ── Prompt print (VGA) ───────────────────────────────────────────────────────

(defmethod ecclesia.kernel:print-prompt-forms ((isa x86_64) str row)
  (ecclesia.utils:vga-rdi-write str :row row :col 0 :attr #x0a))

;;; ── Scancode → ASCII translation ─────────────────────────────────────────────

(defmethod ecclesia.kernel:scancode-translate-forms ((isa x86_64))
  '((movzx eax al)
    (mov   rbx kbd-ascii-table)
    (add   rbx rax)
    (byte-load-al-rbx)
    (test  al al)
    (jz    kbd-main-loop)))

;;; ── VGA offset computation ───────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-offset-forms ((isa x86_64))
  `((mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)
    (imul  edx ,(* 2 +vga-cols+))
    (imul  ecx #x02)
    (add   edx ecx)))

;;; ── VGA character write ──────────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-write-char-forms ((isa x86_64))
  `((mov   rdi ,+vga-base+)
    (store-rdi-edx-al 0)
    (store-rdi-edx-byte 1 ,ecclesia.kernel:*vga-char-attr*)))

;;; ── VGA character erase ──────────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-erase-char-forms ((isa x86_64))
  `((mov   rdi ,+vga-base+)
    (store-rdi-edx-byte 0 #x20)
    (store-rdi-edx-byte 1 ,ecclesia.kernel:*vga-char-attr*)))

;;; ── Cursor advance ───────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:cursor-advance-forms ((isa x86_64))
  `((mov   rbx kbd-cursor-col)
    (inc-byte-rbx)
    (byte-loadsx-ecx-rbx)
    (cmp8  cl ,+vga-cols+)
    (jc    kbd-no-wrap)
    (store-zero-rbx)
    (mov   rbx kbd-cursor-row)
    (inc-byte-rbx)
    (label kbd-no-wrap)))

;;; ── Screen-full check ────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:screen-full-check-forms ((isa x86_64))
  `((mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,ecclesia.kernel:*vga-screen-rows*)
    (jnc   kbd-full)))

;;; ── Backspace ────────────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:backspace-forms ((isa x86_64))
  `(;; Off-screen check
    (mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,ecclesia.kernel:*vga-screen-rows*)
    (jc    kbd-bs-on-screen)
    ;; Snap to last visible cell
    (store-byte-rbx ,(1- ecclesia.kernel:*vga-screen-rows*))
    (mov   rbx kbd-cursor-col)
    (store-byte-rbx ,(1- +vga-cols+))
    (jmp   abs kbd-bs-erase)
    (label kbd-bs-on-screen)
    ;; Prompt-edge clamp
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)
    (cmp8  cl ,(length ecclesia.kernel:*prompt-str*))
    (jbe   kbd-main-loop)
    (dec-byte-rbx)
    (label kbd-bs-erase)
    ,@(ecclesia.kernel:vga-offset-forms isa)
    ,@(ecclesia.kernel:vga-erase-char-forms isa)))

;;; ── ISA descriptor ───────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:make-kernel-isa ((target (eql :x86_64)))
  (make-instance 'x86_64))

(defmethod ecclesia.kernel:isa-bits ((isa x86_64))          64)
(defmethod ecclesia.kernel:isa-origin ((isa x86_64))        #x100000)
(defmethod ecclesia.kernel:isa-stack-pointer ((isa x86_64)) #x200000)

(defmethod ecclesia.kernel:isa-entry-prologue-forms ((isa x86_64))
  `((mov rsp ,(ecclesia.kernel:isa-stack-pointer isa))
    (mov rdi ,+vga-base+)))

;;; ── Structural generics ──────────────────────────────────────────────────────

(defmethod ecclesia.kernel:embedded-data-forms ((isa x86_64) scancode-table-forms)
  `((label kbd-ascii-table)
    ,@scancode-table-forms
    (label kbd-cursor-col) (db ,(length ecclesia.kernel:*prompt-str*))
    (label kbd-cursor-row) (db ,ecclesia.kernel:*prompt-row*)))

(defmethod ecclesia.kernel:unconditional-jump-forms ((isa x86_64) label)
  `((jmp abs ,label)))

(defmethod ecclesia.kernel:save-char-forms ((isa x86_64))
  '((push-reg rax)))

(defmethod ecclesia.kernel:restore-char-forms ((isa x86_64))
  '((pop-reg rax)))

(defmethod ecclesia.kernel:discard-char-forms ((isa x86_64))
  '((pop-reg rax)))

(defmethod ecclesia.kernel:isa-supports-elf-loader-p ((isa x86_64)) t)

(defmethod ecclesia.kernel:asm-prelude-forms ((isa x86_64))
  `((bits ,(ecclesia.kernel:isa-bits isa))
    (org  ,(ecclesia.kernel:isa-origin isa))))
