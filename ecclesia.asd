;;;; ecclesia.asd — ASDF system definition for Ecclesia kernel

(defsystem ecclesia
  :description "Ecclesia: a Common Lisp microkernel OS."
  :serial t
  :components ((:module "src"
                :components ((:file "package")
                             (:file "assembler")
                             (:file "bootloader")
                             (:file "kernel")))))

(defsystem ecclesia/test
  :description "Ecclesia unit tests."
  :depends-on (ecclesia)
  :serial t
  :components ((:module "test"
                :components ((:file "bootloader")))))
