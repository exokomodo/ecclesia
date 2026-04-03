# Ecclesia Userland

This directory contains programs that run in userland — outside the kernel, loaded and executed by the static ELF loader.

---

## How It Works

### The Boot Pipeline

```
Floppy disk layout (1.44MB):
  Sector 1       (byte     0): Stage 1 MBR         — 512 bytes
  Sectors 2-9   (byte   512): Stage 2              — up to 4KB
  Sectors 10-17 (byte  4608): Kernel               — up to 4KB
  Sectors 18-33 (byte  8704): ELF binary           — up to 8KB (16 sectors)
```

1. **Stage 1** (MBR, 512 bytes) loads Stage 2 and the kernel into low memory via BIOS INT 13h.

2. **Stage 2** runs in real mode, loads the ELF binary from sectors 18-33 into physical `0x30000`, then enters protected mode (x86_64 also enters long mode). In protected mode it copies the ELF from `0x30000` to `0x300000` via `REP MOVSD`, then jumps to the kernel.

3. **Kernel** runs the keyboard loop. When the user presses **Escape**, it invokes the ELF loader.

4. **ELF Loader** (in `src/loader/`) parses the ELF binary at `0x300000`, copies each `PT_LOAD` segment to its virtual address, zeros BSS, sets up a userland stack at `0x500000`, then `CALL`s the entry point. When `_start` returns, the loader restores the kernel stack and resumes the keyboard loop.

### Why CALL not JMP?

Using `CALL` instead of `JMP` allows `_start` to `RET` back to the kernel. `JMP` discards the return address — `_start` has no way home. This means userland programs can return to the shell without the whole OS crashing.

---

## Writing a Userland Program

### Directory Structure

Each program lives in its own folder:

```
src/userland/<name>/
  <name>.c          — C source (no libc, no stdlib)
  <name>-x86_64.ld  — linker script for x86-64
  <name>-aarch64.ld — linker script for AArch64
```

### Linker Scripts

The linker script defines where the program loads in virtual memory. Each arch has its own load address to avoid collisions with the kernel and ELF scratch area:

| ISA      | Load address | Rationale                              |
|----------|-------------|----------------------------------------|
| x86_64   | `0x400000`  | 4MB — above kernel at `0x100000`       |
| AArch64  | `0x41000000`| Just above kernel at `0x40000000`      |

The load address must be within the kernel's identity-mapped page tables. For x86_64, Stage 2 maps the first 16MB (0x0 to 0xFFFFFF), so `0x400000` is safely within range.

**Template (x86_64):**

```ld
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
```

### C Source Rules

Programs must be **fully freestanding** — no libc, no runtime, no OS:

```c
void _start(void) {
    // ... do work ...
    // Return normally — loader uses CALL so this RET goes back to the kernel.
}
```

Key rules:
- **No `#include <stdio.h>` etc.** — no standard library exists
- **No `main()`** — the entry point is `_start`
- **No global constructors** — `.init_array` / `.ctors` are not called
- **No exceptions** — no unwinding, no `__cxa_` anything
- **No dynamic linking** — static ELF only (`-static`)
- **No stack protector** — no `__stack_chk_fail` (`-fno-stack-protector`)
- **Always return from `_start`** — do not `hlt` or spin forever

**Accessing hardware directly** (example — VGA on x86):

```c
#define VGA_BASE  ((volatile unsigned short *)0xB8000)
#define VGA_COLS  80
#define VGA_ATTR  0x0A00   /* bright green on black */

void _start(void) {
    volatile unsigned short *vga = VGA_BASE + (6 * VGA_COLS);
    const char *msg = "Hello from userland!";
    for (int i = 0; msg[i]; i++) {
        vga[i] = VGA_ATTR | (unsigned char)msg[i];
    }
}
```

### Adding Build Targets to the Makefile

Add three targets (one per arch) to the `##@ Userland` section:

```makefile
build/<name>-x86_64.elf: src/userland/<name>/<name>.c src/userland/<name>/<name>-x86_64.ld
	mkdir -p build
	@if [ -z "$(CC_x86_64)" ]; then \
	    echo "[ecclesia] Skipping <name> x86_64 — no cross-compiler"; \
	elif $(CC_x86_64) $(USERLAND_CFLAGS) -T src/userland/<name>/<name>-x86_64.ld -o $@ $< 2>/dev/null; then \
	    echo "[ecclesia] Compiled $@ ($$(wc -c < $@) bytes)"; \
	else \
	    echo "[ecclesia] Skipping <name> x86_64 — compilation failed"; \
	fi
```

Also add your target to `userland` and `userland/all`:

```makefile
userland: build/hello-$(TARGET_ARCH).elf build/<name>-$(TARGET_ARCH).elf

userland/all: build/hello-x86_64.elf build/hello-aarch64.elf \
              build/<name>-x86_64.elf build/<name>-aarch64.elf
```

### Choosing Which ELF to Load

Currently the kernel always loads `build/hello-<arch>.elf`. To load a different program, update `write-kernel.lisp` to embed the desired ELF, or extend the loader to support multiple ELFs (see Future Work below).

---

## Pitfalls We Hit (and How We Fixed Them)

### 1. `hlt` in `_start` hangs everything

**Symptom:** Pressing ESC froze the OS permanently.

**Cause:** `_start` was spinning with `while(1){}` or executing `hlt`, which halts the CPU. The kernel never gets control back.

**Fix:** Use `CALL-REG` instead of `JMP-REG` for the entry call. This pushes a return address so `_start` can `RET` back to the loader, which then restores the kernel stack and resumes the keyboard loop.

---

### 2. `JMP-REG` discards the return address

**Symptom:** After `_start` returns (or is changed to return), OS still hangs.

**Cause:** `JMP RAX` doesn't push a return address — `RET` in `_start` jumps to garbage.

**Fix:** Changed to `CALL RAX`. The return address pushed by `CALL` points to the instruction after it (the kernel stack restore + `JMP kbd-main-loop`).

---

### 3. Wrong stack — userland corrupts kernel state

**Symptom:** After `_start` returns, the keyboard loop behaves erratically or crashes.

**Cause:** The kernel stack pointer (`RSP = 0x200000`) was used for the CALL. `_start`'s prologue pushes registers, growing the stack downward and potentially overwriting kernel data.

**Fix:** Set `RSP = 0x500000` before the CALL, restore `RSP = 0x200000` after. Userland gets its own stack region.

---

### 4. `mem-load64` and `mem-load16-zx` declared size was off by 1

**Symptom:** VGA debug showed `LO` — magic check passed but the PH loop crashed. Disassembly showed `JZ` landing in the middle of a `MOV RSI` instruction.

**Cause:** The assembler uses two passes: pass 1 computes label addresses by summing instruction sizes, pass 2 emits bytes. If any instruction reports a different size in pass 1 vs how many bytes it actually emits, all subsequent label addresses are wrong.

`mem-load64` was declared `8` bytes but emits `REX.W + opcode + ModRM + disp32 = 7` bytes. `mem-load16-zx` had the same error. With 6 such instructions before `elf-bss-done`, the label resolved 6 bytes too high — landing in the middle of a `MOV RSI, 0x300000` instruction and executing garbage.

**Fix:** Corrected both declared sizes to `7`. Always verify: count the actual bytes an instruction emits and match the declared size exactly.

**Lesson:** Any time you add a new assembler instruction, count the bytes by hand and verify with a disassembler. One byte off silently corrupts all subsequent label addresses.

---

### 5. Loop counter (ECX) clobbered by `REP MOVSB`

**Symptom:** Loader jumped to entry point immediately without copying any segments, or copied the first segment then crashed.

**Cause:** ECX was used for both the PH loop counter and the `REP MOVSB` byte count. `REP MOVSB` sets ECX to 0 when done, destroying the loop counter.

**Fix:** Push ECX (loop counter) and RBX (PH pointer) before the segment copy, push ECX again (filesz) for the BSS calculation, and restore in the correct reverse order after.

---

### 6. `MOV [imm32], imm` is RIP-relative in 64-bit mode

**Symptom:** VGA "ELF?" diagnostic appeared at a wrong location (or not at all).

**Cause:** In x86-64 long mode, `MOV [0xB8460], value` doesn't write to absolute address `0xB8460` — it's interpreted as `MOV [RIP + 0xB8460]` which is somewhere in kernel memory.

**Fix:** Load the address into a register first (`MOV RDI, 0xB8460`) then write relative to that register (`MOV WORD PTR [RDI + offset], value`). Always use register-indirect addressing for absolute memory access in 64-bit mode.

---

### 7. Stage 2 fits in 2048 bytes — ELF loading must happen in Stage 2, not Stage 1

**Symptom:** Adding the ELF INT 13h load to Stage 1 caused a build error: "Stage 1 must be exactly 512 bytes".

**Cause:** Stage 1 is exactly 512 bytes (the MBR). There's no room.

**Fix:** Moved the ELF disk load to Stage 2 (real mode section, before the PM switch). Stage 2 has up to 4KB, plenty of room.

---

## ELF Slot Size Limitation

Currently only **8KB** (16 sectors) is reserved for the ELF at sector 18. A complex program (with debug info, large data, etc.) could easily exceed this.

The embedded ELF should be compiled with:
```
-Os       # optimize for size
-g0       # no debug info
-fdata-sections -ffunction-sections
-Wl,--gc-sections   # strip unused code
```

And the linker script should discard:
```ld
/DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.debug*) }
```

To increase the slot size, change `(mov al #x10)` (16 sectors) in Stage 2 and update the `elf-sector-size` constant in `write-kernel.lisp`.

---

## Future Work

### Multiple userland programs
The current system embeds a single ELF. A proper shell would:
1. Maintain a directory of programs in the floppy sectors beyond sector 33
2. Allow the kernel to load a program by name from the directory
3. Support argument passing via a register or stack convention

### Return codes
`_start` currently returns void. A convention like `EAX = exit code` would let the kernel display the result or make decisions based on it.

### Inter-process communication
The kernel and userland currently share no interface except registers. A proper microkernel would expose system calls via a software interrupt (`INT 0x80` on x86, `SVC` on AArch64) with defined calling conventions.

### Memory isolation
Currently userland runs with full access to all memory — it can overwrite the kernel. A proper system would use page tables to isolate userland to its own virtual address space, with the kernel at a protected high address.

### Shared libraries
Static linking means every program carries its own copy of any shared code. A dynamic linker (`.interp` section, `ld-ecclesia.so`) would allow shared routines and smaller programs. This requires a much more complex loader.

### AArch64 userland
The AArch64 kernel uses UART for I/O instead of VGA. A userland program targeting AArch64 should write to the PL011 UART at `0x09000000` (QEMU virt) or `0xFE201000` (RPi4) rather than the VGA buffer. The `hello-aarch64.ld` linker script is in place; the C source needs to be updated to use UART writes for AArch64 targets.
