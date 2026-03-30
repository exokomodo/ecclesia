;;;; assembler.lisp — Stub x86-64 assembler
;;;;
;;;; Emits a flat binary image from Lisp s-expression assembly.
;;;; Inspired by yalo's cross-compiler (cc package).
;;;; This stub will be fleshed out into a full x86-64 assembler in CL.

(in-package #:ecclesia)

(defun emit-bytes (stream &rest bytes)
  "Write raw bytes to STREAM."
  (dolist (b bytes)
    (write-byte b stream)))

(defun assemble (instructions)
  "Assemble a list of s-expression instructions into a byte vector.
   Currently a stub — returns an empty byte array."
  (declare (ignore instructions))
  (make-array 0 :element-type '(unsigned-byte 8)))
