// Copyright (c) 2026 Freya. All rights reserved.
//
// Unit tests for the pure zoom math (PdfZoomMath).
//
// This is the headless-safe home for the "pinch-math fix": the direction of
// every zoom step and its clamping are pure transforms, so we can assert
// exactly that zoom-in increases scale, zoom-out decreases it, and that
// values stay inside [minScale, maxScale] — without needing a live
// PdfViewerController (which cannot be laid out in flutter_test).

import 'package:flutter_test/flutter_test.dart';
import 'package:freya_pdf/features/viewer/pdf_zoom_math.dart';

void main() {
  group('PdfZoomMath.step', () {
    const min = 1.0;
    const max = 10.0;

    test('zooming in (factor > 1) increases the scale', () {
      expect(PdfZoomMath.step(2.0, 1.25, min: min, max: max), closeTo(2.5, 1e-9));
    });

    test('zooming out (factor < 1) decreases the scale', () {
      expect(PdfZoomMath.step(2.0, 0.8, min: min, max: max), closeTo(1.6, 1e-9));
    });

    test('direction is NOT inverted: in > current > out for any base', () {
      for (final base in [1.0, 1.7, 3.0, 5.0, 8.0]) {
        final in_ = PdfZoomMath.step(base, PdfZoomMath.kZoomInFactor, min: min, max: max);
        final out = PdfZoomMath.step(base, PdfZoomMath.kZoomOutFactor, min: min, max: max);
        expect(in_, greaterThanOrEqualTo(base), reason: 'zoom-in must never shrink at base=$base');
        expect(out, lessThanOrEqualTo(base), reason: 'zoom-out must never grow at base=$base');
      }
    });

    test('step is clamped to the inclusive [min, max] range', () {
      expect(PdfZoomMath.step(9.0, 1.25, min: min, max: max), max); // would be 11.25 -> 10
      expect(PdfZoomMath.step(min, 0.5, min: min, max: max), min); // would be 0.5 -> 1
    });

    test('zoomIn/zoomOut helpers produce inverse trips around unity', () {
      for (final base in [2.0, 4.0, 6.0, 8.0, 10.0]) {
        final up = PdfZoomMath.zoomIn(base, min: min, max: max);
        // Do not over-zoom: only test values that round-trip within the clamp.
        if (up < max) {
          final down = PdfZoomMath.zoomOut(up, min: min, max: max);
          expect(down, closeTo(base, 1e-6));
        }
      }
    });

    test('clamping lower than min returns exactly min', () {
      expect(PdfZoomMath.zoomOut(1.2, min: 1.0, max: 10.0), closeTo(1.0, 1e-9));
    });

    test('clamping beyond max returns exactly max', () {
      expect(PdfZoomMath.zoomIn(8.5, min: 1.0, max: 10.0), closeTo(10.0, 1e-9));
    });
  });

  group('PdfZoomMath fixed factors', () {
    test('zoom-out factor is the reciprocal of zoom-in factor', () {
      expect(PdfZoomMath.kZoomInFactor * PdfZoomMath.kZoomOutFactor, closeTo(1.0, 1e-9));
    });

    test('factors are strictly on the correct sides of 1', () {
      expect(PdfZoomMath.kZoomInFactor, greaterThan(1.0));
      expect(PdfZoomMath.kZoomOutFactor, lessThan(1.0));
    });
  });
}
