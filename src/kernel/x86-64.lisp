;;;; x86-64.lisp — x86-64 implementations of the kernel pipeline generics
;;;;
;;;; Each method specializes on the X86-64 class and returns a list of
;;;; x86-64 assembler forms understood by ecclesia.build:assemble.

(in-package #:ecclesia.kernel.x86-64)



;;; ISA designator — pass (make-instance 'x86-64) to each generic.
(defclass x86-64 () ())

;;; ── PS/2 polling ─────────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:ps2-poll-forms ((isa x86-64))
  "Spin on PS/2 status port 0x64 until output-buffer-full (bit 0) is set,
   then read the scancode from data port 0x60 into AL."
  '((label kbd-poll)
    (in   al #x64)          ; read PS/2 status register
    (test al #x01)          ; output-buffer-full?
    (jz   kbd-poll)         ; not ready — spin
    (in   al #x60)))        ; read scancode → AL

;;; ── Scancode filtering ───────────────────────────────────────────────────────

(defmethod ecclesia.kernel:scancode-filter-forms ((isa x86-64))
  "Discard key-release scancodes (bit 7 set) and any scancode >= 0x59
   (beyond our translation table).  Both cases branch to KBD-MAIN-LOOP."
  '((test al #x80)          ; bit 7 = key release
    (jnz  kbd-main-loop)
    (cmp8 al #x59)          ; beyond translation table?
    (jnc  kbd-main-loop)))

;;; ── Scancode → ASCII translation ─────────────────────────────────────────────

(defmethod ecclesia.kernel:scancode-translate-forms ((isa x86-64))
  "Zero-extend the scancode, index into KBD-ASCII-TABLE, and load the ASCII
   result into AL.  Branches to KBD-MAIN-LOOP for unmapped entries (value 0).
   Clobbers: EAX, RBX."
  '((movzx eax al)                 ; zero-extend scancode into EAX
    (mov   rbx kbd-ascii-table)    ; table base
    (add   rbx rax)                ; table[scancode]
    (byte-load-al-rbx)             ; AL = ascii value
    (test  al al)                  ; unmapped?
    (jz    kbd-main-loop)))

;;; ── VGA offset computation ───────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-offset-forms ((isa x86-64))
  "Compute the VGA byte offset for the current cursor (row, col):
     EDX = row * (cols * 2) + col * 2
   Clobbers: RBX, ECX, EDX."
  `((mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)          ; EDX = row
    (mov   rbx kbd-cursor-col)
    (byte-loadsx-ecx-rbx)          ; ECX = col
    (imul  edx ,(* 2 +vga-cols+))  ; EDX = row * 160
    (imul  ecx #x02)               ; ECX = col * 2
    (add   edx ecx)))              ; EDX = byte offset

;;; ── VGA character write ───────────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-write-char-forms ((isa x86-64))
  "Write AL (character) and the video attribute to the VGA buffer at the
   offset in EDX.  Requires RDI = +vga-base+."
  `((mov   rdi ,+vga-base+)
    (store-rdi-edx-al 0)
    (store-rdi-edx-byte 1 ,ecclesia.kernel:*vga-char-attr*)))

;;; ── VGA character erase ──────────────────────────────────────────────────────

(defmethod ecclesia.kernel:vga-erase-char-forms ((isa x86-64))
  "Write a space and the video attribute to the VGA buffer at the offset in EDX.
   Requires RDI = +vga-base+."
  `((mov   rdi ,+vga-base+)
    (store-rdi-edx-byte 0 #x20)
    (store-rdi-edx-byte 1 ,ecclesia.kernel:*vga-char-attr*)))

;;; ── Cursor advance ───────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:cursor-advance-forms ((isa x86-64))
  "Increment cursor col.  When col reaches +vga-cols+ (80), wrap to 0 and
   increment row.  Clobbers: RBX, ECX."
  `((mov   rbx kbd-cursor-col)
    (inc-byte-rbx)
    (byte-loadsx-ecx-rbx)           ; ECX = new col
    (cmp8  cl ,+vga-cols+)          ; col >= 80?
    (jc    kbd-no-wrap)

    ;; Wrap: col → 0, row++
    (store-zero-rbx)
    (mov   rbx kbd-cursor-row)
    (inc-byte-rbx)

    (label kbd-no-wrap)))

;;; ── Screen-full check ────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:screen-full-check-forms ((isa x86-64))
  "Branch to KBD-FULL if cursor row >= *vga-screen-rows*.
   Clobbers: RBX, EDX, EAX."
  `((mov   rbx kbd-cursor-row)
    (byte-loadsx-edx-rbx)
    (mov   eax edx)
    (cmp8  al ,ecclesia.kernel:*vga-screen-rows*)
    (jnc   kbd-full)))

;;; ── Backspace ────────────────────────────────────────────────────────────────

(defmethod ecclesia.kernel:backspace-forms ((isa x86-64))
  "Handle backspace on x86-64:
   - If off-screen (row >= *vga-screen-rows*), snap to last visible cell.
   - If at/before the prompt edge, ignore.
   - Otherwise decrement col and erase the vacated cell.
   Clobbers: RBX, EAX, ECX, EDX."
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

(defmethod ecclesia.kernel:make-kernel-isa ((target (eql :x86-64)))
  "Return the x86-64 ISA instance for the :x86-64 build target keyword."
  (make-instance 'x86-64))

(defmethod ecclesia.kernel:isa-bits ((isa x86-64))          64)
(defmethod ecclesia.kernel:isa-origin ((isa x86-64))        #x100000)
(defmethod ecclesia.kernel:isa-stack-pointer ((isa x86-64)) #x200000)

(defmethod ecclesia.kernel:isa-entry-prologue-forms ((isa x86-64))
  "x86-64 kernel prologue: set RSP and load VGA base into RDI."
  `((mov rsp ,(ecclesia.kernel:isa-stack-pointer isa))
    (mov rdi ,+vga-base+)))
