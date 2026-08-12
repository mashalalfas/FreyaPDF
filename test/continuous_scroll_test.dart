// Copyright (c) 2026 Freya. All rights reserved.
// Size: small — page-turn mode tests
// (SettingsService with mock SharedPreferences + SettingsProvider)

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';
import 'package:freya_pdf/features/viewer/viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Page Turn — SettingsService', () {
    late SharedPreferences prefs;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs);
    });

    // ── Default value ──
    test('pageTurnMode defaults to false when not set', () {
      expect(service.pageTurnMode, isFalse);
    });

    // ── Persist true ──
    test('setPageTurnMode(true) persists and reads back true', () async {
      await service.setPageTurnMode(true);
      expect(service.pageTurnMode, isTrue);
    });

    // ── Persist false ──
    test('setPageTurnMode(false) persists and reads back false', () async {
      // Start from default (false), set to true, then back to false
      await service.setPageTurnMode(true);
      expect(service.pageTurnMode, isTrue);
      await service.setPageTurnMode(false);
      expect(service.pageTurnMode, isFalse);
    });

    // ── Toggle multiple times ──
    test(
      'pageTurnMode can be toggled multiple times without corruption',
      () async {
        await service.setPageTurnMode(true);
        expect(service.pageTurnMode, isTrue);
        await service.setPageTurnMode(false);
        expect(service.pageTurnMode, isFalse);
        await service.setPageTurnMode(true);
        expect(service.pageTurnMode, isTrue);
        await service.setPageTurnMode(false);
        expect(service.pageTurnMode, isFalse);
      },
    );

    // ── Independent from other settings ──
    test(
      'pageTurnMode is independent of themeMode and autoEncrypt',
      () async {
        await service.setThemeMode('dark');
        await service.setAutoEncrypt(true);
        await service.setPageTurnMode(true);

        expect(service.themeMode, equals('dark'));
        expect(service.autoEncrypt, isTrue);
        expect(service.pageTurnMode, isTrue);

        // Now change only page turn mode
        await service.setPageTurnMode(false);

        expect(service.themeMode, equals('dark'));
        expect(service.autoEncrypt, isTrue);
        expect(service.pageTurnMode, isFalse);
      },
    );

    // ── Survives new instance (reads from same SharedPreferences) ──
    test(
      'pageTurnMode persists across new SettingsService instances',
      () async {
        await service.setPageTurnMode(true);

        // Create a new service backed by the same SharedPreferences instance
        final service2 = SettingsService(prefs);
        expect(service2.pageTurnMode, isTrue);
      },
    );

    // ── Setting to same value is idempotent ──
    test('setting pageTurnMode to same value is idempotent', () async {
      await service.setPageTurnMode(true);
      await service.setPageTurnMode(true); // same value again
      expect(service.pageTurnMode, isTrue);
    });
  });

  group('Page Turn — SettingsProvider', () {
    late SharedPreferences prefs;
    late SettingsService service;
    late SettingsProvider provider;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs);
      provider = SettingsProvider(service);
    });

    // ── Provider defaults ──
    test('pageTurnMode defaults to false', () {
      expect(provider.pageTurnMode, isFalse);
    });

    // ── Provider persist + notify ──
    test('setPageTurnMode(true) updates provider and service', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setPageTurnMode(true);

      expect(provider.pageTurnMode, isTrue);
      expect(service.pageTurnMode, isTrue);
      expect(notified, isTrue);
    });

    // ── Provider set false ──
    test('setPageTurnMode(false) sets provider to false', () async {
      await provider.setPageTurnMode(true);
      expect(provider.pageTurnMode, isTrue);

      await provider.setPageTurnMode(false);
      expect(provider.pageTurnMode, isFalse);
      expect(service.pageTurnMode, isFalse);
    });

    // ── Provider reload ──
    test('reload() re-reads pageTurnMode from service', () async {
      // Set through service directly (bypassing provider)
      await service.setPageTurnMode(true);
      // Provider was initialized with false (from empty prefs)
      expect(provider.pageTurnMode, isFalse);

      await provider.reload();
      expect(provider.pageTurnMode, isTrue);
    });

    // ── Independent from autoEncrypt ──
    test('pageTurnMode and autoEncrypt do not interfere', () async {
      await provider.setPageTurnMode(true);
      await provider.setAutoEncrypt(true);

      expect(provider.pageTurnMode, isTrue);
      expect(provider.autoEncrypt, isTrue);

      await provider.setPageTurnMode(false);

      expect(provider.pageTurnMode, isFalse);
      expect(provider.autoEncrypt, isTrue); // unchanged
    });
  });

  group(
    'Page Turn — layoutPageTurnPages (horizontal side-by-side)',
    () {
      // Simulates an A4 page (595 x 842 pt, 72dpi) on a phone viewport.
      const a4 = Size(595, 842);
      const margin = 8.0;
      const viewportWidth = 360.0;
      const viewportHeight = 780.0;

      test('each page is laid out at or below the viewport width', () {
        final l = layoutPageTurnPages([a4, a4], viewportWidth, margin, viewportHeight);
        final contentWidth = viewportWidth - margin * 2; // 344
        for (final rect in l.pageLayouts) {
          expect(rect.width, lessThanOrEqualTo(contentWidth + 0.001));
        }
      });

      test(
        'narrow pages upscale to fill the width (≤150%)',
        () {
          // A narrow/portrait page must AUTO-ZOOM to fill the screen width,
          // capped at 150%.
          const narrow = Size(200, 300);
          final l = layoutPageTurnPages([narrow], 800, 8, 360);
          final rect = l.pageLayouts.single;
          final contentWidth = 800 - 8 * 2; // 784
          final expectedScale = math.min(1.5, contentWidth / narrow.width);
          expect(rect.width, closeTo(narrow.width * expectedScale, 0.0001));
          // 200 * 1.5 = 300 — the 150% cap stops a tiny page from blowing up.
          // Wait: 784/200 = 3.92, min(1.5, 3.92) = 1.5, so 200*1.5 = 300.
          expect(rect.width, closeTo(300, 0.0001));
        },
      );

      test(
        'A4 fills the width (no side margins within content area)',
        () {
          // The page must zoom in to fill the screen edge-to-edge.
          const vw = 800.0;
          const vh = 360.0;
          final l = layoutPageTurnPages([a4], vw, 8, vh);
          final rect = l.pageLayouts.single;
          final contentWidth = vw - 16; // 784
          expect(rect.width, closeTo(contentWidth, 0.0001));
          expect(rect.left, closeTo(8, 0.0001));
        },
      );

      test('pages are laid out side-by-side (x advances)', () {
        final l = layoutPageTurnPages([a4, a4, a4], viewportWidth, margin, viewportHeight);
        // Each page should be to the right of the previous one.
        for (var i = 1; i < l.pageLayouts.length; i++) {
          expect(
            l.pageLayouts[i].left,
            greaterThan(l.pageLayouts[i - 1].right),
          );
        }
      });

      test('aspect ratio is preserved', () {
        final l = layoutPageTurnPages([a4], viewportWidth, margin, viewportHeight);
        final rect = l.pageLayouts.single;
        const origAspect = 595 / 842;
        expect(rect.width / rect.height, closeTo(origAspect, 0.0001));
      });

      test('document width equals cumulative page widths plus margins', () {
        final l = layoutPageTurnPages([a4, a4], viewportWidth, margin, viewportHeight);
        final contentWidth = viewportWidth - margin * 2; // 344
        final scale = math.min(1.5, contentWidth / a4.width);
        final pageW = a4.width * scale;
        // margin + pageW + margin + pageW + margin
        final expectedWidth = margin + (pageW + margin) + pageW + margin;
        expect(l.documentSize.width, closeTo(expectedWidth, 0.0001));
      });

      test('document height equals tallest page plus margins', () {
        final l = layoutPageTurnPages([a4, a4], viewportWidth, margin, viewportHeight);
        final contentWidth = viewportWidth - margin * 2; // 344
        final scale = math.min(1.5, contentWidth / a4.width);
        final pageH = a4.height * scale;
        expect(l.documentSize.height, closeTo(pageH + margin * 2, 0.0001));
      });

      test('pages are vertically centered within viewport', () {
        const vh = 780.0;
        final l = layoutPageTurnPages([a4], viewportWidth, margin, vh);
        final rect = l.pageLayouts.single;
        final contentWidth = viewportWidth - margin * 2;
        final scale = math.min(1.5, contentWidth / a4.width);
        final pageH = a4.height * scale;
        final expectedY = margin + (vh - margin * 2 - pageH) / 2;
        expect(rect.top, closeTo(expectedY, 0.0001));
      });

      test('a page narrower than the content area fills width (150% cap)', () {
        const small = Size(200, 300);
        final l = layoutPageTurnPages([small], 300, 8, 400);
        final rect = l.pageLayouts.single;
        // contentWidth = 300 - 16 = 284 > 200, so upscale: min(1.5, 284/200) = 1.5
        // Wait: 284/200 = 1.42, min(1.5, 1.42) = 1.42. So width = 200 * 1.42 = 284.
        final contentWidth = 300 - 16; // 284
        final expectedScale = math.min(1.5, contentWidth / small.width);
        expect(rect.width, closeTo(small.width * expectedScale, 0.0001));
      });

      test('empty page list yields margins-only document', () {
        final l = layoutPageTurnPages(const [], viewportWidth, margin, viewportHeight);
        expect(l.pageLayouts, isEmpty);
        expect(l.documentSize.width, equals(margin));
        expect(l.documentSize.height, equals(margin * 2));
      });

      test('zero viewport width produces no division by zero', () {
        final l = layoutPageTurnPages([a4], 0, margin, viewportHeight);
        // scale falls back to 1.0 when contentWidth <= 0
        expect(l.pageLayouts.single.width, equals(a4.width));
      });
    },
  );

  group(
    'Page Turn — landscape page fit (150% fill left-to-right)',
    () {
      // A landscape A4 page (842 x 595 pt) on a phone viewport. The layout
      // fills the width at the default 150% zoom, capped at 1.5x.
      const landscapeA4 = Size(842, 595);
      const margin = 8.0;
      const viewportWidth = 360.0;
      const viewportHeight = 700.0;

      test('landscape page fills the width (≤150%)', () {
        final l = layoutPageTurnPages(
          [landscapeA4],
          viewportWidth,
          margin,
          viewportHeight,
        );
        final rect = l.pageLayouts.single;
        final contentWidth = viewportWidth - margin * 2; // 344
        // Width-fit, capped at 1.5x: 344/842 < 1.5 so it fills the width.
        expect(rect.width, closeTo(contentWidth, 0.0001));
      });

      test('landscape scale is exactly min(contentWidth/width, 1.5)', () {
        final l = layoutPageTurnPages(
          [landscapeA4],
          viewportWidth,
          margin,
          viewportHeight,
        );
        final rect = l.pageLayouts.single;
        final contentWidth = viewportWidth - margin * 2; // 344
        final expectedScale = math.min(1.5, contentWidth / landscapeA4.width);
        expect(rect.width, closeTo(landscapeA4.width * expectedScale, 0.0001));
        expect(rect.height,
            closeTo(landscapeA4.height * expectedScale, 0.0001));
        // Aspect ratio preserved.
        expect(rect.width / rect.height,
            closeTo(landscapeA4.width / landscapeA4.height, 0.0001));
      });

      test('landscape scale is capped at 150% on huge viewports', () {
        // A small page on a huge viewport must never upscale past 1.5x.
        const small = Size(400, 200);
        final l = layoutPageTurnPages([small], 1200, 8, 2000);
        final rect = l.pageLayouts.single;
        expect(rect.width, closeTo(400 * 1.5, 0.0001));
        expect(rect.height, closeTo(200 * 1.5, 0.0001));
      });

      test('layout ignores viewportHeight for scale (fill-width priority)', () {
        // Changing the viewport height must not change the scale.
        const square = Size(400, 300);
        const vw = 400.0;
        const m = 0.0;
        final tall = layoutPageTurnPages([square], vw, m, 2000);
        final short = layoutPageTurnPages([square], vw, m, 150);
        expect(
          tall.pageLayouts.single.width,
          closeTo(short.pageLayouts.single.width, 0.0001),
        );
        expect(
          tall.pageLayouts.single.height,
          closeTo(short.pageLayouts.single.height, 0.0001),
        );
        // Scale is width-fit capped at 1.5: contentWidth/width = 400/400 = 1.0.
        expect(short.pageLayouts.single.width, closeTo(400.0, 0.0001));
        expect(short.pageLayouts.single.height, closeTo(300.0, 0.0001));
      });

      test('page fit-to-width is UNCHANGED by the height param', () {
        // Regression guard: the viewportHeight argument must not change the
        // layout's scale — the page is still width-fit and height is only
        // used for vertical centering.
        const a4 = Size(595, 842);
        final tall = layoutPageTurnPages([a4], 360, 8, 1500);
        final short = layoutPageTurnPages([a4], 360, 8, 300);
        expect(
          tall.pageLayouts.single.width,
          closeTo(short.pageLayouts.single.width, 0.0001),
        );
        expect(
          tall.pageLayouts.single.height,
          closeTo(short.pageLayouts.single.height, 0.0001),
        );
        // But the Y position changes (vertical centering).
        expect(
          tall.pageLayouts.single.top,
          isNot(closeTo(short.pageLayouts.single.top, 0.0001)),
        );
      });
    },
  );
}