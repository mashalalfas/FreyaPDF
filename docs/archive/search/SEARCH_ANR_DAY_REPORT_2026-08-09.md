# FeyaPDF — Large-PDF Search ANR: On-Device Investigation Report

**Date:** 2026-08-09 (single-day deep dive, release APK + on-device reproduction)
**Author:** AI debugging session (analysis + implementation + device testing)
**Status:** ⚠️ **NOT FIXED on device.** Scan-side fix implemented and verified in CI/tests; the search-toggle CPU storm persists on hardware and still trips ANR. Root cause NOT yet confirmed. See "Remaining unknowns".

---

## 1. TL;DR

1. The app ANRs (Application Not Responding) on the HMD Skyline phone when the user interacts with Search on a large/image-heavy PDF. Reproduced reliably with logcat evidence ("Input dispatching timed out … waited 5002ms for MotionEvent" / "FocusEvent").
2. A scan-side rewrite (§3 of the analysis spec) was implemented: no full-document page loading during search, bounded per-page text, on-demand geometry, hard gates for very large / image-only documents. All unit + integration tests pass (392 + 4 skips), `flutter analyze` clean, release APK builds.
3. **On-device, the search BAR TOGGLE itself causes a 5–12 s CPU storm (~100–200 % CPU, main thread at 100 %, memory +1.4 GB) even on a tiny 0.45 MB / 320-page text PDF, with no query typed.** That storm trips the ANR. Two mitigation attempts (overlay layout + Consumer scoping) are **confirmed present in the installed APK** but did NOT stop the storm.
4. `simpleperf` is blocked by SELinux on this device (even with a debuggable profile build), so the native/Dart stack of the storm was NOT captured yet. The next step is the Dart VM service (profile APK is installed) or widget-bisection builds.

---

## 2. Environment

| Item | Value |
|---|---|
| Phone | HMD Skyline (1080×2400), `adb` device `HH0001ZRM0481600928` |
| Android | targetSdk 36, ~11.4 GB RAM, user "Anu" (locked with PIN — required manual unlock to test) |
| App | `com.feya.feya_pdf` (FeyaPDF) |
| pdfrx | 2.4.7 (`pdfrx`), 0.4.5 (`pdfrx_engine`) |
| Flutter | `/home/max/snap/flutter/common/flutter/bin/flutter` (direct binary, not snap wrapper) |
| Builds | release APK (76.9 MB), profile APK (98.7 MB, debuggable) |
| Test PDFs (generated, pushed to `/sdcard/Download/`) | `scanned_big.pdf` (31.6 MB, 60 pages, 1400×2000 JPEG pages, no text layer), `huge_text.pdf` (0.45 MB, 320 pages of text), `small_text.pdf` (3 pages of text) |

---

## 3. What was implemented (all in working tree)

### 3.1 `lib/features/viewer/providers/search_provider.dart` (rewritten)

- **No `document.loadPagesProgressively()` in search anymore.** The scan only processes pages where `page.isLoaded == true` (pages the viewer already loaded); it never forces the whole document to load.
- `_isCurrent(session)` stale-check **immediately after each `await page.loadText()` and before touching the payload**, so a superseded session never allocates/copies the huge per-character `charRects` on the main isolate.
- Per-page raw-text cap `kMaxPageTextChars = 256 * 1024` before `toLowerCase()` / `indexOf`.
- `charRects` is **never retained** for scanned pages; geometry loads on demand for the **active match page only** (1-page bound, down from 4).
- Hard gate `kMaxTotalPages = 300` → `searchUnavailableReason = "Search is unavailable for very large documents"`, no scan.
- Image-only gate: samples up to 3 already-loaded pages; if all have empty text → `"No searchable text found (image-only document)"`, no scan.
- `kMaxScannedPages = 400` cap → `searchTruncated = true`.
- Pacing: `notifyListeners()` + 16 ms yield after each page, +50 ms every 8 pages.
- `IndexStatus.unavailable` added; `IndexStatus` and `SearchResult` moved into this file (dead `search_index.dart` deleted).
- `toggleSearchBar()` remains pure UI (bool flip + `notifyListeners`; on close also `clearSearch()`). No PDFium call.

### 3.2 `lib/features/viewer/widgets/search_bar.dart`

- New props `searchUnavailableReason` (String?) and `searchTruncated` (bool).
- Renders the unavailable message instead of "No results" when set; shows "Matches limited — refine query" when truncated.

### 3.3 `lib/features/viewer/viewer_screen.dart`

- Search bar moved from the layout `Column` (inside `AnimatedSize`) to a **`Stack` overlay** (`Positioned(top:0,left:0,right:0)`) so toggling does not resize the viewer.
- Overlay wrapped in **`Consumer<SearchProvider>`** so SearchProvider notifications rebuild only the overlay subtree — the main build (and the `PdfViewer`) is no longer subscribed to SearchProvider (no remaining `context.watch<SearchProvider>` in the build path; verified by grep).
- `_buildSearchButton` gained the `IndexStatus.unavailable` case (icon `search_off`, tooltip = reason, `onPressed` always `toggleSearchBar`).

### 3.4 Dead-code cleanup

- Deleted `lib/features/viewer/providers/search_index.dart`, `search_document_provider.dart`, `test/search_index_test.dart` (all tested dead code — only `SearchProvider` is registered in `main.dart`).
- Removed `HighlightProvider.cachePageTexts()` / `getOrLoadPageText()` and their import; kept single-page `cachePageText()` for visible pages only.

### 3.5 Explicitly NOT done (regression guard)

- No full-document indexing on viewer open.
- No second `PdfDocument` for search.
- No `loadStructuredText()` per page from search (only the visible-page highlight cache uses it, unchanged).
- No per-keystroke search (400 ms debounce kept).
- Password feature untouched (`pdf_password_storage.dart`, `pdf_password_dialog.dart`, `_providePdfPassword*` flow verified intact; password tests pass).

---

## 4. CI / static verification (PASSED)

| Gate | Result |
|---|---|
| `flutter analyze` | No issues found |
| Focused tests (`viewer_crash_fix`, `viewer_integration`, `highlight`, `pdf_password_storage`, `pdf_password_dialog`) | 38 passed, 4 headless skips |
| Full suite serial (`flutter test --concurrency=1`) | **392 passed, 4 intentional skips, 0 failures** |
| `flutter build apk --release` | 76.9 MB APK built (one transient Gradle failure on first attempt; clean on retry) |

---

## 5. On-device evidence (logcat)

All ANRs reproduced with `adb logcat -c` → reproduce → `adb logcat -d | rg -i 'ANR|not responding|Input dispatching'`:

```
16:22:16.542  WindowManager: ANR in Window{...}. Reason:Input dispatching timed out (... Waited 5002ms for MotionEvent)
16:22:17.995  ActivityManager: ANR in com.feya.feya_pdf (.MainActivity) Reason: Input dispatching timed out (... 5002ms for MotionEvent)
16:22:54.400  (repeat — second ANR in the same session)
17:02:29.331  WindowManager: ANR ... Reason:Input dispatching timed out (... Waited 5000ms for MotionEvent)   ← NO tap: background storm on scanned PDF
17:04:15.446  ANR ... Waited 5001ms for MotionEvent                                              ← huge_text.pdf, tap-induced
17:09:50.508  ANR ... Waited 5005ms for FocusEvent(hasFocus=true)                                 ← search tap storm window
```

Also observed: `/data/anr/` contains a long history of ANR traces on this device (13:29→14:57 — earlier user repros of the same bug).

`/data/anr/*` files are not readable via `adb shell cat` (permission denied, no root on this device), so the official main-thread trace was NOT obtained.

---

## 6. Experiment log (all on device)

| # | Experiment | Result |
|---|---|---|
| 1 | Open `scanned_big.pdf`, wait 60 s, **no tap** | First session appeared idle (later found to be a parsing artifact / variable). A later clean no-tap run (17:02) showed a **storm: 100–207 % CPU for 20+ s and an ANR** — the image-heavy PDF itself storms on open. |
| 2 | Tap Search on `scanned_big.pdf` (fresh open, ~12 s in) | CPU 144→188 % for ~12 s; memory → **PSS 1.66 GB (1.59 GB "Unknown" native)**; uiautomator dump failed ("null root node"). ANR fired when taps arrived during the window. |
| 3 | Control: tap **Highlights panel** (250 px resize, no search code) | Short spike ~3–4 s (~100 %), then idle → resize itself re-renders; contributed to earlier theory (later superseded). |
| 4 | Per-thread sampling during storm (`top -H`) | **Main thread (TID "m.feya.feya_pdf") at 100 % (R state)**; `DartWorker` (PDFium worker isolate) 16–40 %; rasterizer 0 %. Memory +~100 MB/s. |
| 5 | Open `huge_text.pdf` (320 pages, 0.45 MB), no tap | **Idle at 0.0 % for 40 s, RES 198 MB, no ANR.** Text PDF open is cheap. |
| 6 | Tap Search on `huge_text.pdf` (idle, no typing) | **CPU 100–179 % for ~10 s**, RES → 1.6 GB, DartWorker TIME+ 4.8 s, UI unresponsive to dumps. No ANR only because no further input arrived; earlier session with taps + typing ANR'd (17:04). |
| 7 | Tap **inert viewer area** (540,1200) | 0.0 % CPU — harmless. |
| 8 | Tap **TOC button** (60,346) | ~1 s brief spike (55/15/0) — normal bottom-sheet cost. |
| 9 | Re-verify fix is in the APK | `strings` on installed APK contains `feya-search-bar-overlay` (overlay + Consumer code present; build not stale). |
| 10 | `simpleperf record` | **Blocked: "failed to open perf event file for event_type cpu-cycles: Permission denied"** — SELinux blocks perf on this device, even for the debuggable profile APK. |

**Conclusion from experiments:** the storm is **search-button-specific** (controls #7/#8 are clean), **not PDF-open-specific** (control #5 is clean), and **not caused by** the viewer resize or the main-build rebuild (both eliminated by #9 — fixes are active in the APK — yet the storm persists).

---

## 7. pdfrx internals researched (context for whoever continues)

- `pdfrx_engine-0.4.5/lib/src/native/worker.dart` — **one static singleton `BackgroundWorker` isolate** for ALL PDFium FFI (render, page load, text extraction, links, outline). Everything is serialized on it.
- `pdfrx_engine-0.4.5/lib/src/native/pdfrx_pdfium.dart:1710-1739` — `PdfPage.loadText()` re-loads the page (`FPDF_LoadPage`), opens a text page, and loops every character calling `FPDFText_GetUnicode` **and** `FPDFText_GetCharBox`, building `PdfPageRawText(fullText, charRects)` with **one `PdfRect` per character**. `loadText()` is NOT cheaper than `loadStructuredText()` — both produce full char geometry (engine changelog: loadText+charRects were merged, #434).
- `pdf_viewer_params.dart:717 doChangesRequireReload()` — the fields that force a viewer reload do **not** include `pagePaintCallbacks` or `layoutPages`; `textSelectionParams: const PdfTextSelectionParams()` is const-canonical. So a fresh `PdfViewerParams` instance alone should NOT reload the document. (Params-reload theory therefore considered ruled out.)
- The PdfViewer caches rendered page images; memory grew ~1.4 GB per storm — consistent with (re)rendering of cached pages or a render loop.

---

## 8. Theories tested and ruled out

| Theory | Test | Verdict |
|---|---|---|
| ANR is caused by the search *scan* (per-page `loadText` on the main isolate) | §3 rewrite removed the scan path; storm still occurs on a bare bar toggle with NO query typed | **Ruled out as the toggle trigger** (scan fix is still worth keeping) |
| Opening the search bar *resizes the viewer* (`AnimatedSize` in Column) → pdfrx re-renders | Moved bar to a Stack `Positioned` overlay (no resize) | **Ruled out** (storm persists; code confirmed in APK) |
| Main build rebuilds on `SearchProvider.notify` (old `context.watch<SearchProvider>`), reconstructing `PdfViewer`/params | Scoped to `Consumer<SearchProvider>`; zero `context.watch<SearchProvider>` left in build; verified in APK | **Ruled out** |
| Storm is caused by opening the heavy PDF itself | `huge_text.pdf` (0.45 MB) storms identically on the toggle | **Ruled out as sole cause** |
| The tap is hitting the viewer (pdfrx gesture) | Inert viewer tap = 0 % CPU; TOC tap = 1 s | **Ruled out** |

---

## 9. Remaining unknowns / next steps (for whoever picks this up)

1. **Capture the actual stack.** The single most valuable next step:
   - The profile APK is installed (debuggable). Find the Dart VM service port (`adb shell` netstat / `/proc/net/tcp` for listening ports), `adb forward`, and ask the VM service for isolate stack traces during the storm. 
   - Alternative: `flutter run --profile --pid-file …` + `flutter attach`, then `Observatory`/DevTools timeline + CPU profile of the main isolate.
2. **Widget bisection builds** (fast, ~2 min each) to isolate the storming widget:
   - (a) Overlay shows a trivial `Text` instead of `SearchBarWidget` → does the storm persist? (Isolates `SearchBarWidget`/`TextField` first-build.)
   - (b) Remove `AnimatedSwitcher` (no cross-fade) → does the storm persist? (Isolates the animation.)
   - (c) Remove the bar entirely; toggle a dummy flag → sanity control.
3. **pdfrx render knobs to try** (if a re-render is confirmed): `limitRenderingCache`, `onePassRenderingScaleThreshold`, `onePassRenderingSizeThreshold`, `horizontalCacheExtent`/`verticalCacheExtent` — these bound how many pages are cached/rendered around the viewport (continuous scroll lays out all pages).
4. If the storm is confirmed as a pdfrx re-render on overlay paint: consider keeping the search bar permanently in the tree but offstage/invisible (opacity 0) instead of inserting/removing it, so the layer tree never changes on toggle.
5. Afterwards, re-run the full §4 gate list and the device flow: press Search before typing → type query → verify gates ("Search is unavailable for very large documents" for >300 pages; image-only message for scanned PDFs; working matches + navigation on text PDFs; no ANR in logcat).

---

## 10. Do not regress (from the original brief)

- Password-protected PDFs, remembered passwords, clearing remembered passwords (all verified working, tests pass).
- `toggleSearchBar()` must stay a pure-UI action.
- No full-document indexing on viewer open; no second `PdfDocument` for search; no `loadStructuredText()` per page; no per-keystroke scan.
- Do not claim the ANR is fixed without a fresh physical-device test.

---

## 11. Day 2 hardening + instrumentation (added 2026-08-09)

### 11.1 Deep pdfrx internals analysed

- **`_CustomPainter.shouldRepaint => true`** (pdf_viewer.dart:4879) — **always** repaints the canvas when the painter changes. Without a `RepaintBoundary`, ANY sibling paint or parent repaint re-draws the entire viewer canvas.
- **`page.render()` on completion calls `_invalidate()`** → `_updateStream` → `StreamBuilder` rebuild → `LayoutBuilder` → new `_CustomPainter` → repaint (pdf_viewer.dart:1748,1695,595). This IS a render→repaint cascading loop — but normally bounded because cached pages are skipped (`pageImages.containsKey` guard at line 1703).
- **`loadPagesProgressively` is called ONCE** at doc open (`_loadDelayed`, line 462). Each page-load fires `PdfDocumentPageStatusChangedEvent` → dirties that page's cache + `_invalidate()`. This dirty+render cascade runs during progressive loading but settles once all pages are loaded.
- **`_shouldBuildTextSemantics`** (line 1445) = `forceEnableTextSemantics || SemanticsBinding.instance.semanticsEnabled`. If mounting the `TextField` flips `semanticsEnabled`, pdfrx builds `Focus`+`Semantics` widgets for every line of visible text — bounded to visible pages but still a synchronous widget-tree build. The ANR trace showed a `FocusEvent` variant — consistent with a semantics/focus trigger.
- **`doChangesRequireReload()`** confirmed to NOT include `pagePaintCallbacks`, `pageOverlaysBuilder`, `layoutPages`, or viewer callbacks. Fresh params with same values do NOT trigger a document reload.
- **Confirmed via grep:** zero `context.watch<SearchProvider>` in `ViewerScreen.build()` — only `Consumer<SearchProvider>` scoped to the search button and overlay. `toggleSearchBar → notifyListeners()` does NOT cause `ViewerScreen.build()`.

### 11.2 Changes deployed

**A. RepaintBoundary around the PdfViewer** (`viewer_screen.dart:_buildBody`):

The entire PDF viewer subtree (PdfViewer + draw-mode overlay) is now wrapped in a `RepaintBoundary`. This caches the viewer's paint layer, so sibling overlays (search bar, draw-mode badge) can mount/paint/animate independently — they can never force a viewer repaint or trigger the pdfrx repaint cascade.

**B. RepaintBoundary around the search overlay** (`viewer_screen.dart`):

The `Consumer<SearchProvider> → Positioned` overlay is also wrapped in its own `RepaintBoundary`. Any paint of the search bar (or its children) is confined to the overlay layer.

**C. Removed `AnimatedSwitcher` from the overlay** (`viewer_screen.dart`):

The overlay now uses a plain `search.showSearchBar ? SearchBarWidget(...) : SizedBox.shrink()`. No cross-fade, no animation frames, no scheduled paints during the 180 ms transition. Instant mount/unmount of the search bar widget.

**D. Storm-trace instrumentation** (`search_provider.dart`):

When `kTraceSearchStorm = true` (default), `toggleSearchBar()` on open arms a 12-second trace window. The trace captures:
- **`stormBuildCount`** — incremented every time `ViewerScreen.build()` runs. Direct evidence of whether the main build fires on search toggle.
- **`stormPaintCount`** — incremented every time `paintSearchMatches()` is invoked on pdfrx's canvas. Counts page-paint callbacks, revealing a render cascade.
- **`SemanticsBinding.instance.semanticsEnabled`** — logged at trace start and end. Reveals whether the TextField mount flips semantics, triggering pdfrx's `_buildPageSemanticsWidgets`.

All trace counters are `static` fields on `SearchProvider`. Set `kTraceSearchStorm = false` to compile them out entirely.

### 11.3 CI verification

| Gate | Result |
|---|---|
| `flutter analyze` | No issues found |
| Full test suite (`flutter test --concurrency=1`) | **392 passed, 4 intentional skips, 0 failures** |

### 11.4 Device test instructions

```bash
# Build the profile APK
cd /home/max/Development/FeyaPDF
/home/max/snap/flutter/common/flutter/bin/flutter build apk --profile

# Install on device
adb install build/app/outputs/flutter-apk/app-profile.apk

# Clear logcat, open the app, push test PDFs, tap Search, wait for storm
adb logcat -c
adb logcat | grep -i 'STORM\|ANR\|Input dispatching\|FeyaPDF\|flutter'
```

**The STORM: trace output will appear ~12s after the first search bar toggle.**

Key log lines:
```
STORM: trace armed (search toggle); semanticsEnabled=...
STORM: 12s window result — viewerBuilds=N pagePaints=M semanticsNow=...
```

**Interpretation:**

| viewerBuilds | pagePaints | semantics flip | Meaning |
|---|---|---|---|
| > 0 | any | — | `ViewerScreen.build()` IS running on toggle. A provider subscription was missed. |
| 0 | > 10 | — | Render cascade inside pdfrx. RepaintBoundary may fix it. |
| 0 | 0 | false→true | TextField enabled semantics; pdfrx built per-page Focus+Semantics widgets. |
| 0 | 0 | false | Neither build nor paint fires. Storm is a framework/pdfrx reaction. RepaintBoundary should fix it. |
| — | — | — | **No ANR, no storm** → RepaintBoundary was the fix. Remove `kTraceSearchStorm` instrumentation and commit. |

