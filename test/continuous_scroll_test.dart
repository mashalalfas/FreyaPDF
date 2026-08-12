// Copyright (c) 2026 Freya. All rights reserved.
// Size: small — continuous scroll mode tests
// (SettingsService with mock SharedPreferences + SettingsProvider)

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';
import 'package:freya_pdf/features/viewer/viewer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Continuous Scroll — SettingsService', () {
    late SharedPreferences prefs;
    late SettingsService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      service = SettingsService(prefs);
    });

    // ── Default value ──
    test('continuousScroll defaults to false when not set', () {
      expect(service.continuousScroll, isFalse);
    });

    // ── Persist true ──
    test('setContinuousScroll(true) persists and reads back true', () async {
      await service.setContinuousScroll(true);
      expect(service.continuousScroll, isTrue);
    });

    // ── Persist false ──
    test('setContinuousScroll(false) persists and reads back false', () async {
      // Start from default (false), set to true, then back to false
      await service.setContinuousScroll(true);
      expect(service.continuousScroll, isTrue);
      await service.setContinuousScroll(false);
      expect(service.continuousScroll, isFalse);
    });

    // ── Toggle multiple times ──
    test(
      'continuousScroll can be toggled multiple times without corruption',
      () async {
        await service.setContinuousScroll(true);
        expect(service.continuousScroll, isTrue);
        await service.setContinuousScroll(false);
        expect(service.continuousScroll, isFalse);
        await service.setContinuousScroll(true);
        expect(service.continuousScroll, isTrue);
        await service.setContinuousScroll(false);
        expect(service.continuousScroll, isFalse);
      },
    );

    // ── Independent from other settings ──
    test(
      'continuousScroll is independent of themeMode and autoEncrypt',
      () async {
        await service.setThemeMode('dark');
        await service.setAutoEncrypt(true);
        await service.setContinuousScroll(true);

        expect(service.themeMode, equals('dark'));
        expect(service.autoEncrypt, isTrue);
        expect(service.continuousScroll, isTrue);

        // Now change only continuous scroll
        await service.setContinuousScroll(false);

        expect(service.themeMode, equals('dark'));
        expect(service.autoEncrypt, isTrue);
        expect(service.continuousScroll, isFalse);
      },
    );

    // ── Survives new instance (reads from same SharedPreferences) ──
    test(
      'continuousScroll persists across new SettingsService instances',
      () async {
        await service.setContinuousScroll(true);

        // Create a new service backed by the same SharedPreferences instance
        final service2 = SettingsService(prefs);
        expect(service2.continuousScroll, isTrue);
      },
    );

    // ── Setting to same value is idempotent ──
    test('setting continuousScroll to same value is idempotent', () async {
      await service.setContinuousScroll(true);
      await service.setContinuousScroll(true); // same value again
      expect(service.continuousScroll, isTrue);
    });
  });

  group('Continuous Scroll — SettingsProvider', () {
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
    test('continuousScroll defaults to false', () {
      expect(provider.continuousScroll, isFalse);
    });

    // ── Provider persist + notify ──
    test('setContinuousScroll(true) updates provider and service', () async {
      var notified = false;
      provider.addListener(() => notified = true);

      await provider.setContinuousScroll(true);

      expect(provider.continuousScroll, isTrue);
      expect(service.continuousScroll, isTrue);
      expect(notified, isTrue);
    });

    // ── Provider set false ──
    test('setContinuousScroll(false) sets provider to false', () async {
      await provider.setContinuousScroll(true);
      expect(provider.continuousScroll, isTrue);

      await provider.setContinuousScroll(false);
      expect(provider.continuousScroll, isFalse);
      expect(service.continuousScroll, isFalse);
    });

    // ── Provider reload ──
    test('reload() re-reads continuousScroll from service', () async {
      // Set through service directly (bypassing provider)
      await service.setContinuousScroll(true);
      // Provider was initialized with false (from empty prefs)
      expect(provider.continuousScroll, isFalse);

      await provider.reload();
      expect(provider.continuousScroll, isTrue);
    });

    // ── Independent from autoEncrypt ──
    test('continuousScroll and autoEncrypt do not interfere', () async {
      await provider.setContinuousScroll(true);
      await provider.setAutoEncrypt(true);

      expect(provider.continuousScroll, isTrue);
      expect(provider.autoEncrypt, isTrue);

      await provider.setContinuousScroll(false);

      expect(provider.continuousScroll, isFalse);
      expect(provider.autoEncrypt, isTrue); // unchanged
    });
  });

  group(
    'Continuous Scroll — layoutContinuousScrollPages (fit to viewport)',
    () {
      // Simulates an A4 page (595 x 842 pt, 72dpi) on a phone viewport.
      const a4 = Size(595, 842);
      const margin = 8.0;
      const viewportWidth = 360.0;
      const viewportHeight = 780.0; // portrait pages are height-agnostic

      test('each page is laid out at or below the viewport width', () {
        final l = layoutContinuousScrollPages([a4, a4], viewportWidth, margin, viewportHeight);
        final contentWidth = viewportWidth - margin * 2; // 344
        for (final rect in l.pageLayouts) {
          expect(rect.width, lessThanOrEqualTo(contentWidth));
          expect(rect.right, lessThanOrEqualTo(viewportWidth));
          expect(rect.left, greaterThanOrEqualTo(0));
        }
      });

      test(
        'landscape viewport: narrow pages upscale to fill the width (≤150%)',
        () {
          // Device rotated (viewport wider than tall): a narrow/portrait page
          // must AUTO-ZOOM to fill the screen width, capped at 150% — vertical
          // overflows and scrolls, horizontal is always fully visible.
          const narrow = Size(200, 300);
          final l = layoutContinuousScrollPages([narrow], 800, 8, 360);
          final rect = l.pageLayouts.single;
          final contentWidth = 800 - 8 * 2; // 784
          final expectedScale = math.min(1.5, contentWidth / narrow.width);
          expect(rect.width, closeTo(narrow.width * expectedScale, 0.0001));
          // 200 * 1.5 = 300 — the 150% cap stops a tiny page from blowing up.
          expect(rect.width, closeTo(300, 0.0001));
          // Horizontally centred within the content area.
          final centerOff = (rect.left - 8) + (rect.width / 2);
          expect(centerOff, closeTo(contentWidth / 2, 0.0001));
        },
      );

      test(
        'landscape viewport: portrait A4 fills the width (no side margins)',
        () {
          // The exact user scenario: rotate to landscape, page must zoom in to
          // fill the screen edge-to-edge (Google-Drive style), not sit at
          // native width with wasted side margins.
          const a4 = Size(595, 842);
          const vw = 800.0;
          const vh = 360.0;
          final l = layoutContinuousScrollPages([a4], vw, 8, vh);
          final rect = l.pageLayouts.single;
          final contentWidth = vw - 16; // 784
          expect(rect.width, closeTo(contentWidth, 0.0001));
          expect(rect.left, closeTo(8, 0.0001));
          expect(rect.right, closeTo(vw - 8, 0.0001));
        },
      );

      test('aspect ratio is preserved', () {
        const a4 = Size(595, 842);
        final l = layoutContinuousScrollPages([a4], viewportWidth, margin, viewportHeight);
        final rect = l.pageLayouts.single;
        const origAspect = 595 / 842;
        expect(rect.width / rect.height, closeTo(origAspect, 0.0001));
        expect(rect.right - rect.left, closeTo(rect.width, 0.0001));
      });

      test('document width equals the viewport width', () {
        final l = layoutContinuousScrollPages([a4, a4], viewportWidth, margin, viewportHeight);
        expect(l.documentSize.width, equals(viewportWidth));
      });

      test('document height stacks scaled pages vertically with margins', () {
        final l = layoutContinuousScrollPages([a4, a4], viewportWidth, margin, viewportHeight);
        final scale =
            (viewportWidth - margin * 2) / a4.width; // fit content width, <=1
        final pageH = a4.height * scale;
        final expectedHeight = margin + (pageH + margin) + pageH + margin;
        expect(l.documentSize.height, closeTo(expectedHeight, 0.0001));
        // Each page is horizontally centered.
        for (final rect in l.pageLayouts) {
          final contentWidth = viewportWidth - margin * 2;
          final centerOff = (rect.left - margin) + (rect.width / 2);
          expect(centerOff, closeTo(contentWidth / 2, 0.0001));
        }
      });

      test('a page narrower than the content area keeps natural width and is '
          'centered', () {
        const small = Size(200, 300);
        final l = layoutContinuousScrollPages([small], 300, 8, 400);
        final rect = l.pageLayouts.single;
        // contentWidth = 300 - 16 = 284 > 200, so no upscale: width stays 200.
        expect(rect.width, equals(200));
        // Centered: left = margin + (284 - 200)/2 = 8 + 42 = 50.
        expect(rect.left, closeTo(50, 0.0001));
      });

      test('empty page list yields margins-only document height', () {
        final l = layoutContinuousScrollPages(const [], viewportWidth, margin, viewportHeight);
        expect(l.pageLayouts, isEmpty);
        expect(l.documentSize.width, equals(viewportWidth));
        expect(l.documentSize.height, equals(margin));
      });
    },
  );

  group(
    'Continuous Scroll — landscape page fit (150% fill left-to-right)',
    () {
      // A landscape A4 page (842 x 595 pt) on a phone viewport. The landscape
      // branch fills the width at the default 150% zoom, capped at 1.5x, and
      // does NOT height-constrain (which would re-introduce side margins).
      const landscapeA4 = Size(842, 595);
      const margin = 8.0;
      const viewportWidth = 360.0;
      const viewportHeight = 700.0;

      test('landscape page fills the width (≤150%), no side margins', () {
        final l = layoutContinuousScrollPages(
          [landscapeA4],
          viewportWidth,
          margin,
          viewportHeight,
        );
        final rect = l.pageLayouts.single;
        final contentWidth = viewportWidth - margin * 2; // 344
        // Width-fit, capped at 1.5x: 344/842 < 1.5 so it fills the width.
        expect(rect.width, closeTo(contentWidth, 0.0001));
        // Left/right reach the content edges (centred means margins consumed).
        expect(rect.left, closeTo(margin, 0.0001));
        expect(rect.right, closeTo(viewportWidth - margin, 0.0001));
      });

      test('landscape scale is exactly min(contentWidth/width, 1.5)', () {
        final l = layoutContinuousScrollPages(
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
        // A small landscape page on a huge viewport must never upscale past
        // 1.5x (the new 150% default-zoom cap).
        const small = Size(400, 200);
        final l = layoutContinuousScrollPages([small], 1200, 8, 2000);
        final rect = l.pageLayouts.single;
        expect(rect.width, closeTo(400 * 1.5, 0.0001));
        expect(rect.height, closeTo(200 * 1.5, 0.0001));
      });

      test('landscape ignores viewportHeight (fill-width priority)', () {
        // Even when height-fit would be the binding constraint, the landscape
        // branch keeps the fill-left-to-right scale (≤150%) because that is
        // the priority; changing the viewport height must not change layout.
        const square = Size(400, 300);
        const vw = 400.0;
        const m = 0.0;
        final tall = layoutContinuousScrollPages([square], vw, m, 2000);
        final short = layoutContinuousScrollPages([square], vw, m, 150);
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

      test('portrait page fit-to-width is UNCHANGED by the height param', () {
        // Regression guard: the viewportHeight argument must not change the
        // portrait layout — a portrait page is still width-fit and height-agnostic.
        const a4 = Size(595, 842);
        final tall = layoutContinuousScrollPages([a4], 360, 8, 1500);
        final short = layoutContinuousScrollPages([a4], 360, 8, 300);
        expect(
          tall.pageLayouts.single.width,
          closeTo(short.pageLayouts.single.width, 0.0001),
        );
        expect(
          tall.pageLayouts.single.height,
          closeTo(short.pageLayouts.single.height, 0.0001),
        );
        expect(
          tall.pageLayouts.single.left,
          closeTo(short.pageLayouts.single.left, 0.0001),
        );
      });
    },
  );
}

