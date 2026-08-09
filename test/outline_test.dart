// Copyright (c) 2026 Freya. All rights reserved.
// Size: small — outline flattening logic tests (pure logic, uses pdfrx types)

import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

/// Flatten an outline tree into a flat list of (node, depth) pairs.
/// Depth 0 = top-level entries, depth 1 = children of top-level, etc.
List<({PdfOutlineNode node, int depth})> flattenOutline(
  List<PdfOutlineNode> nodes, [
  int depth = 0,
]) {
  final result = <({PdfOutlineNode node, int depth})>[];
  for (final node in nodes) {
    result.add((node: node, depth: depth));
    result.addAll(flattenOutline(node.children, depth + 1));
  }
  return result;
}

void main() {
  group('Outline — flattenOutline', () {
    // ── Empty outline ──
    test('empty list returns empty list', () {
      expect(flattenOutline([]), isEmpty);
    });

    // ── Flat outline (no children) ──
    test('single top-level node returns one entry at depth 0', () {
      final node = const PdfOutlineNode(
        title: 'Introduction',
        dest: null,
        children: [],
      );
      final result = flattenOutline([node]);

      expect(result, hasLength(1));
      expect(result[0].node.title, equals('Introduction'));
      expect(result[0].depth, equals(0));
    });

    test('multiple flat top-level nodes', () {
      final nodes = [
        const PdfOutlineNode(title: 'Chapter 1', dest: null, children: []),
        const PdfOutlineNode(title: 'Chapter 2', dest: null, children: []),
        const PdfOutlineNode(title: 'Chapter 3', dest: null, children: []),
      ];
      final result = flattenOutline(nodes);

      expect(result, hasLength(3));
      expect(result[0].depth, equals(0));
      expect(result[1].depth, equals(0));
      expect(result[2].depth, equals(0));
      expect(result.map((e) => e.node.title).toList(),
          equals(['Chapter 1', 'Chapter 2', 'Chapter 3']));
    });

    // ── Nested outline (one level) ──
    test('node with children preserves parent-child ordering', () {
      final nodes = [
        const PdfOutlineNode(
          title: 'Chapter 1',
          dest: null,
          children: [
            PdfOutlineNode(title: '1.1 Intro', dest: null, children: []),
            PdfOutlineNode(title: '1.2 Background', dest: null, children: []),
          ],
        ),
      ];
      final result = flattenOutline(nodes);

      expect(result, hasLength(3));
      // Parent first
      expect(result[0].node.title, equals('Chapter 1'));
      expect(result[0].depth, equals(0));
      // Then children in order
      expect(result[1].node.title, equals('1.1 Intro'));
      expect(result[1].depth, equals(1));
      expect(result[2].node.title, equals('1.2 Background'));
      expect(result[2].depth, equals(1));
    });

    // ── Deeply nested outline (3 levels) ──
    test('deeply nested nodes have correct depth values', () {
      final nodes = [
        const PdfOutlineNode(
          title: 'Part I',
          dest: null,
          children: [
            PdfOutlineNode(
              title: 'Chapter 1',
              dest: null,
              children: [
                PdfOutlineNode(
                  title: 'Section 1.1',
                  dest: null,
                  children: [
                    PdfOutlineNode(
                      title: 'Subsection 1.1.1',
                      dest: null,
                      children: [],
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ];
      final result = flattenOutline(nodes);

      expect(result, hasLength(4));
      expect(result[0].node.title, equals('Part I'));
      expect(result[0].depth, equals(0));
      expect(result[1].node.title, equals('Chapter 1'));
      expect(result[1].depth, equals(1));
      expect(result[2].node.title, equals('Section 1.1'));
      expect(result[2].depth, equals(2));
      expect(result[3].node.title, equals('Subsection 1.1.1'));
      expect(result[3].depth, equals(3));
    });

    // ── Multiple top-level with children ──
    test('multiple top-level nodes each with children flattened correctly', () {
      final nodes = [
        const PdfOutlineNode(
          title: 'A',
          dest: null,
          children: [
            PdfOutlineNode(title: 'A1', dest: null, children: []),
            PdfOutlineNode(title: 'A2', dest: null, children: []),
          ],
        ),
        const PdfOutlineNode(
          title: 'B',
          dest: null,
          children: [
            PdfOutlineNode(title: 'B1', dest: null, children: []),
          ],
        ),
      ];
      final result = flattenOutline(nodes);

      expect(result, hasLength(5));
      final titles = result.map((e) => e.node.title).toList();
      expect(titles, equals(['A', 'A1', 'A2', 'B', 'B1']));
      final depths = result.map((e) => e.depth).toList();
      expect(depths, equals([0, 1, 1, 0, 1]));
    });

    // ── Nodes with and without dest ──
    test('nodes with dest preserve the dest field', () {
      final dest = PdfDest(5, PdfDestCommand.xyz, null);
      final nodes = [
        const PdfOutlineNode(
          title: 'Intro',
          dest: null,
          children: [],
        ),
        PdfOutlineNode(
          title: 'Chapter 5',
          dest: dest,
          children: [],
        ),
      ];
      final result = flattenOutline(nodes);

      expect(result[0].node.dest, isNull);
      expect(result[1].node.dest, isNotNull);
      expect(result[1].node.dest!.pageNumber, equals(5));
    });

    // ── Node with dest and children (non-leaf with destination) ──
    test('node with both dest and children is still flattened with children', () {
      final dest = PdfDest(10, PdfDestCommand.xyz, null);
      final nodes = [
        PdfOutlineNode(
          title: 'Parent with dest',
          dest: dest,
          children: const [
            PdfOutlineNode(title: 'Child', dest: null, children: []),
          ],
        ),
      ];
      final result = flattenOutline(nodes);

      expect(result, hasLength(2));
      expect(result[0].node.title, equals('Parent with dest'));
      expect(result[0].node.dest, isNotNull);
      expect(result[0].depth, equals(0));
      expect(result[1].node.title, equals('Child'));
      expect(result[1].depth, equals(1));
    });
  });
}
