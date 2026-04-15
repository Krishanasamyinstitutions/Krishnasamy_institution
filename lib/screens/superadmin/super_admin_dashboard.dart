import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../models/fee_model.dart';
import '../../models/payment_model.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../auth/register_screen.dart';

class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;

  static const List<_SANavItem> _navItems = [
    _SANavItem(Icons.dashboard_rounded, 'Dashboard'),
    _SANavItem(Icons.domain_add_rounded, 'Register Institution'),
    _SANavItem(Icons.business_rounded, 'Manage Institutions'),
  ];

  List<Map<String, dynamic>> _institutions = [];
  bool _loadingInstitutions = true;
  bool _loadingFinanceData = true;
  List<_InstitutionFinanceSummary> _institutionSummaries = [];
  List<_SuperAdminTransactionRow> _recentTransactions = [];

  @override
  void initState() {
    super.initState();
    _loadInstitutions();
  }

  void _refreshDashboard() {
    setState(() {
      _loadingInstitutions = true;
      _loadingFinanceData = true;
    });
    _loadInstitutions();
  }

  Future<void> _loadTodayCollections(
      List<_InstitutionFinanceSummary> summaries) async {
    final now = DateTime.now();
    final todayStr =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await Future.wait(summaries.map((s) async {
      try {
        final insRow = await SupabaseService.client
            .from('institution')
            .select('inshortname')
            .eq('ins_id', s.insId)
            .maybeSingle();
        final shortName = (insRow?['inshortname'] as String?)?.toLowerCase();
        if (shortName == null) return;

        final yearRows = await SupabaseService.client
            .from('institutionyear')
            .select('yrlabel, iyrstadate, iyrenddate')
            .eq('ins_id', s.insId)
            .eq('activestatus', 1)
            .order('iyr_id', ascending: false);
        final years = List<Map<String, dynamic>>.from(yearRows as List);
        if (years.isEmpty) return;

        String? yearLabel;
        for (final y in years) {
          final start = DateTime.tryParse(y['iyrstadate']?.toString() ?? '');
          final end = DateTime.tryParse(y['iyrenddate']?.toString() ?? '');
          if (start != null &&
              end != null &&
              !now.isBefore(start) &&
              !now.isAfter(end)) {
            yearLabel = y['yrlabel']?.toString();
            break;
          }
        }
        yearLabel ??= years.first['yrlabel']?.toString();
        if (yearLabel == null) return;

        final schema = '$shortName${yearLabel.replaceAll('-', '')}';
        final rows = await SupabaseService.client
            .schema(schema)
            .from('payment')
            .select('transtotalamount')
            .eq('paydate', todayStr)
            .eq('paystatus', 'C')
            .eq('activestatus', 1);
        final total = (rows as List).fold<double>(
            0,
            (sum, r) =>
                sum + ((r['transtotalamount'] as num?)?.toDouble() ?? 0));
        s.todayCollected = total;
      } catch (e) {
        debugPrint('today collection error for ${s.insName}: $e');
      }
    }));
    if (mounted) setState(() {});
  }

  Future<void> _loadInstitutions() async {
    try {
      // Single RPC call for all institution data with finance summary
      debugPrint('[SuperAdmin] Calling get_super_admin_dashboard RPC...');
      final rpcResult =
          await SupabaseService.client.rpc('get_super_admin_dashboard');
      debugPrint(
          '[SuperAdmin] RPC raw result type=${rpcResult.runtimeType} value=$rpcResult');
      // Supabase returns json RPC results sometimes as List, sometimes as a
      // JSON-encoded String — handle both safely.
      List rawList;
      if (rpcResult == null) {
        rawList = const [];
      } else if (rpcResult is List) {
        rawList = rpcResult;
      } else if (rpcResult is String) {
        final decoded = rpcResult.isEmpty ? null : jsonDecode(rpcResult);
        rawList = decoded is List ? decoded : const [];
      } else {
        rawList = const [];
      }
      final dashboardData =
          rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final institutions = <Map<String, dynamic>>[];
      final summaries = <_InstitutionFinanceSummary>[];

      for (final row in dashboardData) {
        institutions.add(row);
        summaries.add(
          _InstitutionFinanceSummary(
            insId: row['ins_id'] as int? ?? 0,
            insName: row['insname']?.toString() ?? 'Institution',
            insCode: row['inscode']?.toString() ?? '',
            insLogo: row['inslogo']?.toString(),
            totalDemand: (row['total_demand'] as num?)?.toDouble() ?? 0,
            totalCollected: (row['total_collected'] as num?)?.toDouble() ?? 0,
            totalPending: (row['total_pending'] as num?)?.toDouble() ?? 0,
            transactionCount: (row['transaction_count'] as num?)?.toInt() ?? 0,
            activeStatus: row['activestatus'] == 1,
          ),
        );
      }

      if (mounted) {
        setState(() {
          _institutions = institutions;
          _institutionSummaries = summaries;
          _loadingInstitutions = false;
          _loadingFinanceData = false;
        });
      }

      _loadTodayCollections(summaries);
    } catch (e, st) {
      debugPrint('[SuperAdmin] RPC FAILED: $e');
      debugPrint('[SuperAdmin] Stack: $st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dashboard RPC failed: $e',
                style: const TextStyle(fontSize: 12)),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 10),
          ),
        );
      }
      // Fallback: load institutions without finance data
      try {
        final result = await SupabaseService.client
            .from('institution')
            .select(
                'ins_id, insname, inscode, inshortname, inslogo, insmail, insmobno, inscity, insstate, activestatus')
            .order('ins_id');
        final insList = List<Map<String, dynamic>>.from(result);
        final fallbackSummaries = insList
            .map((row) => _InstitutionFinanceSummary(
                  insId: row['ins_id'] as int? ?? 0,
                  insName: row['insname']?.toString() ?? 'Institution',
                  insCode: row['inscode']?.toString() ?? '',
                  insLogo: row['inslogo']?.toString(),
                  totalDemand: 0,
                  totalCollected: 0,
                  totalPending: 0,
                  transactionCount: 0,
                  activeStatus: row['activestatus'] == 1,
                ))
            .toList();
        if (mounted) {
          setState(() {
            _institutions = insList;
            _institutionSummaries = fallbackSummaries;
            _loadingInstitutions = false;
            _loadingFinanceData = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _loadingInstitutions = false;
            _loadingFinanceData = false;
          });
        }
      }
    }
  }

  Future<String> _fetchLatestYearLabel(int insId) async {
    try {
      final result = await SupabaseService.client
          .from('institutionyear')
          .select('yrlabel')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('iyr_id', ascending: false)
          .limit(1)
          .maybeSingle();

      final yrLabel = result?['yrlabel']?.toString();
      if (yrLabel != null && yrLabel.isNotEmpty) {
        return yrLabel;
      }
    } catch (e) {
      debugPrint('Error fetching latest year for institution $insId: $e');
    }

    final year = DateTime.now().year;
    return '$year-${year + 1}';
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      backgroundColor: AppColors.surface,
      drawer: !isDesktop ? Drawer(child: _buildSidebar(context, false)) : null,
      body: Row(
        children: [
          if (isDesktop)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: _sidebarCollapsed ? 78 : 240,
              child: _buildSidebar(context, _sidebarCollapsed),
            ),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(context, isDesktop),
                Expanded(child: _buildContent(context)),
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
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 16.w : 24.w,
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
                    Icons.admin_panel_settings_rounded,
                    color: AppColors.primary,
                    size: 22.sp,
                  ),
                ),
                if (!collapsed) ...[
                  SizedBox(width: 14.w),
                  Text(
                    'Super Admin',
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
          Expanded(
            child: ListView.builder(
              padding:
                  EdgeInsets.symmetric(horizontal: collapsed ? 12.w : 16.w),
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
                        final prevIndex = _selectedNavIndex;
                        setState(() => _selectedNavIndex = index);
                        if (index == 0 && prevIndex != 0) {
                          _refreshDashboard();
                        }
                      },
                      borderRadius: BorderRadius.circular(12.r),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(
                          horizontal: collapsed ? 12.w : 16.w,
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
                              size: 20.sp,
                            ),
                            if (!collapsed) ...[
                              SizedBox(width: 14.w),
                              Flexible(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
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
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, bool isDesktop) {
    final auth = context.watch<AuthProvider>();
    return Container(
      padding:
          EdgeInsets.symmetric(horizontal: isDesktop ? 28 : 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          if (!isDesktop)
            IconButton(
              onPressed: () => Scaffold.of(context).openDrawer(),
              icon: const Icon(Icons.menu_rounded),
            ),
          if (isDesktop)
            IconButton(
              onPressed: () =>
                  setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              icon: Icon(_sidebarCollapsed
                  ? Icons.menu_open_rounded
                  : Icons.menu_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.r)),
              ),
            ),
          SizedBox(width: 16.w),
          Text(
            _navItems[_selectedNavIndex].label,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
            decoration: BoxDecoration(
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
                    (auth.userName ?? 'S')[0].toUpperCase(),
                    style: const TextStyle(
                        color: AppColors.accent, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: 10.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(auth.userName ?? 'Super Admin',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Super Admin',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  position: PopupMenuPosition.under,
                  offset: Offset(0, 8.h),
                  color: Colors.white,
                  elevation: 10,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded,
                      color: AppColors.textSecondary),
                  onSelected: (value) async {
                    if (value == 'signout') {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(
                            context, AppRoutes.welcome);
                      }
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
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

  Widget _buildContent(BuildContext context) {
    switch (_selectedNavIndex) {
      case 1:
        return RegisterScreen(onRegistered: _refreshDashboard);
      case 2:
        return _buildManageInstitutions(context);
      default:
        return _buildDashboardHome(context);
    }
  }

  Widget _buildDashboardHome(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_loadingFinanceData)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_institutionSummaries.isEmpty)
            Expanded(
                child: Center(
                    child: Text('No institutions found',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 14.sp))))
          else ...[
            _buildSummaryRow(),
            SizedBox(height: 12.h),
            Expanded(
              child: ListView.separated(
                itemCount: _institutionSummaries.length,
                separatorBuilder: (_, __) => SizedBox(height: 12.h),
                itemBuilder: (context, index) {
                  final s = _institutionSummaries[index];
                  return _buildInstitutionCard(context, s);
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final activeCount =
        _institutionSummaries.where((s) => s.activeStatus).length;
    final totalDemand =
        _institutionSummaries.fold<double>(0, (sum, s) => sum + s.totalDemand);
    final totalCollection = _institutionSummaries.fold<double>(
        0, (sum, s) => sum + s.todayCollected);
    final totalPending =
        _institutionSummaries.fold<double>(0, (sum, s) => sum + s.totalPending);

    const demandColor = Color(0xFF5C6BC0);
    const collectionColor = Color(0xFF43A047);
    const pendingColor = Color(0xFFEF5350);

    return Row(
      children: [
        SizedBox(
          width: 132.w,
          child: _buildSummaryTile(
              'Active Institutes', activeCount.toString(), demandColor),
        ),
        SizedBox(width: 12.w),
        Expanded(
            child: _buildSummaryTile(
                'Total Demand', _formatAmount(totalDemand), demandColor)),
        SizedBox(width: 12.w),
        Expanded(
            child: _buildSummaryTile('Total Collection',
                _formatAmount(totalCollection), collectionColor)),
        SizedBox(width: 12.w),
        Expanded(
            child: _buildSummaryTile(
                'Total Pending', _formatAmount(totalPending), pendingColor)),
      ],
    );
  }

  Widget _buildSummaryTile(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Text(value,
              style: TextStyle(
                  fontSize: 18.sp, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},')}';
    }
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');
    return '₹$intPart.${parts[1]}';
  }

  Widget _buildInstitutionCard(
      BuildContext context, _InstitutionFinanceSummary s) {
    const demandColor = Color(0xFF5C6BC0);
    const collectionColor = Color(0xFF43A047);
    const pendingColor = Color(0xFFEF5350);

    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42.w,
                height: 42.h,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Center(
                    child: Text(s.insCode.isNotEmpty ? s.insCode[0] : 'I',
                        style: TextStyle(
                            fontSize: 18.sp,
                            fontWeight: FontWeight.w800,
                            color: AppColors.primary))),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.insName,
                        style: TextStyle(
                            fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2.h),
                    Text(s.insCode,
                        style: TextStyle(
                            fontSize: 12.sp, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: s.activeStatus
                      ? collectionColor.withValues(alpha: 0.1)
                      : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  s.activeStatus ? 'Active' : 'Inactive',
                  style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                      color: s.activeStatus ? collectionColor : Colors.grey),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Row(
            children: [
              Container(
                width: 120.w,
                height: 120.h,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.border),
                  color: Colors.white,
                ),
                child: s.insLogo != null && s.insLogo!.isNotEmpty
                    ? ClipRRect(
                        borderRadius: BorderRadius.circular(9.r),
                        child: Image.network(
                          s.insLogo!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) => Center(
                            child: Text(s.insName[0],
                                style: TextStyle(
                                    fontSize: 22.sp,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.primary)),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(s.insName[0],
                            style: TextStyle(
                                fontSize: 22.sp,
                                fontWeight: FontWeight.w800,
                                color: AppColors.primary)),
                      ),
              ),
              SizedBox(width: 12.w),
              _buildFinanceTile('Total Demand', s.totalDemand, demandColor,
                  onTap: () => _showCourseWiseDemand(context, s)),
              SizedBox(width: 12.w),
              _buildFinanceTile(
                  'Total Collection / Today', s.todayCollected, collectionColor,
                  onTap: () => _showCourseWiseCollection(context, s)),
              SizedBox(width: 12.w),
              _buildFinanceTile('Total Pending', s.totalPending, pendingColor,
                  onTap: () => _showCourseWisePending(context, s)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFinanceTile(String label, double amount, Color color,
      {VoidCallback? onTap}) {
    final tile = Container(
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Text(label,
              style: TextStyle(
                  fontSize: 11.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Text(_formatAmount(amount),
              style: TextStyle(
                  fontSize: 18.sp, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
    return Expanded(
      child: onTap != null
          ? GestureDetector(
              behavior: HitTestBehavior.opaque, onTap: onTap, child: tile)
          : tile,
    );
  }

  void _showCourseWiseCollection(
      BuildContext context, _InstitutionFinanceSummary s) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              _CourseWiseCollectionPage(summary: s, mode: 'collection')),
    );
  }

  void _showCourseWisePending(
      BuildContext context, _InstitutionFinanceSummary s) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              _CourseWiseCollectionPage(summary: s, mode: 'pending')),
    );
  }

  void _showCourseWiseDemand(
      BuildContext context, _InstitutionFinanceSummary s) {
    Navigator.of(context).push(
      MaterialPageRoute(
          builder: (_) =>
              _CourseWiseCollectionPage(summary: s, mode: 'demand')),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value,
      IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 48.w,
              height: 48.h,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(icon, color: color, size: 24.sp),
            ),
            SizedBox(width: 16.w),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInstitutionFinanceSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'All Colleges Fee Overview',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  'View Only',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          if (_loadingFinanceData)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_institutionSummaries.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Text(
                'No fee collection data available yet.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                    AppColors.primary.withValues(alpha: 0.08)),
                columns: const [
                  DataColumn(label: Text('COLLEGE')),
                  DataColumn(label: Text('CODE')),
                  DataColumn(label: Text('FEE COLLECTION')),
                  DataColumn(label: Text('PENDING FEES')),
                  DataColumn(label: Text('TRANSACTIONS')),
                  DataColumn(label: Text('STATUS')),
                ],
                rows: _institutionSummaries.map((item) {
                  return DataRow(
                    cells: [
                      DataCell(Text(item.insName)),
                      DataCell(Text(item.insCode)),
                      DataCell(Text(_formatCurrency(item.totalCollected))),
                      DataCell(Text(_formatCurrency(item.totalPending))),
                      DataCell(Text('${item.transactionCount}')),
                      DataCell(
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: item.activeStatus
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20.r),
                          ),
                          child: Text(
                            item.activeStatus ? 'Active' : 'Inactive',
                            style: TextStyle(
                              color: item.activeStatus
                                  ? AppColors.success
                                  : AppColors.error,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactionsSection(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Transactions Across Colleges',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          SizedBox(height: 16.h),
          if (_loadingFinanceData)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_recentTransactions.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: 12.h),
              child: Text(
                'No transactions found.',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(
                    AppColors.primary.withValues(alpha: 0.08)),
                columns: const [
                  DataColumn(label: Text('COLLEGE')),
                  DataColumn(label: Text('PAY NO')),
                  DataColumn(label: Text('AMOUNT')),
                  DataColumn(label: Text('METHOD')),
                  DataColumn(label: Text('REFERENCE')),
                  DataColumn(label: Text('DATE')),
                  DataColumn(label: Text('STATUS')),
                ],
                rows: _recentTransactions.map((row) {
                  final payment = row.payment;
                  final date = payment.paydate ?? payment.createdat;
                  final isPaid = payment.paystatus == 'C';
                  final statusColor =
                      isPaid ? AppColors.success : AppColors.error;
                  final statusText = isPaid ? 'Paid' : payment.statusText;

                  return DataRow(
                    cells: [
                      DataCell(Text(row.institutionName)),
                      DataCell(Text(payment.paynumber ?? '${payment.payId}')),
                      DataCell(Text(_formatCurrency(payment.transtotalamount))),
                      DataCell(Text(payment.paymethod ?? '-')),
                      DataCell(
                        SizedBox(
                          width: 160.w,
                          child: Text(
                            payment.payreference ?? '-',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text(_formatDate(date))),
                      DataCell(
                        Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20.r),
                          ),
                          child: Text(
                            statusText,
                            style: TextStyle(
                              color: statusColor,
                              fontSize: 12.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  String _formatCurrency(double value) {
    final fixed = value.toStringAsFixed(2);
    final parts = fixed.split('.');
    final whole = parts[0].replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (match) => ',',
    );
    return 'Rs. $whole.${parts[1]}';
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildManageInstitutions(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(28.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('All Institutions',
                  style: Theme.of(context).textTheme.headlineSmall),
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedNavIndex = 1),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Register New'),
                style:
                    ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
              ),
            ],
          ),
          SizedBox(height: 16.h),
          Expanded(
            child: _loadingInstitutions
                ? const Center(child: CircularProgressIndicator())
                : _institutions.isEmpty
                    ? const Center(child: Text('No institutions found'))
                    : ListView.builder(
                        itemCount: _institutions.length,
                        itemBuilder: (context, index) {
                          final ins = _institutions[index];
                          return Card(
                            margin: EdgeInsets.only(bottom: 10.h),
                            child: Padding(
                              padding: EdgeInsets.symmetric(
                                  horizontal: 16.w, vertical: 14.h),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22.r,
                                    backgroundColor: AppColors.primary
                                        .withValues(alpha: 0.1),
                                    child: Text(
                                      (ins['insname'] as String? ?? 'I')[0]
                                          .toUpperCase(),
                                      style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w700,
                                          fontSize: 16.sp),
                                    ),
                                  ),
                                  SizedBox(width: 14.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ins['insname'] ?? '',
                                          style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 15.sp,
                                              color: AppColors.textPrimary),
                                        ),
                                        SizedBox(height: 6.h),
                                        Text(
                                          'Code: ${ins['inscode'] ?? ''}',
                                          style: TextStyle(
                                              fontSize: 13.sp,
                                              color: AppColors.textSecondary),
                                        ),
                                        SizedBox(height: 2.h),
                                        Text(
                                          '${ins['insmail'] ?? ''}',
                                          style: TextStyle(
                                              fontSize: 13.sp,
                                              color: AppColors.textSecondary),
                                        ),
                                        if ((ins['inscity'] ?? '')
                                                .toString()
                                                .isNotEmpty ||
                                            (ins['insstate'] ?? '')
                                                .toString()
                                                .isNotEmpty) ...[
                                          SizedBox(height: 2.h),
                                          Text(
                                            '${ins['inscity'] ?? ''}${(ins['inscity'] ?? '').toString().isNotEmpty && (ins['insstate'] ?? '').toString().isNotEmpty ? ', ' : ''}${ins['insstate'] ?? ''}',
                                            style: TextStyle(
                                                fontSize: 13.sp,
                                                color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(
                                        horizontal: 12.w, vertical: 6.h),
                                    decoration: BoxDecoration(
                                      color: ins['activestatus'] == 1
                                          ? AppColors.success
                                              .withValues(alpha: 0.1)
                                          : AppColors.error
                                              .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20.r),
                                    ),
                                    child: Text(
                                      ins['activestatus'] == 1
                                          ? 'Active'
                                          : 'Inactive',
                                      style: TextStyle(
                                        color: ins['activestatus'] == 1
                                            ? AppColors.success
                                            : AppColors.error,
                                        fontSize: 12.sp,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class _SANavItem {
  final IconData icon;
  final String label;
  const _SANavItem(this.icon, this.label);
}

class _InstitutionFinanceSummary {
  final int insId;
  final String insName;
  final String insCode;
  final String? insLogo;
  final double totalDemand;
  final double totalCollected;
  final double totalPending;
  final int transactionCount;
  final bool activeStatus;
  double todayCollected;

  _InstitutionFinanceSummary({
    required this.insId,
    required this.insName,
    required this.insCode,
    this.insLogo,
    this.todayCollected = 0,
    required this.totalDemand,
    required this.totalCollected,
    required this.totalPending,
    required this.transactionCount,
    required this.activeStatus,
  });
}

class _SuperAdminTransactionRow {
  final String institutionName;
  final String institutionCode;
  final PaymentModel payment;

  const _SuperAdminTransactionRow({
    required this.institutionName,
    required this.institutionCode,
    required this.payment,
  });
}

class _InstitutionDetailPage extends StatefulWidget {
  final _InstitutionFinanceSummary summary;
  const _InstitutionDetailPage({required this.summary});

  @override
  State<_InstitutionDetailPage> createState() => _InstitutionDetailPageState();
}

class _InstitutionDetailPageState extends State<_InstitutionDetailPage> {
  bool _loading = true;
  // Each entry: { class, collection, pending }
  List<Map<String, dynamic>> _classWiseData = [];

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    final s = widget.summary;
    try {
      // Single RPC call for course-wise breakdown
      final rpcResult = await SupabaseService.client
          .rpc('get_institution_course_summary', params: {
        'p_ins_id': s.insId,
      });
      final courseData = rpcResult != null
          ? List<Map<String, dynamic>>.from(rpcResult as List)
          : <Map<String, dynamic>>[];

      final classWise = courseData
          .map((row) => {
                'class': '${row['course'] ?? 'Other'} - ${row['class'] ?? ''}',
                'collection': (row['collection'] as num?)?.toDouble() ?? 0.0,
                'pending': (row['pending'] as num?)?.toDouble() ?? 0.0,
                'students': (row['students'] as num?)?.toInt() ?? 0,
              })
          .toList();

      if (mounted) {
        setState(() {
          _classWiseData = classWise;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading institution details: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  String _fmt(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},')}';
    }
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');
    return '₹$intPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.summary;
    const collectionColor = Color(0xFF43A047);
    const pendingColor = Color(0xFFEF5350);

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(s.insName),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: EdgeInsets.all(20.w),
              child: Column(
                children: [
                  // Summary row
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          decoration: BoxDecoration(
                            color: collectionColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                                color: collectionColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              Text('Total Collection',
                                  style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w600,
                                      color: collectionColor)),
                              SizedBox(height: 6.h),
                              Text(
                                  _fmt(_classWiseData.fold<double>(
                                      0,
                                      (sum, r) =>
                                          sum +
                                          ((r['collection'] as double?) ?? 0))),
                                  style: TextStyle(
                                      fontSize: 22.sp,
                                      fontWeight: FontWeight.w800,
                                      color: collectionColor)),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Container(
                          padding: EdgeInsets.symmetric(vertical: 16.h),
                          decoration: BoxDecoration(
                            color: pendingColor.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12.r),
                            border: Border.all(
                                color: pendingColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              Text('Total Pending',
                                  style: TextStyle(
                                      fontSize: 13.sp,
                                      fontWeight: FontWeight.w600,
                                      color: pendingColor)),
                              SizedBox(height: 6.h),
                              Text(
                                  _fmt(_classWiseData.fold<double>(
                                      0,
                                      (sum, r) =>
                                          sum +
                                          ((r['pending'] as double?) ?? 0))),
                                  style: TextStyle(
                                      fontSize: 22.sp,
                                      fontWeight: FontWeight.w800,
                                      color: pendingColor)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  // Table header
                  Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(12.r)),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                            flex: 3,
                            child: Padding(
                                padding: EdgeInsets.fromLTRB(16.w, 0, 24.w, 0),
                                child: Text('Course - Class',
                                    style: TextStyle(
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w700)))),
                        Expanded(
                            child: Text('Students',
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.accent),
                                textAlign: TextAlign.right)),
                        Expanded(
                            child: Text('Collection',
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w700,
                                    color: collectionColor),
                                textAlign: TextAlign.right)),
                        Expanded(
                            child: Text('Pending',
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w700,
                                    color: pendingColor),
                                textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
                  // Table rows
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(
                            bottom: Radius.circular(12.r)),
                        border: Border(
                          left: BorderSide(color: AppColors.border),
                          right: BorderSide(color: AppColors.border),
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: _classWiseData.isEmpty
                          ? Center(
                              child: Text('No data',
                                  style: TextStyle(
                                      color: AppColors.textSecondary,
                                      fontSize: 13.sp)))
                          : ListView.separated(
                              itemCount: _classWiseData.length,
                              separatorBuilder: (_, __) =>
                                  Divider(height: 1, color: AppColors.border),
                              itemBuilder: (context, index) {
                                final row = _classWiseData[index];
                                final cls = row['class'] as String;
                                final collection =
                                    (row['collection'] as double?) ?? 0;
                                final pending =
                                    (row['pending'] as double?) ?? 0;
                                return Padding(
                                  padding: EdgeInsets.symmetric(
                                      horizontal: 16.w, vertical: 12.h),
                                  child: Row(
                                    children: [
                                      Expanded(
                                          flex: 3,
                                          child: Text(cls,
                                              style: TextStyle(
                                                  fontSize: 13.sp,
                                                  fontWeight:
                                                      FontWeight.w600))),
                                      Expanded(
                                          child: Text('${row['students'] ?? 0}',
                                              style: TextStyle(
                                                  fontSize: 13.sp,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.accent),
                                              textAlign: TextAlign.right)),
                                      Expanded(
                                          child: Text(_fmt(collection),
                                              style: TextStyle(
                                                  fontSize: 13.sp,
                                                  fontWeight: FontWeight.w700,
                                                  color: collectionColor),
                                              textAlign: TextAlign.right)),
                                      Expanded(
                                          child: Text(_fmt(pending),
                                              style: TextStyle(
                                                  fontSize: 13.sp,
                                                  fontWeight: FontWeight.w700,
                                                  color: pendingColor),
                                              textAlign: TextAlign.right)),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _CourseWiseCollectionPage extends StatefulWidget {
  final _InstitutionFinanceSummary summary;
  final String mode; // 'collection' or 'pending'
  const _CourseWiseCollectionPage(
      {required this.summary, this.mode = 'collection'});

  @override
  State<_CourseWiseCollectionPage> createState() =>
      _CourseWiseCollectionPageState();
}

class _CourseWiseCollectionPageState extends State<_CourseWiseCollectionPage> {
  bool _loading = true;
  List<Map<String, dynamic>> _rows = [];
  DateTime? _filterFrom;
  DateTime? _filterTo;
  String? _schema;
  String? _activePreset;

  @override
  void initState() {
    super.initState();
    if (widget.mode == 'collection') {
      final now = DateTime.now();
      _filterFrom = DateTime(now.year, now.month, now.day);
      _filterTo = DateTime(now.year, now.month, now.day);
      _activePreset = 'today';
    }
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      if (widget.mode == 'collection' &&
          (_filterFrom != null || _filterTo != null)) {
        await _loadCollectionFromPayments();
      } else {
        final rpc = await SupabaseService.client.rpc(
            'get_institution_course_summary',
            params: {'p_ins_id': widget.summary.insId});
        if (rpc != null) {
          final all = List<Map<String, dynamic>>.from(rpc as List).map((r) {
            final collection = (r['collection'] as num?)?.toDouble() ?? 0;
            final pending = (r['pending'] as num?)?.toDouble() ?? 0;
            return {...r, 'demand': collection + pending};
          }).toList();
          _rows = all
              .where((r) => ((r[widget.mode] as num?)?.toDouble() ?? 0) > 0)
              .toList();

          if (widget.mode == 'pending' || widget.mode == 'collection') {
            await _computeStudentCounts();
          }
        }
      }
    } catch (e) {
      debugPrint('course-wise ${widget.mode} error: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<String?> _resolveSchema() async {
    if (_schema != null) return _schema;
    final now = DateTime.now();
    final insRow = await SupabaseService.client
        .from('institution')
        .select('inshortname')
        .eq('ins_id', widget.summary.insId)
        .maybeSingle();
    final shortName = (insRow?['inshortname'] as String?)?.toLowerCase();
    if (shortName == null) return null;
    final yearRows = await SupabaseService.client
        .from('institutionyear')
        .select('yrlabel, iyrstadate, iyrenddate')
        .eq('ins_id', widget.summary.insId)
        .eq('activestatus', 1)
        .order('iyr_id', ascending: false);
    final years = List<Map<String, dynamic>>.from(yearRows as List);
    if (years.isEmpty) return null;
    String? yearLabel;
    for (final y in years) {
      final start = DateTime.tryParse(y['iyrstadate']?.toString() ?? '');
      final end = DateTime.tryParse(y['iyrenddate']?.toString() ?? '');
      if (start != null &&
          end != null &&
          !now.isBefore(start) &&
          !now.isAfter(end)) {
        yearLabel = y['yrlabel']?.toString();
        break;
      }
    }
    yearLabel ??= years.first['yrlabel']?.toString();
    if (yearLabel == null) return null;
    _schema = '$shortName${yearLabel.replaceAll('-', '')}';
    return _schema;
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  Future<void> _loadCollectionFromPayments() async {
    final schema = await _resolveSchema();
    if (schema == null) {
      _rows = [];
      return;
    }
    var q = SupabaseService.client
        .schema(schema)
        .from('payment')
        .select('stu_id, transtotalamount, paydate')
        .eq('paystatus', 'C')
        .eq('activestatus', 1);
    if (_filterFrom != null) q = q.gte('paydate', _dateStr(_filterFrom!));
    if (_filterTo != null) q = q.lte('paydate', _dateStr(_filterTo!));
    final payments = await q;
    final paymentList = List<Map<String, dynamic>>.from(payments as List);
    final stuIds = paymentList
        .map((p) => p['stu_id'])
        .where((id) => id != null)
        .toSet()
        .toList();
    if (stuIds.isEmpty) {
      _rows = [];
      return;
    }
    final students = await SupabaseService.client
        .schema(schema)
        .from('students')
        .select('stu_id, stuclass, courname')
        .inFilter('stu_id', stuIds);
    final stuMap = <int, Map<String, dynamic>>{};
    for (final s in (students as List)) {
      final id = s['stu_id'];
      if (id is int) stuMap[id] = Map<String, dynamic>.from(s as Map);
    }

    final groups = <String, Map<String, dynamic>>{};
    for (final p in paymentList) {
      final stuId = p['stu_id'];
      final s = stuMap[stuId is int ? stuId : int.tryParse('$stuId')];
      final course = (s?['courname'] ?? 'Other').toString();
      final cls = (s?['stuclass'] ?? '').toString();
      final key = '$course|$cls';
      final amt = (p['transtotalamount'] as num?)?.toDouble() ?? 0;
      final g = groups.putIfAbsent(
          key,
          () => {
                'course': course,
                'class': cls,
                'collection': 0.0,
                '_stu_ids': <dynamic>{},
              });
      g['collection'] = (g['collection'] as double) + amt;
      (g['_stu_ids'] as Set).add(stuId);
    }

    final result = groups.values.map((g) {
      final paid = (g['_stu_ids'] as Set).length;
      g.remove('_stu_ids');
      g['paid_students'] = paid;
      return g;
    }).toList()
      ..sort(
          (a, b) => (a['course'] as String).compareTo(b['course'] as String));
    _rows = result
        .where((r) => ((r['collection'] as num?)?.toDouble() ?? 0) > 0)
        .toList();
  }

  Future<void> _computeStudentCounts() async {
    try {
      final now = DateTime.now();
      final insRow = await SupabaseService.client
          .from('institution')
          .select('inshortname')
          .eq('ins_id', widget.summary.insId)
          .maybeSingle();
      final shortName = (insRow?['inshortname'] as String?)?.toLowerCase();
      if (shortName == null) return;

      final yearRows = await SupabaseService.client
          .from('institutionyear')
          .select('yrlabel, iyrstadate, iyrenddate')
          .eq('ins_id', widget.summary.insId)
          .eq('activestatus', 1)
          .order('iyr_id', ascending: false);
      final years = List<Map<String, dynamic>>.from(yearRows as List);
      if (years.isEmpty) return;

      String? yearLabel;
      for (final y in years) {
        final start = DateTime.tryParse(y['iyrstadate']?.toString() ?? '');
        final end = DateTime.tryParse(y['iyrenddate']?.toString() ?? '');
        if (start != null &&
            end != null &&
            !now.isBefore(start) &&
            !now.isAfter(end)) {
          yearLabel = y['yrlabel']?.toString();
          break;
        }
      }
      yearLabel ??= years.first['yrlabel']?.toString();
      if (yearLabel == null) return;

      final schema = '$shortName${yearLabel.replaceAll('-', '')}';
      final isPending = widget.mode == 'pending';
      final fieldKey = isPending ? 'unpaid_students' : 'paid_students';

      List<dynamic> stuIdRows;
      if (isPending) {
        stuIdRows = await SupabaseService.client
            .schema(schema)
            .from('feedemand')
            .select('stu_id')
            .gt('balancedue', 0)
            .eq('activestatus', 1);
      } else {
        stuIdRows = await SupabaseService.client
            .schema(schema)
            .from('payment')
            .select('stu_id')
            .eq('paystatus', 'C')
            .eq('activestatus', 1);
      }
      final stuIds = stuIdRows
          .map((r) => r['stu_id'])
          .where((id) => id != null)
          .toSet()
          .toList();
      if (stuIds.isEmpty) {
        for (final r in _rows) {
          r[fieldKey] = 0;
        }
        return;
      }

      final students = await SupabaseService.client
          .schema(schema)
          .from('students')
          .select('stu_id, stuclass, courname')
          .inFilter('stu_id', stuIds);

      final counts = <String, int>{};
      for (final s in (students as List)) {
        final key = '${s['courname'] ?? 'Other'}|${s['stuclass'] ?? ''}';
        counts[key] = (counts[key] ?? 0) + 1;
      }
      for (final r in _rows) {
        final key = '${r['course'] ?? 'Other'}|${r['class'] ?? ''}';
        r[fieldKey] = counts[key] ?? 0;
      }
    } catch (e) {
      debugPrint('student counts (${widget.mode}) error: $e');
    }
  }

  Widget _buildDateFilterBar() {
    String fmt(DateTime? d) => d == null
        ? ''
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    Widget quick(String label, String key, VoidCallback onTap) {
      final isActive = _activePreset == key;
      return Padding(
        padding: EdgeInsets.only(left: 4.w),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6.r),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
            decoration: BoxDecoration(
              color: isActive
                  ? AppColors.accent.withValues(alpha: 0.15)
                  : AppColors.surface,
              borderRadius: BorderRadius.circular(6.r),
              border: Border.all(
                  color: isActive ? AppColors.accent : AppColors.border),
            ),
            child: Text(label,
                style: TextStyle(
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w500,
                    color: isActive ? AppColors.accent : null)),
          ),
        ),
      );
    }

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_alt_rounded,
              size: 16, color: AppColors.textSecondary),
          SizedBox(width: 8.w),
          Text('Date Range:',
              style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textSecondary)),
          SizedBox(width: 8.w),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _filterFrom ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() {
                  _filterFrom = picked;
                  _activePreset = null;
                });
                _load();
              }
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 6.w),
                  Text(_filterFrom != null ? fmt(_filterFrom) : 'From',
                      style: TextStyle(fontSize: 13.sp)),
                ],
              ),
            ),
          ),
          Padding(
              padding: EdgeInsets.symmetric(horizontal: 6.w),
              child: const Text('—',
                  style: TextStyle(color: AppColors.textSecondary))),
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _filterTo ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime(2030),
              );
              if (picked != null) {
                setState(() {
                  _filterTo = picked;
                  _activePreset = null;
                });
                _load();
              }
            },
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(6.r),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.calendar_today,
                      size: 14, color: AppColors.textSecondary),
                  SizedBox(width: 6.w),
                  Text(_filterTo != null ? fmt(_filterTo) : 'To',
                      style: TextStyle(fontSize: 13.sp)),
                ],
              ),
            ),
          ),
          SizedBox(width: 8.w),
          quick('Today', 'today', () {
            final now = DateTime.now();
            setState(() {
              _filterFrom = DateTime(now.year, now.month, now.day);
              _filterTo = DateTime(now.year, now.month, now.day);
              _activePreset = 'today';
            });
            _load();
          }),
          quick('7 Days', '7days', () {
            final now = DateTime.now();
            setState(() {
              _filterFrom = now.subtract(const Duration(days: 7));
              _filterTo = DateTime(now.year, now.month, now.day);
              _activePreset = '7days';
            });
            _load();
          }),
          quick('30 Days', '30days', () {
            final now = DateTime.now();
            setState(() {
              _filterFrom = now.subtract(const Duration(days: 30));
              _filterTo = DateTime(now.year, now.month, now.day);
              _activePreset = '30days';
            });
            _load();
          }),
          quick('This Month', 'month', () {
            final now = DateTime.now();
            setState(() {
              _filterFrom = DateTime(now.year, now.month, 1);
              _filterTo = DateTime(now.year, now.month, now.day);
              _activePreset = 'month';
            });
            _load();
          }),
          const Spacer(),
          InkWell(
            onTap: () {
              setState(() {
                _filterFrom = null;
                _filterTo = null;
              });
              _load();
            },
            borderRadius: BorderRadius.circular(6.r),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.refresh_rounded,
                      size: 16.sp, color: AppColors.accent),
                  SizedBox(width: 4.w),
                  Text('Refresh',
                      style: TextStyle(
                          fontSize: 12.sp,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},')}';
    }
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(
        RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');
    return '₹$intPart.${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final Color accentColor;
    final String valueLabel;
    final String totalLabel;
    switch (widget.mode) {
      case 'pending':
        accentColor = const Color(0xFFEF5350);
        valueLabel = 'Pending';
        totalLabel = 'Total Pending';
        break;
      case 'demand':
        accentColor = const Color(0xFF5C6BC0);
        valueLabel = 'Demand';
        totalLabel = 'Total Demand';
        break;
      default:
        accentColor = const Color(0xFF43A047);
        valueLabel = 'Collection';
        totalLabel = 'Total Collection';
    }
    final collectionColor = accentColor;
    final double total;
    if (widget.mode == 'collection') {
      total = _rows.fold<double>(
          0, (sum, r) => sum + ((r['collection'] as num?)?.toDouble() ?? 0));
    } else if (widget.mode == 'pending') {
      total = widget.summary.totalPending;
    } else {
      total = widget.summary.totalDemand;
    }

    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Course-wise $valueLabel',
                style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
            Text(widget.summary.insName,
                style: TextStyle(
                    fontSize: 12.sp,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w400)),
          ],
        ),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: FractionallySizedBox(
                widthFactor: 0.6,
                child: Padding(
                  padding: EdgeInsets.all(20.w),
                  child: Column(
                    children: [
                      if (widget.mode == 'collection') ...[
                        _buildDateFilterBar(),
                        SizedBox(height: 12.h),
                      ],
                      Container(
                        padding: EdgeInsets.symmetric(
                            vertical: 16.h, horizontal: 18.w),
                        decoration: BoxDecoration(
                          color: collectionColor.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                              color: collectionColor.withValues(alpha: 0.2)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(totalLabel,
                                style: TextStyle(
                                    fontSize: 14.sp,
                                    fontWeight: FontWeight.w600,
                                    color: collectionColor)),
                            Text(_fmt(total),
                                style: TextStyle(
                                    fontSize: 20.sp,
                                    fontWeight: FontWeight.w800,
                                    color: collectionColor)),
                          ],
                        ),
                      ),
                      SizedBox(height: 16.h),
                      Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16.w, vertical: 12.h),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.08),
                          borderRadius:
                              BorderRadius.vertical(top: Radius.circular(12.r)),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                                flex: 3,
                                child: Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(16.w, 0, 24.w, 0),
                                    child: Text('Course - Class',
                                        style: TextStyle(
                                            fontSize: 13.sp,
                                            fontWeight: FontWeight.w700)))),
                            Expanded(
                                child: Text(
                                    widget.mode == 'pending'
                                        ? 'Unpaid Students'
                                        : widget.mode == 'collection'
                                            ? 'Paid Students'
                                            : 'Students',
                                    style: TextStyle(
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w700,
                                        color: AppColors.accent),
                                    textAlign: TextAlign.right)),
                            Expanded(
                                child: Text(valueLabel,
                                    style: TextStyle(
                                        fontSize: 13.sp,
                                        fontWeight: FontWeight.w700,
                                        color: collectionColor),
                                    textAlign: TextAlign.right)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.vertical(
                                bottom: Radius.circular(12.r)),
                            border: Border(
                              left: BorderSide(color: AppColors.border),
                              right: BorderSide(color: AppColors.border),
                              bottom: BorderSide(color: AppColors.border),
                            ),
                          ),
                          child: _rows.isEmpty
                              ? Center(
                                  child: Text('No data',
                                      style: TextStyle(
                                          color: AppColors.textSecondary,
                                          fontSize: 13.sp)))
                              : ListView.separated(
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, __) => Divider(
                                      height: 1, color: AppColors.border),
                                  itemBuilder: (context, i) {
                                    final r = _rows[i];
                                    final label =
                                        '${r['course'] ?? 'Other'} - ${r['class'] ?? ''}';
                                    final collection =
                                        (r[widget.mode] as num?)?.toDouble() ??
                                            0;
                                    final int students;
                                    if (widget.mode == 'pending') {
                                      students = (r['unpaid_students'] as num?)
                                              ?.toInt() ??
                                          0;
                                    } else if (widget.mode == 'collection') {
                                      students = (r['paid_students'] as num?)
                                              ?.toInt() ??
                                          0;
                                    } else {
                                      students =
                                          (r['students'] as num?)?.toInt() ?? 0;
                                    }
                                    return Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 16.w, vertical: 12.h),
                                      child: Row(
                                        children: [
                                          Expanded(
                                              flex: 3,
                                              child: Padding(
                                                  padding: EdgeInsets.fromLTRB(
                                                      16.w, 0, 24.w, 0),
                                                  child: Text(label,
                                                      style: TextStyle(
                                                          fontSize: 13.sp,
                                                          fontWeight: FontWeight
                                                              .w600)))),
                                          Expanded(
                                              child: Text('$students',
                                                  style: TextStyle(
                                                      fontSize: 13.sp,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: AppColors.accent),
                                                  textAlign: TextAlign.right)),
                                          Expanded(
                                              child: Text(_fmt(collection),
                                                  style: TextStyle(
                                                      fontSize: 13.sp,
                                                      fontWeight:
                                                          FontWeight.w700,
                                                      color: collectionColor),
                                                  textAlign: TextAlign.right)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}
