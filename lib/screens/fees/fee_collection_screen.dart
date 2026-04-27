import 'dart:io';
import '../../widgets/app_icon.dart';
import '../../widgets/app_search_field.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../models/fee_model.dart';
import '../../services/supabase_service.dart';
import '../../widgets/receipt_widget.dart';

/// Signals when a drilldown view is active inside the Fee Collection tab.
/// Parent screen listens to hide the tabs row while drilled in.
final ValueNotifier<bool> _feeCollectionDrilldownActive = ValueNotifier(false);

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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pill-style tabs (matches Reports page) — hidden when a drilldown is active.
        ValueListenableBuilder<bool>(
          valueListenable: _feeCollectionDrilldownActive,
          builder: (context, isDrilldown, _) {
            if (isDrilldown) return const SizedBox.shrink();
            return ListenableBuilder(
              listenable: _tabController,
              builder: (context, _) {
                final selected = _tabController.index;
                final tabLabels = ['Fee Collection', 'Class-wise Demand', 'Date-wise'];
                final tabIcons = ['wallet-money', 'book-1', 'calendar-1'];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (var i = 0; i < tabLabels.length; i++) ...[
                          GestureDetector(
                            onTap: () => _tabController.animateTo(i),
                            behavior: HitTestBehavior.opaque,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                              decoration: BoxDecoration(
                                color: selected == i ? AppColors.tabSelected : Colors.transparent,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon(tabIcons[i], size: 16, color: selected == i ? AppColors.textOnPrimary : AppColors.textPrimary),
                                  const SizedBox(width: 8),
                                  Text(
                                    tabLabels[i],
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: selected == i ? AppColors.textOnPrimary : AppColors.textPrimary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          if (i < tabLabels.length - 1) const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  ),
                );
              },
            );
          },
        ),
        SizedBox(height: 6.h),
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
  final Set<String> _filterMethods = {};
  bool _isLoading = false;
  List<Map<String, dynamic>> _payments = [];
  List<_DateGroup> _dateGroups = [];
  String? _selectedDate; // null = date list, non-null = drilldown
  Map<int, double> _payFineMap = {}; // pay_id -> fine amount (for drilldown display)
  int? _selectedPayId; // null = payment list, non-null = fee detail drilldown
  Map<String, dynamic>? _selectedPayment; // selected payment data
  List<Map<String, dynamic>>? _feeDetails;
  bool _loadingFeeDetails = false;
  // Card drilldowns
  bool _showPendingFees = false;
  bool _showTotalCollection = false;
  bool _showTodayCollection = false;
  String? _selectedPendingFeeGroup; // null = group list, non-null = course+class list
  String? _selectedPendingCourseClass; // "COURSE|CLASS"; null = course+class list, non-null = student drilldown
  List<Map<String, dynamic>> _demands = [];
  bool _isLoadingDemands = false;
  Map<int, String> _feeGroupById = {};
  Map<String, String> _feeGroupByName = {};
  Map<int, String> _stuIdToName = {};
  Map<int, String> _stuIdToClass = {};
  Map<int, String> _stuIdToCourse = {};
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
  // Pagination for date list
  int _dateListPage = 0;
  static const int _dateListPageSize = 10;
  // Pagination for date drilldown payments
  int _dateDrilldownPage = 0;
  static const int _dateDrilldownPageSize = 10;
  // Institution info for receipt
  String? _insName;
  String? _insAddress;
  String? _insLogoUrl;
  String? _insMobile;
  String? _insEmail;

  // Scroll controllers for horizontal scrollbar on each DataTable
  final ScrollController _methodSummaryScrollCtrl = ScrollController();
  final ScrollController _paymentDetailsScrollCtrl = ScrollController();
  final ScrollController _feeGroupScrollCtrl = ScrollController();
  final ScrollController _studentFeeScrollCtrl = ScrollController();
  final ScrollController _studentListScrollCtrl = ScrollController();
  final ScrollController _dateListScrollCtrl = ScrollController();
  final ScrollController _dateDrilldownScrollCtrl = ScrollController();
  final ScrollController _feeDetailScrollCtrl = ScrollController();

  bool _canScrollDateList = false;
  bool _canScrollDateDrilldown = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _loadInsInfo();
    _dateListScrollCtrl.addListener(_onDateListScrollChanged);
    _dateDrilldownScrollCtrl.addListener(_onDateDrilldownScrollChanged);
  }

  void _onDateListScrollChanged() {
    if (mounted) setState(() {});
  }

  void _onDateDrilldownScrollChanged() {
    if (mounted) setState(() {});
  }

  void _updateCanScrollDateList() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_dateListScrollCtrl.hasClients &&
          _dateListScrollCtrl.positions.isNotEmpty &&
          _dateListScrollCtrl.position.hasContentDimensions) {
        final canScroll = _dateListScrollCtrl.position.maxScrollExtent > 5;
        if (_canScrollDateList != canScroll) {
          setState(() => _canScrollDateList = canScroll);
        }
      } else {
        if (_canScrollDateList) setState(() => _canScrollDateList = false);
      }
    });
  }

  void _updateCanScrollDateDrilldown() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_dateDrilldownScrollCtrl.hasClients &&
          _dateDrilldownScrollCtrl.positions.isNotEmpty &&
          _dateDrilldownScrollCtrl.position.hasContentDimensions) {
        final canScroll = _dateDrilldownScrollCtrl.position.maxScrollExtent > 5;
        if (_canScrollDateDrilldown != canScroll) {
          setState(() => _canScrollDateDrilldown = canScroll);
        }
      } else {
        if (_canScrollDateDrilldown) setState(() => _canScrollDateDrilldown = false);
      }
    });
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
    _methodSummaryScrollCtrl.dispose();
    _paymentDetailsScrollCtrl.dispose();
    _feeGroupScrollCtrl.dispose();
    _studentFeeScrollCtrl.dispose();
    _studentListScrollCtrl.dispose();
    _dateListScrollCtrl.removeListener(_onDateListScrollChanged);
    _dateListScrollCtrl.dispose();
    _dateDrilldownScrollCtrl.removeListener(_onDateDrilldownScrollChanged);
    _dateDrilldownScrollCtrl.dispose();
    _feeDetailScrollCtrl.dispose();
    super.dispose();
  }

  Widget _buildDateScrollbar(ScrollController ctrl) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (context, _) {
        if (!ctrl.hasClients ||
            ctrl.positions.isEmpty ||
            !ctrl.position.hasContentDimensions) {
          return const SizedBox.shrink();
        }
        final maxExtent = ctrl.position.maxScrollExtent;
        if (maxExtent <= 5) return const SizedBox.shrink();
        final viewportWidth = ctrl.position.viewportDimension;
        final totalContentWidth = maxExtent + viewportWidth;
        final thumbRatio = (viewportWidth / totalContentWidth).clamp(0.1, 1.0);

        return LayoutBuilder(builder: (context, constraints) {
          final trackWidth = constraints.maxWidth - 40; // 20px per arrow button
          final thumbWidth = (trackWidth * thumbRatio).clamp(30.0, trackWidth);
          final trackSpace = trackWidth - thumbWidth;
          final scrollRatio = maxExtent > 0 ? (ctrl.offset / maxExtent).clamp(0.0, 1.0) : 0.0;
          final thumbOffset = trackSpace * scrollRatio;

          return Container(
            height: 20,
            decoration: const BoxDecoration(
              color: Color(0xFFF0F0F0),
              border: Border(top: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
            ),
            child: Row(
              children: [
                // Left arrow
                InkWell(
                  onTap: () => ctrl.animateTo(
                    (ctrl.offset - 100).clamp(0.0, maxExtent),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  ),
                  child: Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0E0E0),
                      border: Border(right: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
                    ),
                    child: const AppIcon.linear('Chevron Left', size: 16, color: Color(0xFF333333)),
                  ),
                ),
                // Track + thumb
                Expanded(
                  child: GestureDetector(
                    onHorizontalDragUpdate: (details) {
                      if (trackSpace > 0) {
                        final newRatio = ((thumbOffset + details.delta.dx) / trackSpace).clamp(0.0, 1.0);
                        ctrl.jumpTo(newRatio * maxExtent);
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
                  ),
                ),
                // Right arrow
                InkWell(
                  onTap: () => ctrl.animateTo(
                    (ctrl.offset + 100).clamp(0.0, maxExtent),
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  ),
                  child: Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0E0E0),
                      border: Border(left: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
                    ),
                    child: const AppIcon.linear('Chevron Right', size: 16, color: Color(0xFF333333)),
                  ),
                ),
              ],
            ),
          );
        });
      },
    );
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);

    // Stage 1: Fast — payments + fee group map + fee totals (single RPCs)
    final fastResults = await Future.wait([
      SupabaseService.getPaymentsByDateRange(insId, fromDate: _fromDate, toDate: _toDate),
      SupabaseService.getFeeGroupMaps(insId),
      SupabaseService.getFeeTotals(insId),
    ]);

    final payments = fastResults[0] as List<Map<String, dynamic>>;
    final feeGroupMaps = fastResults[1] as Map<String, Map>;
    final feeTotals = fastResults[2] as Map<String, double>;

    final today = DateTime.now();
    final todayStr = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    // Only reconciled (approved) payments count toward Total Collection.
    // Cash auto-reconciles (recon_status='R'); other methods stay 'P' until
    // bank reconciliation. Pending-approval money is shown on its own card.
    double totalCollectionFromPayments = 0;
    double todayCollection = 0;
    double pendingApprovalAmt = 0;
    final List<int> todayPayIds = [];
    final List<int> allPayIds = [];
    for (final p in payments) {
      final reconStatus = p['recon_status']?.toString() ?? 'P';
      final amt = (p['transtotalamount'] as num?)?.toDouble() ?? 0;
      if (reconStatus == 'P') {
        pendingApprovalAmt += amt;
        continue;
      }
      if (reconStatus != 'R') continue; // skip any other non-approved
      totalCollectionFromPayments += amt;
      final pid = p['pay_id'] as int?;
      if (pid != null) allPayIds.add(pid);
      final payDate = _extractDate(p['paydate']);
      if (payDate == todayStr) {
        todayCollection += amt;
        if (pid != null) todayPayIds.add(pid);
      }
    }

    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final p in payments) {
      final dateStr = _extractDate(p['paydate']);
      grouped.putIfAbsent(dateStr, () => []).add(p);
    }

    // Fetch fine amount per pay_id so each date group can display fine separately
    final Map<int, double> payFineMap = {};
    final payIds = payments
        .map((p) => p['pay_id'] as int?)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();
    for (var i = 0; i < payIds.length; i += 500) {
      final chunk = payIds.sublist(i, (i + 500).clamp(0, payIds.length));
      try {
        final rows = await SupabaseService.fromSchema('feedemand')
            .select('pay_id, fineamount')
            .eq('ins_id', insId)
            .inFilter('pay_id', chunk)
            .gt('fineamount', 0);
        for (final r in (rows as List)) {
          final pid = r['pay_id'] as int?;
          final amt = (r['fineamount'] as num?)?.toDouble() ?? 0;
          if (pid != null) payFineMap[pid] = (payFineMap[pid] ?? 0) + amt;
        }
      } catch (_) {}
    }

    final dateGroups = grouped.entries.map((e) {
      double total = 0;
      double fine = 0;
      for (final p in e.value) {
        total += (p['transtotalamount'] as num?)?.toDouble() ?? 0;
        final pid = p['pay_id'] as int?;
        if (pid != null) fine += payFineMap[pid] ?? 0;
      }
      return _DateGroup(date: e.key, payments: e.value, totalAmount: total, totalFine: fine);
    }).toList();
    dateGroups.sort((a, b) => b.date.compareTo(a.date));

    double todayFine = 0;
    for (final pid in todayPayIds) {
      todayFine += payFineMap[pid] ?? 0;
    }
    double totalFineFromPayments = 0;
    for (final pid in allPayIds) {
      totalFineFromPayments += payFineMap[pid] ?? 0;
    }

    if (mounted) {
      setState(() {
        _payments = payments;
        _dateGroups = dateGroups;
        _payFineMap = payFineMap;
        _todayCollection = todayCollection;
        _todayFine = todayFine;
        _feeGroupById = Map<int, String>.from(feeGroupMaps['byId'] ?? {});
        _feeGroupByName = Map<String, String>.from(feeGroupMaps['byName'] ?? {});
        // Both totals come from the SAME source (payments table) so they tally:
        // total_collection ≥ today_collection always holds, and the fee/fine
        // breakdown comes from the same payFineMap for consistency.
        _totalCollection = totalCollectionFromPayments;
        _totalFine = totalFineFromPayments;
        _pendingApproval = pendingApprovalAmt;
        _pendingFees = feeTotals['totalPending'] ?? 0;
        _isLoading = false;
      });
    }

    // Stage 2: Deferred — load demands only when needed (Class-wise tab or Pending click)
    // This reduces startup DB load significantly
  }

  bool _demandsLoaded = false;
  Future<void> _loadDemandsIfNeeded() async {
    if (_demandsLoaded) return;
    _demandsLoaded = true;
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
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
    final stuIdToClass = <int, String>{};
    final stuIdToCourse = <int, String>{};
    final admNoToName = <String, String>{};
    for (final entry in studentNameMap.entries) {
      stuIdToName[entry.key] = entry.value['stuname'] ?? '';
      stuIdToClass[entry.key] = entry.value['stuclass'] ?? '';
      stuIdToCourse[entry.key] = entry.value['courname'] ?? '';
      admNoToName[entry.value['stuadmno'] ?? ''] = entry.value['stuname'] ?? '';
    }

    if (mounted) {
      setState(() {
        _demands = demands;
        _pendingFees = pendingFees;
        _stuIdToName = stuIdToName;
        _stuIdToClass = stuIdToClass;
        _stuIdToCourse = stuIdToCourse;
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
  double _todayFine = 0;
  double _totalCollection = 0;
  double _totalFine = 0;
  double _pendingApproval = 0;

  Widget _buildDateChip(String label, DateTime date, VoidCallback onTap) {
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
            AppIcon.linear('calendar', size: 14, color: AppColors.accent),
            SizedBox(width: 6.w),
            Text(_formatFilterDate(date), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilter(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
      ),
    );
  }

  Widget _buildSummaryCard(String icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: AppIcon(icon, color: iconColor, size: 18),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(label, style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary)),
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

    final isDrilldown = _showTotalCollection ||
        _showTodayCollection ||
        _showPendingFees ||
        _selectedPayId != null ||
        _selectedDate != null;
    // Notify parent so the tabs row can hide while drilled in.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_feeCollectionDrilldownActive.value != isDrilldown) {
        _feeCollectionDrilldownActive.value = isDrilldown;
      }
    });

    return RefreshIndicator(
      onRefresh: _fetchData,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isDrilldown) ...[
            // Summary cards — IntrinsicHeight makes all 3 cards the same height
            // so the Pending card stretches to match the breakdown cards.
            IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildClickableSummaryCard(
                  'indianrupeesign.circle.fill',
                  AppColors.accent,
                  _formatCurrency(_totalCollection),
                  'Total Collection',
                  () {
                    setState(() {
                      _showTotalCollection = true;
                      _showTodayCollection = false;
                      _showPendingFees = false;
                      _selectedDate = null;
                      _selectedPayId = null;
                    });
                  },
                  feeAmount: _formatCurrency(_totalCollection - _totalFine),
                  fineAmount: _formatCurrency(_totalFine),
                ),
                SizedBox(width: 8.w),
                _buildClickableSummaryCard(
                  'calendar-1',
                  Colors.blue,
                  _formatCurrency(_todayCollection),
                  'Today Collection',
                  () {
                    setState(() {
                      _showTodayCollection = true;
                      _showTotalCollection = false;
                      _showPendingFees = false;
                      _selectedDate = null;
                      _selectedPayId = null;
                    });
                  },
                  feeAmount: _formatCurrency(_todayCollection - _todayFine),
                  fineAmount: _formatCurrency(_todayFine),
                ),
                SizedBox(width: 8.w),
                _buildClickableSummaryCard(
                  'clock',
                  const Color(0xFFFB8C00),
                  _formatCurrency(_pendingApproval),
                  'Pending Approval',
                  () {},
                  hasDrilldown: false,
                ),
                SizedBox(width: 8.w),
                _buildClickableSummaryCard('timer', Colors.orange, _isLoadingDemands ? 'Loading...' : _formatCurrency(_pendingFees), 'Pending Fees', () {
                  _loadDemandsIfNeeded();
                  setState(() {
                    _showPendingFees = true;
                    _showTotalCollection = false;
                    _showTodayCollection = false;
                    _selectedDate = null;
                    _selectedPayId = null;
                    _pendingFeeTypeFilter = null;
                    _pendingClassFilter = null;
                  });
                }, hasDrilldown: false),
              ],
            ),
            ),
            SizedBox(height: 16.h),
            ],
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

    // Method filter is a fixed Cash/Bank list (hardcoded in the dropdown
    // items below). Classes are pulled from all demands so the filter is
    // populated even on a day with no collections.
    final classSet = <String>{};
    for (final d in _demands) {
      final cls = d['stuclass']?.toString();
      if (cls != null && cls.isNotEmpty) classSet.add(cls);
    }
    for (final p in _payments) {
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
      if (_collectionMethodFilter != null) {
        final raw = (p['paymethod']?.toString() ?? '').toLowerCase();
        final bucket = raw == 'cash' ? 'Cash' : 'Bank';
        if (bucket != _collectionMethodFilter) return false;
      }
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

    // Group by payment method — cash stays as 'cash', everything else (cheque,
    // qr_upi, razorpay, …) is lumped under 'Bank' for the summary.
    final Map<String, List<Map<String, dynamic>>> byMethod = {};
    for (final p in filtered) {
      final raw = (p['paymethod']?.toString() ?? 'Unknown').toLowerCase();
      final method = raw == 'cash' ? 'Cash' : 'Bank';
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
        // Back + breadcrumb — white card
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
          children: [
            InkWell(
              onTap: () => setState(() {
                _showTotalCollection = false;
                _showTodayCollection = false;
                _collectionMethodFilter = null;
                _collectionClassFilter = null;
                _collectionSearchQuery = '';
              }),
              borderRadius: BorderRadius.circular(10.r),
              child: Container(
                height: 40,
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: AppColors.accent,
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                    SizedBox(width: 6.w),
                    Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                  ],
                ),
              ),
            ),
            SizedBox(width: 12.w),
            Container(width: 1, height: 18, color: AppColors.border),
            SizedBox(width: 12.w),
            Text('Fee Collection', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            SizedBox(width: 6.w),
            AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
            SizedBox(width: 6.w),
            Text(
              todayOnly ? 'Today Collection' : 'Total Collection',
              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
            ),
            if (todayOnly) ...[
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12.r),
                ),
                child: Text(todayStr, style: TextStyle(fontSize: 13.sp, color: Colors.blue, fontWeight: FontWeight.w500)),
              ),
            ],
            const Spacer(),
            // Search field
            AppSearchField(
              hintText: 'Search student / pay no...',
              onChanged: (v) => setState(() => _collectionSearchQuery = v),
              width: 220,
            ),
            SizedBox(width: 8.w),
            // Payment Method dropdown
            SizedBox(
              height: 40,
              child: DropdownButtonHideUnderline(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButton<String?>(
                    value: _collectionMethodFilter,
                    hint: Text('All Methods', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    icon: AppIcon.linear('Chevron Down', size: 18),
                    isDense: true,
                    // Cash vs Bank matches the Method-wise Summary grouping.
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('All Methods')),
                      DropdownMenuItem<String?>(value: 'Cash', child: Text('Cash')),
                      DropdownMenuItem<String?>(value: 'Bank', child: Text('Bank')),
                    ],
                    onChanged: (v) => setState(() => _collectionMethodFilter = v),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            // Class dropdown
            SizedBox(
              height: 40,
              child: DropdownButtonHideUnderline(
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 14.w),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10.r),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: DropdownButton<String?>(
                    value: _collectionClassFilter,
                    hint: Text('All Classes', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    icon: AppIcon.linear('Chevron Down', size: 18),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All Classes')),
                      ...classes.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                    ],
                    onChanged: (v) => setState(() => _collectionClassFilter = v),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            SizedBox(
              height: 40,
              child: ElevatedButton.icon(
                onPressed: filtered.isNotEmpty ? () => _exportCollectionSummaryExcel(filtered) : null,
                icon: AppIcon('document-download', size: 16, color: Colors.white),
                label: const Text('Export'),
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
        SizedBox(height: 12.h),
        // Summary row
        Row(
          children: [
            _buildSummaryCard('receipt-2', AppColors.accent, '$totalCount', 'Transactions'),
            SizedBox(width: 12.w),
            _buildSummaryCard('people', Colors.blue, '${allStuIds.length}', 'Students'),
            SizedBox(width: 12.w),
            _buildSummaryCard('indianrupeesign.circle.fill', AppColors.success, _formatCurrency(total), 'Total Amount'),
          ],
        ),
        SizedBox(height: 12.h),
        // Payment method-wise table
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    AppIcon('wallet-money', size: 18, color: AppColors.accent),
                    SizedBox(width: 8.w),
                    Text('Method-wise Summary', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${methodKeys.length} methods', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (methodKeys.isEmpty)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No collections found', style: TextStyle(color: AppColors.textSecondary))))
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: LayoutBuilder(builder: (context, constraints) {
                  return Scrollbar(
                    controller: _methodSummaryScrollCtrl,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: SingleChildScrollView(
                    controller: _methodSummaryScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(dividerThickness: 0,
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
                        headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
                        dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
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
                            return DataRow(color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF7FAFC)), cells: [
                              DataCell(Text('${idx + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                              DataCell(Text(method, style: const TextStyle(fontWeight: FontWeight.w600))),
                              DataCell(Text('${items.length}')),
                              DataCell(Text('${mStuIds.length}')),
                              DataCell(Text(_formatCurrency(mTotal), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success))),
                            ]);
                          }),
                          DataRow(color: WidgetStateProperty.all(AppColors.tableHeadBg), cells: [
                            const DataCell(Text('')),
                            DataCell(Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text('$totalCount', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text('${allStuIds.length}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text(_formatCurrency(total), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  );
                })),
              ),
            ],
          ),
        ),
        SizedBox(height: 16.h),
        // Individual payment list
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    AppIcon.linear('receipt-2', size: 18, color: AppColors.accent),
                    SizedBox(width: 8.w),
                    Text('Payment Details', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                    const Spacer(),
                    Text('${filtered.length} records', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (filtered.isEmpty)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No payments found', style: TextStyle(color: AppColors.textSecondary))))
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: LayoutBuilder(builder: (context, constraints) {
                  return Scrollbar(
                    controller: _paymentDetailsScrollCtrl,
                    thumbVisibility: true,
                    trackVisibility: true,
                    child: SingleChildScrollView(
                    controller: _paymentDetailsScrollCtrl,
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: constraints.maxWidth),
                      child: DataTable(dividerThickness: 0,
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
                        headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
                        dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
                        columns: const [
                          DataColumn(label: Text('S No.')),
                          DataColumn(label: Text('PAY NO')),
                          DataColumn(label: Text('STUDENT')),
                          DataColumn(label: Text('COURSE')),
                          DataColumn(label: Text('CLASS')),
                          DataColumn(label: Text('DATE')),
                          DataColumn(label: Text('METHOD')),
                          DataColumn(label: Text('AMOUNT'), numeric: true),
                        ],
                        rows: [
                          ...filtered.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final p = entry.value;
                            final stuId = p['stu_id'] as int?;
                            final stuName = p['stuname']?.toString().isNotEmpty == true ? p['stuname'].toString()
                                : (stuId != null && _stuIdToName.containsKey(stuId)) ? _stuIdToName[stuId]!
                                : (p['stuadmno']?.toString() ?? '-');
                            final stuCourse = p['courname']?.toString().isNotEmpty == true ? p['courname'].toString()
                                : (stuId != null && _stuIdToCourse.containsKey(stuId)) ? _stuIdToCourse[stuId]! : '-';
                            final stuClass = p['stuclass']?.toString().isNotEmpty == true ? p['stuclass'].toString()
                                : (stuId != null && _stuIdToClass.containsKey(stuId)) ? _stuIdToClass[stuId]! : '-';
                            final amount = (p['transtotalamount'] as num?)?.toDouble() ?? 0;
                            return DataRow(color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF7FAFC)), cells: [
                              DataCell(Text('${idx + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                              DataCell(Text(p['paynumber']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w500))),
                              DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 200), child: Text(stuName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w500)))),
                              DataCell(Text(stuCourse)),
                              DataCell(Text(stuClass)),
                              DataCell(Text(_formatDate(p['paydate']))),
                              DataCell(Text(p['paymethod']?.toString() ?? '-')),
                              DataCell(Text(_formatCurrency(amount), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.success))),
                            ]);
                          }),
                          DataRow(color: WidgetStateProperty.all(AppColors.tableHeadBg), cells: [
                            const DataCell(Text('')),
                            DataCell(Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            DataCell(Text(_formatCurrency(total), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  );
                })),
              ),
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

  Widget _buildClickableSummaryCard(
    String icon,
    Color iconColor,
    String value,
    String label,
    VoidCallback onTap, {
    String? subtitle,
    String? feeAmount,
    String? fineAmount,
    bool hasDrilldown = true,
  }) {
    final showBreakdown = feeAmount != null || fineAmount != null;
    return Expanded(
      child: InkWell(
        onTap: hasDrilldown ? onTap : null,
        borderRadius: BorderRadius.circular(12.r),
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: iconColor.withValues(alpha: 0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Top half — icon + large value + label
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 14.h),
                child: Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(10.w),
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: AppIcon(icon, color: iconColor, size: 24),
                    ),
                    SizedBox(width: 12.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(value, style: TextStyle(fontSize: 20.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                          SizedBox(height: 2.h),
                          Text(label, style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                          if (!showBreakdown && subtitle != null) ...[
                            SizedBox(height: 4.h),
                            Text(subtitle, style: TextStyle(fontSize: 10.sp, color: Colors.orange.shade700, fontWeight: FontWeight.w600)),
                          ],
                        ],
                      ),
                    ),
                    if (hasDrilldown) ...[
                      SizedBox(width: 6.w),
                      Container(
                        padding: EdgeInsets.all(4.w),
                        decoration: BoxDecoration(color: iconColor.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(6.r)),
                        child: AppIcon.linear('Chevron Right', size: 16, color: iconColor),
                      ),
                    ],
                  ],
                ),
              ),
              // Bottom half — split bar with FEE (green tint) + FINE (orange tint)
              if (showBreakdown)
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.success.withValues(alpha: 0.08),
                          border: Border(top: BorderSide(color: AppColors.success.withValues(alpha: 0.2))),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                        child: Row(
                          children: [
                            Text('Fee: ', style: TextStyle(fontSize: 11.sp, color: AppColors.success, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                            Flexible(child: Text(feeAmount ?? '-', style: TextStyle(fontSize: 13.sp, color: AppColors.success, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.08),
                          border: Border(top: BorderSide(color: Colors.orange.withValues(alpha: 0.2))),
                        ),
                        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
                        child: Row(
                          children: [
                            Text('Fine: ', style: TextStyle(fontSize: 11.sp, color: Colors.orange.shade800, fontWeight: FontWeight.w700, letterSpacing: 0.3)),
                            Flexible(child: Text(fineAmount ?? '-', style: TextStyle(fontSize: 13.sp, color: Colors.orange.shade800, fontWeight: FontWeight.w700), overflow: TextOverflow.ellipsis)),
                          ],
                        ),
                      ),
                    ),
                  ],
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
    // All rows with non-zero fee amount or any payment activity
    final activeDemands = _demands.where((d) {
      final fee = (d['feeamount'] as num?)?.toDouble() ?? 0;
      final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
      return fee > 0 || paid > 0;
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
      final feeTypeName = d['demfeetype']?.toString() ?? '';
      String groupName;
      if (feeId != null && _feeGroupById.containsKey(feeId)) {
        groupName = _feeGroupById[feeId]!;
      } else if (feeTypeName.isNotEmpty && _feeGroupByName.containsKey(feeTypeName)) {
        groupName = _feeGroupByName[feeTypeName]!;
      } else {
        groupName = 'Uncategorized';
      }
      groupedByFeeGroup.putIfAbsent(groupName, () => []).add(d);
    }

    final groupKeys = groupedByFeeGroup.keys.toList()..sort();

    // If a fee group is selected, show course+class drilldown.
    // Pass ALL demands (paid + unpaid) so PAID/FINE totals match the fee-group
    // row above. The student-list level applies the balance>0 filter itself.
    if (_selectedPendingFeeGroup != null && groupedByFeeGroup.containsKey(_selectedPendingFeeGroup)) {
      final drilldownDemands = groupedByFeeGroup[_selectedPendingFeeGroup] ?? [];
      return _buildPendingStudentList(_selectedPendingFeeGroup!, drilldownDemands, feeTypes, classes);
    }

    // Compute totals from filtered demands (consistent with group rows)
    double totalDemand = 0, totalPaid = 0, totalFine = 0, totalBalance = 0;
    final allStuIds = <String>{};
    for (final d in filtered) {
      totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
      final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
      final isPaid = pa > 0 || d['paidstatus'] == 'P';
      totalPaid += pa - (isPaid ? fa : 0);
      totalFine += isPaid ? fa : 0;
      totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
      if (((d['balancedue'] as num?)?.toDouble() ?? 0) > 0) {
        final stuId = d['stu_id']?.toString();
        if (stuId != null) allStuIds.add(stuId);
      }
    }
    final int totalStudents = allStuIds.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button + breadcrumb
        Row(
          children: [
            InkWell(
              onTap: () => setState(() {
                _showPendingFees = false;
                _pendingSearchQuery = '';
                _pendingFeeTypeFilter = null;
                _pendingClassFilter = null;
                _selectedPendingFeeGroup = null;
                _selectedPendingCourseClass = null;
                _selectedStudentKey = null;
                _selectedStudentDemands = null;
              }),
              borderRadius: BorderRadius.circular(8.r),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8.r)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                  SizedBox(width: 6.w),
                  Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                ]),
              ),
            ),
            SizedBox(width: 12.w),
            Container(width: 1, height: 18, color: AppColors.border),
            SizedBox(width: 12.w),
            Text('Fee Collection', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            SizedBox(width: 6.w),
            AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
            SizedBox(width: 6.w),
            Text('Pending Fees', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            const Spacer(),
            // Search field
            AppSearchField(
              hintText: 'Search student / roll no...',
              onChanged: (v) => setState(() => _pendingSearchQuery = v),
              width: 220,
            ),
            SizedBox(width: 8.w),
            // Fee Type dropdown
            SizedBox(
              height: 40,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _pendingFeeTypeFilter,
                    hint: Text('All Fee Types', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    icon: AppIcon.linear('Chevron Down', size: 18),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All Fee Types')),
                      ...feeTypes.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                    ],
                    onChanged: (v) => setState(() => _pendingFeeTypeFilter = v),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            // Class dropdown
            SizedBox(
              height: 40,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _pendingClassFilter,
                    hint: Text('All Classes', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    icon: AppIcon.linear('Chevron Down', size: 18),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All Classes')),
                      ...classes.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                    ],
                    onChanged: (v) => setState(() => _pendingClassFilter = v),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            TextButton.icon(
              onPressed: filtered.isNotEmpty ? () {
                final pendingFiltered = filtered.where((d) => d['paidstatus']?.toString() == 'U').toList();
                if (pendingFiltered.isNotEmpty) {
                  _exportPendingToExcel(pendingFiltered, totalDemand, totalPaid, totalBalance, totalStudents);
                }
              } : null,
              icon: AppIcon('document-download', size: 16),
              label: const Text('Export'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.accent,
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        // Summary row
        Row(
          children: [
            _buildSummaryCard('people', Colors.blue, totalStudents.toString(), 'Students'),
            SizedBox(width: 12.w),
            _buildSummaryCard('wallet-1', AppColors.accent, _formatCurrency(totalDemand), 'Total Demand'),
            SizedBox(width: 12.w),
            _buildSummaryCard('tick-circle', AppColors.success, _formatCurrency(totalPaid), 'Total Paid'),
            SizedBox(width: 12.w),
            _buildSummaryCard('clock', Colors.orange, _formatCurrency(totalBalance), 'Balance Due'),
          ],
        ),
        SizedBox(height: 12.h),
        // Fee group-wise table
        LayoutBuilder(builder: (context, constraints) {
          return Scrollbar(controller: _feeGroupScrollCtrl, thumbVisibility: true, trackVisibility: true, child: SingleChildScrollView(controller: _feeGroupScrollCtrl, scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(dividerThickness: 0,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
              headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
              dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('FEE GROUP')),
                DataColumn(label: Text('STUDENTS'), numeric: true),
                DataColumn(label: Text('TOTAL DEMAND'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('FINE'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Expanded(child: Text('ACTION', textAlign: TextAlign.right))),
              ],
              rows: groupKeys.isEmpty ? [
                const DataRow(cells: [
                  DataCell(Text('')), DataCell(Text('No pending fees found')), DataCell(Text('')),
                  DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')),
                ]),
              ] : [
                ...groupKeys.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final groupName = entry.value;
                  final items = groupedByFeeGroup[groupName]!;
                  double gDemand = 0, gPaid = 0, gFine = 0, gBalance = 0;
                  final gStuIds = <String>{};
                  for (final d in items) {
                    gDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
                    final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                    final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                    final isPaid = pa > 0 || d['paidstatus'] == 'P';
                    gPaid += pa - (isPaid ? fa : 0);
                    gFine += isPaid ? fa : 0;
                    gBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
                    if (((d['balancedue'] as num?)?.toDouble() ?? 0) > 0) {
                      final sid = d['stu_id']?.toString();
                      if (sid != null) gStuIds.add(sid);
                    }
                  }
                  return DataRow(
                    color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF7FAFC)),
                    onSelectChanged: (_) => setState(() => _selectedPendingFeeGroup = groupName),
                    cells: [
                      DataCell(Text('${idx + 1}')),
                      DataCell(Text(groupName, style: const TextStyle(fontWeight: FontWeight.w600))),
                      DataCell(Text('${gStuIds.length}')),
                      DataCell(Text(_formatCurrency(gDemand))),
                      DataCell(Text(_formatCurrency(gPaid), style: const TextStyle(color: AppColors.success))),
                      DataCell(Text(gFine > 0 ? _formatCurrency(gFine) : '-', style: TextStyle(color: gFine > 0 ? Colors.orange : AppColors.textSecondary))),
                      DataCell(Text(_formatCurrency(gBalance), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange))),
                      DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
                      )),
                    ],
                  );
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(AppColors.tableHeadBg),
                  cells: [
                    const DataCell(Text('')),
                    DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text('$totalStudents', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalDemand), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalPaid), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalFine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalBalance), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          )));
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
      final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
      totalPaid += pa - ((pa > 0 || d['paidstatus'] == 'P') ? fa : 0);
      totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back + breadcrumb
        Row(
          children: [
            InkWell(
              onTap: () => setState(() {
                _selectedStudentKey = null;
                _selectedStudentDemands = null;
              }),
              borderRadius: BorderRadius.circular(8.r),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8.r)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                  SizedBox(width: 6.w),
                  Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                ]),
              ),
            ),
            SizedBox(width: 12.w),
            Container(width: 1, height: 18, color: AppColors.border),
            SizedBox(width: 12.w),
            Text('Pending Fees', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            SizedBox(width: 6.w),
            AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
            SizedBox(width: 6.w),
            Text(stuName, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(width: 6.w),
            Text('($admNo · $stuClass)', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          ],
        ),
        SizedBox(height: 12.h),
        // Summary cards
        Row(
          children: [
            _buildSummaryCard('wallet-1', AppColors.accent, _formatCurrency(totalDemand), 'Total Demand'),
            SizedBox(width: 12.w),
            _buildSummaryCard('tick-circle', AppColors.success, _formatCurrency(totalPaid), 'Total Paid'),
            SizedBox(width: 12.w),
            _buildSummaryCard('clock', Colors.orange, _formatCurrency(totalBalance), 'Balance Due'),
          ],
        ),
        SizedBox(height: 12.h),
        // Fee details table
        LayoutBuilder(builder: (context, constraints) {
          return Scrollbar(controller: _studentFeeScrollCtrl, thumbVisibility: true, trackVisibility: true, child: SingleChildScrollView(controller: _studentFeeScrollCtrl, scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(dividerThickness: 0,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
              headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
              dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('SEMESTER')),
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
                  final dFeeId = d['fee_id'] as int?;
                  final dFeeType = d['demfeetype']?.toString() ?? '-';
                  final feeGroupName = (dFeeId != null && _feeGroupById.containsKey(dFeeId))
                      ? _feeGroupById[dFeeId]!
                      : (_feeGroupByName[dFeeType] ?? dFeeType);
                  final amount = (d['feeamount'] as num?)?.toDouble() ?? 0;
                  final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                  final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                  final paid = pa - ((pa > 0 || d['paidstatus'] == 'P') ? fa : 0);
                  final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  final statusLabel = balance <= 0 ? 'Paid' : paid > 0 ? 'Partial' : 'Unpaid';
                  final statusColor = balance <= 0 ? AppColors.success : paid > 0 ? AppColors.warning : Colors.red;
                  return DataRow(color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7FAFC)), cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(term)),
                    DataCell(Text(feeGroupName, style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(Text(_formatCurrency(amount))),
                    DataCell(Text(_formatCurrency(paid), style: const TextStyle(color: AppColors.success))),
                    DataCell(Text(_formatCurrency(balance), style: TextStyle(fontWeight: FontWeight.w600, color: balance > 0 ? Colors.orange : AppColors.textSecondary))),
                    DataCell(Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(statusLabel, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: statusColor)),
                    )),
                  ]);
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(AppColors.tableHeadBg),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalDemand), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalPaid), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalBalance), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          )));
        }),
      ],
    );
  }

  /// Intermediate drilldown: Fee Group → Course + Class groups.
  /// Shown between "Pending Fees > SCHOOL FEES" and the student list.
  Widget _buildPendingCourseClassList(String feeGroupName, List<Map<String, dynamic>> groupDemands) {
    // Group demands by "COURSE|CLASS"
    final Map<String, List<Map<String, dynamic>>> byGroup = {};
    for (final d in groupDemands) {
      final course = d['courname']?.toString() ?? '-';
      final cls = d['stuclass']?.toString() ?? '-';
      final key = '$course|$cls';
      byGroup.putIfAbsent(key, () => []).add(d);
    }

    // Build per-group totals
    final groupKeys = byGroup.keys.toList();
    groupKeys.sort((a, b) {
      final pa = a.split('|');
      final pb = b.split('|');
      final courseCmp = pa[0].compareTo(pb[0]);
      if (courseCmp != 0) return courseCmp;
      return _compareClass(pa.length > 1 ? pa[1] : '', pb.length > 1 ? pb[1] : '');
    });

    double grandDemand = 0, grandPaid = 0, grandFine = 0, grandBalance = 0;
    int grandStudents = 0;
    final groupRows = <Map<String, dynamic>>[];
    for (final key in groupKeys) {
      final demands = byGroup[key]!;
      double gDemand = 0, gPaid = 0, gFine = 0, gBalance = 0;
      final stuIds = <String>{};
      for (final d in demands) {
        gDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
        final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
        final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
        final isPaid = pa > 0 || d['paidstatus'] == 'P';
        gPaid += pa - (isPaid ? fa : 0);
        gFine += isPaid ? fa : 0;
        gBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
        final sid = d['stu_id']?.toString() ?? d['stuadmno']?.toString();
        if (sid != null) stuIds.add(sid);
      }
      grandDemand += gDemand;
      grandPaid += gPaid;
      grandFine += gFine;
      grandBalance += gBalance;
      grandStudents += stuIds.length;
      final parts = key.split('|');
      groupRows.add({
        'key': key,
        'course': parts[0],
        'class': parts.length > 1 ? parts[1] : '',
        'students': stuIds.length,
        'demand': gDemand,
        'paid': gPaid,
        'fine': gFine,
        'balance': gBalance,
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Breadcrumb / back
        Row(
          children: [
            InkWell(
              onTap: () => setState(() {
                _selectedPendingFeeGroup = null;
                _selectedPendingCourseClass = null;
              }),
              borderRadius: BorderRadius.circular(8.r),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8.r)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                  SizedBox(width: 6.w),
                  Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                ]),
              ),
            ),
            SizedBox(width: 12.w),
            Container(width: 1, height: 18, color: AppColors.border),
            SizedBox(width: 12.w),
            Text('Pending Fees', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
            SizedBox(width: 6.w),
            AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
            SizedBox(width: 6.w),
            Text(feeGroupName, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ],
        ),
        SizedBox(height: 12.h),
        // Course + Class table
        LayoutBuilder(builder: (context, constraints) {
          return SingleChildScrollView(scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              dividerThickness: 0,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
              headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
              dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('COURSE')),
                DataColumn(label: Text('CLASS')),
                DataColumn(label: Text('STUDENTS'), numeric: true),
                DataColumn(label: Text('TOTAL DEMAND'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('FINE'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Expanded(child: Text('ACTION', textAlign: TextAlign.right))),
              ],
              rows: groupRows.isEmpty ? [
                const DataRow(cells: [
                  DataCell(Text('')), DataCell(Text('No data')), DataCell(Text('')), DataCell(Text('')),
                  DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')),
                ]),
              ] : [
                ...groupRows.asMap().entries.map((e) {
                  final i = e.key;
                  final r = e.value;
                  return DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF7FAFC)),
                    onSelectChanged: (_) => setState(() => _selectedPendingCourseClass = r['key'] as String),
                    cells: [
                      DataCell(Text('${i + 1}')),
                      DataCell(Text(r['course'] as String, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.primary))),
                      DataCell(Text(r['class'] as String)),
                      DataCell(Text('${r['students']}')),
                      DataCell(Text(_formatCurrency(r['demand'] as double))),
                      DataCell(Text(_formatCurrency(r['paid'] as double), style: const TextStyle(color: AppColors.success))),
                      DataCell(Text((r['fine'] as double) > 0 ? _formatCurrency(r['fine'] as double) : '-', style: TextStyle(color: (r['fine'] as double) > 0 ? Colors.orange : AppColors.textSecondary))),
                      DataCell(Text(_formatCurrency(r['balance'] as double), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange))),
                      DataCell(Align(
                        alignment: Alignment.centerRight,
                        child: AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
                      )),
                    ],
                  );
                }),
                // Grand total
                DataRow(
                  color: WidgetStateProperty.all(AppColors.tableHeadBg),
                  cells: [
                    const DataCell(Text('')),
                    DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    const DataCell(Text('')),
                    DataCell(Text('$grandStudents', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(grandDemand), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(grandPaid), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(grandFine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(grandBalance), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
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
    // If no course+class selected, show the course+class aggregate list.
    if (_selectedPendingCourseClass == null) {
      return _buildPendingCourseClassList(feeGroupName, groupDemands);
    }

    // Filter to the selected course+class. Include all demands (paid +
    // unpaid) so the student-list totals match the course+class row above.
    // Pending status is conveyed by the per-student status badge.
    final parts = _selectedPendingCourseClass!.split('|');
    final selCourse = parts.isNotEmpty ? parts[0] : '';
    final selClass = parts.length > 1 ? parts[1] : '';
    final filteredDemands = groupDemands.where((d) {
      final c = d['courname']?.toString() ?? '';
      final cl = d['stuclass']?.toString() ?? '';
      return c == selCourse && cl == selClass;
    }).toList();

    // Group by student
    final Map<String, List<Map<String, dynamic>>> byStudent = {};
    for (final d in filteredDemands) {
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
    double totalDemand = 0, totalPaid = 0, totalFine = 0, totalBalance = 0;
    for (final key in studentKeys) {
      for (final d in byStudent[key]!) {
        totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
        final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
        final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
        final isPaid = pa > 0 || d['paidstatus'] == 'P';
        totalPaid += pa - (isPaid ? fa : 0);
        totalFine += isPaid ? fa : 0;
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
              icon: AppIcon.linear('Chevron Left', size: 20),
              onPressed: () => setState(() {
                _selectedPendingCourseClass = null;
                _pendingStudentSearch = '';
                _pendingPage = 0;
              }),
              tooltip: 'Back to Courses',
            ),
            SizedBox(width: 4.w),
            AppIcon('folder-2', size: 18, color: AppColors.accent),
            SizedBox(width: 8.w),
            InkWell(
              onTap: () => setState(() {
                _selectedPendingFeeGroup = null;
                _selectedPendingCourseClass = null;
              }),
              child: Text('Pending Fees', style: TextStyle(fontSize: 13.sp, color: AppColors.accent)),
            ),
            SizedBox(width: 4.w),
            AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
            SizedBox(width: 4.w),
            InkWell(
              onTap: () => setState(() {
                _selectedPendingCourseClass = null;
              }),
              child: Text(feeGroupName, style: TextStyle(fontSize: 13.sp, color: AppColors.accent)),
            ),
            SizedBox(width: 4.w),
            AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
            SizedBox(width: 4.w),
            Text(_selectedPendingCourseClass!.replaceAll('|', ' > '),
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            const Spacer(),
            // Search field
            AppSearchField(
              controller: _pendingStudentSearchController,
              hintText: 'Search student / roll no...',
              onChanged: (v) => setState(() {
                _pendingStudentSearch = v;
                _pendingPage = 0;
              }),
              width: 260,
              suffixIcon: _pendingStudentSearch.isNotEmpty
                  ? Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: IconButton(
                        icon: AppIcon.linear('close-circle', size: 14),
                        onPressed: () => setState(() {
                          _pendingStudentSearchController.clear();
                          _pendingStudentSearch = '';
                          _pendingPage = 0;
                        }),
                        splashRadius: 12,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    )
                  : null,
            ),
            SizedBox(width: 8.w),
            // Fee Type dropdown
            SizedBox(
              height: 40,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _pendingFeeTypeFilter,
                    hint: Text('All Fee Types', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    icon: AppIcon.linear('Chevron Down', size: 18),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All Fee Types')),
                      ...feeTypes.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t))),
                    ],
                    onChanged: (v) => setState(() { _pendingFeeTypeFilter = v; _pendingPage = 0; }),
                  ),
                ),
              ),
            ),
            SizedBox(width: 8.w),
            // Class dropdown
            SizedBox(
              height: 40,
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 14.w),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10.r),
                  border: Border.all(color: AppColors.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _pendingClassFilter,
                    hint: Text('All Classes', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                    icon: AppIcon.linear('Chevron Down', size: 18),
                    isDense: true,
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('All Classes')),
                      ...classes.map((c) => DropdownMenuItem<String?>(value: c, child: Text(c))),
                    ],
                    onChanged: (v) => setState(() { _pendingClassFilter = v; _pendingPage = 0; }),
                  ),
                ),
              ),
            ),
          ],
        ),
        SizedBox(height: 12.h),
        // Summary row
        Row(
          children: [
            _buildSummaryCard('people', Colors.blue, '$totalStudents', 'Students'),
            SizedBox(width: 12.w),
            _buildSummaryCard('wallet-1', AppColors.accent, _formatCurrency(totalDemand), 'Total Demand'),
            SizedBox(width: 12.w),
            _buildSummaryCard('tick-circle', AppColors.success, _formatCurrency(totalPaid), 'Total Paid'),
            SizedBox(width: 12.w),
            _buildSummaryCard('clock', Colors.orange, _formatCurrency(totalBalance), 'Balance Due'),
          ],
        ),
        SizedBox(height: 12.h),
        // Student table
        LayoutBuilder(builder: (context, constraints) {
          return Scrollbar(controller: _studentListScrollCtrl, thumbVisibility: true, trackVisibility: true, child: SingleChildScrollView(controller: _studentListScrollCtrl, scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(dividerThickness: 0,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
              headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
              dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('ROLL NO')),
                DataColumn(label: Text('STUDENT NAME')),
                DataColumn(label: Text('COURSE')),
                DataColumn(label: Text('CLASS')),
                DataColumn(label: Text('FEE AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('FINE'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Text('STATUS')),
              ],
              rows: pagedKeys.isEmpty ? [
                const DataRow(cells: [
                  DataCell(Text('')), DataCell(Text('No students found')), DataCell(Text('')), DataCell(Text('')),
                  DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')), DataCell(Text('')),
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
                  final stuCourse = first['courname']?.toString() ?? '-';
                  double sDemand = 0, sPaid = 0, sFine = 0, sBalance = 0;
                  for (final d in demands) {
                    sDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
                    final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                    final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                    final isPaid = pa > 0 || d['paidstatus'] == 'P';
                    sPaid += pa - (isPaid ? fa : 0);
                    sFine += isPaid ? fa : 0;
                    sBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
                  }
                  final statusLabel = sBalance <= 0 ? 'Paid' : sPaid > 0 ? 'Partial' : 'Unpaid';
                  final statusColor = sBalance <= 0 ? AppColors.success : sPaid > 0 ? AppColors.warning : Colors.red;
                  return DataRow(
                    color: WidgetStateProperty.all(idx.isEven ? Colors.white : const Color(0xFFF7FAFC)),
                    onSelectChanged: (_) => setState(() {
                      _selectedStudentKey = stuKey;
                      _selectedStudentDemands = demands;
                    }),
                    cells: [
                      DataCell(Text('${startIdx + idx + 1}')),
                      DataCell(Text(admNo)),
                      DataCell(Text(stuName, style: const TextStyle(fontWeight: FontWeight.w500))),
                      DataCell(Text(stuCourse, style: const TextStyle(color: AppColors.primary))),
                      DataCell(Text(stuClass)),
                      DataCell(Text(_formatCurrency(sDemand))),
                      DataCell(Text(_formatCurrency(sPaid), style: const TextStyle(color: AppColors.success))),
                      DataCell(Text(sFine > 0 ? _formatCurrency(sFine) : '-', style: TextStyle(color: sFine > 0 ? Colors.orange : AppColors.textSecondary))),
                      DataCell(Text(_formatCurrency(sBalance), style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.orange))),
                      DataCell(Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: Text(statusLabel, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: statusColor)),
                      )),
                    ],
                  );
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(AppColors.tableHeadBg),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(Text(_formatCurrency(totalDemand), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalPaid), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalFine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrency(totalBalance), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          )));
        }),
        SizedBox(height: 8.h),
        // Pagination footer
        Row(
          children: [
            Text(
              'Showing ${totalStudents == 0 ? 0 : startIdx + 1}–$endIdx of $totalStudents students',
              style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
            ),
            const Spacer(),
            IconButton(
              icon: AppIcon.linear('Double Arrow Left', size: 20),
              onPressed: _pendingPage > 0 ? () => setState(() => _pendingPage = 0) : null,
              tooltip: 'First page', splashRadius: 18,
            ),
            IconButton(
              icon: AppIcon.linear('Chevron Left', size: 20),
              onPressed: _pendingPage > 0 ? () => setState(() => _pendingPage--) : null,
              tooltip: 'Previous page', splashRadius: 18,
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6.r)),
              child: Text('${_pendingPage + 1} / ${totalPages == 0 ? 1 : totalPages}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
            IconButton(
              icon: AppIcon.linear('Chevron Right', size: 20),
              onPressed: _pendingPage < totalPages - 1 ? () => setState(() => _pendingPage++) : null,
              tooltip: 'Next page', splashRadius: 18,
            ),
            IconButton(
              icon: AppIcon.linear('Double Arrow Right', size: 20),
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

  Future<void> _openDateMethodFilter() async {
    // Collect available payment methods from loaded payments
    final availableMethods = <String>{};
    for (final p in _payments) {
      final m = (p['paymode']?.toString() ?? '').toLowerCase().trim();
      if (m.isNotEmpty && m != '-') availableMethods.add(m);
    }
    final methodList = availableMethods.toList()..sort();

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        DateTime from = _fromDate;
        DateTime to = _toDate;
        final Set<String> methods = {..._filterMethods};
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          Widget presetChip(String label, VoidCallback onTap) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
              );

          Widget methodChip(String m) {
            final selected = methods.contains(m);
            return Padding(
              padding: const EdgeInsets.only(right: 8, bottom: 6),
              child: InkWell(
                onTap: () => setStateDialog(() {
                  if (selected) {
                    methods.remove(m);
                  } else {
                    methods.add(m);
                  }
                }),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: selected ? AppColors.accent.withValues(alpha: 0.14) : AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: selected ? AppColors.accent : AppColors.border),
                  ),
                  child: Text(
                    m.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                      color: selected ? AppColors.accent : AppColors.textPrimary,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ),
            );
          }

          Widget datePickerBox({required String hint, required DateTime value, required ValueChanged<DateTime> onChanged}) {
            return InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: value,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) onChanged(picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIcon.linear('calendar', size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text('${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  ],
                ),
              ),
            );
          }

          Widget sectionLabel(String text) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(text, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.3)),
              );

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            title: Row(
              children: [
                Text('Filters', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const AppIcon.linear('close-circle', size: 20, color: AppColors.textSecondary),
                  splashRadius: 18,
                  tooltip: 'Close',
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionLabel('QUICK RANGE'),
                  Row(children: [
                    presetChip('Today', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = DateTime(now.year, now.month, now.day); to = DateTime(now.year, now.month, now.day); });
                    }),
                    presetChip('7 Days', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = now.subtract(const Duration(days: 7)); to = DateTime(now.year, now.month, now.day); });
                    }),
                    presetChip('30 Days', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = now.subtract(const Duration(days: 30)); to = DateTime(now.year, now.month, now.day); });
                    }),
                    presetChip('This Month', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = DateTime(now.year, now.month, 1); to = DateTime(now.year, now.month, now.day); });
                    }),
                  ]),
                  const SizedBox(height: 16),
                  sectionLabel('CUSTOM RANGE'),
                  Row(children: [
                    Expanded(child: datePickerBox(hint: 'From', value: from, onChanged: (d) => setStateDialog(() => from = d))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('—')),
                    Expanded(child: datePickerBox(hint: 'To', value: to, onChanged: (d) => setStateDialog(() => to = d))),
                  ]),
                  if (methodList.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    sectionLabel('PAYMENT METHOD'),
                    Wrap(children: methodList.map(methodChip).toList()),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setStateDialog(() {
                  final now = DateTime.now();
                  from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
                  to = DateTime(now.year, now.month, now.day);
                  methods.clear();
                }),
                child: Text('Clear', style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() {
                    _fromDate = from;
                    _toDate = to;
                    _filterMethods
                      ..clear()
                      ..addAll(methods);
                  });
                  Navigator.pop(ctx);
                  _fetchData();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        });
      },
    );
  }

  Widget _buildDateList() {
    final double grandTotal = _dateGroups.fold(0.0, (s, g) => s + g.totalAmount);
    final double grandFine = _dateGroups.fold(0.0, (s, g) => s + g.totalFine);
    final int grandTransactions = _dateGroups.fold(0, (s, g) => s + g.payments.length);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                AppIcon.linear('document-text', size: 18, color: AppColors.accent),
                SizedBox(width: 8.w),
                Text('Date-wise Collection Summary', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                SizedBox(width: 8.w),
                Text('${_dateGroups.length} days', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                const Spacer(),
                SizedBox(
                  height: 40,
                  child: OutlinedButton.icon(
                    onPressed: _openDateMethodFilter,
                    icon: AppIcon.linear('calendar-1', size: 16, color: AppColors.textPrimary),
                    label: Text('Date & Method', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.border),
                      padding: EdgeInsets.symmetric(horizontal: 14.w),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                  ),
                ),
                SizedBox(width: 8.w),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _fetchData,
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
          ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_dateGroups.isEmpty)
            Padding(
              padding: EdgeInsets.all(48.w),
              child: Center(
                child: Column(
                  children: [
                    AppIcon.linear('search-favorite', size: 40.sp, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                    SizedBox(height: 8.h),
                    const Text('No collections found for selected date range', style: TextStyle(color: AppColors.textSecondary)),
                  ],
                ),
              ),
            )
          else
            Builder(builder: (context) {
              final totalItems = _dateGroups.length;
              final totalPages = (totalItems / _dateListPageSize).ceil();
              if (_dateListPage >= totalPages && totalPages > 0) _dateListPage = totalPages - 1;
              final startIdx = _dateListPage * _dateListPageSize;
              final endIdx = (startIdx + _dateListPageSize).clamp(0, totalItems);
              final pagedGroups = _dateGroups.sublist(startIdx, endIdx);

              return Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: LayoutBuilder(
              builder: (context, constraints) {
                _updateCanScrollDateList();
                return Column(
                  children: [
                    SingleChildScrollView(
                      controller: _dateListScrollCtrl,
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(dividerThickness: 0,
                          showCheckboxColumn: false,
                          headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
                          headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
                          dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                          columnSpacing: 20,
                          horizontalMargin: 16,
                          dataRowMinHeight: 40,
                          dataRowMaxHeight: 44,
                          headingRowHeight: 42,
                          columns: const [
                            DataColumn(label: Text('S No.')),
                            DataColumn(label: Text('DATE')),
                            DataColumn(label: Text('TRANSACTIONS'), numeric: true),
                            DataColumn(label: Text('COLLECTION'), numeric: true),
                            DataColumn(label: Text('FINE'), numeric: true),
                            DataColumn(label: Text('TOTAL'), numeric: true),
                            DataColumn(label: Expanded(child: Text('ACTION', textAlign: TextAlign.right))),
                          ],
                          rows: [
                            ...pagedGroups.asMap().entries.map((entry) {
                              final i = entry.key;
                              final group = entry.value;
                              return DataRow(
                                color: WidgetStateProperty.all(i.isEven ? Colors.white : AppColors.surface),
                                onSelectChanged: (_) {
                                  setState(() { _selectedDate = group.date; _dateDrilldownPage = 0; });
                                },
                                cells: [
                                  DataCell(Text('${startIdx + i + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                                  DataCell(Text(_formatDisplayDate(group.date), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  DataCell(Text('${group.payments.length}', textAlign: TextAlign.right, style: const TextStyle(color: AppColors.textSecondary))),
                                  DataCell(Text(_formatCurrency(group.totalAmount - group.totalFine), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  DataCell(Text(group.totalFine > 0 ? _formatCurrency(group.totalFine) : '-', style: TextStyle(fontWeight: FontWeight.w600, color: group.totalFine > 0 ? Colors.orange : AppColors.textSecondary))),
                                  DataCell(Text(_formatCurrency(group.totalAmount), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                                  DataCell(Align(
                                    alignment: Alignment.centerRight,
                                    child: AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
                                  )),
                                ],
                              );
                            }),
                            // Grand total row
                            DataRow(
                              color: WidgetStateProperty.all(AppColors.tableHeadBg),
                              cells: [
                                const DataCell(Text('')),
                                DataCell(Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                                DataCell(Text('$grandTransactions', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                                DataCell(Text(_formatCurrency(grandTotal - grandFine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                                DataCell(Text(_formatCurrency(grandFine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                                DataCell(Text(_formatCurrency(grandTotal), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                                const DataCell(Text('')),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (_canScrollDateList)
                      _buildDateScrollbar(_dateListScrollCtrl),
                  ],
                );
              },
            ),
              ),
            ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Text(
                      '${totalItems == 0 ? 0 : startIdx + 1}\u2013$endIdx of $totalItems',
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.chevron_left_rounded),
                      onPressed: _dateListPage > 0 ? () => setState(() => _dateListPage--) : null,
                      tooltip: 'Previous',
                    ),
                    Text(
                      'Page ${_dateListPage + 1} of ${totalPages == 0 ? 1 : totalPages}',
                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right_rounded),
                      onPressed: _dateListPage < totalPages - 1 ? () => setState(() => _dateListPage++) : null,
                      tooltip: 'Next',
                    ),
                  ],
                ),
              ),
              ]);
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
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                        SizedBox(width: 6.w),
                        Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Container(width: 1, height: 18, color: AppColors.border),
                SizedBox(width: 12.w),
                InkWell(
                  onTap: () => setState(() {
                    _selectedDate = null;
                    _selectedPayId = null;
                    _selectedPayment = null;
                    _feeDetails = null;
                    _dateDrilldownSearch = '';
                    _dateDrilldownMethodFilter = null;
                  }),
                  child: Text('Date-wise Collection', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ),
                SizedBox(width: 6.w),
                AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
                SizedBox(width: 6.w),
                Text(_formatDisplayDate(group.date), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                SizedBox(width: 8.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(
                    '${group.payments.length} payments',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent),
                  ),
                ),
                const Spacer(),
                AppSearchField(
                  hintText: 'Search...',
                  onChanged: (v) => setState(() { _dateDrilldownSearch = v; _dateDrilldownPage = 0; }),
                  width: 240,
                ),
                SizedBox(width: 8.w),
                SizedBox(
                  height: 40,
                  child: DropdownButtonHideUnderline(
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 14.w),
                      decoration: BoxDecoration(
                        border: Border.all(color: AppColors.border),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: DropdownButton<String?>(
                        value: _dateDrilldownMethodFilter,
                        hint: Text('All Methods', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                        // Only Cash vs Bank — matches the Method-wise
                        // Summary buckets above. Listing raw methods
                        // (qr_upi, razorpay, cheque…) was confusing for
                        // accountants who just want cash-hand totals.
                        items: const [
                          DropdownMenuItem<String?>(value: null, child: Text('All Methods')),
                          DropdownMenuItem<String?>(value: 'Cash', child: Text('Cash')),
                          DropdownMenuItem<String?>(value: 'Bank', child: Text('Bank')),
                        ],
                        onChanged: (v) => setState(() { _dateDrilldownMethodFilter = v; _dateDrilldownPage = 0; }),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
                LayoutBuilder(builder: (context, constraints) {
                  final searchLower = _dateDrilldownSearch.toLowerCase();
                  final allFiltered = group.payments.where((p) {
                    if (_dateDrilldownMethodFilter != null) {
                      final raw = (p['paymethod']?.toString() ?? '').toLowerCase();
                      final bucket = raw == 'cash' ? 'Cash' : 'Bank';
                      if (bucket != _dateDrilldownMethodFilter) return false;
                    }
                    if (searchLower.isNotEmpty) {
                      final s = p['students'] as Map<String, dynamic>?;
                      final name = (s?['stuname']?.toString() ?? '').toLowerCase();
                      final admNo = (s?['stuadmno']?.toString() ?? '').toLowerCase();
                      final payNo = (p['paynumber']?.toString() ?? '').toLowerCase();
                      if (!name.contains(searchLower) && !admNo.contains(searchLower) && !payNo.contains(searchLower)) return false;
                    }
                    return true;
                  }).toList();
                  final double grandTotal = allFiltered.fold(0.0, (s, p) => s + ((p['transtotalamount'] as num?)?.toDouble() ?? 0));
                  final double grandFine = allFiltered.fold(0.0, (s, p) => s + (_payFineMap[p['pay_id'] as int?] ?? 0.0));
                  final double grandCollection = grandTotal - grandFine;
                  final ddTotalItems = allFiltered.length;
                  final ddTotalPages = (ddTotalItems / _dateDrilldownPageSize).ceil();
                  if (_dateDrilldownPage >= ddTotalPages && ddTotalPages > 0) _dateDrilldownPage = ddTotalPages - 1;
                  final ddStart = _dateDrilldownPage * _dateDrilldownPageSize;
                  final ddEnd = (ddStart + _dateDrilldownPageSize).clamp(0, ddTotalItems);
                  final filtered = allFiltered.sublist(ddStart, ddEnd);
                  _updateCanScrollDateDrilldown();
                  return Column(children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: SizedBox(
                    width: constraints.maxWidth,
                    child: DataTable(dividerThickness: 0,
                        showCheckboxColumn: false,
                        headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
                        headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
                        dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        columnSpacing: 8, horizontalMargin: 10, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
                        columns: const [
                          DataColumn(label: Text('S No.')),
                          DataColumn(label: Text('PAY NO')),
                          DataColumn(label: Text('TIME')),
                          DataColumn(label: Text('ROLL NO')),
                          DataColumn(label: Text('STUDENT NAME')),
                          DataColumn(label: Text('COURSE')),
                          DataColumn(label: Text('CLASS')),
                          DataColumn(label: Text('METHOD')),
                          DataColumn(label: Text('COLLECTION'), numeric: true),
                          DataColumn(label: Text('FINE'), numeric: true),
                          DataColumn(label: Text('TOTAL'), numeric: true),
                          DataColumn(label: Text('ACTION'), numeric: true),
                        ],
                        rows: [
                          ...List.generate(filtered.length, (i) {
                            final p = filtered[i];
                            final student = p['students'] as Map<String, dynamic>?;
                            final timeStr = _formatTime(p['createdat'] ?? p['paydate']);
                            final totalAmt = (p['transtotalamount'] as num?)?.toDouble() ?? 0;
                            final fine = _payFineMap[p['pay_id'] as int?] ?? 0.0;
                            final collection = totalAmt - fine;
                            return DataRow(
                              color: WidgetStateProperty.all(i.isEven ? Colors.white : AppColors.surface),
                              onSelectChanged: (_) => _onPaymentTap(p),
                              cells: [
                                DataCell(Text('${ddStart + i + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(Text(p['paynumber']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                DataCell(Text(timeStr, style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(Text(student?['stuadmno']?.toString() ?? '-', style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(student?['stuname']?.toString() ?? '-', overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                                DataCell(Text(student?['courname']?.toString().isNotEmpty == true ? student!['courname'].toString() : (_stuIdToCourse[p['stu_id'] as int?] ?? '-'), style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(Text(student?['stuclass']?.toString() ?? '-', style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(Text(p['paymethod'] ?? '-', style: const TextStyle(color: AppColors.textSecondary))),
                                DataCell(Text(_formatCurrency(collection), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                DataCell(Text(fine > 0 ? _formatCurrency(fine) : '-', style: TextStyle(fontWeight: FontWeight.w600, color: fine > 0 ? Colors.orange : AppColors.textSecondary))),
                                DataCell(Text(_formatCurrency(totalAmt), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                                DataCell(Align(
                                  alignment: Alignment.centerRight,
                                  child: Container(
                                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                                    decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(8.r)),
                                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                                      Text('View', style: TextStyle(color: Colors.white, fontSize: 13.sp, fontWeight: FontWeight.w600)),
                                      SizedBox(width: 4.w),
                                      AppIcon.linear('Chevron Right', color: Colors.white, size: 12),
                                    ]),
                                  ),
                                )),
                              ],
                            );
                          }),
                          DataRow(color: WidgetStateProperty.all(AppColors.tableHeadBg), cells: [
                            const DataCell(Text('')),
                            DataCell(Text('GRAND TOTAL', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            const DataCell(Text('')),
                            DataCell(Text(_formatCurrency(grandCollection), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text(_formatCurrency(grandFine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text(_formatCurrency(grandTotal), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            const DataCell(Text('')),
                          ]),
                        ],
                      ),
                    ),
                      ),
                    ),
                  if (_canScrollDateDrilldown)
                    _buildDateScrollbar(_dateDrilldownScrollCtrl),
                  // Pagination controls
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                    child: Row(
                      children: [
                        Text('${ddStart + 1}–$ddEnd of $ddTotalItems', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.chevron_left_rounded),
                          onPressed: _dateDrilldownPage > 0 ? () => setState(() => _dateDrilldownPage--) : null,
                          tooltip: 'Previous',
                        ),
                        Text(
                          'Page ${_dateDrilldownPage + 1} of ${ddTotalPages == 0 ? 1 : ddTotalPages}',
                          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                        ),
                        IconButton(
                          icon: const Icon(Icons.chevron_right_rounded),
                          onPressed: _dateDrilldownPage < ddTotalPages - 1 ? () => setState(() => _dateDrilldownPage++) : null,
                          tooltip: 'Next',
                        ),
                      ],
                    ),
                  ),
                  ]);
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
    final stuAddress = student?['stuaddress']?.toString() ?? '-';
    // Payment in-charge mobile from parents.payinchargemob
    final stuMobile = payment['payinchargemob']?.toString().isNotEmpty == true
        ? payment['payinchargemob'].toString()
        : '-';
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

    // Build fee details grouped by term — fine is shown as a separate line item
    List<ReceiptTermDetail> termDetails = [];
    if (feeDetails != null && feeDetails.isNotEmpty) {
      const monthFeeTypes = ['TUITION FEES', 'TUITION FEE', 'VAN FEES', 'VAN FEE'];
      final termMap = <String, List<ReceiptFeeItem>>{};
      for (final d in feeDetails) {
        String term = d['demfeeterm']?.toString() ?? '-';
        final feeType = d['demfeetype']?.toString() ?? 'Fee';
        // Line amount = what was collected in THIS payment (fee portion only).
        // collectedamount comes from paymentdetails.transtotalamount and includes
        // fine; subtract fine to isolate the fee portion.
        final fine = (d['fineamount'] as num?)?.toDouble() ?? 0;
        final collected = (d['collectedamount'] as num?)?.toDouble()
            ?? (d['feeamount'] as num?)?.toDouble() ?? 0;
        final feeOnly = (collected - fine).clamp(0, double.infinity).toDouble();
        debugPrint('RECEIPT-BUILD: dem_id=${d['dem_id']} feeType=$feeType collectedamount=${d['collectedamount']} feeamount=${d['feeamount']} fineamount=$fine -> feeOnly=$feeOnly');
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
        termMap[term]!.add(ReceiptFeeItem(type: feeType, amount: feeOnly));
        if (fine > 0) {
          termMap[term]!.add(ReceiptFeeItem(type: '  Fine', amount: fine));
        }
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
      courseName: (student?['courname']?.toString().isNotEmpty == true)
          ? student!['courname'].toString()
          : (_stuIdToCourse[student?['stu_id'] as int?] ?? '-'),
      schoolName: _insName ?? auth.insName ?? 'Institution',
      schoolAddress: _insAddress ?? '-',
      schoolLogoUrl: _insLogoUrl,
      schoolMobile: _insMobile,
      schoolEmail: _insEmail,
      feeDetails: termDetails,
      paymentMethod: payMethod,
      paymentDate: dateStr,
      status: 'paid',
      reconStatus: payment['recon_status']?.toString() ?? 'P',
      total: totalAmount,
    );
  }

  Future<pw.Document> _buildReceiptPdf(ReceiptData data) async {
    final font = await PdfGoogleFonts.montserratRegular();
    final fontMedium = await PdfGoogleFonts.montserratMedium();
    final fontSemiBold = await PdfGoogleFonts.montserratSemiBold();
    final fontItalic = await PdfGoogleFonts.montserratItalic();
    final fontPtSerif = await PdfGoogleFonts.pTSerifRegular();

    const primaryBlue = PdfColor.fromInt(0xFF6C8EEF);
    const darkBlue = PdfColor.fromInt(0xFF4A6CD4);
    const textDark = PdfColor.fromInt(0xFF2a2a2a);
    const textMediumC = PdfColor.fromInt(0xFF4c4c4c);
    const headerBg = PdfColor.fromInt(0xFFE9EEFF);
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

    String formatAmount(double amount) {
      if (amount == amount.truncateToDouble()) {
        return amount.toInt().toString().replaceAllMapped(
          RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
      }
      return amount.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},');
    }

    // Split fee details into chunks that fit per page (max 8 per page)
    const int maxItemsPerPage = 8;
    final totalItems = data.feeDetails.length;
    final totalPages = (totalItems / maxItemsPerPage).ceil().clamp(1, 100);

    final pdf = pw.Document();

    for (int page = 0; page < totalPages; page++) {
      final startIdx = page * maxItemsPerPage;
      final endIdx = (startIdx + maxItemsPerPage).clamp(0, totalItems);
      final pageItems = data.feeDetails.sublist(startIdx, endIdx);
      final isFirstPage = page == 0;
      final isLastPage = page == totalPages - 1;

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(60),
          theme: pw.ThemeData.withFont(base: font, bold: fontSemiBold, italic: fontItalic),
          build: (pw.Context ctx) {
            return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                // Header (on every page)
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
                        if (totalPages > 1) ...[
                          pw.SizedBox(height: 6),
                          pw.Text('Page ${page + 1} of $totalPages', style: pw.TextStyle(font: fontMedium, fontSize: 9, color: textMediumC)),
                        ],
                      ],
                    ),
                  ],
                ),
                pw.SizedBox(height: 12),
                pw.Container(height: 1, color: dividerColor),
                pw.SizedBox(height: 12),
                // To section (only on first page)
                if (isFirstPage) ...[
                  pw.Text('To:', style: pw.TextStyle(font: fontSemiBold, fontSize: 13, color: textDark)),
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
                                pw.Expanded(child: pw.Text(
                                  (data.address.trim().isNotEmpty && data.address.trim() != '-' && data.address.trim().toLowerCase() != 'null') ? data.address : 'NA',
                                  style: sMedium,
                                )),
                              ],
                            ),
                          ],
                        ),
                      ),
                      pw.SizedBox(width: 20),
                      pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.end,
                        children: [
                          labelValue('Roll No:', data.admissionNo),
                          pw.SizedBox(height: 6),
                          labelValue('Class:', data.className),
                        ],
                      ),
                    ],
                  ),
                  pw.SizedBox(height: 20),
                ],
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
                                tableCell('Semester', sSemiBold.copyWith(color: primaryBlue)),
                                tableCell('Fee Type', sSemiBold.copyWith(color: primaryBlue)),
                                tableCell('Amount', sSemiBold.copyWith(color: primaryBlue)),
                              ],
                            ),
                            for (var i = 0; i < pageItems.length; i++)
                              pw.TableRow(
                                children: [
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    alignment: pw.Alignment.topCenter,
                                    child: pw.Text('${startIdx + i + 1}.', style: sMediumDark),
                                  ),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    alignment: pw.Alignment.topCenter,
                                    child: pw.Text(pageItems[i].term, style: sMediumDark),
                                  ),
                                  pw.Container(
                                    padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    child: pw.Column(
                                      children: [
                                        for (final fee in pageItems[i].fees)
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
                                        for (final fee in pageItems[i].fees)
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
                        // Sub Total row (only on last page)
                        if (isLastPage)
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
                    // PAID stamp overlay
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
                                borderRadius: pw.BorderRadius.circular(10.r),
                                border: pw.Border.all(color: paidGreen, width: 2.5),
                              ),
                              child: pw.Text('PAID', style: pw.TextStyle(font: fontSemiBold, fontSize: 20, color: paidGreen)),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                if (isLastPage) ...[
                  pw.SizedBox(height: 20),
                  // Payment info
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      labelValue('Receipt Method:', data.paymentMethod.toLowerCase() == 'razorpay' ? 'Online' : data.paymentMethod),
                      pw.SizedBox(height: 6),
                      labelValue('Status:', data.status == 'paid' ? 'Paid' : data.status == 'failed' ? 'Failed' : data.status),
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
                ] else ...[
                  pw.Spacer(),
                  pw.Center(
                    child: pw.Text('Continued on next page...', style: pw.TextStyle(font: fontItalic, fontSize: 10, color: textMediumC)),
                  ),
                ],
              ],
            );
          },
        ),
      );
    }
    return pdf;
  }

  void _showReceiptDialog(Map<String, dynamic> payment, List<Map<String, dynamic>>? feeDetails) async {
    // Enrich student address + fetch parent's payinchargemob for receipt
    final students = payment['students'] as Map<String, dynamic>?;
    final stuId = payment['stu_id'] as int?;
    if (stuId != null) {
      try {
        if (students == null || students['stuaddress'] == null) {
          final result = await SupabaseService.fromSchema('students')
              .select('stumobile, stuaddress, stuadmno')
              .eq('stu_id', stuId)
              .maybeSingle();
          if (result != null) {
            payment['students'] = {
              ...?students,
              'stumobile': result['stumobile'],
              'stuaddress': result['stuaddress'],
              'stuadmno': result['stuadmno'] ?? students?['stuadmno'],
            };
          }
        }
        // Fetch parent's payinchargemob — used as Mobile No on receipt
        final stuadmno = (payment['students'] as Map<String, dynamic>?)?['stuadmno']?.toString();
        final parent = await SupabaseService.getStudentParent(stuId, stuadmno: stuadmno);
        if (parent != null) {
          final payMob = parent['payinchargemob']?.toString();
          if (payMob != null && payMob.isNotEmpty) {
            payment['payinchargemob'] = payMob;
          }
        }
      } catch (e) {
        debugPrint('Failed to enrich receipt data: $e');
      }
    }
    if (!mounted) return;
    final receiptData = _buildReceiptData(payment, feeDetails);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
                        }
                      },
                      icon: AppIcon('document-download', size: 18),
                      label: const Text('Download'),
                    ),
                    SizedBox(width: 8.w),
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
                          if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error));
                        }
                      },
                      icon: AppIcon('printer', size: 18),
                      label: const Text('Print'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        elevation: 0,
                        textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: AppIcon.linear('close-circle', size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(12.w),
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    _selectedPayId = null;
                    _selectedPayment = null;
                    _feeDetails = null;
                  }),
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                        SizedBox(width: 6.w),
                        Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Container(width: 1, height: 18, color: AppColors.border),
                SizedBox(width: 12.w),
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
                        child: Text('Date-wise Collection', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      ),
                      Text('  >  ', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                      InkWell(
                        onTap: () => setState(() {
                          _selectedPayId = null;
                          _selectedPayment = null;
                          _feeDetails = null;
                        }),
                        child: Text(_selectedDate != null ? _formatDisplayDate(_selectedDate!) : '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      ),
                      Text('  >  ', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                      Text('$payNo - $stuName ($admNo)', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
              if (_loadingFeeDetails)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
              else if (_feeDetails == null || _feeDetails!.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No fee details found', style: TextStyle(color: AppColors.textSecondary))))
              else
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: LayoutBuilder(builder: (context, constraints) {
                  return Scrollbar(controller: _feeDetailScrollCtrl, thumbVisibility: true, trackVisibility: true, child: SingleChildScrollView(controller: _feeDetailScrollCtrl, scrollDirection: Axis.horizontal, child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: constraints.maxWidth),
                    child: DataTable(dividerThickness: 0,
                      showCheckboxColumn: false,
                      headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
                      headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
                      dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                      columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
                      columns: const [
                        DataColumn(label: Text('S No.')), DataColumn(label: Text('SEMESTER')), DataColumn(label: Text('FEE TYPE')),
                        DataColumn(label: Text('AMOUNT'), numeric: true), DataColumn(label: Text('PAID'), numeric: true),
                        DataColumn(label: Text('FINE'), numeric: true),
                        DataColumn(label: Text('BALANCE'), numeric: true), DataColumn(label: Text('STATUS')),
                      ],
                      rows: [
                        ...List.generate(_feeDetails!.length, (i) {
                          final fd = _feeDetails![i];
                          final pa = (fd['paidamount'] as num?)?.toDouble() ?? 0;
                          final fa = (fd['fineamount'] as num?)?.toDouble() ?? 0;
                          final paid = pa - ((pa > 0 || fd['paidstatus'] == 'P') ? fa : 0);
                          final balance = (fd['balancedue'] as num?)?.toDouble() ?? 0;
                          final statusLabel = balance <= 0 ? 'Paid' : paid > 0 ? 'Partial' : 'Due';
                          final statusColor = balance <= 0 ? AppColors.success : paid > 0 ? AppColors.warning : AppColors.warning;
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
                          final fineDisplay = (pa > 0 || fd['paidstatus'] == 'P') ? fa : 0.0;
                          return DataRow(color: WidgetStateProperty.all(i.isEven ? Colors.white : AppColors.surface), cells: [
                            DataCell(Text('${i + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                            DataCell(Text(term, style: const TextStyle(color: AppColors.textSecondary))),
                            DataCell(Text(fd['demfeetype']?.toString() ?? '-', style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                            DataCell(Text(_formatCurrency((fd['feeamount'] as num?)?.toDouble() ?? 0), style: const TextStyle(color: AppColors.textSecondary))),
                            DataCell(Text(_formatCurrency(paid), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                            DataCell(Text(fineDisplay > 0 ? _formatCurrency(fineDisplay) : '-', style: TextStyle(fontWeight: FontWeight.w600, color: fineDisplay > 0 ? Colors.orange : AppColors.textSecondary))),
                            DataCell(Text(_formatCurrency(balance), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                            DataCell(Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(statusLabel, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: statusColor)),
                            )),
                          ]);
                        }),
                        // Grand total row
                        DataRow(
                          color: WidgetStateProperty.all(AppColors.tableHeadBg),
                          cells: [
                            const DataCell(Text('')),
                            DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text('${_feeDetails!.length} items', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                            DataCell(Text(_formatCurrency(_feeDetails!.fold<double>(0, (s, d) => s + ((d['feeamount'] as num?)?.toDouble() ?? 0))), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text(_formatCurrency(_feeDetails!.fold<double>(0, (s, d) {
                              final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                              final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                              return s + pa - ((pa > 0 || d['paidstatus'] == 'P') ? fa : 0);
                            })), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text(_formatCurrency(_feeDetails!.fold<double>(0, (s, d) {
                              final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                              final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                              return s + ((pa > 0 || d['paidstatus'] == 'P') ? fa : 0);
                            })), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            DataCell(Text(_formatCurrency(_feeDetails!.fold<double>(0, (s, d) => s + ((d['balancedue'] as num?)?.toDouble() ?? 0))), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                            const DataCell(Text('')),
                          ],
                        ),
                      ],
                    ),
                  )));
                }))),
          Padding(
            padding: EdgeInsets.fromLTRB(0, 12.h, 20.w, 16.h),
            child: Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: () => _showReceiptDialog(p, _feeDetails),
                icon: AppIcon('document-download', size: 16),
                label: const Text('Download PDF'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  elevation: 0,
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportCollectionSummaryExcel(List<Map<String, dynamic>> payments) async {
    try {
      final auth = Provider.of<AuthProvider>(context, listen: false);
      final insId = auth.insId;
      if (insId == null) return;

      // Fetch sequence info
      Map<String, dynamic>? seqInfo;
      try {
        seqInfo = await SupabaseService.fromSchema('sequence')
            .select('seqprefix, sequid, seqstart, seqcurno, seqwidth')
            .eq('ins_id', insId)
            .maybeSingle();
      } catch (_) {}

      // Fetch paymentdetails for these payments to get fee type breakdown
      final payIds = payments.map((p) => p['pay_id'] as int?).where((id) => id != null).toSet().toList();
      final Map<int, List<Map<String, dynamic>>> payDetailMap = {};

      if (payIds.isNotEmpty) {
        for (int i = 0; i < payIds.length; i += 50) {
          final chunk = payIds.sublist(i, (i + 50).clamp(0, payIds.length));
          final details = await SupabaseService.fromSchema('paymentdetails')
              .select('pay_id, dem_id, transtotalamount')
              .inFilter('pay_id', chunk)
              .eq('activestatus', 1);
          for (final d in details) {
            final pid = d['pay_id'] as int;
            payDetailMap.putIfAbsent(pid, () => []).add(d);
          }
        }
      }

      // Fetch dem_id -> demfeetype mapping
      final allDemIds = <int>{};
      for (final details in payDetailMap.values) {
        for (final d in details) {
          final demId = d['dem_id'] as int?;
          if (demId != null) allDemIds.add(demId);
        }
      }
      final Map<int, String> demFeeTypeMap = {};
      if (allDemIds.isNotEmpty) {
        for (int i = 0; i < allDemIds.length; i += 50) {
          final chunk = allDemIds.toList().sublist(i, (i + 50).clamp(0, allDemIds.length));
          final auth = context.read<AuthProvider>();
          final demands = await SupabaseService.fromSchema('feedemand')
              .select('dem_id, demfeetype')
              .eq('ins_id', auth.insId!)
              .inFilter('dem_id', chunk);
          for (final d in demands) {
            demFeeTypeMap[d['dem_id'] as int] = d['demfeetype']?.toString() ?? '';
          }
        }
      }

      // Build fee type totals by payment method (cash vs bank)
      final Map<String, double> cashByFeeType = {};
      final Map<String, double> bankByFeeType = {};
      final Set<String> allFeeTypes = {};

      for (final p in payments) {
        final payId = p['pay_id'] as int?;
        final method = (p['paymethod']?.toString() ?? '').toLowerCase();
        final isCash = method.contains('cash');
        final details = payDetailMap[payId] ?? [];

        for (final d in details) {
          final demId = d['dem_id'] as int?;
          final amount = (d['transtotalamount'] as num?)?.toDouble() ?? 0;
          final feeType = demFeeTypeMap[demId] ?? 'Unknown';
          allFeeTypes.add(feeType);

          if (isCash) {
            cashByFeeType[feeType] = (cashByFeeType[feeType] ?? 0) + amount;
          } else {
            bankByFeeType[feeType] = (bankByFeeType[feeType] ?? 0) + amount;
          }
        }
      }

      final feeTypeList = allFeeTypes.toList()..sort();

      // Build Excel
      final workbook = xl.Excel.createExcel();
      final sheet = workbook['Fee Collection Summary'];
      workbook.delete('Sheet1');

      final headerStyle = xl.CellStyle(
        bold: true,
        fontSize: 13,
      );
      final boldStyle = xl.CellStyle(bold: true);
      final amountStyle = xl.CellStyle(
        horizontalAlign: xl.HorizontalAlign.Right,
      );
      final boldAmountStyle = xl.CellStyle(
        bold: true,
        horizontalAlign: xl.HorizontalAlign.Right,
      );
      final totalRowStyle = xl.CellStyle(
        bold: true,
        fontSize: 13,
      );

      int row = 0;

      // Institution header
      final insName = _insName ?? '';
      final insAddr = _insAddress ?? '';
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(insName.toUpperCase());
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = headerStyle;
      row++;
      if (insAddr.isNotEmpty) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(insAddr.toUpperCase());
        row++;
      }
      row++;

      // Title
      final fromDate = '${_fromDate.day.toString().padLeft(2, '0')}/${_fromDate.month.toString().padLeft(2, '0')}/${_fromDate.year}';
      final toDate = '${_toDate.day.toString().padLeft(2, '0')}/${_toDate.month.toString().padLeft(2, '0')}/${_toDate.year}';
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('FEE COLLECTION SUMMARY');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = xl.CellStyle(bold: true, fontSize: 13);
      row++;
      row++;

      // Collection period & sequence info
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('Collection Period:');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = boldStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue('$fromDate to $toDate');
      row++;
      if (seqInfo != null) {
        final prefix = seqInfo['seqprefix']?.toString() ?? '';
        final start = seqInfo['seqstart']?.toString() ?? '1';
        final curNo = seqInfo['seqcurno']?.toString() ?? '';
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('Receipt Prefix:');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = boldStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue(prefix);
        row++;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('Sequence Start Number $start');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = boldStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue('End Number : $curNo');
        row++;
      }
      row++;

      // Column headers
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('FEETYPE');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = boldStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue('CASH');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = boldStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.TextCellValue('BANK');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).cellStyle = boldStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.TextCellValue('TOTAL');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = boldStyle;
      row++;

      // Data rows
      double grandCash = 0, grandBank = 0, grandTotal = 0;
      for (final feeType in feeTypeList) {
        final cash = cashByFeeType[feeType] ?? 0;
        final bank = bankByFeeType[feeType] ?? 0;
        final total = cash + bank;
        grandCash += cash;
        grandBank += bank;
        grandTotal += total;

        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(feeType.toUpperCase());
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.IntCellValue(cash.toInt());
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = amountStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.IntCellValue(bank.toInt());
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).cellStyle = amountStyle;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.IntCellValue(total.toInt());
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = amountStyle;
        row++;
      }

      // Grand total
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('GRAND TOTAL');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = totalRowStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.IntCellValue(grandCash.toInt());
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = boldAmountStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.IntCellValue(grandBank.toInt());
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).cellStyle = boldAmountStyle;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.IntCellValue(grandTotal.toInt());
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).cellStyle = boldAmountStyle;

      // Set column widths
      sheet.setColumnWidth(0, 30);
      sheet.setColumnWidth(1, 15);
      sheet.setColumnWidth(2, 15);
      sheet.setColumnWidth(3, 15);

      // Save
      final bytes = workbook.encode();
      if (bytes == null) return;
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Fee Collection Summary',
        fileName: 'fee_collection_summary_${_fromDate.year}${_fromDate.month.toString().padLeft(2, '0')}${_fromDate.day.toString().padLeft(2, '0')}.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Fee Collection Summary exported'), backgroundColor: AppColors.success),
          );
        }
      }
    } catch (e) {
      debugPrint('Export collection summary error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _exportPendingToExcel(List<Map<String, dynamic>> demands, double appTotalDemand, double appTotalPaid, double appTotalBalance, int appTotalStudents) async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 1;

    // Fetch fresh data directly from feedemand table for accurate export
    // First page to estimate total, then fetch remaining pages in parallel
    // Single RPC call for all feedemand data with student names
    var allFresh = <Map<String, dynamic>>[];
    try {
      final rpcResult = await SupabaseService.client.rpc('get_pending_export_data', params: {'p_ins_id': insId});
      if (rpcResult != null) allFresh = List<Map<String, dynamic>>.from(rpcResult as List);
    } catch (e) {
      debugPrint('RPC get_pending_export_data failed, using fallback: $e');
      const pageSize = 1000;
      int offset = 0;
      while (true) {
        final batch = await SupabaseService.fromSchema('feedemand')
            .select('stu_id, stuadmno, stuclass, courname, demfeetype, demfeeterm, feeamount, conamount, balancedue, reconbalancedue, paidstatus')
            .eq('ins_id', insId).eq('activestatus', 1).range(offset, offset + pageSize - 1);
        allFresh.addAll(List<Map<String, dynamic>>.from(batch));
        if (batch.length < pageSize) break;
        offset += pageSize;
      }
    }
    demands = allFresh;

    // Enrich with student names from original demands
    final nameMap = <String, String>{};
    for (final d in _demands) {
      final admNo = d['stuadmno']?.toString() ?? '';
      final name = _getStudentName(d);
      if (admNo.isNotEmpty && name.isNotEmpty) nameMap[admNo] = name;
    }

    String insName = auth.insName ?? '';
    String insAddress = '';
    String insMobile = '';
    String insEmail = '';
    if (auth.insId != null) {
      final insInfo = await SupabaseService.getInstitutionInfo(auth.insId!);
      if (insInfo.name != null) insName = insInfo.name!;
      if (insInfo.address != null) insAddress = insInfo.address!;
      if (insInfo.mobile != null) insMobile = insInfo.mobile!;
      if (insInfo.email != null) insEmail = insInfo.email!;
    }

    // Fetch student remarks
    final remarksMap = auth.insId != null
        ? await SupabaseService.getStudentRemarks(auth.insId!)
        : <int, String>{};

    final excel = xl.Excel.createExcel();
    const sheetName = 'Pending Fees';
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    // Build dynamic term columns from actual demfeeterm values in the data
    final termSet = <String>{};
    for (final d in allFresh) {
      final t = d['demfeeterm']?.toString() ?? '';
      if (t.isNotEmpty) termSet.add(t);
    }
    const _pendingTermOrder = [
      'I SEMESTER', 'I TERM', 'II SEMESTER', 'II TERM', 'III SEMESTER', 'III TERM',
      'IV SEMESTER', 'V SEMESTER', 'VI SEMESTER',
      'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER',
      'NOVEMBER', 'DECEMBER', 'JANUARY', 'FEBRUARY',
      'MARCH', 'APRIL', 'MAY',
    ];
    final termCols = termSet.toList()..sort((a, b) {
      final ia = _pendingTermOrder.indexWhere((x) => x.toLowerCase() == a.toLowerCase());
      final ib = _pendingTermOrder.indexWhere((x) => x.toLowerCase() == b.toLowerCase());
      return (ia >= 0 ? ia : 999).compareTo(ib >= 0 ? ib : 999);
    });

    // Use actual demfeeterm value directly (no mapping needed)
    String mapTermToCol(String? term) {
      if (term == null || term.isEmpty) return '';
      return term.toUpperCase().trim();
    }

    // Styles
    final insStyle = xl.CellStyle(bold: true, fontSize: 14, horizontalAlign: xl.HorizontalAlign.Center);
    final insDetailStyle = xl.CellStyle(fontSize: 10, horizontalAlign: xl.HorizontalAlign.Center);
    final labelStyle = xl.CellStyle(bold: true, fontSize: 13);
    final colHeaderStyle = xl.CellStyle(
      bold: true, fontSize: 10,
      backgroundColorHex: xl.ExcelColor.fromHexString('#2D3748'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    );
    final totalStyle = xl.CellStyle(bold: true, fontSize: 13, backgroundColorHex: xl.ExcelColor.fromHexString('#E2E8F0'));
    final grandTotalStyle = xl.CellStyle(
      bold: true, fontSize: 13,
      backgroundColorHex: xl.ExcelColor.fromHexString('#2D3748'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    );

    final headers = ['Sno', 'Class', 'Roll No', 'Student Name', ...termCols, 'Total', 'Remarks'];
    final totalCols = headers.length;
    int row = 0;

    // Institution name
    final insNameCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    insNameCell.value = xl.TextCellValue(insName.toUpperCase());
    insNameCell.cellStyle = insStyle;
    sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
    row++;

    if (insAddress.isNotEmpty) {
      final addrCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      addrCell.value = xl.TextCellValue(insAddress);
      addrCell.cellStyle = insDetailStyle;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
    }

    final contactParts = <String>[];
    if (insMobile.isNotEmpty) contactParts.add('Ph: $insMobile');
    if (insEmail.isNotEmpty) contactParts.add('Email: $insEmail');
    if (contactParts.isNotEmpty) {
      final c = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      c.value = xl.TextCellValue(contactParts.join('  |  '));
      c.cellStyle = insDetailStyle;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
    }

    // PENDING FEE REPORT date
    final now = DateTime.now();
    final reportDate = '${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';
    final reportCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    reportCell.value = xl.TextCellValue('PENDING FEE REPORT AS ON $reportDate');
    reportCell.cellStyle = labelStyle;
    sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
    row++;

    // FEE TYPE filter label
    final feeTypeLabel = _pendingFeeTypeFilter ?? 'ALL FEE TYPE';
    final ftCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    ftCell.value = xl.TextCellValue('FEE TYPE : $feeTypeLabel');
    ftCell.cellStyle = labelStyle;
    sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
    row++;
    row++; // blank

    // Column headers
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = xl.TextCellValue(headers[c]);
      cell.cellStyle = colHeaderStyle;
    }
    row++;

    // DEBUG: Check what data we have
    debugPrint('EXPORT DEBUG: Total demands received: ${demands.length}');
    int hasTermCount = 0;
    int noTermCount = 0;
    int unpaidCount = 0;
    final termValues = <String>{};
    for (final d in demands) {
      final term = d['demfeeterm']?.toString() ?? '';
      final ps = d['paidstatus']?.toString() ?? '';
      if (term.isNotEmpty) {
        hasTermCount++;
        termValues.add(term);
      } else {
        noTermCount++;
      }
      if (ps == 'U') unpaidCount++;
    }
    debugPrint('EXPORT DEBUG: Has demfeeterm: $hasTermCount, Missing demfeeterm: $noTermCount');
    debugPrint('EXPORT DEBUG: Unpaid (paidstatus=U): $unpaidCount');
    debugPrint('EXPORT DEBUG: Unique demfeeterm values: $termValues');
    // Print first 5 rows for inspection
    for (var i = 0; i < demands.length && i < 5; i++) {
      final d = demands[i];
      debugPrint('EXPORT DEBUG ROW $i: paidstatus=${d['paidstatus']}, demfeeterm=${d['demfeeterm']}, balancedue=${d['balancedue']}, stuadmno=${d['stuadmno']}, stuclass=${d['stuclass']}');
    }

    // Group demands by student (stu_id)
    final Map<String, List<Map<String, dynamic>>> byStudent = {};
    for (final d in demands) {
      final stuId = d['stu_id']?.toString() ?? '';
      if (stuId.isNotEmpty) {
        byStudent.putIfAbsent(stuId, () => []).add(d);
      }
    }

    // Build student rows with term amounts
    final studentRows = <Map<String, dynamic>>[];
    for (final entry in byStudent.entries) {
      final stuDemands = entry.value;
      final first = stuDemands.first;
      final stuClass = first['stuclass']?.toString() ?? '-';
      final courName = first['courname']?.toString() ?? '';
      final admNo = first['stuadmno']?.toString() ?? '-';
      final stuName = nameMap[admNo] ?? _getStudentName(first);
      final stuId = first['stu_id'] as int?;
      final remarks = stuId != null ? (remarksMap[stuId] ?? '') : '';

      final Map<String, double> termAmounts = {};
      double total = 0;
      for (final d in stuDemands) {
        final term = d['demfeeterm']?.toString()?.toUpperCase().trim() ?? '';
        // Use reconbalancedue (reconciled balance) for pending report
        final bal = (d['reconbalancedue'] as num?)?.toDouble() ?? (d['balancedue'] as num?)?.toDouble() ?? 0;
        if (term.isNotEmpty && bal > 0) {
          termAmounts[term] = (termAmounts[term] ?? 0) + bal;
        }
        total += bal;
      }

      studentRows.add({
        'class': stuClass,
        'courname': courName,
        'groupKey': courName.isNotEmpty ? '$courName - $stuClass' : stuClass,
        'admNo': admNo,
        'stuName': stuName,
        'termAmounts': termAmounts,
        'total': total,
        'remarks': remarks,
      });
    }

    // Sort by course, then class (I Year, II Year, III Year), then admNo
    studentRows.sort((a, b) {
      final courseCmp = (a['courname'] as String).compareTo(b['courname'] as String);
      if (courseCmp != 0) return courseCmp;
      final classCmp = _compareClass(a['class'] as String, b['class'] as String);
      if (classCmp != 0) return classCmp;
      return (a['admNo'] as String).compareTo(b['admNo'] as String);
    });

    // Write rows grouped by course+class
    int sno = 0;
    String? currentClass;
    final Map<String, double> grandTermTotals = {};

    final groupHeaderStyle = xl.CellStyle(
      bold: true, fontSize: 12,
      backgroundColorHex: xl.ExcelColor.fromHexString('#E8EAF6'),
      fontColorHex: xl.ExcelColor.fromHexString('#1A237E'),
    );

    for (var i = 0; i < studentRows.length; i++) {
      final sr = studentRows[i];
      final stuClass = sr['class'] as String;
      final groupKey = sr['groupKey'] as String;
      final termAmounts = sr['termAmounts'] as Map<String, double>;
      final total = sr['total'] as double;

      if (currentClass != null && groupKey != currentClass) {
        _writePendingClassTotal(sheet, row, 'Total', termCols, studentRows, currentClass, totalStyle);
        row++;
      }

      // Add course+class group header when group changes
      if (groupKey != currentClass) {
        final headerCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        headerCell.value = xl.TextCellValue(groupKey);
        headerCell.cellStyle = groupHeaderStyle;
        sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), xl.CellIndex.indexByColumnRow(columnIndex: 4 + termCols.length + 1, rowIndex: row));
        row++;
        sno = 0;
      }

      currentClass = groupKey;

      sno++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.IntCellValue(sno);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue(stuClass);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.TextCellValue(sr['admNo'] as String);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.TextCellValue(sr['stuName'] as String);

      for (var t = 0; t < termCols.length; t++) {
        final amt = termAmounts[termCols[t]] ?? 0;
        if (amt > 0) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + t, rowIndex: row)).value = xl.IntCellValue(amt.toInt());
        }
      }

      final totalColIdx = 4 + termCols.length;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totalColIdx, rowIndex: row)).value = xl.IntCellValue(total.toInt());

      final remarksStr = sr['remarks'] as String;
      if (remarksStr.isNotEmpty) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: totalColIdx + 1, rowIndex: row)).value = xl.TextCellValue(remarksStr);
      }

      for (final tc in termCols) {
        grandTermTotals[tc] = (grandTermTotals[tc] ?? 0) + (termAmounts[tc] ?? 0);
      }
      row++;
    }

    // Last class total
    if (currentClass != null) {
      _writePendingClassTotal(sheet, row, 'Total', termCols, studentRows, currentClass, totalStyle);
      row++;
    }

    // G.Total (grand total)
    final gtLabelCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
    gtLabelCell.value = xl.TextCellValue('G.Total');
    gtLabelCell.cellStyle = grandTotalStyle;
    for (var c = 0; c < 4; c++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = grandTotalStyle;
    }
    for (var t = 0; t < termCols.length; t++) {
      final amt = grandTermTotals[termCols[t]] ?? 0;
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + t, rowIndex: row));
      if (amt > 0) cell.value = xl.IntCellValue(amt.toInt());
      cell.cellStyle = grandTotalStyle;
    }
    final gtTotalCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + termCols.length, rowIndex: row));
    gtTotalCell.value = xl.IntCellValue(appTotalBalance.toInt());
    gtTotalCell.cellStyle = grandTotalStyle;
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + termCols.length + 1, rowIndex: row)).cellStyle = grandTotalStyle;

    // Column widths
    sheet.setColumnWidth(0, 6);
    sheet.setColumnWidth(1, 8);
    sheet.setColumnWidth(2, 12);
    sheet.setColumnWidth(3, 22);
    for (var t = 0; t < termCols.length; t++) {
      sheet.setColumnWidth(4 + t, 14);
    }
    sheet.setColumnWidth(4 + termCols.length, 14);
    sheet.setColumnWidth(4 + termCols.length + 1, 25);

    // Save
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Pending Fee Report',
      fileName: 'Pending_Fee_Report_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      final path = result.endsWith('.xlsx') ? result : '$result.xlsx';
      final bytes = excel.encode();
      if (bytes != null) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported to $path'), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  void _writePendingClassTotal(
    xl.Sheet sheet, int row, String label,
    List<String> termCols, List<Map<String, dynamic>> studentRows,
    String className, xl.CellStyle style,
  ) {
    final classStudents = studentRows.where((r) => r['groupKey'] == className).toList();
    final Map<String, double> classTotals = {};
    double classTotal = 0;
    for (final sr in classStudents) {
      final ta = sr['termAmounts'] as Map<String, double>;
      for (final tc in termCols) {
        classTotals[tc] = (classTotals[tc] ?? 0) + (ta[tc] ?? 0);
      }
      classTotal += sr['total'] as double;
    }

    final labelCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row));
    labelCell.value = xl.TextCellValue(label);
    labelCell.cellStyle = style;
    for (var c = 0; c < 4; c++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = style;
    }
    for (var t = 0; t < termCols.length; t++) {
      final amt = classTotals[termCols[t]] ?? 0;
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + t, rowIndex: row));
      if (amt > 0) cell.value = xl.IntCellValue(amt.toInt());
      cell.cellStyle = style;
    }
    final tCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + termCols.length, rowIndex: row));
    tCell.value = xl.IntCellValue(classTotal.toInt());
    tCell.cellStyle = style;
    sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + termCols.length + 1, rowIndex: row)).cellStyle = style;
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

  final ScrollController _classTableScrollController = ScrollController();
  final ScrollController _studentTableScrollController = ScrollController();
  final ScrollController _drilldownFeeScrollCtrl = ScrollController();
  bool _canScrollClass = false;
  bool _canScrollStudent = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchData();
    _classTableScrollController.addListener(_onClassScrollChanged);
    _studentTableScrollController.addListener(_onStudentScrollChanged);
  }

  void _onClassScrollChanged() {
    if (mounted) setState(() {});
  }

  void _onStudentScrollChanged() {
    if (mounted) setState(() {});
  }

  void _updateCanScrollClass() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_classTableScrollController.hasClients &&
          _classTableScrollController.positions.isNotEmpty &&
          _classTableScrollController.position.hasContentDimensions) {
        final canScroll = _classTableScrollController.position.maxScrollExtent > 5;
        if (_canScrollClass != canScroll) {
          setState(() => _canScrollClass = canScroll);
        }
      } else {
        if (_canScrollClass) setState(() => _canScrollClass = false);
      }
    });
  }

  void _updateCanScrollStudent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_studentTableScrollController.hasClients &&
          _studentTableScrollController.positions.isNotEmpty &&
          _studentTableScrollController.position.hasContentDimensions) {
        final canScroll = _studentTableScrollController.position.maxScrollExtent > 5;
        if (_canScrollStudent != canScroll) {
          setState(() => _canScrollStudent = canScroll);
        }
      } else {
        if (_canScrollStudent) setState(() => _canScrollStudent = false);
      }
    });
  }

  @override
  void dispose() {
    _classTableScrollController.removeListener(_onClassScrollChanged);
    _studentTableScrollController.removeListener(_onStudentScrollChanged);
    _classTableScrollController.dispose();
    _studentTableScrollController.dispose();
    _drilldownFeeScrollCtrl.dispose();
    super.dispose();
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
      final rawPaid = (r['total_paid'] as num?)?.toDouble() ?? 0;
      final rawFine = (r['total_fine'] as num?)?.toDouble() ?? 0;
      return _ClassGroup(
        className: r['stuclass']?.toString() ?? '',
        courseName: r['courname']?.toString(),
        demands: const [],
        totalDemand: (r['total_demand'] as num?)?.toDouble() ?? 0,
        totalConcession: (r['total_concession'] as num?)?.toDouble() ?? 0,
        // RPC already subtracts fine from total_paid (fee-only collection)
        totalPaid: rawPaid,
        totalFine: rawFine,
        totalPending: (r['total_pending'] as num?)?.toDouble() ?? 0,
        studentCount: (r['student_count'] as num?)?.toInt() ?? 0,
        feeTypes: feeTypes,
      );
    }).toList();
    // Order by course alphabetically, then by class.
    groups.sort((a, b) {
      final courseCmp = (a.courseName ?? '').compareTo(b.courseName ?? '');
      if (courseCmp != 0) return courseCmp;
      return _compareClass(a.className, b.className);
    });
    return groups;
  }

  // Summary totals
  double get _totalDemand => _classGroups.fold(0.0, (s, g) => s + g.totalDemand);
  double get _totalPaid => _classGroups.fold(0.0, (s, g) => s + g.totalPaid);
  double get _totalFine => _classGroups.fold(0.0, (s, g) => s + g.totalFine);
  double get _totalCollected => _totalPaid + _totalFine;
  double get _totalPending => _classGroups.fold(0.0, (s, g) => s + g.totalPending);
  int get _totalStudents => _classGroups.fold(0, (s, g) => s + g.studentCount);

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Signal drilldown state so the parent tabs row hides.
    final isDrilldown = _selectedClass != null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_feeCollectionDrilldownActive.value != isDrilldown) {
        _feeCollectionDrilldownActive.value = isDrilldown;
      }
    });

    // If a class is selected, show student drilldown
    if (_selectedClass != null) {
      final group = _classGroups.firstWhere((g) => g.className == _selectedClass, orElse: () => _classGroups.first);
      return _buildStudentDrilldown(group, _drilldownDemands, _drilldownLoading);
    }

    return Column(
      children: [
        // Summary cards (fixed, no scroll needed)
        Row(
          children: [
            _buildSummaryCard('people', Colors.blue, _totalStudents.toString(), 'Total Students'),
            SizedBox(width: 12.w),
            _buildSummaryCard('wallet-1', AppColors.accent, _formatCurrency(_totalDemand), 'Total Demand'),
            SizedBox(width: 12.w),
            _buildSummaryCard('tick-circle', AppColors.success, _formatCurrency(_totalCollected), 'Total Collected (Fee + Fine)'),
            SizedBox(width: 12.w),
            _buildSummaryCard('clock', AppColors.warning, _formatCurrency(_totalPending), 'Total Pending'),
          ],
        ),
        SizedBox(height: 16.h),
        // Class-wise table card — Expanded so height is bounded
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                  // Card header: title left, search+filter right
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    child: Row(
                      children: [
                        AppIcon('book-1', size: 18, color: AppColors.accent),
                        SizedBox(width: 8.w),
                        Text('Class-Wise Fee Details', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        // Search field
                        AppSearchField(
                          hintText: 'Search class...',
                          onChanged: (v) => setState(() => _classSearchQuery = v.trim().toLowerCase()),
                          width: 240,
                        ),
                        SizedBox(width: 8.w),
                        // Fee type filter dropdown
                        SizedBox(
                          height: 40,
                          child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10.r),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _classFilterFeeType,
                              isDense: true,
                              hint: Text('All Fee Types', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                              icon: AppIcon.linear('Chevron Down', size: 18),
                              items: [
                                DropdownMenuItem<String>(value: null, child: Text('All Fee Types', style: TextStyle(fontSize: 13.sp))),
                                ...() {
                                  final allFeeTypes = <String>{};
                                  for (final g in _classGroups) {
                                    allFeeTypes.addAll(g.feeTypes);
                                  }
                                  final sorted = allFeeTypes.toList()..sort();
                                  return sorted.map((ft) => DropdownMenuItem<String>(value: ft, child: Text(ft, style: TextStyle(fontSize: 13.sp))));
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
                  // Table content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child:
            _isLoading
              ? const Center(child: CircularProgressIndicator())
              : Builder(builder: (context) {
                final filteredGroups = _classGroups.where((g) {
                  if (_classSearchQuery.isNotEmpty && !g.className.toLowerCase().contains(_classSearchQuery)) return false;
                  if (_classFilterFeeType != null && !g.feeTypes.contains(_classFilterFeeType)) return false;
                  return true;
                }).toList();
                return LayoutBuilder(builder: (context, constraints) {
                  final viewportW = constraints.maxWidth;
                  const contentW = 1000.0;
                  final effectiveW = contentW > viewportW ? contentW : viewportW;
                  const scrollbarH = 18.0;

                  // Column widths for class list table
                  const double cHMargin = 16;
                  const double cColSpacing = 20;
                  const double cSnoW = 50;
                  const double cCourseW = 90;
                  const double cClassW = 70;
                  const double cStudentsW = 70;
                  const double cFeeTypesW = 260;
                  const double cTotalDemandW = 110;
                  const double cPaidW = 100;
                  const double cFineW = 80;
                  const double cCollectedW = 90;
                  const double cPendingW = 110;
                  const double cActionW = 130;
                  final List<double> cColWidths = [cSnoW, cCourseW, cClassW, cStudentsW, cFeeTypesW, cTotalDemandW, cPaidW, cFineW, cCollectedW, cPendingW, cActionW];
                  final cTotalFixedWidth = cColWidths.reduce((a, b) => a + b) + (cColWidths.length - 1) * cColSpacing + 2 * cHMargin;
                  final cTableWidth = cTotalFixedWidth > effectiveW ? cTotalFixedWidth : effectiveW;
                  final cExtraSpace = cTableWidth - cTotalFixedWidth;
                  final cSum = cColWidths.reduce((a, b) => a + b);
                  final List<double> cAdj = cColWidths.map((w) => w + (cExtraSpace * w / cSum)).toList();

                  Widget cBuildCell(String text, int colIndex, {FontWeight? fontWeight, double? fontSize, Color? color, Widget? child}) {
                    return SizedBox(
                      width: cAdj[colIndex],
                      child: child ?? Align(
                        alignment: colIndex >= 5 && colIndex <= 10 ? Alignment.centerRight : Alignment.centerLeft,
                        child: Text(text, style: TextStyle(fontSize: fontSize ?? 13.sp, fontWeight: fontWeight, color: color)),
                      ),
                    );
                  }

                  Widget cBuildRow(List<Widget> cells, {Color? bgColor, double height = 44}) {
                    return Container(
                      height: height,
                      color: bgColor,
                      padding: EdgeInsets.symmetric(horizontal: cHMargin),
                      child: Row(
                        children: [
                          for (int ci = 0; ci < cells.length; ci++) ...[
                            if (ci > 0) const SizedBox(width: cColSpacing),
                            cells[ci],
                          ],
                        ],
                      ),
                    );
                  }

                  // --- HEADER ---
                  final classHeaderRow = cBuildRow(
                    [
                      cBuildCell('S No.', 0, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('COURSE', 1, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('CLASS', 2, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('STUDENTS', 3, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('FEE TYPES', 4, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('TOTAL DEMAND', 5, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('PAID', 6, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('FINE', 7, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('% COLLECTED', 8, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('PENDING', 9, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                      cBuildCell('ACTION', 10, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    ],
                    bgColor: AppColors.tableHeadBg,
                    height: 42,
                  );

                  // --- BODY ROWS ---
                  final classBodyChildren = <Widget>[];
                  if (filteredGroups.isEmpty) {
                    classBodyChildren.add(cBuildRow(
                      [
                        cBuildCell('', 0),
                        cBuildCell('No fee demands found', 1),
                        for (int ci = 2; ci < 11; ci++) cBuildCell('', ci),
                      ],
                      height: 44,
                    ));
                  } else {
                    for (int i = 0; i < filteredGroups.length; i++) {
                      final g = filteredGroups[i];
                      final pct = g.totalDemand > 0 ? (g.totalPaid / g.totalDemand * 100) : 0.0;
                      onClassTap() async {
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
                          // Filter by course
                          final filtered = g.courseName != null
                              ? demands.where((d) => (d['courname']?.toString() ?? '') == g.courseName).toList()
                              : demands;
                          for (final d in filtered) {
                            d['_stuname'] = d['stuname']?.toString() ?? '';
                          }
                          if (mounted) {
                            setState(() {
                              _drilldownDemands = filtered;
                              _drilldownLoading = false;
                            });
                          }
                        }
                      }
                      classBodyChildren.add(InkWell(
                        onTap: () => onClassTap(),
                        child: Container(
                          color: i.isEven ? Colors.white : AppColors.surface,
                          padding: EdgeInsets.symmetric(horizontal: cHMargin),
                          constraints: BoxConstraints(minHeight: 50),
                          child: Row(
                            children: [
                              SizedBox(width: cAdj[0], child: Text('${i + 1}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[1], child: Text(g.courseName ?? '-', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.primary))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[2], child: Text(g.className, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[3], child: Text('${g.studentCount}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(
                                width: cAdj[4],
                                child: Wrap(
                                  spacing: 4, runSpacing: 4,
                                  children: [
                                    ...g.feeTypes.map((ft) => Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(color: AppColors.accent.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(6.r)),
                                      child: Text(ft, style: TextStyle(fontSize: 11.sp, color: AppColors.accent, fontWeight: FontWeight.w700)),
                                    )),
                                  ],
                                ),
                              ),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[5], child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(g.totalDemand), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[6], child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(g.totalPaid), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[7], child: Align(alignment: Alignment.centerRight, child: Text(g.totalFine > 0 ? _formatCurrency(g.totalFine) : '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: g.totalFine > 0 ? Colors.orange : AppColors.textSecondary)))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[8], child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                decoration: BoxDecoration(
                                  color: pct >= 100 ? AppColors.success.withValues(alpha: 0.1) : pct >= 50 ? Colors.orange.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Text('${pct.toStringAsFixed(0)}%', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: pct >= 100 ? AppColors.success : pct >= 50 ? Colors.orange : AppColors.warning)),
                              )),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[9], child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(g.totalPending), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                              const SizedBox(width: cColSpacing),
                              SizedBox(width: cAdj[10], child: Align(
                                alignment: Alignment.centerRight,
                                child: AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
                              )),
                            ],
                          ),
                        ),
                      ));
                      classBodyChildren.add(const Divider(height: 1, thickness: 0.5, color: Color(0xFFE8E8E8)));
                    }
                  }

                  // --- FOOTER (GRAND TOTAL) ---
                  final classFooterRow = cBuildRow(
                    [
                      cBuildCell('', 0, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell('Total', 1, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell('$_totalStudents', 2, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell('${_classGroups.length} classes', 3, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell('', 4),
                      cBuildCell(_formatCurrency(_totalDemand), 5, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell(_formatCurrency(_totalPaid), 6, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell(_formatCurrency(_totalFine), 7, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell(_totalDemand > 0 ? '${(_totalPaid / _totalDemand * 100).toStringAsFixed(0)}%' : '0%', 8, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell(_formatCurrency(_totalPending), 9, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                      cBuildCell('', 10),
                    ],
                    bgColor: AppColors.tableHeadBg,
                    height: 42,
                  );

                  _updateCanScrollClass();
                  return Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _classTableScrollController,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: cTableWidth,
                            height: constraints.maxHeight,
                            child: Column(
                              children: [
                                // Fixed header
                                classHeaderRow,
                                // Scrollable body
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.vertical,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: classBodyChildren,
                                    ),
                                  ),
                                ),
                                // Fixed footer
                                classFooterRow,
                              ],
                            ),
                          ),
                        ),
                      ),
                      // Classic horizontal scrollbar with arrow buttons
                      if (_canScrollClass)
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
                                  _classTableScrollController.animateTo(
                                    (_classTableScrollController.offset - 100).clamp(0.0, _classTableScrollController.position.maxScrollExtent),
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
                                  child: AppIcon.linear('Chevron Left', size: 16, color: const Color(0xFF333333)),
                                ),
                              ),
                              // Scrollbar track + thumb
                              Expanded(
                                child: LayoutBuilder(
                                  builder: (context, scrollbarConstraints) {
                                    final maxExtent = _classTableScrollController.hasClients &&
                                            _classTableScrollController.positions.isNotEmpty &&
                                            _classTableScrollController.position.hasContentDimensions
                                        ? _classTableScrollController.position.maxScrollExtent
                                        : 1.0;
                                    final viewportWidth = _classTableScrollController.hasClients &&
                                            _classTableScrollController.positions.isNotEmpty &&
                                            _classTableScrollController.position.hasContentDimensions
                                        ? _classTableScrollController.position.viewportDimension
                                        : scrollbarConstraints.maxWidth;
                                    final totalContentWidth = maxExtent + viewportWidth;
                                    final thumbRatio = (viewportWidth / totalContentWidth).clamp(0.1, 1.0);
                                    final thumbWidth = (scrollbarConstraints.maxWidth * thumbRatio).clamp(30.0, scrollbarConstraints.maxWidth);
                                    final trackSpace = scrollbarConstraints.maxWidth - thumbWidth;
                                    final scrollRatio = maxExtent > 0 ? (_classTableScrollController.offset / maxExtent).clamp(0.0, 1.0) : 0.0;
                                    final thumbOffset = trackSpace * scrollRatio;

                                    return GestureDetector(
                                      onHorizontalDragUpdate: (details) {
                                        if (trackSpace > 0) {
                                          final newRatio = ((thumbOffset + details.delta.dx) / trackSpace).clamp(0.0, 1.0);
                                          _classTableScrollController.jumpTo(newRatio * maxExtent);
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
                                  _classTableScrollController.animateTo(
                                    (_classTableScrollController.offset + 100).clamp(0.0, _classTableScrollController.position.maxScrollExtent),
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
                                  child: AppIcon.linear('Chevron Right', size: 16, color: const Color(0xFF333333)),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  );
                });
              })))),
                ],
              ),
            ),
          ),
        ],
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
    final stuCourse = first?['courname']?.toString() ?? '';

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                InkWell(
                  onTap: () => setState(() {
                    // Go back one level — to the student list (keep class + demands loaded).
                    _drilldownAdmNo = null;
                  }),
                  borderRadius: BorderRadius.circular(10.r),
                  child: Container(
                    height: 40,
                    padding: EdgeInsets.symmetric(horizontal: 14.w),
                    decoration: BoxDecoration(
                      color: AppColors.accent,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                        SizedBox(width: 6.w),
                        Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                      ],
                    ),
                  ),
                ),
                SizedBox(width: 12.w),
                Container(width: 1, height: 18, color: AppColors.border),
                SizedBox(width: 12.w),
                InkWell(
                  onTap: () => setState(() {
                    _selectedClass = null;
                    _drilldownAdmNo = null;
                  }),
                  child: Text('Class-wise Demand', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ),
                SizedBox(width: 6.w),
                AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
                SizedBox(width: 6.w),
                InkWell(
                  onTap: () => setState(() {
                    _drilldownAdmNo = null;
                    _drilldownDemands = [];
                  }),
                  child: Text('${stuCourse.isNotEmpty ? '$stuCourse > ' : ''}$stuClass', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                ),
                SizedBox(width: 6.w),
                AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
                SizedBox(width: 6.w),
                Text('$stuName ($admNo)', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
              ],
            ),
          ),
          // Fee detail table
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.border),
                ),
                child: LayoutBuilder(builder: (context, constraints) {
          double totalDemand = 0, totalPaid = 0, totalFine = 0, totalBalance = 0;
          for (final d in demands) {
            totalDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
            final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
            final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
            final isPaid = pa > 0 || d['paidstatus'] == 'P';
            totalPaid += pa - (isPaid ? fa : 0);
            totalFine += isPaid ? fa : 0;
            totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
          }
          return SingleChildScrollView(child: Scrollbar(controller: _drilldownFeeScrollCtrl, thumbVisibility: true, trackVisibility: true, child: SingleChildScrollView(controller: _drilldownFeeScrollCtrl, scrollDirection: Axis.horizontal, child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(dividerThickness: 0,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
              headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
              dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              columnSpacing: 20, horizontalMargin: 16, dataRowMinHeight: 36, dataRowMaxHeight: 40, headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('SEMESTER')),
                DataColumn(label: Text('FEE TYPE')),
                DataColumn(label: Text('AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('FINE'), numeric: true),
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
                  final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                  final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                  final isPaidRow = pa > 0 || d['paidstatus'] == 'P';
                  final paid = pa - (isPaidRow ? fa : 0);
                  final fineDisplay = isPaidRow ? fa : 0.0;
                  final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  final statusLabel = balance <= 0 ? 'Paid' : paid > 0 ? 'Partial' : 'Pending';
                  final statusColor = balance <= 0 ? AppColors.success : paid > 0 ? AppColors.warning : AppColors.warning;
                  return DataRow(
                    color: WidgetStateProperty.all(i.isEven ? Colors.white : AppColors.surface),
                    cells: [
                    DataCell(Text('${i + 1}', style: const TextStyle(color: AppColors.textSecondary))),
                    DataCell(Text(term, style: const TextStyle(color: AppColors.textSecondary))),
                    DataCell(Text(feeType, style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    DataCell(Text(_formatCurrencyLocal(amount), style: const TextStyle(color: AppColors.textSecondary))),
                    DataCell(Text(_formatCurrencyLocal(paid), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    DataCell(Text(fineDisplay > 0 ? _formatCurrencyLocal(fineDisplay) : '-', style: TextStyle(fontWeight: FontWeight.w600, color: fineDisplay > 0 ? Colors.orange : AppColors.textSecondary))),
                    DataCell(Text(_formatCurrencyLocal(balance), style: const TextStyle(fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                    DataCell(Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(statusLabel, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: statusColor)),
                    )),
                  ]);
                }),
                // Grand total row
                DataRow(
                  color: WidgetStateProperty.all(AppColors.tableHeadBg),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrencyLocal(totalDemand), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrencyLocal(totalPaid), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrencyLocal(totalFine), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text(_formatCurrencyLocal(totalBalance), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ))));
        })))),
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

    return Column(
      children: [
        Expanded(child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    InkWell(
                      onTap: () => setState(() {
                        _selectedClass = null;
                        _studentPage = 0;
                        _studentSearchQuery = '';
                        _studentStatusFilter = null;
                      }),
                      borderRadius: BorderRadius.circular(10.r),
                      child: Container(
                        height: 40,
                        padding: EdgeInsets.symmetric(horizontal: 14.w),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AppIcon.linear('Chevron Left', size: 14, color: Colors.white),
                            SizedBox(width: 6.w),
                            Text('Back', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white)),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(width: 12.w),
                    Container(width: 1, height: 18, color: AppColors.border),
                    SizedBox(width: 12.w),
                    InkWell(
                      onTap: () => setState(() {
                        _selectedClass = null;
                        _studentPage = 0;
                        _studentSearchQuery = '';
                        _studentStatusFilter = null;
                      }),
                      child: Text('Class-wise Demand', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                    ),
                    SizedBox(width: 6.w),
                    AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
                    SizedBox(width: 6.w),
                    Text('${group.courseName != null ? '${group.courseName} > ' : ''}${group.className}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    SizedBox(width: 8.w),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        '$totalStudents students',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent),
                      ),
                    ),
                    const Spacer(),
                    AppSearchField(
                      hintText: 'Search...',
                      onChanged: (v) => setState(() {
                        _studentSearchQuery = v.trim().toLowerCase();
                        _studentPage = 0;
                      }),
                      width: 240,
                    ),
                    SizedBox(width: 8.w),
                    SizedBox(
                      height: 34,
                      child: DropdownButtonHideUnderline(
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(10.r),
                          ),
                          child: DropdownButton<String?>(
                            value: _studentStatusFilter,
                            hint: Text('All Status', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                            items: [
                              DropdownMenuItem<String>(value: null, child: Text('All Status', style: TextStyle(fontSize: 13.sp))),
                              DropdownMenuItem(value: 'Paid', child: Text('Paid', style: TextStyle(fontSize: 13.sp))),
                              DropdownMenuItem(value: 'Partial', child: Text('Partial', style: TextStyle(fontSize: 13.sp))),
                              DropdownMenuItem(value: 'Unpaid', child: Text('Unpaid', style: TextStyle(fontSize: 13.sp))),
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
              // Student list table
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Container(
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: LayoutBuilder(builder: (context, constraints) {
                // Compute totals for grand total row
                double gDemand = 0, gPaid = 0, gFine = 0, gBalance = 0;
                for (final key in studentKeys) {
                  for (final d in byStudent[key]!) {
                    gDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
                    final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                    final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                    final isPaid = pa > 0 || d['paidstatus'] == 'P';
                    gPaid += pa - (isPaid ? fa : 0);
                    gFine += isPaid ? fa : 0;
                    gBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
                  }
                }
                // Column widths for student drilldown table
                const double sHMargin = 16;
                const double sColSpacing = 12;
                const double sSnoW = 45;
                const double sAdmNoW = 80;
                const double sNameW = 160;
                const double sFeeAmtW = 100;
                const double sPaidW = 90;
                const double sFineW = 70;
                const double sBalanceW = 100;
                const double sStatusW = 70;
                const double sActionW = 80;
                final List<double> sColWidths = [sSnoW, sAdmNoW, sNameW, sFeeAmtW, sPaidW, sFineW, sBalanceW, sStatusW, sActionW];
                final sTotalFixedWidth = sColWidths.reduce((a, b) => a + b) + (sColWidths.length - 1) * sColSpacing + 2 * sHMargin;
                final sTableWidth = sTotalFixedWidth > constraints.maxWidth ? sTotalFixedWidth : constraints.maxWidth;
                final sExtraSpace = sTableWidth - sTotalFixedWidth;
                final sSum = sColWidths.reduce((a, b) => a + b);
                final List<double> sAdj = sColWidths.map((w) => w + (sExtraSpace * w / sSum)).toList();

                Widget sBuildCell(String text, int colIndex, {FontWeight? fontWeight, double? fontSize, Color? color, Widget? child}) {
                  final effectiveWeight = fontWeight ?? FontWeight.w600;
                  final effectiveColor = color ?? AppColors.textSecondary;
                  return SizedBox(
                    width: sAdj[colIndex],
                    child: child ?? Align(
                      alignment: colIndex >= 3 && colIndex <= 6 ? Alignment.centerRight : colIndex == 8 ? Alignment.centerRight : Alignment.centerLeft,
                      child: Text(text, style: TextStyle(fontSize: fontSize ?? 13.sp, fontWeight: effectiveWeight, color: effectiveColor)),
                    ),
                  );
                }

                Widget sBuildRow(List<Widget> cells, {Color? bgColor, double height = 40}) {
                  return Container(
                    height: height,
                    color: bgColor,
                    padding: EdgeInsets.symmetric(horizontal: sHMargin),
                    child: Row(
                      children: [
                        for (int ci = 0; ci < cells.length; ci++) ...[
                          if (ci > 0) const SizedBox(width: sColSpacing),
                          cells[ci],
                        ],
                      ],
                    ),
                  );
                }

                // --- HEADER ---
                final stuHeaderRow = sBuildRow(
                  [
                    sBuildCell('S No.', 0, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('ROLL NO', 1, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('STUDENT NAME', 2, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('FEE AMOUNT', 3, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('PAID', 4, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('FINE', 5, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('BALANCE', 6, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('STATUS', 7, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                    sBuildCell('ACTION', 8, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                  ],
                  bgColor: AppColors.tableHeadBg,
                  height: 42,
                );

                // --- BODY ROWS ---
                final stuBodyChildren = <Widget>[];
                if (studentKeys.isEmpty) {
                  stuBodyChildren.add(sBuildRow(
                    [
                      sBuildCell('', 0),
                      sBuildCell('No students found', 1),
                      for (int ci = 2; ci < 9; ci++) sBuildCell('', ci),
                    ],
                    height: 40,
                  ));
                } else {
                  for (int idx = 0; idx < studentKeys.length; idx++) {
                    final admNo = studentKeys[idx];
                    final studentDemands = byStudent[admNo]!;
                    final stuName = studentDemands.first['_stuname']?.toString() ?? '-';
                    double sDemand = 0, sPaid = 0, sFine = 0, sBalance = 0;
                    for (final d in studentDemands) {
                      sDemand += (d['feeamount'] as num?)?.toDouble() ?? 0;
                      final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                      final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                      final isPaid = pa > 0 || d['paidstatus'] == 'P';
                      sPaid += pa - (isPaid ? fa : 0);
                      sFine += isPaid ? fa : 0;
                      sBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
                    }
                    final allPaid = studentDemands.every((d) => d['paidstatus'] == 'P');
                    final anyPaid = studentDemands.any((d) => d['paidstatus'] == 'P');
                    stuBodyChildren.add(InkWell(
                      onTap: () => setState(() {
                        _drilldownAdmNo = admNo;
                        _drilldownDemands = studentDemands;
                      }),
                      child: Container(
                        color: idx.isEven ? Colors.white : AppColors.surface,
                        padding: EdgeInsets.symmetric(horizontal: sHMargin),
                        constraints: BoxConstraints(minHeight: 40),
                        child: Row(
                          children: [
                            SizedBox(width: sAdj[0], child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[1], child: Text(admNo, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[2], child: Text(stuName, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[3], child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(sDemand), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[4], child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(sPaid), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[5], child: Align(alignment: Alignment.centerRight, child: Text(sFine > 0 ? _formatCurrency(sFine) : '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: sFine > 0 ? Colors.orange : AppColors.textSecondary)))),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[6], child: Align(alignment: Alignment.centerRight, child: Text(_formatCurrency(sBalance), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[7], child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: allPaid ? AppColors.success.withValues(alpha: 0.1) : anyPaid ? AppColors.warning.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(allPaid ? 'Paid' : anyPaid ? 'Partial' : 'Unpaid', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: allPaid ? AppColors.success : anyPaid ? AppColors.warning : AppColors.error)),
                            )),
                            const SizedBox(width: sColSpacing),
                            SizedBox(width: sAdj[8], child: Align(
                              alignment: Alignment.centerRight,
                              child: AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary),
                            )),
                          ],
                        ),
                      ),
                    ));
                    stuBodyChildren.add(const Divider(height: 1, thickness: 0.5, color: Color(0xFFE8E8E8)));
                  }
                }

                // --- FOOTER (GRAND TOTAL) ---
                final stuFooterRow = sBuildRow(
                  [
                    sBuildCell('', 0, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                    sBuildCell('', 1, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                    sBuildCell('Total ($totalStudents students)', 2, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                    sBuildCell(_formatCurrency(gDemand), 3, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                    sBuildCell(_formatCurrency(gPaid), 4, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                    sBuildCell(_formatCurrency(gFine), 5, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                    sBuildCell(_formatCurrency(gBalance), 6, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                    sBuildCell('', 7),
                    sBuildCell('', 8),
                  ],
                  bgColor: AppColors.tableHeadBg,
                  height: 42,
                );

                _updateCanScrollStudent();
                return Column(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        controller: _studentTableScrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: sTableWidth,
                          height: constraints.maxHeight,
                          child: Column(
                            children: [
                              // Fixed header
                              stuHeaderRow,
                              // Scrollable body
                              Expanded(
                                child: SingleChildScrollView(
                                  scrollDirection: Axis.vertical,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: stuBodyChildren,
                                  ),
                                ),
                              ),
                              // Fixed footer
                              stuFooterRow,
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Classic horizontal scrollbar with arrow buttons
                    if (_canScrollStudent)
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
                                _studentTableScrollController.animateTo(
                                  (_studentTableScrollController.offset - 100).clamp(0.0, _studentTableScrollController.position.maxScrollExtent),
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
                                child: AppIcon.linear('Chevron Left', size: 16, color: const Color(0xFF333333)),
                              ),
                            ),
                            // Scrollbar track + thumb
                            Expanded(
                              child: LayoutBuilder(
                                builder: (context, scrollbarConstraints) {
                                  final maxExtent = _studentTableScrollController.hasClients &&
                                          _studentTableScrollController.positions.isNotEmpty &&
                                          _studentTableScrollController.position.hasContentDimensions
                                      ? _studentTableScrollController.position.maxScrollExtent
                                      : 1.0;
                                  final viewportWidth = _studentTableScrollController.hasClients &&
                                          _studentTableScrollController.positions.isNotEmpty &&
                                          _studentTableScrollController.position.hasContentDimensions
                                      ? _studentTableScrollController.position.viewportDimension
                                      : scrollbarConstraints.maxWidth;
                                  final totalContentWidth = maxExtent + viewportWidth;
                                  final thumbRatio = (viewportWidth / totalContentWidth).clamp(0.1, 1.0);
                                  final thumbWidth = (scrollbarConstraints.maxWidth * thumbRatio).clamp(30.0, scrollbarConstraints.maxWidth);
                                  final trackSpace = scrollbarConstraints.maxWidth - thumbWidth;
                                  final scrollRatio = maxExtent > 0 ? (_studentTableScrollController.offset / maxExtent).clamp(0.0, 1.0) : 0.0;
                                  final thumbOffset = trackSpace * scrollRatio;

                                  return GestureDetector(
                                    onHorizontalDragUpdate: (details) {
                                      if (trackSpace > 0) {
                                        final newRatio = ((thumbOffset + details.delta.dx) / trackSpace).clamp(0.0, 1.0);
                                        _studentTableScrollController.jumpTo(newRatio * maxExtent);
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
                                _studentTableScrollController.animateTo(
                                  (_studentTableScrollController.offset + 100).clamp(0.0, _studentTableScrollController.position.maxScrollExtent),
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
                                child: AppIcon.linear('Chevron Right', size: 16, color: const Color(0xFF333333)),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              })))),
            ],
          ),
        )),
      ],
    );
  }

  Widget _buildSummaryCard(String icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: AppIcon(icon, color: iconColor, size: 18),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(label, style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWinScrollbar(double viewportW, double contentW, double barH) {
    return ListenableBuilder(
      listenable: _classTableScrollController,
      builder: (context, _) {
        final canScroll = contentW > viewportW;
        // Hide scrollbar entirely when content fits in viewport
        if (!canScroll) return const SizedBox.shrink();
        final maxScroll = canScroll ? contentW - viewportW : 1.0;
        final offset = (_classTableScrollController.hasClients && canScroll)
            ? _classTableScrollController.offset.clamp(0.0, maxScroll)
            : 0.0;
        final ratio = canScroll ? offset / maxScroll : 0.0;
        const btnW = 18.0;
        final trackW = viewportW - btnW * 2;
        final thumbW = canScroll ? (viewportW / contentW * trackW).clamp(30.0, trackW) : trackW;
        final thumbLeft = ratio * (trackW - thumbW);

        void scrollBy(double delta) {
          if (!_classTableScrollController.hasClients) return;
          _classTableScrollController.jumpTo(
              (_classTableScrollController.offset + delta).clamp(0.0, maxScroll));
        }

        return Container(
          height: barH,
          decoration: const BoxDecoration(
            color: Color(0xFFB0B0B0),
            border: Border(top: BorderSide(color: Color(0xFF555555))),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
          ),
          child: Row(
            children: [
              _winArrowBtn('◄', canScroll ? () => scrollBy(-60) : null, btnW, barH),
              Expanded(
                child: GestureDetector(
                  onTapDown: (d) {
                    if (!canScroll) return;
                    _classTableScrollController.jumpTo(
                        (d.localPosition.dx / trackW * maxScroll).clamp(0.0, maxScroll));
                  },
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      Positioned.fill(child: Container(color: const Color(0xFFB0B0B0))),
                      if (canScroll)
                        Positioned(
                          left: thumbLeft,
                          top: 1,
                          bottom: 1,
                          width: thumbW,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (d) {
                              final scale = maxScroll / (trackW - thumbW);
                              scrollBy(d.delta.dx * scale);
                            },
                            child: Container(
                              decoration: BoxDecoration(
                                color: const Color(0xFF555555),
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(color: const Color(0xFF333333)),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              _winArrowBtn('►', canScroll ? () => scrollBy(60) : null, btnW, barH),
            ],
          ),
        );
      },
    );
  }

  Widget _winArrowBtn(String arrow, VoidCallback? onTap, double w, double h) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFB0B0B0),
          border: Border(right: BorderSide(color: const Color(0xFF555555), width: arrow == '◄' ? 1 : 0),
                        left: BorderSide(color: const Color(0xFF555555), width: arrow == '►' ? 1 : 0)),
        ),
        child: Text(arrow, style: TextStyle(fontSize: 8.sp, color: onTap != null ? const Color(0xFF333333) : const Color(0xFFAAAAAA))),
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

  List<String> _feeTypes = [];
  Map<int, String> _payNumberMap = {};
  double _summaryTotalDemand = 0;
  double _summaryTotalPaid = 0;
  double _summaryTotalPending = 0;

  String _searchQuery = '';
  String? _filterFeeType;

  // Pagination for date-wise table
  int _dateWisePage = 0;
  static const int _dateWisePageSize = 10;

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
      // Stage 1: fetch demands and totals in parallel
      final results = await Future.wait([
        SupabaseService.getPaidFeeDemands(insId),
        SupabaseService.getFeeTotals(insId),
      ]);
      final demands = results[0] as List<Map<String, dynamic>>;
      final feeTotals = results[1] as Map<String, double>;

      // Stage 2: fetch pay numbers (needs pay_ids from demands)
      final payIds = demands
          .map((d) => d['pay_id'] as int?)
          .where((id) => id != null)
          .cast<int>()
          .toSet()
          .toList();
      final payNumberMap = await SupabaseService.getPayNumberMap(payIds, insId: insId);

      if (mounted) {
        setState(() {
          _allDemands = demands;
          _payNumberMap = payNumberMap;
          _summaryTotalDemand = feeTotals['totalDemand'] ?? 0;
          // Total Collected card shows actual fee + fine paid
          _summaryTotalPaid = (feeTotals['totalPaid'] ?? 0) + (feeTotals['totalFine'] ?? 0);
          _summaryTotalPending = feeTotals['totalPending'] ?? 0;
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

    // Collect all fee types from paid demands (FINE rows treated as normal fee type)
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
        final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
        final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
        totalPaid += pa - ((pa > 0 || d['paidstatus'] == 'P') ? fa : 0);
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

  Future<void> _openDateMethodFilter() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        DateTime from = _fromDate;
        DateTime to = _toDate;
        return StatefulBuilder(builder: (ctx, setStateDialog) {
          Widget presetChip(String label, VoidCallback onTap) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: InkWell(
                  onTap: onTap,
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  ),
                ),
              );

          Widget datePickerBox({required String hint, required DateTime value, required ValueChanged<DateTime> onChanged}) {
            return InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: ctx,
                  initialDate: value,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) onChanged(picked);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIcon.linear('calendar', size: 14, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(_formatFilterDate(value),
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary)),
                  ],
                ),
              ),
            );
          }

          Widget sectionLabel(String text) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(text, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textSecondary, letterSpacing: 0.3)),
              );

          return AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 8),
            title: Row(
              children: [
                Text('Filters', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
                const Spacer(),
                IconButton(
                  onPressed: () => Navigator.pop(ctx),
                  icon: const AppIcon.linear('close-circle', size: 20, color: AppColors.textSecondary),
                  splashRadius: 18,
                  tooltip: 'Close',
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  sectionLabel('QUICK RANGE'),
                  Row(children: [
                    presetChip('Today', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = DateTime(now.year, now.month, now.day); to = DateTime(now.year, now.month, now.day); });
                    }),
                    presetChip('7 Days', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = now.subtract(const Duration(days: 7)); to = DateTime(now.year, now.month, now.day); });
                    }),
                    presetChip('30 Days', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = now.subtract(const Duration(days: 30)); to = DateTime(now.year, now.month, now.day); });
                    }),
                    presetChip('This Month', () {
                      final now = DateTime.now();
                      setStateDialog(() { from = DateTime(now.year, now.month, 1); to = DateTime(now.year, now.month, now.day); });
                    }),
                  ]),
                  const SizedBox(height: 16),
                  sectionLabel('CUSTOM RANGE'),
                  Row(children: [
                    Expanded(child: datePickerBox(hint: 'From', value: from, onChanged: (d) => setStateDialog(() => from = d))),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: Text('—')),
                    Expanded(child: datePickerBox(hint: 'To', value: to, onChanged: (d) => setStateDialog(() => to = d))),
                  ]),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => setStateDialog(() {
                  final now = DateTime.now();
                  from = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
                  to = DateTime(now.year, now.month, now.day);
                }),
                child: Text('Clear', style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp, fontWeight: FontWeight.w600)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  setState(() {
                    _fromDate = from;
                    _toDate = to;
                  });
                  Navigator.pop(ctx);
                  _applyFilter();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        });
      },
    );
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
            AppIcon.linear('calendar', size: 14, color: AppColors.accent),
            SizedBox(width: 6.w),
            Text(_formatFilterDate(date), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickFilter(String label, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
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

  /// Build student rows for a date group, pivoted by fee type
  List<Map<String, dynamic>> _buildStudentRows(List<Map<String, dynamic>> demands) {
    // Group by pay_id (each payment is a row)
    final Map<int, List<Map<String, dynamic>>> paymentMap = {};
    for (final d in demands) {
      final payId = d['pay_id'] as int?;
      if (payId != null) {
        paymentMap.putIfAbsent(payId, () => []).add(d);
      }
    }

    final rows = <Map<String, dynamic>>[];

    for (final entry in paymentMap.entries) {
      final payId = entry.key;
      final studentDemands = entry.value;
      final first = studentDemands.first;
      final stuName = first['students'] is Map
          ? (first['students']['stuname']?.toString() ?? '-')
          : (first['stuname']?.toString() ?? '-');
      final stuClass = first['stuclass']?.toString() ?? '-';
      final stuCourse = first['courname']?.toString() ?? '-';
      final admNo = first['stuadmno']?.toString() ?? '-';
      final payNo = _payNumberMap[payId] ?? '-';

      final Map<String, double> feeAmounts = {};
      double total = 0;
      double fine = 0;
      for (final d in studentDemands) {
        final ft = d['demfeetype']?.toString() ?? '';
        final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
        final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
        final isPaid = pa > 0 || d['paidstatus'] == 'P';
        final amt = pa - (isPaid ? fa : 0);
        if (isPaid) fine += fa;
        if (ft.isNotEmpty) {
          feeAmounts[ft] = (feeAmounts[ft] ?? 0) + amt;
          total += amt;
        }
      }

      rows.add({
        'payNo': payNo,
        'admNo': admNo,
        'stuName': stuName,
        'stuCourse': stuCourse,
        'stuClass': stuClass,
        'feeAmounts': feeAmounts,
        'fine': fine,
        'total': total + fine,
      });
    }

    rows.sort((a, b) => (a['payNo'] as String).compareTo(b['payNo'] as String));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    // Build flat table rows with date headers and S.Total rows
    final List<Map<String, dynamic>> flatRows = [];
    int globalSno = 0;
    final Map<String, double> grandFeeTypeTotals = {};
    double grandTotal = 0;
    double grandFine = 0;
    final uniqueStudentIds = <String>{};
    int totalDateCount = 0;

    // Use fee types from actual paid demands so columns match data
    final displayFeeTypes = _filterFeeType != null ? [_filterFeeType!] : _feeTypes;

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

      totalDateCount++;

      // Date header row
      flatRows.add({'_type': 'dateHeader', 'date': _formatDisplayDate(group.date)});

      final Map<String, double> dateTotals = {};
      double dateTotal = 0;
      double dateFine = 0;

      for (final row in filteredStudentRows) {
        globalSno++;
        final feeAmounts = row['feeAmounts'] as Map<String, double>;
        final total = row['total'] as double;
        final fine = (row['fine'] as num?)?.toDouble() ?? 0;
        flatRows.add({
          '_type': 'data',
          'sno': globalSno,
          'payNo': row['payNo'] as String,
          'admNo': row['admNo'] as String,
          'stuName': row['stuName'] as String,
          'stuCourse': row['stuCourse'] as String,
          'stuClass': row['stuClass'] as String,
          'feeAmounts': feeAmounts,
          'fine': fine,
          'total': total,
        });
        for (final ft in displayFeeTypes) {
          dateTotals[ft] = (dateTotals[ft] ?? 0) + (feeAmounts[ft] ?? 0);
          grandFeeTypeTotals[ft] = (grandFeeTypeTotals[ft] ?? 0) + (feeAmounts[ft] ?? 0);
        }
        dateTotal += total;
        grandTotal += total;
        dateFine += fine;
        grandFine += fine;
      }
      for (final row in filteredStudentRows) {
        final admNo = row['admNo']?.toString() ?? '';
        if (admNo.isNotEmpty) uniqueStudentIds.add(admNo);
      }

      // S.Total row
      flatRows.add({'_type': 'subTotal', 'feeAmounts': dateTotals, 'fine': dateFine, 'total': dateTotal});
    }

    // Filter display fee types to only those with actual payments
    final activeDisplayFeeTypes = displayFeeTypes.where((ft) => (grandFeeTypeTotals[ft] ?? 0) > 0).toList();

    _updateCanScroll();

    return Column(
          children: [
            // Summary cards
            Row(
              children: [
                _buildSummaryCard('people', Colors.blue, '${uniqueStudentIds.length}', 'Total Students'),
                SizedBox(width: 16.w),
                _buildSummaryCard('wallet-1', AppColors.accent, _formatCurrency(_summaryTotalDemand), 'Total Demand'),
                SizedBox(width: 16.w),
                _buildSummaryCard('tick-circle', AppColors.success, _formatCurrency(_summaryTotalPaid), 'Total Collected (Fee + Fine)'),
                SizedBox(width: 16.w),
                _buildSummaryCard('clock', AppColors.warning, _formatCurrency(_summaryTotalPending), 'Total Pending'),
              ],
            ),
            SizedBox(height: 16.h),
            // Spreadsheet-like table
            Expanded(child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // Title bar with search & filter
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        AppIcon('grid-1', size: 18, color: AppColors.accent),
                        SizedBox(width: 8.w),
                        Text('Date-wise Paid Collection Register', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                        SizedBox(width: 12.w),
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8.r),
                          ),
                          child: Text('$totalDateCount dates  |  ${uniqueStudentIds.length} students',
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
                        ),
                        const Spacer(),
                        AppSearchField(
                          hintText: 'Search...',
                          onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                          width: 240,
                        ),
                        SizedBox(width: 8.w),
                        SizedBox(
                          height: 40,
                          child: DropdownButtonHideUnderline(
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 14.w),
                              decoration: BoxDecoration(
                                border: Border.all(color: AppColors.border),
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: DropdownButton<String?>(
                                value: _filterFeeType,
                                hint: Text('All Fee Types', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                items: [
                                  const DropdownMenuItem<String>(value: null, child: Text('All Fee Types')),
                                  ..._feeTypes.map((ft) => DropdownMenuItem<String>(value: ft, child: Text(ft))),
                                ],
                                onChanged: (v) => setState(() => _filterFeeType = v),
                              ),
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        SizedBox(
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: _openDateMethodFilter,
                            icon: AppIcon.linear('calendar-1', size: 16, color: AppColors.textPrimary),
                            label: Text('Date & Method', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.border),
                              padding: EdgeInsets.symmetric(horizontal: 14.w),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                            ),
                          ),
                        ),
                        SizedBox(width: 8.w),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: flatRows.isNotEmpty ? () => _exportToExcel(flatRows, activeDisplayFeeTypes, grandFeeTypeTotals, grandTotal) : null,
                            icon: AppIcon('document-download', size: 16, color: Colors.white),
                            label: const Text('Export'),
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
                        SizedBox(width: 8.w),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: _fetchData,
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
                  ),
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_dateGroups.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(48.w),
                      child: Center(
                        child: Column(
                          children: [
                            AppIcon.linear('search-favorite', size: 40.sp, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                            SizedBox(height: 8.h),
                            const Text('No paid collections found', style: TextStyle(color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    )
                  else
                    Expanded(child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Container(
                        clipBehavior: Clip.antiAlias,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Column(
                      children: [
                        Expanded(child: LayoutBuilder(
                          builder: (context, constraints) {
                            const headerBg = AppColors.tableHeadBg;
                            const subTotalBg = Color(0xFFE2E8F0);

                            // Column widths: SNO, RECPT.NO, ROLL NO, NAME, COURSE, CLASS, ...feeTypes, TOTAL
                            const double colSpacing = 12;
                            const double hMargin = 12;
                            const double snoW = 50;
                            const double recptW = 100;
                            const double admnW = 80;
                            const double nameW = 150;
                            const double courseW = 100;
                            const double classW = 70;
                            const double feeColW = 170;
                            const double totalColW = 100;
                            final int feeCount = activeDisplayFeeTypes.length;

                            // Build column widths list (FINE col before TOTAL)
                            final List<double> colWidths = [
                              snoW, recptW, admnW, nameW, courseW, classW,
                              ...List.filled(feeCount, feeColW),
                              feeColW, // FINE
                              totalColW,
                            ];
                            final totalFixedWidth = colWidths.reduce((a, b) => a + b) + (colWidths.length - 1) * colSpacing + 2 * hMargin;
                            // Table is at least viewport width, but grows larger if columns need more room → horizontal scroll kicks in.
                            final tableWidth = totalFixedWidth > constraints.maxWidth
                                ? totalFixedWidth
                                : constraints.maxWidth;

                            // Distribute extra space proportionally when viewport is wider than needed
                            final extraSpace = tableWidth - totalFixedWidth;
                            final List<double> adjustedWidths = colWidths.map((w) => w + (extraSpace * w / colWidths.reduce((a, b) => a + b))).toList();

                            Widget buildCell(String text, int colIndex, {FontWeight? fontWeight, double? fontSize, Color? color, TextAlign? textAlign, bool truncate = false}) {
                              final effectiveWeight = fontWeight ?? FontWeight.w600;
                              final effectiveColor = color ?? AppColors.textSecondary;
                              final child = truncate
                                  ? Text(text, overflow: TextOverflow.ellipsis, maxLines: 1,
                                      style: TextStyle(fontSize: fontSize ?? 13.sp, fontWeight: effectiveWeight, color: effectiveColor))
                                  : Text(text, textAlign: textAlign,
                                      style: TextStyle(fontSize: fontSize ?? 13.sp, fontWeight: effectiveWeight, color: effectiveColor));
                              return SizedBox(
                                width: adjustedWidths[colIndex],
                                child: truncate ? child : Align(
                                  alignment: (colIndex >= 5) ? Alignment.centerRight : Alignment.centerLeft,
                                  child: child,
                                ),
                              );
                            }

                            Widget buildRowContainer(List<Widget> cells, {Color? bgColor, double height = 36}) {
                              return Container(
                                height: height,
                                color: bgColor,
                                padding: EdgeInsets.symmetric(horizontal: hMargin.toDouble()),
                                child: Row(
                                  children: [
                                    for (int i = 0; i < cells.length; i++) ...[
                                      if (i > 0) const SizedBox(width: colSpacing),
                                      cells[i],
                                    ],
                                  ],
                                ),
                              );
                            }

                            // --- HEADER ---
                            final headerRow = buildRowContainer(
                              [
                                buildCell('SNO', 0, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                buildCell('RECPT.NO', 1, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                buildCell('ROLL NO', 2, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                buildCell('NAME', 3, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                buildCell('COURSE', 4, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                buildCell('CLASS', 5, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                for (int i = 0; i < feeCount; i++)
                                  buildCell(activeDisplayFeeTypes[i].toUpperCase(), 6 + i, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                buildCell('FINE', 6 + feeCount, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                                buildCell('TOTAL', 7 + feeCount, fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary),
                              ],
                              bgColor: headerBg,
                              height: 40,
                            );

                            // --- BODY ROWS ---
                            final bodyChildren = <Widget>[];
                            for (final row in flatRows) {
                              final type = row['_type'] as String;
                              if (type == 'grandTotal') continue;

                              if (type == 'dateHeader') {
                                // Date header spans the full table row, not constrained to col 0 width
                                bodyChildren.add(Container(
                                  height: 36,
                                  color: const Color(0xFFF1F5F9),
                                  padding: EdgeInsets.symmetric(horizontal: hMargin.toDouble()),
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    row['date'] as String,
                                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.accent),
                                  ),
                                ));
                              } else if (type == 'subTotal') {
                                final feeAmts = row['feeAmounts'] as Map<String, double>;
                                final total = row['total'] as double;
                                final fine = (row['fine'] as num?)?.toDouble() ?? 0;
                                bodyChildren.add(buildRowContainer(
                                  [
                                    buildCell('S.Total', 0, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                    buildCell('', 1),
                                    buildCell('', 2),
                                    buildCell('', 3),
                                    buildCell('', 4),
                                    buildCell('', 5),
                                    for (int i = 0; i < feeCount; i++)
                                      buildCell(
                                        (feeAmts[activeDisplayFeeTypes[i]] ?? 0) > 0
                                            ? (feeAmts[activeDisplayFeeTypes[i]]!).toStringAsFixed(0) : '',
                                        6 + i, fontWeight: FontWeight.w700, color: AppColors.textPrimary,
                                      ),
                                    buildCell(fine > 0 ? fine.toStringAsFixed(0) : '', 6 + feeCount, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                    buildCell(total.toStringAsFixed(0), 7 + feeCount, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                  ],
                                  bgColor: subTotalBg,
                                  height: 36,
                                ));
                              } else {
                                // Data row
                                final feeAmts = row['feeAmounts'] as Map<String, double>;
                                final fine = (row['fine'] as num?)?.toDouble() ?? 0;
                                bodyChildren.add(buildRowContainer(
                                  [
                                    buildCell('${row['sno']}', 0),
                                    buildCell(row['payNo'] as String, 1),
                                    buildCell(row['admNo'] as String, 2),
                                    buildCell(row['stuName'] as String, 3, truncate: true),
                                    buildCell(row['stuCourse'] as String, 4),
                                    buildCell(row['stuClass'] as String, 5),
                                    for (int i = 0; i < feeCount; i++)
                                      buildCell(
                                        (feeAmts[activeDisplayFeeTypes[i]] ?? 0) > 0
                                            ? (feeAmts[activeDisplayFeeTypes[i]]!).toStringAsFixed(0) : '',
                                        6 + i,
                                      ),
                                    buildCell(fine > 0 ? fine.toStringAsFixed(0) : '', 6 + feeCount),
                                    buildCell(
                                      (row['total'] as double).toStringAsFixed(0),
                                      7 + feeCount, fontWeight: FontWeight.w600,
                                    ),
                                  ],
                                  height: 36,
                                ));
                                // Thin divider between data rows
                                bodyChildren.add(const Divider(height: 1, thickness: 0.5, color: Color(0xFFE8E8E8)));
                              }
                            }

                            // --- FOOTER (GRAND TOTAL) ---
                            final footerRow = buildRowContainer(
                              [
                                buildCell('', 0),
                                buildCell('', 1),
                                buildCell('', 2),
                                buildCell('GRAND TOTAL', 3, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                                buildCell('', 4),
                                buildCell('', 5),
                                for (int i = 0; i < feeCount; i++)
                                  buildCell(
                                    (grandFeeTypeTotals[activeDisplayFeeTypes[i]] ?? 0) > 0
                                        ? (grandFeeTypeTotals[activeDisplayFeeTypes[i]]!).toStringAsFixed(0) : '',
                                    6 + i, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary,
                                  ),
                                buildCell(grandFine > 0 ? grandFine.toStringAsFixed(0) : '', 6 + feeCount, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                                buildCell(grandTotal.toStringAsFixed(0), 7 + feeCount, fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary),
                              ],
                              bgColor: headerBg,
                              height: 40,
                            );

                            return SingleChildScrollView(
                              controller: _tableScrollController,
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: tableWidth,
                                height: constraints.maxHeight,
                                child: Column(
                                  children: [
                                    // Fixed header
                                    headerRow,
                                    // Scrollable body
                                    Expanded(
                                      child: SingleChildScrollView(
                                        scrollDirection: Axis.vertical,
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: bodyChildren,
                                        ),
                                      ),
                                    ),
                                    // Fixed footer
                                    footerRow,
                                  ],
                                ),
                              ),
                            );
                          },
                        )),
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
                                    child: AppIcon.linear('Chevron Left', size: 16, color: const Color(0xFF333333)),
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
                                    child: AppIcon.linear('Chevron Right', size: 16, color: const Color(0xFF333333)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    )))),
                ],
              ),
            )),
          ],
    );
  }

  Future<void> _exportToExcel(
    List<Map<String, dynamic>> flatRows,
    List<String> feeTypes,
    Map<String, double> grandFeeTypeTotals,
    double grandTotal,
  ) async {
    // Fetch institution info
    final auth = Provider.of<AuthProvider>(context, listen: false);
    String insName = auth.insName ?? '';
    String insAddress = '';
    String insMobile = '';
    String insEmail = '';
    if (auth.insId != null) {
      final insInfo = await SupabaseService.getInstitutionInfo(auth.insId!);
      if (insInfo.name != null) insName = insInfo.name!;
      if (insInfo.address != null) insAddress = insInfo.address!;
      if (insInfo.mobile != null) insMobile = insInfo.mobile!;
      if (insInfo.email != null) insEmail = insInfo.email!;
    }

    final excel = xl.Excel.createExcel();
    final sheetName = 'Collection';
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    // Styles
    final insStyle = xl.CellStyle(bold: true, fontSize: 14, horizontalAlign: xl.HorizontalAlign.Center);
    final insDetailStyle = xl.CellStyle(fontSize: 10, horizontalAlign: xl.HorizontalAlign.Center);
    final labelStyle = xl.CellStyle(bold: true, fontSize: 13);
    final colHeaderStyle = xl.CellStyle(
      bold: true, fontSize: 10,
      backgroundColorHex: xl.ExcelColor.fromHexString('#2D3748'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    );
    final dateHeaderStyle = xl.CellStyle(bold: true, fontSize: 13, fontColorHex: xl.ExcelColor.fromHexString('#2563EB'));
    final subTotalStyle = xl.CellStyle(bold: true, fontSize: 13, backgroundColorHex: xl.ExcelColor.fromHexString('#E2E8F0'));
    final totalRowStyle = xl.CellStyle(
      bold: true, fontSize: 13,
      backgroundColorHex: xl.ExcelColor.fromHexString('#2D3748'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    );

    // Filter fee types to only those with actual payments
    final activeFeeTypes = feeTypes.where((ft) => (grandFeeTypeTotals[ft] ?? 0) > 0).toList();

    final totalCols = 6 + activeFeeTypes.length + 1; // +1 for TOTAL
    int row = 0;

    // Institution name
    final insNameCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    insNameCell.value = xl.TextCellValue(insName.toUpperCase());
    insNameCell.cellStyle = insStyle;
    sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
    row++;

    // Institution address
    if (insAddress.isNotEmpty) {
      final addrCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      addrCell.value = xl.TextCellValue(insAddress);
      addrCell.cellStyle = insDetailStyle;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
    }

    // Contact
    final contactParts = <String>[];
    if (insMobile.isNotEmpty) contactParts.add('Ph: $insMobile');
    if (insEmail.isNotEmpty) contactParts.add('Email: $insEmail');
    if (contactParts.isNotEmpty) {
      final c = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      c.value = xl.TextCellValue(contactParts.join('  |  '));
      c.cellStyle = insDetailStyle;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
    }
    row++; // blank

    // "FEE COLLECTED BY : ALL USERS"
    final feeLabel = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    feeLabel.value = xl.TextCellValue('FEE COLLECTED BY : ALL USERS');
    feeLabel.cellStyle = labelStyle;
    sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
    row++;

    // Column headers (no Challan No.)
    final headers = ['SNO', 'Recpt. No.', 'Roll No.', 'Name', 'Course', 'Class', ...activeFeeTypes.map((ft) => ft.toUpperCase()), 'TOTAL'];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = xl.TextCellValue(headers[c]);
      cell.cellStyle = colHeaderStyle;
    }
    row++;

    // Data rows
    for (final r in flatRows) {
      final type = r['_type'] as String;

      if (type == 'dateHeader') {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        cell.value = xl.TextCellValue(r['date'] as String);
        cell.cellStyle = dateHeaderStyle;
        row++;
      } else if (type == 'subTotal') {
        final feeAmts = r['feeAmounts'] as Map<String, double>;
        final total = r['total'] as double;
        final stCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
        stCell.value = xl.TextCellValue('S.Total');
        stCell.cellStyle = subTotalStyle;
        for (var i = 1; i < 6; i++) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: row)).cellStyle = subTotalStyle;
        }
        for (var i = 0; i < activeFeeTypes.length; i++) {
          final amt = feeAmts[activeFeeTypes[i]] ?? 0;
          final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + i, rowIndex: row));
          if (amt > 0) cell.value = xl.IntCellValue(amt.toInt());
          cell.cellStyle = subTotalStyle;
        }
        final tCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + activeFeeTypes.length, rowIndex: row));
        tCell.value = xl.IntCellValue(total.toInt());
        tCell.cellStyle = subTotalStyle;
        row++;
      } else {
        // Data row
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.IntCellValue(r['sno'] as int);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue(r['payNo'] as String);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.TextCellValue(r['admNo'] as String);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.TextCellValue(r['stuName'] as String);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = xl.TextCellValue(r['stuCourse'] as String);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row)).value = xl.TextCellValue(r['stuClass'] as String);

        final feeAmts = r['feeAmounts'] as Map<String, double>;
        for (var i = 0; i < activeFeeTypes.length; i++) {
          final amt = feeAmts[activeFeeTypes[i]] ?? 0;
          if (amt > 0) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + i, rowIndex: row)).value = xl.IntCellValue(amt.toInt());
          }
        }
        final total = r['total'] as double;
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + activeFeeTypes.length, rowIndex: row)).value = xl.IntCellValue(total.toInt());
        row++;
      }
    }

    // Grand total row
    final gtLabel = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    gtLabel.value = xl.TextCellValue('GRAND TOTAL');
    gtLabel.cellStyle = totalRowStyle;
    for (var c = 1; c < 6; c++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = totalRowStyle;
    }
    for (var i = 0; i < activeFeeTypes.length; i++) {
      final amt = grandFeeTypeTotals[activeFeeTypes[i]] ?? 0;
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + i, rowIndex: row));
      if (amt > 0) cell.value = xl.IntCellValue(amt.toInt());
      cell.cellStyle = totalRowStyle;
    }
    final gtCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + activeFeeTypes.length, rowIndex: row));
    gtCell.value = xl.IntCellValue(grandTotal.toInt());
    gtCell.cellStyle = totalRowStyle;

    // Column widths
    sheet.setColumnWidth(0, 8);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 12);
    sheet.setColumnWidth(3, 22);
    sheet.setColumnWidth(4, 14);
    sheet.setColumnWidth(5, 8);
    for (var i = 0; i < activeFeeTypes.length; i++) {
      sheet.setColumnWidth(6 + i, 14);
    }
    sheet.setColumnWidth(6 + activeFeeTypes.length, 12);

    // Save
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Date-wise Collection',
      fileName: 'DateWise_Collection_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );

    if (result != null) {
      final path = result.endsWith('.xlsx') ? result : '$result.xlsx';
      final bytes = excel.encode();
      if (bytes != null) {
        await File(path).writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Exported to $path'), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  Widget _buildSummaryCard(String icon, Color iconColor, String value, String label) {
    return Expanded(
      child: Container(
        padding: EdgeInsets.all(20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: EdgeInsets.all(6.w),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: AppIcon(icon, color: iconColor, size: 18),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(label, style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary)),
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
  final double totalFine;

  _DateGroup({
    required this.date,
    required this.payments,
    required this.totalAmount,
    this.totalFine = 0,
  });
}

class _ClassGroup {
  final String className;
  final String? courseName;
  final List<Map<String, dynamic>> demands;
  final double totalDemand;
  final double totalConcession;
  final double totalPaid; // Fee-only collection (already excludes fine)
  final double totalFine;
  final double totalPending;
  final int studentCount;
  final List<String> feeTypes; // "FeeGroup > FeeType" list

  _ClassGroup({
    required this.className,
    this.courseName,
    required this.demands,
    required this.totalDemand,
    required this.totalConcession,
    required this.totalPaid,
    this.totalFine = 0,
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
    final totalPaid = demands.fold<double>(0, (s, d) {
      final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
      return s + pa - ((pa > 0 || d['paidstatus'] == 'P') ? fa : 0);
    });
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
                SizedBox(width: 36, child: Text('${widget.index}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500))),
                Expanded(flex: 1, child: Text(widget.admNo, style: TextStyle(fontSize: 13.sp))),
                Expanded(flex: 3, child: Text(stuName, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500))),
                Expanded(flex: 2, child: Text(widget.formatCurrency(totalFee), textAlign: TextAlign.right, style: TextStyle(fontSize: 13.sp))),
                Expanded(flex: 2, child: Text(widget.formatCurrency(totalPaid), textAlign: TextAlign.right, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.success))),
                Expanded(flex: 2, child: Text(widget.formatCurrency(totalBalance), textAlign: TextAlign.right, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: totalBalance > 0 ? AppColors.warning : AppColors.textSecondary))),
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
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(
                        allPaid ? 'Paid' : anyPaid ? 'Partial' : 'Unpaid',
                        style: TextStyle(
                          fontSize: 9.sp,
                          fontWeight: FontWeight.w600,
                          color: allPaid ? AppColors.success : anyPaid ? AppColors.warning : AppColors.error,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 32,
                  child: AppIcon(_expanded ? 'arrow-up-1' : 'arrow-down', color: AppColors.accent, size: 18),
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
              borderRadius: BorderRadius.circular(8.r),
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
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text('Semester', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 3, child: Text('Fee Type', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Due Date', textAlign: TextAlign.center, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                      SizedBox(width: 50.w, child: Center(child: Text('Status', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)))),
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
                  final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                  final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                  final paidAmt = pa - ((pa > 0 || d['paidstatus'] == 'P') ? fa : 0);
                  final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  final statusLabel = balance <= 0 ? 'Paid' : paidAmt > 0 ? 'Partial' : 'Due';
                  final statusColor = balance <= 0 ? AppColors.success : paidAmt > 0 ? AppColors.warning : AppColors.warning;
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 7),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                    ),
                    child: Row(
                      children: [
                        Expanded(flex: 2, child: Text(d['demfeeterm']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                        Expanded(flex: 3, child: Text(d['demfeetype']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp))),
                        Expanded(flex: 2, child: Text(_formatDueDate(d['duedate']), textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                        Expanded(flex: 2, child: Text(widget.formatCurrency((d['feeamount'] as num?)?.toDouble() ?? 0), textAlign: TextAlign.right, style: TextStyle(fontSize: 13.sp))),
                        Expanded(flex: 2, child: Text(widget.formatCurrency(paidAmt), textAlign: TextAlign.right, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.success))),
                        Expanded(flex: 2, child: Text(widget.formatCurrency(balance), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: balance > 0 ? AppColors.warning : AppColors.textSecondary))),
                        SizedBox(
                          width: 50,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: statusColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8.r),
                              ),
                              child: Text(
                                statusLabel,
                                style: TextStyle(fontSize: 9.sp, fontWeight: FontWeight.w600, color: statusColor),
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

