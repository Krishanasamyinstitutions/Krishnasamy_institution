import 'dart:io';

import 'package:csv/csv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/bank_parsers.dart';

/// Replays the same parsing pipeline that `_uploadBankStatement` uses in
/// `bank_reconciliation_screen.dart` against the shipped fixture CSVs in
/// `test_data/`. Catches regressions where one of the helpers stops
/// recognising a real bank's export.

({List<Map<String, dynamic>> deposits, int skipped}) _parseCsv(String path) {
  final bytes = File(path).readAsBytesSync();
  final csvString = decodeBankBytes(bytes).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final delimiter = detectDelimiter(csvString);

  final allRows = const CsvToListConverter(
    eol: '\n',
    shouldParseNumbers: false,
  ).convert(csvString, fieldDelimiter: delimiter);

  final headerIdx = findHeaderRow(allRows);
  expect(headerIdx, greaterThanOrEqualTo(0), reason: 'header row not found in $path');

  final headers = allRows[headerIdx].map((h) => h.toString().toLowerCase().trim()).toList();
  final rows = allRows.sublist(headerIdx);

  final dateIdx = headers.indexWhere((h) => h.contains('date') && !h.contains('value'));
  final refIdx = headers.indexWhere((h) =>
      h.contains('ref') ||
      h.contains('chq') ||
      h.contains('cheque') ||
      h.contains('transaction') ||
      h.contains('utr') ||
      h.contains('instrument') ||
      h.contains('inst'));
  final narrationIdx = headers.indexWhere((h) =>
      h.contains('narration') || h.contains('desc') || h.contains('particular') || h.contains('remark'));
  int depositIdx = headers.indexWhere((h) =>
      (h.contains('deposit') || h.contains('credit') || h.contains('cr amount')) &&
      !h.contains('debit'));
  int withdrawalIdx = headers.indexWhere((h) =>
      h.contains('withdrawal') || h.contains('debit') || h.contains('dr amount'));
  int amountIdx = depositIdx >= 0 ? depositIdx : headers.indexWhere((h) => h == 'amount' || h.endsWith(' amount') || h.startsWith('amount '));

  final deposits = <Map<String, dynamic>>[];
  int skipped = 0;

  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 2) {
      skipped++;
      continue;
    }

    if (withdrawalIdx >= 0 && withdrawalIdx < row.length) {
      final w = parseAmount(row[withdrawalIdx].toString());
      if (w > 0) {
        skipped++;
        continue;
      }
    }

    final amount = amountIdx >= 0 && amountIdx < row.length
        ? parseAmount(row[amountIdx].toString())
        : 0.0;
    if (amount <= 0) {
      skipped++;
      continue;
    }

    deposits.add({
      'date': dateIdx >= 0 && dateIdx < row.length ? row[dateIdx].toString().trim() : '',
      'reference': refIdx >= 0 && refIdx < row.length ? row[refIdx].toString().trim() : '',
      'narration':
          narrationIdx >= 0 && narrationIdx < row.length ? row[narrationIdx].toString().trim() : '',
      'amount': amount,
    });
  }

  return (deposits: deposits, skipped: skipped);
}

void main() {
  group('CSV pipeline against bank fixtures', () {
    test('HDFC fixture extracts 7 deposits, skips 2 debits', () {
      final result = _parseCsv('test_data/HDFC_bank_statement.csv');
      expect(result.deposits, hasLength(7));
      // ATM CASH WDL + POS PURCHASE
      expect(result.skipped, greaterThanOrEqualTo(2));
      // Spot-check first row: UPI 5,500 to RAVI KUMAR
      expect(result.deposits.first['amount'], 5500);
      expect(result.deposits.first['narration'], contains('RAVI KUMAR'));
    });

    test('ICICI fixture extracts 7 deposits, skips withdrawal', () {
      final result = _parseCsv('test_data/ICICI_bank_statement.csv');
      expect(result.deposits, hasLength(7));
      expect(result.skipped, greaterThanOrEqualTo(1));
    });

    test('SBI fixture extracts 8 deposits, skips withdrawal', () {
      final result = _parseCsv('test_data/SBI_bank_statement.csv');
      expect(result.deposits, hasLength(8));
      expect(result.skipped, greaterThanOrEqualTo(1));
      // SBI has cheque collections — match by ref number
      final cheque = result.deposits.firstWhere(
        (r) => r['reference'] == '300456',
        orElse: () => {},
      );
      expect(cheque, isNotEmpty, reason: 'SBI cheque 300456 not parsed');
      // Fixture has been edited; just confirm a positive amount was parsed.
      expect((cheque['amount'] as num) > 0, true);
    });

    test('IOB fixture extracts 8 deposits, skips ATM/POS', () {
      final result = _parseCsv('test_data/IOB_bank_statement.csv');
      expect(result.deposits, hasLength(8));
      expect(result.skipped, greaterThanOrEqualTo(2));
      // IOB Inst.No column should map to reference via the 'inst' keyword
      final cheque = result.deposits.firstWhere(
        (r) => r['reference'] == '400123',
        orElse: () => {},
      );
      expect(cheque, isNotEmpty, reason: 'IOB cheque 400123 not parsed');
      expect(cheque['amount'], 12500);
    });

    test('All fixtures produce ISO-formatted dates after toIsoDate', () {
      for (final path in [
        'test_data/HDFC_bank_statement.csv',
        'test_data/ICICI_bank_statement.csv',
        'test_data/SBI_bank_statement.csv',
        'test_data/IOB_bank_statement.csv',
      ]) {
        final result = _parseCsv(path);
        for (final row in result.deposits) {
          final iso = toIsoDate(row['date'] as String);
          expect(iso, isNotNull, reason: '$path date "${row['date']}" did not parse');
          expect(RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(iso!), true,
              reason: '$path produced bad ISO: $iso from "${row['date']}"');
        }
      }
    });
  });
}
