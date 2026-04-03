;;;; package.lisp — Ecclesia package definitions
;;;;
;;;; ecclesia.assembler  — generic x86_64 assembler (src/assembler/)
;;;; ecclesia.bootstrap  — image build: MBR, Stage 2, ISA, ELF loader (src/bootstrap/)
;;;;
;;;; src/kernel/  — kernel entry point (C for now); no Lisp package needed yet.

(defpackage #:ecclesia.assembler
  (:use #:cl)
  (:export
   #:assemble
   #:collect-labels
   #:emit-instruction
   #:eval-expr
   #:register-instruction
   #:*asm-bits*
   #:*instruction-table*))

(defpackage #:ecclesia.bootstrap
  (:use #:cl #:ecclesia.assembler)
  (:export
   ;; VGA helpers
   #:+vga-base+
   #:+vga-cols+
   #:vga-addr
   #:vga-offset
   #:vga-cell
   #:vga-clear-forms
   #:vga-write
   #:vga-status
   #:vga-rdi-write
   #:vga-rdi-status
   ;; Register predicates and encoding helpers
   #:r8-p #:r16-p #:r32-p #:r64-p #:sreg-p #:creg-p
   #:push-byte #:push-u16 #:push-u32 #:push-u64
   #:cur-addr #:resolve #:maybe-66
   ;; Boot constants
   #:+floppy-sector-size+
   #:+stage2-sectors+
   #:+stage2-size+
   #:+code-size+
   ;; Stage 2 helpers
   #:real-mode-init-forms
   #:a20-enable-forms
   #:enter-protected-mode-forms
   #:setup-pm-segments-forms
   ;; Boot images
   #:*bootloader*
   #:boot-message-db-forms
   #:*boot-message*
   #:*stage2*
   #:build-stage2
   #:stage2-size
   #:page-table-forms
   #:long-mode-entry-forms
   ;; ISA protocol
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
   #:isa-supports-elf-loader-p
   ;; ISA classes
   #:x86_64
   ;; ELF loader
   #:load-elf-forms
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
   #:+pt-load+
   #:+elf-stack-top+))
