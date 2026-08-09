# FreyaPDF — Documentation

A clean, consolidated documentation set for the FreyaPDF codebase. Old, superseded, and one-off working notes have been archived under `docs/archive/`.

## Index

| Document | Purpose |
|---|---|
| [`README.md`](../../README.md) | Project overview, build, and CI (kept at repo root). |
| [`KNOWLEDGE_MAP.md`](../../KNOWLEDGE_MAP.md) | Architecture map (kept at repo root). |
| [`docs/clean/search.md`](search.md) | PDF search feature: architecture, limits, and resolved ANR. |
| [`docs/clean/roadmap.md`](roadmap.md) | Consolidated plan/roadmap status (plans 001–005 + PDF password memory). |
| [`docs/clean/architecture.md`](architecture.md) | Architecture and module overview. |

## Build

The app embeds the current git commit hash at build time. Always build via the wrapper:

```bash
./tool/build_apk.sh release          # release APK
./tool/build_apk.sh profile --install # profile APK + install on device
```
