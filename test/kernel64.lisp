;;;; test/kernel64.lisp — 64-bit kernel unit tests

(defpackage #:ecclesia-test-kernel64
  (:use #:cl #:ecclesia))
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

    ;; REX.W prefix (0x48) for MOV RSP should appear near start
    (assert= #x48 (aref img 0)
             "First byte is REX.W prefix (MOV RSP, imm64)")

    ;; REP STOSD (0xF3 0xAB) for screen clear should be present
    (let ((rep-pos (loop for i from 0 below (- (length img) 1)
                         when (and (= (aref img i) #xf3)
                                   (= (aref img (1+ i)) #xab))
                         return i)))
      (assert= t (not (null rep-pos))
               "Kernel64 contains REP STOSD (0xF3 0xAB) for screen clear"))

    ;; IN AL, port (0xe4) for keyboard polling should be present
    (let ((in-pos (loop for i from 0 below (length img)
                        when (= (aref img i) #xe4)
                        return i)))
      (assert= t (not (null in-pos))
               "Kernel64 contains IN AL instruction (0xE4) for keyboard")))

  (format t "~%All kernel64 tests passed.~%"))

(run-tests)
