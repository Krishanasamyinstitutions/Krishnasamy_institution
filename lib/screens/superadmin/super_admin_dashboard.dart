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

import '../../widgets/app_icon.dart';
class SuperAdminDashboard extends StatefulWidget {
  const SuperAdminDashboard({super.key});

  @override
  State<SuperAdminDashboard> createState() => _SuperAdminDashboardState();
}

class _SuperAdminDashboardState extends State<SuperAdminDashboard> {
  int _selectedNavIndex = 0;
  bool _sidebarCollapsed = false;

  static const List<_SANavItem> _navItems = [
    _SANavItem('element-3', 'Dashboard', section: 'MAIN MENU'),
    _SANavItem('building', 'Register Institution', section: 'INSTITUTIONS'),
    _SANavItem('buildings-2', 'Manage Institutions', unselectedIcon: 'buildings-2', section: 'INSTITUTIONS'),
    _SANavItem('setting-2', 'Settings', section: 'GENERAL'),
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
    // Try the v2 RPC first — single round-trip aggregation for everything.
    try {
      final v2 = await SupabaseService.client.rpc('get_super_admin_dashboard_v2');
      if (v2 is List) {
        final byId = <int, Map<String, dynamic>>{};
        for (final r in v2) {
          if (r is Map && r['ins_id'] is int) {
            byId[r['ins_id'] as int] = Map<String, dynamic>.from(r);
          }
        }
        for (final s in summaries) {
          final r = byId[s.insId];
          if (r == null) continue;
          s.totalPending = (r['total_pending'] as num?)?.toDouble() ?? s.totalPending;
          s.totalCollected = (r['total_collected'] as num?)?.toDouble() ?? s.totalCollected;
          s.pendingApproval = (r['pending_approval'] as num?)?.toDouble() ?? 0;
        }
        if (mounted) setState(() {});
        return;
      }
    } catch (e) {
      debugPrint('v2 dashboard RPC failed, falling back: $e');
    }

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
            .eq('activestatus', 1);
        final total = (rows as List).fold<double>(
            0,
            (sum, r) =>
                sum + ((r['transtotalamount'] as num?)?.toDouble() ?? 0));
        s.todayCollected = total;

        // Pending Approval = sum of paymentdetails (per-fee allocation)
        // for payments awaiting reconciliation, excluding any FINE rows.
        final pendingPays = await SupabaseService.client
            .schema(schema)
            .from('payment')
            .select('pay_id')
            .eq('paystatus', 'C')
            .eq('recon_status', 'P')
            .eq('activestatus', 1);
        final pendingPayIds = (pendingPays as List)
            .map((r) => r['pay_id'])
            .whereType<int>()
            .toList();
        double pendingApproval = 0;
        for (int i = 0; i < pendingPayIds.length; i += 200) {
          final chunk = pendingPayIds.sublist(
              i, (i + 200).clamp(0, pendingPayIds.length));
          final pd = await SupabaseService.client
              .schema(schema)
              .from('paymentdetails')
              .select('dem_id, transtotalamount')
              .inFilter('pay_id', chunk);
          final demIds = (pd as List)
              .map((r) => r['dem_id'])
              .whereType<int>()
              .toSet()
              .toList();
          final demFineMap = <int, double>{};
          for (int j = 0; j < demIds.length; j += 200) {
            final dchunk =
                demIds.sublist(j, (j + 200).clamp(0, demIds.length));
            final fd = await SupabaseService.client
                .schema(schema)
                .from('feedemand')
                .select('dem_id, fineamount')
                .inFilter('dem_id', dchunk);
            for (final r in (fd as List)) {
              demFineMap[r['dem_id'] as int] =
                  (r['fineamount'] as num?)?.toDouble() ?? 0;
            }
          }
          for (final r in pd) {
            final did = r['dem_id'] as int?;
            final amt = (r['transtotalamount'] as num?)?.toDouble() ?? 0;
            final fine = did != null ? (demFineMap[did] ?? 0) : 0;
            pendingApproval += (amt - fine).clamp(0, double.infinity).toDouble();
          }
        }
        s.pendingApproval = pendingApproval;
        // Total Collection and Total Pending are already set from
        // get_super_admin_dashboard RPC (SUM(paidamount) / SUM(balancedue)).
        // Don't override with (feeamount - reconbalancedue) — that formula
        // drifts from the institution dashboard's figures.
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
    final orderedSections = <String>[];
    final groupedIndices = <String, List<int>>{};
    for (var i = 0; i < _navItems.length; i++) {
      final section = _navItems[i].section;
      if (!groupedIndices.containsKey(section)) {
        orderedSections.add(section);
        groupedIndices[section] = [];
      }
      groupedIndices[section]!.add(i);
    }

    final hPad = collapsed
        ? 12.w
        : (MediaQuery.of(context).size.width < 1100 ? 10.w : 14.w);

    return Container(
      color: AppColors.surfaceSidebar,
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 16.w : (MediaQuery.of(context).size.width < 1100 ? 14.w : 24.w),
              vertical: 20.h,
            ),
            child: Row(
              children: [
                Container(
                  width: 32.w,
                  height: 32.h,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: AppIcon('teacher', color: AppColors.primary, size: 16),
                ),
                if (!collapsed) ...[
                  SizedBox(width: 10.w),
                  Text(
                    'EduDesk',
                    style: TextStyle(
                      fontSize: 16.sp,
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.symmetric(horizontal: hPad),
              children: [
                for (var s = 0; s < orderedSections.length; s++) ...[
                  if (!collapsed)
                    Padding(
                      padding: EdgeInsets.only(
                        top: s == 0 ? 4.h : 18.h,
                        bottom: 8.h,
                        left: 10.w,
                      ),
                      child: Text(
                        orderedSections[s],
                        style: TextStyle(
                          fontSize: 11.sp,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.8,
                          color: AppColors.accent,
                        ),
                      ),
                    )
                  else
                    SizedBox(height: s == 0 ? 4.h : 18.h),
                  for (final idx in groupedIndices[orderedSections[s]]!)
                    _buildNavTile(context, idx, collapsed),
                ],
                SizedBox(height: 16.h),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavTile(BuildContext context, int index, bool collapsed) {
    final item = _navItems[index];
    final isSelected = _selectedNavIndex == index;

    const selectedBg = AppColors.primary;
    const selectedFg = AppColors.textOnPrimary;
    const unselectedFg = AppColors.textSecondary;

    final iconSize =
        MediaQuery.of(context).size.width <= 1366 ? 18.sp : 20.sp;

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
            duration: const Duration(milliseconds: 180),
            padding: EdgeInsets.symmetric(
              horizontal: collapsed ? 4.w : 14.w,
              vertical: 11.h,
            ),
            decoration: BoxDecoration(
              color: isSelected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Row(
              mainAxisAlignment: collapsed ? MainAxisAlignment.center : MainAxisAlignment.start,
              children: [
                AppIcon(
                  isSelected ? item.icon : (item.unselectedIcon ?? item.icon),
                  style: isSelected ? AppIconStyle.bold : AppIconStyle.linear,
                  color: isSelected ? selectedFg : unselectedFg,
                  size: iconSize,
                ),
                if (!collapsed) ...[
                  SizedBox(width: 12.w),
                  Expanded(
                    child: Text(
                      item.label,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 13.sp,
                        color: isSelected ? selectedFg : unselectedFg,
                        fontWeight:
                            isSelected ? FontWeight.w700 : FontWeight.w600,
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
  }

  Widget _buildTopBar(BuildContext context, bool isDesktop) {
    final auth = context.watch<AuthProvider>();
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isDesktop ? (MediaQuery.of(context).size.width < 1100 ? 12 : MediaQuery.of(context).size.width < 1400 ? 16 : 24) : 16,
        vertical: 10,
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
              icon: const AppIcon('menu'),
            ),
          if (isDesktop)
            _softIconButton(
              icon: _sidebarCollapsed ? 'menu-open' : 'menu-close',
              onTap: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            ),
          SizedBox(width: 14.w),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _navItems[_selectedNavIndex].label,
                style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: -0.2, height: 1.1),
              ),
              SizedBox(height: 5.h),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon('security-user', size: 14, color: AppColors.accent),
                    SizedBox(width: 6.w),
                    Text(
                      'Super Admin Console',
                      style: TextStyle(fontSize: 12.sp, color: AppColors.accent, fontWeight: FontWeight.w700, letterSpacing: 0.2),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Spacer(),
          SizedBox(width: 12.w),
          PopupMenuButton<String>(
            tooltip: 'Profile options',
            position: PopupMenuPosition.under,
            offset: Offset(0, 8.h),
            color: Colors.white,
            elevation: 10,
            surfaceTintColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12.r),
              side: const BorderSide(color: AppColors.border),
            ),
            menuPadding: EdgeInsets.symmetric(vertical: 6.h),
            padding: EdgeInsets.zero,
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
                    AppIcon('logout', size: 18),
                    SizedBox(width: 8.w),
                    const Text('Sign out'),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: EdgeInsets.only(left: 4.w, right: 12.w, top: 4.h, bottom: 4.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: AppColors.accent.withValues(alpha: 0.18),
                    child: Text(
                      (auth.userName ?? 'S')[0].toUpperCase(),
                      style: TextStyle(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w800,
                        fontSize: 20.sp,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: isDesktop ? 220 : 140),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          auth.userName ?? 'Super Admin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 16.sp, color: AppColors.textPrimary, fontWeight: FontWeight.w700, height: 1.15, letterSpacing: -0.2),
                        ),
                        SizedBox(height: 2.h),
                        Text(
                          auth.userEmail ?? 'Super Admin',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w500, height: 1.15),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(width: 8.w),
                  AppIcon.linear('Chevron Down', size: 16, color: AppColors.textSecondary),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _softIconButton({
    required String icon,
    bool iconLinear = false,
    bool filled = false,
    required VoidCallback onTap,
  }) {
    final bg = filled ? AppColors.primary : Colors.white;
    final fg = filled ? Colors.white : AppColors.textSecondary;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(12),
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: iconLinear
              ? AppIcon.linear(icon, size: 28, color: fg)
              : AppIcon(icon, size: 28, color: fg),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (_selectedNavIndex) {
      case 1:
        return RegisterScreen(onRegistered: _refreshDashboard);
      case 2:
        return _buildManageInstitutions(context);
      case 3:
        return const _SuperAdminSettings();
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
                            color: AppColors.textSecondary, fontSize: 14.sp, fontWeight: FontWeight.w600))))
          else ...[
            _buildSummaryRow(),
            SizedBox(height: 16.h),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
                      child: Row(
                        children: [
                          AppIcon('buildings-2', size: 18, color: AppColors.accent),
                          SizedBox(width: 8.w),
                          Text('Institutions Overview',
                              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const Spacer(),
                          Text('${_institutionSummaries.length} institutes',
                              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: _institutionSummaries.length,
                          separatorBuilder: (_, __) => SizedBox(height: 12.h),
                          itemBuilder: (context, index) {
                            final s = _institutionSummaries[index];
                            return _buildInstitutionCard(context, s);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
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
        0, (sum, s) => sum + s.totalCollected);
    final totalPendingApproval = _institutionSummaries.fold<double>(
        0, (sum, s) => sum + s.pendingApproval);
    final totalPending = _institutionSummaries.fold<double>(
        0, (sum, s) => sum + s.totalPending);

    return Row(
      children: [
        _buildSummaryCard('buildings-2', AppColors.accent, '$activeCount', 'Active Institutes',
            onTap: () => _showAggregateDrilldown(context, 'active')),
        SizedBox(width: 12.w),
        _buildSummaryCard('wallet-1', AppColors.accent, _formatAmount(totalDemand), 'Total Demand',
            onTap: () => _showAggregateDrilldown(context, 'demand')),
        SizedBox(width: 12.w),
        _buildSummaryCard('tick-circle', AppColors.accent, _formatAmount(totalCollection), 'Total Collection',
            onTap: () => _showAggregateDrilldown(context, 'collection')),
        SizedBox(width: 12.w),
        _buildSummaryCard('clock', AppColors.accent, _formatAmount(totalPendingApproval), 'Pending Approval',
            onTap: () => _showAggregateDrilldown(context, 'approval')),
        SizedBox(width: 12.w),
        _buildSummaryCard('timer', AppColors.accent, _formatAmount(totalPending), 'Total Pending',
            onTap: () => _showAggregateDrilldown(context, 'pending')),
      ],
    );
  }

  Widget _buildSummaryCard(String icon, Color iconColor, String value, String label, {VoidCallback? onTap}) {
    final card = Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: AppIcon(icon, color: iconColor, size: 22),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.2)),
                SizedBox(height: 6.h),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (onTap != null)
            AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
        ],
      ),
    );
    return Expanded(
      child: onTap != null
          ? InkWell(
              borderRadius: BorderRadius.circular(12.r),
              onTap: onTap,
              child: card,
            )
          : card,
    );
  }

  void _showAggregateDrilldown(BuildContext context, String mode) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _AggregateDrilldownPage(
          summaries: _institutionSummaries,
          mode: mode,
        ),
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
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
                            fontSize: 16.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary)),
                    SizedBox(height: 2.h),
                    Text(s.insCode,
                        style: TextStyle(
                            fontSize: 12.sp,
                            color: AppColors.textSecondary,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: s.activeStatus
                      ? AppColors.success.withValues(alpha: 0.1)
                      : AppColors.textSecondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  s.activeStatus ? 'Active' : 'Inactive',
                  style: TextStyle(
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w700,
                      color: s.activeStatus
                          ? AppColors.success
                          : AppColors.textSecondary),
                ),
              ),
            ],
          ),
          SizedBox(height: 14.h),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 80.w,
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
                _buildFinanceTile('Total Demand', s.totalDemand, AppColors.accent,
                    icon: 'wallet-1',
                    onTap: () => _showCourseWiseDemand(context, s)),
                SizedBox(width: 12.w),
                _buildFinanceTile(
                    'Total Collection', s.totalCollected, AppColors.success,
                    icon: 'tick-circle',
                    onTap: () => _showCourseWiseCollection(context, s)),
                SizedBox(width: 12.w),
                _buildFinanceTile(
                    'Pending Approval', s.pendingApproval, AppColors.warning,
                    icon: 'clock'),
                SizedBox(width: 12.w),
                _buildFinanceTile(
                    'Total Pending', s.totalPending, AppColors.error,
                    icon: 'timer',
                    onTap: () => _showCourseWisePending(context, s)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCollectionPendingTile(_InstitutionFinanceSummary s, Color collectionColor, Color pendingColor) {
    final pending = (s.totalPending - s.pendingApproval).clamp(0, double.infinity).toDouble();
    Widget half(String label, String value, Color color, VoidCallback onTap) {
      return Expanded(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
            child: Column(
              children: [
                Text(label, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w500, color: Colors.black)),
                SizedBox(height: 6.h),
                Text(value, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800, color: color)),
              ],
            ),
          ),
        ),
      );
    }
    return Expanded(
      flex: 2,
      child: Container(
        decoration: BoxDecoration(
          color: collectionColor.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: collectionColor.withValues(alpha: 0.15)),
        ),
        child: Row(
          children: [
            half('Total Collection', _formatAmount(s.totalCollected), collectionColor, () => _showCourseWiseCollection(context, s)),
            Container(width: 1, height: 38.h, color: AppColors.border),
            half('Total Pending', _formatAmount(pending), pendingColor, () => _showCourseWisePending(context, s)),
          ],
        ),
      ),
    );
  }

  Widget _buildFinanceTile(String label, double amount, Color color,
      {String icon = 'wallet-1', VoidCallback? onTap}) {
    final tile = Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: AppColors.accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: AppIcon(icon, color: AppColors.accent, size: 22),
          ),
          SizedBox(width: 12.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(_formatAmount(amount),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.2)),
                SizedBox(height: 6.h),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          if (onTap != null)
            AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
        ],
      ),
    );
    return Expanded(
      child: onTap != null
          ? InkWell(
              borderRadius: BorderRadius.circular(10.r),
              onTap: onTap,
              child: tile)
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
      String icon, Color color) {
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
              child: AppIcon(icon, color: color, size: 18),
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
                        ?.copyWith(color: Colors.black)),
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
                        color: Colors.black,
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
                    ?.copyWith(color: Colors.black),
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
                    ?.copyWith(color: Colors.black),
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
      padding: EdgeInsets.all(16.w),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      AppIcon('buildings-2', size: 18, color: AppColors.accent),
                      SizedBox(width: 8.w),
                      Text('All Institutions',
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(width: 10.w),
                      Text('${_institutions.length} institutes',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: () => setState(() => _selectedNavIndex = 1),
                      icon: AppIcon('add', size: 16, color: Colors.white),
                      label: const Text('Register New'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _loadingInstitutions
                  ? const Center(child: CircularProgressIndicator())
                  : _institutions.isEmpty
                      ? Center(child: Text('No institutions found',
                          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600)))
                      : ListView.separated(
                          padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                          itemCount: _institutions.length,
                          separatorBuilder: (_, __) => SizedBox(height: 10.h),
                          itemBuilder: (context, index) {
                            final ins = _institutions[index];
                            return Container(
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: AppColors.border),
                              ),
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
                                              color: Colors.black),
                                        ),
                                        SizedBox(height: 2.h),
                                        Text(
                                          '${ins['insmail'] ?? ''}',
                                          style: TextStyle(
                                              fontSize: 13.sp,
                                              color: Colors.black),
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
                                                color: Colors.black),
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
      ),
    );
  }
}

class _SANavItem {
  final String icon;
  final String? unselectedIcon;
  final String label;
  final String section;
  const _SANavItem(this.icon, this.label, {this.unselectedIcon, this.section = 'MAIN MENU'});
}

class _InstitutionFinanceSummary {
  final int insId;
  final String insName;
  final String insCode;
  final String? insLogo;
  final double totalDemand;
  double totalCollected;
  double totalPending;
  final int transactionCount;
  final bool activeStatus;
  double todayCollected;
  double pendingApproval;

  _InstitutionFinanceSummary({
    required this.insId,
    required this.insName,
    required this.insCode,
    this.insLogo,
    this.todayCollected = 0,
    this.pendingApproval = 0,
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
                                      color: Colors.black,
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
    if (_filterTo != null) {
      q = q.lt('paydate', _dateStr(_filterTo!.add(const Duration(days: 1))));
    }
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

      final stuIds = <dynamic>{};
      const pageSize = 1000;
      int offset = 0;
      while (true) {
        final List page = isPending
            ? await SupabaseService.client
                .schema(schema)
                .from('feedemand')
                .select('stu_id')
                .gt('balancedue', 0)
                .eq('activestatus', 1)
                .range(offset, offset + pageSize - 1)
            : await SupabaseService.client
                .schema(schema)
                .from('payment')
                .select('stu_id')
                .eq('paystatus', 'C')
                .eq('activestatus', 1)
                .range(offset, offset + pageSize - 1);
        for (final r in page) {
          if (r['stu_id'] != null) stuIds.add(r['stu_id']);
        }
        if (page.length < pageSize) break;
        offset += pageSize;
      }
      final stuIdsList = stuIds.toList();
      if (stuIds.isEmpty) {
        for (final r in _rows) {
          r[fieldKey] = 0;
        }
        return;
      }

      final counts = <String, int>{};
      for (int i = 0; i < stuIdsList.length; i += 200) {
        final chunk = stuIdsList.sublist(i, (i + 200).clamp(0, stuIdsList.length));
        final students = await SupabaseService.client
            .schema(schema)
            .from('students')
            .select('stu_id, stuclass, courname')
            .inFilter('stu_id', chunk);
        for (final s in (students as List)) {
          final key = '${s['courname'] ?? 'Other'}|${s['stuclass'] ?? ''}';
          counts[key] = (counts[key] ?? 0) + 1;
        }
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
          const AppIcon('filter',
              size: 16, color: Colors.black),
          SizedBox(width: 8.w),
          Text('Date Range:',
              style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w500,
                  color: Colors.black)),
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
                  const AppIcon.linear('calendar',
                      size: 14, color: Colors.black),
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
                  style: TextStyle(color: Colors.black))),
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
                  const AppIcon.linear('calendar',
                      size: 14, color: Colors.black),
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
          const Spacer(),
          SizedBox(
            height: 40,
            child: ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _filterFrom = null;
                  _filterTo = null;
                });
                _load();
              },
              icon: AppIcon('refresh', size: 16, color: Colors.white),
              label: const Text('Refresh'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: EdgeInsets.symmetric(horizontal: 18.w),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
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
      total = widget.summary.totalCollected;
    } else if (widget.mode == 'pending') {
      total = _rows.fold<double>(
          0, (sum, r) => sum + ((r['pending'] as num?)?.toDouble() ?? 0));
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
                    color: Colors.black,
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
                                flex: 2,
                                child: Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(16.w, 0, 12.w, 0),
                                    child: Text('Course',
                                        style: TextStyle(
                                            fontSize: 13.sp,
                                            fontWeight: FontWeight.w700)))),
                            Expanded(
                                flex: 2,
                                child: Padding(
                                    padding:
                                        EdgeInsets.fromLTRB(0, 0, 24.w, 0),
                                    child: Text('Class',
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
                                          color: Colors.black,
                                          fontSize: 13.sp)))
                              : ListView.separated(
                                  itemCount: _rows.length,
                                  separatorBuilder: (_, __) => Divider(
                                      height: 1, color: AppColors.border),
                                  itemBuilder: (context, i) {
                                    final r = _rows[i];
                                    final courseLabel =
                                        '${r['course'] ?? 'Other'}';
                                    final classLabel =
                                        '${r['class'] ?? ''}';
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
                                              flex: 2,
                                              child: Padding(
                                                  padding: EdgeInsets.fromLTRB(
                                                      16.w, 0, 12.w, 0),
                                                  child: Text(courseLabel,
                                                      style: TextStyle(
                                                          fontSize: 13.sp,
                                                          fontWeight: FontWeight
                                                              .w600)))),
                                          Expanded(
                                              flex: 2,
                                              child: Padding(
                                                  padding: EdgeInsets.fromLTRB(
                                                      0, 0, 24.w, 0),
                                                  child: Text(classLabel,
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

/// Super Admin Settings — reset username and password.
class _SuperAdminSettings extends StatefulWidget {
  const _SuperAdminSettings();
  @override
  State<_SuperAdminSettings> createState() => _SuperAdminSettingsState();
}

class _SuperAdminSettingsState extends State<_SuperAdminSettings> {
  final _formKey = GlobalKey<FormState>();
  final _usernameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _currentPwdCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  bool _saving = false;
  bool _showCurrent = false;
  bool _showNew = false;
  bool _showConfirm = false;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _usernameCtrl.text = auth.currentUser?.usename ?? '';
    _emailCtrl.text = auth.currentUser?.usemail ?? '';
  }

  @override
  void dispose() {
    _usernameCtrl.dispose();
    _emailCtrl.dispose();
    _currentPwdCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final useId = auth.currentUser?.useId;
    // Super admin verifies by USERNAME, not email (see verify_user_login RPC).
    final loginId = auth.currentUser?.usename;
    if (useId == null || loginId == null || loginId.isEmpty) return;

    setState(() => _saving = true);
    try {
      // Verify current password via the same login RPC.
      final verify = await SupabaseService.client.rpc('verify_user_login', params: {
        'p_email': loginId,
        'p_plain_password': _currentPwdCtrl.text,
        'p_is_super_admin': true,
      });
      final list = verify is List ? verify : const [];
      final ok = list.isNotEmpty && (list.first as Map)['is_valid'] == true;
      if (!ok) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Current password is incorrect'), backgroundColor: Colors.red),
          );
        }
        setState(() => _saving = false);
        return;
      }

      final updates = <String, dynamic>{
        'usename': _usernameCtrl.text.trim(),
        'usemail': _emailCtrl.text.trim(),
      };
      if (_newPwdCtrl.text.isNotEmpty) {
        // DB trigger hashes plaintext on UPDATE.
        updates['usepassword'] = _newPwdCtrl.text;
      }
      await SupabaseService.client
          .from('institutionusers')
          .update(updates)
          .eq('use_id', useId);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Settings updated successfully'), backgroundColor: Colors.green),
        );
        _currentPwdCtrl.clear();
        _newPwdCtrl.clear();
        _confirmPwdCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Update failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary)),
      );

  TextStyle _fieldStyle() => TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp, color: AppColors.textPrimary);

  InputDecoration _inputDec(String hint, {Widget? suffix}) => InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.55), fontSize: 13.sp, fontWeight: FontWeight.w500),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.error)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
        filled: true,
        fillColor: Colors.white,
        isDense: false,
        constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
        suffixIcon: suffix,
        suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 16, maxHeight: 16),
      );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: EdgeInsets.fromLTRB(20.w, 20.h, 20.w, 20.h),
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: AppIcon('setting-2', color: AppColors.accent, size: 18),
                  ),
                  SizedBox(width: 12.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Account Settings',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 2.h),
                      Text('Manage your account credentials',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 24.h),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Username'),
                  TextFormField(
                    controller: _usernameCtrl,
                    decoration: _inputDec('Enter username'),
                    style: _fieldStyle(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Username required' : null,
                  ),
                ])),
                SizedBox(width: 14.w),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Email'),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: _inputDec('Enter email'),
                    style: _fieldStyle(),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Email required' : null,
                  ),
                ])),
              ]),
              SizedBox(height: 24.h),
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: AppIcon('lock', color: AppColors.accent, size: 18),
                  ),
                  SizedBox(width: 12.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Change Password',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 2.h),
                      Text('Leave new password blank to keep your current one',
                          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 16.h),
              _label('Current Password *'),
              TextFormField(
                controller: _currentPwdCtrl,
                obscureText: !_showCurrent,
                decoration: _inputDec(
                  'Enter current password',
                  suffix: IconButton(
                    icon: AppIcon(_showCurrent ? 'eye-slash' : 'eye', size: 12, color: AppColors.textSecondary),
                    onPressed: () => setState(() => _showCurrent = !_showCurrent),
                  ),
                ),
                style: _fieldStyle(),
                validator: (v) => (v == null || v.isEmpty) ? 'Required to confirm changes' : null,
              ),
              SizedBox(height: 14.h),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('New Password'),
                  TextFormField(
                    controller: _newPwdCtrl,
                    obscureText: !_showNew,
                    decoration: _inputDec(
                      'Leave blank to keep current',
                      suffix: IconButton(
                        icon: AppIcon(_showNew ? 'eye-slash' : 'eye', size: 12, color: AppColors.textSecondary),
                        onPressed: () => setState(() => _showNew = !_showNew),
                      ),
                    ),
                    style: _fieldStyle(),
                    validator: (v) {
                      if (v != null && v.isNotEmpty && v.length < 6) return 'Min 6 characters';
                      return null;
                    },
                  ),
                ])),
                SizedBox(width: 14.w),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _label('Confirm New Password'),
                  TextFormField(
                    controller: _confirmPwdCtrl,
                    obscureText: !_showConfirm,
                    decoration: _inputDec(
                      'Re-enter new password',
                      suffix: IconButton(
                        icon: AppIcon(_showConfirm ? 'eye-slash' : 'eye', size: 12, color: AppColors.textSecondary),
                        onPressed: () => setState(() => _showConfirm = !_showConfirm),
                      ),
                    ),
                    style: _fieldStyle(),
                    validator: (v) {
                      if (_newPwdCtrl.text.isEmpty) return null;
                      if (v != _newPwdCtrl.text) return 'Passwords do not match';
                      return null;
                    },
                  ),
                ])),
              ]),
              SizedBox(height: 28.h),
              Center(
                child: SizedBox(
                  height: 48,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : AppIcon('save-2', size: 18, color: Colors.white),
                    label: Text(_saving ? 'Saving...' : 'Save Changes',
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AggregateDrilldownPage extends StatelessWidget {
  final List<_InstitutionFinanceSummary> summaries;
  final String mode; // active | demand | collection | approval | pending
  const _AggregateDrilldownPage({required this.summaries, required this.mode});

  String get _title {
    switch (mode) {
      case 'active':
        return 'Active Institutes';
      case 'demand':
        return 'Total Demand';
      case 'collection':
        return 'Total Collection';
      case 'approval':
        return 'Pending Approval';
      case 'pending':
        return 'Total Pending';
      default:
        return 'Drilldown';
    }
  }

  String get _columnLabel {
    switch (mode) {
      case 'active':
        return 'STATUS';
      case 'demand':
        return 'DEMAND';
      case 'collection':
        return 'COLLECTION';
      case 'approval':
        return 'PENDING APPROVAL';
      case 'pending':
        return 'PENDING';
      default:
        return 'VALUE';
    }
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

  double _value(_InstitutionFinanceSummary s) {
    switch (mode) {
      case 'demand':
        return s.totalDemand;
      case 'collection':
        return s.totalCollected;
      case 'approval':
        return s.pendingApproval;
      case 'pending':
        return s.totalPending;
      default:
        return 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = mode == 'active'
        ? summaries.where((s) => s.activeStatus).toList()
        : summaries.where((s) => _value(s) > 0).toList();
    if (mode != 'active') {
      filtered.sort((a, b) => _value(b).compareTo(_value(a)));
    }
    final aggregate = mode == 'active'
        ? filtered.length.toString()
        : _formatAmount(filtered.fold<double>(0, (sum, s) => sum + _value(s)));

    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Padding(
        padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 16.h),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(10.r),
                  onTap: () => Navigator.of(context).pop(),
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: AppColors.border),
                    ),
                    alignment: Alignment.center,
                    child: AppIcon.linear('arrow-left-2', size: 18, color: AppColors.textSecondary),
                  ),
                ),
                SizedBox(width: 12.w),
                Text(_title,
                    style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(width: 12.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.4)),
                  ),
                  child: Text('Total: $aggregate',
                      style: TextStyle(fontSize: 12.sp, color: AppColors.accent, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            SizedBox(height: 16.h),
            Expanded(
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 16.h, 16.w, 12.h),
                      child: Row(
                        children: [
                          AppIcon('buildings-2', size: 18, color: AppColors.accent),
                          SizedBox(width: 8.w),
                          Text('Institution Breakdown',
                              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          const Spacer(),
                          Text('${filtered.length} institutes',
                              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                      padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.h),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                          children: [
                            Container(
                              color: AppColors.tableHeadBg,
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                              child: Row(
                                children: [
                                  SizedBox(width: 50.w, child: Text('S NO.', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.4))),
                                  Expanded(child: Text('INSTITUTION', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.4))),
                                  SizedBox(width: 100.w, child: Text('CODE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.4))),
                                  SizedBox(width: 180.w, child: Text(_columnLabel, textAlign: TextAlign.right, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.4))),
                                ],
                              ),
                            ),
                            Expanded(
                              child: filtered.isEmpty
                                  ? Center(
                                      child: Text('No data',
                                          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
                                    )
                                  : ListView.builder(
                                      itemCount: filtered.length,
                                      itemBuilder: (_, i) {
                                        final s = filtered[i];
                                        final zebra = i.isOdd ? AppColors.surface : Colors.white;
                                        return Container(
                                          color: zebra,
                                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                                          child: Row(
                                            children: [
                                              SizedBox(width: 50.w, child: Text('${i + 1}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                              Expanded(child: Text(s.insName, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                              SizedBox(width: 100.w, child: Text(s.insCode, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                              SizedBox(
                                                width: 180.w,
                                                child: mode == 'active'
                                                    ? Align(
                                                        alignment: Alignment.centerRight,
                                                        child: Container(
                                                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                                                          decoration: BoxDecoration(
                                                            color: s.activeStatus
                                                                ? AppColors.success.withValues(alpha: 0.1)
                                                                : AppColors.textSecondary.withValues(alpha: 0.1),
                                                            borderRadius: BorderRadius.circular(999),
                                                          ),
                                                          child: Text(
                                                            s.activeStatus ? 'Active' : 'Inactive',
                                                            style: TextStyle(
                                                                fontSize: 11.sp,
                                                                fontWeight: FontWeight.w700,
                                                                color: s.activeStatus ? AppColors.success : AppColors.textSecondary),
                                                          ),
                                                        ),
                                                      )
                                                    : Text(_formatAmount(_value(s)),
                                                        textAlign: TextAlign.right,
                                                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
