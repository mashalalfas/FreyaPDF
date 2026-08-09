# FeyaPDF Search Engine — Bug Report & Fix Plan

**Investigation date:** 2026-07-15
**Investigator:** Sub-agent (deep read of Tier 2 implementation + pdfrx 2.4.7 source)
**Scope:** `lib/features/viewer/providers/{search_provider,search_index,search_document_provider}.dart`,
`lib/features/viewer/viewer_screen.dart`, `lib/features/viewer/widgets/search_bar.dart`,
`lib/features/highlights/highlight_provider.dart`, `lib/main.dart`, plus pdfrx engine internals.

---

## TL;DR — Root Causes

Tier 2 has **three** independent reasons the user perceives search as broken on device:

1. **The 1 MB memory cap silently truncates the index for any non-trivial PDF.** For
   anything > ~150 pages of text (or fewer pages of dense text), the indexer stops
   mid-document. The user searches for content in later pages and gets **0 results with
   no UI indication** that the index is incomplete.

2. **Match highlighting on the page was deleted.** Tier 1 had
   `matchTextColor` / `activeMatchTextColor` and a `pagePaintCallback` that drew yellow
   rectangles on matched text. Tier 2 removed both. The page now jumps to the matched
   page but **does not show WHERE on the page the match is** — so the user sees the
   page change and concludes "search doesn't work."

3. **The index discards `charRects`** returned by `PdfPage.loadText()`. Even if we
   re-add the highlight overlay, the data needed to draw it has been thrown away —
   we'd need to either store charRects or switch to `loadStructuredText()` (heavier).

The **architectural** approach is sound (separate `PdfDocument` with
`useProgressiveLoading: false` + pure-Dart index). The failures are in the
**integration, memory budgeting, and visual feedback** layers.

There are also several secondary bugs (memory leak on open failure, dead code,
duplicated isolate work, no within-page scroll to match). See §3.

---

## 1. Architecture recap (what Tier 2 is doing right)

```
_initState
  └── _loadPdf (async, fire-and-forget)
        ├── reads encryption / settings / fileOps providers
        ├── if encrypted: fileOps.getPdfBytes → encryptedBytes (DECRYPTED bytes,
        │   despite the misleading name)
        ├── builds viewer PdfDocumentRef
        │     encrypted → PdfDocumentRefData(decryptedBytes, useProgressiveLoading:false)
        │     plain     → PdfDocumentRefFile(path, useProgressiveLoading:true)
        ├── _searchDocProvider = SearchDocumentProvider()
        ├── unawaited(openSearchDocument(...))        ← SEPARATE doc for text
        ├── _pdfController = PdfViewerController()
        └── setState(_isLoading = false) → triggers build

PdfViewer build → onViewerReady fires when viewer doc loads
  ├── searchProvider.attach(controller)               ← controller now wired
  ├── kickOffIndexing() — runs immediately if searchDoc.isReady
  │     else attaches a one-shot listener that fires when searchDoc.isReady
  │     → startIndexing(searchDoc)        (iterates pages, page.loadText())
  │     → HighlightProvider.cachePageTexts(searchDoc)
  │         (iterates pages, page.loadStructuredText() → internally calls loadText())
```

This eliminates the original `PdfTextSearcher` SIGSEGV because:
- We never call `PdfTextSearcher.startTextSearch(...)`.
- We never call `PdfDocument`'s text-search methods.
- We only call `loadText()` / `loadStructuredText()` on `PdfPage`, which return
  `PdfPageRawText?` / `PdfPageText` — pure data, no native search code paths.

`grep -r "PdfTextSearcher" lib/` returns zero matches. The Tier 1 SIGSEGV path is
genuinely gone.

`flutter analyze` passes and unit tests pass because:
- The 3 new classes have no unit tests at all (see §3.12).
- The widget tests only assert that `ViewerScreen` constructs without throwing
  when a `SearchProvider` is in the tree — they never verify search *behaviour*.

---

## 2. pdfrx 2.4.7 API verification

Verified against `~/.pub-cache/hosted/pub.dev/pdfrx-2.4.7` and `pdfrx_engine-0.4.5`:

| Concern | Finding |
|---|---|
| `page.loadText()` return type | `Future<PdfPageRawText?>` (`PdfPageRawText(fullText: String, charRects: List<PdfRect>)`). Returns `null` if `document.isDisposed` or `!isLoaded`. |
| `page.loadStructuredText()` | Internally calls `page.loadText()` first (see `PdfTextFormatter._loadFormattedText` in `pdf_text_formatter.dart:276`), then does text-flow + line-segmentation analysis. Returns non-nullable `PdfPageText`. |
| `useProgressiveLoading: false` semantics | In `_PdfDocumentPdfium.fromPdfDocument`, `maxPageCountToLoadAdditionally: null` is passed → `_loadPagesInLimitedTime` runs `end = pageCount`, all pages loaded with `isLoaded: true` synchronously. **Verified correct.** |
| `PdfDocument.openFile(path, ...)` | Accepts `useProgressiveLoading: false` ✓. Does NOT accept `sourceName` (auto-generates `file%<path>`). The comment in `search_document_provider.dart:84` is correct. |
| `PdfDocument.openData(bytes, sourceName:, useProgressiveLoading:)` | ✓ accepts both. |
| `PdfDocumentRef.useProgressiveLoading` | Default is `true` for both `PdfDocumentRefFile` and `PdfDocumentRefData`. The viewer correctly sets `true` for unencrypted, `false` for encrypted. |
| Background isolate | `BackgroundWorker._instance` is a **singleton** (`pdfrx_engine-0.4.5/lib/src/native/worker.dart:13`). All PDFium work — view + search doc open + every `loadText` + every `loadStructuredText` + every page render — is **serialized** through this single isolate. **This has architectural implications — see §3.7.** |
| Tier 1 `PdfTextSearcher` still imported? | No. `grep -r PdfTextSearcher lib/` → 0 matches (only doc-comments reference it). |

The pdfrx API surface is being used correctly.

---

## 3. Bugs found

### 🔴 BUG #1 — 1 MB memory cap silently truncates the index

**Severity:** High (silently degrades search for any non-trivial PDF)
**Location:** `lib/features/viewer/providers/search_index.dart:99-127`

```dart
// search_index.dart:99-127
const maxIndexedBytes = 1024 * 1024; // 1 MB
var indexedBytes = 0;
for (var i = 0; i < pages.length; i++) {
  if (indexedBytes >= maxIndexedBytes) {
    debugPrint('SearchIndex: Memory cap (${maxIndexedBytes}B) reached — '
        'stopping at ${_pageTexts.length} pages');
    break;  // ← silently aborts
  }
  ...
  final rawText = await page.loadText();
  if (rawText != null && rawText.fullText.trim().isNotEmpty) {
    _pageTexts[page.pageNumber] = rawText.fullText;
    indexedBytes += rawText.fullText.length;
  }
}
```

**Symptoms:**
- For any PDF where total extracted text > 1 MB, `_pageTexts` contains only the first
  ~100–350 pages (varies wildly with text density).
- `SearchIndex.status` still becomes `IndexStatus.ready` because `_pageTexts.isNotEmpty`.
- The user sees the search button enabled. They search for a word on page 800.
- `_index.search()` returns 0 matches because page 800 isn't in `_pageTexts`.
- The UI shows "No results." The user concludes search is broken.
- There is no warning, no "indexed 350 of 1200 pages" indicator.

**Why this exists:** It was carried over from Tier 1 to "avoid unbounded memory
growth." But with `useProgressiveLoading: false`, pages are already in memory — the
extracted text is *additional* memory, not 2x the PDF size. The cap was always
wrong; it just became fatal in Tier 2 because there are no character rects / match
boxes to compensate (see Bug #2).

**Reproduce on device:** Open a 500-page PDF with body text. Search for a word
that appears only in the last 200 pages. → "No results."

---

### 🔴 BUG #2 — Match highlighting was deleted in Tier 2

**Severity:** Critical (user perceives "search failed" because the match is invisible)
**Location:** `lib/features/viewer/viewer_screen.dart` (search params block)

In Tier 1 (committed):
```dart
pagePaintCallbacks: [
  _searchProvider.pagePaintCallback,        // ← drew yellow rects on matches
  context.read<HighlightProvider>().paintHighlights,
],
matchTextColor: const Color.fromARGB(80, 255, 255, 0),        // ← removed
activeMatchTextColor: const Color.fromARGB(120, 255, 200, 0), // ← removed
```

In Tier 2 (current):
```dart
pagePaintCallbacks: [
  context.read<HighlightProvider>().paintHighlights,
],
// no matchTextColor / activeMatchTextColor
```

`SearchProvider` no longer has a `pagePaintCallback` method — its `paint` capability
was deleted (see `git diff -- search_provider.dart`).

**Symptoms:**
- User types a query. Search bar shows "1 / 5."
- The viewer navigates to the matched page (`goToPage(pageNumber: match.pageNumber)`).
- **Nothing is drawn over the matched text.** The page looks identical to before.
- User scrolls manually, can't find the match, concludes "search doesn't work."

**Why this exists:** `matchTextColor` / `activeMatchTextColor` only work when
`PdfTextSearcher` is alive (pdfrx routes them through it). Without `PdfTextSearcher`,
those params do nothing. To restore visual highlighting, we have to draw it ourselves
via a `pagePaintCallbacks` entry that knows the match's character offsets.

This is also why the user reports "search fails" — the page DOES change, but the
visual cue is gone.

---

### 🔴 BUG #3 — `SearchIndex` discards `charRects`, blocking future visual highlighting

**Severity:** High (blocks the fix for Bug #2)
**Location:** `lib/features/viewer/providers/search_index.dart:121`

```dart
final rawText = await page.loadText();           // PdfPageRawText(fullText, charRects)
if (rawText != null && rawText.fullText.trim().isNotEmpty) {
  _pageTexts[page.pageNumber] = rawText.fullText;  // ← charRects thrown away
  indexedBytes += rawText.fullText.length;
}
```

`PdfPageRawText` is `(fullText: String, charRects: List<PdfRect>)`. The `charRects`
list has one rect per character, in the same coordinate space as the pdfrx
`pagePaintCallback` canvas. To draw a match highlight, you need both the substring
range (to find which chars match) and the rects (to know where to draw).

If we want to restore visual highlighting, we either:
- (a) Store charRects per page (memory cost: ~80 bytes per char → 10 chars/line ×
  ~40 lines/page × 350 pages = ~11 MB worst case for a dense PDF, more typically
  2–4 MB). Combine with a sane memory cap.
- (b) Switch the index to `loadStructuredText()` which keeps `PdfPageText.fragments`
  with bounding rects, then look up rects on demand (slower at search time but
  lighter on memory).

I recommend **(a)** with a per-page cap (e.g., 100 KB raw text + charRects per page
skip-and-summarize the page if larger), because it makes search→highlight immediate
with no extra PDFium calls.

---

### 🟠 BUG #4 — Listener never self-removes when search-doc open FAILS (memory leak)

**Severity:** Medium (leak; also means user sees stale "loading" state forever)
**Location:** `lib/features/viewer/viewer_screen.dart:269-285`

```dart
void kickOffIndexing() {
  if (kickedOff || !mounted) return;
  if (_searchDocProvider?.isReady != true) return;     // ← returns WITHOUT
                                                      //   self-removing
  kickedOff = true;
  _searchDocProvider?.removeListener(kickOffIndexing);
  ...
}

if (_searchDocProvider?.isReady == true) {
  kickOffIndexing();
} else {
  _searchDocProvider?.addListener(kickOffIndexing);   // ← listener attached
}
```

Combined with `SearchDocumentProvider.openSearchDocument`:

```dart
// search_document_provider.dart:75-92
} catch (e) {
  _error = 'Failed to open search document: $e';
} finally {
  _isLoading = false;
  notifyListeners();   // ← notifies with isReady==false
}
```

When `openSearchDocument` throws (e.g. malformed PDF, FPDF_LoadDocument returns
nullptr, missing file, decryption mismatch):
- `_searchDocument` stays `null`.
- `notifyListeners()` fires.
- Listener runs: `isReady` is `false` → returns without `removeListener`.
- **`kickedOff` stays `false`, listener stays attached for the lifetime of the
  (now disposed) SearchDocumentProvider.**
- Next listener firing: same outcome.

The `SearchDocumentProvider.dispose()` calls `super.dispose()` which does NOT
`notifyListeners()`. So the listener sits there forever — every `kickOffIndexing`
re-fires the closure (still no-op because `!mounted`), but the closure + listener
slot in the internal list are never released until GC runs.

Symptoms:
- After a failed open, `IndexStatus` may go `notIndexed` → `indexing` → `noText`
  (depending on timing) and the button shows "no text to search" — **lying to the
  user**. There IS text in the PDF; the search document just couldn't open.

Fix: remove the listener unconditionally, and surface the error via a new
`IndexStatus.error` enum value.

---

### 🟠 BUG #5 — `IndexStatus.noText` is used for both "image PDF" and "open failure"

**Severity:** Medium (bad UX — masks real errors)
**Location:** `lib/features/viewer/providers/search_index.dart:55-62`, `search_index.dart:108`

```dart
enum IndexStatus {
  notIndexed,
  indexing,
  ready,
  noText,           // ← overloaded to mean two different things
}

...

if (document == null) {
  _status = IndexStatus.noText;   // ← "search doc didn't open" ≠ "no text"
  return;
}
...
} catch (e) {
  _status = IndexStatus.noText;   // ← again
}
```

When the search document fails to open, the user sees the same "no text to search"
icon they would see for a legitimate image-only PDF. There's no way to distinguish
"this is an image PDF" from "we failed to index this PDF."

Fix: add `IndexStatus.error` with an optional `errorMessage` field.

---

### 🟠 BUG #6 — `goToCurrentMatch` doesn't scroll within the page to the match

**Severity:** Medium (long pages are unusable for search)
**Location:** `lib/features/viewer/providers/search_provider.dart:177-182`

```dart
void goToCurrentMatch() {
  if (_matches.isEmpty || _currentMatchIndex < 0) return;
  final match = _matches[_currentMatchIndex];
  _controller?.goToPage(pageNumber: match.pageNumber);  // ← only navigates
                                                        //   to the page
}
```

For a long page where the matched text is near the bottom, the user lands at the
top of the page and has to scroll the entire page to find the match. With Bug #2
(no highlight), they can't even see WHERE to scroll.

Once we have `charRects` stored (Bug #3 fix), this should also use the controller's
`goToRect`/`goTo` with the matched rect to scroll into view.

---

### 🟡 BUG #7 — Duplicate text-extraction work serializes through the singleton isolate

**Severity:** Medium (perf; indirectly affects whether search ever finishes)
**Location:** `lib/features/highlights/highlight_provider.dart:266-301` and
`lib/features/viewer/providers/search_index.dart:99-127`

In `_onViewerReady.kickOffIndexing`:

```dart
searchProvider.startIndexing(_searchDocProvider!);                  // async, not awaited
context.read<HighlightProvider>().cachePageTexts(_searchDocProvider!);  // async, not awaited
```

Both run "in parallel" but **both serialize through `BackgroundWorker._instance`** —
the singleton worker isolate (verified in `pdfrx_engine-0.4.5/lib/src/native/worker.dart:13`).

What this means in practice:
1. `startIndexing` calls `page.loadText()` for every page → enqueues N PDFium jobs.
2. `cachePageTexts` calls `page.loadStructuredText()` for every page → enqueues 2N
   PDFium jobs (because `loadStructuredText` internally calls `loadText` first —
   see `PdfTextFormatter._loadFormattedText` at `pdf_text_formatter.dart:276`, then
   does additional text-flow analysis).
3. While these jobs run, **the viewer also queues page renders** for every visible
   page (continuous scroll mode = many pages visible).
4. Page-rendering starvation → UI jank, perceived as "search broken."
5. Indexing takes 3x as long as it needs to because we're doing the same `loadText`
   twice per page (once for the search index, once for the highlight cache).

Combined with the 1 MB cap (#1), a user with a 500-page PDF will see indexing crawl,
and the indexer will probably hit the cap before all pages are processed.

**Fix:** Use `loadStructuredText()` once per page, populate *both* the search index
AND the highlight cache from the same `PdfPageText`. Or even better: have the search
index share state with the highlight cache (the highlight provider already keeps
`_pageTextCache` — see Bug #8).

---

### 🟡 BUG #8 — `_pageTextCache` and `_pageTexts` are two parallel text stores

**Severity:** Medium (memory; architecturally awkward)
**Location:** `lib/features/highlights/highlight_provider.dart:259-301` and
`lib/features/viewer/providers/search_index.dart:25-127`

`HighlightProvider._pageTextCache` stores `Map<int, PdfPageText>` (with rects).
`SearchIndex._pageTexts` stores `Map<int, String>` (raw text only).

Both are populated at the same moment from the same `SearchDocumentProvider`. They
exist as parallel universes. After Bug #3 is fixed (search index keeps rects), they
become functionally identical — except the highlight provider uses `PdfPageText`
(with `fragments`) while the search index would use `PdfPageRawText` (with
`charRects`). Both contain the rect data needed for visual highlighting.

**Fix:** Consolidate. Have a single `TextIndex` (or `PageTextIndex`) that both the
search provider and the highlight provider consume. This also halves the singleton-
isolate work (only one `loadStructuredText` per page, used by both).

---

### 🟡 BUG #9 — `_buildIndex` doesn't check `searchDoc.isClosed` mid-loop

**Severity:** Low (wasted CPU, no crash)
**Location:** `lib/features/viewer/providers/search_index.dart:99-127`

```dart
for (var i = 0; i < pages.length; i++) {
  // no check: is _searchDocProvider still alive?
  final page = pages[i];
  try {
    if (!page.isLoaded) continue;
    final rawText = await page.loadText();   // returns null if document.isDisposed
    ...
  }
}
```

If the viewer closes mid-indexing:
1. `_ViewerScreenState.dispose()` → `_searchDocProvider?.dispose()` → `_searchDocument?.dispose()` and `_searchDocument = null`.
2. But `pages` is a `List` captured by value at the top of the loop.
3. Subsequent `page.loadText()` returns `null` (engine check at `pdfrx_pdfium.dart:1711`).
4. `_pageTexts[page.pageNumber]` is never updated. The loop spins to completion.
5. The `try/catch` swallows any RangeError but doesn't catch the dead-doc case explicitly.

This wastes CPU for the rest of the loop. Should check `searchDoc.isClosed` at the
top of each iteration and break early. Low severity because it doesn't crash or
leak, just wastes cycles during a brief teardown window.

---

### 🟡 BUG #10 — `startIndexing` notifies 3 times for one status transition

**Severity:** Low (perf, not correctness)
**Location:** `lib/features/viewer/providers/search_provider.dart:90-101`

```dart
Future<void> startIndexing(SearchDocumentProvider searchDoc) async {
  _index.clear();           // no notify
  notifyListeners();        // notify #1

  await _index.buildIndex(searchDoc);  // internally notifies #2 and #3

  notifyListeners();        // notify #4 — redundant with #3
}
```

The buildIndex flow emits `indexing` → `ready/noText`, and `startIndexing` then
emits one more notification. Triggers 4 rebuilds of `Consumer<SearchProvider>`
where 1 would suffice.

Fix: remove the redundant final `notifyListeners()` (or rely on `_index`'s
listener-driven notify, which is already wired via `_onIndexChanged`).

---

### 🟡 BUG #11 — `safeDetach` is dead code; also `attach` doesn't actually need `detach` to call `notifyListeners`

**Severity:** Low (dead code; minor UX glitch)
**Location:** `lib/features/viewer/providers/search_provider.dart:63-83`

```dart
void safeDetach() { ... }   // never called

void attach(PdfViewerController controller) {
  detach();                 // ← calls notifyListeners() as a side-effect
  _controller = controller;
  _attached = true;
}
```

`safeDetach` exists but `grep -r safeDetach lib/ test/` finds no callers.

Side note: `attach()` calls `detach()` which emits a notification with `_attached=false`,
which briefly disables the search button via `_buildSearchButton`'s Consumer. Probably
harmless, but a fast double-notify causes a double rebuild.

Fix: remove `safeDetach`; make `attach` not rely on `detach` for the notify.

---

### 🟡 BUG #12 — No tests for search behaviour; tests pass for the wrong reason

**Severity:** Medium (regressions will ship silently)
**Location:** `test/viewer_integration_test.dart`, `test/viewer_crash_fix_test.dart`

`grep -rn "SearchIndex\|startIndexing\|buildIndex\|searchDocument" test/` → 0 matches.

`grep "SearchProvider" test/` → only the `ChangeNotifierProvider<SearchProvider>(
create: (_) => SearchProvider())` boilerplate needed to instantiate `ViewerScreen`.

The tests assert:
- The screen builds without throwing.
- The screen shows a loading indicator.
- The screen shows an error UI on missing files.
- Draw mode doesn't crash.

They never assert:
- That `SearchIndex.buildIndex` populates `_pageTexts` for a real PDF.
- That `_index.search('the')` returns matches in the right pages.
- That `_onViewerReady` actually triggers indexing on a real PDF.
- That the search button transitions from `indexing` → `ready`.

This is why "the search STILL fails on device" — the test suite proves nothing
about search working.

---

## 4. Concrete fix plan

The fixes cluster into three layers: **memory budgeting**, **visual feedback**, and
**consolidation**. I recommend doing them in this order.

### Step 1 — Replace the 1 MB cap with a per-page cap (Bug #1)

Replace the global `maxIndexedBytes` check with:
- A per-page size cap (e.g., skip pages with text > 500 KB; rare for normal PDFs).
- No global cap.
- A `IndexedPageCount` / `TotalPageCount` getter pair so the UI can show progress.

```dart
// search_index.dart — replace lines 99-127

final totalPages = pages.length;
for (var i = 0; i < pages.length; i++) {
  if (searchDoc.isClosed) break;        // also fixes Bug #9
  if (i > 0 && i % 10 == 0) {
    await Future<void>.delayed(Duration.zero);
  }
  final page = pages[i];
  try {
    if (!page.isLoaded) {
      _skippedPageNumbers.add(page.pageNumber);
      continue;
    }
    final rawText = await page.loadText();
    if (rawText == null) continue;
    final text = rawText.fullText;
    if (text.trim().isEmpty) continue;
    if (text.length > 500 * 1024) {
      // Suspiciously huge page — index the first 500 KB, log warning
      debugPrint('SearchIndex: page ${page.pageNumber} text >500KB, truncating');
      _pageTexts[page.pageNumber] = text.substring(0, 500 * 1024);
      _charRects[page.pageNumber] = rawText.charRects.take(500 * 1024).toList();
    } else {
      _pageTexts[page.pageNumber] = text;
      _charRects[page.pageNumber] = rawText.charRects;
    }
  } on RangeError catch (e) { ... }
  catch (e) { ... }
  _indexedPageCount = _pageTexts.length;
  if (i % 25 == 0) notifyListeners();   // progress updates
}
```

### Step 2 — Store `charRects` alongside `fullText` (Bug #3)

Add a parallel `Map<int, List<PdfRect>> _charRects = {};` populated from
`rawText.charRects`. Add a helper:

```dart
List<Rect> rectsForMatch(int pageNumber, int charOffset, int length) {
  final rects = _charRects[pageNumber];
  if (rects == null) return const [];
  // charOffset/length are in the fullText string. Each char in fullText
  // corresponds to charRects[charOffset ... charOffset+length-1].
  // But fullText uses string indices while charRects is per-character —
  // they align 1:1 because PdfPageRawText is constructed by iterating
  // FPDFText_GetUnicode (one char per charRect). Verified in
  // pdfrx_pdfium.dart:1710-1737.
  final end = (charOffset + length).clamp(0, rects.length);
  return rects.sublist(charOffset, end)
              .map((r) => Rect.fromLTRB(r.left, r.top, r.right, r.bottom))
              .toList(growable: false);
}
```

### Step 3 — Restore match highlighting via a `pagePaintCallbacks` entry (Bug #2)

In `viewer_screen.dart`, re-add the search paint callback:

```dart
pagePaintCallbacks: [
  _buildSearchPaintCallback(),    // ← NEW
  context.read<HighlightProvider>().paintHighlights,
],
```

In `SearchProvider` add:

```dart
void paintSearchMatches(Canvas canvas, Rect pageRect, PdfPage page) {
  if (_matches.isEmpty) return;
  final color = const Color.fromARGB(80, 255, 255, 0);     // light yellow
  final activeColor = const Color.fromARGB(120, 255, 200, 0); // gold
  for (var i = 0; i < _matches.length; i++) {
    final match = _matches[i];
    if (match.pageNumber != page.pageNumber) continue;
    final rects = _index.rectsForMatch(
        match.pageNumber, match.charOffset, match.length);
    if (rects.isEmpty) continue;
    final paint = Paint()
      ..color = (i == _currentMatchIndex ? activeColor : color)
      ..style = PaintingStyle.fill;
    for (final r in rects) {
      // pageRect is in the same coord space as PdfRect (page content space).
      canvas.drawRect(r.translate(pageRect.left, pageRect.top), paint);
    }
  }
}
```

Wire it in `viewer_screen.dart` so it's `context.read<SearchProvider>().paintSearchMatches`.
The function gets re-bound on every build — that's fine, it's a method tear-off.

### Step 4 — Improve `goToCurrentMatch` to scroll within the page (Bug #6)

After re-attaching charRects (Step 2), use the controller's within-page scroll.
pdfrx 2.4.7 doesn't expose a direct `goToRect`, but we can:
- Call `controller.goToPage(pageNumber: match.pageNumber)`.
- Then schedule a post-frame scroll: convert the match rect to viewport coordinates
  via `safeVisibleRect()` (already exists in viewer_screen), compute target scroll,
  and use the controller's `PdfViewerController.goTo` or a direct ScrollController
  on the underlying widget.

If `goTo` isn't available, fall back to `_controller.goToPage(...)` (current
behaviour) — but at least with #3 fixed, the user will see the highlight on the
page and can scroll themselves.

### Step 5 — Fix the listener leak and the open-failure state (Bugs #4 & #5)

In `SearchIndex` add `IndexStatus.error` and `String? errorMessage`:

```dart
enum IndexStatus {
  notIndexed,
  indexing,
  ready,
  noText,        // image-only PDF — text was extracted but empty
  error,         // NEW — couldn't even extract
}

String? _errorMessage;
String? get errorMessage => _errorMessage;
```

In `SearchIndex.buildIndex`, on `document == null` or any catch, set
`_status = IndexStatus.error; _errorMessage = '...';` (not `noText`).

In `viewer_screen.dart:_onViewerReady.kickOffIndexing`, self-remove the listener
unconditionally:

```dart
void kickOffIndexing() {
  _searchDocProvider?.removeListener(kickOffIndexing);  // ALWAYS remove
  if (kickedOff || !mounted) return;
  if (_searchDocProvider?.isReady != true) return;
  kickedOff = true;
  searchProvider.startIndexing(_searchDocProvider!);
  context.read<HighlightProvider>().cachePageTexts(_searchDocProvider!);
}
```

In `_buildSearchButton`, add a new branch for `IndexStatus.error`:

```dart
case IndexStatus.error:
  icon = Icons.error_outline_rounded;
  iconColor = colorScheme.error;
  tooltip = provider.errorMessage ?? 'Search unavailable';
  onPressed = null;
```

### Step 6 — Consolidate text extraction (Bugs #7 & #8)

Make `SearchIndex` and `HighlightProvider` share data. Concretely:

```dart
class PageTextIndex extends ChangeNotifier {
  // Single source of truth for extracted page text + rects.
  final Map<int, PdfPageText> _pages = {};
  IndexStatus _status = IndexStatus.notIndexed;
  String? _errorMessage;

  IndexStatus get status => _status;
  PdfPageText? textFor(int pageNumber) => _pages[pageNumber];
  bool get isReady => _status == IndexStatus.ready;

  Future<void> build(SearchDocumentProvider searchDoc) async { ... }

  /// Case-insensitive substring search returning matches with full
  /// character offsets that map into the PdfPageText for highlight rects.
  List<SearchResult> search(String query) { ... }
}
```

Then:
- `SearchProvider` holds a `PageTextIndex` (instead of its own `SearchIndex`).
- `HighlightProvider` consumes the same `PageTextIndex` for `paintHighlights`
  (its `paintTextHighlight` already takes `PdfPageText`).
- Both `_buildIndex` and `cachePageTexts` go away — `build()` does both jobs.
- Each page is extracted exactly once.

The highlight provider's `_pageTextCache` field becomes redundant — delete it.
The `getOrLoadPageText` method also goes away (just use `textFor`).

### Step 7 — Add a real search test (Bug #12)

Add `test/search_index_test.dart` and `test/viewer_search_test.dart`:

```dart
// test/search_index_test.dart
import 'package:feya_pdf/features/viewer/providers/page_text_index.dart';

void main() {
  test('search returns matches in correct pages with correct offsets', () {
    final index = PageTextIndex();
    // Manually seed without needing a real PDF
    index.seedForTesting({
      1: PdfPageText(pageNumber: 1, fullText: 'hello world',
                     charRects: List.generate(11, (i) => PdfRect(0,0,1,1)),
                     fragments: []),
      2: PdfPageText(pageNumber: 2, fullText: 'another hello here',
                     charRects: ..., fragments: []),
    });
    final results = index.search('hello');
    expect(results.length, 2);
    expect(results[0].pageNumber, 1);
    expect(results[0].charOffset, 0);
    expect(results[1].pageNumber, 2);
    expect(results[1].charOffset, 8);
  });
}
```

And in `test/viewer_integration_test.dart`, add a test that pumps a real
test-PDF, waits for `SearchProvider.indexStatus == IndexStatus.ready`, then
types into the search bar and asserts the match count is correct.

### Step 8 — Clean up (Bugs #10, #11)

- Remove `SearchProvider.safeDetach` (dead code).
- Remove the redundant final `notifyListeners()` in `startIndexing`.
- Make `attach` set fields then notify once (don't rely on `detach`'s notify).

---

## 5. Risk assessment

### Low risk
- Removing the 1 MB cap (#1) — could increase memory for large text-dense PDFs,
  but the existing 1 MB cap *was* the bug. Worst case ~20 MB for a 1000-page dense
  PDF; phones handle this fine.
- Storing `charRects` (#3) — doubles the in-memory size of `_pageTexts` per page.
  ~2–4 MB for a typical 500-page PDF. Fine.
- Removing `safeDetach` (#11) — dead code removal.
- Fixing the listener leak (#4) — strictly less work for GC.

### Medium risk
- Visual match highlighting reintroduction (#2): the rect→canvas transform must
  match pdfrx's content-space. The existing `HighlightProvider._paintTextHighlight`
  is the reference implementation — copy that math, use `pageRect.left/top` for the
  offset (already done in the highlight provider at
  `highlight_provider.dart:399-403`).
- Consolidation (#7/#8): touches `HighlightProvider` and `SearchProvider`
  simultaneously. Run the existing highlight test (`test/highlight_test.dart`)
  after the refactor.

### Higher risk (worth a separate PR)
- Within-page scroll to match (#6): pdfrx 2.4.7 doesn't expose `goToRect` directly.
  You'd need to either use the `PdfViewerController`'s internal scroll state or
  upgrade to a newer pdfrx. Could be deferred to a follow-up — Bug #2 alone is
  enough to make search visibly work.

### Things that could break in other places
- `HighlightProvider.paintHighlights` currently depends on `SearchDocumentProvider`
  (via `cachePageTexts(searchDoc)` and `getOrLoadPageText(searchDoc, ...)`). After
  Step 6 consolidation, the highlight provider no longer needs the search doc
  reference. Search for any callers of `getOrLoadPageText` in `lib/` before
  removing it. (`grep -rn "getOrLoadPageText" lib/` — I checked; the only callers
  are inside `highlight_provider.dart` itself, none outside.)
- `SearchDocumentProvider.getPageText` and `getPageRawText` are also only used
  internally by the highlight/search pipeline. After consolidation, the public
  surface of `SearchDocumentProvider` can shrink to `document`, `isReady`,
  `isClosed`, `error`, `openSearchDocument`, `dispose`.

---

## 6. Verification checklist

After implementing the fix, verify on device:

- [ ] Open a 500+ page PDF — search button becomes enabled within ~5 s.
- [ ] Search for a word on page 1 → matches shown, page jumps, **yellow
      rectangles visible on the matched text**.
- [ ] Search for a word on page 450 → matches shown, page jumps, highlight
      visible.
- [ ] Open an image-only PDF → button shows "image PDF" icon (not "error").
- [ ] Open a corrupted PDF → button shows error icon with reason.
- [ ] Open file A, back, open file B, back, open file A again — search still
      works, no leaked listeners (`debugPrint` "kickOffIndexing" fires once
      per open, not multiple times).
- [ ] With devtools connected, confirm only ONE `loadStructuredText` call per
      page (down from two — once via indexer, once via highlight cache).
- [ ] Run `flutter test test/search_index_test.dart test/viewer_search_test.dart`
      and confirm new tests pass.

---

## 7. Appendix — file-by-file change summary

| File | Change |
|---|---|
| `lib/features/viewer/providers/search_index.dart` | Replace 1 MB cap with per-page cap; add `_charRects`; add `IndexStatus.error` + `errorMessage`; check `searchDoc.isClosed` in loop; add `rectsForMatch` helper. |
| `lib/features/viewer/providers/search_provider.dart` | Add `paintSearchMatches(Canvas, Rect, PdfPage)`; update `goToCurrentMatch` to optionally scroll (Step 4); remove `safeDetach`; remove redundant `notifyListeners()`. |
| `lib/features/viewer/viewer_screen.dart` | Re-add search paint callback in `PdfViewerParams.pagePaintCallbacks`; fix `kickOffIndexing` to always remove listener; handle `IndexStatus.error` in `_buildSearchButton`. |
| `lib/features/viewer/widgets/search_bar.dart` | No change. |
| `lib/features/highlights/highlight_provider.dart` | Remove `_pageTextCache` and `cachePageTexts` and `getOrLoadPageText`; consume the consolidated `PageTextIndex` for `paintHighlights` instead. |
| `lib/features/viewer/providers/page_text_index.dart` (NEW) | The consolidated text store + search engine, replacing `SearchIndex` + `_pageTextCache`. |
| `lib/main.dart` | No change. |
| `test/search_index_test.dart` (NEW) | Unit tests for the consolidated index: search, rect lookup, status transitions. |
| `test/viewer_search_test.dart` (NEW) | Widget test: pump a real PDF, wait for ready, type a query, assert match count + paint callback fires. |

---

*End of report.*