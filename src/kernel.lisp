;;;; kernel.lisp — Ecclesia kernel entry point
;;;;
;;;; write-kernel assembles Stage 1 (MBR) and Stage 2, then writes
;;;; both into a floppy image:
;;;;   Bytes 0-511:    Stage 1 MBR
;;;;   Bytes 512-2047: Stage 2 (4 sectors × 512 bytes)

(in-package #:ecclesia)

(defconstant +floppy-sector-size+ 512)
(defconstant +stage2-sectors+     4)
(defconstant +stage2-size+        (* +stage2-sectors+ +floppy-sector-size+))

(defun write-kernel (output-path)
  "Assemble Ecclesia and write a bootable floppy image to OUTPUT-PATH."
  (format t "[ecclesia] Assembling Stage 1 (MBR)...~%")
  (let ((stage1 (assemble *bootloader*)))
    (unless (= (length stage1) +floppy-sector-size+)
      (error "Stage 1 must be exactly ~d bytes, got ~d"
             +floppy-sector-size+ (length stage1)))

    (format t "[ecclesia] Assembling Stage 2...~%")
    (let ((stage2 (assemble *stage2*)))
      (when (> (length stage2) +stage2-size+)
        (error "Stage 2 too large: ~d bytes (max ~d)"
               (length stage2) +stage2-size+))

      (format t "[ecclesia] Writing floppy image (~d bytes)...~%"
              (+ +floppy-sector-size+ +stage2-size+))

      (with-open-file (out output-path
                           :direction :output
                           :element-type '(unsigned-byte 8)
                           :if-exists :supersede)
        ;; Sector 1: Stage 1 MBR
        (write-sequence stage1 out)
        ;; Sectors 2-5: Stage 2 (padded to +stage2-size+)
        (write-sequence stage2 out)
        (loop repeat (- +stage2-size+ (length stage2))
              do (write-byte 0 out)))

      (format t "[ecclesia] Done. Stage1=~d Stage2=~d Total=~d bytes~%"
              (length stage1) (length stage2)
              (+ +floppy-sector-size+ +stage2-size+)))))
