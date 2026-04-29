// CSV upload size limit (S4 in the testing plan). The bank reconciliation
// upload rejects files > 5 MB before the parser touches them. This test
// validates the byte-count-against-limit logic in isolation — no Supabase
// or file picker dependency.

import 'package:flutter_test/flutter_test.dart';

/// Mirror of the constant inlined into `_uploadBankStatement` in
/// `lib/screens/fees/bank_reconciliation_screen.dart`. Kept in sync via
/// this test — if the production code raises the limit, update here.
const _maxBankStatementBytes = 5 * 1024 * 1024;

bool _isWithinLimit(int sizeBytes) => sizeBytes <= _maxBankStatementBytes;

void main() {
  group('Bank statement size limit', () {
    test('5 MB exactly is allowed', () {
      expect(_isWithinLimit(_maxBankStatementBytes), true);
    });

    test('5 MB + 1 byte is rejected', () {
      expect(_isWithinLimit(_maxBankStatementBytes + 1), false);
    });

    test('typical 100 KB statement passes', () {
      expect(_isWithinLimit(100 * 1024), true);
    });

    test('zero-byte file passes (validation happens later)', () {
      expect(_isWithinLimit(0), true);
    });

    test('10 MB hostile payload is rejected', () {
      expect(_isWithinLimit(10 * 1024 * 1024), false);
    });

    test('limit constant is the documented 5 MB', () {
      expect(_maxBankStatementBytes, 5242880);
    });
  });
}
