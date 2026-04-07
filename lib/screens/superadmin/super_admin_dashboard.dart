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

  Future<void> _loadInstitutions() async {
    try {
      final result = await SupabaseService.client
          .from('institution')
          .select('ins_id, insname, inscode, inshortname, inslogo, insmail, insmobno, inscity, insstate, activestatus')
          .order('insname');
      final institutions = List<Map<String, dynamic>>.from(result);
      await _loadFinanceData(institutions);
      if (mounted) {
        setState(() {
          _institutions = institutions;
          _loadingInstitutions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loadingInstitutions = false;
          _loadingFinanceData = false;
        });
      }
    }
  }

  Future<void> _loadFinanceData(List<Map<String, dynamic>> institutions) async {
    final previousSchema = SupabaseService.currentSchema;
    final summaries = <_InstitutionFinanceSummary>[];
    final allTransactions = <_SuperAdminTransactionRow>[];

    try {
      for (final ins in institutions) {
        final insId = ins['ins_id'] as int?;
        final insName = ins['insname']?.toString() ?? 'Institution';
        final insCode = ins['inscode']?.toString() ?? '';
        final shortName = ins['inshortname']?.toString().toLowerCase();
        final insLogo = ins['inslogo']?.toString();

        if (insId == null || shortName == null || shortName.isEmpty) {
          summaries.add(
            _InstitutionFinanceSummary(
              insId: insId ?? 0,
              insName: insName,
              insCode: insCode,
              insLogo: insLogo,
              totalDemand: 0,
              totalCollected: 0,
              totalPending: 0,
              transactionCount: 0,
              activeStatus: ins['activestatus'] == 1,
            ),
          );
          continue;
        }

        final yearLabel = await _fetchLatestYearLabel(insId);
        final schemaName = '$shortName${yearLabel.replaceAll('-', '')}';

        SupabaseService.setSchema(schemaName);

        final results = await Future.wait([
          SupabaseService.getFeeSummary(insId),
          SupabaseService.getAllTransactions(insId),
        ]);

        final feeSummary = results[0] as FeeSummary;
        final transactionMaps = results[1] as List<Map<String, dynamic>>;
        final payments = transactionMaps.map(PaymentModel.fromJson).toList()
          ..sort((a, b) {
            final aDate = a.paydate ?? a.createdat;
            final bDate = b.paydate ?? b.createdat;
            return bDate.compareTo(aDate);
          });

        summaries.add(
          _InstitutionFinanceSummary(
            insId: insId,
            insName: insName,
            insCode: insCode,
            insLogo: insLogo,
            totalDemand: feeSummary.totalDue,
            totalCollected: feeSummary.totalPaid,
            totalPending: feeSummary.totalPending,
            transactionCount: payments.length,
            activeStatus: ins['activestatus'] == 1,
          ),
        );

        allTransactions.addAll(
          payments.take(10).map(
            (payment) => _SuperAdminTransactionRow(
              institutionName: insName,
              institutionCode: insCode,
              payment: payment,
            ),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error loading super admin finance data: $e');
    } finally {
      SupabaseService.setSchema(previousSchema);
    }

    allTransactions.sort((a, b) {
      final aDate = a.payment.paydate ?? a.payment.createdat;
      final bDate = b.payment.paydate ?? b.payment.createdat;
      return bDate.compareTo(aDate);
    });

    if (!mounted) return;
    setState(() {
      _institutionSummaries = summaries;
      _recentTransactions = allTransactions.take(20).toList();
      _loadingFinanceData = false;
    });
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
      drawer: !isDesktop
          ? Drawer(child: _buildSidebar(context, false))
          : null,
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
              padding: EdgeInsets.symmetric(horizontal: collapsed ? 12.w : 16.w),
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
                              color: isSelected ? AppColors.primary : AppColors.textSecondary,
                              size: 20.sp,
                            ),
                            if (!collapsed) ...[
                              SizedBox(width: 14.w),
                              Flexible(
                                child: Text(
                                  item.label,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                        color: isSelected ? AppColors.primary : AppColors.textSecondary,
                                        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
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
      padding: EdgeInsets.symmetric(horizontal: isDesktop ? 28 : 16, vertical: 12),
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
              onPressed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
              icon: Icon(_sidebarCollapsed ? Icons.menu_open_rounded : Icons.menu_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.surface,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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
                    style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700),
                  ),
                ),
                SizedBox(width: 10.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(auth.userName ?? 'Super Admin',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                    Text('Super Admin',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
                PopupMenuButton<String>(
                  tooltip: 'Options',
                  position: PopupMenuPosition.under,
                  offset: Offset(0, 8.h),
                  color: Colors.white,
                  elevation: 10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                  icon: const Icon(Icons.keyboard_arrow_down_rounded, color: AppColors.textSecondary),
                  onSelected: (value) async {
                    if (value == 'signout') {
                      await auth.logout();
                      if (context.mounted) {
                        Navigator.pushReplacementNamed(context, AppRoutes.welcome);
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
            Expanded(child: Center(child: Text('No institutions found', style: TextStyle(color: AppColors.textSecondary, fontSize: 14.sp))))
          else ...[
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
            SizedBox(height: 12.h),
            _buildSummaryRow(),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryRow() {
    final activeCount = _institutionSummaries.where((s) => s.activeStatus).length;
    final totalDemand = _institutionSummaries.fold<double>(0, (sum, s) => sum + s.totalDemand);
    final totalCollection = _institutionSummaries.fold<double>(0, (sum, s) => sum + s.totalCollected);
    final totalPending = _institutionSummaries.fold<double>(0, (sum, s) => sum + s.totalPending);

    const demandColor = Color(0xFF5C6BC0);
    const collectionColor = Color(0xFF43A047);
    const pendingColor = Color(0xFFEF5350);

    return Row(
      children: [
        SizedBox(
          width: 132.w,
          child: _buildSummaryTile('Active Institutes', activeCount.toString(), demandColor),
        ),
        SizedBox(width: 12.w),
        Expanded(child: _buildSummaryTile('Total Demand', _formatAmount(totalDemand), demandColor)),
        SizedBox(width: 12.w),
        Expanded(child: _buildSummaryTile('Total Collection', _formatAmount(totalCollection), collectionColor)),
        SizedBox(width: 12.w),
        Expanded(child: _buildSummaryTile('Total Pending', _formatAmount(totalPending), pendingColor)),
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
          Text(label, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
          SizedBox(height: 6.h),
          Text(value, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800, color: color)),
        ],
      ),
    );
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},')}';
    }
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');
    return '₹$intPart.${parts[1]}';
  }

  Widget _buildInstitutionCard(BuildContext context, _InstitutionFinanceSummary s) {
    const demandColor = Color(0xFF5C6BC0);
    const collectionColor = Color(0xFF43A047);
    const pendingColor = Color(0xFFEF5350);

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => _InstitutionDetailPage(summary: s)),
        );
      },
      child: Container(
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
                child: Center(child: Text(s.insCode.isNotEmpty ? s.insCode[0] : 'I', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800, color: AppColors.primary))),
              ),
              SizedBox(width: 12.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.insName, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2.h),
                    Text(s.insCode, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: s.activeStatus ? collectionColor.withValues(alpha: 0.1) : Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20.r),
                ),
                child: Text(
                  s.activeStatus ? 'Active' : 'Inactive',
                  style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: s.activeStatus ? collectionColor : Colors.grey),
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
                            child: Text(s.insName[0], style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: AppColors.primary)),
                          ),
                        ),
                      )
                    : Center(
                        child: Text(s.insName[0], style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: AppColors.primary)),
                      ),
              ),
              SizedBox(width: 12.w),
              _buildFinanceTile('Total Demand', s.totalDemand, demandColor),
              SizedBox(width: 12.w),
              _buildFinanceTile('Total Collection', s.totalCollected, collectionColor),
              SizedBox(width: 12.w),
              _buildFinanceTile('Total Pending', s.totalPending, pendingColor),
            ],
          ),
        ],
      ),
    ),
    );
  }

  Widget _buildFinanceTile(String label, double amount, Color color) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 14.h),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: color.withValues(alpha: 0.15)),
        ),
        child: Column(
          children: [
            Text(label, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            SizedBox(height: 6.h),
            Text(_formatAmount(amount), style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w800, color: color)),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(BuildContext context, String title, String value, IconData icon, Color color) {
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
                Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
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
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
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
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: item.activeStatus
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20.r),
                          ),
                          child: Text(
                            item.activeStatus ? 'Active' : 'Inactive',
                            style: TextStyle(
                              color: item.activeStatus ? AppColors.success : AppColors.error,
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: AppColors.textSecondary),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                headingRowColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.08)),
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
                  final statusColor = isPaid ? AppColors.success : AppColors.error;
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
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
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
              Text('All Institutions', style: Theme.of(context).textTheme.headlineSmall),
              ElevatedButton.icon(
                onPressed: () => setState(() => _selectedNavIndex = 1),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Register New'),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent),
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
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22.r,
                                    backgroundColor: AppColors.primary.withValues(alpha: 0.1),
                                    child: Text(
                                      (ins['insname'] as String? ?? 'I')[0].toUpperCase(),
                                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 16.sp),
                                    ),
                                  ),
                                  SizedBox(width: 14.w),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          ins['insname'] ?? '',
                                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15.sp, color: AppColors.textPrimary),
                                        ),
                                        SizedBox(height: 6.h),
                                        Text(
                                          'Code: ${ins['inscode'] ?? ''}',
                                          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                                        ),
                                        SizedBox(height: 2.h),
                                        Text(
                                          '${ins['insmail'] ?? ''}',
                                          style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                                        ),
                                        if ((ins['inscity'] ?? '').toString().isNotEmpty || (ins['insstate'] ?? '').toString().isNotEmpty) ...[
                                          SizedBox(height: 2.h),
                                          Text(
                                            '${ins['inscity'] ?? ''}${(ins['inscity'] ?? '').toString().isNotEmpty && (ins['insstate'] ?? '').toString().isNotEmpty ? ', ' : ''}${ins['insstate'] ?? ''}',
                                            style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  SizedBox(width: 12.w),
                                  Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                                    decoration: BoxDecoration(
                                      color: ins['activestatus'] == 1
                                          ? AppColors.success.withValues(alpha: 0.1)
                                          : AppColors.error.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(20.r),
                                    ),
                                    child: Text(
                                      ins['activestatus'] == 1 ? 'Active' : 'Inactive',
                                      style: TextStyle(
                                        color: ins['activestatus'] == 1 ? AppColors.success : AppColors.error,
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

  const _InstitutionFinanceSummary({
    required this.insId,
    required this.insName,
    required this.insCode,
    this.insLogo,
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
    final previousSchema = SupabaseService.currentSchema;
    try {
      final insResult = await SupabaseService.client
          .from('institution')
          .select('inshortname')
          .eq('ins_id', s.insId)
          .maybeSingle();
      final shortName = insResult?['inshortname']?.toString().toLowerCase();
      if (shortName == null || shortName.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final yrResult = await SupabaseService.client
          .from('institutionyear')
          .select('yrlabel')
          .eq('ins_id', s.insId)
          .eq('activestatus', 1)
          .order('iyr_id', ascending: false)
          .limit(1)
          .maybeSingle();
      final year = DateTime.now().year;
      final yrLabel = yrResult?['yrlabel']?.toString() ?? '$year-${year + 1}';
      final schemaName = '$shortName${yrLabel.replaceAll('-', '')}';

      SupabaseService.setSchema(schemaName);

      // Fetch feedemand with stu_id, paidamount, balancedue (paginated)
      final feedemandList = <Map<String, dynamic>>[];
      const batchSize = 1000;
      int offset = 0;
      while (true) {
        final batch = await SupabaseService.fromSchema('feedemand')
            .select('stu_id, paidamount, balancedue')
            .eq('ins_id', s.insId)
            .range(offset, offset + batchSize - 1);
        final list = List<Map<String, dynamic>>.from(batch);
        feedemandList.addAll(list);
        if (list.length < batchSize) break;
        offset += batchSize;
      }

      // Fetch students with courname (paginated) - table is 'students' (plural)
      final stuCourseMap = <int, String>{};
      offset = 0;
      while (true) {
        final batch = await SupabaseService.fromSchema('students')
            .select('stu_id, courname')
            .eq('ins_id', s.insId)
            .range(offset, offset + batchSize - 1);
        final list = List<Map<String, dynamic>>.from(batch);
        for (final sr in list) {
          final sid = sr['stu_id'] as int?;
          final course = sr['courname']?.toString() ?? 'Other';
          if (sid != null) stuCourseMap[sid] = course;
        }
        if (list.length < batchSize) break;
        offset += batchSize;
      }

      // Group feedemand by student's course
      final collectionMap = <String, double>{};
      final pendingMap = <String, double>{};
      for (final row in feedemandList) {
        final stuId = row['stu_id'] as int?;
        final course = stuCourseMap[stuId ?? 0] ?? 'Other';
        final paid = (row['paidamount'] as num?)?.toDouble() ?? 0;
        final balance = (row['balancedue'] as num?)?.toDouble() ?? 0;
        collectionMap[course] = (collectionMap[course] ?? 0) + paid;
        pendingMap[course] = (pendingMap[course] ?? 0) + balance;
      }

      final allCourses = {...collectionMap.keys, ...pendingMap.keys}.toList()..sort();
      final classWise = allCourses.map((course) => {
        'class': course,
        'collection': collectionMap[course] ?? 0.0,
        'pending': pendingMap[course] ?? 0.0,
      }).toList();

      if (mounted) {
        setState(() {
          _classWiseData = classWise;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading institution details: $e');
      if (mounted) setState(() => _loading = false);
    } finally {
      SupabaseService.setSchema(previousSchema);
    }
  }

  String _fmt(double amount) {
    if (amount == amount.roundToDouble()) {
      return '₹${amount.toInt().toString().replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},')}';
    }
    final parts = amount.toStringAsFixed(2).split('.');
    final intPart = parts[0].replaceAllMapped(RegExp(r'(\d)(?=(\d{2})+(\d)(?!\d))'), (m) => '${m[1]},');
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
                            border: Border.all(color: collectionColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              Text('Total Collection', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: collectionColor)),
                              SizedBox(height: 6.h),
                              Text(_fmt(_classWiseData.fold<double>(0, (sum, r) => sum + ((r['collection'] as double?) ?? 0))),
                                  style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: collectionColor)),
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
                            border: Border.all(color: pendingColor.withValues(alpha: 0.2)),
                          ),
                          child: Column(
                            children: [
                              Text('Total Pending', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: pendingColor)),
                              SizedBox(height: 6.h),
                              Text(_fmt(_classWiseData.fold<double>(0, (sum, r) => sum + ((r['pending'] as double?) ?? 0))),
                                  style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w800, color: pendingColor)),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  // Table header
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text('Course', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700))),
                        Expanded(child: Text('Collection', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: collectionColor), textAlign: TextAlign.right)),
                        Expanded(child: Text('Pending', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: pendingColor), textAlign: TextAlign.right)),
                      ],
                    ),
                  ),
                  // Table rows
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(bottom: Radius.circular(12.r)),
                        border: Border(
                          left: BorderSide(color: AppColors.border),
                          right: BorderSide(color: AppColors.border),
                          bottom: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: _classWiseData.isEmpty
                          ? Center(child: Text('No data', style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp)))
                          : ListView.separated(
                              itemCount: _classWiseData.length,
                              separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border),
                              itemBuilder: (context, index) {
                                final row = _classWiseData[index];
                                final cls = row['class'] as String;
                                final collection = (row['collection'] as double?) ?? 0;
                                final pending = (row['pending'] as double?) ?? 0;
                                return Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                                  child: Row(
                                    children: [
                                      Expanded(flex: 2, child: Text(cls, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600))),
                                      Expanded(child: Text(_fmt(collection), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: collectionColor), textAlign: TextAlign.right)),
                                      Expanded(child: Text(_fmt(pending), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: pendingColor), textAlign: TextAlign.right)),
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
