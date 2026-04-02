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

    ;; ── Verify ELF magic ─────────────────────────────────────────────────
    ;; First 4 bytes must be 0x7F 'E' 'L' 'F'
    (mem-load32 eax rsi 0)
    (cmp eax ,+elf-magic+)
    (jnz elf-bad-magic)

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
    ;; RDI = p_vaddr
    (mem-load64 rdi rbx ,+ph64-p-vaddr+)
    ;; RDX = p_offset; source = RSI + p_offset
    (mem-load64 rdx rbx ,+ph64-p-offset+)
    ;; Save RBX and filesz before REP MOVSB clobbers RCX
    (push-reg rbx)
    (mem-load64 rcx rbx ,+ph64-p-filesz+)
    (push-reg rcx)                ; save filesz
    ;; RSI = ELF base + p_offset  (rdx already = p_offset; add base)
    (mov-r64 rsi rdx)
    (add-imm64 rsi ,elf-load-addr) ; rsi = p_offset + elf_base
    ;; REP MOVSB — copy filesz bytes
    (rep movsb)

    ;; ── Zero BSS (memsz - filesz bytes after segment) ────────────────────
    (pop-reg rcx)                 ; rcx = filesz
    (pop-reg rbx)                 ; restore PH pointer
    (mem-load64 rdx rbx ,+ph64-p-memsz+)
    (sub rdx rcx)                 ; rdx = memsz - filesz
    (cmp rdx 0)
    (jz elf-ph-next)              ; no BSS to zero
    (mem-load64 rdi rbx ,+ph64-p-vaddr+)
    (add rdi rcx)                 ; rdi = p_vaddr + filesz (BSS start)
    (mov-r64 rcx rdx)
    (xor eax eax)
    (rep stosb)

    ;; ── Advance to next PH entry (size = 56 bytes for ELF64) ─────────────
    (label elf-ph-next)
    (mov rsi ,elf-load-addr)      ; restore RSI (clobbered by rep)
    (add-imm64 rbx 56)
    (dec ecx)
    (jmp abs elf-ph-loop)

    ;; ── Jump to entry point ───────────────────────────────────────────────
    (label elf-jump-entry)
    (mem-load64 rax rsi ,+elf64-e-entry+)
    (jmp-reg rax)

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
