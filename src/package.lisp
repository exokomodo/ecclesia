;;;; package.lisp — Ecclesia package definition

(defpackage #:ecclesia
  (:use #:cl)
  (:export #:write-kernel
           #:assemble
           #:*bootloader*
           #:+code-size+
           #:boot-message-db-forms
           #:*boot-message*))
