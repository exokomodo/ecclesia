;;; boot.lisp — Ecclesia bare-metal entry point
;;;
;;; This file is loaded by the SBCL bare-metal runtime immediately after
;;; the assembly stub hands off control. It initializes the kernel
;;; environment and drops into the REPL shell.

;;; Disable the default SBCL interactive debugger — we have no terminal
;;; infrastructure yet, so any unhandled condition should halt cleanly.
(setf *debugger-hook*
      (lambda (condition hook)
        (declare (ignore hook))
        (format t "~&FATAL: ~A~%" condition)
        ;; Halt — we'll replace this with a proper panic routine later
        (loop)))

;;; Print the Ecclesia banner
(defun print-banner ()
  (format t "~&~%")
  (format t "  ███████  ██████ ██      ███████ ███████ ██  █████  ~%")
  (format t "  ██      ██      ██      ██      ██      ██ ██   ██ ~%")
  (format t "  █████   ██      ██      █████   ███████ ██ ███████ ~%")
  (format t "  ██      ██      ██      ██           ██ ██ ██   ██ ~%")
  (format t "  ███████  ██████ ███████ ███████ ███████ ██ ██   ██ ~%")
  (format t "~%  Ecclesia OS — Common Lisp Microkernel~%")
  (format t "  Built on SBCL ~A~%~%" (lisp-implementation-version)))

;;; Kernel main entry point
(defun kernel-main ()
  (print-banner)
  (format t "Entering REPL...~%~%")
  ;; Drop into the standard SBCL REPL as the initial shell
  (sb-impl::toplevel-repl nil))

;;; Boot
(kernel-main)
