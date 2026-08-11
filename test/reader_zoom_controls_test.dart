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

  testWidgets('fullscreen action fires onToggleFullscreen and icon switches',
      (tester) async {
    var toggles = 0;
    late StateSetter setParentState;
    var isFullscreen = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setParentState = setState;
              return Stack(
                children: [
                  const SizedBox.expand(),
                  ReaderZoomControls(
                    onZoomIn: () {},
                    onZoomOut: () {},
                    onReset: () {},
                    onToggleFullscreen: () {
                      toggles++;
                      setParentState(() => isFullscreen = !isFullscreen);
                    },
                    isFullscreen: isFullscreen,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    // Expand to reveal the row including the fullscreen action.
    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);

    // Tap fullscreen: callback fires and the parent flips the flag so the
    // row now shows the exit glyph.
    await tester.tap(find.byIcon(Icons.fullscreen_rounded));
    await tester.pumpAndSettle();
    expect(toggles, 1);
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsOneWidget);

    // Tap again to leave fullscreen; exit glyph reverts to the enter glyph.
    await tester.tap(find.byIcon(Icons.fullscreen_exit_rounded));
    await tester.pumpAndSettle();
    expect(toggles, 2);
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
    expect(find.byIcon(Icons.fullscreen_exit_rounded), findsNothing);
  });

  testWidgets('collapsed row hides fullscreen action (only expanded shows it)',
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

    // Collapsed: no fullscreen glyph anywhere.
    expect(find.byIcon(Icons.fullscreen_rounded), findsNothing);
    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.fullscreen_rounded), findsOneWidget);
  });

  testWidgets('expanded row never auto-fades; collapsed fades 5s→0.3, '
      '+5s→0.0+IgnorePointer; re-tap restores', (tester) async {
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

    double fadeOpacity() {
      final ft = tester.widget<FadeTransition>(
        find.byKey(const ValueKey('zoom-controls-fade')),
      );
      return ft.opacity.value;
    }

    // Fully visible initially (collapsed).
    expect(fadeOpacity(), 1.0);

    // Expand (an interaction): stays at 1.0 and — critically — NEVER fades
    // while expanded, even long after the old 3s/6s windows would have fired.
    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), 1.0);
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), 1.0,
        reason: 'Expanded controls must never auto-fade.');
    expect(find.byKey(const ValueKey('zoom-controls-ignore')), findsNothing);

    // Collapse: starts the 5s countdown fresh; +5s of inactivity fades the
    // collapsed control to the 0.3 floor (still tappable, not ignored).
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), 1.0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), closeTo(0.3, 0.01),
        reason: 'Collapsed control floors at 0.3 after 5s idle.');
    expect(find.byKey(const ValueKey('zoom-controls-ignore')), findsNothing,
        reason: 'At the 0.3 floor the control must stay tappable.');

    // Any interaction while visible resets timers back to full 1.0 (here: a
    // re-expand before the full-hide fires).
    await tester.tap(find.byIcon(Icons.zoom_in_rounded));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), 1.0,
        reason: 'Interaction must reset the collapsed control to full opacity.');

    // Expand: never fades, even after another long idle window.
    await tester.pump(const Duration(seconds: 8));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), 1.0,
        reason: 'Expanded controls must never auto-fade.');

    // Collapse again and run the full 10s idle window → 0.0 and IgnorePointer.
    await tester.tap(find.byIcon(Icons.chevron_right_rounded));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), closeTo(0.3, 0.01));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(fadeOpacity(), 0.0,
        reason: 'After ~10s total idle the collapsed control fully hides.');
    expect(find.byKey(const ValueKey('zoom-controls-ignore')), findsOneWidget,
        reason: 'Only once fully hidden should the control be ignored.');
  });
}
