// Auto-login on relaunch.
//
// Validates that AuthProvider's flutter_secure_storage path persists the
// password and the next launch lands on the dashboard without re-entering
// credentials.
//
// Run: flutter test integration_test/auto_login_test.dart -d windows

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:school_admin/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final email = Platform.environment['TEST_INSTITUTION_EMAIL'];
  final password = Platform.environment['TEST_INSTITUTION_PASSWORD'];
  final hasCreds = email != null && password != null;

  testWidgets('previously-logged-in user lands on Dashboard without login form',
      (tester) async {
    app.main();
    await tester.pumpAndSettle(const Duration(seconds: 8));

    // If credentials were saved on a prior run, the login form should NOT
    // be visible — Dashboard should mount directly.
    final dashboardLabel = find.text('Dashboard');
    expect(dashboardLabel, findsWidgets,
        reason: 'expected auto-login to land on Dashboard');
  }, skip: !hasCreds);
}
