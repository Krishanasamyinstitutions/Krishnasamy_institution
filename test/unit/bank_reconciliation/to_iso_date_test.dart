import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/bank_parsers.dart';

void main() {
  group('toIsoDate', () {
    test('DD/MM/YYYY → YYYY-MM-DD', () {
      expect(toIsoDate('01/04/2026'), '2026-04-01');
    });

    test('DD-MM-YYYY → YYYY-MM-DD', () {
      expect(toIsoDate('15-08-2026'), '2026-08-15');
    });

    test('DD.MM.YYYY → YYYY-MM-DD', () {
      expect(toIsoDate('20.04.2026'), '2026-04-20');
    });

    test('DD/MM/YY where YY < 70 → 20YY', () {
      expect(toIsoDate('01/04/26'), '2026-04-01');
    });

    test('DD/MM/YY where YY >= 70 → 19YY', () {
      expect(toIsoDate('01/04/85'), '1985-04-01');
    });

    test('single-digit day/month gets zero-padded', () {
      expect(toIsoDate('1/4/2026'), '2026-04-01');
    });

    test('already-ISO date passes through (timestamp truncated)', () {
      expect(toIsoDate('2026-04-01'), '2026-04-01');
      expect(toIsoDate('2026-04-01T10:30:00Z'), '2026-04-01');
    });

    test('null input returns null', () {
      expect(toIsoDate(null), null);
    });

    test('empty input returns null', () {
      expect(toIsoDate(''), null);
      expect(toIsoDate('   '), null);
    });

    test('non-date text returns null', () {
      expect(toIsoDate('not a date'), null);
    });

    test('whitespace gets trimmed', () {
      expect(toIsoDate('  01/04/2026  '), '2026-04-01');
    });
  });
}
