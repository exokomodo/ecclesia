# Ecclesia Assembler

The Ecclesia assembler is a generic two-pass assembler written in Common Lisp.
Instruction encodings are decoupled from the assembly machinery via a
registration table, making it straightforward to add new CPU architectures
without touching the core.

## Architecture

```plaintext
src/assembler/
  assembler.lisp   — generic two-pass core
  x86_64.lisp      — x86_64 instruction encodings
```

### assembler.lisp — the core

The core provides:

- `*instruction-table*` — a hash table mapping mnemonic symbols to `(size-fn emit-fn)` pairs
- `register-instruction mnemonic size-fn emit-fn` — registers an instruction
- `assemble instructions` — two-pass assembles a list of s-expression forms into a byte vector
- `collect-labels instructions origin` — pass 1: walks instructions and records label addresses
- `emit-instruction form labels origin buf` — pass 2: emits bytes for a single instruction
- `eval-expr expr labels` — evaluates label arithmetic expressions (e.g. `(- end start 1)`)
- `*asm-bits*` — dynamic variable tracking the current bit mode (16, 32, or 64)

Reserved forms handled directly by the core (not in the instruction table):

| Form           | Meaning                                   |
| -------------- | ----------------------------------------- |
| `(bits N)`     | Set current bit mode to N (16, 32, or 64) |
| `(org ADDR)`   | Set the load origin address               |
| `(label NAME)` | Define a label at the current address     |

### x86_64.lisp — instruction encodings

Registers all x86_64 instructions using the `definsn` macro and
`register-instruction`. Each instruction specifies:

- A **size form** — how many bytes this instruction produces (may depend on `mode` and operands)
- An **emit body** — side effects that write bytes into the output buffer

## Adding a New CPU Architecture

To add support for a new CPU (e.g. RISC-V, ARM):

### 1. Create the encoding file

```plaintext
src/assembler/riscv.lisp
```

### 2. Define your register tables

```lisp
(defparameter *riscv-regs*
  '((x0 . 0) (x1 . 1) (x2 . 2) ...))
```

### 3. Register instructions using `definsn`

`definsn` is a convenience macro that calls `register-instruction`:

```lisp
(definsn nop (args mode) 4       ; always 4 bytes (one 32-bit word)
         (args labels origin buf mode)
  (push-u32 buf #x00000013))     ; ADDI x0, x0, 0

(definsn add (args mode) 4
         (args labels origin buf mode)
  (let ((rd  (enc *riscv-regs* (first args)))
        (rs1 (enc *riscv-regs* (second args)))
        (rs2 (enc *riscv-regs* (third args))))
    (push-u32 buf (logior #x00000033
                          (ash rd  7)
                          (ash rs1 15)
                          (ash rs2 20)))))
```

### 4. Add the file to ecclesia.asd

```lisp
(:module "assembler"
 :components ((:file "assembler")
              (:file "x86_64")
              (:file "riscv")))   ; ← add here
```

### 5. Use `(bits N)` at the start of your instruction list

```lisp
(defparameter *my-program*
  '((bits 32)
    (org #x80000000)
    (nop)
    (add x1 x2 x3)
    ...))

(assemble *my-program*)
```

## Instruction Form Reference

All instructions are s-expressions. The first element is the mnemonic;
remaining elements are operands.

```lisp
(cli)                          ; no operands
(mov eax #x1234)               ; register ← immediate
(mov ds ax)                    ; segment register ← register
(mov (mem32 #xb8000) #x0720)   ; memory ← immediate (x86 absolute)
(jmp short done)               ; short relative jump to label
(jmp far #x0008 entry)         ; far jump: segment:label
(times 510 db 0)               ; repeat: N copies of byte
(label entry)                  ; label definition
(dw (- end start 1))           ; data word with label arithmetic
```

## Label Expressions

Data directives (`db`, `dw`, `dd`, `dq`) accept label arithmetic:

```lisp
(dw (- gdt-end gdt-start 1))   ; GDT limit
(dd gdt-start)                 ; GDT base address
```

Supported operators: `+`, `-`, `*` (N-ary).

## Bit Mode

The assembler tracks a `*asm-bits*` variable (default 16). Change it with:

```lisp
(bits 32)   ; switch to 32-bit operand defaults
(bits 64)   ; switch to 64-bit
```

x86_64 uses `*asm-bits*` to decide whether to emit operand-size prefixes
(e.g. `0x66` before 16-bit register moves in 32-bit mode). Other architectures
can use or ignore it as appropriate.
