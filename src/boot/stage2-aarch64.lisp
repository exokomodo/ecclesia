;;;; stage2-aarch64.lisp — Stage 2 for AArch64 QEMU virt
;;;; This implements early UART initialization for input/output.

(in-package #:ecclesia.boot)

(defun *stage2-aarch64* ()
  `(;; Start of 64-bit AArch64 kernel sequence
    (bits 64)
    (org  #x40000000)

    ;; UART initialization — PL011 at 0x09000000
    (movx x0 #x09000000)              ; x0 = UART base
    ;; Print "Stage2\n" via UART to confirm Stage 2 is alive
    (movx x1 83)  (strb w1 (mem x0))  ; 'S'
    (movx x1 116) (strb w1 (mem x0))  ; 't'
    (movx x1 97)  (strb w1 (mem x0))  ; 'a'
    (movx x1 103) (strb w1 (mem x0))  ; 'g'
    (movx x1 101) (strb w1 (mem x0))  ; 'e'
    (movx x1 50)  (strb w1 (mem x0))  ; '2'
    (movx x1 10)  (strb w1 (mem x0))  ; newline

    ;; Jump to kernel entry at 0x40000000
    (movx x9 #x40000000)
    (br x9)))

(defparameter *stage2-aarch64* (*stage2-aarch64*))