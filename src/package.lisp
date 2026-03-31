;;;; package.lisp — Ecclesia package definitions
;;;;
;;;; ecclesia.build — build-time toolchain: assembler, VGA helpers, boot code
;;;; ecclesia       — kernel runtime: the OS itself

(defpackage #:ecclesia.build
  (:use #:cl)
  (:export
   ;; Assembler core
   #:assemble
   #:collect-labels
   #:emit-instruction
   #:eval-expr
   #:register-instruction
   #:*asm-bits*
   #:*instruction-table*
   ;; x86-64 register predicates and helpers
   #:r8-p #:r16-p #:r32-p #:r64-p #:sreg-p #:creg-p
   #:push-byte #:push-u16 #:push-u32 #:push-u64
   #:cur-addr #:resolve #:maybe-66
   ;; VGA helpers
   #:+vga-base+ #:+vga-cols+
   #:vga-addr #:vga-offset #:vga-cell
   #:vga-clear-forms
   #:vga-write #:vga-status
   #:vga-rdi-write #:vga-rdi-status
   ;; Boot constants
   #:+floppy-sector-size+
   #:+stage2-sectors+
   #:+stage2-size+
   #:+code-size+
   ;; Boot image symbols
   #:*bootloader*
   #:boot-message-db-forms
   #:*boot-message*
   #:*stage2*
   #:stage2-size
   #:page-table-forms
   #:long-mode-entry-forms))

(defpackage #:ecclesia
  (:use #:cl #:ecclesia.build)
  (:export
   ;; Kernel entry point
   #:*kernel64*))
