import 'dart:convert';

/// Pure parsing helpers used by Bank Reconciliation. These functions are
/// extracted from `lib/screens/fees/bank_reconciliation_screen.dart` so they
/// can be unit-tested in isolation. They have no Flutter / Supabase / state
/// dependencies — pass strings/bytes in, get values out.

/// Strip every non-alphanumeric character and uppercase. Used to compare
/// references across formats (`'IB-1234/25'` and `'ib1234 25'` both become
/// `'IB123425'`).
String normalizeReference(String value) =>
    value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

/// Convert common bank-statement date formats (DD/MM/YYYY, DD-MM-YYYY,
/// DD/MM/YY, DD.MM.YYYY) to ISO `YYYY-MM-DD` for Postgres. Two-digit years
/// are mapped 70-99 → 19xx, 00-69 → 20xx. Already-ISO inputs pass through.
/// Returns null when the input can't be interpreted.
String? toIsoDate(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(s)) return s.substring(0, 10);
  final m = RegExp(r'^(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})').firstMatch(s);
  if (m == null) return null;
  final d = m.group(1)!.padLeft(2, '0');
  final mo = m.group(2)!.padLeft(2, '0');
  var y = m.group(3)!;
  if (y.length == 2) y = (int.parse(y) >= 70 ? '19' : '20') + y;
  return '$y-$mo-$d';
}

/// Decode bank statement bytes. Strips a UTF-8 BOM, tries strict UTF-8, and
/// falls back to Latin-1 (Windows-1252) when bytes don't decode cleanly —
/// covers HDFC/ICICI exports that contain ₹ or other 8-bit characters.
String decodeBankBytes(List<int> bytes) {
  var data = bytes;
  if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
    data = data.sublist(3);
  }
  try {
    return utf8.decode(data, allowMalformed: false);
  } catch (_) {
    return latin1.decode(data, allowInvalid: true);
  }
}

/// Pick the delimiter (`,`, `;`, or `\t`) that appears most consistently in
/// the first ten non-blank lines. Defaults to `,` when no delimiter dominates.
String detectDelimiter(String text) {
  final lines = text.split('\n').where((l) => l.trim().isNotEmpty).take(10).toList();
  if (lines.isEmpty) return ',';
  int commaTotal = 0, semiTotal = 0, tabTotal = 0;
  for (final l in lines) {
    commaTotal += ','.allMatches(l).length;
    semiTotal += ';'.allMatches(l).length;
    tabTotal += '\t'.allMatches(l).length;
  }
  if (tabTotal > commaTotal && tabTotal > semiTotal) return '\t';
  if (semiTotal > commaTotal) return ';';
  return ',';
}

/// Find the real header row inside a parsed CSV. Banks usually prefix the
/// statement with preamble rows (account number, period, branch). Accept the
/// first row whose cells contain a Date keyword AND at least one Narration or
/// Amount keyword. Returns -1 only when `rows` is empty.
int findHeaderRow(List<List<dynamic>> rows) {
  for (int i = 0; i < rows.length && i < 20; i++) {
    final cells = rows[i].map((c) => c.toString().toLowerCase().trim()).toList();
    if (cells.length < 3) continue;
    final hasDate = cells.any((c) => c.contains('date') && !c.contains('value'));
    final hasNarr = cells.any((c) =>
        c.contains('narration') || c.contains('particular') || c.contains('desc') || c.contains('remark'));
    final hasAmount = cells.any((c) =>
        c.contains('amount') || c.contains('deposit') || c.contains('credit') ||
        c.contains('withdrawal') || c.contains('debit'));
    if (hasDate && (hasNarr || hasAmount)) return i;
  }
  return rows.isNotEmpty ? 0 : -1;
}

/// Parse an amount cell.
///   - Strips currency symbols (₹ $ £ € Rs. INR) and non-breaking spaces.
///   - Drops trailing `Cr` / `Dr` suffix (sign comes from caller's column).
///   - Treats `(1,200.00)` (accounting parens) as negative.
///   - Handles both `1,234.56` and European `1.234,56` thousand separators.
///   - Indian-style `1,23,456` is treated as 123456 (commas removed).
///   - Empty / non-numeric input returns 0.
double parseAmount(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return 0;
  s = s.replaceAll(RegExp(r'\s+(cr|dr)\.?$', caseSensitive: false), '');
  s = s
      .replaceAll(RegExp(r'(₹|\$|£|€|Rs\.?|INR| )', caseSensitive: false), '')
      .trim();
  bool negative = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    negative = true;
    s = s.substring(1, s.length - 1);
  }
  final lastComma = s.lastIndexOf(',');
  final lastDot = s.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    if (lastComma > lastDot) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (lastComma >= 0) {
    final afterComma = s.substring(lastComma + 1);
    if (afterComma.length == 2 && !afterComma.contains(',')) {
      s = s.replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  }
  s = s.replaceAll(RegExp(r'\s+'), '');
  final v = double.tryParse(s) ?? 0;
  return negative ? -v : v;
}
