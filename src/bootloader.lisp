;;;; bootloader.lisp — Stage 1 MBR bootloader
;;;;
;;;; 16-bit real mode. Prints a minimal boot message, loads Stage 2
;;;; from floppy sector 2, and jumps to it.
;;;;
;;;; Memory layout:
;;;;   0x7C00  Stage 1 MBR (this file, 512 bytes)
;;;;   0x8000  Stage 2 (loaded by Stage 1 from sector 2+)

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

;;; Code layout byte sizes — must match exactly:
;;;   CLI             1
;;;   XOR AX,AX       2
;;;   MOV DS,AX       2
;;;   MOV ES,AX       2
;;;   MOV SS,AX       2
;;;   MOV SP,#x7c00   3
;;;   STI             1
;;;   MOV SI,<imm16>  3   print banner
;;;   MOV AH,#x0e     2
;;;   MOV BH,#x00     2
;;; .print_loop:
;;;   LODSB           1
;;;   TEST AL,AL      2
;;;   JZ .load_s2     2
;;;   INT #x10        2
;;;   JNZ .print_loop 2
;;; .load_s2:
;;;   MOV AH,#x02     2   INT 13h: read sectors
;;;   MOV AL,#x04     2   4 sectors = 2KB for Stage 2
;;;   MOV CH,#x00     2   cylinder 0
;;;   MOV CL,#x02     2   sector 2 (1-indexed)
;;;   MOV DH,#x00     2   head 0
;;;   MOV DL,#x00     2   drive 0 (floppy A)
;;;   MOV BX,#x8000   3   ES:BX = 0x0000:0x8000
;;;   INT #x13        2
;;;   JMP short .halt 2   if carry set, disk error — halt
;;;   MOV AX,#x8000   3   jump to Stage 2
;;;   MOV SP,ax       2   (reuse SP as temp; actually just JMP)
;;; Actually: use JMP to 0x8000 — need far jump or just jump to known addr.
;;; We implement JMP via: MOV AX, 0x8000 then call (but easiest is just
;;; encoding a 3-byte near JMP: 0xE9 rel16)
;;; Let's use a near JMP to absolute 0x8000 from known position.
;;; Total code before msg = let's compute

(defconstant +code-size+ 82)

(defun make-bootloader ()
  (let* ((msg-forms  (boot-message-db-forms))
         (msg-size   (length msg-forms))
         (msg-addr   (+ #x7c00 +code-size+))
         (pad-size   (- 512 2 +code-size+ msg-size)))
    (when (< pad-size 0)
      (error "Stage 1 too large: code ~d + message ~d = ~d > 510"
             +code-size+ msg-size (+ +code-size+ msg-size)))
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

      ;; Print boot message
      (mov  si ,msg-addr)
      (mov  ah #x0e)
      (mov  bh #x00)
      (label print-loop)
      (lodsb)
      (test  al al)
      (jz    load-stage2)
      (int   #x10)
      (jnz   print-loop)

      ;; Load Stage 2 from floppy into 0x8000
      (label load-stage2)
      ;; Load Stage 2 (sectors 2-5) into 0x8000
      (mov  ah #x02)       ; INT 13h: read sectors
      (mov  al #x04)       ; read 4 sectors = Stage 2
      (mov  ch #x00)       ; cylinder 0
      (mov  cl #x02)       ; sector 2
      (mov  dh #x00)       ; head 0
      (mov  dl #x00)       ; drive 0 (floppy)
      (mov  bx #x8000)     ; destination: 0x0000:0x8000
      (int  #x13)
      (jc   disk-error)

      ;; Load kernel (sectors 6-13, 8 sectors = 4KB) into 0x1000:0x0000 = 0x10000
      ;; We can't load to 0x100000 from real mode without A20+unreal mode tricks.
      ;; Use segment trick: ES=0x1000, BX=0x0000 → physical 0x10000
      ;; Then Stage 2 copies from 0x10000 to 0x100000 in PM.
      ;; Actually, simpler: use unreal mode to access >1MB, OR just load at
      ;; a low address and copy. For now load at 0x20000 (ES=0x2000, BX=0).
      (mov  ax #x2000)
      (mov  es ax)
      (mov  ah #x02)
      (mov  al #x08)       ; 8 sectors = 4KB kernel
      (mov  ch #x00)
      (mov  cl #x06)       ; sector 6
      (mov  dh #x00)
      (mov  dl #x00)
      (mov  bx #x0000)     ; ES:BX = 0x2000:0x0000 = physical 0x20000
      (int  #x13)
      (jc   disk-error)    ; carry set = read failed

      ;; Jump to Stage 2 at 0x8000
      (jmp  abs #x8000)

      ;; Disk error: print 'E' and halt
      (label disk-error)
      (mov  ah #x0e)
      (mov  al #x45)       ; 'E'
      (int  #x10)
      (hlt)

      ;; Inline boot message
      ,@msg-forms
      (times ,pad-size db 0)
      (dw #xaa55))))

(defparameter *bootloader* (make-bootloader))
