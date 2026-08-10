// Copyright (c) 2026 Freya. All rights reserved.
// Size: small — continuous scroll mode tests
// (SettingsService with mock SharedPreferences + SettingsProvider)

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

      test('each page is laid out at or below the viewport width', () {
        final l = layoutContinuousScrollPages([a4, a4], viewportWidth, margin);
        final contentWidth = viewportWidth - margin * 2; // 344
        for (final rect in l.pageLayouts) {
          expect(rect.width, lessThanOrEqualTo(contentWidth));
          expect(rect.right, lessThanOrEqualTo(viewportWidth));
          expect(rect.left, greaterThanOrEqualTo(0));
        }
      });

      test(
        'pages are not upscaled beyond their natural width on wide viewports',
        () {
          // A narrow page on a wide viewport must keep its native size.
          const narrow = Size(200, 300);
          final l = layoutContinuousScrollPages([narrow], 800, 8);
          expect(l.pageLayouts.single.width, equals(200));
        },
      );

      test('aspect ratio is preserved', () {
        const a4 = Size(595, 842);
        final l = layoutContinuousScrollPages([a4], viewportWidth, margin);
        final rect = l.pageLayouts.single;
        const origAspect = 595 / 842;
        expect(rect.width / rect.height, closeTo(origAspect, 0.0001));
        expect(rect.right - rect.left, closeTo(rect.width, 0.0001));
      });

      test('document width equals the viewport width', () {
        final l = layoutContinuousScrollPages([a4, a4], viewportWidth, margin);
        expect(l.documentSize.width, equals(viewportWidth));
      });

      test('document height stacks scaled pages vertically with margins', () {
        final l = layoutContinuousScrollPages([a4, a4], viewportWidth, margin);
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
        final l = layoutContinuousScrollPages([small], 300, 8);
        final rect = l.pageLayouts.single;
        // contentWidth = 300 - 16 = 284 > 200, so no upscale: width stays 200.
        expect(rect.width, equals(200));
        // Centered: left = margin + (284 - 200)/2 = 8 + 42 = 50.
        expect(rect.left, closeTo(50, 0.0001));
      });

      test('empty page list yields margins-only document height', () {
        final l = layoutContinuousScrollPages(const [], viewportWidth, margin);
        expect(l.pageLayouts, isEmpty);
        expect(l.documentSize.width, equals(viewportWidth));
        expect(l.documentSize.height, equals(margin));
      });
    },
  );
}
