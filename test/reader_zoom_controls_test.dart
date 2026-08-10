// Copyright (c) 2026 Freya. All rights reserved.
//
// Widget tests for the floating ReaderZoomControls overlay.
//
// ReaderZoomControls is a plain Flutter widget (no pdfrx dependency), so it
// CAN be exercised headlessly — unlike pdfrx's PdfViewer, which needs a real
// render surface (see test/viewer_integration_test.dart). These tests pin
// the UI contract the user asked for: a small floating button that expands
// into zoom-in / zoom-out / reset-centre actions, each wired to its callback.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/viewer/widgets/reader_zoom_controls.dart';

Widget _wrap(ReaderZoomControls controls) {
  return MaterialApp(
    home: Scaffold(
      body: Stack(children: [const SizedBox.expand(), controls]),
    ),
  );
}

void main() {
  testWidgets('starts collapsed as a single zoom button, not the action row',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReaderZoomControls(
          onZoomIn: () {},
          onZoomOut: () {},
          onReset: () {},
        ),
      ),
    );

    // Collapsed state: the glyph button is present; the row actions are not.
    expect(find.byIcon(Icons.zoom_in_rounded), findsOneWidget);
    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.remove_rounded), findsNothing);
    expect(find.byIcon(Icons.center_focus_strong_rounded), findsNothing);
  });

  testWidgets('tapping the floating button expands the zoom action row',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReaderZoomControls(
          onZoomIn: () {},
          onZoomOut: () {},
          onReset: () {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_rounded), findsOneWidget); // zoom in
    expect(find.byIcon(Icons.remove_rounded), findsOneWidget); // zoom out
    expect(
      find.byIcon(Icons.center_focus_strong_rounded),
      findsOneWidget, // reset / centre
    );
  });

  testWidgets('zoom-in button fires onZoomIn and keeps the row expanded',
      (tester) async {
    var zoomInCalls = 0;
    await tester.pumpWidget(
      _wrap(
        ReaderZoomControls(
          onZoomIn: () => zoomInCalls++,
          onZoomOut: () {},
          onReset: () {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();

    expect(zoomInCalls, 1);
    // Row stays open so the user can step repeatedly without re-expanding.
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);
  });

  testWidgets('zoom-out button fires onZoomOut', (tester) async {
    var zoomOutCalls = 0;
    await tester.pumpWidget(
      _wrap(
        ReaderZoomControls(
          onZoomIn: () {},
          onZoomOut: () => zoomOutCalls++,
          onReset: () {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pumpAndSettle();

    expect(zoomOutCalls, 1);
  });

  testWidgets('reset button fires onReset', (tester) async {
    var resetCalls = 0;
    await tester.pumpWidget(
      _wrap(
        ReaderZoomControls(
          onZoomIn: () {},
          onZoomOut: () {},
          onReset: () => resetCalls++,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.center_focus_strong_rounded));
    await tester.pumpAndSettle();

    expect(resetCalls, 1);
  });

  testWidgets('chevron collapses the row back to the floating button',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        ReaderZoomControls(
          onZoomIn: () {},
          onZoomOut: () {},
          onReset: () {},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.add_rounded), findsOneWidget);

    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.add_rounded), findsNothing);
    expect(find.byIcon(Icons.zoom_in_rounded), findsOneWidget);
  });
}
