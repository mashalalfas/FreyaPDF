# Search Engine Bug Fixes — 2026-07-15

Applied fixes per `SEARCH_BUG_REPORT.md` (Steps 1–5). Steps 6–8 (highlight consolidation, tests, within-page scroll) deferred to separate PRs.

## Changes Made

### 1. Removed 1 MB global memory cap, added per-page cap (`search_index.dart`)
- **Bug #1:** Deleted the `maxIndexedBytes` global cap that silently truncated indexing for any PDF > ~150 pages. Replaced with a per-page cap of 500 KB — pages with text exceeding this are truncated and logged.
- **Bug #9:** Added `searchDoc.isClosed` check at the top of each loop iteration to bail early if the viewer closes mid-indexing.
- Added `indexedPageCount` / `totalPageCount` getters for UI progress display.

### 2. Stored `charRects` alongside `fullText` (`search_index.dart`)
- **Bug #3:** Added `Map<int, List<PdfRect>> _charRects` populated from `rawText.charRects` during `buildIndex`.
- Added `rectsForMatch(pageNumber, charOffset, length)` helper that returns `List<Rect>` for drawing match highlights. Uses `PdfRect` internally (pdfrx's native type) and converts to `Rect` only at the call boundary.

### 3. Restored match highlighting (`search_provider.dart`, `viewer_screen.dart`)
- **Bug #2:** Added `paintSearchMatches(Canvas, Rect, PdfPage)` to `SearchProvider` — draws light-yellow rectangles for all matches and gold for the active match.
- Wired into `PdfViewerParams.pagePaintCallbacks` in `viewer_screen.dart`, positioned before the highlight paint callback.

### 4. Fixed listener leak and error status (`search_index.dart`, `viewer_screen.dart`)
- **Bug #5:** Added `IndexStatus.error` enum value with `errorMessage` field. The search document failing to open now sets `error` (not `noText`), which surfaces a red error icon with the reason.
- **Bug #4:** In `kickOffIndexing`, moved `_searchDocProvider?.removeListener(kickOffIndexing)` to the very top of the function — unconditionally, before any early-return checks. This prevents the listener from leaking when the search doc fails to open.
- Updated `_buildSearchButton` to handle `IndexStatus.error` with `Icons.error_outline_rounded` and `colorScheme.error`.

### 5. Cleaned up (`search_provider.dart`)
- **Bug #11:** Removed `safeDetach()` — dead code (never called).
- **Bug #10:** Removed redundant final `notifyListeners()` in `startIndexing` — `buildIndex` already notifies via its `_onIndexChanged` listener.
- **Bug #11:** Made `attach()` set all fields then notify once, instead of calling `detach()` first (which caused a brief double-notify with `_attached=false`).
- Added `errorMessage` getter to `SearchProvider` to expose the index's error state.

## Files Modified
- `lib/features/viewer/providers/search_index.dart`
- `lib/features/viewer/providers/search_provider.dart`
- `lib/features/viewer/viewer_screen.dart`

## Verification
- `flutter analyze` — **No issues found.**
