import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _progressController;

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..forward();

    _navigateToNextScreen();
  }

  Future<void> _navigateToNextScreen() async {
    await Future.delayed(const Duration(seconds: 4));
    if (!mounted) return;

    // Product-license gate. The whole app is gated by an annual product
    // license stored in public.tbsannuallicense. If no active row exists,
    // route to the product-activation screen; if the most recent row is
    // expired, route to the expired-license screen. Only when an active
    // license is found do we proceed to auto-login / onboarding.
    final license = await SupabaseService.client
        .rpc('get_product_license_status')
        .then((v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{})
        .catchError((_) => <String, dynamic>{});
    if (!mounted) return;
    final state = license['state']?.toString();
    if (state != 'active') {
      Navigator.pushReplacementNamed(
        context,
        state == 'expired' ? AppRoutes.productExpired : AppRoutes.productActivation,
      );
      return;
    }
    // Soft "ends soon" warning. Threshold is 30 days; blocks navigation
    // only until the user dismisses the dialog. Shown every startup so
    // the office has a chance of being contacted before the hard expiry.
    final daysLeft = (license['days_left'] as num?)?.toInt() ?? 0;
    if (daysLeft <= 30 && daysLeft > 0) {
      await _showEndingSoonDialog(daysLeft, license['end_date']?.toString());
      if (!mounted) return;
    }

    final auth = context.read<AuthProvider>();
    final loggedIn = await auth.tryAutoLogin();
    if (!mounted) return;

    if (loggedIn) {
      Navigator.pushReplacementNamed(
        context,
        auth.isSuperAdmin ? AppRoutes.superAdminDashboard : AppRoutes.dashboard,
      );
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
    }
  }

  Future<void> _showEndingSoonDialog(int daysLeft, String? endDate) async {
    final dayWord = daysLeft == 1 ? 'day' : 'days';
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        icon: Icon(Icons.schedule_rounded, color: AppColors.accent, size: 40),
        title: const Text('Subscription Ending Soon'),
        content: Text(
          'Your annual license expires in $daysLeft $dayWord'
          '${endDate != null && endDate.isNotEmpty ? ' (on $endDate)' : ''}.\n\n'
          'Please contact the office to renew before this date.',
          textAlign: TextAlign.center,
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _progressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF003166),
              Color(0xFF002147),
              Color(0xFF00152E),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),
              FadeInDown(
                duration: const Duration(milliseconds: 800),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 200.w,
                      height: 200.h,
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(32.r),
                        border: Border.all(
                          color: AppColors.accent.withValues(
                            alpha: 0.3 + (_pulseController.value * 0.2),
                          ),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.accent.withValues(
                              alpha: 0.1 + (_pulseController.value * 0.1),
                            ),
                            blurRadius: 40,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                      padding: EdgeInsets.all(20.w),
                      child: Image.asset(
                        'assets/images/educore360_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.school_rounded,
                          size: 60.sp,
                          color: AppColors.accent,
                        ),
                      ),
                    );
                  },
                ),
              ),
              SizedBox(height: 32.h),
              FadeInUp(
                delay: const Duration(milliseconds: 400),
                duration: const Duration(milliseconds: 800),
                child: Text(
                  'EduCore360',
                  style: Theme.of(context).textTheme.displayLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -1.w,
                      ),
                ),
              ),
              SizedBox(height: 8.h),
              FadeInUp(
                delay: const Duration(milliseconds: 600),
                duration: const Duration(milliseconds: 800),
                child: Text(
                  'School Administration Platform',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColors.textLight.withValues(alpha: 0.8),
                        letterSpacing: 1.w,
                      ),
                ),
              ),
              const Spacer(flex: 2),
              FadeInUp(
                delay: const Duration(milliseconds: 800),
                duration: const Duration(milliseconds: 600),
                child: Column(
                  children: [
                    SizedBox(
                      width: 200.w,
                      child: AnimatedBuilder(
                        animation: _progressController,
                        builder: (context, child) {
                          return ClipRRect(
                            borderRadius: BorderRadius.circular(4.r),
                            child: LinearProgressIndicator(
                              value: _progressController.value,
                              backgroundColor:
                                  Colors.white.withValues(alpha: 0.1),
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColors.accent.withValues(alpha: 0.8),
                              ),
                              minHeight: 3.h,
                            ),
                          );
                        },
                      ),
                    ),
                    SizedBox(height: 16.h),
                    Text(
                      'Initializing...',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textLight.withValues(alpha: 0.5),
                          ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FadeIn(
                delay: const Duration(milliseconds: 1000),
                child: Text(
                  'v1.0.0',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textLight.withValues(alpha: 0.3),
                      ),
                ),
              ),
              SizedBox(height: 32.h),
            ],
          ),
        ),
      ),
    );
  }
}
