# PDF Search — Architecture, Limits, and Resolved ANR

Consolidated from the archived search investigation reports.

## Current architecture

Search is implemented in `SearchProvider` (`lib/features/viewer/providers/search_provider.dart`).

**Invariants (do not regress):**

- No `PdfTextSearcher`; no second `PdfDocument` for search.
- No full-document page loading during search — only pages the viewer has already loaded are scanned.
- No full-document indexing on viewer open.
- No per-keystroke scan (400 ms debounce).
- `toggleSearchBar()` is a pure-UI action (flips a bool, notifies).
- Match geometry (`charRects`) is loaded only for the active match page.

**Flow:**

1. Tap search → overlay `SearchBarWidget` mounts (overlay, so the viewer is never resized).
2. Type a query → `SearchProvider.search()` debounces 400 ms → `_runSearch()`.
3. Scan loads raw text per already-loaded page (`page.loadText()`), caps per-page text, and finds matches.
4. Hard gates: documents over `kMaxTotalPages` (300) pages or image-only documents show an unavailable message instead of scanning.

**User-visible states:** `notIndexed`, `indexing`, `ready`, `noText`, `unavailable`, `error`; plus `searchTruncated` when the scan stopped at the page cap.

## Root causes found and fixed (search correctness)

| Issue | Fix |
|---|---|
| Global 1 MB index cap silently stopped indexing large PDFs | Removed cap; bounded per-page text |
| Visible match highlighting discarded `charRects` | Restored on-demand match geometry |
| Search-document failures mislabeled as "no text" | Distinct `IndexStatus.error` |
| Search navigated only to page, not match | `_goToCurrentMatch` + single-page geometry |
| Search + highlights duplicated extraction through pdfrx's singleton worker | Search only scans already-loaded pages |
| Search-bar resize/rebuild triggered pdfrx re-renders | Overlay layout + scoped `Consumer` |

## Resolved ANR: search-bar toggle focus storm

**Symptom:** toggling search caused a 5–12 s CPU storm, ~1.4 GB memory growth, and
`Input dispatching timed out` ANRs (MotionEvent / FocusEvent), even on a small text PDF.

**Investigation facts:**

- `viewerBuilds=0`, `pagePaints=0` during the storm — neither the main build nor the
  page-paint callbacks were responsible.
- `simpleperf` was blocked by SELinux; official ANR traces were inaccessible.
- pdfrx's `_CustomPainter.shouldRepaint => true` and its render→`_invalidate`→repaint
  loop made sibling paints expensive without a `RepaintBoundary`.

**Root cause:** `SearchBarWidget` attached the same `FocusNode` twice — once on the outer
`Focus` widget and once on the `TextField` (whose internal `EditableText` also attaches
it). This corrupted Flutter's focus tree and, combined with semantics enabled on-device,
produced the `FocusEvent` ANR when the field mounted.

**Fix (shipped in v1.2.0):**

- `search_bar.dart`: outer `Focus` now uses its own node; `_focusNode` is owned only by the `TextField`.
- Added `RepaintBoundary` around the viewer and the search overlay; removed the overlay `AnimatedSwitcher`.
- Added a temporary storm-trace (`SearchProvider.kTraceSearchStorm`) for device diagnosis.

**Verification:** `flutter analyze` clean; 392 tests pass; on-device search opens instantly and returns results.

## Remaining risks

- Bounds produce intentional false negatives for unloaded pages, pages >300, and image-only PDFs.
- Trace instrumentation should be removed after final confirmation.
