# FreyaPDF — Consolidated Design Improvement Plan

**Date:** 2026-08-14
**Sources:** GLM 5.2 review (`DESIGN_REVIEW_GLM52.md`, score 7.5/10) · Qwen 3.8 Max review (`DESIGN_REVIEW_QWEN38.md`, score 7.2/10) · 3DUIUX design DNA (`~/Development/3DUIUX/SKILL.md`)
**Target:** v1.5.x → visually polished release
**Guiding constraint:** ⚠️ **Avoid the Generic AI look** — no purple gradients, no glassmorphism-by-default, no single-sans-font-everything, no cookie-cutter uniform grids. Freya's warm identity is the asset; this plan sharpens it instead of normalizing it.

---

## Part 1 — The 3DUIUX Design DNA (the "character layer")

The 3DUIUX template's aesthetic (warm fog palette `#fdf5ea`, editorial display type, tactile cursor, atmospheric depth, seeded organic variation) is not a tech stack — it's a **design philosophy** that translates 1:1 to a Flutter reader app:

| 3DUIUX DNA | What it means for FreyaPDF |
|---|---|
| **Warm atmospheric palette** | ✅ Freya already has it (`#FBF8F1`, `#D4A04A` amber, teal seed). This is *validation*, not a change. Lean in — never cool-grey the surfaces. |
| **Editorial typography** | The #1 anti-AI-look lever. Pair a **display serif or warm grotesque** for titles with Inter for body. One distinctive type personality beats 13 generic sizes. |
| **Tactile hand-crafted details** | Freya has shake+haptics, stagger, pulsing lock. Extend the same *physicality* to empty states, theme switch, selection mode. |
| **Atmospheric depth, not flat layers** | Fix the dark-mode surface collision; use soft glow/tonal elevation instead of heavy shadows. |
| **Organic variation (seeded)** | Staggered list is good. Add subtle per-tile variation (tiny rotation/delay jitter) so lists don't read as "AI-generated uniform grid." |
| **Premium restraint** | Fewer, bigger actions. Viewer toolbar: 11 buttons → 4 + overflow. Restraint IS the luxury signal. |

**Anti-AI-look guardrails (do NOT do):**
- ❌ No `LinearGradient` purple/blue hero headers
- ❌ No frosted-glass everywhere
- ❌ No emoji as icons
- ❌ No perfectly uniform identical cards (no visual rhythm)
- ❌ No AI-cliché copy like "Your trusted reading companion" in empty states
- ❌ No 3D-render logos or generic illustration packs — custom Lottie or hand-tuned CustomPaint only

---

## Part 2 — Consolidated Fix List (merged from both reviews)

Deduped across GLM + Qwen. Each item lists both reviewers' agreement.

### 🟥 P0 — Do these first (biggest visual impact)

**P0-1. Complete the TextTheme + type personality** *(GLM #2 · Qwen #1 — unanimous #1/#2)*
- Define all 13 M3 text roles in `theme.dart` light+dark (both reviews provide full code).
- Sweep ~80 inline `fontSize:` occurrences → theme references.
- **Anti-AI add:** add a display font (e.g., a warm serif like Fraunces/Libre Caslon, or a characterful grotesque) for `headlineLarge`/`titleLarge`. One pairing decision defines the app's personality.
- Files: `lib/theme.dart`, all widgets with inline styles. Effort: 2-3h.

**P0-2. Viewer toolbar declutter** *(GLM #1 · Qwen #6)*
- 11 icon buttons in a 40px row → **4 primary actions** (TOC, Search, Bookmark, More) + overflow (Thumbnails, Dark reading, Highlight, Highlights panel, Save, Share).
- Fix landscape duplicate action list; consistent active-state coloring (`primary` vs `onSurfaceVariant@0.7`).
- Files: `viewer_screen.dart:1190-1420`. Effort: 1-2h.

**P0-3. Dark mode surface ramp fix** *(GLM dark-note · Qwen #4)*
- `surfaceContainer` == `surfaceContainerHigh` (`#353739` both) → differentiate: `#2D2F31` / `#333537` / `#3B3D3F`.
- Fix hardcoded text colors that won't track theme (`bodyLarge`/`bodyMedium` hex, AppBar foreground).
- Files: `theme.dart:49-53, 93-96, 100-108`. Effort: 30 min.

### 🟨 P1 — High-value consistency sweep

**P1-1. Spacing system** *(GLM #3)* — `lib/core/dimens.dart` with 4/8/12/16/24/32 grid; audit 6/10/14/20 outliers. Effort: 1-2h.

**P1-2. Radius standardization** *(Qwen #3 · GLM #10)* — 3-tier: 8px chips/badges · 12px cards/inputs · 16px dialogs/sheets/FAB; kill 10px/20px outliers. Effort: 30 min.

**P1-3. Bottom sheet standardization** *(GLM #8 · Qwen component notes)* — shared `BottomSheetHeader` widget: handle 36×4 @ vertical 10, header 17/w600, radius 16. 5+ call sites. Effort: 1h.

**P1-4. File tile metadata legibility** *(Qwen #2)* — 11px/0.6α → 12px/0.7α, icons 13px. Effort: 10 min.

**P1-5. Color system hygiene** *(GLM #6, #7)* — `Colors.red` → `colorScheme.error` (4 sites); `Colors.amber` → `colorScheme.secondary` (2 sites). Effort: 15 min.

**P1-6. Empty states get character** *(GLM #9 · Qwen #5)* — shared `EmptyState` widget: 72-96px tinted-circle icon or repurposed Lottie; title `titleMedium` + subtitle + action. Replace all 48px-icon empty states. **Anti-AI:** custom Lottie or CustomPaint, never stock illustration packs. Effort: 1-2h (widget) + asset time.

**P1-7. Home AppBar density** *(GLM #4)* — 5 visible actions → Search + Sort visible, Bookmarks/Tags/Settings → overflow. Effort: 20 min.

**P1-8. Selection state clarity** *(GLM #5)* — selection alpha 0.08 → 0.15 (light) / 0.20 (dark) + optional 4dp accent stripe. Effort: 10 min.

### 🟩 P2 — Polish & motion

**P2-1. AnimatedTheme on theme switch** *(Qwen #10)* — wrap MaterialApp in `AnimatedTheme` (200ms crossfade). Effort: 10 min.

**P2-2. Selection AppBar continuity** *(Qwen #7)* — match main AppBar styling, `VisualDensity.compact`, overflow the rare batch actions. Effort: 15 min.

**P2-3. Page indicator themed surface** *(Qwen #8)* — replace raw Container with `surfaceContainerLow` + `outlineVariant` border. Effort: 20 min.

**P2-4. Encryption badge into tile layout** *(Qwen #9)* — move from `Positioned(right:24, top:12)` overlay into tile trailing column. Effort: 15 min.

**P2-5. Dialog consistency** *(GLM #10)* — `dialogTheme` radius 16 in both themes; destructive action = rightmost `TextButton` in `error`; `barrierDismissible:false` for destructive/progress only. Effort: 30 min.

**P2-6. Lock screen light-mode bg** *(GLM dark-note)* — `#F8F9FA` cool grey → `_warmBg`/`colorScheme.surface` so lock matches the app. Effort: 5 min.

**P2-7. Snackbar helper** *(Qwen component notes)* — `FreyaSnackBar.show()` to kill duplication. Effort: 20 min.

---

## Part 3 — Suggested Execution Order

**Phase A (consistency foundation, ~1 soldier day):** P0-3 → P1-2 → P1-4 → P1-5 → P1-8 → P2-5 → P2-6 — all mechanical, low risk, huge polish-per-hour.

**Phase B (structure, ~1 soldier day):** P0-1 (type scale + display font pairing) → P1-1 (spacing grid) → P1-3 (bottom sheet widget) → P1-7.

**Phase C (character, ~1-2 soldier days):** P0-2 (viewer toolbar redesign) → P1-6 (empty states + custom Lottie) → P2-1/2/3/4 (motion & continuity) → **FAB speed-dial file manager** (below).

**🆕 Phase C+ — FAB speed-dial file manager (Mashal-approved 2026-08-15):**
- FAB expands **vertically** with two options: 📄 **File** | 📁 **Folder** (no new screen, no custom file-browser UI — native SAF picker is the file finder)
- **File** → `FilePicker.pickFiles(type: custom, pdf, allowMultiple: true)` → each selected PDF imported **individually** into the library (copied into app storage so library entries survive the original being moved/deleted)
- **Folder** → existing `_pickDirectory()` bulk-scan flow, unchanged
- Motion: staggered expansion + light haptics (Freya's existing tactile patterns)
- Future hook: third "Browse" option if an in-app browser is ever wanted
- Effort: ~½ soldier day

**Phase D (verification):** `flutter analyze` + full suite after each phase; release bump + build + install + Drive after B and C.

---

## Part 4 — The One Decision That Sets the Personality

Every other item is consistency. This one is identity: **the display font.**

- Option A (editorial/classic): serif display (Fraunces, Libre Caslon, Source Serif) for titles + Inter body → literary, premium, PDF-authentic.
- Option B (warm grotesque): a characterful sans (e.g., Sora, Space Grotesk, Manrope) for display + Inter body → modern, warm, techy.
- Keep the amber/teal/warm-cream palette untouched — it's already the brand.

**Recommendation: Option A (serif display).** A PDF reader is a reading app; editorial serif titles say "this is about documents" instantly, and it's the strongest possible anti-AI-look signal since AI-generated UIs almost always default to sans-only.
