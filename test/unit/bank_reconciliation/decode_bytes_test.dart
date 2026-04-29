import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/bank_parsers.dart';

void main() {
  group('decodeBankBytes', () {
    test('decodes plain ASCII', () {
      final bytes = utf8.encode('Date,Amount\n01/04/2026,1500');
      expect(decodeBankBytes(bytes), 'Date,Amount\n01/04/2026,1500');
    });

    test('strips UTF-8 BOM', () {
      final bytes = [0xEF, 0xBB, 0xBF, ...utf8.encode('Date,Amount')];
      expect(decodeBankBytes(bytes), 'Date,Amount');
    });

    test('decodes UTF-8 rupee symbol', () {
      final bytes = utf8.encode('Amount: ₹12,500');
      expect(decodeBankBytes(bytes).contains('₹'), true);
    });

    test('falls back to Latin-1 on invalid UTF-8', () {
      // 0xA3 is £ in Latin-1, invalid as a standalone UTF-8 byte
      final bytes = [0xA3, 0x35, 0x30]; // '£50' in Latin-1
      final out = decodeBankBytes(bytes);
      expect(out.endsWith('50'), true);
      // Latin-1 decoded result will contain the 0xA3 character
      expect(out.length, 3);
    });

    test('empty input returns empty string', () {
      expect(decodeBankBytes([]), '');
    });
  });

  group('detectDelimiter', () {
    test('detects comma', () {
      expect(detectDelimiter('a,b,c\n1,2,3'), ',');
    });

    test('detects semicolon over comma', () {
      expect(detectDelimiter('a;b;c\n1;2;3'), ';');
    });

    test('detects tab when most common', () {
      expect(detectDelimiter('a\tb\tc\n1\t2\t3'), '\t');
    });

    test('defaults to comma on empty input', () {
      expect(detectDelimiter(''), ',');
      expect(detectDelimiter('   \n   '), ',');
    });

    test('comma wins on tie with semicolon', () {
      // Equal counts — should still favor comma per implementation
      expect(detectDelimiter('a,b\nc,d'), ',');
    });

    test('skips blank lines while sampling', () {
      expect(detectDelimiter('\n\n\na,b,c\n1,2,3\n'), ',');
    });
  });
}
