;;;; kernel.lisp — Ecclesia floppy image writer
;;;;
;;;; Assembles Stage 1 (MBR), Stage 2, and the 64-bit kernel, then
;;;; writes them into a single floppy image:
;;;;
;;;;   Sector 1   (0x0000): Stage 1 MBR            (512 bytes)
;;;;   Sectors 2-5 (0x0200): Stage 2                (4 × 512 = 2048 bytes)
;;;;   Sectors 6+  (0x0A00): 64-bit kernel          (padded to sector boundary)
;;;;
;;;; Stage 1 loads sectors 2-5 into 0x8000 (Stage 2).
;;;; Stage 2 is responsible for loading the kernel from sectors 6+ into
;;;; 0x100000. For now Stage 2 doesn't load the kernel — we embed it in
;;;; the image and let QEMU map it directly via -kernel or our own loader.
;;;; NOTE: actual INT 13h kernel loading will be added in the next PR.

(in-package #:ecclesia)

(defconstant +floppy-sector-size+ 512)
(defconstant +stage2-sectors+     4)
(defconstant +stage2-size+        (* +stage2-sectors+ +floppy-sector-size+))

(defun pad-to-sector (bytes)
  "Return a new byte vector padded to the next sector boundary."
  (let* ((len     (length bytes))
         (padded  (* +floppy-sector-size+
                     (ceiling len +floppy-sector-size+)))
         (result  (make-array padded :element-type '(unsigned-byte 8)
                              :initial-element 0)))
    (replace result bytes)
    result))

(defun write-kernel (output-path)
  "Assemble Ecclesia and write a bootable floppy image to OUTPUT-PATH."
  (format t "[ecclesia] Assembling Stage 1 (MBR)...~%")
  (let ((stage1 (assemble *bootloader*)))
    (unless (= (length stage1) +floppy-sector-size+)
      (error "Stage 1 must be exactly ~d bytes, got ~d"
             +floppy-sector-size+ (length stage1)))

    (format t "[ecclesia] Assembling Stage 2...~%")
    (let ((stage2 (pad-to-sector (assemble *stage2*))))
      (when (> (length stage2) +stage2-size+)
        (error "Stage 2 too large: ~d bytes (max ~d)"
               (length stage2) +stage2-size+))

      (format t "[ecclesia] Assembling 64-bit kernel...~%")
      (let ((kernel (pad-to-sector (assemble *kernel64*))))
        (let ((total (+ +floppy-sector-size+ +stage2-size+ (length kernel))))
          (format t "[ecclesia] Writing floppy image (~d bytes)...~%~%" total)

          (with-open-file (out output-path
                               :direction :output
                               :element-type '(unsigned-byte 8)
                               :if-exists :supersede)
            (write-sequence stage1 out)
            (write-sequence stage2 out)
            ;; Pad stage2 to exactly +stage2-size+ if needed
            (loop repeat (- +stage2-size+ (length stage2))
                  do (write-byte 0 out))
            (write-sequence kernel out))

          (format t "[ecclesia] Done.~%")
          (format t "  Stage 1: ~d bytes~%" (length stage1))
          (format t "  Stage 2: ~d bytes~%" (length stage2))
          (format t "  Kernel:  ~d bytes~%" (length kernel))
          (format t "  Total:   ~d bytes~%" total))))))
