// Copyright (c) 2026 Freya. All rights reserved.
//
// Pure, side-effect-free zoom math.
//
// WHY THIS EXISTS
// --------------
// Device feedback (HMD Skyline, FreyaPDF v1.2.0+6) reported two related
// problems with large PDFs:
//   1. After pinch-zooming, the page drifted off-center to the right, so
//      the right portion of the page was hidden off-screen.
//   2. Pinch-zooming "felt inverted" — pulling fingers apart sometimes
//      appeared to shrink the content, and zooming always left the page
//      off-center.
//
// Root cause: pdfrx's PdfViewer runs Flutter's InteractiveViewer with
// `boundaryMargin = double.infinity` (the default when no scrollPhysics is
// configured, which this app does not set). With an infinite boundary and
// `constrained: false`, pdfrx does NOT clamp or re-center the viewport
// after a gesture. The viewer zooms about the gesture's focal point (which
// naturally sits off the page center) and accumulates the small two-finger
// translation that accompanies any pinch. Over a couple of pinches the
// content drifts and a page edge is pushed out of view, which reads as
// "zooming the wrong way" / "zoomed in when I pinched out."
//
// The fix we ship mirrors every deliberate zoom (buttons and, where useful,
// re-centring) about the viewport CENTRE instead of the gesture focal
// point, and clamps every step to the viewer's [minScale, maxScale] range.
// Keeping the document point currently under the viewport centre stationary
// guarantees the page stays centred regardless of how many steps are taken.
//
// This class contains ONLY the pure numeric transform so it can be unit
// tested headlessly (a live PdfViewer/PdfViewerController cannot be laid
// out in flutter_test — see test/viewer_integration_test.dart).

/// Pure zoom step helpers.
abstract final class PdfZoomMath {
  /// Multiplier applied when zooming in (increase scale).
  static const double kZoomInFactor = 1.25;

  /// Multiplier applied when zooming out (decrease scale), the inverse of
  /// [kZoomInFactor] so a zoom-in followed by a zoom-out returns to ~1.0.
  static const double kZoomOutFactor = 0.8;

  /// Returns `current * factor` clamped to the inclusive [min, max] range.
  ///
  /// * zooming in uses factor > 1 -> scale increases (content grows).
  /// * zooming out uses factor < 1 -> scale decreases (content shrinks).
  ///
  /// This is the single source of truth for "which direction a button
  /// moves the zoom", so a wrong sign here is caught by unit tests.
  static double step(
    double current,
    double factor, {
    required double min,
    required double max,
  }) {
    final target = current * factor;
    if (target <= min) return min;
    if (target >= max) return max;
    return target;
  }

  /// Convenience: one zoom-in step.
  static double zoomIn(
    double current, {
    required double min,
    required double max,
  }) =>
      step(current, kZoomInFactor, min: min, max: max);

  /// Convenience: one zoom-out step.
  static double zoomOut(
    double current, {
    required double min,
    required double max,
  }) =>
      step(current, kZoomOutFactor, min: min, max: max);
}
