import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(color: AppColors.surface),
        child: isDesktop
            ? _buildDesktopLayout(context, size)
            : _buildMobileLayout(context, size),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, Size size) {
    return Row(
      children: [
        // Left panel - Decorative
        Expanded(
          flex: 5,
          child: Container(
            decoration: const BoxDecoration(
              gradient: AppColors.splashGradient,
            ),
            child: Stack(
              children: [
                // Decorative elements
                Positioned(
                  top: -80,
                  left: -80,
                  child: Container(
                    width: 300.w,
                    height: 300.h,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.accent.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                Positioned(
                  bottom: -40,
                  right: -40,
                  child: Container(
                    width: 200.w,
                    height: 200.h,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: AppColors.secondary.withValues(alpha: 0.05),
                    ),
                  ),
                ),
                // Grid pattern
                ...List.generate(24, (index) {
                  final row = index ~/ 4;
                  final col = index % 4;
                  return Positioned(
                    top: 80.0 + (row * 100),
                    left: 60.0 + (col * 100),
                    child: Container(
                      width: 4.w,
                      height: 4.h,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                  );
                }),

                // Center content
                Center(
                  child: Padding(
                    padding: EdgeInsets.all(64.w),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FadeInDown(
                          duration: const Duration(milliseconds: 600),
                          child: Container(
                            width: 100.w,
                            height: 100.h,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(28.r),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: Icon(
                              Icons.school_rounded,
                              size: 50.sp,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        SizedBox(height: 32.h),
                        FadeInUp(
                          delay: const Duration(milliseconds: 200),
                          child: Text(
                            'EduDesk',
                            style: Theme.of(context)
                                .textTheme
                                .displayLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 40.sp,
                                ),
                          ),
                        ),
                        SizedBox(height: 12.h),
                        FadeInUp(
                          delay: const Duration(milliseconds: 400),
                          child: Text(
                            'Empowering Education Through\nIntelligent Administration',
                            textAlign: TextAlign.center,
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: Colors.white.withValues(alpha: 0.6),
                                      height: 1.6,
                                    ),
                          ),
                        ),
                        SizedBox(height: 48.h),
                        FadeInUp(
                          delay: const Duration(milliseconds: 600),
                          child: _buildStatsRow(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Right panel - Action area
        Expanded(
          flex: 4,
          child: _buildActionPanel(context),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(BuildContext context, Size size) {
    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(32.w),
          child: Column(
            children: [
              SizedBox(height: 40.h),
              FadeInDown(
                child: Container(
                  width: 90.w,
                  height: 90.h,
                  decoration: BoxDecoration(
                    gradient: AppColors.splashGradient,
                    borderRadius: BorderRadius.circular(24.r),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    size: 44.sp,
                    color: AppColors.accent,
                  ),
                ),
              ),
              SizedBox(height: 24.h),
              FadeInUp(
                delay: const Duration(milliseconds: 200),
                child: Text(
                  'EduDesk',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
              ),
              SizedBox(height: 8.h),
              FadeInUp(
                delay: const Duration(milliseconds: 300),
                child: Text(
                  'School Administration Platform',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              SizedBox(height: 48.h),
              _buildActionPanel(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _buildStatItem(context, '500+', 'Schools'),
        Container(
          width: 1.w,
          height: 40.h,
          margin: EdgeInsets.symmetric(horizontal: 28.w),
          color: Colors.white.withValues(alpha: 0.15),
        ),
        _buildStatItem(context, '50K+', 'Students'),
        Container(
          width: 1.w,
          height: 40.h,
          margin: EdgeInsets.symmetric(horizontal: 28.w),
          color: Colors.white.withValues(alpha: 0.15),
        ),
        _buildStatItem(context, '99.9%', 'Uptime'),
      ],
    );
  }

  Widget _buildStatItem(BuildContext context, String value, String label) {
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
              ),
        ),
        SizedBox(height: 4.h),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.white.withValues(alpha: 0.5),
              ),
        ),
      ],
    );
  }

  Widget _buildActionPanel(BuildContext context) {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        padding: EdgeInsets.all(40.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FadeInRight(
              delay: const Duration(milliseconds: 400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Welcome Back!',
                    style: Theme.of(context).textTheme.displayMedium?.copyWith(
                          fontSize: 32.sp,
                        ),
                  ),
                  SizedBox(height: 8.h),
                  Text(
                    'Sign in to continue managing your school, or create a new account to get started.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                        ),
                  ),
                ],
              ),
            ),

            SizedBox(height: 40.h),

            // Super Admin Sign In
            FadeInRight(
              delay: const Duration(milliseconds: 500),
              child: _WelcomeButton(
                label: 'Super Admin Login',
                icon: Icons.admin_panel_settings_rounded,
                isPrimary: true,
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.login, arguments: 'super_admin'),
              ),
            ),

            SizedBox(height: 16.h),

            // Institution User Sign In
            FadeInRight(
              delay: const Duration(milliseconds: 600),
              child: _WelcomeButton(
                label: 'Institution Login',
                icon: Icons.school_rounded,
                isPrimary: false,
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.login, arguments: 'institution'),
              ),
            ),

            SizedBox(height: 32.h),

            // Divider
            FadeInRight(
              delay: const Duration(milliseconds: 800),
              child: Row(
                children: [
                  Expanded(
                    child: Container(height: 1.h, color: AppColors.border),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w),
                    child: Text(
                      'OR',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textLight,
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Container(height: 1.h, color: AppColors.border),
                  ),
                ],
              ),
            ),

            SizedBox(height: 24.h),

            // Demo button
            FadeInRight(
              delay: const Duration(milliseconds: 900),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.dashboard),
                  child: Container(
                    padding: EdgeInsets.symmetric(vertical: 14.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.play_circle_outline_rounded,
                          color: AppColors.primary.withValues(alpha: 0.7),
                          size: 20.sp,
                        ),
                        SizedBox(width: 8.w),
                        Text(
                          'Explore Demo',
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: AppColors.primary.withValues(alpha: 0.7),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomeButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final bool isPrimary;
  final VoidCallback onTap;

  const _WelcomeButton({
    required this.label,
    required this.icon,
    required this.isPrimary,
    required this.onTap,
  });

  @override
  State<_WelcomeButton> createState() => _WelcomeButtonState();
}

class _WelcomeButtonState extends State<_WelcomeButton> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: EdgeInsets.symmetric(vertical: 18.h),
          decoration: BoxDecoration(
            gradient: widget.isPrimary ? AppColors.accentGradient : null,
            color: widget.isPrimary ? null : Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: widget.isPrimary
                ? null
                : Border.all(color: AppColors.border, width: 1.5),
            boxShadow: [
              if (widget.isPrimary)
                BoxShadow(
                  color: AppColors.accent
                      .withValues(alpha: _isHovered ? 0.4 : 0.25),
                  blurRadius: _isHovered ? 25 : 20,
                  offset: const Offset(0, 8),
                ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                color:
                    widget.isPrimary ? Colors.white : AppColors.textPrimary,
                size: 20.sp,
              ),
              SizedBox(width: 10.w),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: widget.isPrimary
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontSize: 16.sp,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
