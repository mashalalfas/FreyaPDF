// Copyright (c) 2026 Freya. All rights reserved.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/core/security/root_detection.dart';
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

  testWidgets('passes through when the check reports clean', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RootSecurityGate(
          check: () async => RootCheckOutcome.clean,
          child: const Scaffold(body: Text('secure-app')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('secure-app'), findsOneWidget);
    expect(find.text('Unsupported device'), findsNothing);
  });

  testWidgets('BLOCKS (fails closed) when the device is compromised',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: RootSecurityGate(
          check: () async => RootCheckOutcome.compromised,
          child: const Scaffold(body: Text('secure-app')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The child must NOT be revealed on a confirmed rooted/jailbroken device.
    expect(find.text('secure-app'), findsNothing);
    expect(find.text('Unsupported device'), findsOneWidget);
    expect(find.textContaining('rooted'), findsOneWidget);
  });

  testWidgets('fails open (passes through) when the check throws',
      (tester) async {
    // Decide & lock: a check error is treated as an availability failure and
    // fails OPEN — the reader stays usable. Only an explicit compromised result
    // fails closed. See root_security_gate.dart doc comment.
    await tester.pumpWidget(
      MaterialApp(
        home: RootSecurityGate(
          check: () async => throw StateError('plugin unavailable'),
          child: const Scaffold(body: Text('secure-app')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('secure-app'), findsOneWidget);
    expect(find.text('Unsupported device'), findsNothing);
  });
}
