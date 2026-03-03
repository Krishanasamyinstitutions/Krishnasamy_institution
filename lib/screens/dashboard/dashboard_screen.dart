import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/recent_activities.dart';
import '../../widgets/upcoming_events.dart';
import '../../widgets/quick_actions.dart';
import '../../services/supabase_service.dart';
import '../../models/fee_model.dart';
import '../students/students_screen.dart';

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
  FeeSummary? _feeSummary;
  bool _isLoadingStats = true;
  String? _institutionType;
  String _institutionRecognized = 'Yes';
  DateTime? _institutionStartDate;
  DateTime? _affiliationStartYear;
  final TextEditingController _institutionNameController =
      TextEditingController();
  final TextEditingController _institutionCodeController =
      TextEditingController();
  final TextEditingController _authorizedUsernameController =
      TextEditingController();
  final TextEditingController _designationController = TextEditingController();
  final TextEditingController _mobileNumberController = TextEditingController();
  final TextEditingController _institutionAffiliationController =
      TextEditingController();
  final TextEditingController _affiliationNumberController =
      TextEditingController();
  final TextEditingController _address1Controller = TextEditingController();
  final TextEditingController _address2Controller = TextEditingController();
  final TextEditingController _address3Controller = TextEditingController();
  final TextEditingController _pinCodeController = TextEditingController();
  final List<String> _institutionTypes = [
    'Schools (Primary, Secondary, Higher Secondary)',
    'Colleges',
    'Universities',
    'Polytechnic Institutions',
    'Vocational Training Centers',
    'Coaching Institutes',
  ];

  final List<_NavItem> _navItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.people_alt_rounded, 'Students'),
    _NavItem(Icons.class_rounded, 'Classes'),
    _NavItem(Icons.domain_add_rounded, 'Institution creation'),
    _NavItem(Icons.account_balance_wallet_rounded, 'Fees'),
    _NavItem(Icons.notifications_rounded, 'Notices'),
    _NavItem(Icons.settings_rounded, 'Settings'),
  ];

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  @override
  void dispose() {
    _institutionNameController.dispose();
    _institutionCodeController.dispose();
    _authorizedUsernameController.dispose();
    _designationController.dispose();
    _mobileNumberController.dispose();
    _institutionAffiliationController.dispose();
    _affiliationNumberController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _address3Controller.dispose();
    _pinCodeController.dispose();
    super.dispose();
  }

  Future<void> _loadDashboardData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoadingStats = true);

    final results = await Future.wait([
      SupabaseService.getStudentCount(insId),
      SupabaseService.getFeeSummary(insId),
    ]);

    if (mounted) {
      setState(() {
        _studentCount = results[0] as int;
        _feeSummary = results[1] as FeeSummary;
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
                  child: _isFullHeightScreen()
                      ? Padding(
                          padding: EdgeInsets.all(isDesktop ? 28 : 16),
                          child: _buildDashboardContent(context, isDesktop),
                        )
                      : SingleChildScrollView(
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

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDesktop) {
    final auth = context.watch<AuthProvider>();
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
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                  child: Text(
                    (auth.userName ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 180 : 120,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.userName ?? 'User',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      Text(
                        auth.userRole ?? 'Staff',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppColors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  tooltip: 'Profile options',
                  position: PopupMenuPosition.under,
                  offset: const Offset(0, 8),
                  color: Colors.white,
                  elevation: 10,
                  surfaceTintColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: AppColors.border),
                  ),
                  menuPadding: const EdgeInsets.symmetric(vertical: 6),
                  padding: EdgeInsets.zero,
                  icon: const Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: AppColors.textSecondary,
                  ),
                  onSelected: (value) {
                    if (value == 'signout') {
                      auth.logout();
                      Navigator.pushReplacementNamed(context, AppRoutes.welcome);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem<String>(
                      value: 'signout',
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded, size: 18),
                          SizedBox(width: 8),
                          Text('Sign out'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Screens that manage their own scroll and need full bounded height
  bool _isFullHeightScreen() {
    final label = _navItems[_selectedNavIndex].label;
    return label == 'Students';
  }

  Widget _buildDashboardContent(BuildContext context, bool isDesktop) {
    final selectedMenu = _navItems[_selectedNavIndex].label;
    if (selectedMenu == 'Institution creation') {
      return _buildInstitutionCreationContent(context, isDesktop);
    }
    if (selectedMenu == 'Students') {
      return const StudentsScreen();
    }

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

        // Upcoming events row
        if (isDesktop)
          FadeInDown(
            delay: const Duration(milliseconds: 200),
            duration: const Duration(milliseconds: 400),
            child: const UpcomingEventsWidget(),
          )
        else ...[
          FadeInDown(
            delay: const Duration(milliseconds: 200),
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

  Widget _buildInstitutionCreationContent(BuildContext context, bool isDesktop) {
    final fieldWidth = isDesktop
        ? (MediaQuery.of(context).size.width - (_sidebarCollapsed ? 180 : 360)) /
            2
        : double.infinity;

    return FadeInDown(
      duration: const Duration(milliseconds: 300),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Institution Type',
                child: DropdownButtonFormField<String>(
                  initialValue: _institutionType,
                  decoration: const InputDecoration(
                    hintText: 'Select institution type',
                  ),
                  items: _institutionTypes
                      .map((type) => DropdownMenuItem<String>(
                            value: type,
                            child: Text(type),
                          ))
                      .toList(),
                  onChanged: (value) =>
                      setState(() => _institutionType = value),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Institution Name',
                child: TextFormField(
                  controller: _institutionNameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter institution name',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Institution Code',
                child: TextFormField(
                  controller: _institutionCodeController,
                  decoration: const InputDecoration(
                    hintText: 'Enter institution code',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Institution Start Date',
                child: _buildDateField(
                  context: context,
                  value: _institutionStartDate,
                  onTap: _pickInstitutionStartDate,
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Authorized Username',
                child: TextFormField(
                  controller: _authorizedUsernameController,
                  decoration: const InputDecoration(
                    hintText: 'Enter authorized username',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Designation',
                child: TextFormField(
                  controller: _designationController,
                  decoration: const InputDecoration(
                    hintText: 'Enter designation',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Mobile Number',
                child: TextFormField(
                  controller: _mobileNumberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    hintText: 'Enter mobile number',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Institution Recognized',
                child: DropdownButtonFormField<String>(
                  initialValue: _institutionRecognized,
                  decoration: const InputDecoration(
                    hintText: 'Select recognized status',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Yes', child: Text('Yes')),
                    DropdownMenuItem(value: 'No', child: Text('No')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _institutionRecognized = value);
                    }
                  },
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Institution Affiliation',
                child: TextFormField(
                  controller: _institutionAffiliationController,
                  decoration: const InputDecoration(
                    hintText: 'Enter institution affiliation',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Affiliation Number',
                child: TextFormField(
                  controller: _affiliationNumberController,
                  decoration: const InputDecoration(
                    hintText: 'Enter affiliation number',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Affiliation Start Year',
                child: _buildDateField(
                  context: context,
                  value: _affiliationStartYear,
                  onTap: _pickAffiliationStartYear,
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Address 1',
                child: TextFormField(
                  controller: _address1Controller,
                  decoration: const InputDecoration(
                    hintText: 'Enter address line 1',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Address 2',
                child: TextFormField(
                  controller: _address2Controller,
                  decoration: const InputDecoration(
                    hintText: 'Enter address line 2',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Address 3 (Optional)',
                child: TextFormField(
                  controller: _address3Controller,
                  decoration: const InputDecoration(
                    hintText: 'Enter address line 3',
                  ),
                ),
              ),
            ),
            _buildFieldWrapper(
              width: fieldWidth,
              child: _buildLabeledField(
                context: context,
                label: 'Pin Code',
                child: TextFormField(
                  controller: _pinCodeController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    hintText: 'Enter pin code',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldWrapper({required double width, required Widget child}) {
    return SizedBox(
      width: width,
      child: child,
    );
  }

  Widget _buildLabeledField({
    required BuildContext context,
    required String label,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }

  Widget _buildDateField({
    required BuildContext context,
    required DateTime? value,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          hintText: 'Select date',
          suffixIcon: const Icon(Icons.calendar_month_rounded),
        ),
        child: Text(
          value == null ? 'Select date' : _formatDate(value),
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }

  Future<void> _pickInstitutionStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _institutionStartDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => _institutionStartDate = picked);
    }
  }

  Future<void> _pickAffiliationStartYear() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _affiliationStartYear ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Select Affiliation Start Year',
      fieldLabelText: 'Year',
    );
    if (picked != null) {
      setState(() => _affiliationStartYear = DateTime(picked.year));
    }
  }

  String _formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, '0');
    final mm = date.month.toString().padLeft(2, '0');
    final yyyy = date.year.toString();
    return '$dd/$mm/$yyyy';
  }

  String _formatCurrency(double amount) {
    final str = amount.toStringAsFixed(0);
    final pattern = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = str.replaceAllMapped(pattern, (m) => '${m[1]},');
    return '₹$formatted';
  }

  Widget _buildStatCards(BuildContext context, bool isDesktop) {
    final totalPaid = _feeSummary?.totalPaid ?? 0;
    final totalDue = _feeSummary?.totalDue ?? 0;
    final totalPending = _feeSummary?.totalPending ?? 0;
    final pendingCount = _feeSummary?.pendingCount ?? 0;
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
        label: 'Total Fee Amount',
        value: _isLoadingStats ? '...' : _formatCurrency(totalDue),
        change: '',
        isPositive: true,
        icon: Icons.request_quote_rounded,
        color: AppColors.info,
      ),
      StatData(
        label: 'Total Collection Amount',
        value: _isLoadingStats ? '...' : _formatCurrency(totalPaid),
        change: _isLoadingStats ? '' : '$targetPercent% collected',
        isPositive: true,
        icon: Icons.account_balance_wallet_rounded,
        color: AppColors.secondary,
      ),
      StatData(
        label: 'Pending Amount',
        value: _isLoadingStats ? '...' : _formatCurrency(totalPending),
        change: _isLoadingStats
            ? ''
            : (pendingCount > 0 ? '$pendingCount pending records' : 'No pending'),
        isPositive: totalPending <= 0,
        icon: Icons.pending_actions_rounded,
        color: AppColors.warning,
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
