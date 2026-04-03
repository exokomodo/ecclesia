;;;; loader/elf-x86_64.lisp — x86-64 ELF64 loader implementation
;;;;
;;;; Register conventions during load:
;;;;   RSI = ELF base address (constant throughout)
;;;;   RCX = loop counter (phnum → 0)
;;;;   RBX = current program header pointer
;;;;   RDI = copy destination
;;;;   RAX = scratch
;;;;   RDX = scratch
;;;;
;;;; Clobbers: RAX, RBX, RCX, RDX, RDI, RSI

(in-package #:ecclesia.loader)

(defmethod load-elf-forms ((isa ecclesia.kernel.x86-base:x86-base) elf-load-addr)
  `(;; ── Load ELF base into RSI ────────────────────────────────────────────
    (mov rsi ,elf-load-addr)

    ;; ── Debug: 'L' in cyan on row 8 col 0 = entered loader ──────────────
    (mov rdi #xb8000)
    (mov-rdi-word ,(* 8 80 2) #x0b4c)   ; col 0: 'L'

    ;; ── Verify ELF magic ─────────────────────────────────────────────────
    (mem-load32 eax rsi 0)
    (cmp eax ,+elf-magic+)
    (jnz elf-bad-magic)

    ;; ── Debug: 'O' in cyan col 1 = magic ok ─────────────────────────────
    (mov rdi #xb8000)
    (mov-rdi-word ,(+ (* 8 80 2) 2) #x0b4f)   ; col 1: 'O'

    ;; ── Read e_phnum → ECX ───────────────────────────────────────────────
    (mem-load16-zx ecx rsi ,+elf64-e-phnum+)

    ;; ── Read e_phoff → RBX; compute first PH entry = RSI + e_phoff ──────
    (mem-load64 rbx rsi ,+elf64-e-phoff+)
    (add rbx rsi)



    ;; ── Walk program headers ─────────────────────────────────────────────
    (label elf-ph-loop)
    (cmp ecx 0)
    (jz elf-jump-entry)

    ;; Read p_type (u32 at RBX+0)
    (mem-load32 eax rbx 0)
    (cmp eax ,+pt-load+)
    (jnz elf-ph-next)

    ;; ── Copy PT_LOAD segment ──────────────────────────────────────────────
    ;; Save loop counter (ECX = phnum remaining) and PH pointer (RBX)
    (push-reg rcx)                ; save loop counter
    (push-reg rbx)                ; save PH pointer

    ;; RDI = p_vaddr (destination)
    (mem-load64 rdi rbx ,+ph64-p-vaddr+)
    ;; RCX = p_filesz (byte count for copy)
    (mem-load64 rcx rbx ,+ph64-p-filesz+)
    ;; RSI = ELF base + p_offset (source)
    (mem-load64 rdx rbx ,+ph64-p-offset+)
    (mov-r64 rsi rdx)
    ;; RSI = ELF base + RDX (p_offset)
    (mov-r64 rsi rdx)
    (add-imm64 rsi ,elf-load-addr)
    ;; Save filesz for BSS calculation
    (push-reg rcx)
    ;; REP MOVSB — copy filesz bytes from [RSI] to [RDI]
    (rep movsb)

    ;; ── Zero BSS (memsz - filesz bytes after segment) ────────────────────
    (pop-reg rcx)                 ; rcx = filesz
    (pop-reg rbx)                 ; restore PH pointer
    (mem-load64 rdx rbx ,+ph64-p-memsz+)
    (sub rdx rcx)                 ; rdx = memsz - filesz = BSS size
    (cmp rdx 0)
    (jz elf-bss-done)             ; no BSS to zero
    ;; RDI already points past the copied data (REP MOVSB advanced it)
    (mov-r64 rcx rdx)
    (xor eax eax)
    (rep stosb)
    (label elf-bss-done)

    ;; Restore loop counter
    (pop-reg rcx)                 ; rcx = phnum remaining

    ;; ── Advance to next PH entry (size = 56 bytes for ELF64) ─────────────
    (label elf-ph-next)
    (mov rsi ,elf-load-addr)
    (add-imm64 rbx 56)
    (dec ecx)
    (jmp abs elf-ph-loop)

    ;; ── Call entry point (CALL so _start can RET back here) ──────────────
    (label elf-jump-entry)
    ;; Debug: 'J' in cyan col 2 = reached jump-entry
    (mov rdi #xb8000)
    (mov-rdi-word ,(+ (* 8 80 2) 4) #x0b4a)
    (mem-load64 rax rsi ,+elf64-e-entry+)
    ;; Debug: 'C' in cyan col 3 = about to call
    (mov rdi #xb8000)
    (mov-rdi-word ,(+ (* 8 80 2) 6) #x0b43)
    ;; Give userland its own stack at 0x500000 (well above kernel at 0x200000)
    (mov rsp #x500000)
    (call-reg rax)
    ;; Debug: 'R' in cyan col 4 = _start returned
    (mov rdi #xb8000)
    (mov-rdi-word ,(+ (* 8 80 2) 8) #x0b52)
    ;; _start returned — restore kernel stack and resume keyboard loop
    (mov rsp #x200000)
    (jmp abs kbd-main-loop)

    ;; ── Bad magic: write "ELF?" in red on VGA row 7 then resume keyboard ──
    ;; Must use register-indirect: in 64-bit mode, MOV [imm32],imm is RIP-relative.
    ;; Row 7 col 0 = 0xB8000 + 7*80*2 = 0xB8460
    (label elf-bad-magic)
    (mov rdi #xb8460)             ; absolute VGA address in register
    (mov-rdi-word 0 #x0c45)      ; 'E' red  (byte offset 0)
    (mov-rdi-word 2 #x0c4c)      ; 'L' red  (byte offset 2)
    (mov-rdi-word 4 #x0c46)      ; 'F' red  (byte offset 4)
    (mov-rdi-word 6 #x0c3f)      ; '?' red  (byte offset 6)
    ;; Return to keyboard loop — don't hlt, keep the OS alive
    (jmp abs kbd-main-loop)))
