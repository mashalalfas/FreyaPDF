// Regression tests for the "Null check operator used on a null value"
// crash that hit ViewerScreen when draw mode was activated while pdfrx's
// internal _viewSize was still null.
//
// The crash was reproducible because pdfrx 1.3.5's PdfViewerController
// implements `viewSize` and `visibleRect` via getters that dereference
// `_viewSize!` / `_state!` internally — so a non-null controller that
// has not yet been laid out throws the moment any code touches those
// getters.
//
// We verify:
//   1. A freshly-constructed (unattached) PdfViewerController actually
//      throws on those getters — confirming the underlying trap.
//   2. ViewerScreen's safe accessors return null instead of propagating.
//   3. Activating draw mode mid-load never throws.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_provider.dart';
import 'package:freya_pdf/features/bookmarks/bookmark_service.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/file_management/file_operations_provider.dart';
import 'package:freya_pdf/features/highlights/highlight_provider.dart';
import 'package:freya_pdf/features/highlights/highlight_service.dart';
import 'package:freya_pdf/features/viewer/providers/search_provider.dart';
import 'package:freya_pdf/features/settings/settings_provider.dart';
import 'package:freya_pdf/features/settings/settings_service.dart';
import 'package:freya_pdf/features/viewer/viewer_screen.dart';
import 'package:provider/provider.dart';

Future<HighlightProvider> _pumpViewerWithDrawMode(
  WidgetTester tester, {
  required bool drawModeActive,
  Size physicalSize = const Size(360, 800),
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();

  final encProvider = EncryptionProvider();
  encProvider.setPassphrase('test');
  final settingsProvider = SettingsProvider(SettingsService(prefs));
  final highlightProvider = HighlightProvider(HighlightService(prefs));
  if (drawModeActive) {
    highlightProvider.setHighlightMode('rectangle');
  }

  tester.view.physicalSize = physicalSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  final dir = Directory.systemTemp.createTempSync('viewer_crash_fix_');
  final file = PdfFile(
    path: '${dir.path}/sample.pdf',
    name: 'sample.pdf',
    sizeBytes: 100,
    modified: DateTime.now(),
  );

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<EncryptionProvider>.value(value: encProvider),
        ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
        ChangeNotifierProvider<FileOperationsProvider>(
          create: (_) => FileOperationsProvider(),
        ),
        ChangeNotifierProvider<AppState>(create: (_) => AppState()),
        ChangeNotifierProvider<HighlightProvider>.value(value: highlightProvider),
        // SearchProvider is accessed via context.read inside ViewerScreen
        // (Tier 2 decoupled search document). Add a minimal instance so
        // the screen can be instantiated in widget tests without crashing.
        ChangeNotifierProvider<SearchProvider>(create: (_) => SearchProvider()),
        ChangeNotifierProvider<BookmarkProvider>(
          create: (_) => BookmarkProvider(BookmarkService(prefs)),
        ),
      ],
      child: MaterialApp(
        home: ViewerScreen(file: file),
      ),
    ),
  );

  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  return highlightProvider;
}

void main() {
  setUpAll(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    'pdfrx PdfViewerController throws when not attached '
    '(documents the underlying trap the fix protects against)',
    () {
      final controller = PdfViewerController();
      // isReady must be false — controller has no viewer attached.
      expect(controller.isReady, isFalse);

      // The very accessors ViewerScreen relied on must throw — this is the
      // crash the user hit on their device.
      expect(() => controller.visibleRect, throwsA(isA<Error>()));
      expect(() => controller.viewSize, throwsA(isA<Error>()));
    },
  );

  testWidgets(
    'ViewerScreen.safeVisibleRect/safeViewSize swallow the trap',
    (tester) async {
      final highlightProvider = await _pumpViewerWithDrawMode(
        tester,
        drawModeActive: true,
      );

      // The state object holds an internal `_pdfController` that the
      // production code-path would touch during the build that creates
      // _DrawPreviewPainter. In the test the controller is null (PDF
      // failed to load), but our safe accessors still must not throw.
      final state =
          tester.state<State<ViewerScreen>>(find.byType(ViewerScreen))
              as dynamic;
      expect(state.safeVisibleRect(), isNull);
      expect(state.safeViewSize(), isNull);

      // Suppress unused warning
      expect(highlightProvider, isNotNull);
    },
  );

  testWidgets(
    'rectangle draw mode does not crash on initial pump',
    (tester) async {
      await _pumpViewerWithDrawMode(tester, drawModeActive: true);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'toggling draw mode mid-load does not crash',
    (tester) async {
      final highlightProvider = await _pumpViewerWithDrawMode(
        tester,
        drawModeActive: false,
      );
      expect(tester.takeException(), isNull);

      highlightProvider.setHighlightMode('rectangle');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
    },
  );
}