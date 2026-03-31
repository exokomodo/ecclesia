;;;; test/main.lisp — 64-bit kernel unit tests

(defpackage #:ecclesia-test-kernel64
  (:use #:cl #:ecclesia #:ecclesia.build))
(in-package #:ecclesia-test-kernel64)

(defun assert= (expected actual description)
  (if (equal expected actual)
      (format t "  PASS  ~a~%" description)
      (progn
        (format t "  FAIL  ~a~%" description)
        (format t "        expected: ~a~%" expected)
        (format t "        actual:   ~a~%" actual)
        (error "Test failed: ~a" description))))

(defun run-tests ()
  (format t "~%Running kernel64 unit tests...~%~%")

  (let ((img (assemble *kernel64*)))

    (assert= t (> (length img) 0)
             "Kernel64 assembles to a non-empty image")

    (assert= t (<= (length img) (* 8 +floppy-sector-size+))
             "Kernel64 fits within 8 sectors (4096 bytes)")

    ;; Stub: just verify it assembles and halts
    (let ((hlt-pos (loop for i from 0 below (length img)
                         when (= (aref img i) #xf4) return i)))
      (assert= t (not (null hlt-pos))
               "Kernel64 stub contains HLT (0xF4)")))

  (format t "~%All kernel64 tests passed.~%"))

(run-tests)
