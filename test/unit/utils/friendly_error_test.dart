import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/utils/friendly_error.dart';

void main() {
  group('friendlyError', () {
    test('SocketException → cannot reach server', () {
      final result = friendlyError('SocketException: Failed host lookup');
      expect(result, contains('Cannot reach the server'));
    });

    test('TimeoutException → server took too long', () {
      final result = friendlyError(TimeoutException('took too long'));
      expect(result, contains('took too long'));
    });

    test('Postgres 42501 / RLS → permission denied', () {
      final result = friendlyError('PostgrestException: code: 42501, message: row-level security');
      expect(result, contains('permission'));
    });

    test('Duplicate key 23505 → record already exists', () {
      final result = friendlyError('duplicate key value violates 23505');
      expect(result, contains('already exists'));
    });

    test('Foreign key 23503 → linked to other data', () {
      final result = friendlyError('foreign key constraint 23503');
      expect(result, contains('linked'));
    });

    test('Already-paid balance guard returns specific message', () {
      final result =
          friendlyError('PostgrestException: P0001: Demand 12345 is already paid');
      expect(result, contains('already been collected'));
    });

    test('Bucket not found → storage missing', () {
      final result = friendlyError('Bucket not found');
      expect(result, contains('Storage bucket'));
    });

    test('Payload too large → 413 file too big', () {
      final result = friendlyError('413: payload too large');
      expect(result, contains('too large'));
    });

    test('Razorpay order_id not found → start fresh payment', () {
      final result = friendlyError('order_id abc123 not found');
      expect(result, contains('order'));
    });

    test('Unknown error → generic try-again message', () {
      final result = friendlyError('Some weird internal error');
      expect(result, contains('Something went wrong'));
    });

    test('Empty string → generic message', () {
      expect(friendlyError(''), contains('Something went wrong'));
    });

    group('PII redaction (S10)', () {
      test('does not echo the user email passed in the error', () {
        final out =
            friendlyError('Login failed for user secret@example.com (PostgrestException 42501)');
        expect(out, isNot(contains('secret@example.com')));
        expect(out, isNot(contains('@')));
      });

      test('does not echo a phone number passed in the error', () {
        final out = friendlyError('OTP send failed for phone 9876543210');
        expect(out, isNot(contains('9876543210')));
      });

      test('does not echo a password / token in the error', () {
        final out = friendlyError(
            'AuthException: invalid password Krish@!2026 for token abc.def.ghi');
        expect(out, isNot(contains('Krish@!2026')));
        expect(out, isNot(contains('abc.def.ghi')));
      });

      test('demand-id branch surfaces only generic copy', () {
        final out = friendlyError(
            'PostgrestException: P0001: Demand 12345 is already paid');
        expect(out, contains('already been collected'));
        // The numeric ID is OK to echo (not PII), but verify the user
        // email/phone branches don't expose anything.
      });
    });
  });
}
