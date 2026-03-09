import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

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

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchData();
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

    // Stage 2: Background — demands + student names (lightweight columns only)
    final slowResults = await Future.wait([
      SupabaseService.getFeeDemands(insId),
      SupabaseService.getStudentNameMap(insId),
    ]);

    final demands = slowResults[0] as List<Map<String, dynamic>>;
    final studentNameMap = slowResults[1] as Map<int, Map<String, String>>;

    double pendingFees = 0;
    for (final d in demands) {
      pendingFees += (d['balancedue'] as num?)?.toDouble() ?? 0;
    }

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
                _buildClickableSummaryCard(Icons.pending_actions_rounded, Colors.orange, _formatCurrency(_pendingFees), 'Pending Fees', () {
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 40, child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 3, child: Text('Payment Method', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Transactions', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Students', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 3, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                  ],
                ),
              ),
              if (methodKeys.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('No collections found', style: TextStyle(color: AppColors.textSecondary))),
                )
              else
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
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text('${idx + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                        Expanded(flex: 3, child: Text(method, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        Expanded(flex: 2, child: Text('${items.length}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                        Expanded(flex: 2, child: Text('${mStuIds.length}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                        Expanded(flex: 3, child: Text(_formatCurrency(mTotal), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success))),
                      ],
                    ),
                  );
                }),
              // Total row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    const Expanded(flex: 3, child: Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    Expanded(flex: 2, child: Text('$totalCount', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    Expanded(flex: 2, child: Text('${allStuIds.length}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    Expanded(flex: 3, child: Text(_formatCurrency(total), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success))),
                  ],
                ),
              ),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const Text('Payment Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    Text('${filtered.length} records', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                color: Colors.grey.shade50,
                child: const Row(
                  children: [
                    SizedBox(width: 40, child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Pay No', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 3, child: Text('Student', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Date', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Method', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                  ],
                ),
              ),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('No payments found', style: TextStyle(color: AppColors.textSecondary))),
                )
              else
                ...filtered.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final p = entry.value;
                  final stuId = p['stu_id'] as int?;
                  final stuName = (stuId != null && _stuIdToName.containsKey(stuId))
                      ? _stuIdToName[stuId]!
                      : (p['stuadmno']?.toString() ?? '-');
                  final amount = (p['transtotalamount'] as num?)?.toDouble() ?? 0;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 40, child: Text('${idx + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                        Expanded(flex: 2, child: Text(p['paynumber']?.toString() ?? '-', style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 3, child: Text(stuName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                        Expanded(flex: 2, child: Text(_formatDate(p['paydate']), style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 2, child: Text(p['paymethod']?.toString() ?? '-', style: const TextStyle(fontSize: 12))),
                        Expanded(flex: 2, child: Text(_formatCurrency(amount), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success))),
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
              Icon(Icons.chevron_right_rounded, size: 18, color: iconColor),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPendingFeesView() {
    // Filter only unpaid demands (balancedue > 0)
    final pendingDemands = _demands.where((d) {
      final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
      return balance > 0;
    }).toList();

    // Get unique fee types and classes for dropdowns
    final feeTypes = pendingDemands.map((d) => d['demfeetype']?.toString() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
    final classes = pendingDemands.map((d) => d['stuclass']?.toString() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort(_compareClass);

    // Apply filters
    final filtered = pendingDemands.where((d) {
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

    // Group by fee group
    final Map<String, List<Map<String, dynamic>>> groupedByFeeGroup = {};
    for (final d in filtered) {
      final feeId = d['fee_id'] as int?;
      final groupName = (feeId != null && _feeGroupMap.containsKey(feeId))
          ? _feeGroupMap[feeId]!
          : 'Uncategorized';
      groupedByFeeGroup.putIfAbsent(groupName, () => []).add(d);
    }

    final groupKeys = groupedByFeeGroup.keys.toList()..sort();

    // If a student is selected, show student fee detail drilldown
    if (_selectedStudentKey != null && _selectedStudentDemands != null) {
      return _buildStudentFeeDrilldown();
    }

    // If a fee group is selected, show student drilldown
    if (_selectedPendingFeeGroup != null && groupedByFeeGroup.containsKey(_selectedPendingFeeGroup)) {
      return _buildPendingStudentList(_selectedPendingFeeGroup!, groupedByFeeGroup[_selectedPendingFeeGroup]!, feeTypes, classes);
    }

    // Compute totals
    double totalDemand = 0, totalPaid = 0, totalBalance = 0;
    int totalStudents = 0;
    final allStuIds = <String>{};
    for (final d in filtered) {
      totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
      totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
      totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
      final stuId = d['stu_id']?.toString();
      if (stuId != null) allStuIds.add(stuId);
    }
    totalStudents = allStuIds.length;

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
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              // Table header
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 40, child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 3, child: Text('Fee Group', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 1, child: Text('Students', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Total Demand', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                  ],
                ),
              ),
              if (groupKeys.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: Text('No pending fees found', style: TextStyle(color: AppColors.textSecondary))),
                )
              else
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
                    final sid = d['stu_id']?.toString();
                    if (sid != null) gStuIds.add(sid);
                  }
                  return InkWell(
                    onTap: () => setState(() => _selectedPendingFeeGroup = groupName),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                      decoration: BoxDecoration(
                        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: 40, child: Text('${idx + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                          Expanded(flex: 3, child: Text(groupName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent))),
                          Expanded(flex: 1, child: Text('${gStuIds.length}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                          Expanded(flex: 2, child: Text(_formatCurrency(gDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                          Expanded(flex: 2, child: Text(_formatCurrency(gPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: AppColors.success))),
                          Expanded(flex: 2, child: Text(_formatCurrency(gBalance), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange))),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
                        ],
                      ),
                    ),
                  );
                }),
              // Total row
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.05),
                  borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 40),
                    const Expanded(flex: 3, child: Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    Expanded(flex: 1, child: Text('$totalStudents', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    Expanded(flex: 2, child: Text(_formatCurrency(totalDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                    Expanded(flex: 2, child: Text(_formatCurrency(totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success))),
                    Expanded(flex: 2, child: Text(_formatCurrency(totalBalance), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange))),
                  ],
                ),
              ),
            ],
          ),
        ),
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
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 40, child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Term', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 3, child: Text('Fee Type', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Fee Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    ],
                  ),
                ),
                // Table body
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: demands.length,
                    itemBuilder: (context, i) {
                      final d = demands[i];
                      final term = d['demfeeterm']?.toString() ?? '-';
                      final feeType = d['demfeetype']?.toString() ?? '-';
                      final feeGroupName = _feeGroupMap[d['fee_id'] as int?] ?? feeType;
                      final amount = (d['feeamount'] as num?)?.toDouble() ?? 0;
                      final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
                      final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                      final isPaid = balance <= 0;

                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: 40, child: Text('${i + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                            Expanded(flex: 2, child: Text(term, style: const TextStyle(fontSize: 13))),
                            Expanded(flex: 3, child: Text(feeGroupName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                            Expanded(flex: 2, child: Text(_formatCurrency(amount), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                            Expanded(flex: 2, child: Text(_formatCurrency(paid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: AppColors.success))),
                            Expanded(flex: 2, child: Text(_formatCurrency(balance), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange))),
                            Expanded(
                              flex: 1,
                              child: Center(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: isPaid ? AppColors.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    isPaid ? 'Paid' : 'Unpaid',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : Colors.red),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                // Total footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 40),
                      const Expanded(flex: 2, child: SizedBox()),
                      const Expanded(flex: 3, child: Text('Total', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text(_formatCurrency(totalDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text(_formatCurrency(totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success))),
                      Expanded(flex: 2, child: Text(_formatCurrency(totalBalance), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.orange))),
                      const Expanded(flex: 1, child: SizedBox()),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
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
        SizedBox(
          height: MediaQuery.of(context).size.height - 380,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 40, child: Text('#', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Adm No', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 3, child: Text('Student Name', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Class', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Fee Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    ],
                  ),
                ),
                // Table body
                Expanded(
                  child: pagedKeys.isEmpty
                      ? const Center(child: Text('No students found', style: TextStyle(color: AppColors.textSecondary)))
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: pagedKeys.length,
                          itemBuilder: (context, idx) {
                            final stuKey = pagedKeys[idx];
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
                            return InkWell(
                              onTap: () => setState(() {
                                _selectedStudentKey = stuKey;
                                _selectedStudentDemands = demands;
                              }),
                              child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                              ),
                              child: Row(
                                children: [
                                  SizedBox(width: 40, child: Text('${startIdx + idx + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text(admNo, style: const TextStyle(fontSize: 13))),
                                  Expanded(flex: 3, child: Text(stuName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                                  Expanded(flex: 2, child: Text(stuClass, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13))),
                                  Expanded(flex: 2, child: Text(_formatCurrency(sDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13))),
                                  Expanded(flex: 2, child: Text(_formatCurrency(sPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, color: AppColors.success))),
                                  Expanded(flex: 2, child: Text(_formatCurrency(sBalance), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.orange))),
                                  Expanded(
                                    flex: 1,
                                    child: Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isPaid ? AppColors.success.withValues(alpha: 0.1) : Colors.red.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Text(
                                          isPaid ? 'Paid' : 'Unpaid',
                                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : Colors.red),
                                        ),
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
                // Pagination footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'Showing ${totalStudents == 0 ? 0 : startIdx + 1}–$endIdx of $totalStudents students',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.first_page_rounded, size: 20),
                        onPressed: _pendingPage > 0 ? () => setState(() => _pendingPage = 0) : null,
                        tooltip: 'First page',
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        onPressed: _pendingPage > 0 ? () => setState(() => _pendingPage--) : null,
                        tooltip: 'Previous page',
                        splashRadius: 18,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${_pendingPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        onPressed: _pendingPage < totalPages - 1 ? () => setState(() => _pendingPage++) : null,
                        tooltip: 'Next page',
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.last_page_rounded, size: 20),
                        onPressed: _pendingPage < totalPages - 1 ? () => setState(() => _pendingPage = totalPages - 1) : null,
                        tooltip: 'Last page',
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
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
    // Try nested student data from join
    final students = demand['students'];
    if (students is Map && students['stuname'] != null) {
      return students['stuname'].toString();
    }
    return admNo.isNotEmpty ? admNo : '-';
  }

  Widget _buildDateList() {
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
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppColors.primary.withValues(alpha: 0.03),
            child: const Row(
              children: [
                SizedBox(width: 36, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                Expanded(flex: 3, child: Text('Date', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Transactions', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                SizedBox(width: 32),
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
            ...List.generate(_dateGroups.length, (i) {
              final group = _dateGroups[i];
              return InkWell(
                onTap: () => setState(() => _selectedDate = group.date),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 36,
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Center(
                            child: Text('${i + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.accent)),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Text(_formatDisplayDate(group.date), style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text('${group.payments.length} payments', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _formatCurrency(group.totalAmount),
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded, color: AppColors.accent, size: 20),
                      const SizedBox(width: 4),
                    ],
                  ),
                ),
              );
            }),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
          // Back button + date header
          Row(
            children: [
              InkWell(
                onTap: () => setState(() {
                  _selectedDate = null;
                  _selectedPayId = null;
                  _selectedPayment = null;
                  _feeDetails = null;
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                      const SizedBox(width: 6),
                      Text('Back', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                _formatDisplayDate(group.date),
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
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
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.success.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatCurrency(group.totalAmount),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Payment details table
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.03),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 36, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Pay No', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('Time', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Adm No', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 3, child: Text('Student Name', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('Class', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Method', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 26),
                    ],
                  ),
                ),
                const Divider(height: 1),
                // Payment rows
                ...List.generate(group.payments.length, (i) {
                  final p = group.payments[i];
                  final student = p['students'] as Map<String, dynamic>?;
                  final timeStr = _formatTime(p['createdat'] ?? p['paydate']);
                  return InkWell(
                    onTap: () => _onPaymentTap(p),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      decoration: const BoxDecoration(
                        border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                      ),
                      child: Row(
                        children: [
                          SizedBox(width: 36, child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                          Expanded(flex: 2, child: Text(p['paynumber']?.toString() ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                          Expanded(flex: 1, child: Text(timeStr, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                          Expanded(flex: 2, child: Text(student?['stuadmno']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
                          Expanded(flex: 3, child: Text(student?['stuname']?.toString() ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                          Expanded(flex: 1, child: Text(student?['stuclass']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
                          Expanded(flex: 2, child: Text(p['paymethod'] ?? '-', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                          Expanded(
                            flex: 2,
                            child: Text(
                              _formatCurrency((p['transtotalamount'] as num?)?.toDouble() ?? 0),
                              textAlign: TextAlign.right,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.success),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right_rounded, color: AppColors.accent, size: 18),
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

  Widget _buildFeeDetailDrilldown() {
    final p = _selectedPayment!;
    final student = p['students'] as Map<String, dynamic>?;
    final payNo = p['paynumber']?.toString() ?? '-';
    final stuName = student?['stuname']?.toString() ?? '-';
    final admNo = student?['stuadmno']?.toString() ?? '-';
    final amount = (p['transtotalamount'] as num?)?.toDouble() ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button + payment header
        Row(
          children: [
            InkWell(
              onTap: () => setState(() {
                _selectedPayId = null;
                _selectedPayment = null;
                _feeDetails = null;
              }),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                    SizedBox(width: 6),
                    Text('Back', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 16),
            const Icon(Icons.receipt_rounded, size: 18, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(payNo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(width: 16),
            Text(stuName, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            Text('($admNo)', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.success.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatCurrency(amount),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.success),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        // Fee details table
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: _loadingFeeDetails
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                )
              : (_feeDetails == null || _feeDetails!.isEmpty)
                  ? const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: Text('No fee details found for this payment', style: TextStyle(color: AppColors.textSecondary))),
                    )
                  : Column(
                      children: [
                        // Table header
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.03),
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 36, child: Text('#', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              Expanded(flex: 2, child: Text('Term', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              Expanded(flex: 3, child: Text('Fee Type', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              SizedBox(width: 60, child: Center(child: Text('Status', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        ...List.generate(_feeDetails!.length, (i) {
                          final fd = _feeDetails![i];
                          final isPaid = fd['paidstatus'] == 'P';
                          final balance = (fd['balancedue'] as num?)?.toDouble() ?? 0;
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                            ),
                            child: Row(
                              children: [
                                SizedBox(width: 36, child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                                Expanded(flex: 2, child: Text(fd['demfeeterm']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
                                Expanded(flex: 3, child: Text(fd['demfeetype']?.toString() ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                                Expanded(flex: 2, child: Text(_formatCurrency((fd['feeamount'] as num?)?.toDouble() ?? 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                                Expanded(flex: 2, child: Text(_formatCurrency((fd['paidamount'] as num?)?.toDouble() ?? 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.success))),
                                Expanded(flex: 2, child: Text(_formatCurrency(balance), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: balance > 0 ? AppColors.warning : AppColors.textSecondary))),
                                SizedBox(
                                  width: 60,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: isPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        isPaid ? 'Paid' : 'Due',
                                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : AppColors.warning),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                        // Total row
                        Builder(builder: (_) {
                          final totalAmount = _feeDetails!.fold<double>(0, (s, d) => s + ((d['feeamount'] as num?)?.toDouble() ?? 0));
                          final totalPaid = _feeDetails!.fold<double>(0, (s, d) => s + ((d['paidamount'] as num?)?.toDouble() ?? 0));
                          final totalBalance = _feeDetails!.fold<double>(0, (s, d) => s + ((d['balancedue'] as num?)?.toDouble() ?? 0));
                          return Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.04),
                              border: const Border(top: BorderSide(color: AppColors.border, width: 1)),
                            ),
                            child: Row(
                              children: [
                                const SizedBox(width: 36),
                                const Expanded(flex: 2, child: Text('Total', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                Expanded(flex: 3, child: Text('${_feeDetails!.length} items', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                                Expanded(flex: 2, child: Text(_formatCurrency(totalAmount), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                                Expanded(flex: 2, child: Text(_formatCurrency(totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.success))),
                                Expanded(flex: 2, child: Text(_formatCurrency(totalBalance), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: totalBalance > 0 ? AppColors.warning : AppColors.textSecondary))),
                                const SizedBox(width: 60),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
        ),
        const SizedBox(height: 16),
        // Receipt button
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: () {
              // TODO: Generate/download receipt
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Receipt generation coming soon!'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.receipt_long_rounded, size: 18),
            label: const Text('Download Receipt'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
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
  int _studentPage = 0;
  static const int _studentPageSize = 10;
  // Student fee detail drilldown
  String? _drilldownAdmNo;
  List<Map<String, dynamic>>? _drilldownDemands;

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

    final demands = await SupabaseService.getFeeDemands(insId);

    // Fetch all students for this institution to map names
    final allStudents = await SupabaseService.getStudents(insId);
    final Map<int, String> stuIdToName = {};
    final Map<String, String> admNoToName = {};
    for (final s in allStudents) {
      stuIdToName[s.stuId] = s.stuname;
      admNoToName[s.stuadmno] = s.stuname;
    }
    // Attach student name to each demand
    for (final d in demands) {
      final stuId = d['stu_id'] as int?;
      final admNo = d['stuadmno']?.toString() ?? '';
      if (stuId != null && stuIdToName.containsKey(stuId)) {
        d['_stuname'] = stuIdToName[stuId];
      } else if (admNo.isNotEmpty && admNoToName.containsKey(admNo)) {
        d['_stuname'] = admNoToName[admNo];
      }
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final d in demands) {
      final cls = d['stuclass']?.toString() ?? 'Unknown';
      grouped.putIfAbsent(cls, () => []).add(d);
    }

    final classGroups = grouped.entries.map((e) {
      double totalDemand = 0;
      double totalPaid = 0;
      double totalPending = 0;
      double totalConcession = 0;
      final Set<String> studentAdmNos = {};
      final Set<String> feeTypeSet = {};

      for (final d in e.value) {
        final fee = (d['feeamount'] as num?)?.toDouble() ?? 0;
        final con = (d['conamount'] as num?)?.toDouble() ?? 0;
        final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
        final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
        totalDemand += fee;
        totalConcession += con;
        totalPaid += paid;
        totalPending += balance;
        final admNo = d['stuadmno']?.toString() ?? '';
        if (admNo.isNotEmpty) studentAdmNos.add(admNo);
        final feeType = d['demfeetype']?.toString() ?? '';
        if (feeType.isNotEmpty) feeTypeSet.add(feeType);
      }

      final feeTypes = feeTypeSet.toList()..sort();

      return _ClassGroup(
        className: e.key,
        demands: e.value,
        totalDemand: totalDemand,
        totalConcession: totalConcession,
        totalPaid: totalPaid,
        totalPending: totalPending,
        studentCount: studentAdmNos.length,
        feeTypes: feeTypes,
      );
    }).toList();

    classGroups.sort((a, b) => _compareClass(a.className, b.className));

    if (mounted) {
      setState(() {
        _classGroups = classGroups;
        _isLoading = false;
      });
    }
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
      return _buildStudentDrilldown(group);
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
            // Class-wise table
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
                        Icon(Icons.school_outlined, size: 18, color: AppColors.accent),
                        const SizedBox(width: 8),
                        const Text('Class-wise Fee Demand', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${_classGroups.length} classes', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Table header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                    color: AppColors.surface,
                    child: const Row(
                      children: [
                        SizedBox(width: 36),
                        Expanded(flex: 2, child: Text('Class', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        Expanded(flex: 1, child: Text('Students', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        Expanded(flex: 3, child: Text('Fee Types', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        Expanded(flex: 2, child: Text('Total Demand', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        Expanded(flex: 2, child: Text('Pending', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        Expanded(flex: 1, child: Text('% Collected', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                        SizedBox(width: 32),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_classGroups.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(48),
                      child: Center(
                        child: Column(
                          children: [
                            Icon(Icons.search_off, size: 40, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                            const SizedBox(height: 8),
                            const Text('No fee demands found', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    )
                  else
                    ...List.generate(_classGroups.length, (i) {
                      final g = _classGroups[i];
                      final pct = g.totalDemand > 0 ? (g.totalPaid / g.totalDemand * 100) : 0.0;
                      return InkWell(
                        onTap: () => setState(() => _selectedClass = g.className),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: const BoxDecoration(
                            border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 28,
                                height: 28,
                                decoration: BoxDecoration(
                                  color: AppColors.accent.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Center(
                                  child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(flex: 2, child: Text(g.className, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))),
                              Expanded(flex: 1, child: Text('${g.studentCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                              Expanded(flex: 3, child: Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: g.feeTypes.map((ft) => Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(ft, style: const TextStyle(fontSize: 9, color: AppColors.accent)),
                                )).toList(),
                              )),
                              Expanded(flex: 2, child: Text(_formatCurrency(g.totalDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                              Expanded(flex: 2, child: Text(_formatCurrency(g.totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.success))),
                              Expanded(flex: 2, child: Text(_formatCurrency(g.totalPending), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: g.totalPending > 0 ? AppColors.warning : AppColors.textSecondary))),
                              Expanded(
                                flex: 1,
                                child: Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: pct >= 100
                                          ? AppColors.success.withValues(alpha: 0.1)
                                          : pct >= 50
                                              ? Colors.orange.withValues(alpha: 0.1)
                                              : AppColors.warning.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      '${pct.toStringAsFixed(0)}%',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: pct >= 100 ? AppColors.success : pct >= 50 ? Colors.orange : AppColors.warning,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 32, child: Icon(Icons.chevron_right, color: AppColors.textSecondary, size: 18)),
                            ],
                          ),
                        ),
                      );
                    }),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStudentFeeDetail() {
    final demands = _drilldownDemands!;
    final first = demands.first;
    final stuName = first['_stuname']?.toString() ?? '-';
    final admNo = _drilldownAdmNo ?? '-';
    final stuClass = first['stuclass']?.toString() ?? '-';

    double totalDemand = 0, totalPaid = 0, totalBalance = 0;
    for (final d in demands) {
      totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
      totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
      totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
    }

    String formatDueDate(dynamic duedate) {
      if (duedate == null) return '-';
      try {
        final dt = DateTime.parse(duedate.toString());
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
      } catch (_) {
        return duedate.toString();
      }
    }

    final sorted = List<Map<String, dynamic>>.from(demands)
      ..sort((a, b) {
        final da = a['duedate']?.toString();
        final db = b['duedate']?.toString();
        if (da == null && db == null) return 0;
        if (da == null) return 1;
        if (db == null) return -1;
        return da.compareTo(db);
      });

    return Column(
      children: [
        // Back + student info header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() {
                  _drilldownAdmNo = null;
                  _drilldownDemands = null;
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, size: 16, color: AppColors.accent),
                      SizedBox(width: 6),
                      Text('Back', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.accent)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stuName, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  const SizedBox(height: 2),
                  Text('Adm No: $admNo  |  Class: $stuClass', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),
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
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 36, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Term', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 3, child: Text('Fee Type', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Due Date', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 60, child: Center(child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: sorted.length,
                    itemBuilder: (context, i) {
                      final d = sorted[i];
                      final isPaid = d['paidstatus'] == 'P';
                      final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                        decoration: BoxDecoration(
                          border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                        ),
                        child: Row(
                          children: [
                            SizedBox(width: 36, child: Text('${i + 1}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                            Expanded(flex: 2, child: Text(d['demfeeterm']?.toString() ?? '-', style: const TextStyle(fontSize: 11))),
                            Expanded(flex: 3, child: Text(d['demfeetype']?.toString() ?? '-', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                            Expanded(flex: 2, child: Text(formatDueDate(d['duedate']), textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                            Expanded(flex: 2, child: Text(_formatCurrency((d['feeamount'] as num?)?.toDouble() ?? 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                            Expanded(flex: 2, child: Text(_formatCurrency((d['paidamount'] as num?)?.toDouble() ?? 0), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, color: AppColors.success))),
                            Expanded(flex: 2, child: Text(_formatCurrency(balance), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: balance > 0 ? AppColors.warning : AppColors.textSecondary))),
                            SizedBox(
                              width: 60,
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
                    },
                  ),
                ),
                // Total footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 36),
                      const Expanded(flex: 2, child: SizedBox()),
                      const Expanded(flex: 3, child: Text('Total', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                      const Expanded(flex: 2, child: SizedBox()),
                      Expanded(flex: 2, child: Text(_formatCurrency(totalDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                      Expanded(flex: 2, child: Text(_formatCurrency(totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.success))),
                      Expanded(flex: 2, child: Text(_formatCurrency(totalBalance), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.orange))),
                      const SizedBox(width: 60),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStudentDrilldown(_ClassGroup group) {
    // Group demands by student (stuadmno)
    final Map<String, List<Map<String, dynamic>>> byStudent = {};
    for (final d in group.demands) {
      final admNo = d['stuadmno']?.toString() ?? 'Unknown';
      byStudent.putIfAbsent(admNo, () => []).add(d);
    }

    // If a student is selected, show fee detail drilldown
    if (_drilldownAdmNo != null && _drilldownDemands != null) {
      return _buildStudentFeeDetail();
    }

    final studentKeys = byStudent.keys.toList();
    final totalStudents = studentKeys.length;
    final totalPages = (totalStudents / _studentPageSize).ceil();
    if (_studentPage >= totalPages && totalPages > 0) _studentPage = totalPages - 1;
    final startIdx = _studentPage * _studentPageSize;
    final endIdx = (startIdx + _studentPageSize).clamp(0, totalStudents);
    final pagedKeys = studentKeys.sublist(startIdx, endIdx);

    return Column(
      children: [
        // Back button header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              InkWell(
                onTap: () => setState(() {
                  _selectedClass = null;
                  _studentPage = 0;
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.arrow_back, size: 16, color: AppColors.accent),
                      SizedBox(width: 6),
                      Text('Back', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.accent)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Icon(Icons.school_outlined, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text('Class ${group.className} — Student Fee Details', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('$totalStudents students', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Student list with pagination
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Table header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  ),
                  child: const Row(
                    children: [
                      SizedBox(width: 36, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 1, child: Text('Adm No', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 3, child: Text('Student Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Fee Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 60, child: Center(child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                      SizedBox(width: 26),
                    ],
                  ),
                ),
                // Table body
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: pagedKeys.length,
                    itemBuilder: (context, idx) {
                      final admNo = pagedKeys[idx];
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

                      return InkWell(
                        onTap: () => setState(() {
                          _drilldownAdmNo = admNo;
                          _drilldownDemands = studentDemands;
                        }),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                          decoration: BoxDecoration(
                            border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                          ),
                          child: Row(
                            children: [
                              SizedBox(width: 36, child: Text('${startIdx + idx + 1}', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                              Expanded(flex: 1, child: Text(admNo, style: const TextStyle(fontSize: 11))),
                              Expanded(flex: 3, child: Text(stuName, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500))),
                              Expanded(flex: 2, child: Text(_formatCurrency(sDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11))),
                              Expanded(flex: 2, child: Text(_formatCurrency(sPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: AppColors.success))),
                              Expanded(flex: 2, child: Text(_formatCurrency(sBalance), textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: sBalance > 0 ? AppColors.warning : AppColors.textSecondary))),
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
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                // Pagination footer
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.05),
                    borderRadius: const BorderRadius.vertical(bottom: Radius.circular(12)),
                  ),
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
                        tooltip: 'First page',
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left_rounded, size: 20),
                        onPressed: _studentPage > 0 ? () => setState(() => _studentPage--) : null,
                        tooltip: 'Previous',
                        splashRadius: 18,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Text(
                          '${_studentPage + 1} / ${totalPages == 0 ? 1 : totalPages}',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_right_rounded, size: 20),
                        onPressed: _studentPage < totalPages - 1 ? () => setState(() => _studentPage++) : null,
                        tooltip: 'Next',
                        splashRadius: 18,
                      ),
                      IconButton(
                        icon: const Icon(Icons.last_page_rounded, size: 20),
                        onPressed: _studentPage < totalPages - 1 ? () => setState(() => _studentPage = totalPages - 1) : null,
                        tooltip: 'Last page',
                        splashRadius: 18,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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
  DateTime _fromDate = DateTime.now().subtract(const Duration(days: 30));
  DateTime _toDate = DateTime.now();
  bool _isLoading = false;
  List<Map<String, dynamic>> _allDemands = [];
  List<_DateDemandGroup> _dateGroups = [];
  String? _drilldownDate; // date string for drilldown
  List<Map<String, dynamic>> _drilldownDemands = [];

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

  String _formatDisplayDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${days[dt.weekday - 1]}, ${dt.day} ${months[dt.month - 1]} ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);

    final demands = await SupabaseService.getFeeDemands(insId);

    if (mounted) {
      setState(() {
        _allDemands = demands;
        _isLoading = false;
      });
      _applyFilter();
    }
  }

  void _applyFilter() {
    final fromStr = '${_fromDate.year}-${_fromDate.month.toString().padLeft(2, '0')}-${_fromDate.day.toString().padLeft(2, '0')}';
    final toStr = '${_toDate.year}-${_toDate.month.toString().padLeft(2, '0')}-${_toDate.day.toString().padLeft(2, '0')}';

    final filtered = _allDemands.where((d) {
      final dateStr = _extractDate(d['createdat']);
      return dateStr.compareTo(fromStr) >= 0 && dateStr.compareTo(toStr) <= 0;
    }).toList();

    // Group by createdat date
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final d in filtered) {
      final dateStr = _extractDate(d['createdat']);
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
  double get _totalPending => _dateGroups.fold(0.0, (s, g) => s + g.totalPending);

  String _formatShortDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      final months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${dt.day.toString().padLeft(2, '0')}-${months[dt.month - 1]}-${dt.year.toString().substring(2)}';
    } catch (_) {
      return isoDate;
    }
  }

  Widget _buildDrilldownDetail() {
    final demands = _drilldownDemands;

    // Get unique fee types from demands
    final Set<String> feeTypeSet = {};
    for (final d in demands) {
      final ft = d['demfeetype']?.toString() ?? '';
      if (ft.isNotEmpty) feeTypeSet.add(ft);
    }
    final feeTypes = feeTypeSet.toList()..sort();

    // Group by student (stuadmno) - each student may have multiple fee type rows
    final Map<String, List<Map<String, dynamic>>> studentMap = {};
    for (final d in demands) {
      final admNo = d['stuadmno']?.toString() ?? '-';
      studentMap.putIfAbsent(admNo, () => []).add(d);
    }

    // Build student rows: each student gets one row with fee types as columns
    final studentRows = <Map<String, dynamic>>[];
    for (final entry in studentMap.entries) {
      final admNo = entry.key;
      final studentDemands = entry.value;
      final first = studentDemands.first;
      final stuName = first['students'] is Map ? (first['students']['stuname']?.toString() ?? '-') : (first['stuname']?.toString() ?? '-');
      final stuClass = first['stuclass']?.toString() ?? '-';
      final date = _extractDate(first['createdat']);

      // Pivot fee types
      final Map<String, double> feeAmounts = {};
      double total = 0;
      for (final d in studentDemands) {
        final ft = d['demfeetype']?.toString() ?? '';
        final amt = (d['feeamount'] as num?)?.toDouble() ?? 0;
        if (ft.isNotEmpty) {
          feeAmounts[ft] = (feeAmounts[ft] ?? 0) + amt;
        }
        total += amt;
      }

      studentRows.add({
        'date': date,
        'admNo': admNo,
        'stuName': stuName,
        'stuClass': stuClass,
        'feeAmounts': feeAmounts,
        'total': total,
      });
    }

    // Sort by admNo
    studentRows.sort((a, b) => (a['admNo'] as String).compareTo(b['admNo'] as String));

    // Calculate column totals
    final Map<String, double> colTotals = {};
    double grandTotal = 0;
    for (final row in studentRows) {
      final feeAmounts = row['feeAmounts'] as Map<String, double>;
      for (final ft in feeTypes) {
        colTotals[ft] = (colTotals[ft] ?? 0) + (feeAmounts[ft] ?? 0);
      }
      grandTotal += row['total'] as double;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button + title
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () => setState(() {
                  _drilldownDate = null;
                  _drilldownDemands = [];
                }),
                tooltip: 'Back to date list',
              ),
              const SizedBox(width: 8),
              Icon(Icons.calendar_today, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                'Date: ${_formatDisplayDate(_drilldownDate!)}',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text('${studentRows.length} students', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            ],
          ),
        ),
        // Scrollable table
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.05)),
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              columnSpacing: 16,
              horizontalMargin: 16,
              columns: [
                const DataColumn(label: Text('S.No')),
                const DataColumn(label: Text('Date')),
                const DataColumn(label: Text('Adm.No')),
                const DataColumn(label: Text('Student Name')),
                const DataColumn(label: Text('Class')),
                ...feeTypes.map((ft) => DataColumn(label: Text(ft), numeric: true)),
                const DataColumn(label: Text('TOTAL'), numeric: true),
              ],
              rows: [
                ...List.generate(studentRows.length, (i) {
                  final row = studentRows[i];
                  final feeAmounts = row['feeAmounts'] as Map<String, double>;
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(_formatShortDate(row['date'] as String))),
                    DataCell(Text(row['admNo'] as String)),
                    DataCell(ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: Text(row['stuName'] as String, overflow: TextOverflow.ellipsis),
                    )),
                    DataCell(Text(row['stuClass'] as String)),
                    ...feeTypes.map((ft) {
                      final amt = feeAmounts[ft] ?? 0;
                      return DataCell(Text(amt > 0 ? _formatCurrency(amt) : '', textAlign: TextAlign.right));
                    }),
                    DataCell(Text(
                      _formatCurrency(row['total'] as double),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )),
                  ]);
                }),
                // TOTAL row
                DataRow(
                  color: WidgetStateProperty.all(AppColors.accent.withValues(alpha: 0.08)),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('TOTAL', style: TextStyle(fontWeight: FontWeight.w700))),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    ...feeTypes.map((ft) {
                      final amt = colTotals[ft] ?? 0;
                      return DataCell(Text(
                        amt > 0 ? _formatCurrency(amt) : '',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ));
                    }),
                    DataCell(Text(
                      _formatCurrency(grandTotal),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    )),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
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
                _buildSummaryCard(Icons.check_circle_outline, AppColors.success, _formatCurrency(_totalPaid), 'Total Paid'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.pending_outlined, AppColors.warning, _formatCurrency(_totalPending), 'Total Pending'),
                const SizedBox(width: 16),
                _buildSummaryCard(Icons.calendar_month, Colors.blue, '${_dateGroups.length}', 'Demand Dates'),
              ],
            ),
            const SizedBox(height: 16),
            // Date-wise demand table or drilldown detail
            if (_drilldownDate != null)
              _buildDrilldownDetail()
            else
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
                          Icon(Icons.date_range, size: 18, color: AppColors.accent),
                          const SizedBox(width: 8),
                          const Text('Date-wise Fee Demand', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const Spacer(),
                          Text('${_dateGroups.length} dates', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      color: AppColors.surface,
                      child: const Row(
                        children: [
                          SizedBox(width: 36),
                          Expanded(flex: 3, child: Text('Date', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                          Expanded(flex: 1, child: Text('Students', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                          Expanded(flex: 2, child: Text('Demand', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                          Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                          Expanded(flex: 2, child: Text('Pending', textAlign: TextAlign.right, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                          Expanded(flex: 1, child: Text('% Collected', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                          SizedBox(width: 26),
                        ],
                      ),
                    ),
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
                              const Text('No fee demands found', style: TextStyle(color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      )
                    else
                      ...List.generate(_dateGroups.length, (i) {
                        final g = _dateGroups[i];
                        final pct = g.totalDemand > 0 ? (g.totalPaid / g.totalDemand * 100) : 0.0;
                        return InkWell(
                          onTap: () {
                            setState(() {
                              _drilldownDate = g.date;
                              _drilldownDemands = g.demands;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                            decoration: const BoxDecoration(
                              border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 28,
                                  height: 28,
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Center(
                                    child: Text('${i + 1}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.accent)),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(flex: 3, child: Text(_formatDisplayDate(g.date), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                                Expanded(flex: 1, child: Text('${g.studentCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12))),
                                Expanded(flex: 2, child: Text(_formatCurrency(g.totalDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12))),
                                Expanded(flex: 2, child: Text(_formatCurrency(g.totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.success))),
                                Expanded(flex: 2, child: Text(_formatCurrency(g.totalPending), textAlign: TextAlign.right, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: g.totalPending > 0 ? AppColors.warning : AppColors.textSecondary))),
                                Expanded(
                                  flex: 1,
                                  child: Center(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: pct >= 100
                                            ? AppColors.success.withValues(alpha: 0.1)
                                            : pct >= 50
                                                ? Colors.orange.withValues(alpha: 0.1)
                                                : AppColors.warning.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${pct.toStringAsFixed(0)}%',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          color: pct >= 100 ? AppColors.success : pct >= 50 ? Colors.orange : AppColors.warning,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
                              ],
                            ),
                          ),
                        );
                      }),
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

