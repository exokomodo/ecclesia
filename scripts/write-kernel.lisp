#!/usr/bin/env -S sbcl --script
;;;; scripts/write-kernel.lisp — Ecclesia build script
;;;;
;;;; Assembles Stage 1, Stage 2, and the kernel into a bootable 1.44MB floppy.
;;;;
;;;; Layout:
;;;;   Sector 1     (0x0000): Stage 1 MBR            (512 bytes)
;;;;   Sectors 2-9  (0x0200): Stage 2                 (up to 4KB)
;;;;   Sectors 10+  (0x1200): kernel                  (padded to sector boundary)
;;;;   Remainder:             zero-padded to 1.44MB
;;;;
;;;; TARGET_ARCH environment variable selects the build target (default: x86_64).

(require 'asdf)
(pushnew (truename "./") asdf:*central-registry* :test #'equal)
(asdf:oos 'asdf:load-op 'ecclesia)
(in-package #:ecclesia)

(defconstant +floppy-total-size+ (* 2880 512))  ; standard 1.44MB

(defun pad-to-sector (bytes)
  "Pad BYTES with zeros to the next 512-byte sector boundary."
  (let* ((len    (length bytes))
         (padded (* +floppy-sector-size+ (ceiling len +floppy-sector-size+)))
         (result (make-array padded :element-type '(unsigned-byte 8)
                             :initial-element 0)))
    (replace result bytes)
    result))

(let* ((target-arch  (or (sb-ext:posix-getenv "TARGET_ARCH") "x86_64"))
       (arch-keyword (intern (string-upcase target-arch) :keyword)))

  (format t "[ecclesia] Assembling Stage 1 (MBR)...~%")
  (let ((stage1 (assemble *bootloader*)))
    (unless (= (length stage1) +floppy-sector-size+)
      (error "Stage 1 must be exactly ~d bytes, got ~d"
             +floppy-sector-size+ (length stage1)))

    (format t "[ecclesia] Assembling Stage 2 [~a]...~%" target-arch)
    (let ((stage2 (pad-to-sector
                   (assemble (ecase arch-keyword
                               (:x86_64 *stage2*)
                               (:i386   *stage2-i386*)
                               (:aarch64 *stage2-aarch64*))))))
      (when (> (length stage2) +stage2-size+)
        (error "Stage 2 too large: ~d bytes (max ~d)" (length stage2) +stage2-size+))

      (format t "[ecclesia] Assembling kernel [~a]...~%" target-arch)
      (setf *build-target* arch-keyword)
      (setf *kernel-main*  (make-kernel-main))
      (let* ((kernel       (pad-to-sector (assemble *kernel-main*)))
             (content-size (+ +floppy-sector-size+ +stage2-size+ (length kernel)))
             (output-path  (format nil "ecclesia-~a.img" target-arch)))

        (format t "[ecclesia] Writing ~a (~d bytes / 1.44MB)...~%~%"
                output-path +floppy-total-size+)

        (with-open-file (out output-path
                             :direction :output
                             :element-type '(unsigned-byte 8)
                             :if-exists :supersede)
          (write-sequence stage1 out)
          (write-sequence stage2 out)
          (loop repeat (- +stage2-size+ (length stage2)) do (write-byte 0 out))
          (write-sequence kernel out)
          (loop repeat (- +floppy-total-size+ content-size) do (write-byte 0 out)))

        (format t "[ecclesia] Done.~%")
        (format t "  Stage 1: ~4d bytes~%" (length stage1))
        (format t "  Stage 2: ~4d bytes~%" (length stage2))
        (format t "  Kernel:  ~4d bytes~%" (length kernel))
        (format t "  Total:   ~4d bytes~%" +floppy-total-size+)))))
