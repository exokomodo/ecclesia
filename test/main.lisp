;;;; test/main.lisp — kernel unit tests

(defpackage #:ecclesia-test-kernel
  (:use #:cl
        #:ecclesia
        #:ecclesia.assembler
        ; #:ecclesia.build
        ))
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

  (let ((img (assemble *kernel-main*)))

    (assert= t (> (length img) 0)
             "Kernel assembles to a non-empty image")

    (assert= t (<= (length img) (* 8 +floppy-sector-size+))
             "Kernel fits within 8 sectors (4096 bytes)")

    ;; REX.W prefix (0x48) should appear (MOV RSP, imm64)
    (assert= #x48 (aref img 0)
             "Kernel first byte is REX.W prefix (MOV RSP)")

    ;; IN AL opcode (0xE4) should appear (PS/2 keyboard polling)
    (let ((in-pos (loop for i from 0 below (length img)
                        when (= (aref img i) #xe4) return i)))
      (assert= t (not (null in-pos))
               "Kernel contains IN AL (0xE4) for keyboard polling"))

    ;; Scancode table should be present (contains ASCII 113='q' at index 0x10)
    ;; 113 = 0x71
    (let ((q-pos (loop for i from 0 below (- (length img) 1)
                       when (and (= (aref img i) 113)     ; 'q'
                                 (= (aref img (1+ i)) 119)) ; 'w' follows
                       return i)))
      (assert= t (not (null q-pos))
               "Kernel contains scancode→ASCII table (q/w at consecutive offsets)")))

  (format t "~%All kernel tests passed.~%"))

(run-tests)
