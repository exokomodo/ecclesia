---
name: rtk
description: Use rtk to compress shell command output before it reaches context. Use when running git, file, test, build, lint, or container commands to reduce token consumption by 60-90%. Binary is at ~/.cargo/bin/rtk (v0.34.3).
---

# RTK - Token Compression

`rtk` wraps shell commands and filters/compresses output before it hits context.
Binary: `/home/butler/.cargo/bin/rtk` (already in PATH via ~/.bashrc)

## When to use rtk

Use `rtk <command>` instead of the bare command whenever you need to read the output.
**Do not use rtk** when piping output to another tool or when exact raw output is required.
**Always fall back** to the bare command if rtk fails — never block a task.

## Git

```bash
rtk git status
rtk git log -n 20
rtk git diff
rtk git diff HEAD~1
rtk git add .          # → "ok"
rtk git commit -m "msg"  # → "ok abc1234"
rtk git push           # → "ok main"
rtk git pull           # → "ok 3 files +10 -2"
```

## GitHub CLI

```bash
rtk gh pr list
rtk gh pr view 123
rtk gh issue list
rtk gh run list
```

## File Operations

```bash
rtk ls .
rtk read file.go
rtk grep "pattern" .
rtk find "*.go" .
rtk json config.json    # structure without values
rtk env -f AWS          # filtered env vars
```

## Tests & Builds

```bash
rtk go test ./...
rtk cargo test
rtk cargo build
rtk cargo clippy
rtk pytest
rtk npm test
rtk npm run build
rtk ruff check
```

## Containers

```bash
rtk docker ps
rtk docker logs <container>
rtk kubectl pods
rtk kubectl logs <pod>
```

## Check savings

```bash
rtk gain
rtk gain --global
```
