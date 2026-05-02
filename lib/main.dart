import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase_config.dart';
import 'utils/app_theme.dart';
import 'utils/app_routes.dart';
import 'utils/auth_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Silence all debugPrint calls in release builds. Every existing
  // debugPrint across the codebase routes through this handler, so
  // this single override keeps debug behaviour identical while
  // preventing logs from leaking in production.
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }

  // Initialize Supabase
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider()),
      ],
      child: const SchoolAdminApp(),
    ),
  );
}

class SchoolAdminApp extends StatelessWidget {
  const SchoolAdminApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ScreenUtilInit(
      // Design baseline tuned so 1366×768 renders at ~78% scale
      // (1366/1750 ≈ 0.78). On 1920×1080 things scale up to ~110%, so the
      // UI feels proportional on both common laptop and desktop sizes.
      // Mobile screens (welcome/onboarding/login/forgot) use fixed pixel
      // values, so they aren't affected.
      designSize: const Size(1750, 984),
      minTextAdapt: true,
      builder: (context, child) {
        return MaterialApp(
          title: 'EduCore360 - School Administration',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: ThemeMode.light,
          scrollBehavior: const _AppScrollBehavior(),
          initialRoute: AppRoutes.splash,
          routes: AppRoutes.routes,
        );
      },
    );
  }
}

/// App-wide scroll behaviour:
/// - Adds trackpad and stylus to the default drag set (mouse is intentionally
///   omitted — enabling it makes mouse-drag inside TextFields a scroll
///   gesture, which breaks click-drag text selection).
/// - Uses a smooth bouncing physics so wheel/drag inertia feels natural.
class _AppScrollBehavior extends MaterialScrollBehavior {
  const _AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}
