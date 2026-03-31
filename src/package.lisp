;;;; package.lisp — Ecclesia package definitions
;;;;
;;;; ecclesia.utils — VGA helpers, common utilities
;;;; ecclesia.build — build-time toolchain: assembler, boot code
;;;; ecclesia       — kernel runtime: the OS itself

(defpackage #:ecclesia.utils
  (:use #:cl)
  (:export
   ;; VGA helpers
   #:+vga-base+
   #:+vga-cols+
   #:vga-addr
   #:vga-offset
   #:vga-cell
   #:vga-clear-forms
   #:vga-write
   #:vga-status
   #:vga-rdi-write
   #:vga-rdi-status))

(defpackage #:ecclesia.build
  (:use #:cl
        #:ecclesia.utils)
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
   #:r8-p
   #:r16-p
   #:r32-p
   #:r64-p
   #:sreg-p
   #:creg-p
   #:push-byte
   #:push-u16
   #:push-u32
   #:push-u64
   #:cur-addr
   #:resolve
   #:maybe-66
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
  (:use #:cl
        #:ecclesia.build
        #:ecclesia.utils)
  (:export
   ;; Kernel entry point
   #:*kernel64*))
