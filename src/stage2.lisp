;;;; stage2.lisp — Stage 2 bootloader
;;;;
;;;; Loaded at 0x8000 by Stage 1. Transitions the CPU:
;;;;   16-bit real mode → 32-bit protected mode → 64-bit long mode
;;;;
;;;; Page table layout (identity map first 2MB):
;;;;   0x1000 — PML4:  entry 0 → 0x2003 (PDPT, present+writable)
;;;;   0x2000 — PDPT:  entry 0 → 0x3003 (PD,   present+writable)
;;;;   0x3000 — PD:    entry 0 → 0x0083 (2MB huge page, PS+present+writable)
;;;;
;;;; Kernel entry: 0x100000

(in-package #:ecclesia)

(defparameter *stage2*
  '(;; ===== 16-bit real mode entry =====
    (bits 16)
    (org  #x8000)

    (cli)

    ;; Load GDT
    (lgdt (gdt-descriptor))

    ;; Enable protected mode: CR0.PE
    (mov  eax cr0)
    (or   eax #x01)
    (mov  cr0 eax)

    ;; Flush pipeline, enter 32-bit PM (selector 0x08 = code segment)
    (jmp  far #x0008 pm-entry)

    ;; ===== GDT =====
    (label gdt-start)
    (dq #x0000000000000000)       ; null
    (dq #x00af9a000000ffff)       ; 64-bit code: base=0, limit=max, L=1
    (dq #x00cf92000000ffff)       ; 64-bit data: base=0, limit=max
    (label gdt-end)

    ;; GDT descriptor
    (label gdt-descriptor)
    (dw (- gdt-end gdt-start 1))
    (dd gdt-start)

    ;; ===== 32-bit protected mode =====
    (bits 32)
    (label pm-entry)

    ;; Load data segment selectors
    (mov  ax #x0010)
    (mov  ds ax)
    (mov  es ax)
    (mov  fs ax)
    (mov  gs ax)
    (mov  ss ax)
    (mov  esp #x90000)

    ;; ── Build identity-mapped page tables ───────────────────────────────
    ;; Zero out 0x1000–0x3FFF (3 pages × 4096 bytes = 12288 bytes)
    (mov  edi #x1000)
    (xor  eax eax)
    (mov  ecx #x3000)             ; 12288 bytes / 4 = 3072 dwords
    (rep  stosd)                  ; memset to zero

    ;; PML4[0] → PDPT at 0x2000 (present + writable = 0x03)
    (mov  (mem32 #x1000) #x2003)

    ;; PDPT[0] → PD at 0x3000 (present + writable = 0x03)
    (mov  (mem32 #x2000) #x3003)

    ;; PD[0] → 2MB huge page at 0x000000 (PS=0x80 + present + writable = 0x83)
    (mov  (mem32 #x3000) #x0083)

    ;; ── Copy kernel from 0x20000 to 0x100000 ────────────────────────────
    ;; Stage 1 loaded 8 sectors (4096 bytes) of kernel at 0x20000.
    ;; We copy it to 0x100000 now (in 32-bit PM, full 4GB flat addressing).
    (mov  esi #x20000)       ; source
    (mov  edi #x100000)      ; destination
    (mov  ecx #x400)         ; 4096 / 4 = 1024 dwords
    (rep  movsd)

    ;; Load PML4 into CR3
    (mov  eax #x1000)
    (mov  cr3 eax)

    ;; Enable PAE (CR4.PAE = bit 5)
    (mov  eax cr4)
    (or   eax #x20)
    (mov  cr4 eax)

    ;; Set EFER.LME (MSR 0xC0000080, bit 8)
    (mov  ecx #xc0000080)
    (rdmsr)
    (or   eax #x100)
    (wrmsr)

    ;; Enable paging: CR0.PG (bit 31) + CR0.PE (bit 0)
    (mov  eax cr0)
    (or   eax #x80000001)
    (mov  cr0 eax)

    ;; Far jump to 64-bit long mode (selector 0x08 = 64-bit code)
    (jmp  far #x0008 lm-entry)

    ;; ===== 64-bit long mode =====
    (bits 64)
    (label lm-entry)

    ;; Set up 64-bit data segments
    (mov  ax #x0010)
    (mov  ds ax)
    (mov  es ax)
    (mov  ss ax)

    ;; ── Load 64-bit kernel from floppy sectors 6+ into 0x100000 ─────────
    ;; We're in 64-bit long mode now but INT 13h (BIOS) is gone.
    ;; We do this load in 32-bit PM BEFORE entering long mode.
    ;; (This block is placed before the far-jump to lm-entry)

    ;; Jump to kernel at 0x100000
    (jmp  abs #x100000)))

(defun stage2-size ()
  (length (assemble *stage2*)))
