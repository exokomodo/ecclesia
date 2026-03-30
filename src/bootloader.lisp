;;;; bootloader.lisp — Stage 1 MBR bootloader
;;;;
;;;; 16-bit real mode. Prints a minimal boot message via BIOS INT 10h,
;;;; then halts. The real Ecclesia banner is printed by boot.lisp once
;;;; the SBCL kernel is running.
;;;;
;;;; Memory layout at 0x7C00:
;;;;
;;;;   [code: setup + print loop]   ← BIOS jumps here
;;;;   [boot string, null-term]     ← SI points here
;;;;   [zero padding to offset 510]
;;;;   [0x55 0xAA]                  ← boot signature

(in-package #:ecclesia)

(defparameter *boot-message*
  (concatenate 'string
    (string #\Return) (string #\Newline)
    "Ecclesia booting..."
    (string #\Return) (string #\Newline)))

(defun boot-message-db-forms ()
  "Return DB forms for *boot-message* plus a null terminator."
  (append (loop for c across *boot-message* collect `(db ,(char-code c)))
          '((db 0))))

;;; Code layout byte sizes:
;;;   CLI             1
;;;   XOR AX,AX       2
;;;   MOV DS,AX       2
;;;   MOV ES,AX       2
;;;   MOV SS,AX       2
;;;   MOV SP,#x7c00   3
;;;   STI             1
;;;   MOV SI,<imm16>  3
;;;   MOV AH,#x0e     2
;;;   MOV BH,#x00     2
;;; .print_loop:
;;;   LODSB           1
;;;   TEST AL,AL      2
;;;   JZ .done        2
;;;   INT #x10        2
;;;   JNZ .print_loop 2
;;; .done:
;;;   HLT             1
;;; Total:           30

(defconstant +code-size+ 30)

(defun make-bootloader ()
  (let* ((msg-forms  (boot-message-db-forms))
         (msg-size   (length msg-forms))
         (msg-addr   (+ #x7c00 +code-size+))
         (pad-size   (- 512 2 +code-size+ msg-size)))
    (when (< pad-size 0)
      (error "Bootloader too large: code ~d + message ~d = ~d > 510"
             +code-size+ msg-size (+ +code-size+ msg-size)))
    `((bits 16)
      (org  #x7c00)

      (cli)
      (xor  ax ax)
      (mov  ds ax)
      (mov  es ax)
      (mov  ss ax)
      (mov  sp #x7c00)
      (sti)

      (mov  si ,msg-addr)
      (mov  ah #x0e)
      (mov  bh #x00)

      (label print-loop)
      (lodsb)
      (test  al al)
      (jz    done)
      (int   #x10)
      (jnz   print-loop)

      (label done)
      (hlt)

      ,@msg-forms
      (times ,pad-size db 0)
      (dw #xaa55))))

(defparameter *bootloader* (make-bootloader))
