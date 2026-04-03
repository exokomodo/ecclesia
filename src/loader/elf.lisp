;;;; loader/elf.lisp — Static ELF64 loader, emitted as kernel assembly forms
;;;;
;;;; Parses an ELF64 binary loaded at a known physical address and relocates
;;;; its PT_LOAD segments to their virtual addresses, then jumps to e_entry.
;;;;
;;;; ELF64 layout (offsets from start of ELF image):
;;;;
;;;;   0x00  e_ident[16]    magic + class + data + version + OS/ABI
;;;;   0x10  e_type         ET_EXEC=2
;;;;   0x12  e_machine      EM_X86_64=0x3E / EM_AARCH64=0xB7
;;;;   0x14  e_version
;;;;   0x18  e_entry        virtual entry point (64-bit)
;;;;   0x20  e_phoff        offset of program header table (64-bit)
;;;;   0x28  e_shoff        (ignored)
;;;;   0x30  e_flags        (ignored)
;;;;   0x34  e_ehsize       (ignored)
;;;;   0x36  e_phentsize    size of one program header entry
;;;;   0x38  e_phnum        number of program header entries
;;;;
;;;; ELF64 Program Header entry (32 bytes):
;;;;   0x00  p_type         PT_LOAD=1
;;;;   0x04  p_flags        rwx permissions
;;;;   0x08  p_offset       offset in file
;;;;   0x10  p_vaddr        virtual address to load at
;;;;   0x18  p_paddr        (physical, ignored)
;;;;   0x20  p_filesz       bytes in file
;;;;   0x28  p_memsz        bytes in memory (memsz-filesz = BSS)
;;;;
;;;; The loader assumes:
;;;;   - ELF image base is in RSI (x86-64) or X20 (aarch64)
;;;;   - Segments are PT_LOAD (type=1); others are skipped
;;;;   - No dynamic linking / relocations needed (static ELF)
;;;;
;;;; After loading, jumps to e_entry.

(in-package #:ecclesia.loader)

;;; ── ELF64 field offsets ──────────────────────────────────────────────────────

(defconstant +elf64-e-entry+    #x18)  ; 8-byte entry point VA
(defconstant +elf64-e-phoff+    #x20)  ; 8-byte PH table offset
(defconstant +elf64-e-phentsize+ #x36) ; 2-byte PH entry size
(defconstant +elf64-e-phnum+    #x38)  ; 2-byte PH entry count

(defconstant +ph64-p-type+   0)        ; 4-byte segment type
(defconstant +ph64-p-offset+ #x08)     ; 8-byte file offset
(defconstant +ph64-p-vaddr+  #x10)     ; 8-byte virtual address
(defconstant +ph64-p-filesz+ #x20)     ; 8-byte file size
(defconstant +ph64-p-memsz+  #x28)     ; 8-byte memory size

(defconstant +pt-load+ 1)

;;; ── ELF magic verification ───────────────────────────────────────────────────

(defconstant +elf-magic+ #x464c457f)   ; 0x7F 'E' 'L' 'F'

;;; ── Generic loader forms ─────────────────────────────────────────────────────
;;;
;;; These are ISA-specific; each ISA implements load-elf-forms.

(defgeneric load-elf-forms (isa elf-load-addr)
  (:documentation
   "Return assembly forms that parse an ELF64 binary at ELF-LOAD-ADDR
    and jump to its entry point.  The binary must be a static executable."))
