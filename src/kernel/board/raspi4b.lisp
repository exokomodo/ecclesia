;;;; board/raspi4b.lisp — Raspberry Pi 4 Model B

(in-package #:ecclesia.kernel.board)

(defclass raspi4b (board) ())

(defmethod make-board ((target (eql :raspi4b))) (make-instance 'raspi4b))

;;; RPi4 uses PL011 UART0 at 0xFE201000 (mapped from BCM2711 base 0xFE000000)
(defmethod board-uart-base         ((b raspi4b)) #xFE201000)
(defmethod board-qemu-machine      ((b raspi4b)) "raspi4b")
(defmethod board-qemu-cpu          ((b raspi4b)) nil)  ; QEMU picks Cortex-A72
(defmethod board-kernel-load-address ((b raspi4b)) #x80000)
(defmethod board-stack-top         ((b raspi4b)) #x80000000)
