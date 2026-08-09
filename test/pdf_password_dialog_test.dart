// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:freya_pdf/features/viewer/widgets/pdf_password_dialog.dart';

void main() {
  testWidgets('submits password and remember choice', (tester) async {
    late Future<PdfPasswordPromptResult?> prompt;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              prompt = showPdfPasswordDialog(context);
            },
            child: const Text('Open prompt'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open prompt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.enterText(find.byType(TextField), 'bank-password');
    await tester.tap(find.byType(CheckboxListTile));
    final openButton = find.widgetWithText(FilledButton, 'Open');
    expect(openButton, findsOneWidget);
    expect(tester.widget<FilledButton>(openButton).onPressed, isNotNull);
    await tester.tap(openButton);
    await tester.pump();

    final result = await prompt;
    expect(result?.password, 'bank-password');
    expect(result?.remember, isTrue);
  });

  testWidgets('cancel returns null', (tester) async {
    late Future<PdfPasswordPromptResult?> prompt;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () {
              prompt = showPdfPasswordDialog(context);
            },
            child: const Text('Open prompt'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open prompt'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Cancel'));
    await tester.pump();

    expect(await prompt, isNull);
  });
}
