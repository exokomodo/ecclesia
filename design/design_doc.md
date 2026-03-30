# Ecclesia: Design Document

## Vision
Ecclesia is a modern Lisp-inspired microkernel operating system with extensibility, simplicity, and dynamism at its core. It recalls the spirit of Lisp Machines while embracing a microkernel structure to achieve modularity. The goal is to create an OS where components are pluggable and redefine runtime behaviors dynamically using Lisp's REPL capabilities.

---

## 1. Initial Goals
- **Boot in QEMU:** A minimal, bootstrapping kernel capable of initializing in a virtualized environment (QEMU).  
- **Integrated Lisp REPL Shell:** The system starts with a Lisp REPL ready as the default shell, enabling direct interaction with the OS.  
- **ELF Binary Support:** Load and execute static ELF binaries seamlessly.

---

## 2. Microkernel Architecture
Ecclesia adopts a microkernel design to maximize modularity and extensibility.  

### Characteristics:
- **Minimal Core:** The kernel provides only core functionalities:  
  - Thread/Task Management  
  - Inter-Process Communication (IPC)  
  - Basic Memory Management
- **Pluggable Services:** All other functionalities (e.g., filesystems, networking, POSIX subsystem) are implemented as loadable modules, dynamically attachable to the system.
- **Dynamic Redefinition:** The kernel and modules are flexible and reconfigurable during runtime, leveraging the Lisp REPL.

---

## 3. Key Components

### 3.1 Core Kernel
- Written in **Common Lisp** with inline Assembly for hardware-specific tasks (e.g., bootstrapping and low-level CPU interactions).  
- Plan: Use **SBCL** (Steel Bank Common Lisp) for the initial development.

### 3.2 REPL as System Shell
Ecclesia treats the Lisp REPL as the core interaction mechanism.  
- Familiar to users with experience in Lisp systems.  
- Enables runtime introspection, debugging, and redeployment of kernel modules.  

### 3.3 Dynamic Module System
Modules replace monolithic design components:  
- Drivers (device management, filesystems)  
- POSIX compatibility (installable if required)  
- UI/UI modules such as window managers.  

Use loadable **FASL (Fast Loading Lisp)** files for module distribution.

### 3.4 File System Abstraction
Filesystems are modules that implement a specific interface contract for pluggability.  
- Minimal VFS for mounting/unmounting filesystems.  
- Possible support for existing filesystems (EXT4, FAT32) via dedicated modules.

---

## 4. Development Phases
### Phase 1: Base Kernel + REPL
1. Basic kernel setup: thread management, IPC, minimal scheduler.  
2. Integrate a lightweight Lisp interpreter or REPL directly into kernel initialization.
3. Bootable in QEMU: BIOS/UEFI-based bootloader to initialize kernel image.

### Phase 2: ELF Execution
1. Implement memory loading and execution support for static ELF binaries.
2. Test with simple C programs to validate ELF loader functionality.

### Phase 3: Runtime Module Loading
1. Dynamically load/unload FASL-encoded Lisp modules.  
2. Extend kernel capabilities using installed modules.

---

## 5. Long-Term Goals
- Support for SMP (Symmetric Multiprocessing).  
- User-space networking stack as a module.  
- POSIX compatibility layer if required by higher-level applications.  
- Extension of the Lisp REPL as a full development environment for the OS.

---

## Decisions
1. **Memory Model:** Start with a flat memory model for simplicity.  
2. **Lisp Interpreter:** Begin with SBCL as the Lisp engine.  
3. **Bootloader:** Off-the-shelf bootloader (e.g., GRUB) for quick setup.  
4. **ELF Support:** Focus on static ELF binaries initially; dynamic linking to be deferred to a later stage.