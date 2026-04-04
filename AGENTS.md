# AGENTS.md

## Key Rules

- Respect the existing formatting and naming conventions in the repo's Common Lisp and C sources.
- Preserve existing indentation, package structure, and file organization.
- Avoid unrelated reformatting while making functional changes.
- Keep architecture-agnostic logic separate from x86_64-specific code.

## Test-Driven Development (TDD) Preference

- Follow Test-Driven Development (TDD) as the default approach for new features, bug fixes, and significant changes.
- Recommended workflow:
  1. Write or update tests first in `test/*.lisp` to define the desired behavior.
  2. Run the tests to confirm they fail before changing production code.
  3. Implement the minimal code needed to make the tests pass.
  4. Refactor while keeping tests green.
- Tests should be clear, focused, readable, and aligned with the intended behavior.
- Cover edge cases, error conditions, and boundary values where relevant.
- For refactors with no intended behavior change, run tests before and after the change.

## Build And Validation

- Use `make test` as the default validation command for Lisp changes.
- `./scripts/run-tests.lisp` is the underlying unit test entry point and is useful for direct test runs.
- Use `make build` when a change affects image generation, boot flow, or kernel packaging.
- Do not run `make boot`, `make boot-once`, or `make debug` unless explicitly requested, since they launch QEMU.
- Running tests and non-interactive build commands for validation is encouraged.

## Code Organization

- Keep bootloader, stage2, image-building, and kernel concerns separated according to the existing `src/` layout.
- Put ISA-specific behavior in the x86_64-specific files instead of mixing it into shared bootstrap logic.
- Prefer small, localized changes that match the current ASDF system layout and package boundaries.
- When changing behavior in assembler, bootstrap, or floppy/image generation code, add or update the corresponding tests.

## Pull Request And Commit Conventions

- Prefer conventional commit format for PR titles and commits: `type: description`.
- Common types in this repo include `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`, and `perf:`.
- Use lowercase, imperative descriptions such as `fix: validate ELF entry point`.
- Include the issue number in the PR body when applicable, for example `Closes #40`.
- Prefer short, descriptive branch names. If work is tied to an issue, include the issue number when practical.
