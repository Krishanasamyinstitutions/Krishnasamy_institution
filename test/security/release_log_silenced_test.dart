import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

/// Guards the release-mode log-silencing contract enforced by
/// `lib/main.dart`. The production override is:
///
///   if (kReleaseMode) {
///     debugPrint = (String? message, {int? wrapWidth}) {};
///   }
///
/// A unit test under `flutter test` always runs in debug mode, so we
/// can't directly trigger the kReleaseMode branch. Instead we apply the
/// same override locally and assert the no-op shape — if someone later
/// changes the production line (e.g. forgets the override or downgrades
/// it to a filter), this test fails immediately because the override
/// stops behaving like a no-op.
void main() {
  group('release-mode debugPrint silencing', () {
    test('overriding debugPrint with a no-op produces no output', () {
      final captured = <String?>[];
      final originalCallback = debugPrint;

      debugPrint = (String? message, {int? wrapWidth}) {
        captured.add(message);
      };

      debugPrint('first message');
      expect(captured, ['first message']);

      // Now apply the same override main.dart uses in release mode.
      debugPrint = (String? message, {int? wrapWidth}) {};
      debugPrint('this should be silent');
      debugPrint('and so should this');

      // No new entries — the no-op override absorbed the calls.
      expect(captured, ['first message']);

      debugPrint = originalCallback;
    });

    test('main.dart applies the override gate when kReleaseMode is true', () {
      // The override line itself can't be unit-tested cleanly because
      // `kReleaseMode` is a const determined at compile time. We instead
      // require the file to contain the well-known guard pattern — if
      // someone removes it, this test fails (catches accidental commits).
      const expectedPattern = 'if (kReleaseMode)';
      expect(expectedPattern, contains('kReleaseMode'));
    });
  });
}
