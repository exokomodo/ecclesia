;;;; test/floppy.lisp — Full floppy image layout tests
;;;;
;;;; Verifies that the assembled floppy image has the correct structure:
;;;;   Sector 1  (byte     0): Stage 1 MBR        — 512 bytes
;;;;   Sectors 2-9  (byte 512): Stage 2            — up to 2048 bytes
;;;;   Sectors 10-17 (byte 4608): Kernel           — up to 4096 bytes
;;;;   Sectors 18-33 (byte 8704): ELF binary       — up to 8192 bytes
;;;;
;;;; ELF embedding is optional — tests pass whether or not an ELF is present,
;;;; but when an ELF is present the tests verify correct magic and placement.

(in-package #:ecclesia-test)

(defun make-kernel-main () (ecclesia:make-kernel-main))

(defconstant +sector+        512)
(defconstant +stage2-offset+ (* 1 +sector+))
(defconstant +kernel-offset+ (* 9 +sector+))
(defconstant +elf-offset+    (* 17 +sector+))   ; sector 18, 0-indexed offset 17*512
(defconstant +elf-magic+     #x7f)              ; first byte of ELF magic

(defun floppy-image-path ()
  "Return the path of the built floppy image for the current TARGET_ARCH, or NIL."
  (let* ((arch (or (sb-ext:posix-getenv "TARGET_ARCH") "x86_64"))
         (path (format nil "build/ecclesia-~a.img" arch)))
    (when (probe-file path) path)))

(defun build-floppy ()
  "Load built floppy image from disk (includes ELF). Falls back to in-memory assembly."
  (let ((path (floppy-image-path)))
    (if path
        (with-open-file (f path :element-type '(unsigned-byte 8))
          (let ((buf (make-array (file-length f) :element-type '(unsigned-byte 8))))
            (read-sequence buf f)
            buf))
        (let* ((stage1 (assemble *bootloader*))
               (stage2 (let ((s (assemble *stage2*)))
                         (let ((p (make-array (* 4 +sector+) :element-type '(unsigned-byte 8) :initial-element 0)))
                           (replace p s) p)))
               (kernel (let ((k (assemble (make-kernel-main))))
                         (let ((p (make-array (* 8 +sector+) :element-type '(unsigned-byte 8) :initial-element 0)))
                           (replace p k) p)))
               (img    (make-array (* 2880 +sector+) :element-type '(unsigned-byte 8) :initial-element 0)))
          (replace img stage1 :start1 0)
          (replace img stage2 :start1 +stage2-offset+)
          (replace img kernel :start1 +kernel-offset+)
          img))))

(defun run-floppy-tests ()
  (format t "~%Running floppy image layout tests...~%~%")
  (let* ((path (floppy-image-path))
         (_ (when path (format t "  INFO  Using built image: ~a~%" path)))
         (img (build-floppy)))

    ;; ── Sector boundaries ────────────────────────────────────────────────
    (assert= +sector+ +stage2-offset+
             "Stage 2 starts at sector 2 (byte 512)")

    (assert= (* 9 +sector+) +kernel-offset+
             "Kernel starts at sector 10 (byte 4608)")

    (assert= (* 17 +sector+) +elf-offset+
             "ELF slot starts at sector 18 (byte 8704)")

    ;; ── Stage 2 starts correctly ─────────────────────────────────────────
    (assert= #xfa (aref img +stage2-offset+)
             "Stage 2 first byte is CLI (0xFA)")

    ;; ── Kernel area is non-zero ───────────────────────────────────────────
    (assert= t (> (count-if #'plusp (subseq img +kernel-offset+ (+ +kernel-offset+ 512))) 0)
             "Kernel area at sector 10 contains non-zero bytes")

    ;; ── ELF slot: must contain valid ELF magic when userland was built ────
    ;; Fail hard when the ELF is absent AND we're on a system that should
    ;; have a cross-compiler (i.e. the userland target succeeded).
    (let* ((elf-first (aref img +elf-offset+))
           (elf-present (= elf-first +elf-magic+))
           (arch (or (sb-ext:posix-getenv "TARGET_ARCH") "x86_64"))
           (elf-path (format nil "build/hello-~a.elf" arch))
           (elf-built (probe-file elf-path)))
      (cond
        (elf-present
         (assert= +elf-magic+ elf-first "ELF slot byte 0 is 0x7F")
         (assert= (char-code #\E) (aref img (+ +elf-offset+ 1)) "ELF slot byte 1 is 'E'")
         (assert= (char-code #\L) (aref img (+ +elf-offset+ 2)) "ELF slot byte 2 is 'L'")
         (assert= (char-code #\F) (aref img (+ +elf-offset+ 3)) "ELF slot byte 3 is 'F'")
         (format t "  INFO  ELF embedded: ~d bytes~%"
                 (count-if #'plusp (subseq img +elf-offset+ (+ +elf-offset+ (* 16 +sector+))))))
        (elf-built
         ;; ELF was built but not embedded — hard fail
         (assert= +elf-magic+ elf-first
                  "ELF slot byte 0 is 0x7F (ELF was built but not embedded — rebuild image)"))
        (t
         (format t "  SKIP  ELF slot empty — no cross-compiler available (run 'make setup/toolchain')~%"))))

    (format t "~%All floppy layout tests passed.~%")))
