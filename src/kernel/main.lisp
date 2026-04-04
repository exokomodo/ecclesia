;;;; main.lisp — Ecclesia kernel entry (ECL-compiled to freestanding ELF)

;;; VGA helpers (freestanding, no libc — use FFI to access 0xB8000 directly)

(defconstant +vga-base+ #xB8000)
(defconstant +vga-cols+ 80)
(defconstant +vga-rows+ 25)
(defconstant +vga-attr-white+ #x0F00)  ;; bright white on black
(defconstant +vga-attr-cyan+  #x0B00)  ;; bright cyan on black
(defconstant +vga-attr-gray+  #x0700)  ;; light gray on black

(defun vga-addr (row col)
  "Get VGA memory address for row/col."
  (sys:ffi-inline ((row :int) (col :int))
                  (:pointer :unsigned-short)
                  "((unsigned short *)0xB8000) + row * 80 + col"))

(defun vga-clear ()
  "Clear VGA screen to spaces with light gray attribute."
  (sys:ffi-inline ()
                  (:void)
                  "{
    volatile unsigned short *vga = (volatile unsigned short *)0xB8000;
    for (int i = 0; i < 80 * 25; i++) {
      vga[i] = 0x0700 | ' ';
    }
  }"))

(defun vga-write (s row col attr)
  "Write string S to VGA at ROW/COL with ATTR."
  (sys:ffi-inline ((s :cstring) (row :int) (col :int) (attr :unsigned-short))
                  (:void)
                  "{
    volatile unsigned short *vga = ((volatile unsigned short *)0xB8000) + row * 80 + col;
    while (*s) {
      *vga++ = attr | (unsigned char)*s++;
    }
  }"))

(defun halt ()
  "Halt the CPU indefinitely."
  (sys:ffi-inline () (:void) "{ __asm__ volatile (\"hlt\"); }"))

(defun kernel-main ()
  ;; Stub: clear VGA, print banner, halt
  (vga-clear)
  (vga-write "Ecclesia" 0 0 +vga-attr-cyan+)
  (vga-write "v0.1" 0 9 +vga-attr-white+)
  (vga-write "Booted." 1 0 +vga-attr-gray+)
  (loop (halt)))