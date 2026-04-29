import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/bank_parsers.dart';

void main() {
  group('normalizeReference', () {
    test('strips spaces, hyphens, slashes', () {
      expect(normalizeReference(' utr-123/45 '), 'UTR12345');
    });

    test('uppercases letters', () {
      expect(normalizeReference('ib1234abc'), 'IB1234ABC');
    });

    test('preserves alphanumerics in long Excel-mangled refs', () {
      expect(normalizeReference('4.98012E+11'), '498012E11');
    });

    test('Razorpay-style ref unchanged except case', () {
      expect(normalizeReference('IB456789012345'), 'IB456789012345');
    });

    test('empty input returns empty', () {
      expect(normalizeReference(''), '');
    });

    test('all-symbol input returns empty', () {
      expect(normalizeReference('---/// '), '');
    });

    test('removes underscores', () {
      expect(normalizeReference('pay_abc_123'), 'PAYABC123');
    });

    test('preserves digits-only input', () {
      expect(normalizeReference('300456'), '300456');
    });
  });
}
