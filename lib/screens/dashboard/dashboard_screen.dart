import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/student_model.dart';
import '../students/students_screen.dart';
import '../fees/fee_collection_screen.dart';
import '../fees/student_fee_collection_screen.dart';
import '../fees/student_ledger_screen.dart';
import '../transactions/failed_transactions_screen.dart';
import '../admin/admin_creation_screen.dart';
import '../notices/notices_screen.dart';
import '../notifications/notification_screen.dart';
import '../fees/fee_demand_screen.dart';
import '../fees/fee_demand_approval_screen.dart';
import '../admin/master_import_screen.dart';
import '../admin/settings_screen.dart';
import '../fees/bank_reconciliation_screen.dart';



class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;

  // Notification unread count
  int _unreadNotifCount = 0;
  String _academicYear = '';
  List<Map<String, dynamic>> _availableYears = [];

  // Global search
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final LayerLink _searchLayerLink = LayerLink();
  OverlayEntry? _searchOverlay;
  List<StudentModel> _allStudents = [];
  List<StudentModel> _searchResults = [];


  static const List<_NavItem> _allNavItems = [
    _NavItem(Icons.dashboard_rounded, 'Dashboard'),
    _NavItem(Icons.people_alt_rounded, 'Students', adminOnly: true),
    _NavItem(Icons.request_page_rounded, 'Fee Demand', accountantOnly: true),
    _NavItem(Icons.payments_rounded, 'Fee Collection', accountantOnly: true),
    _NavItem(Icons.menu_book_rounded, 'Student Ledger'),
    _NavItem(Icons.receipt_long_rounded, 'Transactions'),
    _NavItem(Icons.approval_rounded, 'Fee Demand Approval', adminOnly: true),
    _NavItem(Icons.admin_panel_settings_rounded, 'User Creation', adminOnly: true),
    _NavItem(Icons.upload_rounded, 'Master Data', adminOnly: true),
    _NavItem(Icons.settings_rounded, 'Sequence Creation', adminOnly: true),
    _NavItem(Icons.account_balance_rounded, 'Bank Reconciliation', accountantOnly: true),
    _NavItem(Icons.notifications_rounded, 'Notices'),
    _NavItem(Icons.notifications_active_rounded, 'Notifications'),
  ];

  late List<_NavItem> _navItems;

  List<_NavItem> _getNavItems(BuildContext context) {
    final auth = context.read<AuthProvider>();
    final isAdmin = auth.currentUser?.urname == 'Admin';
    final isAccountant = auth.currentUser?.urname == 'Accountant';
    if (isAdmin) return _allNavItems.where((item) => !item.accountantOnly).toList();
    return _allNavItems.where((item) {
      if (item.adminOnly) return false;
      if (item.accountantOnly && !isAccountant) return false;
      if (item.hideForAccountant && isAccountant) return false;
      return true;
    }).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadUnreadNotifCount();
    _loadAcademicYear();
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) {
        // Delay removal so overlay tap events can fire first
        Future.delayed(const Duration(milliseconds: 200), () {
          _removeSearchOverlay();
        });
      }
    });
  }

  Future<void> _loadAcademicYear() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      // Load from institutionyear (public) - all years for this institution
      final result = await SupabaseService.client
          .from('institutionyear')
          .select('yrlabel, iyrstadate, iyrenddate, activestatus')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('iyr_id', ascending: false);
      final years = List<Map<String, dynamic>>.from(result);
      if (years.isNotEmpty && mounted) {
        // Detect current year from active schema
        String currentYear = years.first['yrlabel']?.toString() ?? '';
        final schema = SupabaseService.currentSchema ?? '';
        for (final y in years) {
          final label = y['yrlabel']?.toString() ?? '';
          if (schema.endsWith(label.replaceAll('-', ''))) {
            currentYear = label;
            break;
          }
        }
        setState(() {
          _availableYears = years;
          _academicYear = currentYear;
        });
      }
    } catch (_) {}
  }

  Future<void> _switchYear(String yearLabel) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    // Get institution short name
    final insRow = await SupabaseService.client
        .from('institution')
        .select('inshortname')
        .eq('ins_id', insId)
        .maybeSingle();
    if (insRow == null || insRow['inshortname'] == null) return;

    final shortName = (insRow['inshortname'] as String).toLowerCase();
    final newSchema = '$shortName${yearLabel.replaceAll('-', '')}';

    // Set new schema
    SupabaseService.setSchema(newSchema);
    setState(() => _academicYear = yearLabel);

    // Reload all data
    _loadStudentsForSearch();
    _loadUnreadNotifCount();
    // Reset to dashboard tab to refresh
    setState(() => _selectedNavIndex = 0);
  }

  void _showCreateYearDialog() {
    // Auto-calculate next year from current
    final currentParts = _academicYear.split('-');
    final nextStart = currentParts.length == 2 ? int.tryParse(currentParts[1]) ?? (DateTime.now().year + 1) : DateTime.now().year + 1;
    final nextEnd = nextStart + 1;
    final nextLabel = '$nextStart-$nextEnd';

    final startDateCtrl = TextEditingController(text: '$nextStart-06-01');
    final endDateCtrl = TextEditingController(text: '$nextEnd-05-31');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
        title: Text('Create New Academic Year', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16.sp)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New Year: $nextLabel', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
            SizedBox(height: 16.h),
            TextField(
              controller: startDateCtrl,
              decoration: InputDecoration(
                labelText: 'Start Date (YYYY-MM-DD)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                isDense: true,
              ),
            ),
            SizedBox(height: 12.h),
            TextField(
              controller: endDateCtrl,
              decoration: InputDecoration(
                labelText: 'End Date (YYYY-MM-DD)',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                isDense: true,
              ),
            ),
            SizedBox(height: 8.h),
            Text('This will create a new empty schema with all tables.', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _createNewYear(nextLabel, startDateCtrl.text.trim(), endDateCtrl.text.trim());
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  Future<void> _createNewYear(String yearLabel, String startDate, String endDate) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    try {
      // Get institution short name
      final insRow = await SupabaseService.client
          .from('institution')
          .select('inshortname')
          .eq('ins_id', insId)
          .maybeSingle();
      if (insRow == null || insRow['inshortname'] == null) return;

      final shortName = (insRow['inshortname'] as String).toLowerCase();
      final schemaName = '$shortName${yearLabel.replaceAll('-', '')}';

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Creating schema $schemaName...'), backgroundColor: AppColors.accent),
        );
      }

      await SupabaseService.client.rpc('create_institution_schema', params: {
        'p_schema_name': schemaName,
        'p_ins_id': insId,
        'p_year_label': yearLabel,
        'p_start_date': startDate,
        'p_end_date': endDate,
      });

      // Reload years and switch
      await _loadAcademicYear();
      await _switchYear(yearLabel);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Academic year $yearLabel created successfully!'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  bool _studentsLoaded = false;
  Future<void> _loadStudentsForSearch() async {
    if (_studentsLoaded) return;
    _studentsLoaded = true;
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) { _studentsLoaded = false; return; }
    _allStudents = await SupabaseService.getStudents(insId);
  }

  Future<void> _loadUnreadNotifCount() async {
    try {
      final auth = context.read<AuthProvider>();
      final insId = auth.insId;
      if (insId == null) return;
      final rows = await SupabaseService.fromSchema('notification')
          .select('isread')
          .eq('ins_id', insId)
          .eq('activestatus', 1);
      final unread = (rows as List).where((n) => n['isread'] != true && n['isread'] != 1).length;
      if (mounted) setState(() => _unreadNotifCount = unread);
    } catch (_) {}
  }

  void _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      _removeSearchOverlay();
      _searchResults = [];
      return;
    }
    // Lazy load students on first search
    if (!_studentsLoaded) await _loadStudentsForSearch();
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
      width: 350.w,
      child: CompositedTransformFollower(
        link: _searchLayerLink,
        showWhenUnlinked: false,
        offset: Offset(0, 48.h),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12.r),
          child: Container(
            constraints: BoxConstraints(maxHeight: 400.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.border),
            ),
            child: ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 4.h),
              shrinkWrap: true,
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final s = _searchResults[index];
                return InkWell(
                  onTap: () => _onStudentSelected(s),
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 18.r,
                          backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                          child: s.stuphoto != null && s.stuphoto!.startsWith('http')
                              ? ClipOval(child: Image.network(s.stuphoto!, width: 36.w, height: 36.h, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Text(s.stuname[0].toUpperCase(), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14.sp))))
                              : Text(s.stuname[0].toUpperCase(), style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14.sp)),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(s.stuname, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                              Text('${s.stuadmno}  •  Class ${s.stuclass}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                        Text(s.stumobile, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
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
              width: _sidebarCollapsed ? 78 : (isDesktop ? (size.width < 1100 ? 170 : size.width < 1400 ? 200 : 240) : 78),
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
                          padding: EdgeInsets.all(isDesktop ? (size.width < 1100 ? 12 : size.width < 1400 ? 16 : 28) : 16),
                          child: _buildDashboardContent(context, isDesktop),
                        )
                      : SingleChildScrollView(
                          padding: EdgeInsets.all(isDesktop ? (size.width < 1100 ? 12 : size.width < 1400 ? 16 : 28) : 16),
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
      color: AppColors.surfaceSidebar,
      child: Column(
        children: [
          // Logo area
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 16.w : (MediaQuery.of(context).size.width < 1100 ? 14.w : 24.w),
              vertical: 24.h,
            ),
            child: Row(
              children: [
                Container(
                  width: 42.w,
                  height: 42.h,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12.r),
                  ),
                  child: Icon(
                    Icons.school_rounded,
                    color: AppColors.primary,
                    size: 22.sp,
                  ),
                ),
                if (!collapsed) ...[
                  SizedBox(width: 14.w),
                  Text(
                    'EduDesk',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ],
            ),
          ),

          SizedBox(height: 8.h),

          // Nav items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 12.w : (MediaQuery.of(context).size.width < 1100 ? 10.w : 16.w)),
              itemCount: _navItems.length,
              itemBuilder: (context, index) {
                final item = _navItems[index];
                final isSelected = _selectedNavIndex == index;

                return Padding(
                  padding: EdgeInsets.only(bottom: 4.h),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        setState(() => _selectedNavIndex = index);
                        _loadUnreadNotifCount();
                      },
                      borderRadius: BorderRadius.circular(12.r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        clipBehavior: Clip.hardEdge,
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 12.w : (MediaQuery.of(context).size.width < 1100 ? 10.w : 16.w),
                          vertical: 12.h,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.primary.withValues(alpha: 0.12)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              item.icon,
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.textSecondary,
                              size: MediaQuery.of(context).size.width <= 1366 ? 18.sp : 22.sp,
                            ),
                            if (!collapsed) ...[
                              SizedBox(width: 14.w),
                              Flexible(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: isSelected
                                            ? AppColors.primary
                                            : AppColors.textSecondary,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
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

          SizedBox(height: 16.h),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDesktop) {
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? (MediaQuery.of(context).size.width < 1100 ? 12 : MediaQuery.of(context).size.width < 1400 ? 16 : 28) : 16,
        vertical: 12,
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
                  borderRadius: BorderRadius.circular(10.r),
                ),
              ),
            ),
          SizedBox(width: 16.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _navItems[_selectedNavIndex].label,
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              if (_academicYear.isNotEmpty)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_today_rounded, size: 14.sp, color: AppColors.accent),
                    SizedBox(width: 6.w),
                    Text(
                      'Academic Year $_academicYear',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 13.sp, color: AppColors.accent, fontWeight: FontWeight.w600,
                          ),
                    ),
                  ],
                ),
            ],
          ),

          // School logo, name and address (center)
          if (isDesktop)
            Expanded(
              child: Center(
                child: (auth.insLogo != null || auth.insName != null)
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (auth.insLogo != null)
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8.r),
                            child: Image.network(
                              auth.insLogo!,
                              width: 44.w,
                              height: 44.h,
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(Icons.school_rounded, size: 36.sp, color: AppColors.accent),
                            ),
                          )
                        else
                          Icon(Icons.school_rounded, size: 36.sp, color: AppColors.accent),
                        SizedBox(width: 10.w),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (auth.insName != null)
                              Text(
                                auth.insName!,
                                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                              ),
                            if (auth.insAddress != null)
                              Text(
                                auth.insAddress!,
                                style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                          ],
                        ),
                      ],
                    )
                  : const SizedBox.shrink(),
              ),
            ),

          SizedBox(width: 16.w),

          // Notification bell
          Stack(
            children: [
              IconButton(
                onPressed: () {
                  setState(() => _selectedNavIndex = _navItems.indexWhere((i) => i.label == 'Notifications'));
                  _loadUnreadNotifCount();
                },
                icon: Icon(Icons.notifications_outlined, size: 22.sp),
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                ),
              ),
              if (_unreadNotifCount > 0)
                Positioned(
                  right: 8.w,
                  top: 8.h,
                  child: Container(
                    width: 8.w,
                    height: 8.h,
                    decoration: const BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(width: 12.w),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircleAvatar(
                  radius: 17.r,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.2),
                  child: Text(
                    (auth.userName ?? 'U')[0].toUpperCase(),
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                SizedBox(width: 10.w),
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
                  offset: Offset(0, 8.h),
                  color: Colors.white,
                  elevation: 10,
                  surfaceTintColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12.r),
                    side: BorderSide(color: AppColors.border),
                  ),
                  menuPadding: EdgeInsets.symmetric(vertical: 6.h),
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
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      value: 'signout',
                      child: Row(
                        children: [
                          Icon(Icons.logout_rounded, size: 18.sp),
                          SizedBox(width: 8.w),
                          const Text('Sign out'),
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
    return label == 'Dashboard' || label == 'Students' || label == 'Fee Demand' || label == 'Fee Collection' || label == 'Student Ledger' || label == 'Fee Demand Approval' || label == 'Transactions' || label == 'User Creation' || label == 'Notices' || label == 'Notifications' || label == 'Master Data' || label == 'Sequence Creation' || label == 'Bank Reconciliation';
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
    if (selectedMenu == 'Fee Collection') {
      return StudentFeeCollectionScreen(
        onNavigateToTransactions: () {
          final idx = _navItems.indexWhere((i) => i.label == 'Transactions');
          if (idx >= 0) setState(() => _selectedNavIndex = idx);
        },
      );
    }
    if (selectedMenu == 'Student Ledger') {
      return const StudentLedgerScreen();
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
    if (selectedMenu == 'Notices') {
      return const NoticesScreen();
    }
    if (selectedMenu == 'Notifications') {
      return NotificationScreen(onReadChanged: _loadUnreadNotifCount);
    }
    if (selectedMenu == 'Master Data') {
      return const MasterImportScreen();
    }
    if (selectedMenu == 'Sequence Creation') {
      return const SettingsScreen();
    }
    if (selectedMenu == 'Bank Reconciliation') {
      return const BankReconciliationScreen();
    }
    // Dashboard shows Fee Collection screen
    return const FeeCollectionScreen();
  }

}

class _NavItem {
  final IconData icon;
  final String label;
  final bool adminOnly;
  final bool accountantOnly;
  final bool hideForAccountant;
  const _NavItem(this.icon, this.label, {this.adminOnly = false, this.accountantOnly = false, this.hideForAccountant = false});
}

