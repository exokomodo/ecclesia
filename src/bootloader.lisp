;;;; bootloader.lisp — Stage 1 + Stage 2 bootloader definition
;;;;
;;;; Written as Lisp s-expressions representing x86 assembly.
;;;; The assembler (assembler.lisp) will translate these into
;;;; a bootable floppy image.
;;;;
;;;; Boot sequence:
;;;;   1. BIOS loads 512-byte MBR at 0x7C00 (16-bit real mode)
;;;;   2. Stage 1 loads stage 2 from floppy sectors
;;;;   3. Stage 2 enters 32-bit protected mode -> 64-bit long mode
;;;;   4. Control is handed to the Lisp kernel

(in-package #:ecclesia)

(defparameter *bootloader*
  '(;; ===== Stage 1: 16-bit real mode MBR =====
    (bits 16)
    (org  #x7c00)

    ;; Initialise segments and stack
    (cli)
    (xor ax ax)
    (mov ds ax)
    (mov es ax)
    (mov ax #x7000)
    (mov ss ax)
    (mov sp #xff00)
    (sti)

    ;; TODO: Load stage 2 from floppy (INT 13h)

    ;; Boot sector padding + signature
    (times (- 510 (- $ $$)) db 0)
    (dw #xaa55)))
