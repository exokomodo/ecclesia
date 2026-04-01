;;;; stage2-aarch64.lisp — Stage 2 for AArch64 QEMU virt
;;;; This implements early UART initialization for input/output.

(in-package #:ecclesia.boot)

(defun *stage2-aarch64* ()
  `(;; Start of 64-bit AArch64 kernel sequence
    (bits 64)
    (org  #x40000000)

    ;; UART initialization — PL011 at 0x09000000
    (mov x0 #x09000000)              ; UART base
    ;; Write "Stage 2 start" via UART
    (mov x1 #'S) (strb x1 [x0, #0])  ; Transmit 'S'
    (mov x1 #'2) (strb x1 [x0, #0])  ; Transmit '2'
    (mov x1 #10) (strb x1 [x0, #0])  ; Transmit newline

    ;; Next: Jump to kernel entry at 0x40000000
    (br #x40000000)))

(defparameter *stage2-aarch64* (*stage2-aarch64*))