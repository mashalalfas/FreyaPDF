# FeyaPDF — Roadmap & Plan Status

Consolidated from the archived `plans/` directory.

## Status summary

| Plan | Summary | Status |
|---|---|---|
| `plans/001-test-coverage.md` | Service/provider unit tests (encryption, file I/O) | **Shipped** (README reflects current test count) |
| `plans/002-decompose-app-state.md` | Split large `AppState` into focused providers | **Shipped** |
| `plans/003-memory-safe-large-files.md` | File-based encryption service methods | **Shipped**, but not truly bounded-memory — AES-GCM paths still load full buffers |
| `plans/004-ci-cd-pipeline.md` | GitHub Actions analyze + tests | **Shipped** |
| `plans/005-gitignore.md` | Ignore workspace/agent artifacts | **Shipped** |
| `docs/plans/2026-08-09-pdf-password-memory-plan.md` | Optional secure remembering of PDF passwords | **In progress / pending** |

## Current release

- **Version:** 1.2.0 (build 6)
- **Verification:** `flutter analyze` clean; 392 tests passed; on-device search ANR resolved.
- **Git hash:** embedded at build time via `./tool/build_apk.sh` (Settings → About → Commit).

## Open / follow-up work

1. **PDF password memory** — implement the five tasks in the plan: secure storage service, prompt dialog, viewer wiring, forget/clear, full verification.
2. **Genuinely bounded-memory encryption** — Plan 003 is technically overstated; streaming encrypt/decrypt remains a real OOM concern for very large files.
3. **Search trace cleanup** — remove `SearchProvider.kTraceSearchStorm` instrumentation once confirmed stable.

## Security constraints (from plan 003 / password plan)

- Remembered PDF passwords live only in `flutter_secure_storage`, keyed by a normalized path hash — never in preferences, backups, logs, or exports.
- Opt-in storage, obscured input, bounded retries, cancellation, save-after-success only.
- Clear-all action required; per-file cleanup on delete/rename where path tracking is stable.
