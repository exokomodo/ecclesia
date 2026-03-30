;;;; ecclesia.asd — ASDF system definition for Ecclesia kernel

(defsystem ecclesia
  :description "Ecclesia: a Common Lisp microkernel OS."
  :serial t
  :components ((:module "src"
                :components
                ((:file "package")
                 (:file "assembler")
                 (:module "utils"
                  :components ((:file "vga-print")))
                 (:module "boot"
                  :components ((:file "bootloader")
                               (:file "stage2")
                               (:file "kernel64")))))))

(defsystem ecclesia/test
  :description "Ecclesia unit tests."
  :depends-on (ecclesia)
  :serial t
  :components ((:module "test"
                :components ((:file "bootloader")
                             (:file "stage2")
                             (:file "kernel64")))))
