import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/bank_parsers.dart';

void main() {
  group('findHeaderRow', () {
    test('HDFC layout — header at row 0', () {
      final rows = [
        ['Date', 'Narration', 'Chq/Ref No', 'Value Date', 'Withdrawal Amt', 'Deposit Amt', 'Closing Balance'],
        ['01-04-26', 'UPI/...', '4.26001E+11', '01-04-26', '', '5500', '155500'],
      ];
      expect(findHeaderRow(rows), 0);
    });

    test('ICICI layout — header at row 0', () {
      final rows = [
        ['S.No.', 'Value Date', 'Transaction Date', 'Cheque Number', 'Transaction Remarks',
            'Withdrawal Amount (INR)', 'Deposit Amount (INR)', 'Balance (INR)'],
        ['1', '08/04/2026', '08/04/2026', '', 'UPI-IB456789012345', '0.00', '6300', '206300'],
      ];
      expect(findHeaderRow(rows), 0);
    });

    test('IOB layout with Particulars/Inst.No', () {
      final rows = [
        ['Sr.No.', 'Date', 'Particulars', 'Inst. No', 'Withdrawal (Dr)', 'Deposit (Cr)', 'Balance'],
        ['1', '20/04/2026', 'UPI/CR/IOB512345001', 'IOB512345001', '', '3450', '323000'],
      ];
      expect(findHeaderRow(rows), 0);
    });

    test('skips preamble rows', () {
      final rows = [
        ['Account No: 12345'],
        ['Statement period: 01/04/2026 to 30/04/2026'],
        [''],
        ['Date', 'Narration', 'Chq/Ref No', 'Withdrawal Amt', 'Deposit Amt'],
        ['01/04/2026', 'UPI/...', '...', '', '5500'],
      ];
      expect(findHeaderRow(rows), 3);
    });

    test('empty rows list returns -1', () {
      expect(findHeaderRow([]), -1);
    });

    test('no recognisable header — falls back to row 0', () {
      final rows = [
        ['some', 'random', 'data'],
        ['without', 'header', 'keywords'],
      ];
      expect(findHeaderRow(rows), 0);
    });

    test('only date keyword without narration/amount returns 0 fallback', () {
      final rows = [
        ['Birth Date', 'Random', 'Cells'],
      ];
      expect(findHeaderRow(rows), 0);
    });

    test('value-date alone does not qualify', () {
      // 'Value Date' contains "value" so it should be skipped
      final rows = [
        ['Value Date', 'Some', 'Stuff'],
        ['Date', 'Narration', 'Amount'],
      ];
      expect(findHeaderRow(rows), 1);
    });
  });
}
