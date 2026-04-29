import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import '../../utils/app_routes.dart';

class _TealPalette {
  static const Color dark = Color(0xFF001530);
  static const Color deep = Color(0xFF002147);
  static const Color amber = Color(0xFFD2913C);
  static const Color amberPale = Color(0xFFF0D2A5);

  static const LinearGradient backgroundGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF002147), Color(0xFF001F42), Color(0xFF00152E)],
  );

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE5A85C), Color(0xFFB5752A)],
  );
}

class FeatureItem {
  final String title;
  final String subtitle;
  const FeatureItem({required this.title, required this.subtitle});
}

class OnboardingData {
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final List<FeatureItem> features;

  const OnboardingData({
    required this.title,
    required this.subtitle,
    required this.description,
    required this.icon,
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

  final List<OnboardingData> _pages = const [
    OnboardingData(
      title: 'Student\nManagement',
      subtitle: 'Organize Everything',
      description:
          'Effortlessly manage student records, admissions, attendance, and academic performance â€” all from one centralized platform.',
      icon: Icons.people_alt_rounded,
      features: [
        FeatureItem(
          title: 'Digital Student Profiles',
          subtitle: 'Complete records, photos, and documents in one place',
        ),
        FeatureItem(
          title: 'Attendance Tracking',
          subtitle: 'Daily attendance with automated reports',
        ),
        FeatureItem(
          title: 'Grade Management',
          subtitle: 'Track academic performance across terms',
        ),
      ],
    ),
    OnboardingData(
      title: 'Staff &\nScheduling',
      subtitle: 'Streamline Operations',
      description:
          'Manage faculty information, create timetables, assign duties, and track leave requests with intelligent scheduling tools.',
      icon: Icons.calendar_month_rounded,
      features: [
        FeatureItem(
          title: 'Smart Timetables',
          subtitle: 'Auto-generate class schedules effortlessly',
        ),
        FeatureItem(
          title: 'Leave Management',
          subtitle: 'Approve or decline staff leave requests',
        ),
        FeatureItem(
          title: 'Duty Assignments',
          subtitle: 'Allocate responsibilities across your team',
        ),
      ],
    ),
    OnboardingData(
      title: 'Reports &\nAnalytics',
      subtitle: 'Data-Driven Decisions',
      description:
          'Generate comprehensive reports, track performance trends, and gain actionable insights to improve educational outcomes.',
      icon: Icons.insights_rounded,
      features: [
        FeatureItem(
          title: 'Performance Analytics',
          subtitle: 'Understand student and staff performance trends',
        ),
        FeatureItem(
          title: 'Custom Reports',
          subtitle: 'Build reports tailored to your institution',
        ),
        FeatureItem(
          title: 'Trend Visualization',
          subtitle: 'Charts and dashboards that tell the story',
        ),
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
      backgroundColor: _TealPalette.deep,
      body: Container(
        decoration: const BoxDecoration(
          gradient: _TealPalette.backgroundGradient,
        ),
        child: Stack(
          children: [
            Positioned(
              top: -100,
              right: -100,
              child: Container(
                width: 300,
                height: 300,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _TealPalette.amber.withValues(alpha: 0.07),
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
                  color: _TealPalette.amberPale.withValues(alpha: 0.05),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 24,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(12),
                              child: Container(
                                width: 40,
                                height: 40,
                                color: Colors.white,
                                padding: EdgeInsets.all(2),
                                child: Image.asset(
                                  'assets/images/educore360_logo.png',
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, __, ___) => const Icon(
                                    Icons.school_rounded,
                                    color: _TealPalette.amber,
                                    size: 22,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 12),
                            Text(
                              'EduCore360',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: _skip,
                          child: Row(
                            children: [
                              Text(
                                'Skip',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyLarge
                                    ?.copyWith(
                                      color: _TealPalette.amberPale,
                                    ),
                              ),
                              SizedBox(width: 4),
                              const Icon(
                                Icons.chevron_right_rounded,
                                color: _TealPalette.amberPale,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 32,
                      vertical: 32,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: List.generate(
                            _pages.length,
                            (index) => AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              margin: EdgeInsets.only(right: 8),
                              height: 6,
                              width: _currentPage == index ? 32 : 6,
                              decoration: BoxDecoration(
                                color: _currentPage == index
                                    ? _TealPalette.amber
                                    : Colors.white.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        ),
                        MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onTap: _nextPage,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              padding: EdgeInsets.symmetric(
                                horizontal: _currentPage == _pages.length - 1
                                    ? 32
                                    : 24,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                gradient: _TealPalette.buttonGradient,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: _TealPalette.amber
                                        .withValues(alpha: 0.4),
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
                                  SizedBox(width: 8),
                                  const Icon(
                                    Icons.chevron_right_rounded,
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
            ),
          ],
        ),
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
        padding: EdgeInsets.symmetric(horizontal: 64),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: FadeInLeft(
                duration: const Duration(milliseconds: 600),
                child: _buildIllustration(context),
              ),
            ),
            SizedBox(width: 64),
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
      padding: EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          SizedBox(height: 24),
          FadeInDown(
            duration: const Duration(milliseconds: 600),
            child: _buildIllustration(context),
          ),
          SizedBox(height: 40),
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
          color: _TealPalette.dark.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(40),
          border: Border.all(
            color: _TealPalette.amber.withValues(alpha: 0.25),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: _TealPalette.amber.withValues(alpha: 0.15),
              blurRadius: 40,
              spreadRadius: 4,
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              top: 30,
              right: 30,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _TealPalette.amber.withValues(alpha: 0.15),
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
                  color: _TealPalette.amberPale.withValues(alpha: 0.25),
                  shape: BoxShape.circle,
                ),
              ),
            ),
            Icon(
              data.icon,
              size: 100,
              color: _TealPalette.amber,
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
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: _TealPalette.amber.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _TealPalette.amber.withValues(alpha: 0.4),
            ),
          ),
          child: Text(
            data.subtitle,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: _TealPalette.amber,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
          ),
        ),
        SizedBox(height: 20),
        Text(
          data.title,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
                height: 1.2,
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
        ),
        SizedBox(height: 16),
        Text(
          data.description,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                height: 1.6,
                color: Colors.white.withValues(alpha: 0.75),
              ),
        ),
        SizedBox(height: 28),
        ...data.features.map(
          (feature) => Padding(
            padding: EdgeInsets.only(bottom: 12),
            child: _FeatureCard(item: feature),
          ),
        ),
      ],
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final FeatureItem item;
  const _FeatureCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _TealPalette.dark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _TealPalette.amber.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _TealPalette.amber,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: _TealPalette.amber.withValues(alpha: 0.45),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                ),
                SizedBox(height: 2),
                Text(
                  item.subtitle,
                  style: TextStyle(
                    color: _TealPalette.amberPale.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
