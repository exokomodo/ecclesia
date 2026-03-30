;;;; test/stage2.lisp — Stage 2 assembler unit tests

(defpackage #:ecclesia-test-stage2
  (:use #:cl #:ecclesia))
(in-package #:ecclesia-test-stage2)

(defun assert= (expected actual description)
  (if (equal expected actual)
      (format t "  PASS  ~a~%" description)
      (progn
        (format t "  FAIL  ~a~%" description)
        (format t "        expected: ~a~%" expected)
        (format t "        actual:   ~a~%" actual)
        (error "Test failed: ~a" description))))

(defun run-tests ()
  (format t "~%Running Stage 2 unit tests...~%~%")

  (let ((img (assemble *stage2*)))

    (assert= t (> (length img) 0)
             "Stage 2 assembles to a non-empty image")

    (assert= t (<= (length img) +stage2-size+)
             "Stage 2 fits within 4 sectors (2048 bytes)")

    ;; Stage 2 starts with MOV SI, imm16 (0xBE)
    (assert= #xbe (aref img 0)
             "Stage 2 first byte is MOV SI (0xBE)")

    ;; HLT (0xF4) should appear — Stage 2 halts after printing
    (let ((hlt-pos (loop for i from 0 below (length img)
                         when (= (aref img i) #xf4) return i)))
      (assert= t (not (null hlt-pos))
               "Stage 2 contains HLT (0xF4)")))

  (format t "~%All Stage 2 tests passed.~%"))

(run-tests)
