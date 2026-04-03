/* hello.ld — Linker script for Ecclesia userland programs
 * Load at 0x400000 (4MB) — above kernel at 0x100000, below ELF scratch area.
 */
OUTPUT_FORMAT("elf64-x86-64")
OUTPUT_ARCH(i386:x86-64)
ENTRY(_start)

SECTIONS {
    . = 0x400000;

    .text   : { *(.text*)   }
    .rodata : { *(.rodata*) }
    .data   : { *(.data*)   }
    .bss    : { *(.bss*)    }

    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
