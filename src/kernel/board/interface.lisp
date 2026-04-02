;;;; board/interface.lisp — Board abstraction generics
;;;;
;;;; A "board" is the physical (or emulated) hardware platform independent of
;;;; the ISA. It captures things like UART base address, QEMU machine name,
;;;; memory layout, and eventually interrupt controller type.
;;;;
;;;; The ISA and board are orthogonal: the same AArch64 ISA can target a
;;;; Raspberry Pi 4, a Raspberry Pi 3, or QEMU's virt machine.

(in-package #:ecclesia.kernel.board)

(defclass board () ()
  (:documentation "Base class for all target boards."))

;;; ── Board registry ───────────────────────────────────────────────────────────

(defgeneric make-board (target)
  (:documentation
   "Return a board instance for TARGET keyword (e.g. :qemu-virt, :raspi4b)."))

;;; ── UART ─────────────────────────────────────────────────────────────────────

(defgeneric board-uart-base (board)
  (:documentation
   "Physical base address of the primary UART (PL011 or equivalent)."))

;;; ── QEMU integration ─────────────────────────────────────────────────────────

(defgeneric board-qemu-machine (board)
  (:documentation
   "QEMU -machine argument string for this board (e.g. \"virt\", \"raspi4b\")."))

(defgeneric board-qemu-cpu (board)
  (:documentation
   "QEMU -cpu argument string, or NIL to use QEMU's default for the machine."))

;;; ── Memory layout ────────────────────────────────────────────────────────────

(defgeneric board-kernel-load-address (board)
  (:documentation
   "Physical address where the kernel binary is loaded by firmware/QEMU."))

(defgeneric board-stack-top (board)
  (:documentation
   "Initial stack pointer address for the kernel."))
