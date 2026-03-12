import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/student_model.dart';
import '../students/students_screen.dart';
import '../fees/fee_collection_screen.dart';
import '../transactions/failed_transactions_screen.dart';
import '../admin/admin_creation_screen.dart';
import '../admin/settings_screen.dart';
import '../notices/notices_screen.dart';
import '../notifications/notification_screen.dart';
import '../fees/fee_demand_screen.dart';
import '../fees/fee_demand_approval_screen.dart';


class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;

  // Global search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _searchLayerLink = LayerLink();
  OverlayEntry? _searchOverlay;
  List<StudentModel> _allStudents = [];
  List<StudentModel> _searchResults = [];


  static const List<_NavItem> _allNavItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.people_alt_rounded, 'Students', accountantHidden: true),
    _NavItem(Icons.request_page_rounded, 'Fee Demand', accountantHidden: true),
    _NavItem(Icons.people_alt_rounded, 'Students'),
    _NavItem(Icons.request_page_rounded, 'Fee Demand'),

    _NavItem(Icons.receipt_long_rounded, 'Transactions'),
    _NavItem(Icons.approval_rounded, 'Fee Demand Approval', accountantOnly: true),
    _NavItem(Icons.admin_panel_settings_rounded, 'User Creation', adminOnly: true),
    _NavItem(Icons.settings_rounded, 'Designation & Role', adminOnly: true),
    _NavItem(Icons.notifications_rounded, 'Notices'),
    _NavItem(Icons.notifications_active_rounded, 'Notifications'),
  ];

  late List<_NavItem> _navItems;

  List<_NavItem> _getNavItems(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isAdmin = auth.currentUser?.urname == 'Admin';
    final isAccountant = auth.currentUser?.desname == 'Accountant';
    if (isAdmin) return _allNavItems.where((item) => !item.accountantOnly).toList();
    return _allNavItems.where((item) {
      if (item.adminOnly) return false;
      if (item.accountantOnly && !isAccountant) return false;
      if (isAccountant && item.accountantHidden) return false;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadStudentsForSearch();
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        // Delay removal so overlay tap events can fire first
        Future.delayed(const Duration(milliseconds: 200), () {
          _removeSearchOverlay();
        });
      }
    });
  }

  Future<void> _loadStudentsForSearch() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    _allStudents = await SupabaseService.getStudents(insId);
  }

  void _onSearchChanged(String query) {
    if (query.trim().isEmpty) {
      _removeSearchOverlay();
      _searchResults = [];
      return;
    }
    final q = query.toLowerCase();
    _searchResults = _allStudents.where((s) =>
      s.stuname.toLowerCase().contains(q) ||
      s.stuadmno.toLowerCase().contains(q)
    ).take(10).toList();
    _showSearchOverlay();
  }

  void _showSearchOverlay() {
    _removeSearchOverlay();
    if (_searchResults.isEmpty) return;
    _searchOverlay = OverlayEntry(builder: (context) => _buildSearchOverlay());
    Overlay.of(context).insert(_searchOverlay!);
  }

  void _removeSearchOverlay() {
    _searchOverlay?.remove();
    _searchOverlay = null;
  }

  StudentModel? _navigateToStudent;

  void _onStudentSelected(StudentModel student) {
    _removeSearchOverlay();
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _navigateToStudent = student;
      _selectedNavIndex = 1; // Students tab
    });
  }


  Widget _buildSearchOverlay() {
    return Positioned(
      width: 350,
      child: CompositedTransformFollower(
        link: _searchLayerLink,
        showWhenUnlinked: false,
        offset: const Offset(0, 48),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            constraints: const BoxConstraints(maxHeight: 400),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final s = _searchResults[index];
                return InkWell(
                  onTap: () => _onStudentSelected(s),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18,
                          backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                          child: s.stuphoto != null && s.stuphoto!.startsWith('http')
                              ? ClipOval(child: Image.network(s.stuphoto!, width: 36, height: 36, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Text(s.stuname[0].toUpperCase(), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14))))
                              : Text(s.stuname[0].toUpperCase(), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.stuname, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              Text('${s.stuadmno}  •  Class ${s.stuclass}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Text(s.stumobile, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeSearchOverlay();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _navItems = _getNavItems(context);
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;
    final isTablet = size.width > 500 && size.width <= 800;

    // Clamp selected index if nav items changed (e.g. role-based filtering)
    if (_selectedNavIndex >= _navItems.length) {
      _selectedNavIndex = 0;
    }

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
          if (!isDesktop && MediaQuery.of(context).size.width <= 500)
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
            CompositedTransformTarget(
              link: _searchLayerLink,
              child: Container(
                width: 350,
                height: 42,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.border),
                ),
                child: TextField(
                  controller: _searchController,
                  focusNode: _searchFocusNode,
                  onChanged: _onSearchChanged,
                  decoration: InputDecoration(
                    hintText: 'Search by name or admission no...',
                    hintStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppColors.textLight,
                          fontSize: 13,
                        ),
                    prefixIcon: const Icon(Icons.search_rounded,
                        size: 20, color: AppColors.textLight),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                            onPressed: () {
                              _searchController.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 0, vertical: 10),
                  ),
                ),
              ),
            ),

          const SizedBox(width: 16),

          // Notification bell
          Stack(
            children: [
              IconButton(
                onPressed: () => setState(() => _selectedNavIndex = _navItems.indexWhere((i) => i.label == 'Notifications')),
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
                  onSelected: (value) async {
                    if (value == 'signout') {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, AppRoutes.welcome);
                      }
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
    return label == 'Dashboard' || label == 'Students' || label == 'Fee Demand' || label == 'Fee Demand Approval' || label == 'Transactions' || label == 'User Creation' || label == 'Designation & Role' || label == 'Notices' || label == 'Notifications';
  }

  Widget _buildDashboardContent(BuildContext context, bool isDesktop) {
    final selectedMenu = _navItems[_selectedNavIndex].label;
    if (selectedMenu == 'Students') {
      final student = _navigateToStudent;
      _navigateToStudent = null;
      return StudentsScreen(key: student != null ? ValueKey(student.stuId) : null, initialStudent: student);
    }
    if (selectedMenu == 'Fee Demand') {
      return const FeeDemandScreen();
    }
    if (selectedMenu == 'Transactions') {
      return const FailedTransactionsScreen();
    }
    if (selectedMenu == 'Fee Demand Approval') {
      return const FeeDemandApprovalScreen();
    }
    if (selectedMenu == 'User Creation') {
      return const AdminCreationScreen();
    }
    if (selectedMenu == 'Designation & Role') {
      return const SettingsScreen();
    }
    if (selectedMenu == 'Notices') {
      return const NoticesScreen();
    }
    if (selectedMenu == 'Notifications') {
      return const NotificationScreen();
    }
    // Dashboard shows Fee Collection screen
    return const FeeCollectionScreen();
  }

}

class _NavItem {
  final IconData icon;
  final String label;
  final bool adminOnly;
  final bool accountantHidden;
  final bool accountantOnly;
  const _NavItem(this.icon, this.label, {this.adminOnly = false, this.accountantHidden = false, this.accountantOnly = false});
}

