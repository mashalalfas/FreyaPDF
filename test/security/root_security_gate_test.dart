// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/security/widgets/root_security_gate.dart';

void main() {
  testWidgets('RootSecurityGate passes through when check is unavailable',
      (tester) async {
    // In the test environment the flutter_jailbreak_detection MethodChannel is
    // absent, so RootDetector degrades to a non-blocking outcome. The gate must
    // reveal its child rather than crash or block.
    await tester.pumpWidget(
      const MaterialApp(
        home: RootSecurityGate(
          child: Scaffold(body: Text('secure-app')),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('secure-app'), findsOneWidget);
    expect(find.textContaining('rooted'), findsNothing);
  });
}
