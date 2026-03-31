;;;; ecclesia.asd — ASDF system definition for Ecclesia

(defsystem ecclesia
  :description "Ecclesia: a Common Lisp microkernel OS."
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "package")
     (:module "utils"
      :components ((:file "vga")))
     (:module "build"
      :components
      ((:module "assembler"
        :components ((:file "assembler")
                     (:file "x86-64")))
       (:module "boot"
        :components ((:file "bootloader-x86-64")
                     (:file "stage2-x86-64")))))
     (:module "kernel"
      :components ((:file "interface")
                   (:file "x86-64")))
     (:file "main")))))

(defsystem ecclesia/test
  :description "Ecclesia unit tests."
  :depends-on (ecclesia)
  :serial t
  :components
  ((:module "test"
    :components ((:file "bootloader")
                 (:file "stage2")
                 (:file "main")))))
