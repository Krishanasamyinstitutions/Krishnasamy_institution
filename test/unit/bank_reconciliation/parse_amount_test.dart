import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/bank_parsers.dart';

void main() {
  group('parseAmount', () {
    test('plain integer', () {
      expect(parseAmount('1500'), 1500);
    });

    test('thousands separator with decimals (US)', () {
      expect(parseAmount('1,234.56'), 1234.56);
    });

    test('European thousands and decimal', () {
      expect(parseAmount('1.234,56'), 1234.56);
    });

    test('Indian-style 1,23,456 → 123456', () {
      expect(parseAmount('1,23,456'), 123456);
    });

    test('accounting parens become negative', () {
      expect(parseAmount('(1,500)'), -1500);
      expect(parseAmount('(1,234.56)'), -1234.56);
    });

    test('rupee symbol stripped', () {
      expect(parseAmount('₹ 12,500.00'), 12500);
    });

    test('Rs. prefix stripped', () {
      expect(parseAmount('Rs.1,234.00'), 1234);
      expect(parseAmount('Rs 1,234.00'), 1234);
    });

    test('USD/EUR/GBP symbols stripped', () {
      expect(parseAmount(r'$100'), 100);
      expect(parseAmount('£250.50'), 250.50);
      expect(parseAmount('€999'), 999);
    });

    test('trailing Cr/Dr suffix dropped', () {
      expect(parseAmount('1,200.00 Cr'), 1200);
      expect(parseAmount('1,200.00 Dr'), 1200);
      expect(parseAmount('500 cr.'), 500);
    });

    test('empty string returns 0', () {
      expect(parseAmount(''), 0);
      expect(parseAmount('   '), 0);
    });

    test('non-numeric returns 0', () {
      expect(parseAmount('abc'), 0);
      expect(parseAmount('-'), 0);
    });

    test('comma followed by 2 digits is treated as decimal when ambiguous', () {
      // Single comma, two trailing digits = European decimal style
      expect(parseAmount('1234,56'), 1234.56);
    });

    test('comma with three trailing digits is thousands separator', () {
      expect(parseAmount('1,234'), 1234);
    });

    test('plain decimal', () {
      expect(parseAmount('1234.56'), 1234.56);
    });
  });
}
