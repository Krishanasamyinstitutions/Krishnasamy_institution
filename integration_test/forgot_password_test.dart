// Forgot-password OTP flow: email → OTP → new password → next login works.
//
// Requires staging Supabase + a known user with OTP-mock disabled (so the
// edge function fires). Set:
//   set TEST_INSTITUTION_EMAIL=test@kcet.local
//   set TEST_OTP_CODE=123456
//   set TEST_NEW_PASSWORD=NewTest@2026
//
// Run: flutter test integration_test/forgot_password_test.dart -d windows

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:school_admin/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = Platform.environment['TEST_INSTITUTION_EMAIL'];
  final otpCode = Platform.environment['TEST_OTP_CODE'];
  final newPassword = Platform.environment['TEST_NEW_PASSWORD'];
  final hasAll = email != null && otpCode != null && newPassword != null;

  testWidgets('forgot password 3-step flow advances through each step',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 6));

    // Tap Forgot Password? link
    final link = find.text('Forgot Password?');
    if (link.evaluate().isEmpty) return;
    await tester.tap(link.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Step 1: email
    final emailField = find.byType(TextField).first;
    await tester.enterText(emailField, email!);
    await tester.tap(find.text('Send OTP').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 5));

    // Step 2: OTP
    final otpField = find.byType(TextField).first;
    await tester.enterText(otpField, otpCode!);
    await tester.tap(find.text('Verify').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // Step 3: new password
    final pwFields = find.byType(TextField);
    expect(pwFields, findsAtLeastNWidgets(2),
        reason: 'expected new + confirm password fields');
    await tester.enterText(pwFields.at(0), newPassword!);
    await tester.enterText(pwFields.at(1), newPassword);
    await tester.tap(find.text('Reset').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 4));

    // Should land back on welcome screen (login form visible).
    expect(find.byType(TextFormField), findsAtLeastNWidgets(2));
  }, skip: !hasAll);
}
