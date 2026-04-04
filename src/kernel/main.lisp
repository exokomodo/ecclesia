;;;; main.lisp — Ecclesia kernel entry (ECL-compiled)

(defun kernel-main ()
  ;; Stub: clear VGA, print banner, halt
  (vga-clear)
  (vga-write "Ecclesia" 0 0 +attr-cyan+)
  (vga-write "v0.1" 0 9 +attr-white+)
  (vga-write "Booted." 1 0 +attr-gray+)
  (loop (halt))) ; infinite halt loop