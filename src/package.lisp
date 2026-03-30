;;;; package.lisp — Ecclesia package definition

(defpackage #:ecclesia
  (:use #:cl)
  (:export #:write-kernel
           #:assemble
           #:collect-labels
           #:emit-instruction
           #:eval-expr
           #:*bootloader*
           #:+code-size+
           #:boot-message-db-forms
           #:*boot-message*
           #:*stage2*
           #:stage2-size
           #:*kernel64*
           #:+floppy-sector-size+
           #:+stage2-sectors+
           #:+stage2-size+))
