import 'package:flutter_test/flutter_test.dart';
import 'package:school_admin/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const SchoolAdminApp());
    expect(find.text('EduDesk'), findsWidgets);
  });
}
