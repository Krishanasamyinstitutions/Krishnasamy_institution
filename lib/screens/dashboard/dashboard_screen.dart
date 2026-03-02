import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../widgets/dashboard_sidebar.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/attendance_chart.dart';
import '../../widgets/recent_activities.dart';
import '../../widgets/upcoming_events.dart';
import '../../widgets/quick_actions.dart';
import '../../services/supabase_service.dart';
import '../../models/fee_model.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;

  // Supabase data
  int _studentCount = 0;
  int _teacherCount = 0;
  FeeSummary? _feeSummary;
  bool _isLoadingStats = true;

  final List<_NavItem> _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.people_alt_rounded, 'Students'),
    _NavItem(Icons.school_rounded, 'Teachers'),
    _NavItem(Icons.class_rounded, 'Classes'),
    _NavItem(Icons.event_note_rounded, 'Attendance'),
    _NavItem(Icons.assessment_rounded, 'Exams'),
    _NavItem(Icons.account_balance_wallet_rounded, 'Fees'),
    _NavItem(Icons.calendar_month_rounded, 'Calendar'),
    _NavItem(Icons.notifications_rounded, 'Notices'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoadingStats = true);

    final results = await Future.wait([
      SupabaseService.getStudentCount(insId),
      SupabaseService.getTeacherCount(insId),
      SupabaseService.getFeeSummary(insId),
    ]);

    if (mounted) {
      setState(() {
        _studentCount = results[0] as int;
        _teacherCount = results[1] as int;
        _feeSummary = results[2] as FeeSummary;
        _isLoadingStats = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 1100;
    final isTablet = size.width > 700 && size.width <= 1100;

    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: (!isDesktop && !isTablet)
          ? Drawer(child: _buildSidebar(context, false))
          : null,
      body: Row(
        children: [
          // Sidebar
          if (isDesktop || isTablet)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _sidebarCollapsed ? 78 : (isDesktop ? 260 : 78),
              child: _buildSidebar(
                  context, _sidebarCollapsed || isTablet),
            ),

          // Main content
          Expanded(
            child: Column(
              children: [
                // Top bar
                _buildTopBar(context, isDesktop),

                // Content area
                Expanded(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isDesktop ? 28 : 16),
                    child: _buildDashboardContent(context, isDesktop),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar(BuildContext context, bool collapsed) {
    final auth = context.watch<AuthProvider>();

    return Container(
      color: AppColors.primary,
      child: Column(
        children: [
          // Logo area
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 16 : 24,
              vertical: 24,
            ),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: AppColors.accent,
                    size: 22,
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 14),
                  Text(
                    'EduDesk',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: 8),

          // Nav items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 12 : 16),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = _selectedNavIndex == index;

                return Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedNavIndex = index),
                      borderRadius: BorderRadius.circular(12),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 12 : 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accent.withValues(alpha: 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              color: isSelected
                                  ? AppColors.accent
                                  : Colors.white.withValues(alpha: 0.5),
                              size: 22,
                            ),
                            if (!collapsed) ...[
                              const SizedBox(width: 14),
                              Text(
                                item.label,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(
                                      color: isSelected
                                          ? AppColors.accent
                                          : Colors.white.withValues(alpha: 0.7),
                                      fontWeight: isSelected
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // User profile at bottom
          Container(
            padding: EdgeInsets.all(collapsed ? 12 : 20),
            margin: EdgeInsets.all(collapsed ? 8 : 16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                  child: Text(
                    (auth.userName ?? 'U')[0],
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (!collapsed) ...[
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          auth.userName ?? 'User',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          auth.userRole ?? 'Staff',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.5),
                                    fontSize: 11,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      auth.logout();
                      Navigator.pushReplacementNamed(
                          context, AppRoutes.welcome);
                    },
                    child: Icon(
                      Icons.logout_rounded,
                      color: Colors.white.withValues(alpha: 0.5),
                      size: 18,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDesktop) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? 28 : 16,
        vertical: 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (!isDesktop && MediaQuery.of(context).size.width <= 700)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          if (isDesktop)
            IconButton(
              onPressed: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              icon: Icon(
                _sidebarCollapsed
                    ? Icons.menu_open_rounded
                    : Icons.menu_rounded,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _navItems[_selectedNavIndex].label,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text(
                  'Academic Year 2025-26',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontSize: 12,
                      ),
                ),
              ],
            ),
          ),

          // Search bar (desktop only)
          if (isDesktop)
            Container(
              width: 280,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: TextField(
                decoration: InputDecoration(
                  hintText: 'Search students, staff...',
                  hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textLight,
                        fontSize: 13,
                      ),
                  prefixIcon: const Icon(Icons.search_rounded,
                      size: 20, color: AppColors.textLight),
                  border: InputBorder.none,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                ),
              ),
            ),

          const SizedBox(width: 16),

          // Notification bell
          Stack(
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_outlined, size: 22),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.error,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDashboardContent(BuildContext context, bool isDesktop) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Stat cards
        FadeInDown(
          duration: const Duration(milliseconds: 400),
          child: _buildStatCards(context, isDesktop),
        ),

        const SizedBox(height: 24),

        // Quick actions
        FadeInDown(
          delay: const Duration(milliseconds: 100),
          duration: const Duration(milliseconds: 400),
          child: const QuickActionsWidget(),
        ),

        const SizedBox(height: 24),

        // Charts & Activity row
        if (isDesktop)
          FadeInDown(
            delay: const Duration(milliseconds: 200),
            duration: const Duration(milliseconds: 400),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 6, child: const AttendanceChartWidget()),
                const SizedBox(width: 24),
                Expanded(flex: 4, child: const UpcomingEventsWidget()),
              ],
            ),
          )
        else ...[
          FadeInDown(
            delay: const Duration(milliseconds: 200),
            child: const AttendanceChartWidget(),
          ),
          const SizedBox(height: 24),
          FadeInDown(
            delay: const Duration(milliseconds: 300),
            child: const UpcomingEventsWidget(),
          ),
        ],

        const SizedBox(height: 24),

        // Recent activities
        FadeInDown(
          delay: const Duration(milliseconds: 300),
          duration: const Duration(milliseconds: 400),
          child: const RecentActivitiesWidget(),
        ),
      ],
    );
  }

  String _formatCurrency(double amount) {
    if (amount >= 10000000) {
      return '₹${(amount / 10000000).toStringAsFixed(1)}Cr';
    } else if (amount >= 100000) {
      return '₹${(amount / 100000).toStringAsFixed(1)}L';
    } else if (amount >= 1000) {
      return '₹${(amount / 1000).toStringAsFixed(1)}K';
    }
    return '₹${amount.toStringAsFixed(0)}';
  }

  Widget _buildStatCards(BuildContext context, bool isDesktop) {
    final totalPaid = _feeSummary?.totalPaid ?? 0;
    final totalDue = _feeSummary?.totalDue ?? 0;
    final targetPercent =
        totalDue > 0 ? ((totalPaid / totalDue) * 100).toStringAsFixed(0) : '0';

    final stats = [
      StatData(
        label: 'Total Students',
        value: _isLoadingStats ? '...' : '$_studentCount',
        change: '',
        isPositive: true,
        icon: Icons.people_alt_rounded,
        color: AppColors.accent,
      ),
      StatData(
        label: 'Total Teachers',
        value: _isLoadingStats ? '...' : '$_teacherCount',
        change: '',
        isPositive: true,
        icon: Icons.school_rounded,
        color: AppColors.info,
      ),
      StatData(
        label: "Today's Attendance",
        value: '--',
        change: 'Coming soon',
        isPositive: true,
        icon: Icons.check_circle_outline_rounded,
        color: AppColors.success,
      ),
      StatData(
        label: 'Fee Collection',
        value: _isLoadingStats ? '...' : _formatCurrency(totalPaid),
        change: _isLoadingStats ? '' : '$targetPercent% collected',
        isPositive: true,
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.secondary,
      ),
    ];

    if (isDesktop) {
      return Row(
        children: stats.map((stat) {
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                right: stat == stats.last ? 0 : 16,
              ),
              child: StatCard(data: stat),
            ),
          );
        }).toList(),
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: stats.map((stat) {
        return SizedBox(
          width: (MediaQuery.of(context).size.width - 44) / 2,
          child: StatCard(data: stat),
        );
      }).toList(),
    );
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  const _NavItem(this.icon, this.label);
}
