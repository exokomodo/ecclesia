;;;; package.lisp — Ecclesia package definitions
;;;;
;;;; ecclesia.utils         — VGA helpers, common utilities
;;;; ecclesia.assembler     — Generic assembler
;;;; ecclesia.boot          — boot code
;;;; ecclesia.kernel        — ISA-agnostic kernel generics
;;;; ecclesia.kernel.x86_64 — x86_64 implementations of the kernel generics
;;;; ecclesia               — kernel image definitions (*kernel-main*, etc.)

(defpackage #:ecclesia.utils
  (:use #:cl)
  (:export
   #:+vga-base+
   #:+vga-cols+
   #:vga-addr
   #:vga-offset
   #:vga-cell
   #:vga-clear-forms
   #:vga-write
   #:vga-status
   #:vga-rdi-write
   #:vga-rdi-status))

(defpackage #:ecclesia.assembler
  (:use #:cl
        #:ecclesia.utils)
  (:export
   #:assemble
   #:collect-labels
   #:emit-instruction
   #:eval-expr
   #:register-instruction
   #:*asm-bits*
   #:*instruction-table*))

(defpackage #:ecclesia.boot
  (:use #:cl
        #:ecclesia.assembler
        #:ecclesia.utils)
  (:export
   #:r8-p
   #:r16-p
   #:r32-p
   #:r64-p
   #:sreg-p
   #:creg-p
   #:push-byte
   #:push-u16
   #:push-u32
   #:push-u64
   #:cur-addr
   #:resolve
   #:maybe-66
   #:+floppy-sector-size+
   #:+stage2-sectors+
   #:+stage2-size+
   #:+code-size+
   #:real-mode-init-forms
   #:a20-enable-forms
   #:enter-protected-mode-forms
   #:setup-pm-segments-forms
   #:*bootloader*
   #:boot-message-db-forms
   #:*boot-message*
   #:*stage2*
   #:stage2-size
   #:page-table-forms
   #:long-mode-entry-forms))

(defpackage #:ecclesia.kernel
  (:use #:cl
        #:ecclesia.utils)
  (:export
   #:*prompt-str*
   #:*prompt-row*
   #:*vga-screen-rows*
   #:*vga-char-attr*
   #:isa-bits
   #:isa-origin
   #:isa-stack-pointer
   #:isa-entry-prologue-forms
   #:*build-target*
   #:make-kernel-isa
   #:resolve-build-target
   #:ps2-poll-forms
   #:scancode-filter-forms
   #:scancode-translate-forms
   #:vga-offset-forms
   #:vga-write-char-forms
   #:vga-erase-char-forms
   #:cursor-advance-forms
   #:screen-full-check-forms
   #:backspace-forms
   #:embedded-data-forms
   #:dispatch-to-handler-forms
   #:save-char-forms
   #:restore-char-forms
   #:discard-char-forms
   #:asm-prelude-forms
   #:unconditional-jump-forms
   #:print-prompt-forms
   #:isa-supports-elf-loader-p))

(defpackage #:ecclesia.kernel.x86_64
  (:use #:cl
        #:ecclesia.kernel
        #:ecclesia.utils)
  (:export #:x86_64))

(defpackage #:ecclesia.loader
  (:use #:cl
        #:ecclesia.assembler
        #:ecclesia.kernel
        #:ecclesia.kernel.x86_64)
  (:export #:load-elf-forms
           #:+elf-magic+
           #:+elf64-e-entry+
           #:+elf64-e-phoff+
           #:+elf64-e-phentsize+
           #:+elf64-e-phnum+
           #:+ph64-p-type+
           #:+ph64-p-offset+
           #:+ph64-p-vaddr+
           #:+ph64-p-filesz+
           #:+ph64-p-memsz+
           #:+pt-load+))

(defpackage #:ecclesia
  (:use #:cl
        #:ecclesia.assembler
        #:ecclesia.boot
        #:ecclesia.kernel
        #:ecclesia.kernel.x86_64
        #:ecclesia.loader
        #:ecclesia.utils)
  (:export
   #:make-kernel-main
   #:*kernel-main*))
