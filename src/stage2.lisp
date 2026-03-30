;;;; stage2.lisp — Stage 2 (minimal: 16-bit real mode, print message, halt)
;;;;
;;;; Goal: confirm Stage 1 → Stage 2 handoff works before adding
;;;; protected mode, long mode, or page tables.

(in-package #:ecclesia)

(defparameter *stage2-message*
  (concatenate 'string
    (string #\Return) (string #\Newline)
    "Stage 2 OK"
    (string #\Return) (string #\Newline)))

(defun stage2-message-db-forms ()
  (append (loop for c across *stage2-message* collect `(db ,(char-code c)))
          '((db 0))))

(defconstant +s2-code-size+ 17)  ; see layout below

(defun make-stage2 ()
  (let* ((msg-forms (stage2-message-db-forms))
         (msg-size  (length msg-forms))
         (msg-addr  (+ #x8000 +s2-code-size+)))
    ;;  MOV SI, imm16  = 3
    ;;  MOV AH, #x0e  = 2
    ;;  MOV BH, #x00  = 2
    ;;  LODSB          = 1
    ;;  TEST AL, AL    = 2
    ;;  JZ done        = 2
    ;;  INT #x10       = 2
    ;;  JNZ print-loop = 2
    ;;  HLT            = 1
    ;; Total           = 17
    `((bits 16)
      (org  #x8000)

      (mov  si ,msg-addr)
      (mov  ah #x0e)
      (mov  bh #x00)

      (label print-loop)
      (lodsb)
      (test al al)
      (jz   done)
      (int  #x10)
      (jnz  print-loop)

      (label done)
      (hlt)

      ,@msg-forms)))

(defparameter *stage2* (make-stage2))

(defun stage2-size ()
  (length (assemble *stage2*)))
