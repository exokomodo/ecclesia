/* hello.c — Ecclesia first-stage program
 *
 * This is the first code that runs after the bootloader hands off control.
 * It writes a boot banner to VGA text mode and halts.
 *
 * Freestanding — no libc, no dynamic linking.
 */

#define VGA_BASE   ((volatile unsigned short *)0xB8000)
#define VGA_COLS   80
#define ATTR_WHITE 0x0F00   /* bright white on black */
#define ATTR_CYAN  0x0B00   /* bright cyan on black  */
#define ATTR_GRAY  0x0700   /* light gray on black   */

static void vga_write(const char *s, int row, int col, unsigned short attr) {
    volatile unsigned short *vga = VGA_BASE + row * VGA_COLS + col;
    while (*s)
        *vga++ = attr | (unsigned char)*s++;
}

static void vga_clear(void) {
    volatile unsigned short *vga = VGA_BASE;
    for (int i = 0; i < VGA_COLS * 25; i++)
        *vga++ = 0x0700 | ' ';
}

void _start(void) {
    vga_clear();

    vga_write("Ecclesia",          0,  0, ATTR_CYAN);
    vga_write("v0.1",              0,  9, ATTR_WHITE);
    vga_write("Booted.",           1,  0, ATTR_GRAY);

    /* halt */
    while (1)
        __asm__ volatile ("hlt");
}
