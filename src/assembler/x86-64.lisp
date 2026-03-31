;;;; x86-64.lisp — x86-64 instruction encodings
;;;;
;;;; Registers each supported mnemonic with the generic assembler via
;;;; register-instruction. Covers the subset needed for Ecclesia's boot chain.

(in-package #:ecclesia.assembler)

;;; ── Register tables ─────────────────────────────────────────────────────────

(defparameter *r8*
  '((al . 0) (cl . 1) (dl . 2) (bl . 3)
    (ah . 4) (ch . 5) (dh . 6) (bh . 7)))

(defparameter *r16*
  '((ax . 0) (cx . 1) (dx . 2) (bx . 3)
    (sp . 4) (bp . 5) (si . 6) (di . 7)))

(defparameter *r32*
  '((eax . 0) (ecx . 1) (edx . 2) (ebx . 3)
    (esp . 4) (ebp . 5) (esi . 6) (edi . 7)))

(defparameter *r64*
  '((rax . 0) (rcx . 1) (rdx . 2) (rbx . 3)
    (rsp . 4) (rbp . 5) (rsi . 6) (rdi . 7)))

(defparameter *sreg*
  '((es . 0) (cs . 1) (ss . 2) (ds . 3) (fs . 4) (gs . 5)))

(defparameter *creg*
  '((cr0 . 0) (cr2 . 2) (cr3 . 3) (cr4 . 4)))

(defun enc (table reg)
  (or (cdr (assoc reg table)) (error "Unknown register ~a" reg)))

(defun in-table (table sym) (not (null (assoc sym table))))

(defun r8-p   (s) (in-table *r8*   s))
(defun r16-p  (s) (in-table *r16*  s))
(defun r32-p  (s) (in-table *r32*  s))
(defun r64-p  (s) (in-table *r64*  s))
(defun sreg-p (s) (in-table *sreg* s))
(defun creg-p (s) (in-table *creg* s))

;;; ── Emit helpers ────────────────────────────────────────────────────────────

(defun push-byte (buf b)
  (vector-push-extend (logand b #xff) buf))

(defun push-u16 (buf w)
  (push-byte buf (logand w #xff))
  (push-byte buf (logand (ash w -8) #xff)))

(defun push-u32 (buf d)
  (loop for i from 0 to 24 by 8
        do (push-byte buf (logand (ash d (- i)) #xff))))

(defun push-u64 (buf q)
  (loop for i from 0 to 56 by 8
        do (push-byte buf (logand (ash q (- i)) #xff))))

(defun cur-addr (origin buf)
  (+ origin (fill-pointer buf)))

(defun resolve (labels name)
  (or (gethash name labels)
      (error "Undefined label: ~a" name)))

;;; ── Operand-size prefix helper ───────────────────────────────────────────────

(defun maybe-66 (buf mode)
  "Emit 0x66 operand-size prefix when in 32/64-bit mode and using 16-bit operands."
  (unless (= mode 16) (push-byte buf #x66)))

;;; ── Instruction registration macro ─────────────────────────────────────────

(defmacro definsn (mnemonic (args-var mode-var) size-form
                   (args-var2 labels-var origin-var buf-var mode-var2) &body emit-body)
  "Register a new instruction with the assembler table."
  `(register-instruction
    ',mnemonic
    (lambda (,args-var ,mode-var)
      (declare (ignorable ,args-var ,mode-var))
      ,size-form)
    (lambda (,args-var2 ,labels-var ,origin-var ,buf-var ,mode-var2)
      (declare (ignorable ,args-var2 ,labels-var ,origin-var ,buf-var ,mode-var2))
      ,@emit-body)))

;;; ── Data directives ─────────────────────────────────────────────────────────

(definsn db (args mode) (length args)
         (args labels origin buf mode)
  (dolist (b args) (push-byte buf (eval-expr b labels))))

(definsn dw (args mode) 2
         (args labels origin buf mode)
  (push-u16 buf (eval-expr (first args) labels)))

(definsn dd (args mode) 4
         (args labels origin buf mode)
  (push-u32 buf (eval-expr (first args) labels)))

(definsn dq (args mode) 8
         (args labels origin buf mode)
  (push-u64 buf (eval-expr (first args) labels)))

(definsn times (args mode) (first args)
         (args labels origin buf mode)
  (destructuring-bind (n _op byte) args
    (dotimes (_ n) (push-byte buf byte))))

;;; ── Single-byte instructions ────────────────────────────────────────────────

(macrolet ((simple (mnem byte)
             `(definsn ,mnem (args mode) 1
                       (args labels origin buf mode)
                (push-byte buf ,byte))))
  (simple cli   #xfa)
  (simple sti   #xfb)
  (simple hlt   #xf4)
  (simple lodsb #xac)
  (simple lodsw #xad)
  (simple stosd #xab)
  (simple stosb #xaa)
  (simple movsd #xa5)
  (simple movsb #xa4))

(definsn rdmsr (args mode) 2 (args labels origin buf mode)
  (push-byte buf #x0f) (push-byte buf #x32))

(definsn wrmsr (args mode) 2 (args labels origin buf mode)
  (push-byte buf #x0f) (push-byte buf #x30))

;;; ── REP prefix ──────────────────────────────────────────────────────────────

(definsn rep (args mode) (1+ (instruction-size (list (first args))))
         (args labels origin buf mode)
  (push-byte buf #xf3)
  (emit-instruction (list (first args)) labels origin buf))

;;; ── XOR ─────────────────────────────────────────────────────────────────────

(definsn xor (args mode) 2
         (args labels origin buf mode)
  (let ((dst (first args)) (src (second args)))
    (cond
      ((r32-p dst)
       (push-byte buf #x31)
       (push-byte buf (logior #xc0 (ash (enc *r32* src) 3) (enc *r32* dst))))
      (t
       (push-byte buf #x31)
       (push-byte buf (logior #xc0 (ash (enc *r16* src) 3) (enc *r16* dst)))))))

;;; ── TEST ────────────────────────────────────────────────────────────────────

(definsn test (args mode)
         (cond ((and (eq (first args) 'al) (numberp (second args))) 2)  ; TEST AL, imm8
               (t 2))  ; TEST r8, r8
         (args labels origin buf mode)
  (let ((dst (first args)) (src (second args)))
    (cond
      ;; TEST AL, imm8  →  0xA8 imm8
      ((and (eq dst 'al) (numberp src))
       (push-byte buf #xa8)
       (push-byte buf (logand src #xff)))
      ;; TEST r8, r8  →  0x84 /r
      (t
       (push-byte buf #x84)
       (push-byte buf #xc0)))))

;;; ── MOV ─────────────────────────────────────────────────────────────────────

(defun mov-size (dst src mode)
  (cond
    ((and (r8-p dst)   (numberp src))                    2)
    ((and (r8-p dst)   (r8-p src))                       2)
    ((sreg-p dst)                       (if (= mode 16)  2  3))
    ((and (r16-p dst)  (numberp src))   (if (= mode 16)  3  4))
    ((and (r16-p dst)  (r16-p src))     (if (= mode 16)  2  3))
    ((and (r32-p dst)  (creg-p src))                     3)
    ((and (creg-p dst) (r32-p src))                      3)
    ((and (r32-p dst)  (r32-p src))                      2)
    ((and (r32-p dst)  (or (numberp src) (symbolp src)))  5)
    ((and (listp dst) (eq (car dst) 'mem32) (r32-p src)) 6)
    ((and (listp dst) (eq (car dst) 'mem32) (numberp src)) 10)
    ((and (r64-p dst) (or (numberp src) (symbolp src)))  10)
    (t (error "Unknown MOV: ~a ~a" dst src))))

(definsn mov (args mode)
         (mov-size (first args) (second args) mode)
         (args labels origin buf mode)
  (let ((dst (first args)) (src (second args)))
    (cond
      ((and (r8-p dst) (numberp src))
       (push-byte buf (+ #xb0 (enc *r8* dst)))
       (push-byte buf (logand src #xff)))
      ((and (r8-p dst) (r8-p src))
       (push-byte buf #x88)
       (push-byte buf (logior #xc0 (ash (enc *r8* src) 3) (enc *r8* dst))))
      ((sreg-p dst)
       (maybe-66 buf mode)
       (push-byte buf #x8e)
       (push-byte buf (logior #xc0 (ash (enc *sreg* dst) 3) (enc *r16* src))))
      ((and (r16-p dst) (numberp src))
       (maybe-66 buf mode)
       (push-byte buf (+ #xb8 (enc *r16* dst)))
       (push-u16 buf src))
      ((and (r16-p dst) (r16-p src))
       (maybe-66 buf mode)
       (push-byte buf #x89)
       (push-byte buf (logior #xc0 (ash (enc *r16* src) 3) (enc *r16* dst))))
      ((and (r32-p dst) (creg-p src))
       (push-byte buf #x0f) (push-byte buf #x20)
       (push-byte buf (logior #xc0 (ash (enc *creg* src) 3) (enc *r32* dst))))
      ((and (creg-p dst) (r32-p src))
       (push-byte buf #x0f) (push-byte buf #x22)
       (push-byte buf (logior #xc0 (ash (enc *creg* dst) 3) (enc *r32* src))))
      ((and (r32-p dst) (r32-p src))
       (push-byte buf #x89)
       (push-byte buf (logior #xc0 (ash (enc *r32* src) 3) (enc *r32* dst))))
      ((and (r32-p dst) (or (numberp src) (symbolp src)))
       (push-byte buf (+ #xb8 (enc *r32* dst)))
       (push-u32 buf (eval-expr src labels)))
      ((and (listp dst) (eq (car dst) 'mem32) (r32-p src))
       (push-byte buf #x89)
       (push-byte buf (logior #x05 (ash (enc *r32* src) 3)))
       (push-u32 buf (eval-expr (second dst) labels)))
      ((and (listp dst) (eq (car dst) 'mem32) (numberp src))
       (push-byte buf #xc7) (push-byte buf #x05)
       (push-u32 buf (eval-expr (second dst) labels))
       (push-u32 buf src))
      ((and (r64-p dst) (or (numberp src) (symbolp src)))
       (push-byte buf #x48)
       (push-byte buf (+ #xb8 (enc *r64* dst)))
       (push-u64 buf (eval-expr src labels))))))

;;; ── OR ──────────────────────────────────────────────────────────────────────

(definsn or (args mode)
         (cond ((and (r8-p  (first args)) (numberp (second args))) 2)
               ((and (r32-p (first args)) (numberp (second args))) 6)
               (t 2))
         (args labels origin buf mode)
  (let ((dst (first args)) (src (second args)))
    (cond
      ((and (r8-p dst) (eq dst 'al) (numberp src))
       (push-byte buf #x0c)                      ; OR AL, imm8
       (push-byte buf (logand src #xff)))
      ((and (r32-p dst) (numberp src))
       (push-byte buf #x81)
       (push-byte buf (logior #xc8 (enc *r32* dst)))
       (push-u32 buf src))
      ((and (r32-p dst) (r32-p src))
       (push-byte buf #x09)
       (push-byte buf (logior #xc0 (ash (enc *r32* src) 3) (enc *r32* dst)))))))

;;; ── LGDT ────────────────────────────────────────────────────────────────────

(definsn lgdt (args mode) 5
         (args labels origin buf mode)
  (let* ((label-name (caar args))
         (addr       (resolve labels label-name)))
    (push-byte buf #x0f) (push-byte buf #x01)
    (push-byte buf #x16)
    (push-u16 buf (logand addr #xffff))))

;;; ── IN ──────────────────────────────────────────────────────────────────────

;; (out port al) — OUT imm8, AL
(definsn out (args mode) 2
         (args labels origin buf mode)
  (push-byte buf #xe6)
  (push-byte buf (logand (first args) #xff)))

(definsn in (args mode) 2
         (args labels origin buf mode)
  (push-byte buf #xe4)
  (push-byte buf (logand (second args) #xff)))

;;; ── INT ─────────────────────────────────────────────────────────────────────

(definsn int (args mode) 2
         (args labels origin buf mode)
  (push-byte buf #xcd)
  (push-byte buf (logand (first args) #xff)))

;;; ── MOV-RDI-WORD ────────────────────────────────────────────────────────────

(definsn mov-rdi-word (args mode) 9
         (args labels origin buf mode)
  (push-byte buf #x66) (push-byte buf #xc7) (push-byte buf #x87)
  (push-u32 buf (first args))
  (push-u16 buf (second args)))

;;; ── Conditional jumps (always near = 6 bytes) ──────────────────────────────
;;; Use (jz-short label) for the 2-byte short form in tight code (Stage 1).

(macrolet ((cjmp-near (mnem short-op)
             (let ((near-op (+ short-op #x10)))
               `(definsn ,mnem (args mode) 6
                         (args labels origin buf mode)
                  (let* ((tgt (resolve labels (first args)))
                         (rel (- tgt (+ (cur-addr origin buf) 6))))
                    (push-byte buf #x0f)
                    (push-byte buf ,near-op)
                    (push-u32  buf (logand rel #xffffffff))))))
           (cjmp-short (mnem opcode)
             `(definsn ,mnem (args mode) 2
                       (args labels origin buf mode)
                (let* ((tgt (resolve labels (first args)))
                       (rel (- tgt (+ (cur-addr origin buf) 2))))
                  (unless (<= -128 rel 127)
                    (error "~a out of range to ~a (rel=~d)" ',mnem (first args) rel))
                  (push-byte buf ,opcode)
                  (push-byte buf (logand rel #xff))))))
  (cjmp-near jz   #x74)
  (cjmp-near jnz  #x75)
  (cjmp-near jc   #x72)
  (cjmp-near jnc  #x73)
  ;; Short variants for size-constrained code
  (cjmp-short jz-short  #x74)
  (cjmp-short jnz-short #x75)
  (cjmp-short jc-short  #x72)
  (cjmp-short jnc-short #x73))

;;; ── CMP ─────────────────────────────────────────────────────────────────────

;; (cmp8 al imm8)  →  0x3C imm8
(definsn cmp8 (args mode)
         (if (eq (first args) 'al) 2 3)    ; AL=2 bytes, CL=3 bytes
         (args labels origin buf mode)
  (cond
    ((eq (first args) 'al)
     (push-byte buf #x3c)                  ; CMP AL, imm8
     (push-byte buf (logand (second args) #xff)))
    ((eq (first args) 'cl)
     (push-byte buf #x80)                  ; CMP r/m8, imm8
     (push-byte buf #xf9)                  ; ModRM: mod=11 /7 r/m=CL
     (push-byte buf (logand (second args) #xff)))
    (t (error "CMP8 only supports AL or CL, got ~a" (first args)))))

;;; ── JNB / JAE (jump if not below = jump if carry clear) ────────────────────
;; Additional conditional jumps (always near).
(macrolet ((cjmp-near (mnem short-op)
             (let ((near-op (+ short-op #x10)))
               `(definsn ,mnem (args mode) 6
                         (args labels origin buf mode)
                  (let* ((tgt (resolve labels (first args)))
                         (rel (- tgt (+ (cur-addr origin buf) 6))))
                    (push-byte buf #x0f)
                    (push-byte buf ,near-op)
                    (push-u32  buf (logand rel #xffffffff)))))))
  (cjmp-near jge  #x7d)    ; jump if >=  (signed)
  (cjmp-near jle  #x7e)    ; jump if <=
  (cjmp-near ja   #x77)    ; jump if above (unsigned)
  (cjmp-near jbe  #x76))   ; jump if below or equal

;;; ── MOVZX ───────────────────────────────────────────────────────────────────

;; (movzx eax al)   →  0x0F 0xB6 0xC0   (r32←r8, mod=11)
(definsn movzx (args mode)
         (cond ((and (r32-p (first args)) (r8-p (second args))) 3)
               (t (error "Unknown MOVZX form: ~a ~a" (first args) (second args))))
         (args labels origin buf mode)
  (let ((dst (first args)) (src (second args)))
    (push-byte buf #x0f) (push-byte buf #xb6)
    (push-byte buf (logior #xc0 (ash (enc *r32* dst) 3) (enc *r8* src)))))

;;; ── ADD ──────────────────────────────────────────────────────────────────────

(definsn add (args mode)
         (cond ((and (r32-p (first args)) (r32-p (second args))) 2)
               ((and (r64-p (first args)) (r64-p (second args))) 3)  ; REX.W + 0x01
               (t (error "Unknown ADD form: ~a ~a" (first args) (second args))))
         (args labels origin buf mode)
  (let ((dst (first args)) (src (second args)))
    (cond
      ((and (r64-p dst) (r64-p src))
       (push-byte buf #x48)   ; REX.W
       (push-byte buf #x01)
       (push-byte buf (logior #xc0 (ash (enc *r64* src) 3) (enc *r64* dst))))
      (t
       (push-byte buf #x01)
       (push-byte buf (logior #xc0 (ash (enc *r32* src) 3) (enc *r32* dst)))))))

;;; ── IMUL (r32, imm32) ────────────────────────────────────────────────────────

;; (imul edx #xa0)  →  0x69 /r imm32  (3-operand: dst=dst, src=dst, imm)
(definsn imul (args mode) 6
         (args labels origin buf mode)
  (let ((dst (first args)) (imm (second args)))
    (push-byte buf #x69)
    (push-byte buf (logior #xc0 (ash (enc *r32* dst) 3) (enc *r32* dst)))
    (push-u32 buf imm)))

;;; ── INC ─────────────────────────────────────────────────────────────────────

;; (inc al)  →  0xFE /0  (INC r/m8, mod=11)
(definsn inc (args mode)
         (if (r8-p (first args)) 2 (error "Unknown INC form"))
         (args labels origin buf mode)
  (push-byte buf #xfe)
  (push-byte buf (logior #xc0 (enc *r8* (first args)))))

;;; ── PUSH / POP (r64) ─────────────────────────────────────────────────────────

;; (push-reg rax) → 0x50+r   (push-reg rbx) → 0x50+3 etc
(definsn push-reg (args mode) 1
         (args labels origin buf mode)
  (let ((reg (first args)))
    (push-byte buf (+ #x50 (if (r64-p reg) (enc *r64* reg) (enc *r32* reg))))))

;; (pop-reg rax) → 0x58+r
(definsn pop-reg (args mode) 1
         (args labels origin buf mode)
  (let ((reg (first args)))
    (push-byte buf (+ #x58 (if (r64-p reg) (enc *r64* reg) (enc *r32* reg))))))

;;; ── Byte operations via [RBX] ───────────────────────────────────────────────

;; (mov al (byte-at-rbx))  →  0x8A 0x03  (MOV AL, [RBX])
(definsn byte-load-al-rbx (args mode) 2
         (args labels origin buf mode)
  (push-byte buf #x8a) (push-byte buf #x03))

;; (movzx eax (byte-at-rbx))  →  0x0F 0xB6 0x03
(definsn byte-loadsx-eax-rbx (args mode) 3
         (args labels origin buf mode)
  (push-byte buf #x0f) (push-byte buf #xb6) (push-byte buf #x03))

;; (movzx ecx (byte-at-rbx))  →  0x0F 0xB6 0x0B
(definsn byte-loadsx-ecx-rbx (args mode) 3
         (args labels origin buf mode)
  (push-byte buf #x0f) (push-byte buf #xb6) (push-byte buf #x0b))

;; (movzx edx (byte-at-rbx))  →  0x0F 0xB6 0x13
(definsn byte-loadsx-edx-rbx (args mode) 3
         (args labels origin buf mode)
  (push-byte buf #x0f) (push-byte buf #xb6) (push-byte buf #x13))

;; (inc-byte-rbx)  →  0xFE 0x03  (INC BYTE PTR [RBX])
(definsn inc-byte-rbx (args mode) 2
         (args labels origin buf mode)
  (push-byte buf #xfe) (push-byte buf #x03))

;; (dec-byte-rbx)  →  0xFE 0x0B  (DEC BYTE PTR [RBX])
(definsn dec-byte-rbx (args mode) 2
         (args labels origin buf mode)
  (push-byte buf #xfe) (push-byte buf #x0b))

;; (store-zero-rbx)  →  0xC6 0x03 0x00  (MOV BYTE PTR [RBX], 0)
(definsn store-zero-rbx (args mode) 3
         (args labels origin buf mode)
  (push-byte buf #xc6) (push-byte buf #x03) (push-byte buf #x00))

;; (store-byte-rbx imm8)  →  0xC6 0x03 imm8  (MOV BYTE PTR [RBX], imm8)
(definsn store-byte-rbx (args mode) 3
         (args labels origin buf mode)
  (push-byte buf #xc6) (push-byte buf #x03) (push-byte buf (logand (first args) #xff)))

;;; ── VGA byte store: [RDI+EDX+disp8] ────────────────────────────────────────
;; Used to write char and attr bytes at computed VGA offsets.
;;
;; (store-rdi-edx-byte <disp8> <imm8>)
;; MOV BYTE PTR [RDI+EDX+disp8], imm8
;; 0xC6 ModRM(mod=01,reg=0,r/m=4) SIB(scale=0,idx=EDX,base=RDI) disp8 imm8
;; ModRM = 0x44, SIB = 0x17
(definsn store-rdi-edx-byte (args mode) 5
         (args labels origin buf mode)
  (let ((disp (first args)) (imm (second args)))
    (push-byte buf #xc6)
    (push-byte buf #x44)    ; ModRM: mod=01 reg=0 r/m=4(SIB)
    (push-byte buf #x17)    ; SIB: scale=0 idx=RDX(2) base=RDI(7)
    (push-byte buf (logand disp #xff))
    (push-byte buf (logand imm  #xff))))

;; (store-rdi-edx-al <disp8>)
;; MOV BYTE PTR [RDI+EDX+disp8], AL
;; 0x88 ModRM(mod=01,reg=0(AL),r/m=4) SIB disp8
(definsn store-rdi-edx-al (args mode) 4
         (args labels origin buf mode)
  (let ((disp (first args)))
    (push-byte buf #x88)
    (push-byte buf #x44)
    (push-byte buf #x17)
    (push-byte buf (logand disp #xff))))

;;; ── JMP ─────────────────────────────────────────────────────────────────────

(definsn jmp (args mode)
         (cond ((eq (first args) 'far)   (if (= mode 16) 5 7))
               ((eq (first args) 'abs)   (if (= mode 64) 5 3))
               ((eq (first args) 'short) 2)
               (t (error "Unknown JMP form")))
         (args labels origin buf mode)
  (cond
    ((eq (first args) 'far)
     (push-byte buf #xea)
     (if (= mode 16)
         (push-u16 buf (logand (resolve labels (third args)) #xffff))
         (push-u32 buf (logand (resolve labels (third args)) #xffffffff)))
     (push-u16 buf (logand (second args) #xffff)))
    ((eq (first args) 'abs)
     (let* ((instr-size (if (= mode 64) 5 3))
            (target (eval-expr (second args) labels))
            (rel    (- target (+ (cur-addr origin buf) instr-size))))
       (push-byte buf #xe9)
       (if (= mode 64)
           (push-u32 buf (logand rel #xffffffff))
           (push-u16 buf (logand rel #xffff)))))
    ((eq (first args) 'short)
     (let* ((tgt (resolve labels (second args)))
            (rel (- tgt (+ (cur-addr origin buf) 2))))
       (unless (<= -128 rel 127)
         (error "Short jump out of range to ~a (rel=~d)" (second args) rel))
       (push-byte buf #xeb)
       (push-byte buf (logand rel #xff))))))
