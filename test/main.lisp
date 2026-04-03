;;;; test/main.lisp — Stage 2 ELF loader integration tests
;;;;
;;;; Now that Stage 2 *is* the kernel (no separate kernel binary),
;;;; we verify that the assembled Stage 2 image contains the expected
;;;; ELF loader machinery.

(defpackage #:ecclesia-test-kernel
  (:use #:cl
        #:ecclesia
        #:ecclesia.assembler
        #:ecclesia.boot))
(in-package #:ecclesia-test-kernel)

(defun assert= (expected actual description)
  (if (equal expected actual)
      (format t "  PASS  ~a~%" description)
      (progn
        (format t "  FAIL  ~a~%" description)
        (format t "        expected: ~a~%" expected)
        (format t "        actual:   ~a~%" actual)
        (error "Test failed: ~a" description))))

(defun run-tests ()
  (format t "~%Running kernel unit tests...~%~%")

  ;; Stage 2 contains the ELF loader — verify it assembles and is bounded
  (let ((img (assemble *stage2*)))

    (assert= t (> (length img) 0)
             "Stage 2 + ELF loader assembles to a non-empty image")

    (assert= t (<= (length img) (* 8 +floppy-sector-size+))
             "Stage 2 + ELF loader fits within 8 sectors (4096 bytes)")

    ;; CLI (0xFA) — Stage 2 starts with interrupt disable
    (assert= #xfa (aref img 0)
             "Stage 2 first byte is CLI (0xFA)")

    ;; REP MOVSD (0xF3 0xA5) — segment copy for ELF loading
    (let ((rep-pos (loop for i from 0 below (- (length img) 1)
                         when (and (= (aref img i) #xf3)
                                   (= (aref img (1+ i)) #xa5))
                         return i)))
      (assert= t (not (null rep-pos))
               "Stage 2 contains REP MOVSD (0xF3 0xA5) for ELF segment copy"))

    ;; HLT (0xF4) — ELF bad-magic path halts
    (let ((hlt-pos (loop for i from 0 below (length img)
                         when (= (aref img i) #xf4) return i)))
      (assert= t (not (null hlt-pos))
               "Stage 2 contains HLT (0xF4) for bad-ELF halt")))

  (format t "~%All kernel tests passed.~%"))

(run-tests)
