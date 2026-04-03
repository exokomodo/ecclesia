/* hello.c — First userland program for Ecclesia
 * Writes "Hello from userland!" to VGA text buffer at 0xB8000, row 6.
 * No libc — bare metal, static ELF64.
 */

#define VGA_BASE  ((volatile unsigned short *)0xB8000)
#define VGA_COLS  80
#define VGA_ATTR  0x0A00   /* bright green on black */

static const char msg[] = "Hello from userland!";

void _start(void) {
    volatile unsigned short *vga = VGA_BASE + (6 * VGA_COLS);
    for (int i = 0; msg[i]; i++) {
        vga[i] = VGA_ATTR | (unsigned char)msg[i];
    }
    /* Return to kernel — loader uses CALL so RET returns to kbd-main-loop */
}
