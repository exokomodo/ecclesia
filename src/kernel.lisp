;;;; kernel.lisp — Ecclesia kernel entry point
;;;;
;;;; write-kernel assembles the bootloader and kernel image,
;;;; then writes the result to a floppy image file.

(in-package #:ecclesia)

(defun write-kernel (output-path)
  "Assemble Ecclesia and write a bootable floppy image to OUTPUT-PATH."
  (format t "[ecclesia] Assembling kernel...~%")
  (let ((image (assemble *bootloader*)))
    (with-open-file (out output-path
                         :direction :output
                         :element-type '(unsigned-byte 8)
                         :if-exists :supersede)
      (write-sequence image out))
    (format t "[ecclesia] Written ~a bytes to ~a~%" (length image) output-path)))
