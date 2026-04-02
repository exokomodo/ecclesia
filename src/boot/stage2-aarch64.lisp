;;;; stage2-aarch64.lisp — Stage 2 for AArch64 QEMU virt
;;;; This implements early UART initialization for input/output.

(in-package #:ecclesia.boot)

(defun *stage2-aarch64* ()
  `(;; Start of 64-bit AArch64 kernel sequence
    (bits 64)
    (org  #x40000000)

    ;; Jump to kernel entry at 0x40000000
    (movx x9 #x40000000)
    (br x9)))

(defparameter *stage2-aarch64* (*stage2-aarch64*))