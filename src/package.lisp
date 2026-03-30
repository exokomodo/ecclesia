;;;; package.lisp — Ecclesia package definition

(defpackage #:ecclesia
  (:use #:cl)
  (:export #:assemble
           #:collect-labels
           #:emit-instruction
           #:eval-expr
           #:*bootloader*
           #:+code-size+
           #:boot-message-db-forms
           #:*boot-message*
           #:+vga-base+
           #:+vga-cols+
           #:vga-addr
           #:vga-offset
           #:vga-cell
           #:vga-clear-forms
           #:vga-write
           #:vga-status
           #:vga-rdi-write
           #:vga-rdi-status
           #:*stage2*
           #:stage2-size
           #:*kernel64*
           #:+floppy-sector-size+
           #:+stage2-sectors+
           #:+stage2-size+))
