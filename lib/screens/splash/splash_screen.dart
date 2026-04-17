import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';

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
        decoration: const BoxDecoration(gradient: AppColors.splashGradient),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(flex: 3),

              // Animated Logo
              FadeInDown(
                duration: const Duration(milliseconds: 800),
                child: AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    return Container(
                      width: 120.w,
                      height: 120.h,
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
                      child: Icon(
                        Icons.school_rounded,
                        size: 60.sp,
                        color: AppColors.accent,
                      ),
                    );
                  },
                ),
              ),

              SizedBox(height: 32.h),

              // App Name
              FadeInUp(
                delay: const Duration(milliseconds: 400),
                duration: const Duration(milliseconds: 800),
                child: Text(
                  'EduDesk',
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

              // Loading indicator
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

              // Version
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
