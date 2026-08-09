// Size: small — continuous scroll mode tests
// (SettingsService with mock SharedPreferences + SettingsProvider)

import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';
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
    test('continuousScroll can be toggled multiple times without corruption', () async {
      await service.setContinuousScroll(true);
      expect(service.continuousScroll, isTrue);
      await service.setContinuousScroll(false);
      expect(service.continuousScroll, isFalse);
      await service.setContinuousScroll(true);
      expect(service.continuousScroll, isTrue);
      await service.setContinuousScroll(false);
      expect(service.continuousScroll, isFalse);
    });

    // ── Independent from other settings ──
    test('continuousScroll is independent of themeMode and autoEncrypt', () async {
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
    });

    // ── Survives new instance (reads from same SharedPreferences) ──
    test('continuousScroll persists across new SettingsService instances', () async {
      await service.setContinuousScroll(true);

      // Create a new service backed by the same SharedPreferences instance
      final service2 = SettingsService(prefs);
      expect(service2.continuousScroll, isTrue);
    });

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
}
