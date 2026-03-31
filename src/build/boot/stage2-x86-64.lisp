;;;; stage2-x86-64.lisp — Stage 2: 32-bit PM → 64-bit long mode, print status, halt
;;;;
;;;; Steps:
;;;;   1. Extend GDT with a 64-bit code segment (L=1)
;;;;   2. Write identity-mapped page tables into 0x1000–0x3FFF (16MB)
;;;;   3. Enable PAE, load CR3, set EFER.LME, enable paging
;;;;   4. Far jump to 64-bit code segment
;;;;   5. Print [  OK  ] status lines via vga-print.lisp helpers

(in-package #:ecclesia.build)

;;; Stage 2 is loaded from floppy sectors 2-9 (8 sectors = 4KB max)
(defconstant +floppy-sector-size+ 512)
(defconstant +stage2-sectors+     8)
(defconstant +stage2-size+        (* +stage2-sectors+ +floppy-sector-size+))

(defun page-table-forms ()
  "Write identity-mapped page tables in 32-bit PM.
   Maps first 16MB as 8 × 2MB huge pages — covers VGA at 0xB8000.
   PML4 @ 0x1000, PDPT @ 0x2000, PD @ 0x3000"
  `(;; Zero 3 pages (0x1000–0x3FFF)
    (mov  edi #x1000)
    (xor  eax eax)
    (mov  ecx #x0c00)
    (rep  stosd)

    ;; PML4[0] → PDPT at 0x2000
    (mov  (mem32 #x1000) #x2003)

    ;; PDPT[0] → PD at 0x3000
    (mov  (mem32 #x2000) #x3003)

    ;; PD entries 0-7: identity-map 8 × 2MB = 16MB (covers 0xB8000)
    (mov  (mem32 #x3000) #x000083)
    (mov  (mem32 #x3008) #x200083)
    (mov  (mem32 #x3010) #x400083)
    (mov  (mem32 #x3018) #x600083)
    (mov  (mem32 #x3020) #x800083)
    (mov  (mem32 #x3028) #xa00083)
    (mov  (mem32 #x3030) #xc00083)
    (mov  (mem32 #x3038) #xe00083)))

(defun long-mode-entry-forms ()
  "Enable PAE, load CR3, set EFER.LME, enable paging, then far jump to 64-bit."
  `(;; ── Copy kernel from 0x20000 → 0x100000 (in 32-bit PM, full addressing) ──
    ;; Stage 1 loaded 8 sectors (4096 bytes) at physical 0x20000.
    (mov  esi #x20000)
    (mov  edi #x100000)
    (mov  ecx #x400)        ; 4096 / 4 = 1024 dwords
    (rep  movsd)

    ;; Enable PAE (CR4 bit 5)
    (mov  eax cr4)
    (or   eax #x20)
    (mov  cr4 eax)

    ;; Load PML4 into CR3
    (mov  eax #x1000)
    (mov  cr3 eax)

    ;; Set EFER.LME (MSR 0xC0000080 bit 8)
    (mov  ecx #xc0000080)
    (rdmsr)
    (or   eax #x100)
    (wrmsr)

    ;; Enable paging: CR0.PG (bit 31) — activates long mode
    (mov  eax cr0)
    (or   eax #x80000000)
    (mov  cr0 eax)

    ;; Row 3: confirm paging enabled (before far jump, still in 32-bit PM)
    ,@(vga-status "PAE + EFER.LME + paging enabled" :row 3)

    ;; Far jump to 64-bit code segment (selector 0x18 = GDT entry 3)
    (jmp  far #x0018 lm-entry)))

(defparameter *stage2*
  `(;; ===== 16-bit real mode =====
    (bits 16)
    (org  #x8000)

    (cli)
    (lgdt (gdt-ptr))

    ;; Enable protected mode
    (mov  eax cr0)
    (or   eax #x01)
    (mov  cr0 eax)

    ;; Far jump to 32-bit PM (selector 0x08)
    (jmp  far #x0008 pm-entry)

    ;; ── GDT ──────────────────────────────────────────────────────────────
    (label gdt-start)
    (dq #x0000000000000000)       ; 0x00: null
    (dq #x00cf9a000000ffff)       ; 0x08: 32-bit code (D=1)
    (dq #x00cf92000000ffff)       ; 0x10: 32-bit data
    (dq #x00af9a000000ffff)       ; 0x18: 64-bit code (L=1)
    (label gdt-end)

    (label gdt-ptr)
    (dw (- gdt-end gdt-start 1))
    (dd gdt-start)

    ;; ===== 32-bit protected mode =====
    (bits 32)
    (label pm-entry)

    (mov  ax #x0010)
    (mov  ds ax)
    (mov  es ax)
    (mov  fs ax)
    (mov  gs ax)
    (mov  ss ax)
    (mov  esp #x90000)

    ;; Clear screen
    ,@(vga-clear-forms)

    ;; Row 0: header
    ,@(vga-write "Ecclesia OS" :row 0 :col 0 :attr #x0e)

    ;; Row 1: protected mode confirmed
    ,@(vga-status "Entered 32-bit protected mode" :row 1)

    ;; Row 2: page tables
    ,@(page-table-forms)
    ,@(vga-status "Identity-mapped page tables (16MB)" :row 2)

    ;; Enter long mode (prints row 3, then far jumps)
    ,@(long-mode-entry-forms)

    ;; ===== 64-bit long mode =====
    (bits 64)
    (label lm-entry)

    ;; Load VGA base into RDI for all 64-bit VGA writes
    (mov  rdi #xb8000)

    (mov  ax #x0010)
    (mov  ds ax)
    (mov  es ax)
    (mov  ss ax)

    ;; Row 4: long mode confirmed
    ,@(vga-rdi-status "Entered 64-bit long mode" :row 4)

    ;; Halt
    (hlt)))

(defun stage2-size ()
  (length (assemble *stage2*)))
