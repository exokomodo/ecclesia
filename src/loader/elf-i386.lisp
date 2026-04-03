;;;; loader/elf-i386.lisp — i386 ELF32 loader implementation
;;;;
;;;; ELF32 header offsets:
;;;;   0x00  e_ident[16]
;;;;   0x10  e_type        (2 bytes)
;;;;   0x12  e_machine     (2 bytes)
;;;;   0x14  e_version     (4 bytes)
;;;;   0x18  e_entry       (4 bytes) ← virtual entry point
;;;;   0x1c  e_phoff       (4 bytes) ← program header table offset
;;;;   0x24  e_flags       (4 bytes)
;;;;   0x28  e_ehsize      (2 bytes)
;;;;   0x2a  e_phentsize   (2 bytes)
;;;;   0x2c  e_phnum       (2 bytes)
;;;;
;;;; ELF32 Program Header (32 bytes):
;;;;   0x00  p_type   (4 bytes)
;;;;   0x04  p_offset (4 bytes)
;;;;   0x08  p_vaddr  (4 bytes)
;;;;   0x0c  p_paddr  (4 bytes)
;;;;   0x10  p_filesz (4 bytes)
;;;;   0x14  p_memsz  (4 bytes)
;;;;   0x18  p_flags  (4 bytes)
;;;;   0x1c  p_align  (4 bytes)
;;;;
;;;; Register conventions:
;;;;   ESI = ELF base address (constant throughout)
;;;;   ECX = loop counter (phnum)
;;;;   EBX = current program header pointer
;;;;   EDI = copy destination
;;;;   EAX = scratch
;;;;   EDX = scratch

(in-package #:ecclesia.loader)

(defconstant +elf32-e-entry+    #x18)
(defconstant +elf32-e-phoff+    #x1c)
(defconstant +elf32-e-phnum+    #x2c)

(defconstant +ph32-p-type+   0)
(defconstant +ph32-p-offset+ #x04)
(defconstant +ph32-p-vaddr+  #x08)
(defconstant +ph32-p-filesz+ #x10)
(defconstant +ph32-p-memsz+  #x14)

;;; Helper: MOV r32, [r32+disp32]  →  8b /r disp32  (6 bytes)
;;; We inline this instead of a separate instruction to keep it simple.

(defmethod load-elf-forms ((isa ecclesia.kernel.i386:i386) elf-load-addr)
  `(;; ── Load ELF base into ESI ────────────────────────────────────────────
    (mov esi ,elf-load-addr)

    ;; ── Verify ELF magic ─────────────────────────────────────────────────
    (mem-load32 eax esi 0)
    (cmp eax ,+elf-magic+)
    (jnz elf-bad-magic)

    ;; ── Read e_phnum → ECX ───────────────────────────────────────────────
    (mem-load16-zx ecx esi ,+elf32-e-phnum+)

    ;; ── Read e_phoff → EBX; first PH = ESI + e_phoff ────────────────────
    (mem-load32 ebx esi ,+elf32-e-phoff+)
    (add ebx esi)

    ;; ── Walk program headers ─────────────────────────────────────────────
    (label elf-ph-loop)
    (cmp ecx 0)
    (jz elf-jump-entry)

    ;; Read p_type (u32 at EBX+0)
    (mem-load32 eax ebx 0)
    (cmp eax ,+pt-load+)
    (jnz elf-ph-next)

    ;; ── Copy PT_LOAD segment ──────────────────────────────────────────────
    (push-reg ecx)                ; save loop counter
    (push-reg ebx)                ; save PH pointer

    (mem-load32 edi ebx ,+ph32-p-vaddr+)
    (mem-load32 ecx ebx ,+ph32-p-filesz+)
    (mem-load32 edx ebx ,+ph32-p-offset+)
    (mov esi edx)
    (add esi ,elf-load-addr)      ; esi = elf_base + p_offset

    (push-reg ecx)                ; save filesz
    (rep movsb)

    ;; ── Zero BSS ─────────────────────────────────────────────────────────
    (pop-reg ecx)                 ; ecx = filesz
    (pop-reg ebx)                 ; restore PH pointer
    (mem-load32 edx ebx ,+ph32-p-memsz+)
    (sub edx ecx)                 ; edx = memsz - filesz
    (cmp edx 0)
    (jz elf-bss-done)
    (mov ecx edx)
    (xor eax eax)
    (rep stosb)
    (label elf-bss-done)

    (pop-reg ecx)                 ; restore loop counter

    ;; ── Advance to next PH (ELF32 PH entry = 32 bytes) ───────────────────
    (label elf-ph-next)
    (mov esi ,elf-load-addr)
    (add ebx 32)
    (dec ecx)
    (jmp abs elf-ph-loop)

    ;; ── Call entry point ─────────────────────────────────────────────────
    (label elf-jump-entry)
    (mem-load32 eax esi ,+elf32-e-entry+)
    (mov esp #x500000)            ; userland stack
    (call-reg32 eax)
    (mov esp #x90000)             ; restore kernel stack
    (jmp abs kbd-main-loop)

    ;; ── Bad magic: show ELF? in red on VGA row 7 ─────────────────────────
    (label elf-bad-magic)
    (mov edi #xb8460)
    (mov-rdi-word 0 #x0c45)       ; 'E'
    (mov-rdi-word 2 #x0c4c)       ; 'L'
    (mov-rdi-word 4 #x0c46)       ; 'F'
    (mov-rdi-word 6 #x0c3f)       ; '?'
    (jmp abs kbd-main-loop)))
