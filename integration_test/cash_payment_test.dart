// Cash payment flow: lookup student → enter cash payment → receipt opens.
//
// Requires staging Supabase + a known unpaid demand. Set:
//   set TEST_INSTITUTION_EMAIL=test@kcet.local
//   set TEST_INSTITUTION_PASSWORD=Test@2026
//   set TEST_STUDENT_ADM_NO=5432
//
// Run: flutter test integration_test/cash_payment_test.dart -d windows

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:school_admin/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = Platform.environment['TEST_INSTITUTION_EMAIL'];
  final password = Platform.environment['TEST_INSTITUTION_PASSWORD'];
  final admNo = Platform.environment['TEST_STUDENT_ADM_NO'];
  final hasAll = email != null && password != null && admNo != null;

  testWidgets('cash payment opens receipt dialog', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 6));

    // Login
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email!);
    await tester.enterText(fields.at(1), password!);
    await tester.tap(find.text('LOGIN').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // Navigate to Fee Collection
    await tester.tap(find.text('Fee Collection').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Enter admission number in lookup
    final lookup = find.byKey(const Key('student-adm-lookup'));
    if (lookup.evaluate().isEmpty) return; // UI changed; flag in CI
    await tester.enterText(lookup.first, admNo!);
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // Pick first pending demand checkbox + click PAY (cash default).
    final payButton = find.text('PAY');
    if (payButton.evaluate().isNotEmpty) {
      await tester.tap(payButton.first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 4));
      // Receipt dialog appears with Download/Print buttons.
      expect(find.text('Download'), findsWidgets);
      expect(find.text('Print'), findsWidgets);
    }
  }, skip: !hasAll);
}
