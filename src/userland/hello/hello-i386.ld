/* hello-i386.ld — Linker script for i386 userland programs
 * Load at 0x400000 (4MB) — above kernel at 0x20000.
 */
OUTPUT_FORMAT("elf32-i386")
OUTPUT_ARCH(i386)
ENTRY(_start)

SECTIONS {
    . = 0x400000;

    .text   : { *(.text*)   }
    .rodata : { *(.rodata*) }
    .data   : { *(.data*)   }
    .bss    : { *(.bss*)    }

    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
