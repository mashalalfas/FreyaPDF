# FreyaPDF Visual Design Review

**Reviewer:** Qwen 3.8 Max (subagent, design-focused read-only audit)
**Date:** 2026-08-14
**Scope:** Full visual design critique from source code — no runtime inspection
**Version reviewed:** 1.5.1+17

---

## Overall Impression: 7.2 / 10

FreyaPDF is *well above average* for an indie Flutter app. The warm earthy palette is distinctive and cohesive, Material 3 is properly adopted (not just `useMaterial3: true` with default seeds), and there's genuine attention to micro-interactions (stagger animations, shake-on-wrong-PIN, pulsing lock icon during encryption). The typography hierarchy is functional, dark mode is clearly considered rather than afterthoughted, and component shapes are consistent.

What keeps it from an 8.5–9 is a collection of *almost-right* decisions: incomplete type scale, inconsistent corner radii across similar components, metadata text that's too small to comfortably read, missing elevation differentiation between surface layers in dark mode, and several places where the design defaults to "safe generic" instead of leveraging the warmth the palette establishes. It reads as a *very good hobby project* or an *early-stage professional product* — the gap to "polished commercial app" is bridgeable with focused refinement, not a redesign.

---

## Top Strengths

### 1. Distinctive, cohesive warm palette
The teal seed (`0xFF00897B`) + amber secondary (`0xFFD4A04A`) + warm off-white surfaces (`0xFFFBF8F1`, `0xFFF5F0E8`) create an identity that immediately distinguishes FreyaPDF from the sea of blue/grey PDF readers. The surface container gradient in light mode (`theme.dart:33-37`) shows someone understood M3 tonal elevation rather than just slapping on a seed color. This is the app's strongest design asset.

**Evidence:** `lib/theme.dart:7-14` (palette constants), `lib/theme.dart:24-38` (light surface containers)

### 2. Proper Material 3 adoption with transparent surface tint
Every themed component explicitly sets `surfaceTintColor: Colors.transparent` (`theme.dart:44,52,61,98,106,115`). This is correct for apps that use custom surface colors — without it, M3 applies an unwanted tint overlay that muddies custom palettes. Most Flutter apps miss this. FreyaPDF doesn't.

**Evidence:** `lib/theme.dart:44,52,61` (light), `lib/theme.dart:98,106,115` (dark)

### 3. Stagger animation on file list load
The `_staggerController` with per-item delay (`index * 0.03`) and combined opacity + translate transform (`home_screen.dart:395-411`) gives the file list a polished cascading entrance. This is exactly the kind of motion detail that separates polished apps from functional ones. The clamp logic prevents items from popping in after animation completes.

**Evidence:** `lib/features/file_management/home_screen.dart:55-58` (controller setup), `:395-411` (stagger builder)

### 4. PIN screen shake animation with proper haptics
The `_ShakeWidget` (`app_lock_screen.dart:393-430`) uses a damped `TweenSequence` (10→-10→8→-8→6→-6→4→-4→2→0) paired with `HapticFeedback.heavyImpact()` on wrong PIN (`:268`). This is textbook security UX feedback — the physical shake + vibration communicates failure more viscerally than a red text label alone.

**Evidence:** `lib/features/security/widgets/app_lock_screen.dart:264-273` (haptics + shake trigger), `:393-430` (shake widget)

### 5. Smart AppBar lifecycle in viewer (no ANR)
The `_AnimatedAppBar` pattern (`viewer_screen.dart:127-154`) keeps the AppBar mounted but collapses `preferredSize` to zero and fades/slides it out. This avoids remounting the PdfViewer body subtree, which would cause pdfrx to re-render from scratch on large files. This is invisible to users but *critical* to perceived quality — nothing kills trust faster than UI freezes when toggling fullscreen.

**Evidence:** `lib/features/viewer/viewer_screen.dart:127-154` (_AnimatedAppBar class)

### 6. Passphrase strength meter with animated transitions
The `TweenAnimationBuilder` wrapping the `LinearProgressIndicator` (`passphrase_dialog.dart:107-121`) smoothly animates strength bar changes rather than snapping. Combined with contextual icons (warning/check/verified) and color coding, this is well-executed security UX that guides users toward better passphrases without being preachy.

**Evidence:** `lib/features/encryption/widgets/passphrase_dialog.dart:107-138`

### 7. Consistent bottom sheet handle bars
Every bottom sheet (bookmarks, outline, thumbnails, theme picker, context menu) includes a drag handle bar with consistent sizing (32-40px wide, 4px tall, rounded, 0.2 alpha onSurfaceVariant). This is a small detail that signals polish and makes sheets feel native.

**Evidence:** `home_screen.dart:195-201`, `viewer_screen.dart:538-544`, `thumbnail_grid.dart:227-233`, `settings_screen.dart:298-304`

---

## Top 10 Improvement Recommendations (Ranked by Impact)

### 1. 🔴 Complete the TextTheme — only 2 of 13 styles are defined
**What's wrong:** `theme.dart:39-42` and `:93-96` define only `bodyLarge` and `bodyMedium`. All other text styles (`headlineLarge`, `titleMedium`, `labelSmall`, etc.) fall back to whatever `ColorScheme.fromSeed` generates. This means every `Text('...', style: Theme.of(context).textTheme.titleMedium)` call gets auto-generated sizing/weight that may not match Inter or the intended hierarchy.

**Why it matters:** Inconsistent type is the single fastest way to make an app look amateur. When some screens use explicit `TextStyle(fontSize: 18, fontWeight: FontWeight.w600)` inline (`home_screen.dart:209`) and others reference undefined theme styles, you get subtle size/weight mismatches across screens. Adobe Acrobat and Moon Reader have meticulously defined type scales.

**Concrete fix:** Define all 13 M3 TextTheme roles in both `light()` and `dark()`:
```dart
textTheme: const TextTheme(
  displayLarge: TextStyle(fontFamily: _fontFamily, fontSize: 57, height: 1.12, fontWeight: FontWeight.w400),
  displayMedium: TextStyle(fontFamily: _fontFamily, fontSize: 45, height: 1.15, fontWeight: FontWeight.w400),
  headlineLarge: TextStyle(fontFamily: _fontFamily, fontSize: 32, height: 1.25, fontWeight: FontWeight.w600),
  headlineMedium: TextStyle(fontFamily: _fontFamily, fontSize: 28, height: 1.29, fontWeight: FontWeight.w500),
  headlineSmall: TextStyle(fontFamily: _fontFamily, fontSize: 24, height: 1.33, fontWeight: FontWeight.w500),
  titleLarge: TextStyle(fontFamily: _fontFamily, fontSize: 22, height: 1.27, fontWeight: FontWeight.w600),
  titleMedium: TextStyle(fontFamily: _fontFamily, fontSize: 16, height: 1.5, fontWeight: FontWeight.w600),
  titleSmall: TextStyle(fontFamily: _fontFamily, fontSize: 14, height: 1.43, fontWeight: FontWeight.w600),
  bodyLarge: TextStyle(fontFamily: _fontFamily, fontSize: 16, height: 1.6),
  bodyMedium: TextStyle(fontFamily: _fontFamily, fontSize: 14, height: 1.5),
  bodySmall: TextStyle(fontFamily: _fontFamily, fontSize: 12, height: 1.43),
  labelLarge: TextStyle(fontFamily: _fontFamily, fontSize: 14, height: 1.43, fontWeight: FontWeight.w600, letterSpacing: 0.1),
  labelMedium: TextStyle(fontFamily: _fontFamily, fontSize: 12, height: 1.33, fontWeight: FontWeight.w600, letterSpacing: 0.5),
  labelSmall: TextStyle(fontFamily: _fontFamily, fontSize: 11, height: 1.45, fontWeight: FontWeight.w600, letterSpacing: 0.5),
),
```
Then audit every inline `TextStyle(fontSize: ...)` in the codebase and replace with theme references. There are ~40+ inline font sizes scattered through home_screen.dart, file_list_tile.dart, and viewer_screen.dart.

**Where:** `lib/theme.dart:39-42,93-96`; audit all files with inline `fontSize:` (~80 occurrences)

**Effort:** Medium-big (2-3 hours for theme + audit)

---

### 2. 🔴 File tile metadata text is too small (11px)
**What's wrong:** Date and file size in `file_list_tile.dart:98-117` use `fontSize: 11` with `alpha: 0.6`. At typical phone viewing distance, 11px at 60% opacity is barely legible. The icons are also 11px. WCAG AA requires 4.5:1 contrast for normal text; at 0.6 alpha on a warm surface, these likely fail.

**Why it matters:** Users scan file lists primarily by name, but secondarily by date/size to find recent documents. If the metadata is squinting territory, the scanning flow breaks. Google Files uses 12px for metadata; ReadEra uses 12-13px.

**Concrete fix:** Bump metadata to `fontSize: 12` and increase alpha to `0.7`. Icons to 13px. This maintains hierarchy (still smaller than the 14px title) while being comfortably readable:
```dart
// file_list_tile.dart:98-117
Icon(Icons.access_time_rounded, size: 13, 
     color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7)),
Text(file.modifiedFormatted,
     style: TextStyle(fontSize: 12, 
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
```

**Where:** `lib/features/file_management/widgets/file_list_tile.dart:93-117`

**Effort:** Quick win (<10 min)

---

### 3. 🟡 Inconsistent border radius across components
**What's wrong:** The app uses at least 6 different border radius values:
- Cards: 12px (`theme.dart:49`)
- FAB: 16px (`theme.dart:57`)
- Input fields: 10px (`theme.dart:66`)
- File tiles: 10px (`file_list_tile.dart:48`)
- Dialogs: 16px (most), 20px (PIN setup `settings_screen.dart:548`)
- Bottom sheets: 16px (some), 20px (bookmarks `home_screen.dart:189`)
- Zoom controls: 28px (`reader_zoom_controls.dart:141`)
- Snackbars: 10px (consistent, at least)

**Why it matters:** Radius inconsistency creates visual noise. Each radius change forces the eye to re-evaluate the shape language. Professional apps pick 2-3 radii and stick to them (e.g., Google Files: 12px cards/sheets, 24px buttons/chips, 28px dialogs).

**Concrete fix:** Standardize on a 3-tier system:
- **Small (8px):** Tag chips, badges, inner elements
- **Medium (12px):** Cards, tiles, input fields, snackbars
- **Large (16px):** Dialogs, bottom sheets, FAB
- **Pill (full/stadium):** Chips, buttons, zoom controls

Update all outliers. The 10px inputs should become 12px. The 20px bookmark sheet should become 16px. The 28px zoom row can stay as pill-shape since it's a floating control cluster.

**Where:** Scattered across `theme.dart`, `file_list_tile.dart`, `home_screen.dart`, `settings_screen.dart`, `reader_zoom_controls.dart`

**Effort:** Quick win (20-30 min)

---

### 4. 🟡 Dark mode surface containers lack differentiation
**What's wrong:** In dark mode (`theme.dart:100-104`), `surfaceContainer` and `surfaceContainerHigh` are *identical* (`0xFF353739`). This means cards, elevated surfaces, and container backgrounds are visually indistinguishable from each other. Light mode has proper gradation (`E8E0D0` → `E5DECF` → `D8D1C2`).

**Why it matters:** Surface differentiation is how M3 communicates depth without shadows. When two adjacent container levels share the same color, the hierarchy flattens and cards blend into backgrounds. This is especially visible in settings where section cards sit on the scaffold.

**Concrete fix:** Add 2-3dp luminance steps between dark containers:
```dart
surfaceContainerLowest: Color(0xFF1A1C1E),  // scaffold bg
surfaceContainerLow: Color(0xFF252729),     // card bg  
surfaceContainer: Color(0xFF2D2F31),       // elevated cards
surfaceContainerHigh: Color(0xFF333537),    // high emphasis
surfaceContainerHighest: Color(0xFF3B3D3F), // highest emphasis
```

**Where:** `lib/theme.dart:100-104`

**Effort:** Quick win (5 min)

---

### 5. 🟡 Empty states use the app logo as illustration
**What's wrong:** The "No PDFs found" empty state (`home_screen.dart:363-370`) uses `Image.asset('assets/logo/FREYA PDF.png', width: 64)` as its hero visual. Same for the lock screen (`app_lock_screen.dart:206-210`). App logos are branding, not illustration. They communicate "this is what the app is called," not "here's what you should do."

**Why it matters:** Empty states are onboarding moments. Google Files uses purpose-drawn illustrations (folder with arrow, magnifying glass). Moon Reader uses an open book graphic. A logo says nothing about the action the user should take. It feels like placeholder art.

**Concrete fix:** Create or source 2-3 Lottie/SVG illustrations:
- **No files:** Open folder with a "+" sparkle (matches the FAB action)
- **Secure folder locked:** Shield with keyhole (already has the circle icon, but an illustration would be warmer)
- **No bookmarks:** Bookmark ribbon with dotted outline

Alternatively, since the app already bundles Lottie (`lottie` package in pubspec.yaml), use a lightweight Lottie animation for the primary empty state. The existing `document_open.json` could be repurposed.

If custom illustrations aren't feasible short-term, at minimum use a large thematic icon (folder_open at 80px, tinted with primary at 0.3 alpha) inside a soft circular background — matching the secure folder locked view pattern (`secure_folder_screen.dart:265-274`) which already does this correctly.

**Where:** `lib/features/file_management/home_screen.dart:363-370`, `lib/features/security/widgets/app_lock_screen.dart:206-210`

**Effort:** Medium (illustration sourcing/creation: 1-2 hours; quick-fix icon treatment: 15 min)

---

### 6. 🟡 Viewer toolbar density varies wildly between portrait and landscape
**What's wrong:** Portrait mode shows a 80px AppBar + 40px bottom toolbar row (`viewer_screen.dart:480-486`) with 8 icon buttons crammed horizontally. Landscape compresses everything into a single 48px AppBar with actions (`:461-479`). The portrait bottom toolbar uses `MainAxisAlignment.spaceEvenly` which spreads buttons unpredictably across widths, and the icons vary in active/inactive styling inconsistently (some use `colorScheme.primary` when active, others use `null`).

**Why it matters:** The reader toolbar is the most-touched UI surface. Inconsistent density and alignment make it feel unpolished compared to Adobe Acrobat's precisely spaced reader bar or Moon Reader's configurable toolbar. The `spaceEvenly` distribution means button spacing changes with device width.

**Concrete fix:**
- Replace `spaceEvenly` with fixed-width tap targets (48×40) in a `Wrap` or fixed-spacing `Row`
- Standardize active state: all active icons use `colorScheme.primary`, all inactive use `onSurfaceVariant.withValues(alpha: 0.7)` (some currently use `null` which resolves differently)
- Consider grouping related actions (TOC + Thumbnails | Highlight + Search | Bookmark + Share) with subtle dividers

**Where:** `lib/features/viewer/viewer_screen.dart:486-560` (portrait bottom toolbar)

**Effort:** Medium (30-60 min)

---

### 7. 🟡 Selection mode AppBar doesn't match main AppBar styling
**What's wrong:** The selection AppBar (`home_screen.dart:432-474`) uses default AppBar styling with no customization. The main AppBar has the warm surface background, custom title style, and logo. When entering selection mode, the entire top chrome shifts to a generic appearance. Also, 6 icon buttons + overflow menu in the actions row is dense — some will overflow on narrow devices.

**Why it matters:** Mode transitions should feel continuous, not jarring. The visual discontinuity breaks immersion. Compare Google Photos' selection mode which smoothly transforms the existing AppBar rather than replacing it.

**Concrete fix:** Keep the same AppBar theme (it inherits from theme.dart, so this may already work — verify). More importantly, move less-frequent batch actions (secure folder move) into the overflow menu, keeping only delete + share + tag + encrypt as direct actions. Use `IconButton` with `visualDensity: VisualDensity.compact` for all selection actions.

**Where:** `lib/features/file_management/home_screen.dart:432-474`

**Effort:** Quick win (15 min)

---

### 8. 🟢 Page indicator bar uses raw Container instead of themed surface
**What's wrong:** The page navigation bar (`viewer_screen.dart:880-953`) builds a custom `Container` with manual decoration rather than using themed surfaces. The background color, borders, and text styles are all hardcoded inline. This means it won't automatically respond to theme changes and duplicates color logic.

**Why it matters:** Maintenance burden and consistency risk. If the surface color scheme changes, this bar needs manual updating.

**Concrete fix:** Wrap in a `BottomAppBar` or use `colorScheme.surfaceContainerLow` with `Border.top` using `outlineVariant`. Extract the page counter tap-to-seek dialog into its own widget for readability.

**Where:** `lib/features/viewer/viewer_screen.dart:880-953`

**Effort:** Quick win (20 min)

---

### 9. 🟢 Encryption badge positioning is fragile
**What's wrong:** The `EncryptionBadge` is positioned via `Positioned(right: 24, top: 12)` in a Stack wrapping each file tile (`home_screen.dart:509-513`). This hardcodes pixel offsets that assume specific tile padding. If tile padding changes, the badge drifts. Also, the badge overlaps the chevron/favorite area and could occlude content on narrow screens.

**Why it matters:** Fragile positioning leads to visual bugs across device sizes and after layout refactors.

**Concrete fix:** Move the badge *inside* the FileListTile widget, positioned within the trailing column alongside the favorite star and chevron. This makes it part of the tile's intrinsic layout rather than an overlay.

**Where:** `lib/features/file_management/home_screen.dart:505-514`, `lib/features/encryption/widgets/encryption_badge.dart`

**Effort:** Quick win (15 min)

---

### 10. 🟢 No transition animation for theme switching
**What's wrong:** When changing themes in Settings → Theme picker (`settings_screen.dart:309-341`), the theme change is instant. There's no crossfade or animated transition between light/dark/system modes.

**Why it matters:** Instant theme switches feel jarring. Android's system theme toggle uses a smooth crossfade. Adding even a 200ms animated transition makes the switch feel intentional rather than glitchy.

**Concrete fix:** Wrap the MaterialApp's theme in an `AnimatedTheme` widget (built into Flutter), or use `AnimatedSwitcher` around the root widget keyed on theme mode. This is a one-line change if the app uses `MaterialApp(theme:)` properly.

**Where:** App root (likely `main.dart`); theme picker at `lib/features/settings/settings_screen.dart:309-341`

**Effort:** Quick win (10 min)

---

## Quick Wins (<30 min each)

| # | Task | Time | File(s) |
|---|------|------|---------|
| 1 | Bump file tile metadata from 11px/0.6α to 12px/0.7α | 10 min | `file_list_tile.dart:93-117` |
| 2 | Fix dark mode surfaceContainer = surfaceContainerHigh collision | 5 min | `theme.dart:102-103` |
| 3 | Standardize border radii (10→12 for inputs, 20→16 for sheets) | 20 min | `theme.dart`, `home_screen.dart`, `settings_screen.dart` |
| 4 | Move EncryptionBadge inside FileListTile trailing column | 15 min | `home_screen.dart:505-514`, `file_list_tile.dart` |
| 5 | Add AnimatedTheme for theme switch transitions | 10 min | `main.dart` |
| 6 | Selection AppBar: add visualDensity.compact to actions | 10 min | `home_screen.dart:432-474` |
| 7 | Page indicator: use themed surface colors | 20 min | `viewer_screen.dart:880-953` |
| 8 | Remove duplicate code in biometric_unlock_dialog passphrase UI (copy-pasted from passphrase_dialog.dart) | 25 min | `biometric_unlock_dialog.dart:130-260` |

## Bigger Redesigns (>1 hour)

| Task | Est. Time | Notes |
|------|-----------|-------|
| Complete TextTheme (all 13 styles) + audit inline TextStyles | 2-3 hrs | Highest overall impact on polish |
| Custom empty state illustrations (Lottie or SVG) | 2-4 hrs | Includes asset creation/sourcing |
| Viewer toolbar redesign (grouped actions, consistent active states) | 1-2 hrs | Most-touched surface deserves precision |
| Extract shared bottom sheet header widget | 1 hr | Handle bar + title + count pattern repeated 5+ times |
| Responsive layout audit (tablet/landscape adaptations) | 2-3 hrs | Only viewer has landscape-specific code currently |

---

## Dark Mode-Specific Notes

### ✅ What works well
- **Surface tint suppression** is correctly applied everywhere — no muddy overlays
- **Divider alpha** is appropriately lower in dark (0.06 vs 0.08 in light) — `theme.dart:73,127`
- **Card borders** use white at 0.06 alpha in dark vs black at 0.08 in light — correct directional contrast (`theme.dart:50,104`)
- **Tag chip colors** adapt properly with separate light/dark alpha paths (`tag_chip.dart:51-59`)
- **Lock screen background** uses a slightly lighter shade (`0xFFF8F9FA` light, `surface` dark) — appropriate differentiation (`app_lock_screen.dart:199-201`)

### ⚠️ Issues to address
1. **surfaceContainer = surfaceContainerHigh** (`theme.dart:102-103`): Both are `0xFF353739`. Cards on elevated surfaces disappear. Fix: differentiate by 2-3dp luminance.

2. **Text colors are partially hardcoded**: `bodyLarge` specifies `Color(0xFFE4E4E4)` and `bodyMedium` specifies `Color(0xFFC4C4C4)` (`theme.dart:94-95`), but any widget using `colorScheme.onSurface` directly gets the auto-generated value which may differ. Either let the color scheme drive all text colors, or explicitly set `onSurface` in the copyWith.

3. **AppBar foreground is hardcoded** (`theme.dart:108`): `Color(0xFFE4E4E4)` matches bodyLarge but isn't linked to it. If you later adjust body text brightness, the AppBar won't follow. Use `colorScheme.onSurface` instead.

4. **Input fill alpha too low in dark**: `0xFFFFFFFF.at(0.04)` (`theme.dart:118`) produces a near-invisible fill on dark surfaces. Bump to 0.06-0.08 for adequate affordance.

5. **Navigation indicator alpha difference** is minimal: light uses `0.15` (`theme.dart:54`), dark uses `0.2` (`theme.dart:108`). The dark indicator should be slightly more opaque (0.25-0.3) since teal on dark surfaces has lower perceived contrast than teal on warm cream.

6. **Search bar border** uses `outlineVariant.at(0.3)` (`search_bar.dart:78`) which may be too subtle against dark surfaces. Test on actual device — might need 0.4-0.5.

---

## Component-by-Component Notes

### Cards (`theme.dart:46-52`)
Good: Low elevation (0.5) with subtle shadow, transparent tint, bordered shape. The 1px border at 8% alpha is a nice touch that adds definition without heaviness. Matches modern M3 "outlined card" aesthetic.

### FAB (`theme.dart:54-59`)
The 16px radius on the FAB is slightly unusual (M3 default is 12px for small, 16px for large). Since there's only one FAB and it uses the default size, consider 12px for consistency with cards, or explicitly make it a `FloatingActionButton.large` with 16px to signal intentionality.

### Bottom Sheets
Consistently use `DraggableScrollableSheet` with `initialChildSize: 0.6-0.85`, which is good. Handle bars are present everywhere. However, the bookmark sheet (`home_screen.dart:189`) uses `borderRadius.vertical(top: Radius.circular(20))` while others use 16px — standardize to 16px.

### Dialogs
All use `borderRadius: BorderRadius.circular(16)` except PIN setup which uses 20px (`settings_screen.dart:548`). The passphrase dialog's strength meter is excellent. Delete confirmation dialogs correctly use red for destructive action. Good use of `barrierDismissible: false` for safety-critical dialogs.

### Snackbars
Consistently floating with 10px radius across the entire app. This is good consistency. However, they're all created inline — extracting a `FreyaSnackBar.show(context, message)` helper would reduce duplication and ensure future changes propagate.

### Tag Chips (`tag_chip.dart`)
Excellent implementation. Separate compact/full modes, proper light/dark color adaptation, animated container transitions, dot + label combo in compact mode. One of the best-executed components in the app.

---

## Summary

FreyaPDF has strong bones. The warm palette is distinctive, M3 adoption is mostly correct, and there are genuine moments of delight (stagger animation, shake feedback, pulsing encryption dialog). The path from 7.2 to 8.5 is clear: complete the type scale, fix the dark mode surface differentiation, bump metadata readability, standardize radii, and invest in proper empty state illustrations. None of these require architectural changes — they're refinements to an already solid foundation.

The code quality supports the design quality: clean separation, proper use of providers, thoughtful comments explaining *why* (not just *what*), and defensive patterns around async/mounted checks. This is a codebase that can absorb design polish without fighting back.
