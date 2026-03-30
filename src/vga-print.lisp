;;;; vga-print.lisp — VGA text buffer helpers
;;;;
;;;; Two flavours:
;;;;   pm-vga-*   — 32-bit PM (MOV [abs], imm32 via (mem32 addr))
;;;;   lm-vga-*   — 64-bit long mode (MOV WORD PTR [RDI+off], imm16 via mov-rdi-word)
;;;;
;;;; Both emit lists of assembly forms for splicing into instruction sequences.
;;;;
;;;; VGA text mode: 80×25, each cell = 2 bytes (low=char, high=attr).
;;;; Attributes: 0x0f=white, 0x07=grey, 0x0a=green, 0x0c=red, 0x0e=yellow, 0x08=dark grey.

(in-package #:ecclesia)

(defconstant +vga-base+  #xb8000)
(defconstant +vga-cols+  80)

;;; ── Shared helpers ──────────────────────────────────────────────────────────

(defun vga-addr (row col)
  "Linear address of VGA cell (ROW, COL)."
  (+ +vga-base+ (* 2 (+ (* row +vga-cols+) col))))

(defun vga-offset (row col)
  "Byte offset from VGA base for cell (ROW, COL)."
  (* 2 (+ (* row +vga-cols+) col)))

(defun vga-cell (char attr)
  "16-bit cell value: attr in high byte, char in low byte."
  (logior (logand char #xff) (ash (logand attr #xff) 8)))

;;; ── 32-bit PM writes ────────────────────────────────────────────────────────

(defun pm-vga-forms (str &key (row 0) (col 0) (attr #x0f))
  "Emit forms to write STR to VGA at (ROW, COL) with ATTR.
   Uses (mem32 addr) — safe in 32-bit protected mode."
  (loop for ch across str
        for c from col
        collect `(mov (mem32 ,(vga-addr row c))
                      ,(vga-cell (char-code ch) attr))))

(defun pm-vga-status-forms (msg &key (row 0) (ok t))
  "Emit a Linux-style status line at ROW:
     [  OK  ] msg     attr: dark-grey brackets, green/red status, grey message"
  (let ((status    (if ok "  OK  " " FAIL "))
        (ok-attr   #x0a)
        (fail-attr #x0c)
        (dim-attr  #x08)
        (msg-attr  #x07))
    (append
     (pm-vga-forms "["      :row row :col 0 :attr dim-attr)
     (pm-vga-forms status   :row row :col 1 :attr (if ok ok-attr fail-attr))
     (pm-vga-forms "]"      :row row :col 7 :attr dim-attr)
     (pm-vga-forms (concatenate 'string " " msg) :row row :col 8 :attr msg-attr))))

;;; ── Screen clear (32-bit PM) ────────────────────────────────────────────────

(defun vga-clear-forms ()
  "Emit forms to clear the VGA screen (80×25 cells, grey on black).
   Uses REP STOSD — EDI must not be relied on after this."
  '((mov  edi #xb8000)
    (mov  eax #x07200720)   ; two cells: space + grey attr
    (mov  ecx #x03e8)       ; 1000 dwords = 2000 cells
    (rep  stosd)))

;;; ── 64-bit long mode writes ─────────────────────────────────────────────────
;;;
;;; In 64-bit mode, (mem32 addr) uses RIP-relative addressing.
;;; Instead we load VGA base into RDI and use mov-rdi-word for all writes.
;;; Caller must ensure RDI = +vga-base+ before using these.

(defun lm-vga-forms (str &key (row 0) (col 0) (attr #x0f))
  "Emit forms to write STR to VGA at (ROW, COL) with ATTR.
   Uses (mov-rdi-word offset word) — requires RDI = +vga-base+."
  (loop for ch across str
        for c from col
        collect `(mov-rdi-word ,(vga-offset row c)
                               ,(vga-cell (char-code ch) attr))))

(defun lm-vga-status-forms (msg &key (row 0) (ok t))
  "Emit a Linux-style status line at ROW in 64-bit mode.
   Requires RDI = +vga-base+."
  (let ((status    (if ok "  OK  " " FAIL "))
        (ok-attr   #x0a)
        (fail-attr #x0c)
        (dim-attr  #x08)
        (msg-attr  #x07))
    (append
     (lm-vga-forms "["      :row row :col 0 :attr dim-attr)
     (lm-vga-forms status   :row row :col 1 :attr (if ok ok-attr fail-attr))
     (lm-vga-forms "]"      :row row :col 7 :attr dim-attr)
     (lm-vga-forms (concatenate 'string " " msg) :row row :col 8 :attr msg-attr))))
