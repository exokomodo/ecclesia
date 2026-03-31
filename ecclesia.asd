;;;; ecclesia.asd — ASDF system definition for Ecclesia

(defsystem ecclesia
  :description "Ecclesia: a Common Lisp microkernel OS."
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "package")
     (:module "build"
      :components
      ((:module "assembler"
        :components ((:file "assembler")
                     (:file "x86-64")))
       (:module "utils"
        :components ((:file "vga-print")))
       (:module "boot"
        :components ((:file "bootloader-x86-64")
                     (:file "stage2-x86-64")))))
     (:module "kernel"
      :components ((:file "kernel64")))))))

(defsystem ecclesia/test
  :description "Ecclesia unit tests."
  :depends-on (ecclesia)
  :serial t
  :components
  ((:module "test"
    :components ((:file "bootloader")
                 (:file "stage2")
                 (:file "kernel64")))))
