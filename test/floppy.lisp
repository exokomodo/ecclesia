;;;; test/floppy.lisp — Floppy image layout tests
;;;;
;;;; Floppy layout (pure-bootstrap, no separate kernel binary):
;;;;   Sector 1     (byte     0): Stage 1 MBR       — 512 bytes
;;;;   Sectors 2-9  (byte   512): Stage 2            — up to 4KB
;;;;   Sectors 10-25 (byte 4608): ELF program        — up to 8KB
;;;;   Remainder:                 zero-padded to 1.44MB

(in-package #:ecclesia-test)

(defconstant +sector+        512)
(defconstant +stage2-offset+ (* 1 +sector+))   ; byte 512
(defconstant +elf-offset+    (* 9 +sector+))   ; byte 4608 — sector 10
(defconstant +elf-magic+     #x7f)             ; first byte of ELF magic

(defun floppy-image-path ()
  (let* ((arch (or (sb-ext:posix-getenv "TARGET_ARCH") "x86_64"))
         (path (format nil "build/ecclesia-~a.img" arch)))
    (when (probe-file path) path)))

(defun build-floppy ()
  "Load built floppy image from disk. Falls back to in-memory Stage1+Stage2 only."
  (let ((path (floppy-image-path)))
    (if path
        (with-open-file (f path :element-type '(unsigned-byte 8))
          (let ((buf (make-array (file-length f) :element-type '(unsigned-byte 8))))
            (read-sequence buf f)
            buf))
        ;; Fallback: assemble just enough to test Stage 1/2 offsets
        (let* ((stage1 (assemble *bootloader*))
               (stage2 (let ((s (assemble *stage2*)))
                         (let ((p (make-array (* 8 +sector+) :element-type '(unsigned-byte 8) :initial-element 0)))
                           (replace p s) p)))
               (img    (make-array (* 2880 +sector+) :element-type '(unsigned-byte 8) :initial-element 0)))
          (replace img stage1 :start1 0)
          (replace img stage2 :start1 +stage2-offset+)
          img))))

(defun run-floppy-tests ()
  (format t "~%Running floppy image layout tests...~%~%")
  (let* ((path (floppy-image-path))
         (_ (when path (format t "  INFO  Using built image: ~a~%" path)))
         (img (build-floppy)))

    ;; ── Sector boundaries ────────────────────────────────────────────────
    (assert= +sector+ +stage2-offset+
             "Stage 2 starts at sector 2 (byte 512)")

    (assert= (* 9 +sector+) +elf-offset+
             "ELF slot starts at sector 10 (byte 4608)")

    ;; ── Stage 2 starts correctly ─────────────────────────────────────────
    (assert= #xfa (aref img +stage2-offset+)
             "Stage 2 first byte is CLI (0xFA)")

    ;; ── ELF slot ─────────────────────────────────────────────────────────
    (let* ((elf-first  (aref img +elf-offset+))
           (elf-present (= elf-first +elf-magic+))
           (arch        (or (sb-ext:posix-getenv "TARGET_ARCH") "x86_64"))
           (elf-path    (format nil "build/hello-~a.elf" arch))
           (elf-built   (probe-file elf-path)))
      (cond
        (elf-present
         (assert= +elf-magic+ elf-first "ELF slot byte 0 is 0x7F")
         (assert= (char-code #\E) (aref img (+ +elf-offset+ 1)) "ELF slot byte 1 is 'E'")
         (assert= (char-code #\L) (aref img (+ +elf-offset+ 2)) "ELF slot byte 2 is 'L'")
         (assert= (char-code #\F) (aref img (+ +elf-offset+ 3)) "ELF slot byte 3 is 'F'")
         (format t "  INFO  ELF embedded at sector 10: ~d bytes~%"
                 (count-if #'plusp (subseq img +elf-offset+ (+ +elf-offset+ (* 16 +sector+))))))
        (elf-built
         (assert= +elf-magic+ elf-first
                  "ELF slot byte 0 is 0x7F (ELF was built but not embedded — rebuild image)"))
        (t
         (format t "  SKIP  ELF slot empty — no cross-compiler available (run 'make setup/toolchain')~%"))))

    (format t "~%All floppy layout tests passed.~%")))
