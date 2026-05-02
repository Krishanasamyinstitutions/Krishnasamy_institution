// Microbenchmarks for hot-path formatters. These run under `flutter test`
// and assert each operation stays under a generous budget so a future
// regression (e.g. accidental String.split storm in formatIndianNumber)
// is caught rather than first noticed when 10K-row reports get slow.
//
// Per-call (microsecond) budgets are skipped on CI because GitHub Actions
// runners vary by 5-30x between runs (observed: 0.5 µs locally, 5 µs on a
// good runner, 32 µs on a contended runner). The coarse 1000-row bulk-loop
// test (millisecond budget) still runs everywhere and catches the kind of
// regression these tests were meant to guard against.

import 'dart:io' show Platform;

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

final bool _onCi = Platform.environment['CI'] == 'true';
final Object _skipOnCi = _onCi ? 'CI runner timing too noisy for per-call microbenchmarks' : false;

void main() {
  group('Hot-path performance', () {
    test('formatIndianNumber under 5 µs per call', () {
      final r = _measure(20000, () => formatIndianNumber(1234567.89));
      expect(r.perCall, lessThan(5.0),
          reason: 'formatIndianNumber regressed: ${r.perCall} µs/call');
    }, skip: _skipOnCi);

    test('parseAmount under 5 µs per call', () {
      final r = _measure(20000, () => parseAmount('₹1,23,456.78 Cr'));
      expect(r.perCall, lessThan(5.0),
          reason: 'parseAmount regressed: ${r.perCall} µs/call');
    }, skip: _skipOnCi);

    test('toIsoDate under 3 µs per call', () {
      final r = _measure(20000, () => toIsoDate('15/04/2026'));
      expect(r.perCall, lessThan(3.0),
          reason: 'toIsoDate regressed: ${r.perCall} µs/call');
    }, skip: _skipOnCi);

    test('normalizeReference under 2 µs per call', () {
      final r = _measure(20000, () => normalizeReference(' utr-123/45 '));
      expect(r.perCall, lessThan(2.0),
          reason: 'normalizeReference regressed: ${r.perCall} µs/call');
    }, skip: _skipOnCi);

    test('1000-row formatIndianNumber loop completes under 200 ms', () {
      final r = _measure(1000, () => formatIndianNumber(1234567.89));
      expect(r.total.inMilliseconds, lessThan(200),
          reason: '1000-row format took ${r.total.inMilliseconds} ms');
    });
  });
}
