# AGENTS.md

# ... (existing content preserved) ...

## 🚦 Autobutler-Specific Agent Guidelines

### Minimize DB Table Additions/Modifications (Last Resort)
- Expanding or changing DB tables is a last resort and generally discouraged.
- Prefer manipulating files directly or using native file-level metadata for app and user data
- Only use the database when a file-based or other native (filesystem, attributes) approach is impossible or reliably breaks down

### Makefile Target Usage
- Agents should invoke existing Make targets to run, test, or lint the codebase (`make run`, `make test`, `make lint`)
- If there is a common/templated workflow not already a make target, add a new one rather than direct shell

### Flutter / Dart Packages
- The `packages/` directory contains fully independent Dart or Flutter libraries
- These are maintained by Autobutler for:
  - Code reuse within the monorepo
  - Publishing as standalone open-source packages for other Flutter devs
  - Keeping app code and generic library code cleanly separated

(Above drafted per James' 2026-04-15 guidance: minimize DB whenever possible, use Makefile not shell, and note the intent of packages/ for both internal/external Flutter consumption.)

## Make It Yours

This is a starting point. Add your own conventions, style, and rules as you figure out what works.
