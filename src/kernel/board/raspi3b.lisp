;;;; board/raspi3b.lisp — Raspberry Pi 3 Model B

(in-package #:ecclesia.kernel.board)

(defclass raspi3b (board) ())

(defmethod make-board ((target (eql :raspi3b))) (make-instance 'raspi3b))

;;; RPi3 uses mini-UART (AUX) by default; PL011 is at 0x3F201000
;;; We target PL011 (UART0) — requires config.txt: dtoverlay=disable-bt
(defmethod board-uart-base         ((b raspi3b)) #x3F201000)
(defmethod board-qemu-machine      ((b raspi3b)) "raspi3b")
(defmethod board-qemu-cpu          ((b raspi3b)) nil)  ; QEMU picks Cortex-A53
(defmethod board-kernel-load-address ((b raspi3b)) #x80000)
(defmethod board-stack-top         ((b raspi3b)) #x40000000)
