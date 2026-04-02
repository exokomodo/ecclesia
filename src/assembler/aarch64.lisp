;;;; aarch64.lisp — AArch64 instruction encodings for the Ecclesia assembler
;;;;
;;;; Implements the subset needed for the AArch64 boot chain:
;;;;   MOV  Xn, #imm16             (MOVZ — zero-extended 16-bit immediate)
;;;;   MOVK Xn, #imm16, LSL shift  (keep other bits, insert imm16 at shift)
;;;;   STRB Wn, [Xm]               (store byte, base register only)
;;;;   LDR  Xn, [Xm]               (load 64-bit register from base)
;;;;   BR   Xn                     (branch to register)
;;;;   B    label                  (unconditional branch, PC-relative)
;;;;   BL   label                  (branch with link)
;;;;   CBZ  Xn, label              (compare and branch if zero)
;;;;   CBNZ Xn, label              (compare and branch if non-zero)
;;;;   ADD  Xn, Xm, #imm12         (add immediate)
;;;;   SUB  Xn, Xm, #imm12         (subtract immediate)
;;;;   CMP  Xn, #imm12             (compare, alias for SUBS XZR, Xn, #imm)
;;;;   RET                         (return, alias for BR X30)
;;;;   NOP                         (no operation)

(in-package #:ecclesia.assembler)

;;; ── Register tables ──────────────────────────────────────────────────────────

(defparameter *r64-aa*
  '((x0 . 0)  (x1 . 1)  (x2 . 2)  (x3 . 3)
    (x4 . 4)  (x5 . 5)  (x6 . 6)  (x7 . 7)
    (x8 . 8)  (x9 . 9)  (x10 . 10) (x11 . 11)
    (x12 . 12) (x13 . 13) (x14 . 14) (x15 . 15)
    (x16 . 16) (x17 . 17) (x18 . 18) (x19 . 19)
    (x20 . 20) (x21 . 21) (x22 . 22) (x23 . 23)
    (x24 . 24) (x25 . 25) (x26 . 26) (x27 . 27)
    (x28 . 28) (x29 . 29) (x30 . 30) (xzr . 31)
    (sp . 31)))

(defparameter *r32-aa*
  '((w0 . 0)  (w1 . 1)  (w2 . 2)  (w3 . 3)
    (w4 . 4)  (w5 . 5)  (w6 . 6)  (w7 . 7)
    (w8 . 8)  (w9 . 9)  (w10 . 10) (w11 . 11)
    (w12 . 12) (w13 . 13) (w14 . 14) (w15 . 15)
    (w16 . 16) (w17 . 17) (w18 . 18) (w19 . 19)
    (w20 . 20) (w21 . 21) (w22 . 22) (w23 . 23)
    (w24 . 24) (w25 . 25) (w26 . 26) (w27 . 27)
    (w28 . 28) (w29 . 29) (w30 . 30) (wzr . 31)))

(defun aa-r64-p (s) (not (null (assoc s *r64-aa*))))
(defun aa-r32-p (s) (not (null (assoc s *r32-aa*))))

(defun enc-r64 (reg)
  (or (cdr (assoc reg *r64-aa*))
      ;; Accept W registers as aliases (same encoding, context determines width)
      (cdr (assoc reg *r32-aa*))
      (error "Unknown AArch64 X register: ~a" reg)))

(defun enc-r32 (reg)
  (or (cdr (assoc reg *r32-aa*))
      ;; Accept X registers as aliases
      (cdr (assoc reg *r64-aa*))
      (error "Unknown AArch64 W register: ~a" reg)))

;;; ── Emit helpers ─────────────────────────────────────────────────────────────

(defun push-u32-le (buf val)
  "Emit a 32-bit little-endian word (all AArch64 instructions are 32 bits)."
  (loop for shift from 0 to 24 by 8
        do (push-byte buf (logand (ash val (- shift)) #xff))))

;;; ── Instruction encodings ────────────────────────────────────────────────────

;;; MOV Xn, #imm  — encoded as MOVZ Xd, #imm16, LSL 0
;;; Also handles large immediates via MOVZ + MOVK pairs.
;;;
;;; MOVZ:  sf(1) opc(10) 100101 hw(2) imm16(16) Rd(5)

(defun encode-movz (rd imm hw)
  "MOVZ Xd, #imm16, LSL (hw*16). hw ∈ {0,1,2,3}."
  (logior (ash 1 31)            ; sf = 1 (64-bit)
          (ash #b10 29)         ; opc = 10
          (ash #b100101 23)
          (ash hw 21)
          (ash (logand imm #xffff) 5)
          rd))

(defun encode-movk (rd imm hw)
  "MOVK Xd, #imm16, LSL (hw*16). hw ∈ {0,1,2,3}."
  (logior (ash 1 31)
          (ash #b11 29)         ; opc = 11
          (ash #b100101 23)
          (ash hw 21)
          (ash (logand imm #xffff) 5)
          rd))

(defun aa-movz-size (src)
  "Number of bytes needed to load SRC into an X register (MOVZ + MOVKs)."
  (let ((hw1 (logand (ash src -16) #xffff))
        (hw2 (logand (ash src -32) #xffff))
        (hw3 (logand (ash src -48) #xffff)))
    (* 4 (+ 1
            (if (zerop hw1) 0 1)
            (if (zerop hw2) 0 1)
            (if (zerop hw3) 0 1)))))

(defun aa-movz-emit (buf rd src &key fixed-size)
  "Emit MOVZ + optional MOVKs to load SRC into X register Rd.
   When FIXED-SIZE is true, always emit 4 instructions (pad with NOPs)
   so that size is constant regardless of the immediate value."
  (let ((hw0 (logand src #xffff))
        (hw1 (logand (ash src -16) #xffff))
        (hw2 (logand (ash src -32) #xffff))
        (hw3 (logand (ash src -48) #xffff))
        (count 0))
    (push-u32-le buf (encode-movz rd hw0 0)) (incf count)
    (if (or fixed-size (not (zerop hw1)))
        (progn (push-u32-le buf (encode-movk rd hw1 1)) (incf count)))
    (if (or fixed-size (not (zerop hw2)))
        (progn (push-u32-le buf (encode-movk rd hw2 2)) (incf count)))
    (if (or fixed-size (not (zerop hw3)))
        (progn (push-u32-le buf (encode-movk rd hw3 3)) (incf count)))
    ;; Pad to 4 instructions if fixed-size requested
    (when fixed-size
      (loop while (< count 4)
            do (push-u32-le buf #xd503201f) ; NOP
               (incf count)))))

;;; Register a new mnemonic MOVX (MOV for AArch64 X registers) to avoid
;;; colliding with the x86 MOV in the global instruction table.
;;; stage2-aarch64.lisp uses MOVX internally; we alias MOV→MOVX at load time
;;; via the package-level dispatch in the kernel interface.

(register-instruction 'movx
  (lambda (args mode)
    (declare (ignore mode))
    (let ((dst (first args))
          (src (second args)))
      (cond
        ((and (aa-r64-p dst) (integerp src)) (aa-movz-size src))
        ;; Label reference — worst case 4 instructions (MOVZ + 3 MOVK) for 64-bit addr
        ((and (aa-r64-p dst) (symbolp src))  16)
        (t (error "Unknown MOVX form: ~a ~a" dst src)))))
  (lambda (args labels origin buf mode)
    (declare (ignore mode))
    (let* ((dst (first args))
           (src (second args))
           (sym-p (symbolp src))
           (val   (if sym-p (eval-expr src labels) src)))
      (cond
        ((aa-r64-p dst)
         (aa-movz-emit buf (enc-r64 dst) val :fixed-size sym-p))
        (t (error "Unknown MOVX emit: ~a ~a" dst src))))))

;;; STRB Wn, [Xm] — store byte, unscaled offset 0
;;; Encoding: size(00) 111 0 00 0 imm9(0) 0 1 Rn Rt
;;; Unsigned offset variant: 00 111 001 00 imm12(0) Rn Rt
;;; We use the simpler unsigned-offset form with offset=0.

(register-instruction 'strb
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((src  (first args))
           (addr (second args))          ; (mem Xbase [offset])
           (base (if (listp addr) (second (canonicalize-form addr)) addr))
           (rt   (if (aa-r32-p src) (enc-r32 src) (enc-r64 src)))
           (rn   (enc-r64 base))
           ;; STRB Wt, [Xn, #0] — unsigned offset, imm12=0
           (enc  (logior (ash #b00 30)      ; size = 00
                         (ash #b111 27)
                         (ash #b01 24)
                         (ash 0 10)         ; imm12 = 0
                         (ash rn 5)
                         rt)))
      (push-u32-le buf enc))))

;;; BR Xn — branch to register
;;; Encoding: 1101011 0000 11111 000000 Rn 00000

(register-instruction 'br
  (lambda (args mode)
    (declare (ignore mode))
    (if (aa-r64-p (first args)) 4
        (error "BR requires an X register")))
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rn  (enc-r64 (first args)))
           (enc (logior #xd61f0000 (ash rn 5))))
      (push-u32-le buf enc))))

;;; B label — unconditional branch (PC-relative, ±128MB)
;;; Encoding: 0 00101 imm26

(register-instruction 'b
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore mode))
    (let* ((target (eval-expr (first args) labels))
           (pc     (+ origin (fill-pointer buf)))
           (rel    (ash (- target pc) -2))  ; word offset
           (enc    (logior #x14000000 (logand rel #x3ffffff))))
      (push-u32-le buf enc))))

;;; BL label — branch with link
;;; Encoding: 1 00101 imm26

(register-instruction 'bl
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore mode))
    (let* ((target (eval-expr (first args) labels))
           (pc     (+ origin (fill-pointer buf)))
           (rel    (ash (- target pc) -2))
           (enc    (logior #x94000000 (logand rel #x3ffffff))))
      (push-u32-le buf enc))))

;;; CBZ Xn, label — compare and branch if zero
;;; Encoding: sf(1) 0110100 imm19 Rt

(register-instruction 'cbz
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore mode))
    (let* ((rn     (enc-r64 (first args)))
           (target (eval-expr (second args) labels))
           (pc     (+ origin (fill-pointer buf)))
           (rel    (ash (- target pc) -2))
           (enc    (logior #xb4000000
                           (ash (logand rel #x7ffff) 5)
                           rn)))
      (push-u32-le buf enc))))

;;; CBNZ Xn, label
;;; Encoding: sf(1) 0110101 imm19 Rt

(register-instruction 'cbnz
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore mode))
    (let* ((rn     (enc-r64 (first args)))
           (target (eval-expr (second args) labels))
           (pc     (+ origin (fill-pointer buf)))
           (rel    (ash (- target pc) -2))
           (enc    (logior #xb5000000
                           (ash (logand rel #x7ffff) 5)
                           rn)))
      (push-u32-le buf enc))))

;;; ADD Xd, Xn, #imm12
;;; Encoding: 1 0001011 00 imm12 Rn Rd

(register-instruction 'add-imm
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rd   (enc-r64 (first args)))
           (rn   (enc-r64 (second args)))
           (imm  (third args))
           (enc  (logior #x91000000
                         (ash (logand imm #xfff) 10)
                         (ash rn 5)
                         rd)))
      (push-u32-le buf enc))))

;;; SUB Xd, Xn, #imm12
;;; Encoding: 1 1001011 00 imm12 Rn Rd

(register-instruction 'sub-imm
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rd   (enc-r64 (first args)))
           (rn   (enc-r64 (second args)))
           (imm  (third args))
           (enc  (logior #xd1000000
                         (ash (logand imm #xfff) 10)
                         (ash rn 5)
                         rd)))
      (push-u32-le buf enc))))

;;; LDRB Wt, [Xn] — load byte, unsigned offset 0
;;; Encoding: 00 111 001 01 imm12(0) Rn Rt

(register-instruction 'ldrb
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((dst  (first args))
           (addr (second args))
           (base (if (listp addr) (second (canonicalize-form addr)) addr))
           (rt   (if (aa-r32-p dst) (enc-r32 dst) (enc-r64 dst)))
           (rn   (enc-r64 base))
           (enc  (logior (ash #b00 30)
                         (ash #b111 27)
                         (ash #b01 24)
                         (ash #b01 22)   ; opc = 01 (load)
                         (ash 0 10)
                         (ash rn 5)
                         rt)))
      (push-u32-le buf enc))))

;;; TST Wn, #imm — test bits (ANDS WZR, Wn, #imm)
;;; Use a simple immediate AND form. For our purposes (bit 4 = 0x10),
;;; encode ANDS (32-bit) with immediate bitmask.
;;; Encoding: 0 11 100100 N immr imms Rn Rd(WZR=31)

(defun encode-logical-imm-32 (imm)
  "Encode a 32-bit logical immediate. Returns (N immr imms) or NIL if not encodable.
   We handle simple power-of-two masks only for now."
  ;; For a single-bit mask like 0x10 = bit 4:
  ;; imms = bit_width - 1 = 0 (for 1-bit element), immr = rotation
  ;; Simplified: for 0x10 we need element size 32, one bit set.
  ;; Use the generic formula for a single 1-bit run.
  (let* ((bit (loop for i from 0 below 32
                    when (logbitp i imm) return i))
         (width (loop for i from 0 below 32
                      count (logbitp i imm))))
    (when (and bit width (= width 1))
      ;; Single bit set at position BIT
      ;; N=0, immr=(32-bit) mod 32, imms=0 (one bit wide - 1)
      (list 0 (mod (- 32 bit) 32) 0))))

(register-instruction 'tst-imm
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rn   (enc-r32 (first args)))
           (imm  (second args))
           (enc-parts (encode-logical-imm-32 imm)))
      (unless enc-parts (error "TST-IMM: unencodable immediate #x~x" imm))
      (destructuring-bind (n immr imms) enc-parts
        (let ((enc (logior (ash #b0 31)        ; sf=0 (32-bit)
                           (ash #b11 29)       ; opc=11 (ANDS)
                           (ash #b100100 23)
                           (ash n 22)
                           (ash immr 16)
                           (ash imms 10)
                           (ash rn 5)
                           31)))               ; Rd = WZR
          (push-u32-le buf enc))))))

;;; BNE label — branch if not equal (Z=0)
;;; Encoding: 0101010 0 cond(0001) imm19 0

(register-instruction 'bne
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore mode))
    (let* ((target (eval-expr (first args) labels))
           (pc     (+ origin (fill-pointer buf)))
           (rel    (ash (- target pc) -2))
           (enc    (logior #x54000001        ; B.NE
                           (ash (logand rel #x7ffff) 5))))
      (push-u32-le buf enc))))

;;; BEQ label — branch if equal (Z=1)

(register-instruction 'beq
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore mode))
    (let* ((target (eval-expr (first args) labels))
           (pc     (+ origin (fill-pointer buf)))
           (rel    (ash (- target pc) -2))
           (enc    (logior #x54000000        ; B.EQ
                           (ash (logand rel #x7ffff) 5))))
      (push-u32-le buf enc))))

;;; CMP-REG Wn, Wm — compare registers (SUBS WZR, Wn, Wm)
;;; Encoding: 0 1101011 00 0 Rm 000000 Rn 11111

(register-instruction 'cmp-reg
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rn  (enc-r32 (first args)))
           (rm  (enc-r32 (second args)))
           (enc (logior #x6B00001F
                        (ash rm 16)
                        (ash rn 5))))
      (push-u32-le buf enc))))

;;; CMP-IMM Wn, #imm12 — compare (SUBS WZR, Wn, #imm12)
;;; Encoding: 0 1 1 0001011 shift(00) imm12 Rn Rd(WZR=31)

(register-instruction 'cmp-imm
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rn  (enc-r32 (first args)))
           (imm (second args))
           (enc (logior #x71000000           ; SUBS W WZR, Wn, #imm
                        (ash (logand imm #xfff) 10)
                        (ash rn 5)
                        31)))
      (push-u32-le buf enc))))

;;; MOVSP Xn — move Xn into SP (MOV SP, Xn = ADD SP, Xn, #0)
;;; Encoding: 1 0 0 10001 00 000000000000 Xn SP(31)

(register-instruction 'movsp
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rn  (enc-r64 (first args)))
           (enc (logior #x91000000           ; ADD (64-bit, imm=0)
                        (ash 0 10)           ; imm12=0
                        (ash rn 5)
                        31)))               ; Rd = SP
      (push-u32-le buf enc))))

;;; UDIV Wd, Wn, Wm — unsigned divide (32-bit)
;;; Encoding: 0 00 11010110 Rm 000011 Rn Rd

(register-instruction 'udiv
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rd (enc-r32 (first args)))
           (rn (enc-r32 (second args)))
           (rm (enc-r32 (third args)))
           (enc (logior #x1AC00C00 (ash rm 16) (ash rn 5) rd)))
      (push-u32-le buf enc))))

;;; MSUB Wd, Wn, Wm, Wa — Wd = Wa - Wn*Wm (32-bit)
;;; Encoding: 0 00 11011 000 Rm 1 Ra Rn Rd

(register-instruction 'msub
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore labels origin mode))
    (let* ((rd (enc-r32 (first args)))
           (rn (enc-r32 (second args)))
           (rm (enc-r32 (third args)))
           (ra (enc-r32 (fourth args)))
           (enc (logior #x1B008000 (ash rm 16) (ash ra 10) (ash rn 5) rd)))
      (push-u32-le buf enc))))

;;; Additional conditional branches (B.cond variants)

(defun make-bcond (base-enc)
  (list
   (lambda (args mode) (declare (ignore args mode)) 4)
   (lambda (args labels origin buf mode)
     (declare (ignore mode))
     (let* ((target (eval-expr (first args) labels))
            (pc     (+ origin (fill-pointer buf)))
            (rel    (ash (- target pc) -2))
            (enc    (logior base-enc (ash (logand rel #x7ffff) 5))))
       (push-u32-le buf enc)))))

;; BLT — branch if less than (signed, N≠V)
(apply #'register-instruction 'blt (make-bcond #x5400000b))
;; BGE — branch if greater or equal (signed, N=V)
(apply #'register-instruction 'bge (make-bcond #x5400000a))
;; BHI — branch if higher (unsigned, C=1 and Z=0)
(apply #'register-instruction 'bhi (make-bcond #x54000008))
;; BLS — branch if lower or same (unsigned, C=0 or Z=1)
(apply #'register-instruction 'bls (make-bcond #x54000009))
;; BHS/BCS — branch if higher or same (unsigned ≥, C=1)
(apply #'register-instruction 'bhs (make-bcond #x54000002))
;; BLO/BCC — branch if lower (unsigned <, C=0)
(apply #'register-instruction 'blo (make-bcond #x54000003))

;;; RET — return (alias for BR X30)

(register-instruction 'ret
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore args labels origin mode))
    (push-u32-le buf #xd65f03c0)))   ; BR X30

;;; NOP

(register-instruction 'nop
  (lambda (args mode) (declare (ignore args mode)) 4)
  (lambda (args labels origin buf mode)
    (declare (ignore args labels origin mode))
    (push-u32-le buf #xd503201f)))
