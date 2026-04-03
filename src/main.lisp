;;;; main.lisp — Ecclesia bootstrap wiring
;;;;
;;;; All modules are now loaded. This file:
;;;;   1. Builds *stage2* by injecting the ELF loader forms into the Stage 2 template
;;;;   2. Exports *kernel-main* as nil (no separate kernel binary — Stage 2 is it)

(in-package #:ecclesia)

;;; ── Wire up Stage 2 with the ELF loader ─────────────────────────────────────
;;;
;;; stage2-x86_64.lisp defines build-stage2 which accepts a list of asm forms
;;; to inline at the long-mode entry point. We supply the ELF loader forms here
;;; now that both the kernel ISA class and the loader are fully defined.

(setf ecclesia.boot:*stage2*
      (ecclesia.boot:build-stage2
       (ecclesia.loader:load-elf-forms
        (make-instance 'ecclesia.kernel.x86_64:x86_64)
        #x300000)))

;;; ── *kernel-main* — no longer used ──────────────────────────────────────────
;;;
;;; There is no separate kernel binary. Stage 2 is the complete bootstrap;
;;; it loads the ELF and jumps directly to _start.
;;; *kernel-main* is kept as nil so existing references don't break.

(defparameter *kernel-main* nil)
(defun make-kernel-main (&optional isa) (declare (ignore isa)) nil)
