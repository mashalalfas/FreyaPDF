# FreyaPDF — Visual Design Review

**Reviewer:** GLM 5.2 (code-only, read-only)
**Date:** 2026-08-14
**Scope:** `lib/theme.dart`, `lib/features/file_management/`, `lib/features/viewer/`, `lib/features/security/widgets/`, `lib/features/settings/`, `lib/features/encryption/widgets/`, `lib/shared/widgets/`, `lib/features/tags/widgets/`

---

## Overall Impression: 7.5 / 10

FreyaPDF is a **well above-average indie Flutter app** with a coherent warm-earth aesthetic that distinguishes it from the generic Material 3 default look. The codebase shows real care — staggered list animations, a custom Lottie splash route, a fullscreen mode that avoids PdfViewer relayouts, a passphrase strength meter with animated tween, and a custom-styled PIN lock screen with shake-on-error. These are not hobbyist touches.

However, it suffers from **inconsistent spacing systems, an under-defined type scale, ad-hoc color usage outside the theme, and action bar overcrowding** that keep it from looking like a polished commercial product (Google Files, ReadEra, Adobe Acrobat). The viewer toolbar in particular is a usability problem masquerading as a feature — 11 icon buttons in a 40-px row.

The foundation is solid. The issues are fixable without restructuring the app. The recommendations below are ranked by visual-design impact.

---

## Top Strengths (with evidence)

### 1. Cohesive warm palette with intentional dark mode
`theme.dart:4-9` defines a tight palette: teal (`#00897B`), amber (`#D4A04A`), warm background (`#FBF8F1`), warm surface (`#F5F0E8`), and dark-mode counterparts (`#1A1C1E`, `#252729`, `#E0B054`). The surface container ramp is custom-tuned (`theme.dart:17-21` light, `theme.dart:49-53` dark) instead of relying on `ColorScheme.fromSeed` defaults. This gives Freya a distinct identity — not just "Material purple."

### 2. Thoughtful card and shadow design
`theme.dart:33-39`: cards use `elevation: 0.5`, `shadowColor` at 4% alpha, and a 1px border at 8% alpha. This " almost-flat-but-not-quite" treatment is the right call for a warm aesthetic — full elevation shadows would look cold against the warm background. The dark-mode equivalent (`theme.dart:57-63`) uses a 12% shadow + 6% white border. Subtle and appropriate.

### 3. Staggered list entrance animation
`home_screen.dart:97-106`: each file tile fades in and translates 12px upward with a per-item delay (`index * 0.03`), capped at 600ms. This is the kind of micro-animation that makes an app feel alive without wasting the user's time. More polished than most open-source Flutter apps.

### 4. Lottie splash route for document open
`lottie_route.dart:1-83`: a custom `PageRouteBuilder` overlays a Lottie animation (`document_open.json`) that fades in, then fades out while the page slides up. The `RepaintBoundary` around the Lottie column and the `errorBuilder` fallback to a PDF icon (`lottie_route.dart:67-74`) show production-level thinking.

### 5. Custom PIN lock screen with shake animation and haptics
`app_lock_screen.dart:201-290`: a full-screen lock with app logo, animated PIN dots (filled/unfilled states), a numeric keypad with `HapticFeedback.lightImpact()` per digit, a shake animation (`_ShakeWidget`, `app_lock_screen.dart:310-350`) on wrong PIN, and a brute-force lockout countdown (`app_lock_screen.dart:155-170`). This is genuinely professional security UX.

### 6. Passphrase dialog with live strength meter
`passphrase_dialog.dart:78-120`: a `TweenAnimationBuilder` animates a `LinearProgressIndicator` that changes color based on strength (weak/medium/strong/veryStrong). Includes "common password" detection (`isCommonPassword`, `passphrase_dialog.dart:38`). The visual feedback is immediate and educational — a model for how password UIs should work.

### 7. Tag system with color dots and filter chips
`tag_chip.dart:1-120` implements Material You-style filter chips with a color dot in compact mode, tinted backgrounds per tag color, and `Tag.contrastFor()` for accessible text on selected chips. The `_TagFilterBar` (`home_screen.dart:510-560`) and `_AllChip` (`home_screen.dart:565-620`) show a proper "All" chip with a check icon — a small but polished detail.

### 8. Encrypted file badge
`encryption_badge.dart:1-22`: a 20×20 circle with `tertiaryContainer` background and `onTertiaryContainer` lock icon. Tiny, consistent, and technology-appropriate — uses the theme's tertiary slot intentionally rather than a hardcoded red/green.

### 9. Reader zoom controls with expand/collapse
`reader_zoom_controls.dart:1-180`: a floating `CircleBorder` button that expands into a pill row of (−, reset, fullscreen, +, collapse) with `AnimatedSwitcher` + `ScaleTransition`. The "never auto-fades" comment (`reader_zoom_controls.dart:12-14`) shows the design decision was informed by user feedback. Clean component.

### 10. Page indicator with inline seek
`viewer_screen.dart:2190-2260`: the page counter is a `PopupMenuButton` that offers "Jump to page…" and "Bookmark this page" — but also switches to an inline `TextField` when seek is activated. The percentage indicator (`viewer_screen.dart:2235`) is a nice touch. This is more elegant than Adobe Acrobat's page slider.

---

## Top 10 Improvement Recommendations (ranked by impact)

### 1. Viewer action bar is critically overcrowded

**What's wrong:** The portrait bottom toolbar (`viewer_screen.dart:1295-1420`) packs **11 icon buttons** into a 40px `Row` with `MainAxisAlignment.spaceEvenly`. The buttons are: TOC, Thumbnails, Dark reading, Highlight, Search, Highlights panel, Bookmark, Save, Share — plus the AppBar already has back, title, search, bookmarks, sort, tags, settings. In landscape (`viewer_screen.dart:1200-1280`), the same buttons are duplicated into the AppBar actions row at 48px height. There is so much density that individual icon hit targets are below the Material minimum of 48×48dp — the `IconButton` default is 48dp but `VisualDensity.compact` + the sheer count makes them feel cramped and un-tappable.

**Why it matters:** This is the single biggest visual-design and usability problem in the app. A reader is for reading. The action bar competes with content for attention and makes the app look like a toolbox, not a reader. Google Files and ReadEra both limit on-screen reader actions to 4-5, putting the rest in an overflow menu.

**Concrete fix:**
- Reduce the bottom toolbar to **4 primary actions**: TOC, Search, Bookmark, More (overflow).
- Move into the overflow menu: Thumbnails, Dark reading, Highlight mode, Highlights panel, Save, Share.
- Remove the landscape `if (landscape) ...` duplicate action list (`viewer_screen.dart:1200-1280`) and use the same 4-action pattern in the AppBar for both orientations.
- Remove the separate `_buildSearchButton` from the bar entirely — it's already available via overflow → Search. Or keep it as one of 4 primary actions if search is used frequently.

**Where:** `viewer_screen.dart:1190-1420`

---

### 2. No defined type scale beyond bodyLarge/bodyMedium

**What's wrong:** `theme.dart:24-27` defines only `bodyLarge` (16/1.6) and `bodyMedium` (14/1.5) in the `textTheme`. Everything else — titles, subtitles, captions, overlines, button text — falls back to Material 3 defaults, which use Roboto sizing. Since Freya bundles Inter (`pubspec.yaml:42-50`), the fallback sizes interact with Inter's metrics in unpredictable ways. Meanwhile, individual widgets define font sizes ad-hoc:
- `home_screen.dart:620`: `'All'` chip text → `fontSize: 11.5`
- `file_list_tile.dart:93-97`: file name → `fontSize: 14`, metadata → `fontSize: 11`
- `home_screen.dart:45-50`: bookmark count → `fontSize: 13`
- `viewer_screen.dart:2431`: page counter → `fontSize: 13`
- `settings_screen.dart:490`: section header → `fontSize: 11` with `letterSpacing: 1.2`
- `secure_folder_screen.dart:290`: empty state body → `fontSize: 12`

There are **at least 15 distinct ad-hoc font sizes** (11, 11.5, 12, 13, 14, 15, 16, 18, 20, 22, 26) used across the app. No system, no rhythm.

**Why it matters:** Typography hierarchy is the #1 thing that separates professional apps from amateur ones. Google Files, ReadEra, and Acrobat each use a defined scale — rarely more than 5 sizes total. Freya's ad-hoc sizes create visual noise and make relative importance unclear.

**Concrete fix:** Define the full `TextTheme` in `theme.dart`:
```dart
textTheme: const TextTheme(
  headlineLarge: TextStyle(fontFamily: 'Inter', fontSize: 28, fontWeight: FontWeight.w700, height: 1.3),
  headlineMedium: TextStyle(fontFamily: 'Inter', fontSize: 22, fontWeight: FontWeight.w600, height: 1.3),
  titleLarge: TextStyle(fontFamily: 'Inter', fontSize: 20, fontWeight: FontWeight.w600, height: 1.4),
  titleMedium: TextStyle(fontFamily: 'Inter', fontSize: 16, fontWeight: FontWeight.w600, height: 1.4),
  titleSmall: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600, height: 1.4),
  bodyLarge: TextStyle(fontFamily: 'Inter', fontSize: 16, height: 1.5),
  bodyMedium: TextStyle(fontFamily: 'Inter', fontSize: 14, height: 1.5),
  bodySmall: TextStyle(fontFamily: 'Inter', fontSize: 12, height: 1.4),
  labelLarge: TextStyle(fontFamily: 'Inter', fontSize: 14, fontWeight: FontWeight.w600),
  labelMedium: TextStyle(fontFamily: 'Inter', fontSize: 12, fontWeight: FontWeight.w500),
  labelSmall: TextStyle(fontFamily: 'Inter', fontSize: 11, fontWeight: FontWeight.w500, letterSpacing: 0.8),
)
```
Then replace all ad-hoc `fontSize: X` values with the nearest `TextTheme` getter. Use `labelSmall` for section headers (grid titles, metadata), `bodySmall` for captions/issues, `titleSmall` for row titles, etc.

**Where:** `theme.dart:24-27`, and every file with hardcoded `fontSize`.

---

### 3. Spacing system is inconsistent — no shared dimensions

**What's wrong:** Padding, margin, and spacing values are defined per-widget with no shared constants:
- `file_list_tile.dart:80`: `EdgeInsets.symmetric(horizontal: 12, vertical: 2)`
- `file_list_tile.dart:87`: inner padding `horizontal: 12, vertical: 10`
- `home_screen.dart:310`: ListView padding `top: 4, bottom: 88`
- `secure_folder_card.dart:60`: card padding `EdgeInsets.all(14)`
- `viewer_screen.dart:1295`: toolbar padding `horizontal: 4`
- `settings_screen.dart:15`: `EdgeInsets.symmetric(vertical: 8)`
- `viewer_screen.dart:2160`: page indicator `horizontal: 12, vertical: 8`

Horizontal margins: 4, 8, 12, 14, 16, 20, 24 — **7 different horizontal spacings** for what is essentially 3 semantic levels (screen edge, card edge, content). Similarly for vertical spacing.

**Why it matters:** Spacing inconsistency is visually subliminal but compounds — things just feel "off" even when you can't point to why. Professional apps use a 4px or 8px grid: 4, 8, 12, 16, 24, 32 — nothing in between.

**Concrete fix:** Create a `lib/core/dimens.dart` with:
```dart
abstract class Spacing {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
  // Drop 14 → use 12 or 16. Drop 10 → use 8 or 12. Drop 6 → use 4 or 8.
}
```
Audit all `EdgeInsets`, `SizedBox(height:)`, and `padding` calls. Replace in-between values (6, 10, 14, 20) with the nearest grid value. The SecureFolderCard's 14px padding should become 12 or 16. The FileListTile's 2px vertical margin should become 4.

**Where:** Every file, but start with `file_list_tile.dart`, `home_screen.dart`, `secure_folder_card.dart`, `settings_screen.dart`.

---

### 4. AppBar actions in home screen are overcrowded (7 actions)

**What's wrong:** `home_screen.dart:172-210`: the home AppBar `actions` contains: Search, Bookmarks, Sort (PopupMenu), Tags, Settings — **5 visible action items + the title logo + 1 overflow** — plus the title itself. On a standard phone (360dp wide), 5 icon buttons at 48dp each = 240dp, leaving ~120dp for the title — which says "Freya PDF" + a 28×28 logo. The title will truncate on narrow devices, and the action density is high relative to the 2-3 actions Google Files shows (search + overflow only).

**Why it matters:** AppBar density affects perceived complexity. ReadEra's home shows just sort + search; Acrobat shows search + account. Freya looks busier than either competitor despite doing the same things.

**Concrete fix:**
- Keep as visible: Search, Sort.
- Move to an overflow "More" menu: Bookmarks, Tags, Settings.
- Or, since Bookmarks is a landing screen (not a toggle), demote it to overflow. Tags and Settings are navigation, not actions — they belong in overflow or a drawer.

**Where:** `home_screen.dart:172-210`

---

### 5. Selection highlight in file list uses 8% primary — too subtle

**What's wrong:** `file_list_tile.dart:62-66`: when `isSelected`, the tile background is `colorScheme.primary.withValues(alpha: 0.08)` — 8% teal on a warm cream background. At 8% alpha, teal on `#F5F0E8` produces a barely-distinguishable tint. The selection check state is not visually obvious enough for a destructive multi-select operation (where the user might delete multiple files).

**Why it matters:** Selection mode is the one place where visual state must be unmistakable. Google Files uses a visible blue tint + a checkmark circle that replaces the file icon. Freya's selection relies on a small Checkbox (`file_list_tile.dart:87-93`) plus the near-invisible tint.

**Concrete fix:**
- Bump selection alpha to `0.15` minimum (light) / `0.20` (dark): `colorScheme.primary.withValues(alpha: 0.15)`.
- Add a left accent stripe (4dp wide, `colorScheme.primary`) when selected — a common pattern in file managers.
- Alternatively, replace the `Hero` file icon (`file_list_tile.dart:79-91`) with a check-circle when selected (Google Files pattern).

**Where:** `file_list_tile.dart:62-91`

---

### 6. Colors.red used directly instead of colorScheme.error

**What's wrong:** Multiple files use `Colors.red` or `Colors.red.shade400` instead of `colorScheme.error` for destructive actions:
- `file_list_tile.dart:211`: `Colors.red.shade400` (delete in context menu)
- `file_list_tile.dart:234`: `Colors.red` (delete button text)
- `home_screen.dart:370`: `Colors.red` (delete confirmation in batch dialog)
- `home_screen.dart:340`: `Colors.red` (batch delete confirmation)

`Colors.red` is `#F44336` (Material 2). `colorScheme.error` is Material 3's error slot, which in Freya's theme maps to a different seed-derived red. Using both creates two different reds in the same app — one from the theme, one hardcoded.

**Why it matters:** Destructive actions are visually critical — but "red" isn't a design decision, it's a color system. Having two reds breaks the system.

**Concrete fix:** Replace every `Colors.red`, `Colors.red.shade400`, `Colors.red.shade500` with `Theme.of(context).colorScheme.error`. If the seeded error color is too washed out, override it in `theme.dart` with `error: Color(0xFFD32F2F)` or similar in the `ColorScheme.fromSeed` call.

**Where:** `file_list_tile.dart:211`, `file_list_tile.dart:234`, `home_screen.dart:340`, `home_screen.dart:370`, plus `secure_folder_screen.dart:80` (which already uses `Colors.red` in the delete dialog).

---

### 7. Colors.amber used directly for favorites star

**What's wrong:** `file_list_tile.dart:135`: the favorite star icon uses `Colors.amber` when `isFavorite` is true. `Colors.amber` is `#FFC107` — a vivid Material 2 yellow-saturated amber that clashes with Freya's custom `_amber` (`#D4A04A`, `theme.dart:5`) which is earthier and desaturated. The favorite star and the `_amber` used in sorts (`home_screen.dart:217`) for "Favorites first" popup menu icon also uses `Colors.amber`, creating two different ambers.

**Why it matters:** The custom amber is one of Freya's design signatures — it's the warm, golden, earthy accent. `Colors.amber` is a generic Flash-orange. They look completely different side by side. The favorite star is the most visible amber usage in the app, and it uses the wrong one.

**Concrete fix:** Define `amber` as a theme color accessible via `colorScheme.secondary` (it's already set as `secondary: _amber` in `theme.dart:18`) and use `colorScheme.secondary` for the favorite star:
```dart
// file_list_tile.dart:135 — replace:
color: isFavorite ? Colors.amber : ...
// with:
color: isFavorite ? Theme.of(context).colorScheme.secondary : ...
```
If `secondary` isn't the right slot for frequent UI accents, add a custom `extension` to `ThemeData`:
```dart
// theme.dart
extension FreyaColors on ThemeData {
  Color get amber => brightness == Brightness.light ? Color(0xFFD4A04A) : Color(0xFFE0B054);
}
```

**Where:** `file_list_tile.dart:135`, `home_screen.dart:217`

---

### 8. Bottom sheets use inconsistent handle-bar and header styles

**What's wrong:** Three different bottom sheet patterns are used:
1. `home_screen.dart:297-311`: bookmarks bottom sheet — handle bar `width: 40, height: 4`, header with `fontSize: 18, fontWeight: w600`.
2. `viewer_screen.dart:750-770`: outline bottom sheet — handle bar `width: 32, height: 4`, header with `fontSize: 18, fontWeight: w600`.
3. `thumbnail_grid.dart:210-230`: thumbnails bottom sheet — handle bar `width: 32, height: 4`, header with `fontSize: 18, fontWeight: w600`.
4. `file_list_tile.dart:155-170`: context menu bottom sheet — handle bar `width: 32, height: 4`.

The bookmarks sheet uses width 40; the others use width 32. Two use `vertical: 12`, two use `vertical: 8`/`vertical: 10`. The context menu has no header at all — just the handle bar and `Divider()`.

**Why it matters:** Bottom sheets are a recurring surface across the app. Inconsistent handle bar widths, vertical paddings, and header structures make the app feel less cohesive than it is.

**Concrete fix:** Create a reusable `BottomSheetHeader` widget in `lib/shared/widgets/`:
```dart
class BottomSheetHeader extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? trailing;
  // ...
  // Standard: handle bar 36×4 @ vertical 10, header 20px padding,
  // fontSize 17 w600, divider below.
}
```
Use it everywhere a bottom sheet appears. Standardize on width 36 (between 32 and 40).

**Where:** `home_screen.dart:297-311`, `viewer_screen.dart:750-770`, `viewer_screen.dart:800-815`, `thumbnail_grid.dart:210-230`, `file_list_tile.dart:155-170`, `settings_screen.dart:310-325` (theme picker).

---

### 9. Empty state icons are undersized and lack visual hierarchy

**What's wrong:** Empty states across the app use `Icon(size: 48)` for the illustration:
- `home_screen.dart:253`: `Icon(Icons.error_outline_rounded, size: 48, ...)` (error state)
- `home_screen.dart:395`: `Icon(Icons.filter_alt_off_outlined, size: 48, ...)` (empty filter)
- `secure_folder_screen.dart:262`: `Icon(Icons.lock_outline_rounded, size: 48, ...)` (empty secure folder)
- `viewer_screen.dart:786`: `Icon(Icons.article_outlined, size: 48, ...)` (no outline)

48dp is the Material minimum tap target, not an illustration size. Real empty-state illustrations are 80-120dp. Freya has a logo asset (`FREYA PDF.png`) — used on the home empty state (`home_screen.dart:233-237`, 64×64) but not elsewhere. The error state in the viewer (`viewer_screen.dart:576-590`) also uses `size: 48`.

**Why it matters:** Empty states are emotional design moments — they're what the user sees when they have no files, which is the first impression. Google Files and ReadEra use custom illustrations at 120-160dp. Freya's 48px generic icons look tactical, not thoughtful.

**Concrete fix:**
- Use the Lottie animation system (already integrated for route transitions) for empty states. Create a `lib/shared/widgets/empty_state.dart` template with:
  - A 120×120 Lottie illustration or custom `CustomPainter` (no extra Lottie asset needed — can use a styled icon in a colored circle).
  - Title (`titleMedium`, 16/600).
  - Subtitle (`bodyMedium` or `bodySmall`, 14 or 12).
  - Action button if applicable.
- For the "No PDFs found" state on home (`home_screen.dart:231-247`), the logo at 64×64 is okay but should be 80-96.
- For error states, use a circle-tinted icon at 72dp: `Container(width: 72, height: 72, decoration: BoxDecoration(color: colorScheme.errorContainer.withValues(alpha: 0.3), shape:BoxShape.circle), child: Icon(Icons.error_outline_rounded, size: 36, color: colorScheme.error))`.

**Where:** `home_screen.dart:231-247`, `home_screen.dart:249-260`, `home_screen.dart:390-410`, `secure_folder_screen.dart:255-280`, `viewer_screen.dart:780-800` (outline empty), `viewer_screen.dart:1780-1800` (error states).

---

### 10. Dialog shapes, padding, and button ordering are inconsistent

**What's wrong:** Most dialogs use `borderRadius: BorderRadius.circular(16)` — good. But:
- `passphrase_dialog.dart:48`: `circular(16)` ✓
- `settings_screen.dart:581` (PIN setup): `circular(20)` — different radius!
- `_confirmDelete` (`file_list_tile.dart:225`): `circular(16)` ✓
- `delete_original_dialog.dart:33`: `circular(16)` ✓
- `pdf_password_dialog.dart:56`: no custom shape → uses default M3 (`circular(28)`) ✗
- Some dialogs use `barrierDismissible: false` (`encrypting_progress_dialog.dart:22`, `delete_original_dialog.dart:27`, `settings_screen.dart:566`) while others dismiss on barrier tap (`passphrase_dialog.dart:35`, `file_list_tile.dart:221`).

Button ordering is also inconsistent:
- Passphrase dialog (`passphrase_dialog.dart:133-139`): Cancel (TextButton) → Set (FilledButton) ✓
- Batch delete (`home_screen.dart:353-368`): Cancel → Delete (red TextButton, NOT FilledButton)
- Delete original (`delete_original_dialog.dart:42-52`): Keep → Delete (both TextButton)
- PIN setup confirm (`settings_screen.dart:625-650`): Cancel → Confirm (FilledButton)

Three different conventions for the destructive action: red `TextButton`, red `FilledButton`, or plain `TextButton`.

**Why it matters:** Dialogs are the highest-stakes interaction surface — they ask the user to make a decision. Inconsistent shapes, dismissibility, and button styles undermine trust. Google's Material 3 dialog spec uses `circular(28)` for the shape; Freya's 16px is fine (intentional override) but must be consistent.

**Concrete fix:**
1. Pick one dialog radius and use it everywhere: either `circular(16)` (current majority) or `circular(28)` (M3 spec). Define it in the theme: `dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))`.
2. Standardize destructive actions: always use `TextButton.styleFrom(foregroundColor: colorScheme.error)` for delete, and always place it as the rightmost action. Use `FilledButton` only for the primary constructive action.
3. Standardize `barrierDismissible: false` for destructive/progress dialogs, `true` for informational dialogs.
4. Fix `pdf_password_dialog.dart` to use the same `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))` as the others.

**Where:** All files with `showDialog` or `AlertDialog`: `passphrase_dialog.dart`, `file_list_tile.dart:221-240`, `home_screen.dart:335-372`, `delete_original_dialog.dart`, `pdf_password_dialog.dart`, `settings_screen.dart`, `secure_folder_screen.dart:70-90`, `biometric_unlock_dialog.dart`.

---

## Quick Wins (< 30 min each)

### QW1: Replace `Colors.red` with `colorScheme.error`
Replace `Colors.red.shade400` (`file_list_tile.dart:211`), `Colors.red` (`file_list_tile.dart:234`, `home_screen.dart:340,370`, `secure_folder_screen.dart:80`) with `colorScheme.error`. Pure find-and-replace, 15 minutes.

### QW2: Replace `Colors.amber` with `colorScheme.secondary`
Replace `Colors.amber` (`file_list_tile.dart:135`, `home_screen.dart:217`) with `Theme.of(context).colorScheme.secondary`. 10 minutes.

### QW3: Standardize bottom sheet handle bar width to 36
Change 40→36 (`home_screen.dart:304`) and 32→36 (`viewer_screen.dart:758`, `viewer_screen.dart:800`, `thumbnail_grid.dart:213`, `file_list_tile.dart:158`, `settings_screen.dart:312`). 10 minutes.

### QW4: Fix PIN setup dialog radius from 20 to 16
`settings_screen.dart:581`: change `BorderRadius.circular(20)` to `circular(16)`. 2 minutes.

### QW5: Add `dialogTheme` to `AppTheme.light()` and `AppTheme.dark()`
In `theme.dart`, add: `dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)))` to both `light()` and `dark()`. This makes all dialogs consistent automatically (except those that override locally). 5 minutes.

### QW6: Bump file selection alpha from 0.08 to 0.15
`file_list_tile.dart:64`: change `alpha: 0.08` to `alpha: 0.15`. 1 minute.

### QW7: Fix PDF password dialog missing custom shape
`pdf_password_dialog.dart:55`: add `shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))` to the `AlertDialog`. 2 minutes.

### QW8: Remove encryption icon duplication in viewer AppBar
`viewer_screen.dart:1190-1196`: an encrypted file shows a lock icon in the title AND a separate disabled lock IconButton in actions. Remove the second one (`viewer_screen.dart:1200-1207`). 5 minutes.

---

## Bigger Redesigns (2+ hours each)

### BR1: Consolidate viewer toolbar to 4 primary actions + overflow
Redesign `viewer_screen.dart` portrait bottom bar and landscape AppBar to share one action pattern. Requires thinking through which 4 actions matter most to a reader.

### BR2: Define and enforce a type scale
Introduce `TextTheme` slots, then sweep the codebase replacing ad-hoc `fontSize` values. Requires touching every text-bearing widget.

### BR3: Introduce a spacing constants file and audit all EdgeInsets
Create `lib/core/dimens.dart`, then systematically replace spacing values across the codebase. Mechanical but time-consuming.

### BR4: Create reusable empty-state widget with illustration
Build `lib/shared/widgets/empty_state.dart` with optional Lottie/custom painter illustration, and replace all 48dp-icon empty states. Requires creating or finding a Lottie asset.

### BR5: Reusable bottom sheet header component
Build `lib/shared/widgets/bottom_sheet_header.dart` and replace all hand-rolled handle bars + headers across the app.

---

## Dark Mode-Specific Notes

### Good
- **Color scheme ramp is properly defined** (`theme.dart:49-53`): `surfaceContainerLowest` through `surfaceContainerHighest` step from `#1A1C1E` to `#3B3D3F`. Five levels, mostly even — slight compression between `surfaceContainer` and `surfaceContainerHigh` (both `#353739`), which is a minor missed opportunity for differentiation.
- **Text colors are explicitly set** (`theme.dart:55-56`): `bodyLarge` = `#E4E4E4`, `bodyMedium` = `#C4C4C4`. This is better than relying on the seed, which often generates washed-out on-surface text.
- **Card borders adapt correctly** (`theme.dart:57-63`): white at 6% alpha on dark, vs. black at 8% on light.
- **Shadow alpha is bumped** (`theme.dart:59`): 12% vs. 4% in light mode, so shadows are actually visible against dark backgrounds.
- **Tag chips select contrast text color** (`tag_chip.dart:41`): uses `Tag.contrastFor(tag.color)` so the text adapts based on luminance.

### Issues
- **`surfaceContainer` == `surfaceContainerHigh`** (`theme.dart:51-52`): both are `#353739`. This means the zoom controls floating button (`reader_zoom_controls.dart:74`) and search bar background (`search_bar.dart:47`) look the same as higher-elevation surfaces. Fix: make `surfaceContainerHigh = #3B3D3F` and `surfaceContainerHighest = #424446`.
- **PIN lock screen hardcodes light background** (`app_lock_screen.dart:260-262`): `final bg = brightness == Brightness.dark ? colorScheme.surface : Color(0xFFF8F9FA)`. The light mode uses `#F8F9FA` (a cool grey-white) which is different from the `_warmBg` (`#FBF8F1`, a warm cream). The lock screen looks like a different app in light mode. Fix: use `_warmBg` directly or `colorScheme.surface`.
- **`_darkBg` and `_darkSurface` are very close** (`theme.dart:7-8`): `#1A1C1E` and `#252729`. The delta is only `#0B0709` — distinguishable but tight. Increase to `#2A2C2E` for `surface` to create more separation between scaffold and cards.
- **Dark reading mode uses ColorFilter matrix inversion** (`viewer_screen.dart:35-47`): a full RGB invert. This works for black-on-white PDFs but inverts colors for all content. A better approach (Adobe Acrobat's Night mode) inverts only the background and text while preserving images/graphics. However, this is standard for Flutter PDF readers and not a significant issue.
- **Reader zoom controls use `surfaceContainerHighest`** (`reader_zoom_controls.dart:76`): in dark mode this is `#3B3D3F`, which is fine but sits close to the page content area. An elevation shadow or a slightly more distinct tone would help it pop against the viewer background.

---

## Summary

FreyaPDF's visual design is **good — genuinely good** — especially for a solo/indie project. The warm palette, the staggered animations, the passphrase strength meter, the custom lock screen — these show real design sensibility. The code quality is high: no leftover debug art, named widgets are well-structured, and the theme system is centralized.

The path from "good indie" to "polished commercial" is mostly about **consistency**: defining a type scale, enforcing spacing, standardizing components (dialogs, bottom sheets, empty states), and **decluttering the viewer toolbar** which is the app's worst visual moment. None of these require architectural changes — they're disciplined sweeps.

The aesthetic identity — warm, earthy, human — is the right call for a PDF reader. Now make it consistent enough that the identity reads everywhere.