// Copyright (c) 2026 Freya. All rights reserved.
// Widget tests for the "Decrypt to plain" entry point and the animated
// encrypting progress dialog added alongside decrypt-to-plain support.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/core/models/pdf_file.dart';
import 'package:freya_pdf/features/encryption/widgets/encrypting_progress_dialog.dart';
import 'package:freya_pdf/features/file_management/widgets/file_list_tile.dart';

PdfFile _file(String name) => PdfFile(
      path: '/tmp/$name',
      name: name,
      sizeBytes: 100,
      modified: DateTime.now(),
    );

Widget _tile(PdfFile file) => MaterialApp(
      home: Scaffold(
        body: FileListTile(
          file: file,
          isSelected: false,
          onTap: () {},
          onDecrypt: () {},
        ),
      ),
    );

/// Long-press the tile to open its context (bottom-sheet) menu.
Future<void> _openContextMenu(WidgetTester tester) async {
  await tester.longPress(find.byType(FileListTile));
  await tester.pumpAndSettle();
}

void main() {
  group('FileListTile context menu: Decrypt to plain', () {
    testWidgets('shows "Decrypt to plain" for an encrypted file', (tester) async {
      // Arrange
      await tester.pumpWidget(_tile(_file('report.pdf.enc')));

      // Act: open the context menu via long-press.
      await _openContextMenu(tester);

      // Assert: the decrypt action is offered for encrypted files.
      expect(find.text('Decrypt to plain'), findsOneWidget);
    });

    testWidgets('does NOT show "Decrypt to plain" for a plain file', (tester) async {
      // Arrange
      await tester.pumpWidget(_tile(_file('report.pdf')));

      // Act
      await _openContextMenu(tester);

      // Assert: no decrypt action for an unencrypted file.
      expect(find.text('Decrypt to plain'), findsNothing);
    });
  });

  group('EncryptingProgressDialog animation', () {
    testWidgets('renders title text and animates without throwing', (tester) async {
      // Arrange: open the dialog with a file name (indeterminate mode).
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showEncryptingProgressDialog(
                  context,
                  fileName: 'big.pdf',
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      // Act: tap to open.
      await tester.tap(find.text('go'));
      await tester.pump();

      // Assert: title text visible, dialog present.
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.textContaining('Encrypting big.pdf'), findsOneWidget);

      // Pump several frames — the pulsing lock / spinner controllers must not
      // throw or leave pending timers. pumpAndSettle would hang on a repeating
      // controller, so step through frames explicitly.
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.takeException(), isNull);
    });

    testWidgets('shows a live "X of N" count via updateEncryptingProgress',
        (tester) async {
      // Arrange
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showEncryptingProgressDialog(
                  context,
                  fileName: '',
                  total: 5,
                ),
                child: const Text('go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go'));
      await tester.pump();

      // Initial state: 0 of 5.
      expect(find.text('Encrypting 0 of 5…'), findsOneWidget);

      // Act: simulate the batch callback advancing progress.
      updateEncryptingProgress(tester.element(find.byType(Dialog)), 3);
      await tester.pump();

      // Assert: the dialog reflects the live count.
      expect(find.text('Encrypting 3 of 5…'), findsOneWidget);
    });
  });
}
