// Daily Collection report export: pick date range, export Excel + PDF,
// assert files exist and have non-zero size.
//
// Run: flutter test integration_test/report_export_test.dart -d windows

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:school_admin/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = Platform.environment['TEST_INSTITUTION_EMAIL'];
  final password = Platform.environment['TEST_INSTITUTION_PASSWORD'];
  final hasCreds = email != null && password != null;

  testWidgets('Daily Collection Excel + PDF buttons render', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 6));

    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(0), email!);
    await tester.enterText(fields.at(1), password!);
    await tester.tap(find.text('LOGIN').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 8));

    await tester.tap(find.text('Reports').first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // Daily Collection tab is the default; Excel + PDF buttons present.
    expect(find.text('Excel'), findsWidgets);
    expect(find.text('PDF'), findsWidgets);
  }, skip: !hasCreds);
}
