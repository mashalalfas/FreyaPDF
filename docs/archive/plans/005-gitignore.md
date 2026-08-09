# Plan 005: Add .gitignore for workspace artifacts

> **Executor instructions**: Follow step by step. Verify each step before moving on.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx
- **Planned at**: commit `8a85841`, 2026-06-13

## Why this matters

`.openclaw/`, `.understand-anything/`, `graphify-out/`, `AGENTS.md`, `HEARTBEAT.md` etc keep accidentally getting staged. A .gitignore prevents this noise.

## Steps

### Step 1: Create or update `.gitignore`

Append to existing `.gitignore` (read it first — if it doesn't exist, create):

```
# Workspace artifacts
.openclaw/
.understand-anything/
NAVIGATION_TREE.md
graphify-out/
legal-config.json
legal/

# Agent files
AGENTS.md
HEARTBEAT.md
IDENTITY.md
SOUL.md
TOOLS.md
USER.md
```

### Step 2: Verify

```bash
git status --short
```
No .openclaw, .understand-anything, graphify-out, AGENTS.md, HEARTBEAT.md, etc showing as untracked.

## Done criteria

- [ ] `.gitignore` contains entries for all workspace artifacts
- [ ] `git status` shows only real project files as untracked
