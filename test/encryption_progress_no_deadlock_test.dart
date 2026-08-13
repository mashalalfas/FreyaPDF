// Copyright (c) 2026 Freya. All rights reserved.
// Regression test: the encrypting-progress dialog must NOT deadlock the
// surrounding file operation.
//
// Root cause of the original bug: the call sites in home_screen.dart did
//   await showEncryptingProgressDialog(context, ...);
// before running the encrypt work, and called closeEncryptingProgressDialog()
// AFTER that work. Because showDialog's future completes only when the dialog
// is popped, the caller suspended forever at the await, the work never ran,
// and the UI looked frozen ("stuck, not ending encryption").
//
// The fix: don't await the dialog. Show it un-awaited, run the work, then
// close it. This test pins that behavior so the deadlock cannot regress.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/encryption/widgets/encrypting_progress_dialog.dart';

void main() {
  group('Encryption progress dialog does not deadlock the caller', () {
    testWidgets(
      'dialog is fire-and-forget: work runs even before dialog closes',
      (tester) async {
        // This mirrors the FIXED call-site pattern in home_screen.dart: the
        // dialog is opened WITHOUT awaiting it, so encryption can start.
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Center(
                  child: ElevatedButton(
                    onPressed: () {
                      unawaited(
                        showEncryptingProgressDialog(
                          context,
                          fileName: 'report.pdf',
                        ),
                      );
                      // Proof-of-fix: this line runs immediately. Under the old
                      // deadlocked pattern the caller was suspended inside
                      // `await showDialog(...)` and never reached the work.
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const Scaffold(
                            body: Center(child: Text('work-ran')),
                          ),
                        ),
                      );
                    },
                    child: const Text('go'),
                  ),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('go'));
        await tester.pump(); // push the dialog route
        await tester.pump(); // build/attach the dialog + push work route

        // The dialog is up.
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.textContaining('Encrypting report.pdf'), findsOneWidget);

        // Critically: the "work" route was pushed even though the dialog is
        // still open -> showDialog did not block the caller.
        expect(find.text('work-ran'), findsOneWidget);

        // Clean up: pop the work route, then close the dialog, then step frames
        // (we cannot pumpAndSettle — the dialog's AnimationController repeats).
        Navigator.of(tester.element(find.text('work-ran'))).pop();
        await tester.pump();

        closeEncryptingProgressDialog(tester.element(find.byType(Dialog)));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pump(const Duration(milliseconds: 300));

        expect(find.byType(Dialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('show -> close round-trip resolves (no hang) even if awaited',
        (tester) async {
      // Even if a (mistaken) caller awaited the dialog's future before closing,
      // close() must release that await. This directly guards against a hang.
      var resolved = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    await showEncryptingProgressDialog(
                      context,
                      fileName: 'a.pdf',
                    );
                    resolved = true;
                  },
                  child: const Text('go2'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('go2'));
      await tester.pump();
      await tester.pump();

      // Dialog is open; the handler is suspended inside the await.
      expect(find.byType(Dialog), findsOneWidget);
      expect(resolved, isFalse);

      // Close it the way home_screen.dart does after the work completes.
      closeEncryptingProgressDialog(tester.element(find.byType(Dialog)));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(Dialog), findsNothing);
      expect(resolved, isTrue,
          reason: 'close() must release a caller awaiting the dialog future');
      expect(tester.takeException(), isNull);
    });
  });
}
