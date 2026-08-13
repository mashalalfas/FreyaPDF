// Copyright (c) 2026 Freya. All rights reserved.
//
// Regression test for the secure-folder import dialog text-overflow bug:
// long file names (the user imports 4+ files, sometimes with long names) must
// never leak outside the dialog box, both in the selection list and the
// progress view. Overflows surface as RenderFlex overflow exceptions in test
// mode, so we assert none are thrown while rendering a very long filename.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:freya_pdf/features/encryption/encryption_provider.dart';
import 'package:freya_pdf/features/file_management/app_state.dart';
import 'package:freya_pdf/features/security/secure_folder_provider.dart';
import 'package:freya_pdf/features/security/widgets/secure_folder_import_dialog.dart';

const _passphrase = 'secure-folder-overflow-test-passphrase';

late Directory _tempRoot;

Directory _srcDir() => Directory('${_tempRoot.path}/src');
Directory _secureDir() => Directory('${_tempRoot.path}/FreyaPDF_Secure');

void _pumpPathProvider(String docsRoot) {
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

void main() {
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    _tempRoot = Directory.systemTemp.createTempSync('freya_import_over_');
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
    _pumpPathProvider(_tempRoot.path);
    if (_secureDir().existsSync()) _secureDir().deleteSync(recursive: true);
    if (_srcDir().existsSync()) _srcDir().deleteSync(recursive: true);
  });

  Future<void> pumpImportDialog(
    WidgetTester tester,
    AppState appState,
    SecureFolderProvider provider,
  ) async {
    final enc = EncryptionProvider()..setPassphrase(_passphrase);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<EncryptionProvider>.value(value: enc),
          ChangeNotifierProvider<SecureFolderProvider>.value(value: provider),
          ChangeNotifierProvider<AppState>.value(value: appState),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Center(
              child: _ImportDialogHost(),
            ),
          ),
        ),
      ),
    );
    // Open the dialog via the host button so we exercise the real
    // showSecureFolderImportDialog path.
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'selection list renders a very long file name without overflow',
    (tester) async {
      final longName = 'A very long document title that keeps on going and '
          'going and going and going and going and going and going .pdf';
      final src = _srcDir();
      src.createSync(recursive: true);
      File('${src.path}/$longName').writeAsBytesSync(
        List.generate(256, (i) => i % 256),
      );

      final appState = AppState();
      await tester.runAsync(() async {
        await appState.loadDirectory(src.path);
      });

      final provider = SecureFolderProvider();

      await pumpImportDialog(tester, appState, provider);
      await tester.pump();

      // The long file name must be present (ellipsized) with no layout errors.
      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'long filename must not cause a RenderFlex overflow');
      expect(find.byType(CheckboxListTile), findsOneWidget);
    },
  );

  testWidgets(
    'progress view renders a long current-file name without overflow',
    (tester) async {
      final longName = 'Quarterly financial report with an extremely long '
          'descriptive filename for secure archival purposes.pdf';
      final src = _srcDir();
      src.createSync(recursive: true);
      File('${src.path}/$longName').writeAsBytesSync(
        List.generate(256, (i) => i % 256),
      );

      final appState = AppState();
      await tester.runAsync(() async {
        await appState.loadDirectory(src.path);
      });

      final enc = EncryptionProvider()..setPassphrase(_passphrase);
      final provider = SecureFolderProvider()..attachEncryption(enc);
      await tester.runAsync(() => provider.unlock());

      await pumpImportDialog(tester, appState, provider);
      await tester.pump();

      // Select the file so the import button becomes enabled, then start the
      // import so the progress view (with the current filename) is shown.
      await tester.tap(find.byType(CheckboxListTile));
      await tester.pump();
      await tester.tap(find.text('Import (1)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final exception = tester.takeException();
      expect(exception, isNull,
          reason: 'long filename in progress view must not overflow');

      // The progress UI ("Encrypting … of …") is present.
      expect(find.textContaining('Encrypting'), findsOneWidget);
    },
  );
}

/// A tiny host widget providing a tappable button that opens the import dialog.
class _ImportDialogHost extends StatelessWidget {
  const _ImportDialogHost();

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: () => showSecureFolderImportDialog(context),
      child: const Text('open'),
    );
  }
}
