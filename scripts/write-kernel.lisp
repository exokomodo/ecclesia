#!/usr/bin/env -S sbcl --script
;;;; scripts/write-kernel.lisp — Ecclesia build script
;;;;
;;;; Floppy image layout:
;;;;     Sector 1     (0x0000): Stage 1 MBR            (512 bytes)
;;;;     Sectors 2-9  (0x0200): Stage 2                 (up to 4KB)
;;;;     Sectors 10+  (0x1200): ELF kernel program      (up to 16 sectors / 8KB)
;;;;     Remainder:             zero-padded to 1.44MB
;;;;
;;;; Stage 2 loads the ELF from sectors 10+ into 0x30000, enters long mode,
;;;; parses the ELF header, and jumps directly to _start. No separate kernel binary.
;;;;
;;;; TARGET_ARCH environment variable selects the build target (default: x86_64).

(require 'asdf)
(pushnew (truename "./") asdf:*central-registry* :test #'equal)
(asdf:oos 'asdf:load-op 'ecclesia)
(in-package #:ecclesia.bootstrap)

(defconstant +floppy-total-size+ (* 2880 512))  ; standard 1.44MB
(defconstant +elf-sector-count+  16)            ; sectors reserved for ELF

(defun output-path-from-env ()
  (or (sb-ext:posix-getenv "IMAGE")
      (error "IMAGE environment variable is required")))

(defun ensure-output-directory-exists (output-path)
  (ensure-directories-exist output-path)
  output-path)

(defun pad-to-sector (bytes)
  (let* ((len    (length bytes))
         (padded (* +floppy-sector-size+ (ceiling (max len 1) +floppy-sector-size+)))
         (result (make-array padded :element-type '(unsigned-byte 8)
                             :initial-element 0)))
    (replace result bytes)
    result))

(let* ((target-arch  (or (sb-ext:posix-getenv "TARGET_ARCH") "x86_64"))
       (arch-keyword (intern (string-upcase target-arch) :keyword)))

  (setf *build-target* arch-keyword)

  (format t "[ecclesia] Assembling Stage 1 (MBR)...~%")
  (let ((stage1 (assemble *bootloader*)))
    (unless (= (length stage1) +floppy-sector-size+)
      (error "Stage 1 must be exactly ~d bytes, got ~d"
             +floppy-sector-size+ (length stage1)))

    (format t "[ecclesia] Assembling Stage 2 [~a]...~%" target-arch)
    (let ((stage2 (pad-to-sector (assemble *stage2*))))
      (when (> (length stage2) +stage2-size+)
        (error "Stage 2 too large: ~d bytes (max ~d)" (length stage2) +stage2-size+))

      ;; ── Load ELF program if available ────────────────────────────────────
      ;; ELF goes at sector 10 (right after Stage 2)
      (let* ((elf-path    (format nil "build/kernel-~a.elf" target-arch))
             (elf-bytes   (when (probe-file elf-path)
                            (with-open-file (f elf-path :element-type '(unsigned-byte 8))
                              (let ((buf (make-array (file-length f)
                                                     :element-type '(unsigned-byte 8))))
                                (read-sequence buf f)
                                buf))))
             (elf-size    (* +elf-sector-count+ +floppy-sector-size+))
             (elf-padded  (pad-to-sector (or elf-bytes #(0)))))

        (format t "[ecclesia] ELF path: ~a -> ~a~%"
                elf-path (if elf-bytes "FOUND" "NOT FOUND"))
        (when elf-bytes
          (format t "[ecclesia] Embedding ~a (~d bytes) at sector 10...~%"
                  elf-path (length elf-bytes)))

        (let ((output-path (ensure-output-directory-exists (output-path-from-env))))
          (format t "[ecclesia] Writing ~a (~d bytes / 1.44MB)...~%~%"
                  output-path +floppy-total-size+)

          (with-open-file (out output-path
                               :direction :output
                               :element-type '(unsigned-byte 8)
                               :if-exists :supersede)
            ;; Sector 1: Stage 1 MBR
            (write-sequence stage1 out)
            ;; Sectors 2-9: Stage 2 (padded to 4KB)
            (write-sequence stage2 out)
            (loop repeat (- +stage2-size+ (length stage2)) do (write-byte 0 out))
            ;; Sectors 10-25: ELF program (padded to 8KB)
            (write-sequence elf-padded out)
            (loop repeat (- elf-size (length elf-padded)) do (write-byte 0 out))
            ;; Zero-pad remainder to 1.44MB
            (let ((written (+ +floppy-sector-size+ +stage2-size+ elf-size)))
              (loop repeat (- +floppy-total-size+ written) do (write-byte 0 out))))

          (format t "[ecclesia] Done.~%")
          (format t "  Stage 1:  ~4d bytes~%" (length stage1))
          (format t "  Stage 2:  ~4d bytes~%" (length stage2))
          (when elf-bytes
            (format t "  ELF:      ~4d bytes~%" (length elf-bytes)))
          (format t "  Total:    ~4d bytes~%" +floppy-total-size+))))))
