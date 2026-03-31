#!/usr/bin/env -S sbcl --script
;;;; scripts/write-kernel.lisp — Ecclesia build script
;;;;
;;;; Assembles Stage 1, Stage 2, and the 64-bit kernel into a
;;;; bootable 1.44MB floppy image.
;;;;
;;;; Layout:
;;;;   Sector 1     (0x0000): Stage 1 MBR            (512 bytes)
;;;;   Sectors 2-9  (0x0200): Stage 2                 (up to 4KB)
;;;;   Sectors 10+  (0x1200): 64-bit kernel           (padded to sector boundary)
;;;;   Remainder:             zero-padded to 1.44MB

(require 'asdf)
(pushnew (truename "./") asdf:*central-registry* :test #'equal)
(asdf:oos 'asdf:load-op 'ecclesia)
(in-package #:ecclesia)

;;; ── Constants ───────────────────────────────────────────────────────────────
;;; +floppy-sector-size+, +stage2-sectors+, +stage2-size+ defined in src/boot/stage2-x86-64.lisp

(defconstant +floppy-total-size+ (* 2880 512))  ; standard 1.44MB

;;; ── Helpers ─────────────────────────────────────────────────────────────────

(defun pad-to-sector (bytes)
  "Return BYTES padded with zeros to the next 512-byte sector boundary."
  (let* ((len    (length bytes))
         (padded (* +floppy-sector-size+ (ceiling len +floppy-sector-size+)))
         (result (make-array padded :element-type '(unsigned-byte 8)
                             :initial-element 0)))
    (replace result bytes)
    result))

;;; ── Build ───────────────────────────────────────────────────────────────────

(format t "[ecclesia] Assembling Stage 1 (MBR)...~%")
(let ((stage1 (assemble *bootloader*)))
  (unless (= (length stage1) +floppy-sector-size+)
    (error "Stage 1 must be exactly ~d bytes, got ~d"
           +floppy-sector-size+ (length stage1)))

  (format t "[ecclesia] Assembling Stage 2...~%")
  (let ((stage2 (pad-to-sector (assemble *stage2*))))
    (when (> (length stage2) +stage2-size+)
      (error "Stage 2 too large: ~d bytes (max ~d)" (length stage2) +stage2-size+))

    (format t "[ecclesia] Assembling 64-bit kernel...~%")
    (let* ((kernel       (pad-to-sector (assemble *kernel-main*)))
           (content-size (+ +floppy-sector-size+ +stage2-size+ (length kernel)))
           (output-path  "floppy.img"))

      (format t "[ecclesia] Writing ~a (~d bytes / 1.44MB)...~%~%" output-path +floppy-total-size+)

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
      (format t "  Total:   ~4d bytes~%" +floppy-total-size+))))
