;;;; bootloader.lisp — Stage 1 MBR bootloader
;;;;
;;;; 16-bit real mode. Prints the Ecclesia banner via BIOS INT 10h (TTY mode),
;;;; then halts. Assembled into a 512-byte MBR image by assembler.lisp.
;;;;
;;;; Memory layout at 0x7C00:
;;;;
;;;;   [code: setup + print loop]   ← BIOS jumps here
;;;;   [banner string, null-term]   ← SI points here
;;;;   [zero padding to offset 510]
;;;;   [0x55 0xAA]                  ← boot signature at bytes 510-511
;;;;
;;;; The code must fit before the banner string. We compute the banner's
;;;; load address as (0x7C00 + code-size) and load it into SI.

(in-package #:ecclesia)

(defparameter *banner*
  (concatenate 'string
    (string #\Return) (string #\Newline)
    "  ___         _           _     " (string #\Return) (string #\Newline)
    " | __| __ __ | | ___  ___(_) __ " (string #\Return) (string #\Newline)
    " | _|  \\ V / | |/ -_)(_-/| |/ _|" (string #\Return) (string #\Newline)
    " |___|  \\_/  |_|\\___|/__/|_|\\__|" (string #\Return) (string #\Newline)
    (string #\Return) (string #\Newline)
    "  A Lisp OS for the ages." (string #\Return) (string #\Newline)
    (string #\Return) (string #\Newline)))

(defun banner-db-forms ()
  "Return a list of (db <byte>) forms for *banner* plus a null terminator."
  (append (loop for c across *banner* collect `(db ,(char-code c)))
          '((db 0))))

;;; Code layout (byte sizes):
;;;   CLI             1
;;;   XOR AX,AX       2
;;;   MOV DS,AX       2
;;;   MOV ES,AX       2
;;;   MOV SS,AX       2
;;;   MOV SP,#x7c00   3
;;;   STI             1
;;;   MOV SI,<imm16>  3   ← load banner address into SI
;;;   MOV AH,#x0e     3   ← BIOS TTY subfunction (outside loop, constant)
;;;   MOV BH,#x00     3   ← page number 0
;;; .print_loop:
;;;   LODSB           1   ← AL = [DS:SI], SI++
;;;   TEST AL,AL      2   ← null terminator?
;;;   JZ .done        2   ← yes → stop
;;;   INT #x10        2   ← BIOS print AL
;;;   JNZ .print_loop 2   ← loop (JNZ because TEST set ZF=0)
;;; .done:
;;;   HLT             1   ← halt
;;; Total code bytes  = 1+2+2+2+2+3+1+3+3+3+1+2+2+2+2+1 = 32

(defconstant +code-size+ 30)

(defun make-bootloader ()
  (let* ((banner-addr (+ #x7c00 +code-size+))
         (banner-forms (banner-db-forms))
         (banner-size  (length banner-forms))
         ;; 512 total - 2 for boot signature - code - banner
         (pad-size     (- 512 2 +code-size+ banner-size)))
    (when (< pad-size 0)
      (error "Bootloader too large: code ~d + banner ~d = ~d > 510"
             +code-size+ banner-size (+ +code-size+ banner-size)))
    `((bits 16)
      (org  #x7c00)

      ;; Initialise segments and stack
      (cli)
      (xor  ax ax)
      (mov  ds ax)
      (mov  es ax)
      (mov  ss ax)
      (mov  sp #x7c00)
      (sti)

      ;; SI = address of banner string (immediately after this code)
      (mov  si ,banner-addr)

      ;; AH = 0Eh (BIOS TTY output), BH = page 0
      (mov  ah #x0e)
      (mov  bh #x00)

      ;; Print loop
      (label print-loop)
      (lodsb)                      ; AL = *SI, SI++
      (test  al al)                ; set flags on AL
      (jz    done)                 ; null terminator → stop
      (int   #x10)                 ; BIOS: print AL
      (jnz   print-loop)           ; loop

      (label done)
      (hlt)

      ;; Inline banner string
      ,@banner-forms

      ;; Pad to 510 bytes
      (times ,pad-size db 0)

      ;; Boot signature
      (dw #xaa55))))

(defparameter *bootloader* (make-bootloader))
