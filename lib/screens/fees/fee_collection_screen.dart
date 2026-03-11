import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../models/fee_model.dart';
import '../../services/supabase_service.dart';
import '../../widgets/receipt_widget.dart';

const _classOrder = ['PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];

int _classIndex(String c) {
  final idx = _classOrder.indexOf(c.toUpperCase());
  return idx >= 0 ? idx : _classOrder.length;
}

int _compareClass(String a, String b) {
  return _classIndex(a).compareTo(_classIndex(b));
}

class FeeCollectionScreen extends StatefulWidget {
  const FeeCollectionScreen({super.key});

  @override
  State<FeeCollectionScreen> createState() => _FeeCollectionScreenState();
}

class _FeeCollectionScreenState extends State<FeeCollectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            indicator: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            padding: const EdgeInsets.all(4),
            tabs: const [
              Tab(text: 'Fee Collection'),
              Tab(text: 'Class-wise Demand'),
              Tab(text: 'Date-wise'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _FeeCollectionTab(),
              _ClassWiseDemandTab(),
              _DateWiseTab(),
            ],
          ),
        ),
      ],
    );
  }
}

// ==================== Tab 1: Fee Collection (Date-wise Collection) ====================

class _FeeCollectionTab extends StatefulWidget {
  const _FeeCollectionTab();

  @override
  State<_FeeCollectionTab> createState() => _FeeCollectionTabState();
}

class _FeeCollectionTabState extends State<_FeeCollectionTab> with AutomaticKeepAliveClientMixin {
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  bool _isLoading = false;
  List<Map<String, dynamic>> _payments = [];
  List<_DateGroup> _dateGroups = [];
  String? _selectedDate; // null = date list, non-null = drilldown
  int? _selectedPayId; // null = payment list, non-null = fee detail drilldown
  Map<String, dynamic>? _selectedPayment; // selected payment data
  List<Map<String, dynamic>>? _feeDetails;
  bool _loadingFeeDetails = false;
  // Card drilldowns
  bool _showPendingFees = false;
  bool _showTotalCollection = false;
  bool _showTodayCollection = false;
  String? _selectedPendingFeeGroup; // null = group list, non-null = student drilldown
  List<Map<String, dynamic>> _demands = [];
  bool _isLoadingDemands = false;
  Map<int, String> _feeGroupMap = {};
  Map<int, String> _stuIdToName = {};
  Map<String, String> _admNoToName = {};
  String? _pendingFeeTypeFilter;
  String? _pendingClassFilter;
  String _pendingSearchQuery = '';
  int _pendingPage = 0;
  static const int _pendingPageSize = 10;
  String _pendingStudentSearch = '';
  final TextEditingController _pendingStudentSearchController = TextEditingController();
  // Student drilldown
  String? _selectedStudentKey;
  List<Map<String, dynamic>>? _selectedStudentDemands;
  // Collection drilldown filters
  String? _collectionMethodFilter;
  String? _collectionClassFilter;
  String _collectionSearchQuery = '';
  // Date drilldown filters
  String _dateDrilldownSearch = '';
  String? _dateDrilldownMethodFilter;
  // Institution info for receipt
  String? _insName;
  String? _insAddress;
  String? _insLogoUrl;
  String? _insMobile;
  String? _insEmail;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _loadInsInfo();
  }

  Future<void> _loadInsInfo() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    final info = await SupabaseService.getInstitutionInfo(insId);
    if (mounted) {
      setState(() {
        _insName = info.name;
        _insAddress = info.address;
        _insLogoUrl = info.logo;
        _insMobile = info.mobile;
        _insEmail = info.email;
      });
    }
  }

  @override
  void dispose() {
    _pendingStudentSearchController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);

    // Stage 1: Fast — payments + fee group map (no pagination loops)
    final fastResults = await Future.wait([
      SupabaseService.getPaymentsByDateRange(insId, fromDate: _fromDate, toDate: _toDate),
      SupabaseService.getFeeGroupMap(insId),
    ]);

    final payments = fastResults[0] as List<Map<String, dynamic>>;
    final feeGroupMap = fastResults[1] as Map<int, String>;

    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    double todayCollection = 0;
    for (final p in payments) {
      final payDate = _extractDate(p['paydate']);
      if (payDate == todayStr) {
        todayCollection += (p['transtotalamount'] as num?)?.toDouble() ?? 0;
      }
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final p in payments) {
      final dateStr = _extractDate(p['paydate']);
      grouped.putIfAbsent(dateStr, () => []).add(p);
    }

    final dateGroups = grouped.entries.map((e) {
      double total = 0;
      for (final p in e.value) {
        total += (p['transtotalamount'] as num?)?.toDouble() ?? 0;
      }
      return _DateGroup(date: e.key, payments: e.value, totalAmount: total);
    }).toList();
    dateGroups.sort((a, b) => b.date.compareTo(a.date));

    // Show table immediately — no waiting for heavy data
    if (mounted) {
      setState(() {
        _payments = payments;
        _dateGroups = dateGroups;
        _todayCollection = todayCollection;
        _feeGroupMap = feeGroupMap;
        _isLoading = false;
      });
    }

    // Stage 2: Background — demands + student names + server-side fee summary
    if (mounted) setState(() => _isLoadingDemands = true);
    final slowResults = await Future.wait([
      SupabaseService.getFeeDemands(insId),
      SupabaseService.getStudentNameMap(insId),
      SupabaseService.getFeeSummary(insId),
    ]);

    final demands = slowResults[0] as List<Map<String, dynamic>>;
    final studentNameMap = slowResults[1] as Map<int, Map<String, String>>;
    final feeSummary = slowResults[2] as FeeSummary;

    // Use server-side total to avoid row-limit discrepancies
    double pendingFees = feeSummary.totalPending;

    final stuIdToName = <int, String>{};
    final admNoToName = <String, String>{};
    for (final entry in studentNameMap.entries) {
      stuIdToName[entry.key] = entry.value['stuname'] ?? '';
      admNoToName[entry.value['stuadmno'] ?? ''] = entry.value['stuname'] ?? '';
    }

    if (mounted) {
      setState(() {
        _demands = demands;
        _pendingFees = pendingFees;
        _stuIdToName = stuIdToName;
        _admNoToName = admNoToName;
        _isLoadingDemands = false;
      });
    }
  }

  String _extractDate(dynamic paydate) {
    if (paydate == null) return 'Unknown';
    try {
      final dt = DateTime.parse(paydate.toString());
      return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return paydate.toString().split('T').first;
    }
  }

  String _formatDisplayDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
      ];
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  String _formatCurrency(double amount) {
    final str = amount.toStringAsFixed(0);
    final pattern = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = str.replaceAllMapped(pattern, (m) => '${m[1]},');
    return '₹$formatted';
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
      _fetchData();
    }
  }

  String _formatTime(dynamic timestamp) {
    if (timestamp == null) return '-';
    try {
      final dt = DateTime.parse(timestamp.toString());
      final hour = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
      final amPm = dt.hour >= 12 ? 'PM' : 'AM';
      return '${hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')} $amPm';
    } catch (_) {
      return '-';
    }
  }

  String _formatFilterDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  double _pendingFees = 0;
  double _todayCollection = 0;

  double get _totalCollection => _payments.fold(0.0, (sum, p) => sum + ((p['transtotalamount'] as num?)?.toDouble() ?? 0));

  Widget _buildDateChip(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(_formatFilterDate(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilter(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ),
    );
  }

  Widget _buildSummaryCard(IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }


  @override
  Widget build(BuildContext context) {
    super.build(context);

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Date filter bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Text('Date Range:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  _buildDateChip('From', _fromDate, () => _pickDate(true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('—', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  _buildDateChip('To', _toDate, () => _pickDate(false)),
                  const SizedBox(width: 12),
                  _buildQuickFilter('Today', () {
                    setState(() {
                      _fromDate = DateTime.now();
                      _toDate = DateTime.now();
                    });
                    _fetchData();
                  }),
                  const SizedBox(width: 6),
                  _buildQuickFilter('7 Days', () {
                    setState(() {
                      _toDate = DateTime.now();
                      _fromDate = DateTime.now().subtract(const Duration(days: 7));
                    });
                    _fetchData();
                  }),
                  const SizedBox(width: 6),
                  _buildQuickFilter('30 Days', () {
                    setState(() {
                      _toDate = DateTime.now();
                      _fromDate = DateTime.now().subtract(const Duration(days: 30));
                    });
                    _fetchData();
                  }),
                  const SizedBox(width: 6),
                  _buildQuickFilter('This Month', () {
                    final now = DateTime.now();
                    setState(() {
                      _fromDate = DateTime(now.year, now.month, 1);
                      _toDate = now;
                    });
                    _fetchData();
                  }),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
                    onPressed: _fetchData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Summary cards
            Row(
              children: [
                _buildClickableSummaryCard(Icons.currency_rupee, AppColors.accent, _formatCurrency(_totalCollection), 'Total Collection', () {
                  setState(() {
                    _showTotalCollection = true;
                    _showTodayCollection = false;
                    _showPendingFees = false;
                    _selectedDate = null;
                    _selectedPayId = null;
                  });
                }),
                const SizedBox(width: 16),
                _buildClickableSummaryCard(Icons.today_rounded, Colors.blue, _formatCurrency(_todayCollection), 'Today Collection', () {
                  setState(() {
                    _showTodayCollection = true;
                    _showTotalCollection = false;
                    _showPendingFees = false;
                    _selectedDate = null;
                    _selectedPayId = null;
                  });
                }),
                const SizedBox(width: 16),
                _buildClickableSummaryCard(Icons.pending_actions_rounded, Colors.orange, _isLoadingDemands ? 'Loading...' : _formatCurrency(_pendingFees), 'Pending Fees', () {
                  setState(() {
                    _showPendingFees = true;
                    _showTotalCollection = false;
                    _showTodayCollection = false;
                    _selectedDate = null;
                    _selectedPayId = null;
                    _pendingFeeTypeFilter = null;
                    _pendingClassFilter = null;
                  });
                }),
              ],
            ),
            const SizedBox(height: 16),
            // Show drilldown or date list based on selection
            if (_showTotalCollection)
              _buildCollectionDrilldown(false)
            else if (_showTodayCollection)
              _buildCollectionDrilldown(true)
            else if (_showPendingFees)
              _buildPendingFeesView()
            else if (_selectedPayId != null && _selectedDate != null)
              _buildFeeDetailDrilldown()
            else if (_selectedDate != null)
              _buildDateDrilldown(_dateGroups.firstWhere(
                (g) => g.date == _selectedDate,
                orElse: () => _dateGroups.first,
              ))
            else
              _buildDateList(),
          ],
        ),
      ),
    );
  }

  Widget _buildCollectionDrilldown(bool todayOnly) {
    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';

    // Base filter: today or all
    var basePayments = todayOnly
        ? _payments.where((p) => _extractDate(p['paydate']) == todayStr).toList()
        : List<Map<String, dynamic>>.from(_payments);

    // Get unique methods and classes for dropdowns (before applying filters)
    final methods = basePayments.map((p) => p['paymethod']?.toString() ?? 'Unknown').toSet().toList()..sort();
    // Get classes from student map via stu_id -> demand stuclass
    final classSet = <String>{};
    for (final p in basePayments) {
      final stuId = p['stu_id'] as int?;
      if (stuId != null) {
        final demand = _demands.firstWhere((d) => d['stu_id'] == stuId, orElse: () => {});
        final cls = demand['stuclass']?.toString();
        if (cls != null && cls.isNotEmpty) classSet.add(cls);
      }
    }
    final classes = classSet.toList()..sort(_compareClass);

    // Apply filters
    final filtered = basePayments.where((p) {
      if (_collectionMethodFilter != null && (p['paymethod']?.toString() ?? 'Unknown') != _collectionMethodFilter) return false;
      if (_collectionClassFilter != null) {
        final stuId = p['stu_id'] as int?;
        if (stuId == null) return false;
        final demand = _demands.firstWhere((d) => d['stu_id'] == stuId, orElse: () => {});
        if (demand['stuclass']?.toString() != _collectionClassFilter) return false;
      }
      if (_collectionSearchQuery.isNotEmpty) {
        final query = _collectionSearchQuery.toLowerCase();
        final stuId = p['stu_id'] as int?;
        final stuName = (stuId != null && _stuIdToName.containsKey(stuId)) ? _stuIdToName[stuId]! : '';
        final payNo = p['paynumber']?.toString() ?? '';
        final admNo = p['stuadmno']?.toString() ?? '';
        if (!stuName.toLowerCase().contains(query) && !payNo.toLowerCase().contains(query) && !admNo.toLowerCase().contains(query)) return false;
      }
      return true;
    }).toList();

    // Group by payment method
    final Map<String, List<Map<String, dynamic>>> byMethod = {};
    for (final p in filtered) {
      final method = p['paymethod']?.toString() ?? 'Unknown';
      byMethod.putIfAbsent(method, () => []).add(p);
    }
    final methodKeys = byMethod.keys.toList()..sort();

    // Totals
    double total = 0;
    int totalCount = 0;
    final allStuIds = <String>{};
    for (final p in filtered) {
      total += (p['transtotalamount'] as num?)?.toDouble() ?? 0;
      totalCount++;
      final sid = p['stu_id']?.toString();
      if (sid != null) allStuIds.add(sid);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back + header + filters
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () => setState(() {
                _showTotalCollection = false;
                _showTodayCollection = false;
                _collectionMethodFilter = null;
                _collectionClassFilter = null;
                _collectionSearchQuery = '';
              }),
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            Text(
              todayOnly ? 'Today Collection' : 'Total Collection',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            if (todayOnly) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(todayStr, style: const TextStyle(fontSize: 11, color: Colors.blue, fontWeight: FontWeight.w500)),
              ),
            ],
            const Spacer(),
            // Search field
            SizedBox(
              width: 180,
              height: 34,
              child: TextField(
                onChanged: (v) => setState(() => _collectionSearchQuery = v),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search student / pay no...',
                  hintStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Payment Method dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _collectionMethodFilter,
                  hint: const Text('All Methods', style: TextStyle(fontSize: 12)),
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Methods')),
                    ...methods.map((m) => DropdownMenuItem<String?>(value: m, child: Text(m))),
                  ],
                  onChanged: (v) => setState(() => _collectionMethodFilter = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Class dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _collectionClassFilter,
                  hint: const Text('All Classes', style: TextStyle(fontSize: 12)),
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Classes')),
                    ...classes.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() => _collectionClassFilter = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Summary row
        Row(
          children: [
            _buildSummaryCard(Icons.receipt_long, AppColors.accent, '$totalCount', 'Transactions'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.people_alt_outlined, Colors.blue, '${allStuIds.length}', 'Students'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.currency_rupee, AppColors.success, _formatCurrency(total), 'Total Amount'),
          ],
        ),
        const SizedBox(height: 12),
        // Payment method-wise table
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.payment_rounded, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    const Text('Method-wise Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${methodKeys.length} methods', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (methodKeys.isEmpty)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No collections found', style: TextStyle(color: AppColors.textSecondary))))
              else
                LayoutBuilder(builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
                        headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 40, dataRowMaxHeight: 44, headingRowHeight: 42,
                        columns: const [
                          DataColumn(label: Text('S No.')),
                          DataColumn(label: Text('PAYMENT METHOD')),
                          DataColumn(label: Text('TRANSACTIONS'), numeric: true),
                          DataColumn(label: Text('STUDENTS'), numeric: true),
                          DataColumn(label: Text('AMOUNT'), numeric: true),
                        ],
                        rows: [
                          ...methodKeys.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final method = entry.value;
                            final items = byMethod[method]!;
                            double mTotal = 0;
                            final mStuIds = <String>{};
                            for (final p in items) {
                              mTotal += (p['transtotalamount'] as num?)?.toDouble() ?? 0;
                              final sid = p['stu_id']?.toString();
                              if (sid != null) mStuIds.add(sid);
                            }
                            return DataRow(cells: [
                              DataCell(Text('${idx + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                              DataCell(Text(method, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text('${items.length}')),
                              DataCell(Text('${mStuIds.length}')),
                              DataCell(Text(_formatCurrency(mTotal), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success))),
                            ]);
                          }),
                          DataRow(color: WidgetStateProperty.all(const Color(0xFF2D3748)), cells: [
                            const DataCell(Text('')),
                            DataCell(Text('GRAND TOTAL', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                            DataCell(Text('$totalCount', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text('${allStuIds.length}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text(_formatCurrency(total), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Individual payment list
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.receipt_long, size: 18, color: AppColors.accent),
                    const SizedBox(width: 8),
                    const Text('Payment Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${filtered.length} records', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (filtered.isEmpty)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No payments found', style: TextStyle(color: AppColors.textSecondary))))
              else
                LayoutBuilder(builder: (context, constraints) {
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
                        headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
                        columns: const [
                          DataColumn(label: Text('S No.')),
                          DataColumn(label: Text('PAY NO')),
                          DataColumn(label: Text('STUDENT')),
                          DataColumn(label: Text('DATE')),
                          DataColumn(label: Text('METHOD')),
                          DataColumn(label: Text('AMOUNT'), numeric: true),
                        ],
                        rows: [
                          ...filtered.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final p = entry.value;
                            final stuId = p['stu_id'] as int?;
                            final stuName = (stuId != null && _stuIdToName.containsKey(stuId))
                                ? _stuIdToName[stuId]!
                                : (p['stuadmno']?.toString() ?? '-');
                            final amount = (p['transtotalamount'] as num?)?.toDouble() ?? 0;
                            return DataRow(cells: [
                              DataCell(Text('${idx + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                              DataCell(Text(p['paynumber']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
                              DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: Text(stuName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)))),
                              DataCell(Text(_formatDate(p['paydate']))),
                              DataCell(Text(p['paymethod']?.toString() ?? '-')),
                              DataCell(Text(_formatCurrency(amount), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success))),
                            ]);
                          }),
                          DataRow(color: WidgetStateProperty.all(const Color(0xFF2D3748)), cells: [
                            const DataCell(Text('')),
                            DataCell(Text('GRAND TOTAL', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            DataCell(Text(_formatCurrency(total), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dt = DateTime.parse(date.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return '-';
    }
  }

  Widget _buildClickableSummaryCard(IconData icon, Color iconColor, String value, String label, VoidCallback onTap) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: iconColor.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(color: iconColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: iconColor),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingFeesView() {
    if (_isLoadingDemands) {
      return const Center(child: CircularProgressIndicator());
    }
    // Rows with pending balance (for student drilldown)
    final pendingDemands = _demands.where((d) {
      final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
      return balance > 0;
    }).toList();

    // All rows with non-zero net demand (for group table — shows all fee groups including fully paid)
    final activeDemands = _demands.where((d) {
      final fee = (d['feeamount'] as num?)?.toDouble() ?? 0;
      final con = (d['conamount'] as num?)?.toDouble() ?? 0;
      return fee - con > 0;
    }).toList();

    // Get unique fee types and classes for dropdowns
    final feeTypes = activeDemands.map((d) => d['demfeetype']?.toString() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
    final classes = activeDemands.map((d) => d['stuclass']?.toString() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort(_compareClass);

    // Apply filters to active demands (for group table)
    final filtered = activeDemands.where((d) {
      if (_pendingFeeTypeFilter != null && d['demfeetype']?.toString() != _pendingFeeTypeFilter) return false;
      if (_pendingClassFilter != null && d['stuclass']?.toString() != _pendingClassFilter) return false;
      if (_pendingSearchQuery.isNotEmpty) {
        final query = _pendingSearchQuery.toLowerCase();
        final stuName = _getStudentName(d).toLowerCase();
        final admNo = d['stuadmno']?.toString().toLowerCase() ?? '';
        if (!stuName.contains(query) && !admNo.contains(query)) return false;
      }
      return true;
    }).toList();

    // Group by fee group (all active — for table display)
    final Map<String, List<Map<String, dynamic>>> groupedByFeeGroup = {};
    for (final d in filtered) {
      final feeId = d['fee_id'] as int?;
      final groupName = (feeId != null && _feeGroupMap.containsKey(feeId))
          ? _feeGroupMap[feeId]!
          : 'Uncategorized';
      groupedByFeeGroup.putIfAbsent(groupName, () => []).add(d);
    }

    final groupKeys = groupedByFeeGroup.keys.toList()..sort();

    // If a fee group is selected, show student drilldown (only pending students)
    if (_selectedPendingFeeGroup != null && groupedByFeeGroup.containsKey(_selectedPendingFeeGroup)) {
      final drilldownDemands = (groupedByFeeGroup[_selectedPendingFeeGroup] ?? [])
          .where((d) => ((d['balancedue'] as num?)?.toDouble() ?? 0) > 0)
          .toList();
      return _buildPendingStudentList(_selectedPendingFeeGroup!, drilldownDemands, feeTypes, classes);
    }

    // Compute totals — use all demands for demand (not just pending-filtered)
    // so fully-paid students don't vanish from the summary
    // Balance uses server-side _pendingFees to avoid row-limit discrepancies
    double totalDemand = 0;
    for (final d in _demands) {
      totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
    }
    final double totalBalance = _pendingFees;
    // Total paid = total collection from payment table (already loaded)
    final double totalPaid = _payments.fold(0.0, (s, p) => s + ((p['transtotalamount'] as num?)?.toDouble() ?? 0));
    // Student count = pending students only
    final allStuIds = <String>{};
    for (final d in pendingDemands) {
      final stuId = d['stu_id']?.toString();
      if (stuId != null) allStuIds.add(stuId);
    }
    final int totalStudents = allStuIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button + header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () => setState(() {
                _showPendingFees = false;
                _pendingSearchQuery = '';
                _pendingFeeTypeFilter = null;
                _pendingClassFilter = null;
                _selectedPendingFeeGroup = null;
                _selectedStudentKey = null;
                _selectedStudentDemands = null;
              }),
              tooltip: 'Back',
            ),
            const SizedBox(width: 4),
            const Text('Pending Fees', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            // Search field
            SizedBox(
              width: 180,
              height: 34,
              child: TextField(
                onChanged: (v) => setState(() => _pendingSearchQuery = v),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search student / adm no...',
                  hintStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Fee Type dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _pendingFeeTypeFilter,
                  hint: const Text('All Fee Types', style: TextStyle(fontSize: 12)),
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Fee Types')),
                    ...feeTypes.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                  ],
                  onChanged: (v) => setState(() => _pendingFeeTypeFilter = v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Class dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _pendingClassFilter,
                  hint: const Text('All Classes', style: TextStyle(fontSize: 12)),
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Classes')),
                    ...classes.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() => _pendingClassFilter = v),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Summary row
        Row(
          children: [
            _buildSummaryCard(Icons.people_alt_outlined, Colors.blue, totalStudents.toString(), 'Students'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.account_balance_wallet, AppColors.accent, _formatCurrency(totalDemand), 'Total Demand'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.check_circle_outline, AppColors.success, _formatCurrency(totalPaid), 'Total Paid'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.pending_outlined, Colors.orange, _formatCurrency(totalBalance), 'Balance Due'),
          ],
        ),
        const SizedBox(height: 12),
        // Fee group-wise table
        LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('FEE GROUP')),
                DataColumn(label: Text('STUDENTS'), numeric: true),
                DataColumn(label: Text('TOTAL DEMAND'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
              ],
              rows: groupKeys.isEmpty ? [
                const DataRow(cells: [
                  DataCell(Text('')), DataCell(Text('No pending fees found')), DataCell(Text('')),
                  DataCell(Text('')), DataCell(Text('')), DataCell(Text('')),
                ]),
              ] : [
                ...groupKeys.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final groupName = entry.value;
                  final items = groupedByFeeGroup[groupName]!;
                  double gDemand = 0, gPaid = 0, gBalance = 0;
                  final gStuIds = <String>{};
                  for (final d in items) {
                    gDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
                    gPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
                    gBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
                    if (((d['balancedue'] as num?)?.toDouble() ?? 0) > 0) {
                      final sid = d['stu_id']?.toString();
                      if (sid != null) gStuIds.add(sid);
                    }
                  }
                  return DataRow(
                    cells: [
                      DataCell(Text('${idx + 1}')),
                      DataCell(InkWell(
                        onTap: () => setState(() => _selectedPendingFeeGroup = groupName),
                        child: Row(children: [
                          Flexible(child: Text(groupName, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent))),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(5)),
                            child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                          ),
                        ]),
                      )),
                      DataCell(Text('${gStuIds.length}')),
                      DataCell(Text(_formatCurrency(gDemand))),
                      DataCell(Text(_formatCurrency(gPaid), style: const TextStyle(color: AppColors.success))),
                      DataCell(Text(_formatCurrency(gBalance), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange))),
                    ],
                  );
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text('$totalStudents', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalDemand), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalPaid), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalBalance), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                  ],
                ),
              ],
            ),
          ));
        }),
      ],
    );
  }

  Widget _buildStudentFeeDrilldown() {
    final demands = _selectedStudentDemands!;
    final first = demands.first;
    final admNo = first['stuadmno']?.toString() ?? '-';
    final stuName = _getStudentName(first);
    final stuClass = first['stuclass']?.toString() ?? '-';

    double totalDemand = 0, totalPaid = 0, totalBalance = 0;
    for (final d in demands) {
      totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
      totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
      totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back + student info header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () => setState(() {
                _selectedStudentKey = null;
                _selectedStudentDemands = null;
              }),
              tooltip: 'Back',
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(stuName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const SizedBox(height: 2),
                Text('Adm No: $admNo  |  Class: $stuClass', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Summary cards
        Row(
          children: [
            _buildSummaryCard(Icons.account_balance_wallet, AppColors.accent, _formatCurrency(totalDemand), 'Total Demand'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.check_circle_outline, AppColors.success, _formatCurrency(totalPaid), 'Total Paid'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.pending_outlined, Colors.orange, _formatCurrency(totalBalance), 'Balance Due'),
          ],
        ),
        const SizedBox(height: 12),
        // Fee details table
        LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('TERM')),
                DataColumn(label: Text('FEE TYPE')),
                DataColumn(label: Text('FEE AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Text('STATUS')),
              ],
              rows: [
                ...List.generate(demands.length, (i) {
                  final d = demands[i];
                  final term = d['demfeeterm']?.toString() ?? '-';
                  final feeGroupName = _feeGroupMap[d['fee_id'] as int?] ?? (d['demfeetype']?.toString() ?? '-');
                  final amount = (d['feeamount'] as num?)?.toDouble() ?? 0;
                  final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
                  final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  final isPaid = balance <= 0;
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(term)),
                    DataCell(Text(feeGroupName, style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(Text(_formatCurrency(amount))),
                    DataCell(Text(_formatCurrency(paid), style: const TextStyle(color: AppColors.success))),
                    DataCell(Text(_formatCurrency(balance), style: TextStyle(fontWeight: FontWeight.w600, color: balance > 0 ? Colors.orange : AppColors.textSecondary))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPaid ? AppColors.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(isPaid ? 'Paid' : 'Unpaid', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : Colors.red)),
                    )),
                  ]);
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalDemand), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalPaid), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalBalance), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ));
        }),
      ],
    );
  }

  Widget _buildPendingStudentList(String feeGroupName, List<Map<String, dynamic>> groupDemands, List<String> feeTypes, List<String> classes) {
    // Group by student
    final Map<String, List<Map<String, dynamic>>> byStudent = {};
    for (final d in groupDemands) {
      final key = d['stu_id']?.toString() ?? d['stuadmno']?.toString() ?? 'Unknown';
      byStudent.putIfAbsent(key, () => []).add(d);
    }

    var studentKeys = byStudent.keys.toList();
    // Sort by class first, then by student name
    studentKeys.sort((a, b) {
      final classA = byStudent[a]!.first['stuclass']?.toString() ?? '';
      final classB = byStudent[b]!.first['stuclass']?.toString() ?? '';
      final classCmp = _compareClass(classA, classB);
      if (classCmp != 0) return classCmp;
      final nameA = _getStudentName(byStudent[a]!.first);
      final nameB = _getStudentName(byStudent[b]!.first);
      return nameA.compareTo(nameB);
    });

    // Apply student search filter
    if (_pendingStudentSearch.isNotEmpty) {
      final query = _pendingStudentSearch.toLowerCase();
      studentKeys = studentKeys.where((key) {
        final demands = byStudent[key]!;
        final stuName = _getStudentName(demands.first).toLowerCase();
        final admNo = demands.first['stuadmno']?.toString().toLowerCase() ?? '';
        return stuName.contains(query) || admNo.contains(query);
      }).toList();
    }

    // Compute totals (from all filtered students)
    double totalDemand = 0, totalPaid = 0, totalBalance = 0;
    for (final key in studentKeys) {
      for (final d in byStudent[key]!) {
        totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
        totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
        totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
      }
    }

    // Pagination
    final totalStudents = studentKeys.length;
    final totalPages = (totalStudents / _pendingPageSize).ceil();
    if (_pendingPage >= totalPages && totalPages > 0) {
      _pendingPage = totalPages - 1;
    }
    final startIdx = _pendingPage * _pendingPageSize;
    final endIdx = (startIdx + _pendingPageSize).clamp(0, totalStudents);
    final pagedKeys = studentKeys.sublist(startIdx, endIdx);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button + header
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, size: 20),
              onPressed: () => setState(() {
                _selectedPendingFeeGroup = null;
                _pendingStudentSearch = '';
                _pendingPage = 0;
              }),
              tooltip: 'Back to Fee Groups',
            ),
            const SizedBox(width: 4),
            Text('Pending Fees', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 16, color: AppColors.textSecondary),
            const SizedBox(width: 4),
            Text(feeGroupName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            // Search field
            SizedBox(
              width: 220,
              height: 34,
              child: TextField(
                controller: _pendingStudentSearchController,
                onChanged: (v) => setState(() {
                  _pendingStudentSearch = v;
                  _pendingPage = 0;
                }),
                style: const TextStyle(fontSize: 12),
                decoration: InputDecoration(
                  hintText: 'Search student / adm no...',
                  hintStyle: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  suffixIcon: _pendingStudentSearch.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: () => setState(() {
                            _pendingStudentSearchController.clear();
                            _pendingStudentSearch = '';
                            _pendingPage = 0;
                          }),
                          splashRadius: 14,
                          padding: EdgeInsets.zero,
                        )
                      : null,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Fee Type dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _pendingFeeTypeFilter,
                  hint: const Text('All Fee Types', style: TextStyle(fontSize: 12)),
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Fee Types')),
                    ...feeTypes.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                  ],
                  onChanged: (v) => setState(() { _pendingFeeTypeFilter = v; _pendingPage = 0; }),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Class dropdown
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String?>(
                  value: _pendingClassFilter,
                  hint: const Text('All Classes', style: TextStyle(fontSize: 12)),
                  style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                  icon: const Icon(Icons.arrow_drop_down, size: 18),
                  isDense: true,
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('All Classes')),
                    ...classes.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                  ],
                  onChanged: (v) => setState(() { _pendingClassFilter = v; _pendingPage = 0; }),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Summary row
        Row(
          children: [
            _buildSummaryCard(Icons.people_alt_outlined, Colors.blue, '$totalStudents', 'Students'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.account_balance_wallet, AppColors.accent, _formatCurrency(totalDemand), 'Total Demand'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.check_circle_outline, AppColors.success, _formatCurrency(totalPaid), 'Total Paid'),
            const SizedBox(width: 12),
            _buildSummaryCard(Icons.pending_outlined, Colors.orange, _formatCurrency(totalBalance), 'Balance Due'),
          ],
        ),
        const SizedBox(height: 12),
        // Student table
        LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('ADM NO')),
                DataColumn(label: Text('STUDENT NAME')),
                DataColumn(label: Text('CLASS')),
                DataColumn(label: Text('FEE AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Text('STATUS')),
              ],
              rows: pagedKeys.isEmpty ? [
                const DataRow(cells: [
                  DataCell(Text('')), DataCell(Text('No students found')), DataCell(Text('')), DataCell(Text('')),
                  DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')),
                ]),
              ] : [
                ...pagedKeys.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final stuKey = entry.value;
                  final demands = byStudent[stuKey]!;
                  final first = demands.first;
                  final admNo = first['stuadmno']?.toString() ?? '-';
                  final stuName = _getStudentName(first);
                  final stuClass = first['stuclass']?.toString() ?? '-';
                  double sDemand = 0, sPaid = 0, sBalance = 0;
                  for (final d in demands) {
                    sDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
                    sPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
                    sBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
                  }
                  final isPaid = sBalance <= 0;
                  return DataRow(
                    cells: [
                      DataCell(Text('${startIdx + idx + 1}')),
                      DataCell(Text(admNo)),
                      DataCell(InkWell(
                        onTap: () => setState(() {
                          _selectedStudentKey = stuKey;
                          _selectedStudentDemands = demands;
                        }),
                        child: Row(children: [
                          Flexible(child: Text(stuName, style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.accent))),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                            decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(5)),
                            child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                          ),
                        ]),
                      )),
                      DataCell(Text(stuClass)),
                      DataCell(Text(_formatCurrency(sDemand))),
                      DataCell(Text(_formatCurrency(sPaid), style: const TextStyle(color: AppColors.success))),
                      DataCell(Text(_formatCurrency(sBalance), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange))),
                      DataCell(Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: isPaid ? AppColors.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(isPaid ? 'Paid' : 'Unpaid', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : Colors.red)),
                      )),
                    ],
                  );
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    const DataCell(Text('')),
                    DataCell(Text(_formatCurrency(totalDemand), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalPaid), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(totalBalance), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ));
        }),
        const SizedBox(height: 8),
        // Pagination footer
        Row(
          children: [
            Text(
              'Showing ${totalStudents == 0 ? 0 : startIdx + 1}–$endIdx of $totalStudents students',
              style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.first_page_rounded, size: 20),
              onPressed: _pendingPage > 0 ? () => setState(() => _pendingPage = 0) : null,
              tooltip: 'First page', splashRadius: 18,
            ),
            IconButton(
              icon: const Icon(Icons.chevron_left_rounded, size: 20),
              onPressed: _pendingPage > 0 ? () => setState(() => _pendingPage--) : null,
              tooltip: 'Previous page', splashRadius: 18,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
              child: Text('${_pendingPage + 1} / ${totalPages == 0 ? 1 : totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right_rounded, size: 20),
              onPressed: _pendingPage < totalPages - 1 ? () => setState(() => _pendingPage++) : null,
              tooltip: 'Next page', splashRadius: 18,
            ),
            IconButton(
              icon: const Icon(Icons.last_page_rounded, size: 20),
              onPressed: _pendingPage < totalPages - 1 ? () => setState(() => _pendingPage = totalPages - 1) : null,
              tooltip: 'Last page', splashRadius: 18,
            ),
          ],
        ),
      ],
    );
  }

  String _getStudentName(Map<String, dynamic> demand) {
    final stuId = demand['stu_id'] as int?;
    if (stuId != null && _stuIdToName.containsKey(stuId)) {
      return _stuIdToName[stuId]!;
    }
    final admNo = demand['stuadmno']?.toString() ?? '';
    if (admNo.isNotEmpty && _admNoToName.containsKey(admNo)) {
      return _admNoToName[admNo]!;
    }
    // Try flat stuname from RPC
    final flatName = demand['stuname']?.toString();
    if (flatName != null && flatName.isNotEmpty) return flatName;
    // Try nested student data from old join
    final students = demand['students'];
    if (students is Map && students['stuname'] != null) {
      return students['stuname'].toString();
    }
    return admNo.isNotEmpty ? admNo : '-';
  }

  Widget _buildDateList() {
    final double grandTotal = _dateGroups.fold(0.0, (s, g) => s + g.totalAmount);
    final int grandTransactions = _dateGroups.fold(0, (s, g) => s + g.payments.length);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.description_outlined, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text('Date-wise Collection Summary', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                const Spacer(),
                Text('${_dateGroups.length} days', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_dateGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.search_off, size: 40, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                    const SizedBox(height: 8),
                    const Text('No collections found for selected date range', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
                      headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      columnSpacing: 20,
                      horizontalMargin: 16,
                      dataRowMinHeight: 40,
                      dataRowMaxHeight: 44,
                      headingRowHeight: 42,
                      columns: const [
                        DataColumn(label: Text('S No.')),
                        DataColumn(label: Text('DATE')),
                        DataColumn(label: Text('TRANSACTIONS'), numeric: true),
                        DataColumn(label: Text('AMOUNT'), numeric: true),
                        DataColumn(label: Text('ACTION')),
                      ],
                      rows: [
                        ...List.generate(_dateGroups.length, (i) {
                          final group = _dateGroups[i];
                          return DataRow(
                            onSelectChanged: (_) => setState(() => _selectedDate = group.date),
                            cells: [
                              DataCell(Text('${i + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                              DataCell(Text(_formatDisplayDate(group.date), style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text('${group.payments.length}', textAlign: TextAlign.right)),
                              DataCell(Text(_formatCurrency(group.totalAmount), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success))),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                  Text('View Details', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                  SizedBox(width: 4),
                                  Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                                ]),
                              )),
                            ],
                          );
                        }),
                        // Grand total row
                        DataRow(
                          color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                          cells: [
                            const DataCell(Text('')),
                            DataCell(Text('GRAND TOTAL', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                            DataCell(Text('$grandTransactions', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text(_formatCurrency(grandTotal), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                            const DataCell(Text('')),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Future<void> _onPaymentTap(Map<String, dynamic> payment) async {
    final payId = payment['pay_id'] as int?;
    if (payId == null) return;

    setState(() {
      _selectedPayId = payId;
      _selectedPayment = payment;
      _loadingFeeDetails = true;
      _feeDetails = null;
    });

    final auth = context.read<AuthProvider>();
    final details = await SupabaseService.getFeeDetailsByPayId(payId, insId: auth.insId);
    if (mounted) {
      setState(() {
        _feeDetails = details;
        _loadingFeeDetails = false;
      });
    }
  }

  Widget _buildDateDrilldown(_DateGroup group) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _selectedDate = null;
                    _selectedPayId = null;
                    _selectedPayment = null;
                    _feeDetails = null;
                    _dateDrilldownSearch = '';
                    _dateDrilldownMethodFilter = null;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => setState(() {
                    _selectedDate = null;
                    _selectedPayId = null;
                    _selectedPayment = null;
                    _feeDetails = null;
                    _dateDrilldownSearch = '';
                    _dateDrilldownMethodFilter = null;
                  }),
                  child: const Text('Date-wise Collection', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                ),
                const Text('  >  ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                Text(_formatDisplayDate(group.date), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${group.payments.length} payments',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent),
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 200,
                  height: 34,
                  child: TextField(
                    onChanged: (v) => setState(() => _dateDrilldownSearch = v),
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  height: 34,
                  child: DropdownButtonHideUnderline(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: DropdownButton<String?>(
                        value: _dateDrilldownMethodFilter,
                        hint: const Text('All Methods', style: TextStyle(fontSize: 12)),
                        style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        items: [
                          const DropdownMenuItem(value: null, child: Text('All Methods')),
                          ...{for (final p in group.payments) p['paymethod']?.toString() ?? '-'}.map(
                            (m) => DropdownMenuItem(value: m, child: Text(m)),
                          ),
                        ],
                        onChanged: (v) => setState(() => _dateDrilldownMethodFilter = v),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
                LayoutBuilder(builder: (context, constraints) {
                  final searchLower = _dateDrilldownSearch.toLowerCase();
                  final filtered = group.payments.where((p) {
                    if (_dateDrilldownMethodFilter != null && (p['paymethod']?.toString() ?? '-') != _dateDrilldownMethodFilter) return false;
                    if (searchLower.isNotEmpty) {
                      final s = p['students'] as Map<String, dynamic>?;
                      final name = (s?['stuname']?.toString() ?? '').toLowerCase();
                      final admNo = (s?['stuadmno']?.toString() ?? '').toLowerCase();
                      final payNo = (p['paynumber']?.toString() ?? '').toLowerCase();
                      if (!name.contains(searchLower) && !admNo.contains(searchLower) && !payNo.contains(searchLower)) return false;
                    }
                    return true;
                  }).toList();
                  final double grandTotal = filtered.fold(0.0, (s, p) => s + ((p['transtotalamount'] as num?)?.toDouble() ?? 0));
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
                        headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                        dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                        columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
                        columns: const [
                          DataColumn(label: Text('S No.')),
                          DataColumn(label: Text('PAY NO')),
                          DataColumn(label: Text('TIME')),
                          DataColumn(label: Text('ADMN.NO')),
                          DataColumn(label: Text('STUDENT NAME')),
                          DataColumn(label: Text('CLASS')),
                          DataColumn(label: Text('METHOD')),
                          DataColumn(label: Text('AMOUNT'), numeric: true),
                          DataColumn(label: Text('ACTION')),
                        ],
                        rows: [
                          ...List.generate(filtered.length, (i) {
                            final p = filtered[i];
                            final student = p['students'] as Map<String, dynamic>?;
                            final timeStr = _formatTime(p['createdat'] ?? p['paydate']);
                            return DataRow(
                              onSelectChanged: (_) => _onPaymentTap(p),
                              cells: [
                                DataCell(Text('${i + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(Text(p['paynumber']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
                                DataCell(Text(timeStr, style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(Text(student?['stuadmno']?.toString() ?? '-')),
                                DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: Text(student?['stuname']?.toString() ?? '-', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)))),
                                DataCell(Text(student?['stuclass']?.toString() ?? '-')),
                                DataCell(Text(p['paymethod'] ?? '-')),
                                DataCell(Text(_formatCurrency((p['transtotalamount'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success))),
                                DataCell(Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8)),
                                  child: const Row(mainAxisSize: MainAxisSize.min, children: [
                                    Text('View', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                                  ]),
                                )),
                              ],
                            );
                          }),
                          DataRow(color: WidgetStateProperty.all(const Color(0xFF2D3748)), cells: [
                            const DataCell(Text('')),
                            DataCell(Text('GRAND TOTAL', style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            DataCell(Text(_formatCurrency(grandTotal), style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white))),
                            const DataCell(Text('')),
                          ]),
                        ],
                      ),
                    ),
                  );
                }),
        ],
      ),
    );
  }

  ReceiptData _buildReceiptData(Map<String, dynamic> payment, List<Map<String, dynamic>>? feeDetails) {
    final student = payment['students'] as Map<String, dynamic>?;
    final payNo = payment['paynumber']?.toString() ?? '${payment['pay_id'] ?? '-'}';
    final stuName = student?['stuname']?.toString() ?? '-';
    final admNo = student?['stuadmno']?.toString() ?? '-';
    final stuClass = student?['stuclass']?.toString() ?? '-';
    final stuMobile = student?['stumobile']?.toString() ?? '-';
    final stuAddress = student?['stuaddress']?.toString() ?? '-';
    final payMethod = payment['paymethod']?.toString() ?? '-';
    final totalAmount = (payment['transtotalamount'] as num?)?.toDouble() ?? 0;
    final auth = context.read<AuthProvider>();

    final date = payment['paydate'] ?? payment['createdat'];
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    String dateStr = '-';
    if (date != null) {
      try {
        final dt = DateTime.parse(date.toString());
        dateStr = '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
      } catch (_) {
        dateStr = date.toString();
      }
    }

    // Build fee details grouped by term
    List<ReceiptTermDetail> termDetails = [];
    if (feeDetails != null && feeDetails.isNotEmpty) {
      const monthFeeTypes = ['TUITION FEES', 'TUITION FEE', 'VAN FEES', 'VAN FEE'];
      final termMap = <String, List<ReceiptFeeItem>>{};
      for (final d in feeDetails) {
        String term = d['demfeeterm']?.toString() ?? '-';
        final feeType = d['demfeetype']?.toString() ?? 'Fee';
        final amount = (d['feeamount'] as num?)?.toDouble() ?? 0;
        if (monthFeeTypes.contains(feeType.toUpperCase())) {
          final duedate = d['duedate'];
          if (duedate != null) {
            try {
              final dt = DateTime.parse(duedate.toString());
              term = months[dt.month - 1].toUpperCase();
            } catch (_) {}
          }
        }
        termMap.putIfAbsent(term, () => []);
        termMap[term]!.add(ReceiptFeeItem(type: feeType, amount: amount));
      }
      termDetails = termMap.entries.map((e) => ReceiptTermDetail(term: e.key, fees: e.value)).toList();
    }
    if (termDetails.isEmpty) {
      termDetails = [ReceiptTermDetail(term: '-', fees: [ReceiptFeeItem(type: 'Payment', amount: totalAmount)])];
    }

    return ReceiptData(
      receiptNo: payNo,
      date: dateStr,
      studentName: stuName,
      mobileNo: stuMobile,
      address: stuAddress,
      admissionNo: admNo,
      className: stuClass,
      schoolName: _insName ?? auth.insName ?? 'Institution',
      schoolAddress: _insAddress ?? '-',
      schoolLogoUrl: _insLogoUrl,
      schoolMobile: _insMobile,
      schoolEmail: _insEmail,
      feeDetails: termDetails,
      paymentMethod: payMethod,
      paymentDate: dateStr,
      status: 'paid',
      total: totalAmount,
    );
  }

  Future<pw.Document> _buildReceiptPdf(ReceiptData data) async {
    final font = await PdfGoogleFonts.montserratRegular();
    final fontMedium = await PdfGoogleFonts.montserratMedium();
    final fontSemiBold = await PdfGoogleFonts.montserratSemiBold();
    final fontItalic = await PdfGoogleFonts.montserratItalic();
    final fontPtSerif = await PdfGoogleFonts.pTSerifRegular();

    const primaryBlue = PdfColor.fromInt(0xFF2f5daa);
    const darkBlue = PdfColor.fromInt(0xFF010165);
    const textDark = PdfColor.fromInt(0xFF2a2a2a);
    const textMediumC = PdfColor.fromInt(0xFF4c4c4c);
    const headerBg = PdfColor.fromInt(0xFFeaeff6);
    const borderColor = PdfColor.fromInt(0xFFd9d9d9);
    const paidGreen = PdfColor.fromInt(0xFF34c759);
    const dividerColor = PdfColor.fromInt(0xFFACBEDD);

    final sSemiBold = pw.TextStyle(font: fontSemiBold, fontSize: 10, color: textDark);
    final sMedium = pw.TextStyle(font: fontMedium, fontSize: 10, color: textMediumC);
    final sMediumDark = pw.TextStyle(font: fontMedium, fontSize: 10, color: textDark);

    pw.Widget labelValue(String label, String value) {
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: sSemiBold),
          pw.SizedBox(width: 6),
          pw.Text(value, style: sMedium),
        ],
      );
    }

    pw.Widget tableCell(String text, pw.TextStyle style, {pw.Alignment alignment = pw.Alignment.center}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: alignment,
        child: pw.Text(text, style: style),
      );
    }

    pw.ImageProvider? logoImage;
    if (data.schoolLogoUrl != null) {
      try { logoImage = await networkImage(data.schoolLogoUrl!); } catch (_) {}
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(60),
        theme: pw.ThemeData.withFont(base: font, bold: fontSemiBold, italic: fontItalic),
        build: (pw.Context ctx) {
          String formatAmount(double amount) {
            if (amount == amount.truncateToDouble()) {
              return amount.toInt().toString().replaceAllMapped(
                RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
            }
            return amount.toStringAsFixed(2).replaceAllMapped(
              RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},');
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImage != null)
                          pw.SizedBox(width: 64, height: 64, child: pw.Image(logoImage, fit: pw.BoxFit.cover)),
                        if (logoImage != null) pw.SizedBox(height: 8),
                        pw.Text(data.schoolName, style: pw.TextStyle(font: fontSemiBold, fontSize: 14, color: darkBlue)),
                        pw.SizedBox(height: 6),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Address:  ', style: sSemiBold),
                            pw.Expanded(child: pw.Text(data.schoolAddress, style: sMedium, maxLines: 3)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Receipt', style: pw.TextStyle(font: fontSemiBold, fontSize: 32, color: primaryBlue)),
                      pw.SizedBox(height: 12),
                      labelValue('Receipt No:', data.receiptNo),
                      pw.SizedBox(height: 6),
                      labelValue('Date:', data.date),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Container(height: 1, color: dividerColor),
              pw.SizedBox(height: 12),
              // To section
              pw.Text('To:', style: pw.TextStyle(font: fontSemiBold, fontSize: 12, color: textDark)),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        labelValue('Name:', data.studentName),
                        pw.SizedBox(height: 6),
                        labelValue('Mobile No:', data.mobileNo),
                        pw.SizedBox(height: 6),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Address:', style: sSemiBold),
                            pw.SizedBox(width: 6),
                            pw.Expanded(child: pw.Text(data.address, style: sMedium)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      labelValue('Admission No:', data.admissionNo),
                      pw.SizedBox(height: 6),
                      labelValue('Class:', data.className),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              // Fee Table with stamp overlay
              pw.Stack(
                children: [
                  pw.Column(
                    children: [
                      pw.Table(
                        border: pw.TableBorder.all(color: borderColor, width: 0.5),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(46),
                          1: const pw.FixedColumnWidth(125),
                          2: const pw.FlexColumnWidth(),
                          3: const pw.FixedColumnWidth(120),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: headerBg),
                            children: [
                              tableCell('S.No', sSemiBold.copyWith(color: primaryBlue)),
                              tableCell('Term', sSemiBold.copyWith(color: primaryBlue)),
                              tableCell('Fee Type', sSemiBold.copyWith(color: primaryBlue)),
                              tableCell('Amount', sSemiBold.copyWith(color: primaryBlue)),
                            ],
                          ),
                          for (var i = 0; i < data.feeDetails.length; i++)
                            pw.TableRow(
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  alignment: pw.Alignment.topCenter,
                                  child: pw.Text('${i + 1}.', style: sMediumDark),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  alignment: pw.Alignment.topCenter,
                                  child: pw.Text(data.feeDetails[i].term, style: sMediumDark),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: pw.Column(
                                    children: [
                                      for (final fee in data.feeDetails[i].fees)
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                          child: pw.Text(fee.type, style: sMediumDark, textAlign: pw.TextAlign.center),
                                        ),
                                    ],
                                  ),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                                    children: [
                                      for (final fee in data.feeDetails[i].fees)
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                          child: pw.Text('\u20B9${formatAmount(fee.amount)}', style: sMediumDark, textAlign: pw.TextAlign.right),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      // Sub Total row
                      pw.Row(
                        children: [
                          pw.SizedBox(width: 172),
                          pw.Expanded(
                            child: pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: const pw.BoxDecoration(color: primaryBlue),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(
                                    child: pw.Text('Sub Total', style: pw.TextStyle(font: fontSemiBold, fontSize: 10, color: PdfColors.white), textAlign: pw.TextAlign.right),
                                  ),
                                  pw.SizedBox(
                                    width: 119,
                                    child: pw.Text('\u20B9${formatAmount(data.total)}', style: pw.TextStyle(font: fontSemiBold, fontSize: 10, color: PdfColors.white), textAlign: pw.TextAlign.right),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // PAID stamp overlay – positioned at upper-left of the table
                  if (data.status == 'paid')
                    pw.Positioned(
                      left: 120, top: 40,
                      child: pw.Opacity(
                        opacity: 0.55,
                        child: pw.Transform.rotateBox(
                          angle: -0.40,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                            decoration: pw.BoxDecoration(
                              color: const PdfColor.fromInt(0x66c2eecd),
                              borderRadius: pw.BorderRadius.circular(10),
                              border: pw.Border.all(color: paidGreen, width: 2.5),
                            ),
                            child: pw.Text('PAID', style: pw.TextStyle(font: fontSemiBold, fontSize: 20, color: paidGreen)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 20),
              // Payment info
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  labelValue('Receipt Method:', data.paymentMethod),
                  pw.SizedBox(height: 6),
                  labelValue('Date:', data.paymentDate),
                ],
              ),
              pw.Spacer(),
              // Footer
              pw.Center(
                child: pw.Text('Thank you for your payment.', style: pw.TextStyle(font: fontPtSerif, fontSize: 14, color: textDark)),
              ),
              pw.SizedBox(height: 8),
              if (data.schoolEmail != null || data.schoolMobile != null)
                pw.Center(
                  child: pw.Text(
                    'For any further inquiries, please contact us at '
                    '${data.schoolEmail ?? ''}'
                    '${data.schoolEmail != null && data.schoolMobile != null ? ' or\ncall ' : ''}'
                    '${data.schoolMobile ?? ''}',
                    style: pw.TextStyle(font: fontMedium, fontSize: 10, color: textMediumC),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
    return pdf;
  }

  void _showReceiptDialog(Map<String, dynamic> payment, List<Map<String, dynamic>>? feeDetails) {
    final receiptData = _buildReceiptData(payment, feeDetails);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(
          width: 620,
          height: 920,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          final pdf = await _buildReceiptPdf(receiptData);
                          final bytes = await pdf.save();
                          final defaultName = 'Receipt_${receiptData.receiptNo.replaceAll('/', '_')}.pdf';
                          final result = await FilePicker.platform.saveFile(
                            dialogTitle: 'Save Receipt PDF',
                            fileName: defaultName,
                            type: FileType.custom,
                            allowedExtensions: ['pdf'],
                          );
                          if (result != null) {
                            final file = File(result);
                            await file.writeAsBytes(bytes);
                            if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Receipt saved successfully'), backgroundColor: Colors.green));
                          }
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                        }
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          final pdf = await _buildReceiptPdf(receiptData);
                          await Printing.layoutPdf(
                            onLayout: (PdfPageFormat format) async => pdf.save(),
                            name: 'Receipt_${receiptData.receiptNo.replaceAll('/', '_')}',
                          );
                        } catch (e) {
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error));
                        }
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 2))],
                      ),
                      child: ReceiptWidget(data: receiptData),
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

  Widget _buildFeeDetailDrilldown() {
    final p = _selectedPayment!;
    final student = p['students'] as Map<String, dynamic>?;
    final payNo = p['paynumber']?.toString() ?? '-';
    final stuName = student?['stuname']?.toString() ?? '-';
    final admNo = student?['stuadmno']?.toString() ?? '-';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _selectedPayId = null;
                    _selectedPayment = null;
                    _feeDetails = null;
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      InkWell(
                        onTap: () => setState(() {
                          _selectedDate = null;
                          _selectedPayId = null;
                          _selectedPayment = null;
                          _feeDetails = null;
                          _dateDrilldownSearch = '';
                          _dateDrilldownMethodFilter = null;
                        }),
                        child: const Text('Date-wise Collection', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                      ),
                      const Text('  >  ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      InkWell(
                        onTap: () => setState(() {
                          _selectedPayId = null;
                          _selectedPayment = null;
                          _feeDetails = null;
                        }),
                        child: Text(_selectedDate != null ? _formatDisplayDate(_selectedDate!) : '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                      ),
                      const Text('  >  ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                      Text('$payNo - $stuName ($admNo)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
              if (_loadingFeeDetails)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (_feeDetails == null || _feeDetails!.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No fee details found', style: TextStyle(color: AppColors.textSecondary))))
              else
                LayoutBuilder(builder: (context, constraints) {
                  return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
                      headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
                      columns: const [
                        DataColumn(label: Text('S No.')), DataColumn(label: Text('TERM')), DataColumn(label: Text('FEE TYPE')),
                        DataColumn(label: Text('AMOUNT'), numeric: true), DataColumn(label: Text('PAID'), numeric: true),
                        DataColumn(label: Text('BALANCE'), numeric: true), DataColumn(label: Text('STATUS')),
                      ],
                      rows: [
                        ...List.generate(_feeDetails!.length, (i) {
                          final fd = _feeDetails![i];
                          final isPaid = fd['paidstatus'] == 'P';
                          final balance = (fd['balancedue'] as num?)?.toDouble() ?? 0;
                          // Show month name for monthly fees (TUITION/VAN), otherwise term label
                          const _months = ['JANUARY','FEBRUARY','MARCH','APRIL','MAY','JUNE','JULY','AUGUST','SEPTEMBER','OCTOBER','NOVEMBER','DECEMBER'];
                          const _monthFeeTypes = ['TUITION FEES', 'TUITION FEE', 'VAN FEES', 'VAN FEE'];
                          String term = fd['demfeeterm']?.toString() ?? '-';
                          final feeTypeUpper = (fd['demfeetype']?.toString() ?? '').toUpperCase();
                          if (_monthFeeTypes.contains(feeTypeUpper)) {
                            final duedate = fd['duedate'];
                            if (duedate != null) {
                              try {
                                final dt = DateTime.parse(duedate.toString());
                                term = _months[dt.month - 1];
                              } catch (_) {}
                            }
                          }
                          return DataRow(cells: [
                            DataCell(Text('${i + 1}')),
                            DataCell(Text(term)),
                            DataCell(Text(fd['demfeetype']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
                            DataCell(Text(_formatCurrency((fd['feeamount'] as num?)?.toDouble() ?? 0))),
                            DataCell(Text(_formatCurrency((fd['paidamount'] as num?)?.toDouble() ?? 0), style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.success))),
                            DataCell(Text(_formatCurrency(balance), style: TextStyle(fontWeight: FontWeight.w500, color: balance > 0 ? AppColors.warning : AppColors.textSecondary))),
                            DataCell(Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(isPaid ? 'Paid' : 'Due', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : AppColors.warning)),
                            )),
                          ]);
                        }),
                        // Grand total row
                        DataRow(
                          color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                          cells: [
                            const DataCell(Text('')),
                            const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text('${_feeDetails!.length} items', style: const TextStyle(color: Colors.white70))),
                            DataCell(Text(_formatCurrency(_feeDetails!.fold<double>(0, (s, d) => s + ((d['feeamount'] as num?)?.toDouble() ?? 0))), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text(_formatCurrency(_feeDetails!.fold<double>(0, (s, d) => s + ((d['paidamount'] as num?)?.toDouble() ?? 0))), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text(_formatCurrency(_feeDetails!.fold<double>(0, (s, d) => s + ((d['balancedue'] as num?)?.toDouble() ?? 0))), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            const DataCell(Text('')),
                          ],
                        ),
                      ],
                    ),
                  ));
                }),
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 12, 20, 16),
            child: Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showReceiptDialog(p, _feeDetails),
                icon: const Icon(Icons.download_rounded, size: 16),
                label: const Text('Download PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  elevation: 0,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Tab 2: Class-wise Demand ====================

class _ClassWiseDemandTab extends StatefulWidget {
  const _ClassWiseDemandTab();

  @override
  State<_ClassWiseDemandTab> createState() => _ClassWiseDemandTabState();
}

class _ClassWiseDemandTabState extends State<_ClassWiseDemandTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = false;
  List<_ClassGroup> _classGroups = [];
  String? _selectedClass;
  List<Map<String, dynamic>> _drilldownDemands = [];
  bool _drilldownLoading = false;
  String? _drilldownAdmNo;
  int _studentPage = 0;
  final int _studentPageSize = 10;

  // Search & filter state for class list
  String _classSearchQuery = '';
  String? _classFilterFeeType;
  // Search & filter state for student drilldown
  String _studentSearchQuery = '';
  String? _studentStatusFilter;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  String _formatCurrency(double amount) {
    final str = amount.toStringAsFixed(0);
    final pattern = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = str.replaceAllMapped(pattern, (m) => '${m[1]},');
    return '₹$formatted';
  }

  int _compareClass(String a, String b) {
    const order = ['PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];
    final ia = order.indexOf(a);
    final ib = order.indexOf(b);
    if (ia != -1 && ib != -1) return ia.compareTo(ib);
    if (ia != -1) return -1;
    if (ib != -1) return 1;
    return a.compareTo(b);
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);

    // Use aggregate summary — one row per class, no row-limit issues
    final summaryRows = await SupabaseService.getFeeDemandSummary(insId);

    if (mounted) {
      setState(() {
        _classGroups = _buildClassGroupsFromSummary(summaryRows);
        _isLoading = false;
      });
    }
  }

  List<_ClassGroup> _buildClassGroupsFromSummary(List<Map<String, dynamic>> rows) {
    final groups = rows.map((r) {
      final rawFeeTypes = r['fee_types'];
      final List<String> feeTypes = rawFeeTypes is List
          ? List<String>.from(rawFeeTypes.whereType<String>())
          : [];
      return _ClassGroup(
        className: r['stuclass']?.toString() ?? '',
        demands: const [],
        totalDemand: (r['total_demand'] as num?)?.toDouble() ?? 0,
        totalConcession: (r['total_concession'] as num?)?.toDouble() ?? 0,
        totalPaid: (r['total_paid'] as num?)?.toDouble() ?? 0,
        totalPending: (r['total_pending'] as num?)?.toDouble() ?? 0,
        studentCount: (r['student_count'] as num?)?.toInt() ?? 0,
        feeTypes: feeTypes,
      );
    }).toList();
    groups.sort((a, b) => _compareClass(a.className, b.className));
    return groups;
  }

  // Summary totals
  double get _totalDemand => _classGroups.fold(0.0, (s, g) => s + g.totalDemand);
  double get _totalPaid => _classGroups.fold(0.0, (s, g) => s + g.totalPaid);
  double get _totalPending => _classGroups.fold(0.0, (s, g) => s + g.totalPending);
  int get _totalStudents => _classGroups.fold(0, (s, g) => s + g.studentCount);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // If a class is selected, show student drilldown
    if (_selectedClass != null) {
      final group = _classGroups.firstWhere((g) => g.className == _selectedClass, orElse: () => _classGroups.first);
      return _buildStudentDrilldown(group, _drilldownDemands, _drilldownLoading);
    }

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Summary cards
            Row(
              children: [
                _buildSummaryCard(Icons.people_alt_outlined, Colors.blue, _totalStudents.toString(), 'Total Students'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.account_balance_wallet, AppColors.accent, _formatCurrency(_totalDemand), 'Total Demand'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.check_circle_outline, AppColors.success, _formatCurrency(_totalPaid), 'Total Collected'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.pending_outlined, AppColors.warning, _formatCurrency(_totalPending), 'Total Pending'),
              ],
            ),
            const SizedBox(height: 16),
            // Search & filter bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  // Search bar
                  Expanded(
                    flex: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search, size: 18, color: AppColors.textSecondary),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              decoration: const InputDecoration(
                                hintText: 'Search by class name...',
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(vertical: 8),
                                hintStyle: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              ),
                              style: const TextStyle(fontSize: 12),
                              onChanged: (v) => setState(() => _classSearchQuery = v.trim().toLowerCase()),
                            ),
                          ),
                          if (_classSearchQuery.isNotEmpty)
                            GestureDetector(
                              onTap: () => setState(() => _classSearchQuery = ''),
                              child: const Icon(Icons.close, size: 16, color: AppColors.textSecondary),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Fee type filter dropdown
                  Expanded(
                    flex: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _classFilterFeeType,
                          isExpanded: true,
                          isDense: true,
                          hint: const Text('All Fee Types', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                          icon: const Icon(Icons.arrow_drop_down, size: 18, color: AppColors.textSecondary),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('All Fee Types', style: TextStyle(fontSize: 12))),
                            ...() {
                              final allFeeTypes = <String>{};
                              for (final g in _classGroups) {
                                allFeeTypes.addAll(g.feeTypes);
                              }
                              final sorted = allFeeTypes.toList()..sort();
                              return sorted.map((ft) => DropdownMenuItem<String>(value: ft, child: Text(ft, style: const TextStyle(fontSize: 12))));
                            }(),
                          ],
                          onChanged: (v) => setState(() => _classFilterFeeType = v),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Class-wise table
            if (_isLoading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else
              Builder(builder: (context) {
                final filteredGroups = _classGroups.where((g) {
                  if (_classSearchQuery.isNotEmpty && !g.className.toLowerCase().contains(_classSearchQuery)) return false;
                  if (_classFilterFeeType != null && !g.feeTypes.contains(_classFilterFeeType)) return false;
                  return true;
                }).toList();
                return LayoutBuilder(builder: (context, constraints) {
                  final totalColumns = 8;
                  final minTableWidth = totalColumns * 120.0;
                  final effectiveMin = minTableWidth > constraints.maxWidth ? minTableWidth : constraints.maxWidth;
                  return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: effectiveMin),
                    child: DataTable(
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
                      headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                      columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 40, dataRowMaxHeight: 48, headingRowHeight: 42,
                      columns: const [
                        DataColumn(label: Text('S No.')),
                        DataColumn(label: Text('CLASS')),
                        DataColumn(label: Text('STUDENTS'), numeric: true),
                        DataColumn(label: Text('FEE TYPES')),
                        DataColumn(label: Text('TOTAL DEMAND'), numeric: true),
                        DataColumn(label: Text('PAID'), numeric: true),
                        DataColumn(label: Text('PENDING'), numeric: true),
                        DataColumn(label: Text('% COLLECTED')),
                      ],
                      rows: filteredGroups.isEmpty ? [
                        const DataRow(cells: [
                          DataCell(Text('')), DataCell(Text('No fee demands found')), DataCell(Text('')), DataCell(Text('')),
                          DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')),
                        ]),
                      ] : [
                        ...filteredGroups.asMap().entries.map((entry) {
                          final i = entry.key;
                          final g = entry.value;
                          final pct = g.totalDemand > 0 ? (g.totalPaid / g.totalDemand * 100) : 0.0;
                          return DataRow(
                            cells: [
                              DataCell(Text('${i + 1}')),
                              DataCell(InkWell(
                                onTap: () async {
                                  setState(() {
                                    _selectedClass = g.className;
                                    _drilldownLoading = true;
                                    _drilldownDemands = [];
                                    _studentSearchQuery = '';
                                    _studentStatusFilter = null;
                                    _studentPage = 0;
                                  });
                                  final auth = context.read<AuthProvider>();
                                  final insId = auth.insId;
                                  if (insId != null) {
                                    final demands = await SupabaseService.getFeeDemandsByClass(insId, g.className);
                                    for (final d in demands) {
                                      d['_stuname'] = d['stuname']?.toString() ?? '';
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _drilldownDemands = demands;
                                        _drilldownLoading = false;
                                      });
                                    }
                                  }
                                },
                                child: Row(children: [
                                  Flexible(child: Text(g.className, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.accent))),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(5)),
                                    child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                                  ),
                                ]),
                              )),
                              DataCell(Text('${g.studentCount}')),
                              DataCell(Wrap(
                                spacing: 4, runSpacing: 4,
                                children: g.feeTypes.map((ft) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6)),
                                  child: Text(ft, style: const TextStyle(fontSize: 9, color: AppColors.accent)),
                                )).toList(),
                              )),
                              DataCell(Text(_formatCurrency(g.totalDemand))),
                              DataCell(Text(_formatCurrency(g.totalPaid), style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.success))),
                              DataCell(Text(_formatCurrency(g.totalPending), style: TextStyle(fontWeight: FontWeight.w500, color: g.totalPending > 0 ? AppColors.warning : AppColors.textSecondary))),
                              DataCell(Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: pct >= 100 ? AppColors.success.withValues(alpha: 0.1) : pct >= 50 ? Colors.orange.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: pct >= 100 ? AppColors.success : pct >= 50 ? Colors.orange : AppColors.warning)),
                              )),
                            ],
                          );
                        }),
                        // Grand total row
                        DataRow(
                          color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                          cells: [
                            const DataCell(Text('')),
                            const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text('$_totalStudents', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text('${_classGroups.length} classes', style: const TextStyle(color: Colors.white70))),
                            DataCell(Text(_formatCurrency(_totalDemand), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text(_formatCurrency(_totalPaid), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            DataCell(Text(_formatCurrency(_totalPending), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                            const DataCell(Text('')),
                          ],
                        ),
                      ],
                    ),
                  ));
                });
              }),
          ],
        ),
      ),
    );
  }

  String _formatCurrencyLocal(double amount) {
    final str = amount.toStringAsFixed(0);
    final pattern = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = str.replaceAllMapped(pattern, (m) => '${m[1]},');
    return '₹$formatted';
  }

  Widget _buildStudentFeeDetail() {
    final demands = _drilldownDemands;
    final admNo = _drilldownAdmNo ?? '-';
    final first = demands.isNotEmpty ? demands.first : null;
    final stuName = first != null
        ? (first['students'] is Map ? (first['students']['stuname']?.toString() ?? '-') : (first['stuname']?.toString() ?? '-'))
        : '-';
    final stuClass = first?['stuclass']?.toString() ?? '-';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _selectedClass = null;
                    _drilldownAdmNo = null;
                    _drilldownDemands = [];
                  }),
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                  ),
                ),
                const SizedBox(width: 12),
                InkWell(
                  onTap: () => setState(() {
                    _selectedClass = null;
                    _drilldownAdmNo = null;
                    _drilldownDemands = [];
                  }),
                  child: const Text('Class-wise Demand', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                ),
                const Text('  >  ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                InkWell(
                  onTap: () => setState(() {
                    _drilldownAdmNo = null;
                    _drilldownDemands = [];
                  }),
                  child: Text('Class $stuClass', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                ),
                const Text('  >  ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                Text('$stuName ($admNo)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const Divider(height: 1),
          // Fee detail table
          LayoutBuilder(builder: (context, constraints) {
          double totalDemand = 0, totalPaid = 0, totalBalance = 0;
          for (final d in demands) {
            totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
            totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
            totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
          }
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('TERM')),
                DataColumn(label: Text('FEE TYPE')),
                DataColumn(label: Text('AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Text('STATUS')),
              ],
              rows: [
                ...demands.asMap().entries.map((entry) {
                  final i = entry.key;
                  final d = entry.value;
                  final term = d['demfeeterm']?.toString() ?? '-';
                  final feeType = d['demfeetype']?.toString() ?? '-';
                  final amount = (d['feeamount'] as num?)?.toDouble() ?? 0;
                  final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
                  final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  final isPaid = balance <= 0;
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(term)),
                    DataCell(Text(feeType, style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(Text(_formatCurrencyLocal(amount))),
                    DataCell(Text(_formatCurrencyLocal(paid), style: const TextStyle(color: AppColors.success))),
                    DataCell(Text(_formatCurrencyLocal(balance), style: TextStyle(fontWeight: FontWeight.w500, color: balance > 0 ? AppColors.warning : AppColors.textSecondary))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: isPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(isPaid ? 'Paid' : 'Pending', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : AppColors.warning)),
                    )),
                  ]);
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrencyLocal(totalDemand), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrencyLocal(totalPaid), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrencyLocal(totalBalance), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ));
        }),
        ],
      ),
    );
  }

  Widget _buildStudentDrilldown(_ClassGroup group, List<Map<String, dynamic>> demands, bool loading) {
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    // Group demands by student (stuadmno)
    final Map<String, List<Map<String, dynamic>>> byStudent = {};
    for (final d in demands) {
      final admNo = d['stuadmno']?.toString() ?? 'Unknown';
      byStudent.putIfAbsent(admNo, () => []).add(d);
    }

    // If a student is selected, show fee detail drilldown
    if (_drilldownAdmNo != null && _drilldownDemands != null) {
      return _buildStudentFeeDetail();
    }

    // Apply search and status filter
    final studentKeys = byStudent.keys.where((admNo) {
      final studentDemands = byStudent[admNo]!;
      final stuName = (studentDemands.first['_stuname']?.toString() ?? '').toLowerCase();
      final admNoLower = admNo.toLowerCase();
      // Search filter
      if (_studentSearchQuery.isNotEmpty) {
        if (!admNoLower.contains(_studentSearchQuery) && !stuName.contains(_studentSearchQuery)) {
          return false;
        }
      }
      // Status filter
      if (_studentStatusFilter != null) {
        final allPaid = studentDemands.every((d) => d['paidstatus'] == 'P');
        final anyPaid = studentDemands.any((d) => d['paidstatus'] == 'P');
        final status = allPaid ? 'Paid' : anyPaid ? 'Partial' : 'Unpaid';
        if (status != _studentStatusFilter) return false;
      }
      return true;
    }).toList();
    final totalStudents = studentKeys.length;
    final totalPages = (totalStudents / _studentPageSize).ceil();
    if (_studentPage >= totalPages && totalPages > 0) _studentPage = totalPages - 1;
    final startIdx = _studentPage * _studentPageSize;
    final endIdx = (startIdx + _studentPageSize).clamp(0, totalStudents);
    final pagedKeys = studentKeys.sublist(startIdx, endIdx);

    return SingleChildScrollView(
      child: Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() {
                        _selectedClass = null;
                        _studentPage = 0;
                        _studentSearchQuery = '';
                        _studentStatusFilter = null;
                      }),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                      ),
                    ),
                    const SizedBox(width: 12),
                    InkWell(
                      onTap: () => setState(() {
                        _selectedClass = null;
                        _studentPage = 0;
                        _studentSearchQuery = '';
                        _studentStatusFilter = null;
                      }),
                      child: const Text('Class-wise Demand', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                    ),
                    const Text('  >  ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                    Text('Class ${group.className}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    const SizedBox(width: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '$totalStudents students',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent),
                      ),
                    ),
                    const Spacer(),
                    SizedBox(
                      width: 200,
                      height: 34,
                      child: TextField(
                        onChanged: (v) => setState(() {
                          _studentSearchQuery = v.trim().toLowerCase();
                          _studentPage = 0;
                        }),
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                          prefixIcon: const Icon(Icons.search_rounded, size: 18),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      height: 34,
                      child: DropdownButtonHideUnderline(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: DropdownButton<String?>(
                            value: _studentStatusFilter,
                            hint: const Text('All Status', style: TextStyle(fontSize: 12)),
                            style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                            items: const [
                              DropdownMenuItem<String>(value: null, child: Text('All Status', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'Paid', child: Text('Paid', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'Partial', child: Text('Partial', style: TextStyle(fontSize: 12))),
                              DropdownMenuItem(value: 'Unpaid', child: Text('Unpaid', style: TextStyle(fontSize: 12))),
                            ],
                            onChanged: (v) => setState(() {
                              _studentStatusFilter = v;
                              _studentPage = 0;
                            }),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Student list table
              LayoutBuilder(builder: (context, constraints) {
          // Compute totals for grand total row
          double gDemand = 0, gPaid = 0, gBalance = 0;
          for (final key in studentKeys) {
            for (final d in byStudent[key]!) {
              gDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
              gPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
              gBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
            }
          }
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('ADM NO')),
                DataColumn(label: Text('STUDENT NAME')),
                DataColumn(label: Text('FEE AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Text('STATUS')),
              ],
              rows: pagedKeys.isEmpty ? [
                const DataRow(cells: [
                  DataCell(Text('')), DataCell(Text('No students found')), DataCell(Text('')),
                  DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')),
                ]),
              ] : [
                ...pagedKeys.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final admNo = entry.value;
                  final studentDemands = byStudent[admNo]!;
                  final stuName = studentDemands.first['_stuname']?.toString() ?? '-';
                  double sDemand = 0, sPaid = 0, sBalance = 0;
                  for (final d in studentDemands) {
                    sDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
                    sPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
                    sBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
                  }
                  final allPaid = studentDemands.every((d) => d['paidstatus'] == 'P');
                  final anyPaid = studentDemands.any((d) => d['paidstatus'] == 'P');
                  return DataRow(cells: [
                    DataCell(Text('${startIdx + idx + 1}')),
                    DataCell(Text(admNo)),
                    DataCell(InkWell(
                      onTap: () => setState(() {
                        _drilldownAdmNo = admNo;
                        _drilldownDemands = studentDemands;
                      }),
                      child: Row(children: [
                        Flexible(child: Text(stuName, style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.accent))),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                          decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(5)),
                          child: const Icon(Icons.arrow_forward_ios_rounded, color: Colors.white, size: 12),
                        ),
                      ]),
                    )),
                    DataCell(Text(_formatCurrency(sDemand))),
                    DataCell(Text(_formatCurrency(sPaid), style: const TextStyle(fontWeight: FontWeight.w500, color: AppColors.success))),
                    DataCell(Text(_formatCurrency(sBalance), style: TextStyle(fontWeight: FontWeight.w500, color: sBalance > 0 ? AppColors.warning : AppColors.textSecondary))),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: allPaid ? AppColors.success.withValues(alpha: 0.1) : anyPaid ? AppColors.warning.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(allPaid ? 'Paid' : anyPaid ? 'Partial' : 'Unpaid', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: allPaid ? AppColors.success : anyPaid ? AppColors.warning : AppColors.error)),
                    )),
                  ]);
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(Text('Total ($totalStudents students)', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(gDemand), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(gPaid), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text(_formatCurrency(gBalance), style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ));
              }),
              const SizedBox(height: 8),
              // Pagination footer
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    Text(
                      'Showing ${totalStudents == 0 ? 0 : startIdx + 1}–$endIdx of $totalStudents students',
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.first_page_rounded, size: 20),
                      onPressed: _studentPage > 0 ? () => setState(() => _studentPage = 0) : null,
                      tooltip: 'First page', splashRadius: 18,
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded, size: 20),
                      onPressed: _studentPage > 0 ? () => setState(() => _studentPage--) : null,
                      tooltip: 'Previous', splashRadius: 18,
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                      child: Text('${_studentPage + 1} / ${totalPages == 0 ? 1 : totalPages}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white)),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded, size: 20),
                      onPressed: _studentPage < totalPages - 1 ? () => setState(() => _studentPage++) : null,
                      tooltip: 'Next', splashRadius: 18,
                    ),
                    IconButton(
                      icon: const Icon(Icons.last_page_rounded, size: 20),
                      onPressed: _studentPage < totalPages - 1 ? () => setState(() => _studentPage = totalPages - 1) : null,
                      tooltip: 'Last page', splashRadius: 18,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
    );
  }

  Widget _buildSummaryCard(IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Tab 3: Date-wise (Fee Demand by Date) ====================

class _DateWiseTab extends StatefulWidget {
  const _DateWiseTab();

  @override
  State<_DateWiseTab> createState() => _DateWiseTabState();
}

class _DateWiseTabState extends State<_DateWiseTab> with AutomaticKeepAliveClientMixin {
  DateTime _fromDate = DateTime(2020);
  DateTime _toDate = DateTime.now().add(const Duration(days: 365));
  bool _isLoading = false;
  List<Map<String, dynamic>> _allDemands = [];
  List<_DateDemandGroup> _dateGroups = [];

  List<String> _allFeeTypes = [];
  List<String> _feeTypes = [];
  Map<int, String> _payNumberMap = {};

  String _searchQuery = '';
  String? _filterFeeType;

  final ScrollController _tableScrollController = ScrollController();
  bool _canScroll = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _tableScrollController.addListener(_onScrollChanged);
    _fetchData();
  }

  @override
  void dispose() {
    _tableScrollController.removeListener(_onScrollChanged);
    _tableScrollController.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (mounted) setState(() {});
  }

  void _updateCanScroll() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_tableScrollController.hasClients &&
          _tableScrollController.positions.isNotEmpty &&
          _tableScrollController.position.hasContentDimensions) {
        final canScroll = _tableScrollController.position.maxScrollExtent > 5;
        if (_canScroll != canScroll) {
          setState(() => _canScroll = canScroll);
        }
      } else {
        if (_canScroll) setState(() => _canScroll = false);
      }
    });
  }

  String _formatCurrency(double amount) {
    final str = amount.toStringAsFixed(0);
    final pattern = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = str.replaceAllMapped(pattern, (m) => '${m[1]},');
    return '\u20B9$formatted';
  }

  String _formatDisplayDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day.toString().padLeft(2, '0')}-${months[dt.month - 1]}-${dt.year.toString().substring(2)}';
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        SupabaseService.getPaidFeeDemands(insId),
        SupabaseService.getFeeTypes(insId),
      ]);
      final demands = results[0] as List<Map<String, dynamic>>;
      final feeTypes = results[1] as List<String>;

      // Fetch paynumber map from payment table
      final payIds = demands
          .map((d) => d['pay_id'] as int?)
          .where((id) => id != null)
          .cast<int>()
          .toSet()
          .toList();
      final payNumberMap = await SupabaseService.getPayNumberMap(payIds);

      if (mounted) {
        setState(() {
          _allDemands = demands;
          _allFeeTypes = feeTypes;
          _payNumberMap = payNumberMap;
          _isLoading = false;
        });
        _applyFilter();
      }
    } catch (e) {
      debugPrint('Error fetching date-wise data: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _applyFilter() {
    final fromStr = '${_fromDate.year}-${_fromDate.month.toString().padLeft(2, '0')}-${_fromDate.day.toString().padLeft(2, '0')}';
    final toStr = '${_toDate.year}-${_toDate.month.toString().padLeft(2, '0')}-${_toDate.day.toString().padLeft(2, '0')}';

    final filtered = _allDemands.where((d) {
      final dateStr = _extractDate(d['paydate'] ?? d['createdat']);
      return dateStr.compareTo(fromStr) >= 0 && dateStr.compareTo(toStr) <= 0;
    }).toList();

    // Collect all fee types from paid demands
    final Set<String> feeTypeSet = {};
    for (final d in filtered) {
      final ft = d['demfeetype']?.toString() ?? '';
      if (ft.isNotEmpty) feeTypeSet.add(ft);
    }

    // Group by payment date
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final d in filtered) {
      final dateStr = _extractDate(d['paydate'] ?? d['createdat']);
      grouped.putIfAbsent(dateStr, () => []).add(d);
    }

    final dateGroups = grouped.entries.map((e) {
      double totalDemand = 0, totalPaid = 0, totalPending = 0;
      final Set<String> students = {};
      for (final d in e.value) {
        totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
        totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
        totalPending += (d['balancedue'] as num?)?.toDouble() ?? 0;
        final admNo = d['stuadmno']?.toString() ?? '';
        if (admNo.isNotEmpty) students.add(admNo);
      }
      return _DateDemandGroup(
        date: e.key,
        demands: e.value,
        totalDemand: totalDemand,
        totalPaid: totalPaid,
        totalPending: totalPending,
        studentCount: students.length,
      );
    }).toList();

    dateGroups.sort((a, b) => b.date.compareTo(a.date));

    setState(() {
      _feeTypes = feeTypeSet.toList()..sort();
      _dateGroups = dateGroups;
    });
  }

  String _formatFilterDate(DateTime dt) {
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
  }

  Future<void> _pickDate(bool isFrom) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isFrom ? _fromDate : _toDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
        } else {
          _toDate = picked;
        }
      });
      _applyFilter();
    }
  }

  Widget _buildDateChip(String label, DateTime date, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today, size: 14, color: AppColors.accent),
            const SizedBox(width: 6),
            Text(_formatFilterDate(date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilter(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
      ),
    );
  }

  String _extractDate(dynamic dt) {
    if (dt == null) return 'Unknown';
    try {
      final parsed = DateTime.parse(dt.toString());
      return '${parsed.year}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dt.toString().split('T').first;
    }
  }

  double get _totalDemand => _dateGroups.fold(0.0, (s, g) => s + g.totalDemand);
  double get _totalPaid => _dateGroups.fold(0.0, (s, g) => s + g.totalPaid);
  double get _totalConcession => _dateGroups.fold(0.0, (s, g) => s + g.demands.fold(0.0, (s2, d) => s2 + ((d['conamount'] as num?)?.toDouble() ?? 0)));

  /// Build student rows for a date group, pivoted by fee type
  List<Map<String, dynamic>> _buildStudentRows(List<Map<String, dynamic>> demands) {
    final Map<String, List<Map<String, dynamic>>> studentMap = {};
    for (final d in demands) {
      final admNo = d['stuadmno']?.toString() ?? '-';
      studentMap.putIfAbsent(admNo, () => []).add(d);
    }

    final rows = <Map<String, dynamic>>[];
    for (final entry in studentMap.entries) {
      final admNo = entry.key;
      final studentDemands = entry.value;
      final first = studentDemands.first;
      final stuName = first['students'] is Map
          ? (first['students']['stuname']?.toString() ?? '-')
          : (first['stuname']?.toString() ?? '-');
      final stuClass = first['stuclass']?.toString() ?? '-';
      final payId = first['pay_id'] as int?;
      final payNo = payId != null ? (_payNumberMap[payId] ?? '-') : '-';

      final Map<String, double> feeAmounts = {};
      double total = 0;
      for (final d in studentDemands) {
        final ft = d['demfeetype']?.toString() ?? '';
        final amt = (d['paidamount'] as num?)?.toDouble() ?? 0;
        if (ft.isNotEmpty) {
          feeAmounts[ft] = (feeAmounts[ft] ?? 0) + amt;
        }
        total += amt;
      }

      rows.add({
        'payNo': payNo,
        'admNo': admNo,
        'stuName': stuName,
        'stuClass': stuClass,
        'feeAmounts': feeAmounts,
        'total': total,
      });
    }
    rows.sort((a, b) => (a['admNo'] as String).compareTo(b['admNo'] as String));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Build flat table rows (DATE column per student, no date header/total rows)
    final List<Map<String, dynamic>> flatRows = [];
    int serialNo = 0;
    final Map<String, double> grandFeeTypeTotals = {};
    double grandTotal = 0;
    int totalStudentCount = 0;

    // Use all fee types from feetype table for columns
    final displayFeeTypes = _filterFeeType != null ? [_filterFeeType!] : _allFeeTypes;

    for (final group in _dateGroups) {
      final filteredDemands = _filterFeeType != null
          ? group.demands.where((d) => d['demfeetype']?.toString() == _filterFeeType).toList()
          : group.demands;
      if (filteredDemands.isEmpty) continue;

      final studentRows = _buildStudentRows(filteredDemands);

      final filteredStudentRows = _searchQuery.isEmpty
          ? studentRows
          : studentRows.where((row) {
              final admNo = (row['admNo'] as String).toLowerCase();
              final stuName = (row['stuName'] as String).toLowerCase();
              final stuClass = (row['stuClass'] as String).toLowerCase();
              return admNo.contains(_searchQuery) || stuName.contains(_searchQuery) || stuClass.contains(_searchQuery);
            }).toList();
      if (filteredStudentRows.isEmpty) continue;

      for (final row in filteredStudentRows) {
        serialNo++;
        final feeAmounts = row['feeAmounts'] as Map<String, double>;
        final total = row['total'] as double;
        flatRows.add({
          'date': _formatDisplayDate(group.date),
          'payNo': row['payNo'] as String,
          'admNo': row['admNo'] as String,
          'stuName': row['stuName'] as String,
          'stuClass': row['stuClass'] as String,
          'feeAmounts': feeAmounts,
          'total': total,
        });
        for (final ft in displayFeeTypes) {
          grandFeeTypeTotals[ft] = (grandFeeTypeTotals[ft] ?? 0) + (feeAmounts[ft] ?? 0);
        }
        grandTotal += total;
      }
      totalStudentCount += filteredStudentRows.length;
    }

    _updateCanScroll();

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            // Date filter bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Row(
                children: [
                  const Icon(Icons.filter_alt_rounded, size: 18, color: AppColors.accent),
                  const SizedBox(width: 8),
                  const Text('Date Range:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                  const SizedBox(width: 8),
                  _buildDateChip('From', _fromDate, () => _pickDate(true)),
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 8),
                    child: Text('\u2014', style: TextStyle(color: AppColors.textSecondary)),
                  ),
                  _buildDateChip('To', _toDate, () => _pickDate(false)),
                  const SizedBox(width: 12),
                  _buildQuickFilter('Today', () {
                    setState(() {
                      _fromDate = DateTime.now();
                      _toDate = DateTime.now();
                    });
                    _applyFilter();
                  }),
                  const SizedBox(width: 6),
                  _buildQuickFilter('7 Days', () {
                    setState(() {
                      _toDate = DateTime.now();
                      _fromDate = DateTime.now().subtract(const Duration(days: 7));
                    });
                    _applyFilter();
                  }),
                  const SizedBox(width: 6),
                  _buildQuickFilter('30 Days', () {
                    setState(() {
                      _toDate = DateTime.now();
                      _fromDate = DateTime.now().subtract(const Duration(days: 30));
                    });
                    _applyFilter();
                  }),
                  const SizedBox(width: 6),
                  _buildQuickFilter('This Month', () {
                    final now = DateTime.now();
                    setState(() {
                      _fromDate = DateTime(now.year, now.month, 1);
                      _toDate = now;
                    });
                    _applyFilter();
                  }),
                  const SizedBox(width: 6),
                  _buildQuickFilter('All Time', () {
                    setState(() {
                      _fromDate = DateTime(2020);
                      _toDate = DateTime.now();
                    });
                    _applyFilter();
                  }),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 20, color: AppColors.textSecondary),
                    onPressed: _fetchData,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Summary cards
            Row(
              children: [
                _buildSummaryCard(Icons.account_balance_wallet, AppColors.accent, _formatCurrency(_totalDemand), 'Total Demand'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.check_circle_outline, AppColors.success, _formatCurrency(_totalPaid), 'Total Collected'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.card_giftcard_outlined, AppColors.warning, _formatCurrency(_totalConcession), 'Total Concession'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.people_outline, Colors.blue, '$totalStudentCount', 'Total Students'),
              ],
            ),
            const SizedBox(height: 16),
            // Spreadsheet-like table
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // Title bar with search & filter
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    child: Row(
                      children: [
                        Icon(Icons.table_chart_rounded, size: 18, color: AppColors.accent),
                        const SizedBox(width: 8),
                        const Text('Date-wise Paid Collection Register', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text('${_dateGroups.length} dates  |  $totalStudentCount students',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
                        ),
                        const Spacer(),
                        SizedBox(
                          width: 200,
                          height: 34,
                          child: TextField(
                            onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                            decoration: InputDecoration(
                              hintText: 'Search...',
                              hintStyle: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                              prefixIcon: const Icon(Icons.search_rounded, size: 18),
                              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 34,
                          child: DropdownButtonHideUnderline(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: DropdownButton<String?>(
                                value: _filterFeeType,
                                hint: const Text('All Fee Types', style: TextStyle(fontSize: 12)),
                                style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                items: [
                                  const DropdownMenuItem<String>(value: null, child: Text('All Fee Types')),
                                  ..._feeTypes.map((ft) => DropdownMenuItem<String>(value: ft, child: Text(ft))),
                                ],
                                onChanged: (v) => setState(() => _filterFeeType = v),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_dateGroups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_off, size: 40, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            const Text('No paid collections found', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    )
                  else
                    Column(
                      children: [
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final tableWidget = DataTable(
                              showCheckboxColumn: false,
                              headingRowColor: WidgetStateProperty.all(const Color(0xFF2D3748)),
                              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                              columnSpacing: 20,
                              horizontalMargin: 16,
                              dataRowMinHeight: 36,
                              dataRowMaxHeight: 40,
                              headingRowHeight: 42,
                              columns: [
                                const DataColumn(label: Text('DATE')),
                                const DataColumn(label: Text('PAY NO')),
                                const DataColumn(label: Text('ADMN.NO')),
                                const DataColumn(label: Text('STUDENT NAME')),
                                const DataColumn(label: Text('CLASS')),
                                ...displayFeeTypes.map((ft) => DataColumn(label: Text(ft.toUpperCase()), numeric: true)),
                                const DataColumn(label: Text('TOTAL'), numeric: true),
                              ],
                              rows: [
                                ...flatRows.map((row) {
                                  final feeAmounts = row['feeAmounts'] as Map<String, double>;
                                  return DataRow(
                                    cells: [
                                      DataCell(Text(
                                        row['date'] as String,
                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent),
                                      )),
                                      DataCell(Text(row['payNo'] as String, style: const TextStyle(fontWeight: FontWeight.w500))),
                                      DataCell(Text(row['admNo'] as String, style: const TextStyle(fontWeight: FontWeight.w500))),
                                      DataCell(ConstrainedBox(
                                        constraints: const BoxConstraints(maxWidth: 200),
                                        child: Text(row['stuName'] as String, overflow: TextOverflow.ellipsis),
                                      )),
                                      DataCell(Text(row['stuClass'] as String)),
                                      ...displayFeeTypes.map((ft) {
                                        final amt = feeAmounts[ft] ?? 0;
                                        return DataCell(Text(
                                          amt > 0 ? _formatCurrency(amt) : '',
                                          textAlign: TextAlign.right,
                                        ));
                                      }),
                                      DataCell(Text(
                                        _formatCurrency(row['total'] as double),
                                        style: const TextStyle(fontWeight: FontWeight.w600),
                                      )),
                                    ],
                                  );
                                }),
                                // Grand total row
                                DataRow(
                                  color: WidgetStateProperty.all(const Color(0xFF2D3748)),
                                  cells: [
                                    const DataCell(Text('')),
                                    const DataCell(Text('')),
                                    DataCell(Text('GRAND TOTAL', style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white))),
                                    const DataCell(Text('')),
                                    const DataCell(Text('')),
                                    ...displayFeeTypes.map((ft) {
                                      final amt = grandFeeTypeTotals[ft] ?? 0;
                                      return DataCell(Text(
                                        amt > 0 ? _formatCurrency(amt) : '',
                                        style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
                                      ));
                                    }),
                                    DataCell(Text(
                                      _formatCurrency(grandTotal),
                                      style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
                                    )),
                                  ],
                                ),
                              ],
                            );

                            // Minimum width to keep columns readable
                            final totalColumns = 6 + displayFeeTypes.length;
                            final minTableWidth = totalColumns * 100.0;
                            final effectiveMin = minTableWidth > constraints.maxWidth
                                ? minTableWidth
                                : constraints.maxWidth;

                            return SingleChildScrollView(
                              controller: _tableScrollController,
                              scrollDirection: Axis.horizontal,
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minWidth: effectiveMin),
                                child: tableWidget,
                              ),
                            );
                          },
                        ),
                        // Classic horizontal scrollbar with arrow buttons
                        if (_canScroll)
                          Container(
                            height: 20,
                            decoration: const BoxDecoration(
                              color: Color(0xFFF0F0F0),
                              border: Border(top: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
                            ),
                            child: Row(
                              children: [
                                // Left arrow button
                                InkWell(
                                  onTap: () {
                                    _tableScrollController.animateTo(
                                      (_tableScrollController.offset - 100).clamp(0.0, _tableScrollController.position.maxScrollExtent),
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE0E0E0),
                                      border: Border(right: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
                                    ),
                                    child: const Icon(Icons.chevron_left, size: 14, color: Color(0xFF606060)),
                                  ),
                                ),
                                // Scrollbar track + thumb
                                Expanded(
                                  child: LayoutBuilder(
                                    builder: (context, constraints) {
                                      final maxExtent = _tableScrollController.hasClients &&
                                              _tableScrollController.positions.isNotEmpty &&
                                              _tableScrollController.position.hasContentDimensions
                                          ? _tableScrollController.position.maxScrollExtent
                                          : 1.0;
                                      final viewportWidth = _tableScrollController.hasClients &&
                                              _tableScrollController.positions.isNotEmpty &&
                                              _tableScrollController.position.hasContentDimensions
                                          ? _tableScrollController.position.viewportDimension
                                          : constraints.maxWidth;
                                      final totalContentWidth = maxExtent + viewportWidth;
                                      final thumbRatio = (viewportWidth / totalContentWidth).clamp(0.1, 1.0);
                                      final thumbWidth = (constraints.maxWidth * thumbRatio).clamp(30.0, constraints.maxWidth);
                                      final trackSpace = constraints.maxWidth - thumbWidth;
                                      final scrollRatio = maxExtent > 0 ? (_tableScrollController.offset / maxExtent).clamp(0.0, 1.0) : 0.0;
                                      final thumbOffset = trackSpace * scrollRatio;

                                      return GestureDetector(
                                        onHorizontalDragUpdate: (details) {
                                          if (trackSpace > 0) {
                                            final newRatio = ((thumbOffset + details.delta.dx) / trackSpace).clamp(0.0, 1.0);
                                            _tableScrollController.jumpTo(newRatio * maxExtent);
                                          }
                                        },
                                        child: Container(
                                          color: const Color(0xFFF0F0F0),
                                          height: 20,
                                          child: Stack(
                                            children: [
                                              Positioned(
                                                left: thumbOffset,
                                                top: 2,
                                                child: Container(
                                                  width: thumbWidth,
                                                  height: 16,
                                                  decoration: BoxDecoration(
                                                    color: const Color(0xFFC0C0C0),
                                                    borderRadius: BorderRadius.circular(2),
                                                    border: Border.all(color: const Color(0xFFB0B0B0)),
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
                                // Right arrow button
                                InkWell(
                                  onTap: () {
                                    _tableScrollController.animateTo(
                                      (_tableScrollController.offset + 100).clamp(0.0, _tableScrollController.position.maxScrollExtent),
                                      duration: const Duration(milliseconds: 200),
                                      curve: Curves.easeOut,
                                    );
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFE0E0E0),
                                      border: Border(left: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
                                    ),
                                    child: const Icon(Icons.chevron_right, size: 14, color: Color(0xFF606060)),
                                  ),
                                ),
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
      ),
    );
  }

  Widget _buildSummaryCard(IconData icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: iconColor, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(label, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== Data Models ====================

class _DateGroup {
  final String date;
  final List<Map<String, dynamic>> payments;
  final double totalAmount;

  _DateGroup({
    required this.date,
    required this.payments,
    required this.totalAmount,
  });
}

class _ClassGroup {
  final String className;
  final List<Map<String, dynamic>> demands;
  final double totalDemand;
  final double totalConcession;
  final double totalPaid;
  final double totalPending;
  final int studentCount;
  final List<String> feeTypes; // "FeeGroup > FeeType" list

  _ClassGroup({
    required this.className,
    required this.demands,
    required this.totalDemand,
    required this.totalConcession,
    required this.totalPaid,
    required this.totalPending,
    required this.studentCount,
    this.feeTypes = const [],
  });
}

class _DateDemandGroup {
  final String date;
  final List<Map<String, dynamic>> demands;
  final double totalDemand;
  final double totalPaid;
  final double totalPending;
  final int studentCount;

  _DateDemandGroup({
    required this.date,
    required this.demands,
    required this.totalDemand,
    required this.totalPaid,
    required this.totalPending,
    required this.studentCount,
  });
}

// ==================== Student Accordion ====================

class _StudentAccordion extends StatefulWidget {
  final int index;
  final String admNo;
  final List<Map<String, dynamic>> demands;
  final String Function(double) formatCurrency;

  const _StudentAccordion({
    required this.index,
    required this.admNo,
    required this.demands,
    required this.formatCurrency,
  });

  @override
  State<_StudentAccordion> createState() => _StudentAccordionState();
}

class _StudentAccordionState extends State<_StudentAccordion> {
  bool _expanded = false;

  String _formatDueDate(dynamic duedate) {
    if (duedate == null) return '-';
    try {
      final dt = DateTime.parse(duedate.toString());
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return duedate.toString();
    }
  }

  @override
  Widget build(BuildContext context) {
    final demands = widget.demands;
    final stuName = demands.first['_stuname']?.toString() ?? '-';
    final totalFee = demands.fold<double>(0, (s, d) => s + ((d['feeamount'] as num?)?.toDouble() ?? 0));
    final totalPaid = demands.fold<double>(0, (s, d) => s + ((d['paidamount'] as num?)?.toDouble() ?? 0));
    final totalBalance = demands.fold<double>(0, (s, d) => s + ((d['balancedue'] as num?)?.toDouble() ?? 0));
    final allPaid = demands.every((d) => d['paidstatus'] == 'P');
    final anyPaid = demands.any((d) => d['paidstatus'] == 'P');

    return Column(
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              color: _expanded ? AppColors.accent.withValues(alpha: 0.02) : Colors.transparent,
              border: const Border(top: BorderSide(color: AppColors.border, width: 0.5)),
            ),
            child: Row(
              children: [
                SizedBox(width: 36, child: Text('${widget.index}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                Expanded(flex: 1, child: Text(widget.admNo, style: const TextStyle(fontSize: 11))),
                Expanded(flex: 3, child: Text(stuName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                Expanded(flex: 2, child: Text(widget.formatCurrency(totalFee), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                Expanded(flex: 2, child: Text(widget.formatCurrency(totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.success))),
                Expanded(flex: 2, child: Text(widget.formatCurrency(totalBalance), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: totalBalance > 0 ? AppColors.warning : AppColors.textSecondary))),
                SizedBox(
                  width: 60,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: allPaid
                            ? AppColors.success.withValues(alpha: 0.1)
                            : anyPaid
                                ? AppColors.warning.withValues(alpha: 0.1)
                                : AppColors.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        allPaid ? 'Paid' : anyPaid ? 'Partial' : 'Unpaid',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                          color: allPaid ? AppColors.success : anyPaid ? AppColors.warning : AppColors.error,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: Icon(_expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: AppColors.accent, size: 18),
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Detail header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: const Row(
                    children: [
                      Expanded(flex: 2, child: Text('Term', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 3, child: Text('Fee Type', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Due Date', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 50, child: Center(child: Text('Status', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                    ],
                  ),
                ),
                // Detail rows (sorted by due date)
                ...(List<Map<String, dynamic>>.from(demands)
                  ..sort((a, b) {
                    final da = a['duedate']?.toString();
                    final db = b['duedate']?.toString();
                    if (da == null && db == null) return 0;
                    if (da == null) return 1;
                    if (db == null) return -1;
                    return da.compareTo(db);
                  })).map((d) {
                  final isPaid = d['paidstatus'] == 'P';
                  final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(d['demfeeterm']?.toString() ?? '-', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                        Expanded(flex: 3, child: Text(d['demfeetype']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
                        Expanded(flex: 2, child: Text(_formatDueDate(d['duedate']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                        Expanded(flex: 2, child: Text(widget.formatCurrency((d['feeamount'] as num?)?.toDouble() ?? 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                        Expanded(flex: 2, child: Text(widget.formatCurrency((d['paidamount'] as num?)?.toDouble() ?? 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.success))),
                        Expanded(flex: 2, child: Text(widget.formatCurrency(balance), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: balance > 0 ? AppColors.warning : AppColors.textSecondary))),
                        SizedBox(
                          width: 50,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: isPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                isPaid ? 'Paid' : 'Due',
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : AppColors.warning),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
      ],
    );
  }
}

