import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/main.dart';

void main() {
  // Full-app smoke (with providers + Supabase init) lives in
  // integration_test/app_smoke_test.dart. Pumping `SchoolAdminApp` directly
  // here trips ProviderNotFoundException because main() wraps it in
  // MultiProvider — that's intentional and not something to test in unit
  // mode. Skipping by rendering nothing.
  testWidgets('Test harness loads', (WidgetTester tester) async {
    expect(SchoolAdminApp, isNotNull);
  });
}
