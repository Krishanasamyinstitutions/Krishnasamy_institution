import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/student_model.dart';

class StudentLedgerScreen extends StatefulWidget {
  const StudentLedgerScreen({super.key});

  @override
  State<StudentLedgerScreen> createState() => _StudentLedgerScreenState();
}

class _StudentLedgerScreenState extends State<StudentLedgerScreen> {
  // Class list
  List<String> _classes = [];
  Map<String, int> _classCounts = {};
  bool _loadingClasses = true;

  // Selected class & students
  String? _selectedClass;
  final Map<String, List<StudentModel>> _cachedClassStudents = {};
  bool _loadingStudents = false;

  // Search in student list
  final _searchController = TextEditingController();

  // Selected student & ledger data
  StudentModel? _selectedStudent;
  Map<String, dynamic>? _parent;
  List<Map<String, dynamic>> _demands = [];
  bool _loadingLedger = false;

  static const List<String> _classOrder = [
    'PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V',
    'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
  ];
  static const List<Color> _classColors = [
    Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFA855F7),
    Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFFEF4444),
    Color(0xFFF97316), Color(0xFFF59E0B), Color(0xFF22C55E),
    Color(0xFF6C8EEF), Color(0xFF06B6D4), Color(0xFF6C8EEF),
    Color(0xFF2563EB), Color(0xFF7C3AED), Color(0xFF9333EA), Color(0xFFDB2777),
  ];

  Color _classColor(String cls) {
    final i = _classOrder.indexOf(cls);
    return (i >= 0 && i < _classColors.length) ? _classColors[i] : AppColors.accent;
  }

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadClasses() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _loadingClasses = true);
    try {
      final counts = await SupabaseService.getStudentCountsByClass(insId);
      final rawClasses = counts.keys.toList();
      final ordered = _classOrder.where(rawClasses.contains).toList();
      final extra = rawClasses.where((c) => !_classOrder.contains(c)).toList()..sort();
      setState(() {
        _classes = [...ordered, ...extra];
        _classCounts = counts;
        _loadingClasses = false;
      });
    } catch (_) {
      setState(() => _loadingClasses = false);
    }
  }

  Future<void> _selectClass(String className) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;
    setState(() {
      _selectedClass = className;
      _selectedStudent = null;
      _demands = [];
      _searchController.clear();
    });
    if (_cachedClassStudents[className] == null) {
      setState(() => _loadingStudents = true);
      final students = await SupabaseService.getStudentsByClass(insId, className);
      if (mounted) {
        setState(() {
          _cachedClassStudents[className] = students;
          _loadingStudents = false;
        });
      }
    }
  }

  Future<void> _selectStudent(StudentModel student) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    setState(() {
      _selectedStudent = student;
      _demands = [];
      _parent = null;
      _loadingLedger = true;
    });
    try {
      debugPrint('LEDGER: insId=$insId stuId=${student.stuId} stuadmno=${student.stuadmno}');

      final parentFuture = SupabaseService.getStudentParent(student.stuId, stuadmno: student.stuadmno);

      // Try stuadmno first (primary key used in feedemand)
      const selectFields = 'dem_id, demno, demfeetype, demfeeterm, feeamount, conamount, paidamount, balancedue, duedate, paidstatus, pay_id';
      final demandsByAdmno = await SupabaseService.fromSchema('feedemand')
          .select(selectFields)
          .eq('ins_id', insId)
          .eq('stuadmno', student.stuadmno)
          .order('duedate', ascending: true);

      debugPrint('LEDGER: demands by stuadmno=${(demandsByAdmno as List).length}');

      // Fallback to stu_id if no results
      List<Map<String, dynamic>> demandList;
      if ((demandsByAdmno as List).isEmpty) {
        final demandsByStuId = await SupabaseService.fromSchema('feedemand')
            .select(selectFields)
            .eq('ins_id', insId)
            .eq('stu_id', student.stuId)
            .order('duedate', ascending: true);
        debugPrint('LEDGER: demands by stu_id=${(demandsByStuId as List).length}');
        demandList = List<Map<String, dynamic>>.from(demandsByStuId as List);
      } else {
        demandList = List<Map<String, dynamic>>.from(demandsByAdmno as List);
      }

      // Fetch payment info for paid demands
      final payIds = demandList
          .where((d) => (d['paidstatus'] == 'P' || (d['paidstatus'] == 'U' && ((d['paidamount'] as num?)?.toDouble() ?? 0) > 0)) && d['pay_id'] != null)
          .map((d) => d['pay_id'] as int)
          .toSet()
          .toList();

      Map<int, Map<String, dynamic>> paymentMap = {};
      if (payIds.isNotEmpty) {
        final payments = await SupabaseService.fromSchema('payment')
            .select('pay_id, paynumber, paydate, paymethod')
            .eq('ins_id', insId)
            .inFilter('pay_id', payIds);
        for (final p in (payments as List)) {
          paymentMap[p['pay_id'] as int] = Map<String, dynamic>.from(p);
        }
      }

      // Attach payment data to demands
      for (var i = 0; i < demandList.length; i++) {
        final payId = demandList[i]['pay_id'];
        if (payId != null && paymentMap.containsKey(payId)) {
          demandList[i]['payment'] = paymentMap[payId];
        }
      }

      final parent = await parentFuture;

      if (mounted) {
        setState(() {
          _parent = parent;
          _demands = demandList;
          _loadingLedger = false;
        });
      }
    } catch (e) {
      debugPrint('LEDGER ERROR: $e');
      if (mounted) setState(() => _loadingLedger = false);
    }
  }

  double get _totalDemand => _demands.fold(0.0, (s, d) => s + ((d['feeamount'] as num?)?.toDouble() ?? 0));
  double get _totalPaid => _demands.fold(0.0, (s, d) => s + ((d['paidamount'] as num?)?.toDouble() ?? 0));
  double get _totalPending => _demands.fold(0.0, (s, d) => s + ((d['balancedue'] as num?)?.toDouble() ?? 0));

  // Ledger rows from feedemand: unpaid = debit only, paid = debit + credit
  List<Map<String, dynamic>> get _ledgerRows {
    final rows = <Map<String, dynamic>>[];
    for (final d in _demands) {
      final raw = d['duedate']?.toString() ?? '';
      final paidAmount = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final hasPaid = paidAmount > 0;
      final payment = d['payment'];

      // Demand row (debit)
      rows.add({
        'date': raw.length >= 10 ? raw.substring(0, 10) : raw,
        'docno': d['demno']?.toString() ?? d['dem_id']?.toString() ?? '-',
        'term': d['demfeeterm']?.toString() ?? '-',
        'feetype': d['demfeetype']?.toString() ?? '-',
        'reference': '-',
        'debit': (d['feeamount'] as num?)?.toDouble() ?? 0.0,
        'credit': 0.0,
        'type': 'demand',
      });

      // Payment row (credit) — for paid and partially paid demands
      if (hasPaid && payment is Map) {
        final payDate = payment['paydate']?.toString() ?? raw;
        final payNumber = payment['paynumber']?.toString() ?? '-';
        final payMethod = payment['paymethod']?.toString() ?? '-';
        final balance = (d['balancedue'] as num?)?.toDouble() ?? 0.0;
        final isPartial = balance > 0;
        rows.add({
          'date': payDate.length >= 10 ? payDate.substring(0, 10) : payDate,
          'docno': payNumber,
          'term': d['demfeeterm']?.toString() ?? '-',
          'feetype': isPartial ? 'Partial Payment ($payMethod)' : 'Payment ($payMethod)',
          'reference': d['demno']?.toString() ?? d['dem_id']?.toString() ?? '-',
          'debit': balance,
          'credit': paidAmount,
          'type': 'payment',
        });
      }
    }
    // Demands first (sorted by date), then payments (sorted by date)
    rows.sort((a, b) {
      final typeA = a['type'] == 'demand' ? 0 : 1;
      final typeB = b['type'] == 'demand' ? 0 : 1;
      if (typeA != typeB) return typeA.compareTo(typeB);
      return (a['date'] as String).compareTo(b['date'] as String);
    });
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Left: Class list ──
        Container(
          width: 260.w,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border))),
                child: Row(
                  children: [
                    Icon(Icons.people_alt_rounded, size: 16.sp, color: AppColors.accent),
                    SizedBox(width: 8.w),
                    Text('Students',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const Spacer(),
                    if (!_loadingClasses)
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Text(
                          '${_classCounts.values.fold(0, (a, b) => a + b)}',
                          style: TextStyle(fontSize: 13.sp, color: AppColors.accent, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loadingClasses
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : ListView.builder(
                        padding: EdgeInsets.symmetric(vertical: 4.h),
                        itemCount: _classes.length,
                        itemBuilder: (context, index) {
                          final cls = _classes[index];
                          final count = _classCounts[cls] ?? 0;
                          final color = _classColor(cls);
                          final isSelected = _selectedClass == cls;
                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _selectClass(cls),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 11.h),
                                decoration: BoxDecoration(
                                  color: isSelected ? color.withValues(alpha: 0.08) : null,
                                  border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34.w, height: 34.h,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: isSelected ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(9.r),
                                      ),
                                      child: Center(child: Icon(Icons.class_rounded, size: 16.sp, color: color)),
                                    ),
                                    SizedBox(width: 10.w),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Class $cls',
                                              style: TextStyle(fontSize: 13.sp, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600, color: isSelected ? color : AppColors.textPrimary)),
                                          Text('$count students',
                                              style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: isSelected ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(10.r),
                                      ),
                                      child: Text('$count', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: color)),
                                    ),
                                    SizedBox(width: 6.w),
                                    Icon(isSelected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                                        size: 16.sp, color: isSelected ? color : AppColors.textSecondary),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),

        SizedBox(width: 12.w),

        // ── Right: Student list OR Ledger ──
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.border),
            ),
            child: _selectedClass == null
                ? _emptyState(Icons.class_outlined, 'Select a class to view students')
                : _selectedStudent == null
                    ? _buildStudentList()
                    : _buildLedger(),
          ),
        ),
      ],
    );
  }

  // ── Student List ──
  Widget _buildStudentList() {
    final cls = _selectedClass!;
    final color = _classColor(cls);
    final allStudents = _cachedClassStudents[cls] ?? [];
    final q = _searchController.text.toLowerCase();
    final students = q.isEmpty
        ? allStudents
        : allStudents.where((s) =>
            s.stuname.toLowerCase().contains(q) ||
            s.stuadmno.toLowerCase().contains(q)).toList();

    return Column(
      children: [
        // Header
        Container(
          padding: EdgeInsets.fromLTRB(12.w, 10.h, 16.w, 10.h),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: BorderRadius.only(topLeft: Radius.circular(12.r), topRight: Radius.circular(12.r)),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.class_rounded, size: 14.sp, color: color),
              SizedBox(width: 6.w),
              Text('Class $cls',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: color)),
              SizedBox(width: 8.w),
              Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: Text('${allStudents.length} students',
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: color)),
              ),
              const Spacer(),
              SizedBox(
                width: 240.w,
                height: 36.h,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: TextStyle(fontSize: 13.sp, color: AppColors.textLight),
                    prefixIcon: Icon(Icons.search_rounded, size: 16.sp, color: AppColors.textLight),
                    contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.accent)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Table header
        Container(
          color: const Color(0xFF6C8EEF),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          child: Row(
            children: [
              SizedBox(width: 48.w, child: Text('S NO.', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              SizedBox(width: 80.w, child: Text('ADM NO', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              Expanded(child: Text('STUDENT NAME', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              SizedBox(width: 60.w, child: Text('GENDER', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              SizedBox(width: 40.w),
            ],
          ),
        ),

        // Rows
        Expanded(
          child: _loadingStudents
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : students.isEmpty
                  ? Center(child: Text('No students found', style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400)))
                  : ListView.separated(
                      itemCount: students.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                      itemBuilder: (context, i) {
                        final s = students[i];
                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () => _selectStudent(s),
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48.w,
                                    child: Text('${i + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                                  ),
                                  SizedBox(
                                    width: 80.w,
                                    child: Text(s.stuadmno, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: color)),
                                  ),
                                  Expanded(
                                    child: Text(s.stuname, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                                  ),
                                  SizedBox(
                                    width: 60.w,
                                    child: Text(s.stugender, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                                  ),
                                  SizedBox(
                                    width: 40.w,
                                    child: Icon(Icons.chevron_right_rounded, size: 18.sp, color: color.withValues(alpha: 0.7)),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // ── Ledger ──
  Widget _buildLedger() {
    final s = _selectedStudent!;
    final fatherName = _parent?['fathername']?.toString() ?? '-';

    return Column(
      children: [
        // Back + student info
        Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _selectedStudent = null;
                  _demands = [];
                              _parent = null;
                }),
                icon: Icon(Icons.arrow_back_rounded, size: 18.sp),
                color: AppColors.accent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Back to student list',
              ),
              SizedBox(width: 8.w),
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                child: (s.stuphoto != null && s.stuphoto!.startsWith('http'))
                    ? ClipOval(
                        child: Image.network(
                          s.stuphoto!,
                          width: 40.w, height: 40.h, fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Text(s.stuname.isNotEmpty ? s.stuname[0].toUpperCase() : '?',
                              style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14.sp)),
                        ),
                      )
                    : Text(s.stuname.isNotEmpty ? s.stuname[0].toUpperCase() : '?',
                        style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14.sp)),
              ),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.stuname, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('Adm: ${s.stuadmno}  •  Class ${s.stuclass}  •  Father: $fatherName',
                        style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (!_loadingLedger) ...[
                _chip('Demand', '₹${_totalDemand.toStringAsFixed(0)}', AppColors.textPrimary),
                SizedBox(width: 8.w),
                _chip('Paid', '₹${_totalPaid.toStringAsFixed(0)}', Colors.green.shade700),
                SizedBox(width: 8.w),
                _chip('Pending', '₹${_totalPending.toStringAsFixed(0)}', AppColors.error),
                SizedBox(width: 12.w),
                TextButton.icon(
                  onPressed: _demands.isNotEmpty ? _exportToExcel : null,
                  icon: Icon(Icons.download_rounded, size: 16.sp),
                  label: const Text('Export'),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.accent,
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ],
          ),
        ),

        Expanded(
          child: _loadingLedger
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : _buildDemandsTab(),
        ),
      ],
    );
  }

  Widget _buildDemandsTab() {
    final rows = _ledgerRows;
    final totalDebit   = rows.fold(0.0, (s, r) => s + (r['debit']  as double));
    final totalCredit  = rows.fold(0.0, (s, r) => s + (r['credit'] as double));
    final closingBalance = totalDebit - totalCredit;

    return Column(
      children: [
        // ── Column header ──
        Container(
          color: const Color(0xFF6C8EEF),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          child: Row(
            children: [
              SizedBox(width: 100.w, child: const _TH('DATE')),
              SizedBox(width: 110.w, child: const _TH('DOC.NO')),
              SizedBox(width: 90.w,  child: const _TH('TERM')),
              const Expanded(            child: _TH('FEE TYPE')),
              SizedBox(width: 110.w, child: const _TH('REFERENCE')),
              SizedBox(width: 100.w, child: const _TH('DUE', align: TextAlign.right)),
              SizedBox(width: 100.w, child: const _TH('RECEIVED', align: TextAlign.right)),
            ],
          ),
        ),

        // ── Data rows ──
        Expanded(
          child: rows.isEmpty
              ? Column(
                  children: [
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.receipt_long_outlined, size: 48.sp, color: Colors.grey.shade300),
                            SizedBox(height: 12.h),
                            Text('No fee demands found for this student',
                                style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400)),
                          ],
                        ),
                      ),
                    ),
                  ],
                )
              : ListView.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, __) => const Divider(height: 1, color: Color(0xFFEEEEEE)),
                  itemBuilder: (context, i) {
                    final r      = rows[i];
                    final debit  = r['debit']  as double;
                    final credit = r['credit'] as double;
                    final isDemand = r['type'] == 'demand';
                    return Container(
                      color: i.isOdd ? const Color(0xFFFAFAFA) : Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 11.h),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100.w,
                            child: Text(_fmt(r['date'] as String),
                                style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                          ),
                          SizedBox(
                            width: 110.w,
                            child: Text(r['docno'] as String,
                                style: TextStyle(
                                    fontSize: 13.sp,
                                    fontWeight: FontWeight.w600,
                                    color: isDemand ? AppColors.accent : Colors.green.shade700)),
                          ),
                          SizedBox(
                            width: 90.w,
                            child: Text(r['term'] as String,
                                style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 6.w, height: 6.h,
                                  margin: EdgeInsets.only(right: 6.w),
                                  decoration: BoxDecoration(
                                    color: isDemand ? AppColors.error.withValues(alpha: 0.7) : Colors.green.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(r['feetype'] as String,
                                      style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 110.w,
                            child: Text(r['reference'] as String,
                                style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis),
                          ),
                          SizedBox(
                            width: 100.w,
                            child: Text(
                              debit > 0 ? '₹${debit.toStringAsFixed(0)}' : '-',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: debit > 0 ? AppColors.error : AppColors.textSecondary),
                            ),
                          ),
                          SizedBox(
                            width: 100.w,
                            child: Text(
                              credit > 0 ? '₹${credit.toStringAsFixed(0)}' : '-',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 13.sp,
                                  fontWeight: FontWeight.w600,
                                  color: credit > 0 ? Colors.green.shade700 : AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        ),

        // ── Footer ──
        ClipRRect(
          borderRadius: BorderRadius.only(
              bottomLeft: Radius.circular(12.r), bottomRight: Radius.circular(12.r)),
          child: Column(
            children: [
              // Total row — same dark bg as header
              Container(
                color: const Color(0xFF6C8EEF),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                child: Row(
                  children: [
                    SizedBox(width: 100.w),
                    SizedBox(width: 110.w),
                    SizedBox(width: 90.w),
                    Expanded(
                      child: Text('TOTAL',
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700,
                              color: Colors.white, letterSpacing: 0.5.w)),
                    ),
                    SizedBox(width: 110.w),
                    SizedBox(
                      width: 100.w,
                      child: Text('₹${totalDebit.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                    SizedBox(
                      width: 100.w,
                      child: Text('₹${totalCredit.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700,
                              color: Colors.white)),
                    ),
                  ],
                ),
              ),
              // Closing Balance row — slightly lighter dark
              Container(
                color: const Color(0xFF6C8EEF),
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 11.h),
                child: Row(
                  children: [
                    SizedBox(width: 100.w),
                    SizedBox(width: 110.w),
                    SizedBox(width: 90.w),
                    Expanded(
                      child: Text('CLOSING BALANCE',
                          style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700,
                              color: Colors.white, letterSpacing: 0.5.w)),
                    ),
                    SizedBox(width: 110.w),
                    SizedBox(
                      width: 200.w,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                          decoration: BoxDecoration(
                            color: closingBalance <= 0
                                ? Colors.white.withValues(alpha: 0.2)
                                : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(8.r),
                            border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            closingBalance <= 0
                                ? '₹${closingBalance.abs().toStringAsFixed(0)}  Advance'
                                : '₹${closingBalance.toStringAsFixed(0)}  Due',
                            style: TextStyle(
                                fontSize: 14.sp,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }


  Future<void> _exportToExcel() async {
    final s = _selectedStudent!;
    final fatherName = _parent?['fathername']?.toString() ?? '-';
    final rows = _ledgerRows;
    final totalDebit = rows.fold(0.0, (s, r) => s + (r['debit'] as double));
    final totalCredit = rows.fold(0.0, (s, r) => s + (r['credit'] as double));
    final closingBal = totalDebit - totalCredit;

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
    final sheetName = 'Ledger';
    excel.rename('Sheet1', sheetName);
    final sheet = excel[sheetName];

    // Styles
    final headerStyle = xl.CellStyle(
      bold: true,
      fontSize: 14,
      horizontalAlign: xl.HorizontalAlign.Center,
    );
    final insStyle = xl.CellStyle(
      bold: true,
      fontSize: 13,
      horizontalAlign: xl.HorizontalAlign.Center,
    );
    final insDetailStyle = xl.CellStyle(
      fontSize: 10,
      horizontalAlign: xl.HorizontalAlign.Center,
    );
    final labelStyle = xl.CellStyle(bold: true, fontSize: 13);
    final colHeaderStyle = xl.CellStyle(
      bold: true,
      fontSize: 13,
      backgroundColorHex: xl.ExcelColor.fromHexString('#1E2532'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    );
    final debitStyle = xl.CellStyle(
      fontColorHex: xl.ExcelColor.fromHexString('#EF4444'),
      bold: true,
    );
    final creditStyle = xl.CellStyle(
      fontColorHex: xl.ExcelColor.fromHexString('#22C55E'),
      bold: true,
    );
    final totalRowStyle = xl.CellStyle(
      bold: true,
      fontSize: 13,
      backgroundColorHex: xl.ExcelColor.fromHexString('#1E2532'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
    );

    int row = 0;

    // Institution name
    final insNameCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    insNameCell.value = xl.TextCellValue(insName.toUpperCase());
    insNameCell.cellStyle = insStyle;
    sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row));
    row++;

    // Institution address
    if (insAddress.isNotEmpty) {
      final addrCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      addrCell.value = xl.TextCellValue(insAddress);
      addrCell.cellStyle = insDetailStyle;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row));
      row++;
    }

    // Institution contact (mobile & email)
    final contactParts = <String>[];
    if (insMobile.isNotEmpty) contactParts.add('Ph: $insMobile');
    if (insEmail.isNotEmpty) contactParts.add('Email: $insEmail');
    if (contactParts.isNotEmpty) {
      final contactCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      contactCell.value = xl.TextCellValue(contactParts.join('  |  '));
      contactCell.cellStyle = insDetailStyle;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
          xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row));
      row++;
    }
    row++; // blank row after institution info

    // Title
    final titleCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    titleCell.value = xl.TextCellValue('STUDENT LEDGER - YEAR:  2025-2026');
    titleCell.cellStyle = headerStyle;
    sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row),
        xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row));
    row += 1;

    // Student info
    void addInfo(String label, String value) {
      final c1 = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
      c1.value = xl.TextCellValue(label);
      c1.cellStyle = labelStyle;
      final c2 = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row));
      c2.value = xl.TextCellValue(value);
      row++;
    }

    addInfo('Class', ':  ${s.stuclass}');
    addInfo('Student Name', ':  ${s.stuname}');
    // Add admission no on same row as student name but further right
    final admCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row - 1));
    admCell.value = xl.TextCellValue('Admission No : ${s.stuadmno}');
    admCell.cellStyle = labelStyle;
    addInfo('Father Name', ':  $fatherName');
    row++;

    // "Regular Fee Details:" label
    final regCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    regCell.value = xl.TextCellValue('Regular Fee Details :');
    regCell.cellStyle = labelStyle;
    row++;

    // Column headers
    final headers = ['Date', 'Doc No.', 'Term', 'Fee Type', 'Reference', 'Debit (Rs.)', 'Credit (Rs.)'];
    for (var c = 0; c < headers.length; c++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = xl.TextCellValue(headers[c]);
      cell.cellStyle = colHeaderStyle;
    }
    row++;

    // Data rows
    for (final r in rows) {
      final isDemand = r['type'] == 'demand';
      final debit = r['debit'] as double;
      final credit = r['credit'] as double;

      final dateStr = _fmt(r['date'] as String);
      final docNo = r['docno'] as String;
      final reference = isDemand ? 'Reg Demand' : 'Reg Collection${_capitalize(r['feetype'] as String)}';

      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(dateStr);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue(docNo);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.TextCellValue(r['term'] as String);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.TextCellValue(
          isDemand ? (r['feetype'] as String) : '');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4, rowIndex: row)).value = xl.TextCellValue(reference);

      if (debit > 0) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
        cell.value = xl.DoubleCellValue(debit);
        cell.cellStyle = debitStyle;
      }
      if (credit > 0) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row));
        cell.value = xl.DoubleCellValue(credit);
        cell.cellStyle = creditStyle;
      }
      row++;
    }

    // G Total row
    final gtLabels = ['', '', '', '', 'G Total'];
    for (var c = 0; c < gtLabels.length; c++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row));
      cell.value = xl.TextCellValue(gtLabels[c]);
      cell.cellStyle = totalRowStyle;
    }
    final gtDebit = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
    gtDebit.value = xl.DoubleCellValue(totalDebit);
    gtDebit.cellStyle = totalRowStyle;
    final gtCredit = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6, rowIndex: row));
    gtCredit.value = xl.DoubleCellValue(totalCredit);
    gtCredit.cellStyle = totalRowStyle;
    row++;

    // Closing Bal row
    final cbCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    cbCell.value = xl.TextCellValue('Closing Bal');
    cbCell.cellStyle = labelStyle;
    final cbVal = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
    cbVal.value = xl.DoubleCellValue(closingBal.abs());
    cbVal.cellStyle = labelStyle;
    row++;

    // Net Closing Balance row
    final ncbCell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row));
    ncbCell.value = xl.TextCellValue('Net Closing Balance');
    ncbCell.cellStyle = labelStyle;
    final ncbVal = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: row));
    ncbVal.value = xl.DoubleCellValue(closingBal.abs());
    ncbVal.cellStyle = labelStyle;

    // Column widths
    sheet.setColumnWidth(0, 14);
    sheet.setColumnWidth(1, 16);
    sheet.setColumnWidth(2, 14);
    sheet.setColumnWidth(3, 20);
    sheet.setColumnWidth(4, 22);
    sheet.setColumnWidth(5, 14);
    sheet.setColumnWidth(6, 14);

    // Save
    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Student Ledger',
      fileName: 'Ledger_${s.stuadmno}_${s.stuname.replaceAll(' ', '_')}.xlsx',
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
            SnackBar(content: Text('Ledger exported to $path'), backgroundColor: Colors.green),
          );
        }
      }
    }
  }

  String _capitalize(String s) {
    // Extract payment method from "Payment (cash)" => "Cash"
    final match = RegExp(r'Payment \((\w+)\)').firstMatch(s);
    if (match != null) {
      final method = match.group(1)!;
      return method[0].toUpperCase() + method.substring(1);
    }
    return s;
  }

  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8.r), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9.sp, color: color.withValues(alpha: 0.7))),
        Text(value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }


  Widget _emptyState(IconData icon, String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48.sp, color: Colors.grey.shade300),
      SizedBox(height: 12.h),
      Text(msg, style: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400)),
    ]),
  );

  String _fmt(String iso) {
    final p = iso.split('-');
    return p.length == 3 ? '${p[2]}/${p[1]}/${p[0]}' : iso;
  }
}

class _TH extends StatelessWidget {
  final String text;
  final TextAlign align;
  const _TH(this.text, {this.align = TextAlign.left});
  @override
  Widget build(BuildContext context) =>
      Text(text, textAlign: align, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: Colors.white));
}

