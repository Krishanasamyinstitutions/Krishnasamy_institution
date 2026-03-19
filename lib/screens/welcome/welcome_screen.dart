import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
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
                    width: 300,
                    height: 300,
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
                    width: 200,
                    height: 200,
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
                      width: 4,
                      height: 4,
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
                    padding: const EdgeInsets.all(64),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        FadeInDown(
                          duration: const Duration(milliseconds: 600),
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              color: AppColors.accent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(28),
                              border: Border.all(
                                color: AppColors.accent.withValues(alpha: 0.3),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.school_rounded,
                              size: 50,
                              color: AppColors.accent,
                            ),
                          ),
                        ),
                        const SizedBox(height: 32),
                        FadeInUp(
                          delay: const Duration(milliseconds: 200),
                          child: Text(
                            'EduDesk',
                            style: Theme.of(context)
                                .textTheme
                                .displayLarge
                                ?.copyWith(
                                  color: Colors.white,
                                  fontSize: 40,
                                ),
                          ),
                        ),
                        const SizedBox(height: 12),
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
                        const SizedBox(height: 48),
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
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              const SizedBox(height: 40),
              FadeInDown(
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    gradient: AppColors.splashGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.3),
                        blurRadius: 30,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    size: 44,
                    color: AppColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              FadeInUp(
                delay: const Duration(milliseconds: 200),
                child: Text(
                  'EduDesk',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
              ),
              const SizedBox(height: 8),
              FadeInUp(
                delay: const Duration(milliseconds: 300),
                child: Text(
                  'School Administration Platform',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              const SizedBox(height: 48),
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
          width: 1,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 28),
          color: Colors.white.withValues(alpha: 0.15),
        ),
        _buildStatItem(context, '50K+', 'Students'),
        Container(
          width: 1,
          height: 40,
          margin: const EdgeInsets.symmetric(horizontal: 28),
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
        const SizedBox(height: 4),
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
        padding: const EdgeInsets.all(40),
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
                          fontSize: 32,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Sign in to continue managing your school, or create a new account to get started.',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                        ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 40),

            // Sign In button
            FadeInRight(
              delay: const Duration(milliseconds: 500),
              child: _WelcomeButton(
                label: 'Sign In',
                icon: Icons.login_rounded,
                isPrimary: true,
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.login),
              ),
            ),

            const SizedBox(height: 16),

            // Create Account button
            FadeInRight(
              delay: const Duration(milliseconds: 600),
              child: _WelcomeButton(
                label: 'Create Account',
                icon: Icons.person_add_alt_rounded,
                isPrimary: false,
                onTap: () =>
                    Navigator.pushNamed(context, AppRoutes.register),
              ),
            ),

            const SizedBox(height: 32),

            // Divider
            FadeInRight(
              delay: const Duration(milliseconds: 700),
              child: Row(
                children: [
                  Expanded(
                    child: Container(height: 1, color: AppColors.border),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: AppColors.textLight,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Container(height: 1, color: AppColors.border),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Demo button
            FadeInRight(
              delay: const Duration(milliseconds: 800),
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: GestureDetector(
                  onTap: () =>
                      Navigator.pushNamed(context, AppRoutes.dashboard),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
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
                          size: 20,
                        ),
                        const SizedBox(width: 8),
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
          padding: const EdgeInsets.symmetric(vertical: 18),
          decoration: BoxDecoration(
            gradient: widget.isPrimary ? AppColors.accentGradient : null,
            color: widget.isPrimary ? null : Colors.white,
            borderRadius: BorderRadius.circular(10),
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
                size: 20,
              ),
              const SizedBox(width: 10),
              Text(
                widget.label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: widget.isPrimary
                          ? Colors.white
                          : AppColors.textPrimary,
                      fontSize: 16,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
