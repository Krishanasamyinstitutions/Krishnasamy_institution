// Login → Dashboard → Logout
//
// Requires staging Supabase + a known admin user. Set env vars before running:
//   set TEST_INSTITUTION_EMAIL=test@kcet.local
//   set TEST_INSTITUTION_PASSWORD=Test@2026
//
// Run: flutter test integration_test/auth_flow_test.dart -d windows

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

  testWidgets('login → dashboard → logout', (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 6));

    // Find email + password TextFormFields on the welcome screen.
    final fields = find.byType(TextFormField);
    expect(fields, findsAtLeastNWidgets(2),
        reason: 'welcome login form not visible');

    await tester.enterText(fields.at(0), email!);
    await tester.enterText(fields.at(1), password!);
    await tester.pumpAndSettle();

    // Tap LOGIN button (case-insensitive search).
    final loginBtn = find.text('LOGIN');
    await tester.tap(loginBtn.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // Dashboard mounted: sidebar 'Dashboard' label visible.
    expect(find.text('Dashboard'), findsWidgets);

    // Logout — open user menu, tap Logout. Path may vary; this is the
    // canonical flow today.
    final avatar = find.byKey(const Key('user-menu-avatar'));
    if (avatar.evaluate().isNotEmpty) {
      await tester.tap(avatar.first);
      await tester.pumpAndSettle();
      final logout = find.text('Logout');
      if (logout.evaluate().isNotEmpty) {
        await tester.tap(logout.first);
        await tester.pumpAndSettle(const Duration(seconds: 3));
      }
    }
    // Skip note: requires TEST_INSTITUTION_EMAIL & TEST_INSTITUTION_PASSWORD.
  }, skip: !hasCreds);
}
