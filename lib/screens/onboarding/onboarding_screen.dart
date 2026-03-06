import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';

class OnboardingData {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color iconColor;
  final List<String> features;

  const OnboardingData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.iconColor,
    required this.features,
  });
}

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingData> _pages = [
    OnboardingData(
      title: 'Student\nManagement',
      subtitle: 'Organize Everything',
      description:
          'Effortlessly manage student records, admissions, attendance, and academic performance — all from one centralized platform.',
      icon: Icons.people_alt_rounded,
      iconColor: AppColors.accent,
      features: [
        'Digital Student Profiles',
        'Attendance Tracking',
        'Grade Management',
      ],
    ),
    OnboardingData(
      title: 'Staff &\nScheduling',
      subtitle: 'Streamline Operations',
      description:
          'Manage faculty information, create timetables, assign duties, and track leave requests with intelligent scheduling tools.',
      icon: Icons.calendar_month_rounded,
      iconColor: AppColors.secondary,
      features: [
        'Smart Timetables',
        'Leave Management',
        'Duty Assignments',
      ],
    ),
    OnboardingData(
      title: 'Reports &\nAnalytics',
      subtitle: 'Data-Driven Decisions',
      description:
          'Generate comprehensive reports, track performance trends, and gain actionable insights to improve educational outcomes.',
      icon: Icons.insights_rounded,
      iconColor: AppColors.info,
      features: [
        'Performance Analytics',
        'Custom Reports',
        'Trend Visualization',
      ],
    ),
  ];

  void _nextPage() {
    if (_currentPage < _pages.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOutCubic,
      );
    } else {
      Navigator.pushReplacementNamed(context, AppRoutes.welcome);
    }
  }

  void _skip() {
    Navigator.pushReplacementNamed(context, AppRoutes.welcome);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // Background decoration
          Positioned(
            top: -100,
            right: -100,
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
            bottom: -50,
            left: -50,
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.secondary.withValues(alpha: 0.05),
              ),
            ),
          ),

          // Main content
          Column(
            children: [
              // Top bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.school_rounded,
                            color: AppColors.accent,
                            size: 22,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'EduDesk',
                          style: Theme.of(context)
                              .textTheme
                              .titleLarge
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    TextButton(
                      onPressed: _skip,
                      child: Row(
                        children: [
                          Text(
                            'Skip',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: AppColors.textSecondary,
                                    ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            color: AppColors.textSecondary,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              // Page view
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  itemCount: _pages.length,
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  itemBuilder: (context, index) {
                    return _OnboardingPage(
                      data: _pages[index],
                      isDesktop: isDesktop,
                    );
                  },
                ),
              ),

              // Bottom navigation
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 32, vertical: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Page indicators
                    Row(
                      children: List.generate(
                        _pages.length,
                        (index) => AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          margin: const EdgeInsets.only(right: 8),
                          height: 6,
                          width: _currentPage == index ? 32 : 6,
                          decoration: BoxDecoration(
                            color: _currentPage == index
                                ? AppColors.accent
                                : AppColors.border,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),

                    // Next button
                    MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: _nextPage,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          padding: EdgeInsets.symmetric(
                            horizontal:
                                _currentPage == _pages.length - 1 ? 32 : 24,
                            vertical: 16,
                          ),
                          decoration: BoxDecoration(
                            gradient: AppColors.accentGradient,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.accent.withValues(alpha: 0.3),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _currentPage == _pages.length - 1
                                    ? 'Get Started'
                                    : 'Next',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OnboardingPage extends StatelessWidget {
  final OnboardingData data;
  final bool isDesktop;

  const _OnboardingPage({required this.data, required this.isDesktop});

  @override
  Widget build(BuildContext context) {
    if (isDesktop) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 64),
        child: Row(
          children: [
            // Left: illustration
            Expanded(
              flex: 5,
              child: FadeInLeft(
                duration: const Duration(milliseconds: 600),
                child: _buildIllustration(context),
              ),
            ),
            const SizedBox(width: 64),
            // Right: content
            Expanded(
              flex: 5,
              child: FadeInRight(
                duration: const Duration(milliseconds: 600),
                child: _buildContent(context),
              ),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          const SizedBox(height: 24),
          FadeInDown(
            duration: const Duration(milliseconds: 600),
            child: _buildIllustration(context),
          ),
          const SizedBox(height: 40),
          FadeInUp(
            duration: const Duration(milliseconds: 600),
            child: _buildContent(context),
          ),
        ],
      ),
    );
  }

  Widget _buildIllustration(BuildContext context) {
    return Center(
      child: Container(
        width: 280,
        height: 280,
        decoration: BoxDecoration(
          color: data.iconColor.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: data.iconColor.withValues(alpha: 0.15),
            width: 2,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background decorative circles
            Positioned(
              top: 30,
              right: 30,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: data.iconColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 30,
              child: Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: data.iconColor.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Icon(
              data.icon,
              size: 100,
              color: data.iconColor,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Subtitle chip
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: data.iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            data.subtitle,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: data.iconColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
          ),
        ),

        const SizedBox(height: 20),

        // Title
        Text(
          data.title,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                height: 1.2,
              ),
        ),

        const SizedBox(height: 16),

        // Description
        Text(
          data.description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.6,
                color: AppColors.textSecondary,
              ),
        ),

        const SizedBox(height: 32),

        // Feature list
        ...data.features.map(
          (feature) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: data.iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.check_rounded,
                    color: data.iconColor,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  feature,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
