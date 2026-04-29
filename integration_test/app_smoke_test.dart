// Phase 3 stub for the app smoke flow (cold-start → welcome screen).
//
// This file is intentionally minimal. Run with:
//   flutter test integration_test/app_smoke_test.dart -d windows
//
// Real auth/recon scenarios in Section 3 of
// `C:\Users\User7\.claude\plans\purring-launching-hearth.md` will use a
// staging Supabase project — do NOT run against production.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:school_admin/main.dart' as app;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('App smoke', () {
    testWidgets('app launches and reaches a top-level route',
        (WidgetTester tester) async {
      app.main();
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Either welcome screen, splash, or login renders within ~5 s.
      expect(find.byType(MaterialApp), findsOneWidget,
          reason: 'app failed to render its root MaterialApp');
    });
  });
}
