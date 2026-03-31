;;;; stage2-x86_base.lisp — Shared Stage 2 code for all x86 targets
;;;;
;;;; These functions emit the boot steps that are identical regardless
;;;; of whether the final target is 32-bit or 64-bit.

(in-package #:ecclesia.boot)

(defun real-mode-init-forms ()
  "16-bit real mode initialisation: disable interrupts, zero segment
   registers, set stack pointer."
  '((cli)
    (xor  ax ax)
    (mov  ds ax)
    (mov  es ax)
    (mov  ss ax)
    (mov  sp #x7c00)))

(defun a20-enable-forms ()
  "Enable the A20 line via port 0x92 (fast A20)."
  '((in   al #x92)
    (or   al #x02)
    (out  #x92 al)))

(defun enter-protected-mode-forms ()
  "Set CR0.PE and issue a far jump to flush the prefetch queue.
   Assumes a GDT has already been loaded with:
     selector 0x08 = 32-bit code segment
   The far jump target label must be PM-ENTRY, defined after this block."
  '(;; Set CR0.PE
    (mov  eax cr0)
    (or   eax #x01)
    (mov  cr0 eax)
    ;; Far jump → 32-bit protected mode
    (jmp  far #x08 pm-entry)))

(defun setup-pm-segments-forms (&optional (stack-top #x90000))
  "Set all data/stack segment registers to the flat 32-bit data selector
   (0x10) and initialise ESP."
  `((mov  ax #x10)
    (mov  ds ax)
    (mov  es ax)
    (mov  fs ax)
    (mov  gs ax)
    (mov  ss ax)
    (mov  esp ,stack-top)))
