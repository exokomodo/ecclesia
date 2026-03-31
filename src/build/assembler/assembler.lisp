;;;; assembler.lisp — generic two-pass assembler
;;;;
;;;; Instructions are looked up in *instruction-table*, a hash table mapping
;;;; a mnemonic symbol to a descriptor of the form:
;;;;
;;;;   (size-fn emit-fn)
;;;;
;;;; where:
;;;;   size-fn  — (lambda (args mode)) → integer byte count
;;;;   emit-fn  — (lambda (args labels origin buf mode)) → nil (side effects buf)
;;;;
;;;; mode is the current bit width (16, 32, or 64), tracked via (bits N) forms.
;;;;
;;;; To add new instruction sets, call register-instruction for each mnemonic.

(in-package #:ecclesia.build)

;;; ── Instruction table ───────────────────────────────────────────────────────

(defvar *instruction-table* (make-hash-table)
  "Maps mnemonic symbol → (size-fn emit-fn).")

(defun register-instruction (mnemonic size-fn emit-fn)
  "Register an instruction encoding under MNEMONIC."
  (setf (gethash mnemonic *instruction-table*) (list size-fn emit-fn)))

(defun canonicalize-symbol (sym)
  "Intern SYM into the ecclesia.build package.
   Works for both mnemonics and register/operand symbols."
  (if (symbolp sym)
      (intern (symbol-name sym) '#:ecclesia.build)
      sym))

(defun canonicalize-mnemonic (sym)
  "Intern mnemonic SYM into ecclesia.build."
  (canonicalize-symbol sym))

(defun canonicalize-form (form)
  "Recursively canonicalize all symbols in a form."
  (cond
    ((symbolp form) (canonicalize-symbol form))
    ((listp form)   (mapcar #'canonicalize-form form))
    (t form)))

(defun lookup-instruction (mnemonic)
  (let ((canonical (canonicalize-mnemonic mnemonic)))
    (or (gethash canonical *instruction-table*)
        (error "Unknown instruction: ~a" mnemonic))))

;;; ── Expression evaluator ────────────────────────────────────────────────────

(defun eval-expr (expr labels)
  "Evaluate EXPR: integer → itself; symbol → label lookup;
   list (op args...) → apply op recursively."
  (cond
    ((integerp expr) expr)
    ((symbolp expr)
     (or (gethash (canonicalize-symbol expr) labels)
         (gethash expr labels)
         (error "Undefined label in expression: ~a" expr)))
    ((listp expr)
     (let ((op   (first expr))
           (args (mapcar (lambda (x) (eval-expr x labels)) (rest expr))))
       (case op
         (+ (reduce #'+ args))
         (- (if (cdr args) (reduce #'- args) (- (car args))))
         (* (reduce #'* args))
         (t (error "Unknown expression operator: ~a" op)))))
    (t (error "Cannot evaluate: ~a" expr))))

;;; ── Assembler mode ──────────────────────────────────────────────────────────

(defvar *asm-bits* 16
  "Current assembler bit mode. Updated by (bits N) forms.")

;;; ── Instruction size (pass 1) ───────────────────────────────────────────────

(defun instruction-size (form)
  "Return the byte size of FORM without emitting anything."
  (destructuring-bind (op &rest args) (canonicalize-form form)
    (case op
      ((org label) 0)
      (bits (setf *asm-bits* (first args)) 0)
      (t
       (let ((entry (lookup-instruction op)))
         (funcall (first entry) args *asm-bits*))))))

;;; ── Label collection (pass 1) ───────────────────────────────────────────────

(defun collect-labels (instructions origin)
  "Walk INSTRUCTIONS and return a hash-table mapping label names → addresses."
  (let ((labels    (make-hash-table))
        (offset    0)
        (*asm-bits* 16))
    (dolist (raw-form instructions)
      (let ((form (canonicalize-form raw-form)))
        (destructuring-bind (op &rest args) form
          (case op
            (org   (setf offset (- (first args) origin)))
            (bits  (setf *asm-bits* (first args)))
            (label (setf (gethash (first args) labels) (+ origin offset)))
            (t     (incf offset (instruction-size form)))))))
    labels))

;;; ── Byte emission (pass 2) ──────────────────────────────────────────────────

(defun emit-instruction (form labels origin buf)
  "Emit bytes for FORM into BUF."
  (destructuring-bind (op &rest args) (canonicalize-form form)
    (case op
      (bits  (setf *asm-bits* (first args)))
      ((org label) nil)
      (t
       (let ((entry (lookup-instruction op)))
         (funcall (second entry) args labels origin buf *asm-bits*))))))

;;; ── Public API ──────────────────────────────────────────────────────────────

(defun assemble (instructions)
  "Two-pass assemble INSTRUCTIONS into a (unsigned-byte 8) vector."
  (let* ((origin (or (loop for form in instructions
                           for cform = (canonicalize-form form)
                           when (eq (car cform) 'org)
                           return (cadr cform))
                     0))
         (labels     (collect-labels instructions origin))
         (*asm-bits* 16)
         (buf        (make-array 4096
                                 :element-type '(unsigned-byte 8)
                                 :fill-pointer 0
                                 :adjustable t)))
    (dolist (form instructions)
      (emit-instruction form labels origin buf))
    (subseq buf 0 (fill-pointer buf))))
