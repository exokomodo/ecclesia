;;;; package.lisp — Ecclesia package definition

(defpackage #:ecclesia
  (:use #:cl)
  (:export #:write-kernel
           #:assemble
           #:*bootloader*
           #:+code-size+
           #:banner-db-forms
           #:*banner*))
