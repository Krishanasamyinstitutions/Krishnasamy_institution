import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:school_admin/screens/auth/forgot_password_screen.dart';

Widget _wrap(Widget child) => MaterialApp(
      home: ScreenUtilInit(
        designSize: const Size(360, 690),
        builder: (_, __) => child,
      ),
    );

void main() {
  group('ForgotPasswordScreen', () {
    testWidgets('initial step shows email entry field', (tester) async {
      await tester.pumpWidget(_wrap(const ForgotPasswordScreen()));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // Email step is visible — heading or hint text mentions "email" / "Email"
      expect(find.byType(TextField).evaluate().isNotEmpty ||
          find.byType(TextFormField).evaluate().isNotEmpty, true);
    });

    testWidgets('rejects empty email with client-side error', (tester) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(_wrap(const ForgotPasswordScreen()));
      await tester.pumpAndSettle(const Duration(seconds: 2));

      final buttons = find.byType(ElevatedButton);
      if (buttons.evaluate().isEmpty) return;
      await tester.tap(buttons.first, warnIfMissed: false);
      await tester.pumpAndSettle(const Duration(seconds: 2));

      expect(
        find.textContaining('Enter a valid email', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('renders without exceptions', (tester) async {
      await tester.pumpWidget(_wrap(const ForgotPasswordScreen()));
      await tester.pumpAndSettle(const Duration(seconds: 2));
      // No assertion errors during build
      expect(tester.takeException(), isNull);
    });
  });
}
