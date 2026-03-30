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

    ;; Stage 2 starts with CLI (0xFA)
    (assert= #xfa (aref img 0)
             "Stage 2 first byte is CLI (0xFA)")

    ;; LGDT instruction should appear: 0x0f 0x01
    (let ((lgdt-pos (loop for i from 0 below (- (length img) 1)
                          when (and (= (aref img i) #x0f)
                                    (= (aref img (1+ i)) #x01))
                          return i)))
      (assert= t (not (null lgdt-pos))
               "Stage 2 contains LGDT instruction (0x0F 0x01)")))

  (format t "~%All Stage 2 tests passed.~%"))

(run-tests)
