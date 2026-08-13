// Copyright (c) 2026 Freya. All rights reserved.
// Widget tests for the "Delete original?" confirmation dialog shown after
// encryption, plus the keep/delete seam the encrypt handlers rely on.

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/file_management/file_operations_provider.dart';
import 'package:freya_pdf/features/file_management/widgets/delete_original_dialog.dart';

/// Pump a host widget whose button, when tapped, opens [showDeleteOriginalDialog]
/// and completes [result] with its return value.
Future<void> _open(
  WidgetTester tester,
  Completer<bool?> result, {
  String message = 'Delete the original file?',
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              final r = await showDeleteOriginalDialog(context, message: message);
              result.complete(r);
            },
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('go'));
  await tester.pumpAndSettle();
}

void main() {
  group('showDeleteOriginalDialog', () {
    testWidgets('shows title, message, Keep and Delete actions', (tester) async {
      // Arrange/Act: open the dialog.
      final result = Completer<bool?>();
      await _open(tester, result, message: 'Delete the original report.pdf?');

      // Assert: dialog with title, message and both actions is present.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Delete original?'), findsOneWidget);
      expect(find.text('Delete the original report.pdf?'), findsOneWidget);
      expect(find.text('Keep'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);

      // Cleanup: dismiss without choosing.
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
    });

    testWidgets('tapping Delete returns true (handler will delete original)',
        (tester) async {
      // Arrange: open the dialog.
      final result = Completer<bool?>();
      await _open(tester, result);

      // Act: tap Delete (the user chose to remove the original).
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      // Assert: dialog closed and the result is true.
      expect(find.byType(Dialog), findsNothing);
      expect(await result.future, isTrue);
    });

    testWidgets('tapping Keep returns false and leaves the original unchanged',
        (tester) async {
      // Arrange: open the dialog.
      final result = Completer<bool?>();
      await _open(tester, result);

      // Act: tap Keep (default/safe choice — no delete).
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();

      // Assert: dialog closed, result is false (no deletion).
      expect(find.byType(Dialog), findsNothing);
      expect(await result.future, isFalse);
    });

    testWidgets('not barrier-dismissible — tapping outside never deletes',
        (tester) async {
      // Arrange: open the dialog.
      final result = Completer<bool?>();
      await _open(tester, result);

      // Act: tap the barrier/outside area.
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      // Assert: the dialog is STILL open (outside tap was ignored) — so an
      // accidental outside tap can never delete the original.
      expect(find.byType(Dialog), findsOneWidget);

      // Cleanup: close via Keep.
      await tester.tap(find.text('Keep'));
      await tester.pumpAndSettle();
      expect(await result.future, isFalse);
    });

    testWidgets('dismissing via system back (returning null) is treated as Keep',
        (tester) async {
      // Arrange: open the dialog.
      final result = Completer<bool?>();
      await _open(tester, result);

      // Act: simulate a back-button dismissal, which pops the dialog with null.
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();

      // Assert: dialog closed and result resolves to false (Keep semantics) —
      // because the caller only deletes when the result is exactly true.
      expect(find.byType(Dialog), findsNothing);
      expect(await result.future, isFalse);
    });
  });

  group('handler deletion sequence', () {
    // The single-encrypt handler, on a Delete choice, calls
    // FileOperationsProvider.deleteFile on the original plaintext PdfFile
    // (whose path still exists after encryption created the .enc). Verify that
    // sequence — the plaintext goes away while the .enc survives.
    test('deleting the original plaintext keeps the .enc and removes the .pdf',
        () async {
      final dir = Directory.systemTemp.createTempSync('freya_pdf_del_orig');
      try {
        final pdf = File('${dir.path}/report.pdf')
          ..writeAsBytesSync(List.generate(64, (i) => i % 256));
        final encPath = '${pdf.path}.enc';
        File(encPath).writeAsBytesSync(List.generate(32, (i) => i));

        final original = PdfFile.fromFileSystem(pdf);

        // What the handler does on Delete:
        final ok = await FileOperationsProvider().deleteFile(original);

        expect(ok, isTrue);
        expect(pdf.existsSync(), isFalse, reason: 'plaintext original removed');
        expect(File(encPath).existsSync(), isTrue,
            reason: '.enc copy must remain');
      } finally {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      }
    });
  });
}
