;;;; ecclesia.asd — ASDF system definition for Ecclesia kernel

(defpackage #:ecclesia-system
  (:use #:cl #:asdf))
(in-package #:ecclesia-system)

(defsystem ecclesia
  :description "Ecclesia: a Common Lisp microkernel OS."
  :serial t
  :components
  ((:file "package")
   (:file "assembler")
   (:file "bootloader")
   (:file "kernel")))
