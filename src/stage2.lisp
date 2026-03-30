;;;; stage2.lisp — Stage 2: enter 32-bit protected mode, write to VGA, halt
;;;;
;;;; Atomic goal: confirm protected mode works by writing directly to the
;;;; VGA text buffer at 0xB8000. No BIOS, no long mode, no page tables.
;;;;
;;;; If QEMU shows "Protected mode OK" in white text, this step is done.

(in-package #:ecclesia)

(defparameter *pm-message* "Protected mode OK")

(defun vga-clear-forms ()
  "Return assembly forms to clear the VGA text screen (80×25, grey on black)."
  '((mov  edi #xb8000)
    (mov  eax #x07200720)   ; two cells: space + grey attr
    (mov  ecx #x03e8)       ; 1000 dwords = 2000 cells
    (rep  stosd)))

(defun pm-vga-forms (str)
  "Write STR to VGA at row 0 col 0 (0xB8000), white on black (attr 0x0F).
   Uses (mem32 addr) form — valid in 32-bit PM with flat addressing."
  (loop for ch across str
        for i from 0
        for addr = (+ #xb8000 (* 2 i))
        collect `(mov (mem32 ,addr) ,(logior (char-code ch) #x0f00))))

(defparameter *stage2*
  `(;; ===== 16-bit real mode =====
    (bits 16)
    (org  #x8000)

    (cli)

    ;; Load GDT
    (lgdt (gdt-ptr))

    ;; Set CR0.PE
    (mov  eax cr0)
    (or   eax #x01)
    (mov  cr0 eax)

    ;; Far jump to flush pipeline and enter 32-bit PM
    ;; Selector 0x08 = GDT entry 1 (32-bit code)
    (jmp  far #x0008 pm-entry)

    ;; ── GDT ──────────────────────────────────────────────────────────────
    (label gdt-start)
    (dq #x0000000000000000)       ; null
    ;; 32-bit code: base=0, limit=4GB, G=1, D=1(32-bit), P=1, DPL=0, type=0xA
    (dq #x00cf9a000000ffff)
    ;; 32-bit data: base=0, limit=4GB, G=1, D=1, P=1, DPL=0, type=0x2
    (dq #x00cf92000000ffff)
    (label gdt-end)

    ;; GDT pointer: limit (2 bytes) + base (4 bytes)
    (label gdt-ptr)
    (dw (- gdt-end gdt-start 1))
    (dd gdt-start)

    ;; ===== 32-bit protected mode =====
    (bits 32)
    (label pm-entry)

    ;; Load data segment selectors (0x10 = GDT entry 2)
    (mov  ax #x0010)
    (mov  ds ax)
    (mov  es ax)
    (mov  fs ax)
    (mov  gs ax)
    (mov  ss ax)
    (mov  esp #x90000)

    ;; Clear screen
    ,@(vga-clear-forms)

    ;; Write "Protected mode OK" to VGA text buffer
    ,@(pm-vga-forms *pm-message*)

    ;; Done
    (hlt)))

(defun stage2-size ()
  (length (assemble *stage2*)))
