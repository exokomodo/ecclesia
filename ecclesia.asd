;;;; ecclesia.asd — ASDF system definition for Ecclesia

(defsystem ecclesia
  :description "Ecclesia: a Common Lisp microkernel OS."
  :serial t
  :components
  ((:module "src"
    :components
    ((:file "package")
     (:module "assembler"
      :components ((:file "assembler")
                   (:file "x86_64")))
     (:module "bootstrap"
      :serial t
      :components ((:file "vga")
                   (:file "isa-interface")
                   (:file "isa-x86_64")
                   (:file "stage2-base")
                   (:file "bootloader")
                   (:file "elf")
                   (:file "elf-x86_64")
                   (:file "stage2")
                   (:file "image")))))))

(defsystem ecclesia/test
  :description "Ecclesia unit tests."
  :depends-on (ecclesia)
  :serial t
  :components
  ((:module "test"
    :components ((:file "bootloader")
                 (:file "stage2")
                 (:file "main")
                 (:file "floppy")))))
