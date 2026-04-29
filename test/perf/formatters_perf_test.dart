// Microbenchmarks for hot-path formatters. These run under `flutter test`
// and assert each operation stays under a generous budget so a future
// regression (e.g. accidental String.split storm in formatIndianNumber)
// is caught in CI rather than first noticed when 10K-row reports get slow.

import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/bank_parsers.dart';
import 'package:school_admin/utils/formatters.dart';

({Duration total, double perCall}) _measure(int iterations, void Function() body) {
  final sw = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    body();
  }
  sw.stop();
  return (total: sw.elapsed, perCall: sw.elapsedMicroseconds / iterations);
}

void main() {
  group('Hot-path performance', () {
    test('formatIndianNumber under 5 µs per call', () {
      final r = _measure(20000, () => formatIndianNumber(1234567.89));
      // Generous bound — observed ~0.5 µs on i5/8GB. Failure ≈ 10× regression.
      expect(r.perCall, lessThan(5.0),
          reason: 'formatIndianNumber regressed: ${r.perCall} µs/call');
    });

    test('parseAmount under 5 µs per call', () {
      final r = _measure(20000, () => parseAmount('₹1,23,456.78 Cr'));
      expect(r.perCall, lessThan(5.0),
          reason: 'parseAmount regressed: ${r.perCall} µs/call');
    });

    test('toIsoDate under 3 µs per call', () {
      final r = _measure(20000, () => toIsoDate('15/04/2026'));
      expect(r.perCall, lessThan(3.0),
          reason: 'toIsoDate regressed: ${r.perCall} µs/call');
    });

    test('normalizeReference under 2 µs per call', () {
      final r = _measure(20000, () => normalizeReference(' utr-123/45 '));
      expect(r.perCall, lessThan(2.0),
          reason: 'normalizeReference regressed: ${r.perCall} µs/call');
    });

    test('1000-row formatIndianNumber loop completes under 10 ms', () {
      final r = _measure(1000, () => formatIndianNumber(1234567.89));
      expect(r.total.inMilliseconds, lessThan(10),
          reason: '1000-row format took ${r.total.inMilliseconds} ms');
    });
  });
}
