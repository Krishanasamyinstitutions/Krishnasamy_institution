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
  DateTime _fromDate = DateTime.now();
  DateTime _toDate = DateTime.now();
  String _activeFilter = 'Today';

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

  Future<void> _loadInstitutions() async {
    try {
      final result = await SupabaseService.client
          .from('institution')
          .select('ins_id, insname, inscode, inshortname, insmail, insmobno, inscity, insstate, activestatus')
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

        if (insId == null || shortName == null || shortName.isEmpty) {
          summaries.add(
            _InstitutionFinanceSummary(
              insId: insId ?? 0,
              insName: insName,
              insCode: insCode,
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
                      onTap: () => setState(() => _selectedNavIndex = index),
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
        return const RegisterScreen();
      case 2:
        return _buildManageInstitutions(context);
      default:
        return _buildDashboardHome(context);
    }
  }

  Widget _buildDashboardHome(BuildContext context) {
    final cards = ['KCET', 'KA', 'KP'];
    return Padding(
      padding: EdgeInsets.all(20.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 10.h),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Icon(Icons.filter_alt_rounded, size: 18.sp, color: AppColors.accent),
                SizedBox(width: 8.w),
                Text('Date Range:', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
                SizedBox(width: 8.w),
                _buildDateChip(_fromDate, () => _pickDate(true)),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('—', style: TextStyle(color: AppColors.textSecondary)),
                ),
                _buildDateChip(_toDate, () => _pickDate(false)),
                SizedBox(width: 12.w),
                _buildQuickFilter('Today', () {
                  setState(() {
                    _fromDate = DateTime.now();
                    _toDate = DateTime.now();
                    _activeFilter = 'Today';
                  });
                }),
                SizedBox(width: 6.w),
                _buildQuickFilter('7 Days', () {
                  setState(() {
                    _toDate = DateTime.now();
                    _fromDate = DateTime.now().subtract(const Duration(days: 7));
                    _activeFilter = '7 Days';
                  });
                }),
                SizedBox(width: 6.w),
                _buildQuickFilter('30 Days', () {
                  setState(() {
                    _toDate = DateTime.now();
                    _fromDate = DateTime.now().subtract(const Duration(days: 30));
                    _activeFilter = '30 Days';
                  });
                }),
                SizedBox(width: 6.w),
                _buildQuickFilter('This Month', () {
                  final now = DateTime.now();
                  setState(() {
                    _fromDate = DateTime(now.year, now.month, 1);
                    _toDate = now;
                    _activeFilter = 'This Month';
                  });
                }),
                const Spacer(),
                TextButton.icon(
                  onPressed: _loadInstitutions,
                  icon: Icon(Icons.refresh_rounded, size: 16.sp),
                  label: const Text('Refresh'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.textSecondary,
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(height: 12.h),
          ...cards.map((name) {
            return Expanded(
              child: Padding(
              padding: EdgeInsets.only(bottom: 10.h),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => _InstitutionDetailPage(institutionName: name),
                    ),
                  );
                },
                child: Container(
                width: double.infinity,
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14.r),
                  border: Border.all(color: AppColors.border),
                ),
                child: Stack(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name,
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const Spacer(),
                        Row(
                          children: [
                            const Expanded(child: SizedBox()),
                            ...['Total Demand', 'Total Collection', 'Total Pending'].map((label) {
                              return Expanded(
                                child: Center(
                                  child: Text(
                                    label,
                                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                          color: AppColors.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ],
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 28.sp,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
            );
          }),
          Row(
            children: ['Active Institutes', 'Total Demand', 'Total Collection', 'Total Pending'].map((label) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8.w),
                  child: Container(
                    height: 60,
                    padding: EdgeInsets.all(10.w),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12.r),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Center(
                      child: Text(
                        label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
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

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
        _activeFilter = '';
      });
    }
  }

  Widget _buildDateChip(DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today, size: 14.sp, color: AppColors.accent),
            SizedBox(width: 6.w),
            Text(_formatDate(date), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilter(String label, VoidCallback onTap) {
    final isActive = _activeFilter == label;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: isActive ? AppColors.accent : Colors.transparent,
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13.sp,
            color: isActive ? Colors.white : AppColors.textSecondary,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
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
  final double totalCollected;
  final double totalPending;
  final int transactionCount;
  final bool activeStatus;

  const _InstitutionFinanceSummary({
    required this.insId,
    required this.insName,
    required this.insCode,
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

class _InstitutionDetailPage extends StatelessWidget {
  final String institutionName;
  const _InstitutionDetailPage({required this.institutionName});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: Text(institutionName),
        backgroundColor: Colors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: Center(
        child: Text(
          '$institutionName - Details Coming Soon',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: AppColors.textSecondary,
              ),
        ),
      ),
    );
  }
}
