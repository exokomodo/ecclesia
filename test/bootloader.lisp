;;;; test/unit.lisp — Ecclesia unit tests

(defpackage #:ecclesia-test
  (:use #:cl
        #:ecclesia.assembler
        #:ecclesia.boot))
(in-package #:ecclesia-test)

(defun assert= (expected actual description)
  (if (equal expected actual)
      (format t "  PASS  ~a~%" description)
      (progn
        (format t "  FAIL  ~a~%" description)
        (format t "        expected: ~a~%" expected)
        (format t "        actual:   ~a~%" actual)
        (error "Test failed: ~a" description))))

(defun run-tests ()
  (format t "~%Running Ecclesia unit tests...~%~%")

  (let ((img (assemble *bootloader*)))

    (assert= 512 (length img)
             "Bootloader image is exactly 512 bytes")

    (assert= #x55 (aref img 510)
             "Byte 510 is 0x55 (boot signature low)")

    (assert= #xaa (aref img 511)
             "Byte 511 is 0xAA (boot signature high)")

    (assert= #xfa (aref img 0)
             "First byte is CLI (0xFA)")

    (let* ((msg-start +code-size+)
           (null-pos  (loop for i from msg-start below 512
                            when (= (aref img i) 0) return i)))
      (assert= t (not (null null-pos))
               "Boot message null terminator found in image")
      (assert= (+ msg-start (1- (length (boot-message-db-forms))))
               null-pos
               "Boot message null terminator at expected offset")))

  (format t "~%All tests passed.~%"))

(run-tests)
