/* hello-aarch64.ld — Linker script for AArch64 userland programs
 * Load at 0x41000000 — just above the kernel at 0x40000000.
 */
OUTPUT_FORMAT("elf64-littleaarch64")
OUTPUT_ARCH(aarch64)
ENTRY(_start)

SECTIONS {
    . = 0x41000000;

    .text   : { *(.text*)   }
    .rodata : { *(.rodata*) }
    .data   : { *(.data*)   }
    .bss    : { *(.bss*)    }

    /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) }
}
