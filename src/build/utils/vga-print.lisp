;;;; vga-print.lisp — VGA text buffer helpers
;;;;
;;;; Two addressing flavours:
;;;;   vga-*        — absolute writes via (mem32 addr), safe in 16/32-bit mode
;;;;   vga-rdi-*    — RDI-relative writes via mov-rdi-word, required in 64-bit mode
;;;;                  (caller must set RDI = +vga-base+ before use)
;;;;
;;;; VGA text mode: 80×25, each cell = 2 bytes (low=char, high=attr).
;;;; Common attributes:
;;;;   #x0f  white on black      #x07  grey on black
;;;;   #x0a  bright green        #x0c  bright red
;;;;   #x0e  yellow              #x08  dark grey

(in-package #:ecclesia.build)

(defconstant +vga-base+ #xb8000)
(defconstant +vga-cols+ 80)

;;; ── Shared primitives ───────────────────────────────────────────────────────

(defun vga-addr (row col)
  "Absolute VGA memory address for cell (ROW, COL)."
  (+ +vga-base+ (* 2 (+ (* row +vga-cols+) col))))

(defun vga-offset (row col)
  "Byte offset from +vga-base+ for cell (ROW, COL)."
  (* 2 (+ (* row +vga-cols+) col)))

(defun vga-cell (char attr)
  "16-bit VGA cell value: ATTR in high byte, CHAR in low byte."
  (logior (logand char #xff) (ash (logand attr #xff) 8)))

;;; ── Screen clear ────────────────────────────────────────────────────────────

(defun vga-clear-forms ()
  "Emit forms to clear the VGA screen (80×25, grey on black) via REP STOSD.
   EDI is not preserved after this call."
  '((mov  edi #xb8000)
    (mov  eax #x07200720)   ; two cells: space + grey attr
    (mov  ecx #x03e8)       ; 1000 dwords = 2000 cells
    (rep  stosd)))

;;; ── Absolute writes (16/32-bit mode) ────────────────────────────────────────

(defun vga-write (str &key (row 0) (col 0) (attr #x0f))
  "Emit forms to write STR at (ROW, COL) with ATTR.
   Uses (mem32 addr) — absolute addressing, safe in 16/32-bit mode."
  (loop for ch across str
        for c from col
        collect `(mov (mem32 ,(vga-addr row c))
                      ,(vga-cell (char-code ch) attr))))

(defun vga-status (msg &key (row 0) (ok t))
  "Emit a Linux-style status line at ROW using absolute addressing:
     [  OK  ] msg    or    [ FAIL ] msg"
  (append
   (vga-write "["     :row row :col 0 :attr #x08)
   (vga-write (if ok "  OK  " " FAIL ")
              :row row :col 1 :attr (if ok #x0a #x0c))
   (vga-write "]"     :row row :col 7 :attr #x08)
   (vga-write (concatenate 'string " " msg)
              :row row :col 8 :attr #x07)))

;;; ── RDI-relative writes (64-bit mode) ───────────────────────────────────────

(defun vga-rdi-write (str &key (row 0) (col 0) (attr #x0f))
  "Emit forms to write STR at (ROW, COL) with ATTR.
   Uses (mov-rdi-word offset word) — requires RDI = +vga-base+."
  (loop for ch across str
        for c from col
        collect `(mov-rdi-word ,(vga-offset row c)
                               ,(vga-cell (char-code ch) attr))))

(defun vga-rdi-status (msg &key (row 0) (ok t))
  "Emit a Linux-style status line at ROW using RDI-relative addressing.
   Requires RDI = +vga-base+."
  (append
   (vga-rdi-write "["     :row row :col 0 :attr #x08)
   (vga-rdi-write (if ok "  OK  " " FAIL ")
                  :row row :col 1 :attr (if ok #x0a #x0c))
   (vga-rdi-write "]"     :row row :col 7 :attr #x08)
   (vga-rdi-write (concatenate 'string " " msg)
                  :row row :col 8 :attr #x07)))
