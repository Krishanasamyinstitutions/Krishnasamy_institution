import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

const _classOrder = ['PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];

int _classIndex(String c) {
  final idx = _classOrder.indexOf(c.toUpperCase());
  return idx >= 0 ? idx : _classOrder.length;
}

const _termOrder = [
  'I TERM', 'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER',
  'II TERM', 'NOVEMBER', 'DECEMBER', 'JANUARY', 'FEBRUARY',
  'III TERM', 'III term', 'MARCH', 'APRIL', 'April',
];

int _termIndex(String t) {
  final idx = _termOrder.indexWhere((x) => x.toLowerCase() == t.toLowerCase());
  return idx >= 0 ? idx : _termOrder.length;
}

class StudentFeeCollectionScreen extends StatefulWidget {
  final VoidCallback? onNavigateToTransactions;
  const StudentFeeCollectionScreen({super.key, this.onNavigateToTransactions});

  @override
  State<StudentFeeCollectionScreen> createState() =>
      _StudentFeeCollectionScreenState();
}

class _StudentFeeCollectionScreenState
    extends State<StudentFeeCollectionScreen> {
  final _admNoController = TextEditingController();
  final _nameController = TextEditingController();
  final _classController = TextEditingController();
  final _remarksController = TextEditingController();
  final _chequeNoController = TextEditingController();
  final _upiRefController = TextEditingController();
  final _chequeDateController = TextEditingController();
  final _bankNameController = TextEditingController();
  DateTime? _chequeDate;
  List<Map<String, dynamic>> _studentSuggestions = [];
  List<String> _courseList = [];
  String? _selectedCourse;
  List<String> _classList = [];
  List<String> _allClasses = [];
  Map<String, List<String>> _courseClassMap = {};
  String? _selectedClass;
  List<Map<String, dynamic>> _classSuggestions = [];


  bool _searching = false;
  String? _errorMsg;

  Map<String, dynamic>? _student;
  Map<String, dynamic>? _parent;

  List<Map<String, dynamic>> _allDemands = [];
  bool _loadingDemands = false;

  String? _selectedTerm; // null = All
  String _paymentMode = 'Cash';

  // Per-row controllers: keyed by dem_id
  final Map<String, TextEditingController> _fineCtrl = {};
  final Map<String, TextEditingController> _conCtrl = {};
  final Set<String> _selected = {};
  List<Map<String, dynamic>> _fineRules = [];

  @override
  void initState() {
    super.initState();
    _fetchClasses();
    _loadFineRules();
    _sweepOrphanedPayments();
  }

  /// Reconcile any 'I' (in-progress) online payments older than 15 minutes.
  /// For each one, ask Razorpay for the actual status:
  ///   - captured: call complete_payment_grouped so a paynumber is generated
  ///     and feedemand rows are updated (matching the live-polling path).
  ///   - anything else: mark 'F'.
  /// This prevents the case where polling was cut short but the student's
  /// money cleared — without this sweep the row sits at 'I' forever.
  Future<void> _sweepOrphanedPayments() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      final cutoff = DateTime.now().subtract(const Duration(minutes: 15)).toIso8601String();
      final orphans = await SupabaseService.fromSchema('payment')
          .select('pay_id, payorderid, payitems')
          .eq('ins_id', insId)
          .eq('paystatus', 'I')
          .lt('createdat', cutoff);
      for (final p in (orphans as List)) {
        final payId = p['pay_id'] as int;
        final orderId = p['payorderid']?.toString();
        String? paymentId;
        bool captured = false;
        if (orderId != null && orderId.isNotEmpty) {
          try {
            final resp = await SupabaseService.client.functions.invoke(
              'get-razorpay-payment', body: {'order_id': orderId},
            );
            final data = resp.data as Map<String, dynamic>;
            if (data['status'] == 'captured' && data['payment_id'] != null) {
              captured = true;
              paymentId = data['payment_id'].toString();
            }
          } catch (_) {}
        }
        if (captured) {
          // Decode stored items and run the normal completion path so the
          // row gets a paynumber and feedemand is updated.
          List<dynamic> items = [];
          final raw = p['payitems']?.toString();
          if (raw != null && raw.isNotEmpty) {
            try { items = jsonDecode(raw) as List<dynamic>; } catch (_) {}
          }
          try {
            await SupabaseService.client.rpc('complete_payment_grouped', params: {
              'p_pay_id': payId,
              'p_pay_method': 'razorpay',
              'p_pay_reference': 'Razorpay: $paymentId (recovered)',
              'p_items': items,
              'p_ins_id': insId,
              'p_status': 'C',
            });
          } catch (e) {
            debugPrint('Recovery complete failed for pay_id=$payId: $e');
          }
        } else {
          await SupabaseService.fromSchema('payment')
              .update({'paystatus': 'F'})
              .eq('pay_id', payId)
              .eq('ins_id', insId);
        }
      }
    } catch (e) {
      debugPrint('Orphaned payment sweep failed: $e');
    }
  }

  Future<void> _loadFineRules() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    debugPrint('FINE: Loading fine rules for insId=$insId, schema=${SupabaseService.currentSchema}');
    if (insId == null) return;
    try {
      final result = await SupabaseService.fromSchema('finerule')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('from_days');
      _fineRules = List<Map<String, dynamic>>.from(result);
      debugPrint('FINE: Loaded ${_fineRules.length} rules: $_fineRules');
    } catch (e) {
      debugPrint('FINE: Error loading fine rules: $e');
    }
  }

  double _calculateFine(Map<String, dynamic> demand) {
    if (_fineRules.isEmpty) return 0;
    final dueDateStr = demand['duedate']?.toString();
    if (dueDateStr == null || dueDateStr.isEmpty) return 0;

    DateTime dueDate;
    try { dueDate = DateTime.parse(dueDateStr); } catch (_) { return 0; }

    final today = DateTime.now();
    if (!today.isAfter(dueDate)) return 0; // Not overdue

    final overdueDays = today.difference(dueDate).inDays;
    final feeType = demand['demfeetype']?.toString() ?? '';
    final feeAmount = (demand['feeamount'] as num?)?.toDouble() ?? 0;

    // Find matching rule (fee-type specific first, then ALL)
    Map<String, dynamic>? matchedRule;
    for (final rule in _fineRules) {
      final ruleType = rule['feetype']?.toString() ?? 'ALL';
      final fromDays = (rule['from_days'] as num?)?.toInt() ?? 0;
      final toDays = rule['to_days'] as num?;

      final daysMatch = overdueDays >= fromDays && (toDays == null || overdueDays <= toDays.toInt());
      if (!daysMatch) continue;

      if (ruleType == feeType) { matchedRule = rule; break; } // Exact match
      if (ruleType == 'ALL' && matchedRule == null) matchedRule = rule; // ALL fallback
    }

    if (matchedRule == null) return 0;

    final fineType = matchedRule['fine_type']?.toString() ?? 'FIXED';
    final fineValue = (matchedRule['fine_value'] as num?)?.toDouble() ?? 0;

    if (fineType == 'PERCENT') return (feeAmount * fineValue / 100);
    return fineValue;
  }

  Future<void> _fetchClasses() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    // Get courses and classes from feedemand table
    try {
      final demands = await SupabaseService.getFeeDemands(insId);
      final courseSet = <String>{};
      final mapping = <String, Set<String>>{};
      for (final d in demands) {
        final course = d['courname']?.toString() ?? '';
        final cls = d['stuclass']?.toString() ?? '';
        if (course.isNotEmpty) courseSet.add(course);
        if (course.isNotEmpty && cls.isNotEmpty) {
          mapping.putIfAbsent(course, () => <String>{}).add(cls);
        }
      }
      final allClasses = mapping.values.expand((s) => s).toSet().toList();
      allClasses.sort((a, b) => _classIndex(a).compareTo(_classIndex(b)));
      final courseClassMap = <String, List<String>>{ for (final e in mapping.entries) e.key: e.value.toList()..sort((a, b) => _classIndex(a).compareTo(_classIndex(b))) };
      final courseList = courseSet.toList()..sort();
      if (mounted) setState(() {
        _courseList = courseList;
        _courseClassMap = courseClassMap;
        _allClasses = allClasses;
        _classList = allClasses;
      });
    } catch (e) { debugPrint('Error loading course-class from feedemand: $e'); }
  }

  Future<void> _searchByClass(String className) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      var query = SupabaseService.fromSchema('students')
          .select('stu_id, stuname, stuadmno, stuclass, courname')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .eq('stuclass', className);
      if (_selectedCourse != null) {
        query = query.eq('courname', _selectedCourse!);
      }
      final rows = await query.order('stuname', ascending: true);
      setState(() => _classSuggestions = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  @override
  void dispose() {
    // If the cashier is leaving without a completed payment, reset fineamount
    // to 0 on every unpaid demand currently loaded. Fine should only persist
    // on the DB after a successful payment, not just because a cashier viewed
    // the student.
    _resetFinesOnExit();
    _admNoController.dispose();
    _nameController.dispose();
    _classController.dispose();
    _remarksController.dispose();
    _chequeNoController.dispose();
    _upiRefController.dispose();
    _chequeDateController.dispose();
    _bankNameController.dispose();
    for (final c in _fineCtrl.values) c.dispose();
    for (final c in _conCtrl.values) c.dispose();
    super.dispose();
  }

  void _resetFinesOnExit() {
    if (_allDemands.isEmpty) return;
    final insId = context.read<AuthProvider>().insId;
    if (insId == null) return;
    // Fire-and-forget — dispose can't await.
    for (final d in _allDemands) {
      final demId = d['dem_id'];
      final paidStatus = d['paidstatus']?.toString() ?? 'U';
      if (demId == null) continue;
      if (paidStatus == 'P') continue; // don't wipe historical paid fines
      SupabaseService.fromSchema('feedemand')
          .update({'fineamount': 0})
          .eq('dem_id', demId)
          .eq('ins_id', insId)
          .then((_) {}, onError: (e) => debugPrint('Fine reset on exit failed for dem_id=$demId: $e'));
    }
  }

  void _clear() {
    for (final c in _fineCtrl.values) c.dispose();
    for (final c in _conCtrl.values) c.dispose();
    _fineCtrl.clear();
    _conCtrl.clear();
    setState(() {
      _admNoController.clear();
      _nameController.clear();
      _classController.clear();
      _remarksController.clear();
      _studentSuggestions = [];
      _classSuggestions = [];
      _selectedClass = null;
      _student = null;
      _parent = null;
      _allDemands = [];
      _errorMsg = null;
      _selectedTerm = null;
      _selected.clear();
      _paymentMode = 'Cash';
      _chequeNoController.clear();
      _chequeDateController.clear();
      _bankNameController.clear();
      _upiRefController.clear();
      _chequeDate = null;
    });
  }

  Future<void> _searchByName(String name) async {
    if (name.trim().length < 2) {
      setState(() => _studentSuggestions = []);
      return;
    }
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      final rows = await SupabaseService.fromSchema('students')
          .select('stu_id, stuname, stuadmno, stuclass')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .ilike('stuname', '%${name.trim()}%')
          .limit(10);
      setState(() => _studentSuggestions = List<Map<String, dynamic>>.from(rows));
    } catch (_) {}
  }

  void _selectSuggestion(Map<String, dynamic> student) {
    _admNoController.text = student['stuadmno']?.toString() ?? '';
    _nameController.text = student['stuname']?.toString() ?? '';
    _classController.text = student['stuclass']?.toString() ?? '';
    setState(() {
      _studentSuggestions = [];
      _classSuggestions = [];
    });
    _search();
  }

  Future<void> _search() async {
    final admNo = _admNoController.text.trim();
    if (admNo.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    // Dispose old controllers
    for (final c in _fineCtrl.values) c.dispose();
    for (final c in _conCtrl.values) c.dispose();
    _fineCtrl.clear();
    _conCtrl.clear();

    setState(() {
      _searching = true;
      _errorMsg = null;
      _student = null;
      _parent = null;
      _allDemands = [];
      _selected.clear();
      _selectedTerm = null;
    });

    try {
      final studentRows = await SupabaseService.fromSchema('students')
          .select('stu_id, stuname, stuadmno, stuclass, stugender, stumobile, stuphoto, courname')
          .eq('ins_id', insId)
          .eq('stuadmno', admNo)
          .eq('activestatus', 1)
          .limit(1);

      if ((studentRows as List).isEmpty) {
        setState(() {
          _errorMsg = 'No student found with roll no "$admNo"';
          _searching = false;
        });
        return;
      }

      final student = Map<String, dynamic>.from(studentRows.first as Map);
      final stuId = student['stu_id'] as int;

      _nameController.text = student['stuname']?.toString() ?? '';
      _classController.text = student['stuclass']?.toString() ?? '';
      final stuClass = student['stuclass']?.toString();
      final stuCourse = student['courname']?.toString();

      setState(() {
        _student = student;
        _searching = false;
        _loadingDemands = true;
        _studentSuggestions = [];
        if (stuCourse != null && stuCourse.isNotEmpty && _courseList.contains(stuCourse)) {
          _selectedCourse = stuCourse;
          if (_courseClassMap.containsKey(stuCourse)) {
            _classList = List<String>.from(_courseClassMap[stuCourse]!)
              ..sort((a, b) => _classIndex(a).compareTo(_classIndex(b)));
          }
        }
        if (stuClass != null && _classList.contains(stuClass)) {
          _selectedClass = stuClass;
        }
      });

      // Fine is NOT persisted to feedemand.fineamount at search time — it is
      // only written after a successful payment (see _processPayment). The
      // cashier sees the calculated fine via _calculateFine below; if they
      // abandon without paying, the DB column stays empty.

      // Fetch parent and demands in parallel
      final parentFuture = SupabaseService.getStudentParent(stuId, stuadmno: admNo);
      final demandsFuture = SupabaseService.fromSchema('feedemand')
          .select(
              'dem_id, demno, yr_id, demfeeyear, demfeetype, demfeeterm, feeamount, conamount, balancedue, paidamount, fineamount, duedate, paidstatus, stuclass')
          .eq('ins_id', insId)
          .eq('stuadmno', admNo)
          .eq('paidstatus', 'U')
          .gt('balancedue', 0)
          .order('duedate', ascending: true);

      final parent = await parentFuture;
      final demandList =
          List<Map<String, dynamic>>.from((await demandsFuture) as List);

      // Sort by due date (oldest first) so cashiers collect overdue fees first.
      demandList.sort((a, b) {
        final da = a['duedate']?.toString() ?? '';
        final db = b['duedate']?.toString() ?? '';
        if (da.isEmpty && db.isEmpty) return 0;
        if (da.isEmpty) return 1;
        if (db.isEmpty) return -1;
        return da.compareTo(db);
      });

      _allDemands = demandList;

      // Per-row controllers: prefer the server-computed fineamount column;
      // fall back to client-side rule calculation if server hasn't populated it.
      for (final d in demandList) {
        final key = d['dem_id']?.toString() ?? '';
        if (key.isNotEmpty) {
          final serverFine = (d['fineamount'] as num?)?.toDouble() ?? 0;
          final fine = serverFine > 0 ? serverFine : _calculateFine(d);
          _fineCtrl[key] = TextEditingController(text: fine > 0 ? fine.toStringAsFixed(0) : '');
          _conCtrl[key] = TextEditingController();
        }
      }

      setState(() {
        _parent = parent;
        _loadingDemands = false;
      });
    } catch (e) {
      setState(() {
        _errorMsg = 'Error: $e';
        _searching = false;
        _loadingDemands = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredDemands {
    if (_selectedTerm == null) return _allDemands;
    return _allDemands.where((d) =>
        (d['demfeeterm']?.toString() ?? '') == _selectedTerm).toList();
  }

  List<String> get _terms {
    final seen = <String>[];
    for (final d in _allDemands) {
      final t = d['demfeeterm']?.toString() ?? '';
      if (t.isNotEmpty && !seen.contains(t)) seen.add(t);
    }
    return seen;
  }

  String _demKey(Map<String, dynamic> d) =>
      d['dem_id']?.toString() ?? '';

  double _fine(String key) =>
      double.tryParse(_fineCtrl[key]?.text ?? '') ?? 0;

  double _con(String key) =>
      double.tryParse(_conCtrl[key]?.text ?? '') ?? 0;

  double _netAmt(Map<String, dynamic> d) {
    final key = _demKey(d);
    final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
    final fine = _fine(key);
    return bal + fine;
  }

  double _payableAmt(Map<String, dynamic> d) {
    final key = _demKey(d);
    final col = _con(key);
    final fine = _fine(key);
    if (col > 0) return col + fine;
    final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
    return bal + fine;
  }

  double get _totalNetSelected {
    return _selected.fold(0.0, (sum, key) {
      final d = _allDemands.firstWhere(
          (x) => _demKey(x) == key,
          orElse: () => {});
      if (d.isEmpty) return sum;
      return sum + _payableAmt(d);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header card
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.payments_rounded, color: AppColors.accent, size: 22.sp),
              SizedBox(width: 10.w),
              Text('Fee Collection',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      )),
              const Spacer(),
              TextButton.icon(
                onPressed: _clear,
                icon: Icon(Icons.refresh_rounded, size: 16.sp),
                label: const Text('Clear'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  textStyle: TextStyle(
                      fontSize: 13.sp, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10.h),

        // Body
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Top: Student Lookup (horizontal) ──
              Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12.r),
                  border: Border.all(color: AppColors.border),
                ),
                padding: EdgeInsets.all(12.w),
                child: _buildStudentLookupContent(),
              ),
              SizedBox(height: 12.h),
              if (_student != null) ...[
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: AppColors.border),
                  ),
                  padding: EdgeInsets.all(12.w),
                  child: _buildStudentCardContent(),
                ),
                SizedBox(height: 12.h),
              ],
              // ── Demands ──
              Expanded(child: _buildDemandsPanel()),
            ],
          ),
        ),
      ],
    );
  }

  // ── Student Lookup ──
  Widget _buildStudentLookupContent() {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Student Lookup',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
          SizedBox(height: 12.h),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _admNoController,
                        onSubmitted: (_) => _search(),
                        decoration: _inputDec('Roll No'),
                        style: TextStyle(fontSize: 13.sp),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    SizedBox(
                      height: 42.h,
                      width: 42.w,
                      child: ElevatedButton(
                        onPressed: _searching ? null : _search,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accent,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.r)),
                          padding: EdgeInsets.zero,
                        ),
                        child: _searching
                            ? SizedBox(
                                width: 18.w,
                                height: 18.h,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : Icon(Icons.search_rounded, size: 20.sp),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: TextField(
                  controller: _nameController,
                  decoration: _inputDec('Student Name'),
                  style: TextStyle(fontSize: 13.sp),
                  onChanged: _searchByName,
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedCourse,
                  decoration: _inputDec('Course'),
                  style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                  isExpanded: true,
                  items: _courseList.map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontSize: 13.sp)))).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedCourse = val;
                      _selectedClass = null;
                      _classSuggestions = [];
                      if (val != null && _courseClassMap.containsKey(val)) {
                        _classList = List<String>.from(_courseClassMap[val]!);
                      } else if (val != null) {
                        _classList = List<String>.from(_allClasses);
                      } else {
                        _classList = List<String>.from(_allClasses);
                      }
                      _classList.sort((a, b) => _classIndex(a).compareTo(_classIndex(b)));
                      if (val != null && val.startsWith('M') && _classList.length > 2) {
                        _classList = _classList.sublist(0, 2);
                      }
                    });
                  },
                ),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(_selectedCourse),
                  value: _selectedClass,
                  decoration: _inputDec('Class'),
                  style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                  isExpanded: true,
                  items: _classList.map((c) {
                    final label = _selectedCourse != null && c.contains('-')
                        ? '${c.split('-').first} Year'
                        : c;
                    return DropdownMenuItem(value: c, child: Text(label, style: TextStyle(fontSize: 13.sp)));
                  }).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedClass = val;
                      _classController.text = val ?? '';
                      _classSuggestions = [];
                    });
                    if (val != null) _searchByClass(val);
                  },
                ),
              ),
            ],
          ),
          if (_studentSuggestions.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 4.h),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: AppColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _studentSuggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = _studentSuggestions[i];
                  return ListTile(
                    dense: true,
                    title: Text(s['stuname']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                    subtitle: Text('Roll: ${s['stuadmno']} • ${s['courname'] ?? ''} ${s['stuclass']}', style: TextStyle(fontSize: 13.sp)),
                    onTap: () => _selectSuggestion(s),
                  );
                },
              ),
            ),
          if (_classSuggestions.isNotEmpty)
            Container(
              margin: EdgeInsets.only(top: 4.h),
              constraints: const BoxConstraints(maxHeight: 220),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: AppColors.border),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 8, offset: const Offset(0, 2))],
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _classSuggestions.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final s = _classSuggestions[i];
                  return ListTile(
                    dense: true,
                    title: Text(s['stuname']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                    subtitle: Text('Roll: ${s['stuadmno']} • ${s['courname'] ?? ''} ${s['stuclass']}', style: TextStyle(fontSize: 13.sp)),
                    onTap: () => _selectSuggestion(s),
                  );
                },
              ),
            ),
          if (_errorMsg != null) ...[
            SizedBox(height: 10.h),
            Container(
              padding: EdgeInsets.all(10.w),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(_errorMsg!,
                  style: TextStyle(
                      fontSize: 13.sp, color: AppColors.error)),
            ),
          ],
        ],
      );
  }

  // ── Student Card ──
  Widget _buildStudentCardContent() {
    final name = _student!['stuname']?.toString() ?? '-';
    final admNo = _student!['stuadmno']?.toString() ?? '-';
    final className = _student!['stuclass']?.toString() ?? '-';
    final fatherName = _parent?['fathername']?.toString() ?? '-';
    final courseName = _student!['courname']?.toString() ?? '-';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CircleAvatar(
          radius: 22,
          backgroundColor: AppColors.accent.withValues(alpha: 0.12),
          child: Text(
            name.isNotEmpty ? name[0].toUpperCase() : '?',
            style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w700,
                fontSize: 18.sp),
          ),
        ),
        SizedBox(width: 12.w),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: TextStyle(
                      fontSize: 14.sp,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary),
                  overflow: TextOverflow.ellipsis),
              SizedBox(height: 2.h),
              Text('Roll No: $admNo',
                  style: TextStyle(
                      fontSize: 13.sp, color: AppColors.textSecondary)),
            ],
          ),
        ),
        SizedBox(width: 16.w),
        Container(width: 1, height: 36.h, color: AppColors.border),
        SizedBox(width: 16.w),
        Expanded(child: _detailRow(Icons.person_outline_rounded, 'Father', fatherName)),
        SizedBox(width: 16.w),
        Expanded(child: _detailRow(Icons.menu_book_outlined, 'Course', courseName)),
        SizedBox(width: 16.w),
        Expanded(child: _detailRow(Icons.school_outlined, 'Class', className)),
      ],
    );
  }

  // ── Term Filter ──
  Widget _buildTermFilterContent() {
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filter by Term',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
          SizedBox(height: 10.h),
          DropdownButtonFormField<String?>(
            value: _selectedTerm,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: BorderSide(color: AppColors.border)),
            ),
            items: [
              DropdownMenuItem<String?>(value: null, child: Text('All', style: TextStyle(fontSize: 13.sp))),
              ..._terms.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t, style: TextStyle(fontSize: 13.sp)))),
            ],
            onChanged: (v) => setState(() => _selectedTerm = v),
          ),
        ],
      );
  }


  // ── Demands Panel ──
  Widget _buildDemandsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Panel header
          Container(
            padding:
                EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
            decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Pending Fee Demands',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        )),
                if (_allDemands.isNotEmpty) ...[
                  SizedBox(width: 8.w),
                  Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 8.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12.r),
                    ),
                    child: Text(
                      '${_filteredDemands.length} of ${_allDemands.length} items',
                      style: TextStyle(
                          fontSize: 13.sp,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
                const Spacer(),
                if (_student != null && _terms.isNotEmpty) ...[
                  Text('Semester:', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                  SizedBox(width: 8.w),
                  SizedBox(
                    width: 180.w,
                    height: 38.h,
                    child: DropdownButtonFormField<String?>(
                      value: _selectedTerm,
                      isExpanded: true,
                      decoration: InputDecoration(
                        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: BorderSide(color: AppColors.border)),
                        isDense: true,
                      ),
                      items: [
                        DropdownMenuItem<String?>(value: null, child: Text('All', style: TextStyle(fontSize: 13.sp))),
                        ..._terms.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t, style: TextStyle(fontSize: 12.sp), overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: (v) => setState(() => _selectedTerm = v),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // Content
          Expanded(child: _buildDemandsContent()),
        ],
      ),
    );
  }

  Widget _buildDemandsContent() {
    if (_loadingDemands) {
      return const Center(
          child: CircularProgressIndicator(color: AppColors.accent));
    }

    if (_student == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_rounded,
                size: 52.sp, color: Colors.grey.shade300),
            SizedBox(height: 12.h),
            Text('Search a student to view pending fees',
                style: TextStyle(
                    fontSize: 13.sp, color: Colors.grey.shade400)),
          ],
        ),
      );
    }

    if (_filteredDemands.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 52.sp, color: Colors.green.shade300),
            SizedBox(height: 12.h),
            Text('No pending fee demands',
                style:
                    TextStyle(fontSize: 13.sp, color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    final demands = _filteredDemands;
    final allSelected = demands.isNotEmpty &&
        demands.every((d) => _selected.contains(_demKey(d)));

    return Column(
      children: [
        // Table header (dark)
        Container(
          color: const Color(0xFF6C8EEF),
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          child: Row(
            children: [
              SizedBox(
                width: 32.w,
                child: Checkbox(
                  value: allSelected,
                  onChanged: (v) {
                    setState(() {
                      if (v == true) {
                        for (final d in demands) {
                          _selected.add(_demKey(d));
                        }
                      } else {
                        for (final d in demands) {
                          _selected.remove(_demKey(d));
                        }
                      }
                    });
                  },
                  fillColor: WidgetStateProperty.resolveWith((s) =>
                      s.contains(WidgetState.selected)
                          ? AppColors.accent
                          : Colors.white24),
                  side: const BorderSide(color: Colors.white38),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
              ),
              const _THCell('Semester', flex: 2),
              const _THCell('Fee Type', flex: 3),
              const _THCell('Due Date', flex: 3),
              const _THCell('Fee Amt', flex: 2, textAlign: TextAlign.right),
              const _THCell('Bal. Amt', flex: 2, textAlign: TextAlign.right),
              const _THCell('Col Amount', flex: 2, textAlign: TextAlign.center),
              const _THCell('Fine', flex: 2, textAlign: TextAlign.center),
              const _THCell('Net Amt', flex: 1, textAlign: TextAlign.right),
            ],
          ),
        ),

        // Rows
        Expanded(
          child: ListView.separated(
            itemCount: demands.length,
            separatorBuilder: (_, __) =>
                const Divider(height: 1, color: Color(0xFFEEEEEE)),
            itemBuilder: (context, i) {
              final d = demands[i];
              final key = _demKey(d);
              final isSelected = _selected.contains(key);
              final feeAmt =
                  (d['feeamount'] as num?)?.toDouble() ?? 0;
              final bal =
                  (d['balancedue'] as num?)?.toDouble() ?? 0;
              final dueDate = d['duedate']?.toString() ?? '-';
              final shortDate = dueDate.length >= 10
                  ? _formatDate(dueDate.substring(0, 10))
                  : dueDate;
              final netAmt = _netAmt(d);

              return Container(
                color: isSelected
                    ? AppColors.accent.withValues(alpha: 0.04)
                    : null,
                padding: EdgeInsets.symmetric(
                    horizontal: 12.w, vertical: 10.h),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32.w,
                      child: Checkbox(
                        value: isSelected,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(key);
                            } else {
                              _selected.remove(key);
                            }
                          });
                        },
                        fillColor: WidgetStateProperty.resolveWith((s) =>
                            s.contains(WidgetState.selected)
                                ? AppColors.accent
                                : null),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                    _TDCell(d['demfeeterm']?.toString() ?? '-',
                        flex: 2,
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    _TDCell(d['demfeetype']?.toString() ?? '-',
                        flex: 3,
                        style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColors.textSecondary)),
                    _TDCell(shortDate,
                        flex: 3,
                        style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColors.textSecondary)),
                    _TDCell(feeAmt.toStringAsFixed(2),
                        flex: 2,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 13.sp,
                            color: AppColors.textPrimary)),
                    _TDCell(bal.toStringAsFixed(2),
                        flex: 2,
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFFE87722))),
                    // Col Amount editable — clamp to balance due
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        child: _numField(_conCtrl[key], () {
                          final ctrl = _conCtrl[key];
                          if (ctrl != null) {
                            final entered = double.tryParse(ctrl.text) ?? 0;
                            if (entered > bal) {
                              final clamped = bal.toStringAsFixed(0);
                              ctrl.value = TextEditingValue(
                                text: clamped,
                                selection: TextSelection.collapsed(offset: clamped.length),
                              );
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Collection amount cannot exceed balance due (₹${bal.toStringAsFixed(0)})'),
                                    backgroundColor: Colors.red,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            }
                          }
                          setState(() {});
                        }),
                      ),
                    ),
                    // Fine editable
                    Expanded(
                      flex: 2,
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 4.w),
                        child: _numField(_fineCtrl[key], () => setState(() {})),
                      ),
                    ),
                    // Net Amt
                    Expanded(
                      flex: 1,
                      child: Text(
                        netAmt.toStringAsFixed(2),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w600,
                            color: netAmt > 0
                                ? AppColors.error
                                : AppColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        // Footer
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AppColors.border)),
            borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(12.r),
                bottomRight: Radius.circular(12.r)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_outline_rounded, size: 16.sp, color: AppColors.accent),
              SizedBox(width: 6.w),
              Text(
                '${_selected.length} of ${demands.length} selected',
                style: TextStyle(
                    fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary),
              ),
              const Spacer(),
              Container(
                padding: EdgeInsets.symmetric(
                    horizontal: 14.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8.r),
                  border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    Text('Net Amount: ',
                        style: TextStyle(
                            fontSize: 13.sp,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    Text(
                      'Rs.${_totalNetSelected.toStringAsFixed(2)}',
                      style: TextStyle(
                          fontSize: 13.sp,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent),
                    ),
                  ],
                ),
              ),
              SizedBox(width: 12.w),
              ElevatedButton.icon(
                onPressed:
                    _selected.isEmpty ? null : _onCollectAndReceipt,
                icon: Icon(Icons.payment_rounded, size: 16.sp),
                label: const Text('Proceed to Pay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  disabledForegroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10.r)),
                  padding: EdgeInsets.symmetric(
                      horizontal: 24.w, vertical: 16.h),
                  textStyle: TextStyle(
                      fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  bool _processing = false;

  Future<void> _onCollectAndReceipt() async {
    // Check if sequences exist for all fee groups in selected demands
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId != null) {
      try {
        final sequences = await SupabaseService.fromSchema('sequence')
            .select('fg_id')
            .eq('ins_id', insId);
        final seqFgIds = (sequences as List).map((s) => s['fg_id']).toSet();

        // Get fee groups for selected demands
        for (final key in _selected) {
          final d = _allDemands.firstWhere((x) => _demKey(x) == key, orElse: () => {});
          if (d.isEmpty) continue;
          final demfeetype = d['demfeetype']?.toString() ?? '';
          final ftResult = await SupabaseService.fromSchema('feetype')
              .select('fg_id')
              .eq('feedesc', demfeetype)
              .eq('activestatus', 1)
              .limit(1)
              .maybeSingle();
          final fgId = ftResult?['fg_id'];
          if (fgId != null && !seqFgIds.contains(fgId)) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Please create payment sequence for all fee groups first (Settings > Sequence Creation)'),
                  backgroundColor: Colors.red,
                  duration: const Duration(seconds: 4),
                ),
              );
            }
            return;
          }
        }
      } catch (_) {}
    }

    final totalNet = _totalNetSelected;
    _paymentMode = 'Cash';
    _chequeNoController.clear();
    _chequeDateController.clear();
    _bankNameController.clear();
    _upiRefController.clear();
    _chequeDate = null;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.32),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => Dialog(
          elevation: 0,
          backgroundColor: Colors.transparent,
          insetPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 470.w),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 22.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20.r),
                border: Border.all(
                  color: Colors.grey.withValues(alpha: 0.1),
                  width: 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.08),
                    blurRadius: 60,
                    spreadRadius: 4,
                    offset: const Offset(0, 24),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    blurRadius: 16,
                    spreadRadius: 0,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Proceed to Pay',
                          style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700),
                        ),
                        GestureDetector(
                          onTap: () => Navigator.of(context).pop(),
                          child: Icon(Icons.close, size: 22.sp, color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                    SizedBox(height: 14.h),
                    Text(
                      'Student: ${_student!['stuname']} (${_student!['stuadmno']})',
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                    ),
                    SizedBox(height: 6.h),
                    Text(
                      'Demands selected: ${_selected.length}',
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                    ),
                    SizedBox(height: 12.h),
                    Text(
                      'Total: Rs.${totalNet.toStringAsFixed(2)}',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16.sp,
                        color: AppColors.accent,
                      ),
                    ),
                    SizedBox(height: 18.h),
                    Divider(color: AppColors.border, height: 1),
                    SizedBox(height: 18.h),
                    Text(
                      'Payment Mode *',
                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: 12.h),
                    Wrap(
                      spacing: 10.w,
                      runSpacing: 10.h,
                      children: ['Cash', 'QR/UPI', 'Online', 'Cheque']
                          .map(
                            (mode) => _buildPaymentModeChip(
                              mode: mode,
                              selected: _paymentMode == mode,
                              onTap: () => setDialogState(
                                () => setState(() => _paymentMode = mode),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    if (_paymentMode == 'QR/UPI') ...[
                      SizedBox(height: 18.h),
                      Container(
                        padding: EdgeInsets.all(12.w),
                        decoration: BoxDecoration(
                          color: AppColors.info.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(12.r),
                          border: Border.all(
                            color: AppColors.info.withValues(alpha: 0.16),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              size: 16.sp,
                              color: AppColors.info,
                            ),
                            SizedBox(width: 8.w),
                            Expanded(
                              child: Text(
                                'Enter the UPI Transaction ID shared by the student',
                                style: TextStyle(fontSize: 11.sp, color: AppColors.info),
                              ),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(height: 14.h),
                      _buildDialogInput(
                        label: 'UPI Transaction ID *',
                        child: TextField(
                          controller: _upiRefController,
                          decoration: InputDecoration(
                            hintText: 'e.g. 412345678901',
                            prefixIcon: Icon(Icons.receipt_long_rounded, size: 18.sp),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 12.h,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            isDense: true,
                          ),
                          style: TextStyle(fontSize: 13.sp),
                        ),
                      ),
                    ],
                    if (_paymentMode == 'Cheque') ...[
                      SizedBox(height: 18.h),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: _buildDialogInput(
                              label: 'Cheque No *',
                              child: TextField(
                                controller: _chequeNoController,
                                decoration: InputDecoration(
                                  hintText: 'Enter cheque number',
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12.w,
                                    vertical: 12.h,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  isDense: true,
                                ),
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            child: _buildDialogInput(
                              label: 'Cheque Date *',
                              child: TextField(
                                controller: _chequeDateController,
                                readOnly: true,
                                onTap: () async {
                                  final picked = await showDatePicker(
                                    context: ctx,
                                    initialDate: DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2030),
                                  );
                                  if (picked != null) {
                                    _chequeDate = picked;
                                    _chequeDateController.text =
                                        '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                                    setDialogState(() {});
                                  }
                                },
                                decoration: InputDecoration(
                                  hintText: 'DD/MM/YYYY',
                                  suffixIcon: Icon(Icons.calendar_today, size: 16.sp),
                                  contentPadding: EdgeInsets.symmetric(
                                    horizontal: 12.w,
                                    vertical: 12.h,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12.r),
                                  ),
                                  isDense: true,
                                ),
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 14.h),
                      _buildDialogInput(
                        label: 'Bank Name *',
                        child: TextField(
                          controller: _bankNameController,
                          decoration: InputDecoration(
                            hintText: 'Enter bank name',
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12.w,
                              vertical: 12.h,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            isDense: true,
                          ),
                          style: TextStyle(fontSize: 13.sp),
                        ),
                      ),
                    ],
                    SizedBox(height: 22.h),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            // Reset fineamount to 0 on all selected demands
                            // so no stale fine stays in the DB.
                            final auth = context.read<AuthProvider>();
                            final insId = auth.insId;
                            if (insId == null) return;
                            for (final key in _selected) {
                              final d = _allDemands.firstWhere((x) => _demKey(x) == key, orElse: () => {});
                              final demId = d['dem_id'];
                              if (demId == null) continue;
                              try {
                                await SupabaseService.fromSchema('feedemand')
                                    .update({'fineamount': 0})
                                    .eq('dem_id', demId)
                                    .eq('ins_id', insId);
                              } catch (e) {
                                debugPrint('Fine reset error for dem_id=$demId: $e');
                              }
                            }
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.error,
                            backgroundColor: const Color(0xFFF3F6FD),
                            side: const BorderSide(color: AppColors.border),
                            padding: EdgeInsets.symmetric(
                              horizontal: 18.w,
                              vertical: 12.h,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: Text('Cancel', style: TextStyle(fontSize: 14.sp)),
                        ),
                        SizedBox(width: 10.w),
                        ElevatedButton(
                          onPressed: () {
                            if (_paymentMode == 'QR/UPI') {
                              if (_upiRefController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text('Please enter UPI Transaction ID'),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                            }
                            if (_paymentMode == 'Cheque') {
                              if (_chequeNoController.text.trim().isEmpty ||
                                  _chequeDateController.text.trim().isEmpty ||
                                  _bankNameController.text.trim().isEmpty) {
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Please fill Cheque No, Cheque Date and Bank Name',
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }
                            }
                            Navigator.pop(ctx);
                            _processPayment();
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            padding: EdgeInsets.symmetric(
                              horizontal: 26.w,
                              vertical: 14.h,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                          ),
                          child: Text(
                            'Confirm Payment',
                            style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentModeChip({
    required String mode,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16.r),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.symmetric(horizontal: 18.w, vertical: 11.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : const Color(0xFFF3F6FD),
          borderRadius: BorderRadius.circular(16.r),
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
          ),
        ),
        child: Text(
          mode,
          style: TextStyle(
            fontSize: 13.sp,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildDialogInput({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
        ),
        SizedBox(height: 6.h),
        child,
      ],
    );
  }

  Future<void> _processPayment() async {
    if (_processing || _student == null) return;
    if (_paymentMode == 'Online') {
      await _processOnlinePayment();
    } else {
      await _processDirectPayment();
    }
  }

  // ── Show success dialog ──
  void _showSuccessDialog(String payNumber, double totalNet, {int? payId}) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56.sp),
            SizedBox(height: 12.h),
            Text('Payment Successful', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 8.h),
            Text('Receipt No: $payNumber', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
            Text('Amount: Rs.${totalNet.toStringAsFixed(2)}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
            Text('Mode: $_paymentMode', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
            SizedBox(height: 16.h),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _clear();
                if (payId != null) _downloadReceipt(payId, payNumber);
              },
              icon: Icon(Icons.download_rounded, size: 16.sp),
              label: const Text('Download Receipt'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.accent,
                side: const BorderSide(color: AppColors.accent),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _clear();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  void _downloadReceipt(int payId, String payNumber) {
    widget.onNavigateToTransactions?.call();
  }

  // ── Direct payment (Cash / Bank / Cheque) using atomic RPCs ──
  Future<void> _processDirectPayment() async {
    setState(() => _processing = true);

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final inscode = auth.currentUser?.inscode ?? '';
    final createdBy = auth.currentUser?.usename ?? '';
    final stuId = _student!['stu_id'] as int;
    final totalNet = _totalNetSelected;

    // Declared outside try so the catch block can reset fineamount on failure.
    final items = <Map<String, dynamic>>[];

    try {
      final firstDemand = _allDemands.firstWhere((d) => _selected.contains(_demKey(d)));
      final yrId = firstDemand['yr_id'] as int?;
      final yrlabel = firstDemand['demfeeyear']?.toString() ?? '';

      // Build items list with fee type info
      for (final key in _selected) {
        final d = _allDemands.firstWhere((x) => _demKey(x) == key, orElse: () => {});
        if (d.isEmpty) continue;
        final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
        final fine = _fine(key);
        final col = _con(key);
        final net = (col > 0 ? col : bal) + fine; // Total including fine
        items.add({
          'dem_id': d['dem_id'] as int,
          'yr_id': d['yr_id'],
          'yrlabel': d['demfeeyear']?.toString() ?? '',
          'ins_id': insId,
          'amount': net,
          'fine': fine,
          'demfeetype': d['demfeetype']?.toString() ?? '',
        });
      }

      // Build payment reference
      String payReference = '$_paymentMode collection by $createdBy';
      String payMethod = _paymentMode.toLowerCase();

      if (_paymentMode == 'QR/UPI') {
        final upiRef = _upiRefController.text.trim();
        payReference = 'UPI Txn: $upiRef by $createdBy';
        payMethod = 'qr_upi';
      } else if (_paymentMode == 'Cheque') {
        final chequeNo = _chequeNoController.text.trim();
        final bankName = _bankNameController.text.trim();
        payReference = 'Cheque $chequeNo ($bankName) by $createdBy';
        payMethod = 'cheque';
      }

      // Call grouped payment RPC — creates one payment per fee group
      // totalNet includes fine — paidamount will include fine (old approach)
      final result = await SupabaseService.client.rpc('process_grouped_payment', params: {
        'p_ins_id': insId,
        'p_inscode': inscode,
        'p_stu_id': stuId,
        'p_yr_id': yrId,
        'p_yrlabel': yrlabel,
        'p_total_amount': totalNet,
        'p_created_by': createdBy,
        'p_pay_method': payMethod,
        'p_pay_reference': payReference,
        'p_items': items,
      });

      // Result is JSON array of receipt numbers
      final receipts = result is List ? result : (result is String ? [result] : []);
      final receiptStr = receipts.map((r) => r is Map ? r['paynumber'] ?? r.toString() : r.toString()).join(', ');

      // Update cheque details if applicable
      if (_paymentMode == 'Cheque' && receipts.isNotEmpty) {
        for (final r in receipts) {
          final payId = r is Map ? r['pay_id'] : null;
          if (payId != null) {
            await SupabaseService.fromSchema('payment').update({
              'paychequeno': _chequeNoController.text.trim(),
              'paychequedate': _chequeDate != null
                  ? '${_chequeDate!.year}-${_chequeDate!.month.toString().padLeft(2, '0')}-${_chequeDate!.day.toString().padLeft(2, '0')}'
                  : null,
              'paybankname': _bankNameController.text.trim(),
            }).eq('pay_id', payId).eq('ins_id', insId!);
          }
        }
      }

      // Update fineamount column on each paid demand so reports/totals reflect
      // the fine separately. The RPC already added (bal + fine) into paidamount
      // for the row, so we just need to record how much of that was fine.
      for (final item in items) {
        final fine = (item['fine'] as num?)?.toDouble() ?? 0;
        if (fine > 0) {
          final demId = item['dem_id'];
          if (demId != null) {
            try {
              await SupabaseService.fromSchema('feedemand')
                  .update({'fineamount': fine})
                  .eq('dem_id', demId)
                  .eq('ins_id', insId!);
            } catch (e) {
              debugPrint('Fine column update error for dem_id=$demId: $e');
            }
          }
        }
      }

      _showSuccessDialog(receiptStr, totalNet);
    } catch (e) {
      String errorMsg = e.toString();
      if (errorMsg.contains('already fully paid')) {
        errorMsg = 'One or more fees have already been paid. Please refresh and try again.';
      } else if (errorMsg.contains('currently being processed')) {
        errorMsg = 'These fees are already being processed. Please wait and try again.';
      } else if (errorMsg.contains('not found or inactive')) {
        errorMsg = 'One or more fees are no longer available. Please refresh.';
      }

      // Payment failed — reset fineamount to 0 on attempted demands so no
      // stale fine is left in the DB.
      for (final item in items) {
        final demId = item['dem_id'];
        if (demId != null) {
          try {
            await SupabaseService.fromSchema('feedemand')
                .update({'fineamount': 0})
                .eq('dem_id', demId)
                .eq('ins_id', insId!);
          } catch (e2) {
            debugPrint('Fine reset error for dem_id=$demId: $e2');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $errorMsg'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  // ── Online payment (Razorpay) ──
  Timer? _pollTimer;

  Future<void> _processOnlinePayment() async {
    setState(() => _processing = true);

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final inscode = auth.currentUser?.inscode ?? '';
    final createdBy = auth.currentUser?.usename ?? '';
    final stuId = _student!['stu_id'] as int;
    final totalNet = _totalNetSelected;
    final amountInPaise = (totalNet * 100).round();

    // Block duplicate online attempts while a recent 'I' row exists for this
    // student. The sweep only clears orphans after 15 minutes, so within that
    // window we warn the user to wait instead of creating another pending row.
    try {
      final pending = await SupabaseService.fromSchema('payment')
          .select('pay_id, createdat')
          .eq('ins_id', insId!)
          .eq('stu_id', stuId)
          .eq('paystatus', 'I')
          .order('createdat', ascending: false)
          .limit(1)
          .maybeSingle();
      if (pending != null) {
        final createdAtStr = pending['createdat']?.toString();
        final createdAt = createdAtStr != null ? DateTime.tryParse(createdAtStr) : null;
        if (createdAt != null) {
          final ageMin = DateTime.now().difference(createdAt).inMinutes;
          if (ageMin < 15) {
            final waitMin = 15 - ageMin;
            if (mounted) {
              setState(() => _processing = false);
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Payment in progress'),
                  content: Text(
                    'An online payment for this student is still pending.\n'
                    'Please try again in about $waitMin minute${waitMin == 1 ? '' : 's'}.',
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
                  ],
                ),
              );
            }
            return;
          }
        }
      }
    } catch (e) {
      debugPrint('Pending-payment check failed: $e');
    }

    try {
      final firstDemand = _allDemands.firstWhere((d) => _selected.contains(_demKey(d)));
      final yrId = firstDemand['yr_id'] as int?;
      final yrlabel = firstDemand['demfeeyear']?.toString() ?? '';

      // Build items with demfeetype for grouping
      final items = <Map<String, dynamic>>[];
      for (final key in _selected) {
        final d = _allDemands.firstWhere((x) => _demKey(x) == key, orElse: () => {});
        if (d.isEmpty) continue;
        final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
        final fine = _fine(key);
        final col = _con(key);
        final net = (col > 0 ? col : bal) + fine;
        items.add({
          'dem_id': d['dem_id'] as int,
          'yr_id': d['yr_id'],
          'yrlabel': d['demfeeyear']?.toString() ?? '',
          'ins_id': insId,
          'amount': net,
          'demfeetype': d['demfeetype']?.toString() ?? '',
        });
      }

      // 1. Create a temporary payment for Razorpay order (status I).
      // Use insert().select() to atomically return pay_id — avoids the race
      // where a follow-up query could pick up a different row if two online
      // payments are started simultaneously for the same student.
      // Store the items JSON in paygwresponse so the orphan sweep can
      // reconstruct and finalize this payment if polling misses the capture.
      final inserted = await SupabaseService.fromSchema('payment').insert({
        'ins_id': insId,
        'inscode': inscode,
        'stu_id': stuId,
        'yr_id': yrId ?? 0,
        'yrlabel': yrlabel,
        'transtotalamount': totalNet,
        'transcurrency': 'INR',
        'paydate': DateTime.now().toIso8601String(),
        'paystatus': 'I',
        'createdby': createdBy,
        'recon_status': 'P',
        'payitems': jsonEncode(items),
      }).select('pay_id').single();
      final payId = inserted['pay_id'] as int;

      // 2. Create Razorpay order
      final orderResponse = await SupabaseService.client.functions.invoke(
        'create-razorpay-order',
        body: {
          'amount': amountInPaise,
          'currency': 'INR',
          'pay_id': payId,
          'receipt': 'PAY-$payId',
        },
      );

      final orderData = orderResponse.data is Map<String, dynamic>
          ? orderResponse.data as Map<String, dynamic>
          : <String, dynamic>{};
      final orderId = orderData['order_id'] as String;

      // Update payorderid
      await SupabaseService.fromSchema('payment').update({
        'payorderid': orderId,
      }).eq('pay_id', payId).eq('ins_id', insId!);

      // 3. Build checkout HTML and open in browser
      final studentName = _student!['stuname']?.toString() ?? '';
      final studentMobile = _student!['stumobile']?.toString() ?? '';
      final studentEmail = _student!['stuemail']?.toString() ?? '';

      final html = '''
<!DOCTYPE html>
<html>
<head>
  <title>TBS School - Fee Payment</title>
  <meta charset="utf-8">
  <style>
    body { font-family: Arial, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: #f5f5f5; }
    .container { text-align: center; padding: 40px; background: white; border-radius: 12px; box-shadow: 0 2px 10px rgba(0,0,0,0.1); }
    .success { color: #4CAF50; font-size: 24px; }
    .failed { color: #F44336; font-size: 24px; }
    .info { color: #666; margin-top: 10px; }
  </style>
  <script src="https://checkout.razorpay.com/v1/checkout.js"></script>
</head>
<body>
  <div class="container" id="status">
    <p>Opening Razorpay Checkout...</p>
  </div>
  <script>
    var options = {
      key: 'rzp_test_RQsgJgVFwM7kov',
      amount: $amountInPaise,
      currency: 'INR',
      name: 'TBS School',
      description: 'School Fees Payment',
      order_id: '$orderId',
      prefill: {
        name: '${studentName.replaceAll("'", "\\'")}',
        contact: '$studentMobile',
        email: '$studentEmail'
      },
      theme: { color: '#00B4AB' },
      notes: { pay_id: '$payId', student_id: '$stuId' },
      handler: function(response) {
        document.getElementById('status').innerHTML =
          '<p class="success">Payment Successful!</p>' +
          '<p class="info">Payment ID: ' + response.razorpay_payment_id + '</p>' +
          '<p class="info">You can close this window now.</p>';
      }
    };
    var rzp = new Razorpay(options);
    rzp.on('payment.failed', function(response) {
      document.getElementById('status').innerHTML =
        '<p class="failed">Payment Failed</p>' +
        '<p class="info">' + response.error.description + '</p>' +
        '<p class="info">You can close this window now.</p>';
    });
    rzp.open();
  </script>
</body>
</html>
''';

      // Write temp HTML file for WebView — unique per pay_id so concurrent
      // sessions (or retries after an abandoned checkout) never share state.
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/tbs_razorpay_checkout_$payId.html');
      await tempFile.writeAsString(html);

      // 4. Show WebView dialog with Razorpay checkout + polling
      if (mounted) {
        await _showRazorpayWebViewDialog(payId, insId, totalNet, tempFile.path, inscode, stuId, createdBy);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Online payment failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      _pollTimer?.cancel();
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _showRazorpayWebViewDialog(int payId, int? insId, double totalNet, String htmlPath, String inscode, int stuId, String createdBy) async {
    final completer = Completer<String?>(); // 'C', 'F', or null (cancelled)
    final webviewController = WebviewController();

    try {
      await webviewController.initialize();
      await webviewController.setBackgroundColor(Colors.white);
      await webviewController.loadUrl(Uri.file(htmlPath).toString());
    } catch (e) {
      if (!completer.isCompleted) completer.complete(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open payment window: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Start polling for payment status. Cap total polling time at 10 minutes
    // so a stuck Razorpay session can't leave the dialog and timer alive.
    final pollStarted = DateTime.now();
    const pollMaxDuration = Duration(minutes: 10);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      if (DateTime.now().difference(pollStarted) > pollMaxDuration) {
        timer.cancel();
        // Before giving up, do ONE final verification with Razorpay. The
        // student may have captured the payment in the last few seconds
        // before our timer elapsed — we don't want to mark F while money
        // has actually cleared on their side.
        try {
          final payRec = await SupabaseService.fromSchema('payment')
              .select('payorderid').eq('pay_id', payId).single();
          final orderId = payRec['payorderid']?.toString();
          if (orderId != null && orderId.isNotEmpty) {
            final finalResp = await SupabaseService.client.functions.invoke(
              'get-razorpay-payment', body: {'order_id': orderId},
            );
            final fd = finalResp.data as Map<String, dynamic>;
            if (fd['status'] == 'captured' && fd['payment_id'] != null) {
              await SupabaseService.fromSchema('payment').update({
                'payreference': fd['payment_id'].toString(),
              }).eq('pay_id', payId).eq('ins_id', insId!);
              if (!completer.isCompleted) completer.complete('C');
              return;
            }
          }
        } catch (_) {}
        if (!completer.isCompleted) completer.complete('F');
        return;
      }
      try {
        final payRecord = await SupabaseService.fromSchema('payment')
            .select('payorderid')
            .eq('pay_id', payId)
            .single();

        final orderId = payRecord['payorderid']?.toString();
        if (orderId == null || orderId.isEmpty) return;

        final rpResponse = await SupabaseService.client.functions.invoke(
          'get-razorpay-payment',
          body: {'order_id': orderId},
        );

        final rpData = rpResponse.data as Map<String, dynamic>;
        final rpPaymentId = rpData['payment_id']?.toString();
        final rpStatus = rpData['status']?.toString();

        if (rpPaymentId != null && rpPaymentId.isNotEmpty) {
          // Only 'captured' means money is actually in the account.
          // 'authorized' is still pending — treat as in-progress (keep polling).
          if (rpStatus == 'captured') {
            timer.cancel();
            await SupabaseService.fromSchema('payment').update({
              'payreference': rpPaymentId,
            }).eq('pay_id', payId).eq('ins_id', insId!);
            if (!completer.isCompleted) completer.complete('C');
          } else if (rpStatus == 'failed') {
            timer.cancel();
            await SupabaseService.fromSchema('payment').update({
              'payreference': rpPaymentId,
            }).eq('pay_id', payId).eq('ins_id', insId!);
            if (!completer.isCompleted) completer.complete('F');
          }
        }
      } catch (_) {}
    });

    // Show WebView dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          child: SizedBox(
            width: 500.w,
            height: 620.h,
            child: Column(
              children: [
                // Header
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14.r)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.payment, color: Colors.white, size: 20.sp),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: Text(
                          'Razorpay Payment  -  Rs.${totalNet.toStringAsFixed(2)}',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15.sp),
                        ),
                      ),
                      InkWell(
                        onTap: () async {
                          _pollTimer?.cancel();
                          // Check if payment was already completed before closing
                          try {
                            final checkPay = await SupabaseService.fromSchema('payment')
                                .select('payreference')
                                .eq('pay_id', payId)
                                .eq('ins_id', insId!)
                                .maybeSingle();
                            final ref = checkPay?['payreference']?.toString() ?? '';
                            if (ref.isNotEmpty && ref.startsWith('pay_')) {
                              // Payment was successful
                              try { webviewController.dispose(); } catch (_) {}
                              Navigator.pop(ctx);
                              if (!completer.isCompleted) completer.complete('C');
                              return;
                            }
                          } catch (_) {}
                          try { webviewController.dispose(); } catch (_) {}
                          Navigator.pop(ctx);
                          if (!completer.isCompleted) completer.complete(null);
                        },
                        child: Icon(Icons.close, color: Colors.white, size: 20.sp),
                      ),
                    ],
                  ),
                ),
                // WebView
                Expanded(
                  child: Webview(webviewController),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final result = await completer.future;

    // Dispose webview first
    try { webviewController.dispose(); } catch (_) {}

    // Dialog is already popped by its own close handlers (cancel, success, or X button).
    // Do NOT pop again here — it would pop the parent screen and cascade toward login.

    // Wait a moment for dialog to close
    await Future.delayed(const Duration(milliseconds: 300));

    if (result == 'C' || result == 'F' || result == null) {
      final status = result == 'C' ? 'C' : 'F';

      // Get Razorpay reference
      String rpRef = '';
      try {
        final payRecord = await SupabaseService.fromSchema('payment')
            .select('payreference')
            .eq('pay_id', payId)
            .eq('ins_id', insId!)
            .maybeSingle();
        rpRef = payRecord?['payreference']?.toString() ?? '';
      } catch (_) {}

      // Build items with demfeetype for per-group receipts
      final items = <Map<String, dynamic>>[];
      for (final key in _selected) {
        final d = _allDemands.firstWhere((x) => _demKey(x) == key, orElse: () => {});
        if (d.isEmpty) continue;
        final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
        final fine = _fine(key);
        final col = _con(key);
        final net = (col > 0 ? col : bal) + fine;
        items.add({
          'dem_id': d['dem_id'] as int,
          'amount': net,
          'demfeetype': d['demfeetype']?.toString() ?? '',
        });
      }

      String payRef = status == 'C' ? 'Razorpay: $rpRef' : (result == 'F' ? 'Razorpay Failed: $rpRef' : 'Cancelled by user');

      try {
        final rpResult = await SupabaseService.client.rpc('complete_payment_grouped', params: {
          'p_pay_id': payId,
          'p_pay_method': 'razorpay',
          'p_pay_reference': payRef,
          'p_items': items,
          'p_ins_id': insId,
          'p_status': status,
        });

        final receipts = rpResult is List ? rpResult : [rpResult];
        final receiptStr = receipts.map((r) => r is Map ? r['paynumber'] ?? r.toString() : r.toString()).join(', ');

        // On cancel/fail, explicitly reset fineamount to 0 on the attempted
        // demands so no stale fine value is left in the DB.
        if (status != 'C') {
          for (final item in items) {
            final demId = item['dem_id'];
            if (demId != null) {
              try {
                await SupabaseService.fromSchema('feedemand')
                    .update({'fineamount': 0})
                    .eq('dem_id', demId)
                    .eq('ins_id', insId!);
              } catch (e) {
                debugPrint('Fine reset error for dem_id=$demId: $e');
              }
            }
          }
        }

        if (mounted) {
          if (status == 'C') {
            _showSuccessDialog(receiptStr, totalNet);
          } else if (result == 'F') {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Payment failed. Receipt: $receiptStr'), backgroundColor: Colors.red),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Payment cancelled. Receipt: $receiptStr'), backgroundColor: Colors.orange),
            );
          }
        }
      } catch (e) {
        debugPrint('complete_payment_grouped failed: $e');
        // Fallback: just mark as failed
        try {
          await SupabaseService.fromSchema('payment').update({
            'paystatus': 'F',
          }).eq('pay_id', payId).eq('ins_id', insId!);
        } catch (_) {}
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Payment error: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  // ── Helpers ──

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      padding: EdgeInsets.all(12.w),
      child: child,
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(fontSize: 13.sp, color: AppColors.textLight),
      contentPadding:
          EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8.r),
          borderSide:
              const BorderSide(color: AppColors.accent, width: 1.5)),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15.sp, color: AppColors.textSecondary),
        SizedBox(width: 8.w),
        Text('$label  ',
            style: TextStyle(
                fontSize: 13.sp, color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: TextStyle(
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _termChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(20.r),
          border:
              Border.all(color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 13.sp,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  Widget _numField(TextEditingController? ctrl, VoidCallback onChange) {
    if (ctrl == null) return const SizedBox();
    return SizedBox(
      height: 28.h,
      child: TextField(
        controller: ctrl,
        onChanged: (_) => onChange(),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13.sp),
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: TextStyle(
              fontSize: 13.sp, color: AppColors.textLight),
          contentPadding:
              EdgeInsets.symmetric(horizontal: 6.w, vertical: 4.h),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.r),
              borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.r),
              borderSide: BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6.r),
              borderSide: const BorderSide(
                  color: AppColors.accent, width: 1.2)),
        ),
      ),
    );
  }

  String _formatDate(String iso) {
    // Convert yyyy-MM-dd → dd/MM/yyyy
    final parts = iso.split('-');
    if (parts.length == 3) return '${parts[2]}/${parts[1]}/${parts[0]}';
    return iso;
  }
}

class _THCell extends StatelessWidget {
  final String text;
  final int flex;
  final TextAlign textAlign;
  const _THCell(this.text, {this.flex = 1, this.textAlign = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text.toUpperCase(),
          textAlign: textAlign,
          style: TextStyle(
              fontSize: 13.sp,
              fontWeight: FontWeight.w700,
              color: Colors.white)),
    );
  }
}

class _TDCell extends StatelessWidget {
  final String text;
  final int flex;
  final TextStyle? style;
  final TextAlign textAlign;
  const _TDCell(this.text, {this.flex = 1, this.style, this.textAlign = TextAlign.left});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          textAlign: textAlign,
          style: style ??
              TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis),
    );
  }
}
