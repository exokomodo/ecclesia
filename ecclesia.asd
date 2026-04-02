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
     (:module "assembler"
      :components ((:file "assembler")
                   (:file "x86_64")
                   (:file "aarch64")))
     (:module "boot"
      :components ((:file "bootloader-x86_64")
                   (:file "stage2-x86_base")
                   (:file "stage2-x86_64")
                   (:file "stage2-i386")
                   (:file "stage2-aarch64")))
     (:module "kernel"
      :components ((:file "interface")
                   (:file "x86_base")
                   (:file "x86_64")
                   (:file "i386")
                   (:module "board"
                    :components ((:file "interface")
                                 (:file "qemu-virt")
                                 (:file "raspi4b")
                                 (:file "raspi3b")))
                   (:file "aarch64")))
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
