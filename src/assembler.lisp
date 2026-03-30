;;;; assembler.lisp — x86-16 two-pass assembler (MBR-capable)
;;;;
;;;; Pass 1: walk instructions, record label addresses (using estimated sizes).
;;;; Pass 2: emit bytes with labels resolved.
;;;;
;;;; Supported forms:
;;;;   (org  <addr>)           — set origin
;;;;   (bits 16)               — accepted, no-op
;;;;   (db   <byte> ...)       — emit raw byte(s)
;;;;   (dw   <word>)           — emit 16-bit little-endian word
;;;;   (times <n> db <byte>)   — emit N copies of byte
;;;;   (label <name>)          — define label at current position
;;;;   (cli) (sti) (hlt)       — single-byte instructions
;;;;   (xor  <r16> <r16>)      — XOR reg, reg
;;;;   (mov  <dst> <src>)      — MOV (sreg←r16, r16←imm16, r16←r16)
;;;;   (int  <imm8>)           — INT imm8
;;;;   (jmp  short <label>)    — short relative jump (rel8)

(in-package #:ecclesia)

;;; ── Register encoding ──────────────────────────────────────────────────────

(defparameter *r16-encoding*
  '((ax . 0) (cx . 1) (dx . 2) (bx . 3)
    (sp . 4) (bp . 5) (si . 6) (di . 7)))

(defparameter *r8-encoding*
  '((al . 0) (cl . 1) (dl . 2) (bl . 3)
    (ah . 4) (ch . 5) (dh . 6) (bh . 7)))

(defparameter *sreg-encoding*
  '((es . 0) (cs . 1) (ss . 2) (ds . 3) (fs . 4) (gs . 5)))

(defun r16-enc (reg)
  (or (cdr (assoc reg *r16-encoding*))
      (error "Unknown r16 register: ~a" reg)))

(defun sreg-enc (reg)
  (cdr (assoc reg *sreg-encoding*)))

(defun sreg-p (sym) (not (null (assoc sym *sreg-encoding*))))
(defun r16-p  (sym) (not (null (assoc sym *r16-encoding*))))
(defun r8-p   (sym) (not (null (assoc sym *r8-encoding*))))
(defun r8-enc (reg) (or (cdr (assoc reg *r8-encoding*))
                        (error "Unknown r8 register: ~a" reg)))

;;; ── Instruction size estimation (pass 1) ──────────────────────────────────

(defun instruction-size (form)
  "Return the byte size of FORM without emitting anything."
  (destructuring-bind (op &rest args) form
    (case op
      ((bits org label) 0)
      (db    (length args))
      (dw    2)
      (times (destructuring-bind (n db-op byte) args
               (declare (ignore db-op byte))
               n))
      ((cli sti hlt lodsb lodsw)  1)
      ((test jz jnz)  2)
      (xor   2)                       ; 0x31 ModRM
      (mov
       (let ((dst (first args)) (src (second args)))
         (cond ((sreg-p dst) 2)       ; 0x8e ModRM
               ((and (r8-p dst) (numberp src)) 2)  ; 0xb0+r imm8
               ((numberp src) 3)      ; 0xb8+r imm16
               ((r16-p src)   2)      ; 0x89 ModRM
               (t (error "Unknown MOV: ~a ~a" dst src)))))
      (int   2)
      (jmp   2)                       ; 0xeb rel8
      (t (error "Unknown instruction (size): ~a" op)))))

;;; ── Pass 1: collect label addresses ───────────────────────────────────────

(defun collect-labels (instructions origin)
  "Walk INSTRUCTIONS and return a hash-table mapping label names → addresses."
  (let ((labels (make-hash-table))
        (offset 0))
    (dolist (form instructions)
      (destructuring-bind (op &rest args) form
        (case op
          (org (setf offset (- (first args) origin)))
          (label (setf (gethash (first args) labels) (+ origin offset)))
          (t (incf offset (instruction-size form))))))
    labels))

;;; ── Pass 2: emit bytes ─────────────────────────────────────────────────────

(defun emit-instruction (form labels origin buf)
  "Emit bytes for FORM into BUF (adjustable vector with fill-pointer).
   LABELS is the hash-table from pass 1. ORIGIN is the load address."
  (flet ((cur-addr () (+ origin (fill-pointer buf)))
         (push-byte (b) (vector-push-extend (logand b #xff) buf))
         (push-u16 (w)
           (vector-push-extend (logand w #xff) buf)
           (vector-push-extend (logand (ash w -8) #xff) buf)))
    (destructuring-bind (op &rest args) form
      (case op
        ((bits org label) nil)

        (db    (dolist (b args) (push-byte b)))
        (dw    (push-u16 (first args)))

        (times (destructuring-bind (n db-op byte) args
                 (declare (ignore db-op))
                 (dotimes (_ n) (push-byte byte))))

        (cli   (push-byte #xfa))
        (sti   (push-byte #xfb))
        (hlt   (push-byte #xf4))

        (xor
         (let ((dst (r16-enc (first args)))
               (src (r16-enc (second args))))
           (push-byte #x31)
           (push-byte (logior #xc0 (ash src 3) dst))))

        (mov
         (let ((dst (first args)) (src (second args)))
           (cond
             ((sreg-p dst)
              (push-byte #x8e)
              (push-byte (logior #xc0 (ash (sreg-enc dst) 3) (r16-enc src))))
             ;; MOV r8, imm8  →  0xb0+r imm8
           ((and (r8-p dst) (numberp src))
            (push-byte (+ #xb0 (r8-enc dst)))
            (push-byte (logand src #xff)))
           ;; MOV r16, imm16  →  0xb8+r imm16
           ((numberp src)
            (push-byte (+ #xb8 (r16-enc dst)))
            (push-u16 src))
             ((r16-p src)
              (push-byte #x89)
              (push-byte (logior #xc0 (ash (r16-enc src) 3) (r16-enc dst))))
             (t (error "Unsupported MOV: ~a ~a" dst src)))))

        ;; LODSB — load byte at DS:SI into AL, increment SI
        (lodsb (push-byte #xac))

        ;; LODSW — load word at DS:SI into AX, increment SI by 2
        (lodsw (push-byte #xad))

        ;; TEST AL, AL  (or TEST r8, r8 — we support only AL,AL for now)
        (test
         (when (and (eq (first args) 'al) (eq (second args) 'al))
           (push-byte #x84) (push-byte #xc0)))

        ;; JZ / JE  short label  →  0x74 rel8
        (jz
         (let* ((target (or (gethash (first args) labels)
                            (error "Undefined label: ~a" (first args))))
                (here   (+ (cur-addr) 2))
                (rel    (- target here)))
           (unless (<= -128 rel 127)
             (error "JZ out of range to ~a (rel=~d)" (first args) rel))
           (push-byte #x74) (push-byte (logand rel #xff))))

        ;; JNZ / JNE  short label  →  0x75 rel8
        (jnz
         (let* ((target (or (gethash (first args) labels)
                            (error "Undefined label: ~a" (first args))))
                (here   (+ (cur-addr) 2))
                (rel    (- target here)))
           (unless (<= -128 rel 127)
             (error "JNZ out of range to ~a (rel=~d)" (first args) rel))
           (push-byte #x75) (push-byte (logand rel #xff))))

        (int
         (push-byte #xcd)
         (push-byte (logand (first args) #xff)))

        (jmp
         ;; (jmp short <label>)
         (when (eq (first args) 'short)
           (let* ((target (or (gethash (second args) labels)
                              (error "Undefined label: ~a" (second args))))
                  (here   (+ (cur-addr) 2))
                  (rel    (- target here)))
             (unless (<= -128 rel 127)
               (error "Short jump out of range to ~a (rel=~d)" (second args) rel))
             (push-byte #xeb)
             (push-byte (logand rel #xff)))))

        (t (error "Unknown instruction: ~a" op))))))

;;; ── Public API ─────────────────────────────────────────────────────────────

(defun assemble (instructions)
  "Two-pass assemble INSTRUCTIONS into a (unsigned-byte 8) vector."
  ;; Determine origin from first (org ...) form, default 0
  (let ((origin (or (loop for form in instructions
                          when (eq (car form) 'org)
                          return (cadr form))
                    0)))
    (let ((labels (collect-labels instructions origin))
          (buf    (make-array 512
                              :element-type '(unsigned-byte 8)
                              :fill-pointer 0
                              :adjustable t)))
      (dolist (form instructions)
        (emit-instruction form labels origin buf))
      (subseq buf 0 (fill-pointer buf)))))
