// Size: small — page navigation validation tests (pure logic, no I/O)

import 'package:flutter_test/flutter_test.dart';
import 'package:feya_pdf/features/viewer/page_navigation.dart';

void main() {
  group('Page Navigation — validatePageNumber', () {
    const totalPages = 45;

    // ── Valid inputs ──
    test('"1" returns 1 (lower boundary)', () {
      expect(validatePageNumber('1', totalPages), equals(1));
    });

    test('"45" returns 45 (upper boundary = totalPages)', () {
      expect(validatePageNumber('45', totalPages), equals(45));
    });

    test('"12" returns 12 (middle of range)', () {
      expect(validatePageNumber('12', totalPages), equals(12));
    });

    test('" 23 " returns 23 (trims whitespace)', () {
      expect(validatePageNumber(' 23 ', totalPages), equals(23));
    });

    test('"\\t42\\n" returns 42 (trims tabs and newlines)', () {
      expect(validatePageNumber('\t42\n', totalPages), equals(42));
    });

    // ── Invalid: out of range ──
    test('"0" returns null (below lower boundary)', () {
      expect(validatePageNumber('0', totalPages), isNull);
    });

    test('"46" returns null (above totalPages)', () {
      expect(validatePageNumber('46', totalPages), isNull);
    });

    test('"999" returns null (way above totalPages)', () {
      expect(validatePageNumber('999', totalPages), isNull);
    });

    test('"-1" returns null (negative number)', () {
      expect(validatePageNumber('-1', totalPages), isNull);
    });

    test('"-5" returns null (any negative)', () {
      expect(validatePageNumber('-5', totalPages), isNull);
    });

    // ── Invalid: non-numeric ──
    test('"abc" returns null (non-numeric)', () {
      expect(validatePageNumber('abc', totalPages), isNull);
    });

    test('empty string returns null', () {
      expect(validatePageNumber('', totalPages), isNull);
    });

    test('"   " returns null (whitespace only)', () {
      expect(validatePageNumber('   ', totalPages), isNull);
    });

    test('"12abc" returns null (mixed alphanumeric)', () {
      expect(validatePageNumber('12abc', totalPages), isNull);
    });

    test('"12.5" returns null (decimal number)', () {
      expect(validatePageNumber('12.5', totalPages), isNull);
    });

    test('"--5" returns null (malformed negative)', () {
      expect(validatePageNumber('--5', totalPages), isNull);
    });

    // ── Edge cases ──
    test('works with totalPages = 1', () {
      expect(validatePageNumber('1', 1), equals(1));
      expect(validatePageNumber('0', 1), isNull);
      expect(validatePageNumber('2', 1), isNull);
    });

    test('works with large totalPages (10000)', () {
      expect(validatePageNumber('9999', 10000), equals(9999));
      expect(validatePageNumber('10000', 10000), equals(10000));
      expect(validatePageNumber('10001', 10000), isNull);
    });

    test('leading zeros are parsed as integers ("007" → 7)', () {
      // int.tryParse("007") returns 7, which is in range [1, 45]
      expect(validatePageNumber('007', totalPages), equals(7));
    });

    test('"+5" returns 5 (explicit positive sign)', () {
      // int.tryParse("+5") returns 5
      expect(validatePageNumber('+5', totalPages), equals(5));
    });
  });

  group('Page Navigation — isNotFirstPage', () {
    test('currentPage 1 → false (at first page)', () {
      expect(isNotFirstPage(1), isFalse);
    });

    test('currentPage 2 → true (past first page)', () {
      expect(isNotFirstPage(2), isTrue);
    });

    test('currentPage 45 → true (any page > 1)', () {
      expect(isNotFirstPage(45), isTrue);
    });

    test('currentPage 0 → false (invalid, but treated as ≤ 1)', () {
      expect(isNotFirstPage(0), isFalse);
    });

    test('currentPage -1 → false (invalid, treated as ≤ 1)', () {
      expect(isNotFirstPage(-1), isFalse);
    });
  });

  group('Page Navigation — isNotLastPage', () {
    test('currentPage 1, totalPages 45 → true (not at last)', () {
      expect(isNotLastPage(1, 45), isTrue);
    });

    test('currentPage 44, totalPages 45 → true (one before last)', () {
      expect(isNotLastPage(44, 45), isTrue);
    });

    test('currentPage 45, totalPages 45 → false (at last page)', () {
      expect(isNotLastPage(45, 45), isFalse);
    });

    test('currentPage 5, totalPages 5 → false (single-page doc at last)', () {
      expect(isNotLastPage(5, 5), isFalse);
    });

    test('currentPage 10, totalPages 1 → false (current > total, invalid)', () {
      expect(isNotLastPage(10, 1), isFalse);
    });

    test('currentPage 1, totalPages 1 → false (only one page)', () {
      expect(isNotLastPage(1, 1), isFalse);
    });

    test('currentPage 0, totalPages 10 → true (before first, valid as not last)', () {
      expect(isNotLastPage(0, 10), isTrue);
    });
  });

  group('Page Navigation — button boundary logic integration', () {
    // Simulates the bottom bar logic for First/Last/Prev/Next buttons
    test('all buttons active on middle page of multi-page doc', () {
      // currentPage=12, totalPages=45
      expect(isNotFirstPage(12), isTrue);  // First Page + Prev enabled
      expect(isNotLastPage(12, 45), isTrue); // Last Page + Next enabled
    });

    test('First and Prev disabled on page 1, Next and Last enabled', () {
      // currentPage=1, totalPages=45
      expect(isNotFirstPage(1), isFalse);  // First Page + Prev disabled
      expect(isNotLastPage(1, 45), isTrue); // Next + Last enabled
    });

    test('First and Prev disabled, Next and Last disabled on single-page doc', () {
      // currentPage=1, totalPages=1
      expect(isNotFirstPage(1), isFalse);  // all disabled
      expect(isNotLastPage(1, 1), isFalse);
    });

    test('Next and Last disabled on last page, First and Prev enabled', () {
      // currentPage=45, totalPages=45
      expect(isNotFirstPage(45), isTrue);   // First + Prev enabled
      expect(isNotLastPage(45, 45), isFalse); // Next + Last disabled
    });
  });
}
