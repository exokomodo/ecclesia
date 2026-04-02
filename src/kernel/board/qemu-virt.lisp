;;;; board/qemu-virt.lisp — QEMU AArch64 virt machine

(in-package #:ecclesia.kernel.board)

(defclass qemu-virt (board) ())

(defmethod make-board ((target (eql :qemu-virt))) (make-instance 'qemu-virt))

(defmethod board-uart-base         ((b qemu-virt)) #x09000000)
(defmethod board-qemu-machine      ((b qemu-virt)) "virt")
(defmethod board-qemu-cpu          ((b qemu-virt)) "cortex-a57")
(defmethod board-kernel-load-address ((b qemu-virt)) #x40000000)
(defmethod board-stack-top         ((b qemu-virt)) #x40100000)
