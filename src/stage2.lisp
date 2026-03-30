;;;; stage2.lisp — Stage 2: 32-bit PM → 64-bit long mode, write to VGA, halt
;;;;
;;;; Atomic goal: confirm long mode works by writing "Long mode OK" to VGA.
;;;;
;;;; Steps added over the previous PR:
;;;;   1. Extend GDT with a 64-bit code segment (L=1)
;;;;   2. Write identity-mapped page tables into 0x1000–0x3FFF
;;;;   3. Enable PAE, load CR3, set EFER.LME, enable paging
;;;;   4. Far jump to 64-bit code segment
;;;;   5. Write "Long mode OK" to VGA from 64-bit code

(in-package #:ecclesia)

(defparameter *lm-message* "Long mode OK")

(defun vga-clear-forms ()
  "Return assembly forms to clear the VGA screen (80×25, grey on black)."
  '((mov  edi #xb8000)
    (mov  eax #x07200720)
    (mov  ecx #x03e8)
    (rep  stosd)))

(defun pm-vga-forms (str &key (row 0) (col 0) (attr #x0f))
  "Write STR to VGA at (ROW, COL) with ATTR. Safe in 32-bit PM."
  (loop for ch across str
        for c from col
        for addr = (+ #xb8000 (* 2 (+ (* row 80) c)))
        collect `(mov (mem32 ,addr) ,(logior (char-code ch) (ash attr 8)))))

(defun page-table-forms ()
  "Write minimal identity-mapped page tables in 32-bit PM.
   PML4 @ 0x1000, PDPT @ 0x2000, PD @ 0x3000 (2MB huge page)."
  `(;; Zero 3 pages (0x1000–0x3FFF = 12288 bytes = 3072 dwords)
    (mov  edi #x1000)
    (xor  eax eax)
    (mov  ecx #x0c00)
    (rep  stosd)

    ;; PML4[0] → PDPT at 0x2000 (present + writable)
    (mov  (mem32 #x1000) #x2003)

    ;; PDPT[0] → PD at 0x3000 (present + writable)
    (mov  (mem32 #x2000) #x3003)

    ;; PD[0] → 2MB huge page at 0x000000 (PS=0x80 + present + writable)
    (mov  (mem32 #x3000) #x0083)))

(defun long-mode-entry-forms ()
  "Enable PAE, load CR3, set EFER.LME, enable paging."
  `(;; Enable PAE (CR4 bit 5)
    (mov  eax cr4)
    (or   eax #x20)
    (mov  cr4 eax)
    (mov  (mem32 #xb8006) #x0b31)   ; checkpoint '1' = PAE done

    ;; Load PML4 into CR3
    (mov  eax #x1000)
    (mov  cr3 eax)
    (mov  (mem32 #xb8008) #x0b32)   ; checkpoint '2' = CR3 done

    ;; Set EFER.LME (MSR 0xC0000080 bit 8)
    (mov  ecx #xc0000080)
    (rdmsr)
    (or   eax #x100)
    (wrmsr)
    (mov  (mem32 #xb800a) #x0b33)   ; checkpoint '3' = EFER done

    ;; Enable paging: CR0.PG (bit 31) — activates long mode
    (mov  eax cr0)
    (or   eax #x80000000)
    (mov  cr0 eax)
    (mov  (mem32 #xb800c) #x0b34)   ; checkpoint '4' = paging done

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

    (mov  ax #x0010)              ; 32-bit data selector
    (mov  ds ax)
    (mov  es ax)
    (mov  fs ax)
    (mov  gs ax)
    (mov  ss ax)
    (mov  esp #x90000)

    ;; Clear screen
    ,@(vga-clear-forms)

    ;; Checkpoint A: PM entry confirmed (cyan 'A' at col 0)
    (mov (mem32 #xb8000) #x0b41)

    ;; Build page tables
    ,@(page-table-forms)

    ;; Checkpoint B: page tables written (cyan 'B' at col 1)
    (mov (mem32 #xb8002) #x0b42)

    ;; Enter long mode
    ,@(long-mode-entry-forms)

    ;; Checkpoint C: after CR0.PG set (cyan 'C' at col 2) — only if we don't fault
    (mov (mem32 #xb8004) #x0b43)

    ;; ===== 64-bit long mode =====
    (bits 64)
    (label lm-entry)

    ;; Load VGA base so mov-rdi-word works correctly
    (mov  rdi #xb8000)

    ;; Checkpoint E: landed in lm-entry
    (mov-rdi-word 14 #x0b45)      ; 'E' at VGA col 7

    (mov  ax #x0010)
    (mov  ds ax)
    (mov  es ax)
    (mov  ss ax)

    ;; Checkpoint F: past segment setup
    (mov-rdi-word 16 #x0b46)      ; 'F' at VGA col 8

    ;; Write "Long mode OK" to VGA
    ,@(pm-vga-forms *lm-message* :row 0 :col 0 :attr #x0a)  ; bright green

    ;; Halt
    (hlt)))

(defun stage2-size ()
  (length (assemble *stage2*)))
