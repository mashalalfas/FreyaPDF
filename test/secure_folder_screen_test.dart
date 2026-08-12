// Copyright (c) 2026 Freya. All rights reserved.
// Widget tests for the dedicated secure-folder page and the compact home entry
// card. These cover the locked / unlocked-with-files / empty states and that
// tapping the compact card opens the dedicated page.
//
// Uses a mocked path_provider channel + a temp secure dir so the provider's
// listFiles works without real platform channels. Because the screen refreshes
// (auto loadFiles) on open and can momentarily show an indeterminate loading
// spinner, we flush real async file I/O with runAsync and use bounded pumps
// rather than pumpAndSettle (which never settles while a spinner animates).

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_card.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_screen.dart';

const _passphrase = 'secure-folder-widget-test-passphrase';

late Directory _tempRoot;

Directory _secureDir() => Directory('${_tempRoot.path}/FreyaPDF_Secure');

void _pumpSecureChannel(String docsRoot) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (call) async {
      if (call.method == 'getApplicationDocumentsDirectory') {
        return docsRoot;
      }
      return null;
    },
  );
}

void _writeFakeEnc(String name) {
  final dir = _secureDir();
  if (!dir.existsSync()) dir.createSync(recursive: true);
  File('${dir.path}/$name').writeAsBytesSync(
    List.generate(256, (i) => i % 256),
  );
}

/// Let the screen's auto-refresh (provider.loadFiles) finish real file I/O and
/// re-render without relying on pumpAndSettle. A fresh [loadFiles] call running
/// under [WidgetTester.runAsync] completes deterministically and clears the
/// loading spinner, which a bare timer delay does not.
Future<void> _flushLoads(
  WidgetTester tester,
  SecureFolderProvider provider,
) async {
  await tester.pump(); // fire the post-frame init callback → starts loadFiles
  await tester.runAsync(() => provider.loadFiles());
  await tester.pump(); // remove the loading spinner, render the result
  await tester.pump(const Duration(milliseconds: 100));
}

Future<SecureFolderProvider> _unlockedProvider() async {
  final enc = EncryptionProvider()..setPassphrase(_passphrase);
  final provider = SecureFolderProvider()..attachEncryption(enc);
  await provider.unlock();
  return provider;
}

Widget _wrap(SecureFolderProvider provider) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider.value(
        value: EncryptionProvider()..setPassphrase(_passphrase),
      ),
      ChangeNotifierProvider.value(value: provider),
      ChangeNotifierProvider.value(value: AppState()),
    ],
    child: const MaterialApp(
      home: SecureFolderScreen(),
    ),
  );
}

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _tempRoot = Directory.systemTemp.createTempSync('freya_sec_screen_');
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    );
    if (_tempRoot.existsSync()) _tempRoot.deleteSync(recursive: true);
  });

  setUp(() {
    _pumpSecureChannel(_tempRoot.path);
    if (_secureDir().existsSync()) _secureDir().deleteSync(recursive: true);
  });

  group('SecureFolderScreen', () {
    testWidgets('renders locked state with an Unlock button', (tester) async {
      // A fresh provider starts locked.
      final provider = SecureFolderProvider();
      await tester.pumpWidget(_wrap(provider));
      await tester.pump();

      expect(find.text('Secure Folder is locked'), findsOneWidget);
      expect(find.text('Unlock'), findsOneWidget);
      expect(find.byIcon(Icons.lock_rounded), findsWidgets);
    });

    testWidgets('renders empty state when unlocked with no files', (tester) async {
      final provider = (await tester.runAsync<SecureFolderProvider>(
        _unlockedProvider,
      ))!; // empty dir
      await tester.pumpWidget(_wrap(provider));
      await _flushLoads(tester, provider);

      expect(find.text('No files in secure folder'), findsOneWidget);
      expect(find.text('Import files'), findsWidgets);
    });

    testWidgets('renders the encrypted file list when unlocked with files',
        (tester) async {
      _writeFakeEnc('report.pdf.enc');
      _writeFakeEnc('invoice.pdf.enc');

      // Unlock performs real file I/O (scanning the secure dir), so it must run
      // inside runAsync to complete under the fake-async test zone.
      final provider = (await tester.runAsync<SecureFolderProvider>(
        _unlockedProvider,
      ))!;
      await tester.pumpWidget(_wrap(provider));
      await _flushLoads(tester, provider);

      // displayName strips the .enc suffix.
      expect(find.text('report.pdf'), findsWidgets);
      expect(find.text('invoice.pdf'), findsWidgets);
      // The full page owns the list — it renders here and nothing inline on
      // the home card anymore.
      expect(find.byType(SecureFolderScreen), findsOneWidget);
    });
  });

  group('SecureFolderCard (compact entry point)', () {
    testWidgets('shows file count and opens the dedicated page on tap',
        (tester) async {
      _writeFakeEnc('doc.pdf.enc');
      final provider = (await tester.runAsync<SecureFolderProvider>(
        _unlockedProvider,
      ))!;

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: EncryptionProvider()..setPassphrase(_passphrase),
            ),
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: AppState()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SecureFolderCard()),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Compact card shows title + file count (no inline file list).
      expect(find.text('Secure Folder'), findsOneWidget);
      expect(find.text('1 file'), findsOneWidget);
      // The inline list is gone — the file name must NOT appear on home.
      expect(find.text('doc.pdf'), findsNothing);

      // Tapping navigates to the dedicated page.
      await tester.tap(find.text('Secure Folder'));
      await tester.pump();
      // Advance past the default MaterialPageRoute transition so the home route
      // is offstage (its compact chevron/import icons no longer found). Do NOT
      // pumpAndSettle here — the pushed page auto-loads and its indeterminate
      // spinner never settles under the fake-async test zone.
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.byType(SecureFolderScreen), findsOneWidget);
      // (Home is now behind the pushed route; its inline file list is already
      // proven absent above — see find.text('doc.pdf') findsNothing.)
    });

    testWidgets('renders compact locked card without auto-navigating',
        (tester) async {
      final provider = SecureFolderProvider();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider.value(
              value: EncryptionProvider()..setPassphrase(_passphrase),
            ),
            ChangeNotifierProvider.value(value: provider),
            ChangeNotifierProvider.value(value: AppState()),
          ],
          child: const MaterialApp(
            home: Scaffold(body: SecureFolderCard()),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Secure Folder'), findsOneWidget);
      expect(find.text('Tap to open'), findsOneWidget);
      expect(find.byType(SecureFolderScreen), findsNothing);
    });
  });
}
