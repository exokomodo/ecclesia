;;;; assembler.lisp — x86 two-pass assembler (16/32/64-bit, MBR + Stage 2)
;;;;
;;;; Pass 1: walk instructions, record label addresses.
;;;; Pass 2: emit bytes with labels resolved.
;;;;
;;;; Supported forms:
;;;;   (org  <addr>)              — set origin
;;;; Mode control:
;;;;   (bits 16|32|64)            — set current addressing mode
;;;; Data:
;;;;   (db   <byte> ...)          — emit raw byte(s)
;;;;   (dw   <word>)              — emit 16-bit LE word
;;;;   (dd   <dword>)             — emit 32-bit LE dword
;;;;   (dq   <qword>)             — emit 64-bit LE qword
;;;;   (times <n> db <byte>)      — emit N copies of byte
;;;;   (label <name>)             — define label at current position
;;;; 16-bit instructions:
;;;;   (cli) (sti) (hlt)
;;;;   (xor  <r16> <r16>)
;;;;   (mov  <dst> <src>)         — sreg←r16, r16←imm16, r16←r16, r8←imm8
;;;;   (int  <imm8>)
;;;;   (lodsb) (lodsw)
;;;;   (test al al)
;;;;   (jmp  short <label>)       — rel8
;;;;   (jmp  abs   <addr>)        — near rel16/32
;;;;   (jmp  far   <sel> <label>) — far jump (segment:offset)
;;;;   (jz/jnz/jc/jnc <label>)   — conditional short jumps
;;;; 32-bit instructions:
;;;;   (mov  eax cr0|cr4)         — read control register
;;;;   (mov  cr0|cr4 eax)         — write control register
;;;;   (mov  <r32> <imm32>)       — MOV r32, imm32
;;;;   (mov  <sreg> <r16imm>)     — MOV sreg, ax (16-bit)
;;;;   (or   <r32> <imm32>)       — OR r32, imm32
;;;;   (mov  esp <imm32>)         — stack pointer
;;;;   (lgdt (<label>))           — load GDT
;;;;   (rdmsr) (wrmsr)            — MSR access
;;;;   (mov  ecx <imm32>)         — MOV ECX, imm32

(in-package #:ecclesia)

;;; ── Register tables ─────────────────────────────────────────────────────────

(defparameter *r8-encoding*
  '((al . 0) (cl . 1) (dl . 2) (bl . 3)
    (ah . 4) (ch . 5) (dh . 6) (bh . 7)))

(defparameter *r16-encoding*
  '((ax . 0) (cx . 1) (dx . 2) (bx . 3)
    (sp . 4) (bp . 5) (si . 6) (di . 7)))

(defparameter *r32-encoding*
  '((eax . 0) (ecx . 1) (edx . 2) (ebx . 3)
    (esp . 4) (ebp . 5) (esi . 6) (edi . 7)))

(defparameter *sreg-encoding*
  '((es . 0) (cs . 1) (ss . 2) (ds . 3) (fs . 4) (gs . 5)))

(defparameter *r64-encoding*
  '((rax . 0) (rcx . 1) (rdx . 2) (rbx . 3)
    (rsp . 4) (rbp . 5) (rsi . 6) (rdi . 7)))

(defparameter *creg-encoding*
  '((cr0 . 0) (cr2 . 2) (cr3 . 3) (cr4 . 4)))

(defun r8-enc  (r) (or (cdr (assoc r *r8-encoding*))  (error "Unknown r8:  ~a" r)))
(defun r16-enc (r) (or (cdr (assoc r *r16-encoding*)) (error "Unknown r16: ~a" r)))
(defun r32-enc (r) (or (cdr (assoc r *r32-encoding*)) (error "Unknown r32: ~a" r)))
(defun sreg-enc (r) (cdr (assoc r *sreg-encoding*)))
(defun creg-enc (r) (cdr (assoc r *creg-encoding*)))

(defun r8-p   (s) (not (null (assoc s *r8-encoding*))))
(defun r16-p  (s) (not (null (assoc s *r16-encoding*))))
(defun r32-p  (s) (not (null (assoc s *r32-encoding*))))
(defun r64-p  (s) (not (null (assoc s *r64-encoding*))))
(defun sreg-p (s) (not (null (assoc s *sreg-encoding*))))
(defun creg-p (s) (not (null (assoc s *creg-encoding*))))

(defun r64-enc (r) (or (cdr (assoc r *r64-encoding*)) (error "Unknown r64: ~a" r)))

;;; ── Instruction size estimation (pass 1) ────────────────────────────────────

;;; Current bit mode (updated by (bits N) forms during each pass)
(defvar *asm-bits* 16)

(defun instruction-size (form)
  (destructuring-bind (op &rest args) form
    (case op
      ((org label) 0)
      (bits (setf *asm-bits* (first args)) 0)
      (db    (length args))
      (dw    2)
      (dd    4)
      (dq    8)
      (times (destructuring-bind (n db-op byte) args (declare (ignore db-op byte)) n))
      ((cli sti hlt lodsb lodsw rdmsr wrmsr stosd stosb movsd movsb) 1)
      (rep   (1+ (instruction-size (list (first args)))))
      (int   2)
      ((test jz jnz jc jnc) 2)
      ;; XOR r16,r16 = 2; XOR r32,r32 = 2; XOR r32,r32 (with REX) = 3 (we skip REX for now)
      (xor   (if (r32-p (first args)) 2 2))
      ;; MOV [imm32], r32 = 6 (opcode + ModRM + disp32)
      ;; MOV [imm32], imm32 handled in mov size below
      (mov
       (let ((dst (first args)) (src (second args)))
         (cond
           ;; MOV r8, imm8
           ((and (r8-p dst) (numberp src)) 2)
           ;; MOV sreg, r16: 2 bytes in 16-bit mode, 3 (with 0x66) in 32/64-bit
           ((sreg-p dst) (if (= *asm-bits* 16) 2 3))
           ;; MOV r16, imm16: 3 in 16-bit, 4 in 32/64-bit
           ((and (r16-p dst) (numberp src)) (if (= *asm-bits* 16) 3 4))
           ;; MOV r16, r16: 2 in 16-bit, 3 in 32/64-bit
           ((and (r16-p dst) (r16-p src)) (if (= *asm-bits* 16) 2 3))
           ;; MOV r32, cr  or  MOV cr, r32  (0x0f 0x20/0x22 ModRM)
           ((or (and (r32-p dst) (creg-p src))
                (and (creg-p dst) (r32-p src))) 3)
           ;; MOV r32, imm32
           ((and (r32-p dst) (numberp src)) 5)
           ;; MOV r32, r32
           ((and (r32-p dst) (r32-p src)) 2)
           ;; MOV [imm32], r32  →  6 bytes (0x89 ModRM disp32)
           ((and (listp dst) (eq (car dst) 'mem32) (r32-p src)) 6)
           ;; MOV [imm32], imm32  →  10 bytes (0xc7 /0 disp32 imm32)
           ((and (listp dst) (eq (car dst) 'mem32) (numberp src)) 10)
           ;; MOV r64, imm64  →  REX.W(1) + 0xb8+r + imm64 = 10 bytes
           ((and (r64-p dst) (numberp src)) 10)
           (t (error "Unknown MOV size: ~a ~a" dst src)))))
      (or
       (let ((dst (first args)) (src (second args)))
         (cond
           ;; OR r32, imm32
           ((and (r32-p dst) (numberp src)) 6)
           ;; OR r32, r32
           ((and (r32-p dst) (r32-p src)) 2)
           (t (error "Unknown OR size: ~a ~a" dst src)))))
      (lgdt  5)   ; 0x0f 0x01 ModRM disp16
      ;; IN AL, imm8  →  2 bytes
      (in    2)
      ;; MOV WORD PTR [RDI+disp32], imm16  →  0x66 0xC7 0x87 disp32 imm16 = 9 bytes
      (mov-rdi-word 9)
      (jmp
       (cond
         ;; FAR: 16-bit mode → 0xEA off16 seg16 = 5 bytes
         ;;      32-bit mode → 0xEA off32 seg16 = 7 bytes
         ((eq (first args) 'far)   (if (= *asm-bits* 16) 5 7))
         ((eq (first args) 'abs)   3)
         ((eq (first args) 'short) 2)
         (t (error "Unknown JMP form"))))
      (t (error "Unknown instruction (size): ~a" op)))))

;;; ── Pass 1: collect label addresses ─────────────────────────────────────────

(defun collect-labels (instructions origin)
  (let ((labels (make-hash-table))
        (offset 0)
        (*asm-bits* 16))         ; reset mode for this pass
    (dolist (form instructions)
      (destructuring-bind (op &rest args) form
        (case op
          (org   (setf offset (- (first args) origin)))
          (bits  (setf *asm-bits* (first args)))
          (label (setf (gethash (first args) labels) (+ origin offset)))
          (t     (incf offset (instruction-size form))))))
    labels))

;;; ── Expression evaluator ─────────────────────────────────────────────────────

(defun eval-expr (expr labels)
  "Evaluate EXPR: integer → itself; symbol → label lookup;
   list (op a b) → apply op recursively."
  (cond
    ((integerp expr) expr)
    ((symbolp expr)
     (or (gethash expr labels)
         (error "Undefined label in expression: ~a" expr)))
    ((listp expr)
     (let ((op  (first expr))
           (a   (eval-expr (second expr) labels))
           (b   (when (third expr) (eval-expr (third expr) labels))))
       (case op
         (+ (+ a b))
         (- (if b (- a b) (- a)))
         (* (* a b))
         (t (error "Unknown expression operator: ~a" op)))))
    (t (error "Cannot evaluate expression: ~a" expr))))

;;; ── Pass 2: emit bytes ───────────────────────────────────────────────────────

(defun emit-instruction (form labels origin buf)
  (flet ((cur-addr () (+ origin (fill-pointer buf)))
         (push-byte (b) (vector-push-extend (logand b #xff) buf))
         (push-u16 (w)
           (vector-push-extend (logand w #xff) buf)
           (vector-push-extend (logand (ash w -8) #xff) buf))
         (push-u32 (d)
           (loop for i from 0 to 24 by 8
                 do (vector-push-extend (logand (ash d (- i)) #xff) buf)))
         (push-u64 (q)
           (loop for i from 0 to 56 by 8
                 do (vector-push-extend (logand (ash q (- i)) #xff) buf)))
         (resolve (name)
           (or (gethash name labels)
               (error "Undefined label: ~a" name))))
    (destructuring-bind (op &rest args) form
      (case op
        (bits  (setf *asm-bits* (first args)))
        ((org label) nil)

        (db    (dolist (b args) (push-byte (eval-expr b labels))))
        (dw    (push-u16 (eval-expr (first args) labels)))
        (dd    (push-u32 (eval-expr (first args) labels)))
        (dq    (push-u64 (eval-expr (first args) labels)))

        (times (destructuring-bind (n db-op byte) args
                 (declare (ignore db-op))
                 (dotimes (_ n) (push-byte byte))))

        (cli    (push-byte #xfa))
        (sti    (push-byte #xfb))
        (hlt    (push-byte #xf4))
        (lodsb  (push-byte #xac))
        (lodsw  (push-byte #xad))
        (stosd  (push-byte #xab))
        (stosb  (push-byte #xaa))
        (movsd  (push-byte #xa5))
        (movsb  (push-byte #xa4))
        (rdmsr  (push-byte #x0f) (push-byte #x32))
        (wrmsr  (push-byte #x0f) (push-byte #x30))

        ;; REP prefix  →  0xF3 + following instruction
        (rep
         (push-byte #xf3)
         (emit-instruction (list (first args)) labels origin buf))

        ;; XOR r16,r16 → 0x31 /r   XOR r32,r32 → 0x31 /r (same opcode, 32-bit default in PM)
        (xor
         (cond
           ((r32-p (first args))
            (let ((dst (r32-enc (first args)))
                  (src (r32-enc (second args))))
              (push-byte #x31)
              (push-byte (logior #xc0 (ash src 3) dst))))
           (t
            (let ((dst (r16-enc (first args)))
                  (src (r16-enc (second args))))
              (push-byte #x31)
              (push-byte (logior #xc0 (ash src 3) dst))))))

        ;; TEST AL, AL  →  0x84 0xC0
        (test
         (when (and (eq (first args) 'al) (eq (second args) 'al))
           (push-byte #x84) (push-byte #xc0)))

        ;; MOV — many variants
        (mov
         (let ((dst (first args)) (src (second args)))
           (cond
             ;; MOV r8, imm8  →  0xb0+r imm8
             ((and (r8-p dst) (numberp src))
              (push-byte (+ #xb0 (r8-enc dst)))
              (push-byte (logand src #xff)))
             ;; MOV sreg, r16  →  [0x66] 0x8e /r
             ;; 0x66 prefix needed when default operand size is 32/64-bit
             ((sreg-p dst)
              (unless (= *asm-bits* 16) (push-byte #x66))
              (push-byte #x8e)
              (push-byte (logior #xc0 (ash (sreg-enc dst) 3) (r16-enc src))))
             ;; MOV r16, imm16  →  [0x66] 0xb8+r imm16
             ((and (r16-p dst) (numberp src))
              (unless (= *asm-bits* 16) (push-byte #x66))
              (push-byte (+ #xb8 (r16-enc dst)))
              (push-u16 src))
             ;; MOV r16, r16  →  [0x66] 0x89 /r
             ((and (r16-p dst) (r16-p src))
              (unless (= *asm-bits* 16) (push-byte #x66))
              (push-byte #x89)
              (push-byte (logior #xc0 (ash (r16-enc src) 3) (r16-enc dst))))
             ;; MOV r32, cr  →  0x0f 0x20 /r
             ((and (r32-p dst) (creg-p src))
              (push-byte #x0f) (push-byte #x20)
              (push-byte (logior #xc0 (ash (creg-enc src) 3) (r32-enc dst))))
             ;; MOV cr, r32  →  0x0f 0x22 /r
             ((and (creg-p dst) (r32-p src))
              (push-byte #x0f) (push-byte #x22)
              (push-byte (logior #xc0 (ash (creg-enc dst) 3) (r32-enc src))))
             ;; MOV r32, imm32  →  0xb8+r imm32
             ((and (r32-p dst) (numberp src))
              (push-byte (+ #xb8 (r32-enc dst)))
              (push-u32 src))
             ;; MOV r32, r32  →  0x89 /r
             ((and (r32-p dst) (r32-p src))
              (push-byte #x89)
              (push-byte (logior #xc0 (ash (r32-enc src) 3) (r32-enc dst))))
             ;; MOV [imm32], r32  →  0x89 /r  mod=00 r/m=5 disp32
             ((and (listp dst) (eq (car dst) 'mem32) (r32-p src))
              (push-byte #x89)
              (push-byte (logior #x05 (ash (r32-enc src) 3)))
              (push-u32 (eval-expr (second dst) labels)))
             ;; MOV [imm32], imm32  →  0xc7 /0  mod=00 r/m=5 disp32 imm32
             ((and (listp dst) (eq (car dst) 'mem32) (numberp src))
              (push-byte #xc7)
              (push-byte #x05)   ; mod=00, reg=0, r/m=5
              (push-u32 (eval-expr (second dst) labels))
              (push-u32 src))
             ;; MOV r64, imm64  →  REX.W 0xb8+r imm64
             ((and (r64-p dst) (numberp src))
              (push-byte #x48)   ; REX.W prefix
              (push-byte (+ #xb8 (r64-enc dst)))
              (push-u64 src))
             (t (error "Unsupported MOV: ~a ~a" dst src)))))

        ;; OR r32, imm32  →  0x81 /1 imm32
        (or
         (let ((dst (first args)) (src (second args)))
           (cond
             ((and (r32-p dst) (numberp src))
              (push-byte #x81)
              (push-byte (logior #xc8 (r32-enc dst)))  ; /1 = 0b001xxxxx
              (push-u32 src))
             ((and (r32-p dst) (r32-p src))
              (push-byte #x09)
              (push-byte (logior #xc0 (ash (r32-enc src) 3) (r32-enc dst))))
             (t (error "Unsupported OR: ~a ~a" dst src)))))

        ;; LGDT [label]  →  0x0f 0x01 /2  ModRM(mod=00,reg=2,r/m=6) + disp16
        ;; (lgdt (<label>))
        (lgdt
         (let* ((label-name (caar args))
                (addr       (resolve label-name))
                (offset16   (logand addr #xffff)))
           (push-byte #x0f) (push-byte #x01)
           (push-byte #x16)   ; ModRM: mod=00 reg=010(/2) r/m=110 → [disp16]
           (push-u16 offset16)))

        ;; MOV ECX, imm32 (handled above in MOV)

        ;; Conditional short jumps
        (jz
         (let* ((tgt (resolve (first args)))
                (rel (- tgt (+ (cur-addr) 2))))
           (unless (<= -128 rel 127) (error "JZ out of range"))
           (push-byte #x74) (push-byte (logand rel #xff))))

        (jnz
         (let* ((tgt (resolve (first args)))
                (rel (- tgt (+ (cur-addr) 2))))
           (unless (<= -128 rel 127) (error "JNZ out of range"))
           (push-byte #x75) (push-byte (logand rel #xff))))

        (jc
         (let* ((tgt (resolve (first args)))
                (rel (- tgt (+ (cur-addr) 2))))
           (unless (<= -128 rel 127) (error "JC out of range"))
           (push-byte #x72) (push-byte (logand rel #xff))))

        (jnc
         (let* ((tgt (resolve (first args)))
                (rel (- tgt (+ (cur-addr) 2))))
           (unless (<= -128 rel 127) (error "JNC out of range"))
           (push-byte #x73) (push-byte (logand rel #xff))))

        ;; MOV WORD PTR [RDI+disp32], imm16
        ;; 0x66 0xC7 0x87 <disp32> <imm16>
        (mov-rdi-word
         (let ((disp (first args))
               (word (second args)))
           (push-byte #x66)
           (push-byte #xc7)
           (push-byte #x87)       ; ModRM: mod=10, reg=0, r/m=111(rdi)
           (push-u32 disp)
           (push-u16 word)))

        ;; IN AL, imm8  →  0xe4 imm8
        (in
         (when (eq (first args) 'al)
           (push-byte #xe4)
           (push-byte (logand (second args) #xff))))

        ;; INT imm8
        (int
         (push-byte #xcd)
         (push-byte (logand (first args) #xff)))

        ;; JMP
        (jmp
         (cond
           ;; (jmp far <seg16> <label>)
           ;; 16-bit mode: 0xEA off16 seg16  (5 bytes)
           ;; 32-bit mode: 0xEA off32 seg16  (7 bytes)
           ((eq (first args) 'far)
            (let* ((seg    (second args))
                   (label  (third args))
                   (offset (resolve label)))
              (push-byte #xea)
              (if (= *asm-bits* 16)
                  (push-u16 (logand offset #xffff))
                  (push-u32 (logand offset #xffffffff)))
              (push-u16 (logand seg #xffff))))
           ;; (jmp abs <addr16/32>) — near relative: 0xE9 rel16
           ((eq (first args) 'abs)
            (let* ((target (second args))
                   (here   (+ (cur-addr) 3))
                   (rel    (- target here)))
              (push-byte #xe9)
              (push-u16 (logand rel #xffff))))
           ;; (jmp short <label>) — short relative: 0xEB rel8
           ((eq (first args) 'short)
            (let* ((tgt (resolve (second args)))
                   (rel (- tgt (+ (cur-addr) 2))))
              (unless (<= -128 rel 127)
                (error "Short jump out of range to ~a (rel=~d)" (second args) rel))
              (push-byte #xeb)
              (push-byte (logand rel #xff))))
           (t (error "Unsupported JMP form: ~a" args))))

        (t (error "Unknown instruction: ~a" op))))))

;;; ── Public API ───────────────────────────────────────────────────────────────

(defun assemble (instructions)
  "Two-pass assemble INSTRUCTIONS into a (unsigned-byte 8) vector."
  (let ((origin (or (loop for form in instructions
                          when (eq (car form) 'org)
                          return (cadr form))
                    0)))
    (let ((labels (collect-labels instructions origin))
          (*asm-bits* 16)          ; reset mode for emit pass
          (buf    (make-array 4096
                              :element-type '(unsigned-byte 8)
                              :fill-pointer 0
                              :adjustable t)))
      (dolist (form instructions)
        (emit-instruction form labels origin buf))
      (subseq buf 0 (fill-pointer buf)))))
