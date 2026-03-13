import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
  List<Map<String, dynamic>> _payments = [];
  bool _loadingLedger = false;

  static const List<String> _classOrder = [
    'PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V',
    'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
  ];
  static const List<Color> _classColors = [
    Color(0xFF6366F1), Color(0xFF8B5CF6), Color(0xFFA855F7),
    Color(0xFFEC4899), Color(0xFFF43F5E), Color(0xFFEF4444),
    Color(0xFFF97316), Color(0xFFF59E0B), Color(0xFF22C55E),
    Color(0xFF14B8A6), Color(0xFF06B6D4), Color(0xFF3B82F6),
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
      _payments = [];
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
      _payments = [];
      _parent = null;
      _loadingLedger = true;
    });
    try {
      debugPrint('LEDGER: insId=$insId stuId=${student.stuId} stuadmno=${student.stuadmno}');

      final parentFuture = SupabaseService.getStudentParent(student.stuId, stuadmno: student.stuadmno);

      // Try stuadmno first (primary key used in feedemand)
      final demandsByAdmno = await SupabaseService.client
          .from('feedemand')
          .select('dem_id, demno, demfeetype, demfeeterm, feeamount, conamount, balancedue, duedate, paidstatus, demconcategory')
          .eq('ins_id', insId)
          .eq('stuadmno', student.stuadmno)
          .order('duedate', ascending: true);

      debugPrint('LEDGER: demands by stuadmno=${(demandsByAdmno as List).length}');

      // Fallback to stu_id if no results
      List<Map<String, dynamic>> demandList;
      if ((demandsByAdmno as List).isEmpty) {
        final demandsByStuId = await SupabaseService.client
            .from('feedemand')
            .select('dem_id, demno, demfeetype, demfeeterm, feeamount, conamount, balancedue, duedate, paidstatus, demconcategory')
            .eq('ins_id', insId)
            .eq('stu_id', student.stuId)
            .order('duedate', ascending: true);
        debugPrint('LEDGER: demands by stu_id=${(demandsByStuId as List).length}');
        demandList = List<Map<String, dynamic>>.from(demandsByStuId as List);
      } else {
        demandList = List<Map<String, dynamic>>.from(demandsByAdmno as List);
      }

      final paymentsFuture = SupabaseService.client
          .from('payment')
          .select('pay_id, paynumber, paydate, transtotalamount, paystatus, paymethod')
          .eq('ins_id', insId)
          .eq('stu_id', student.stuId)
          .order('paydate', ascending: false);

      final parent = await parentFuture;
      final paymentList = List<Map<String, dynamic>>.from((await paymentsFuture) as List);
      debugPrint('LEDGER: payments=${paymentList.length}');

      if (mounted) {
        setState(() {
          _parent = parent;
          _demands = demandList;
          _payments = paymentList;
          _loadingLedger = false;
        });
      }
    } catch (e) {
      debugPrint('LEDGER ERROR: $e');
      if (mounted) setState(() => _loadingLedger = false);
    }
  }

  double get _totalDemand => _demands.fold(0.0, (s, d) => s + ((d['feeamount'] as num?)?.toDouble() ?? 0));
double get _totalPaid => _payments.where((p) => p['paystatus'] == 'C').fold(0.0, (s, p) => s + ((p['transtotalamount'] as num?)?.toDouble() ?? 0));
  double get _totalPending => _demands.where((d) => d['paidstatus'] == 'U').fold(0.0, (s, d) => s + ((d['balancedue'] as num?)?.toDouble() ?? 0));

  // Combined ledger rows: demands as debit, payments as credit, sorted by date
  List<Map<String, dynamic>> get _ledgerRows {
    final rows = <Map<String, dynamic>>[];
    for (final d in _demands) {
      final raw = d['duedate']?.toString() ?? '';
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
    }
    for (final p in _payments) {
      final raw = p['paydate']?.toString() ?? '';
      rows.add({
        'date': raw.length >= 10 ? raw.substring(0, 10) : raw,
        'docno': p['paynumber']?.toString() ?? '-',
        'term': '-',
        'feetype': 'Payment (${p['paymethod'] ?? '-'})',
        'reference': p['paynumber']?.toString() ?? '-',
        'debit': 0.0,
        'credit': (p['transtotalamount'] as num?)?.toDouble() ?? 0.0,
        'type': 'payment',
      });
    }
    rows.sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // ── Left: Class list ──
        Container(
          width: 260,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border))),
                child: Row(
                  children: [
                    const Icon(Icons.people_alt_rounded, size: 16, color: AppColors.accent),
                    const SizedBox(width: 8),
                    Text('Students',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const Spacer(),
                    if (!_loadingClasses)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_classCounts.values.fold(0, (a, b) => a + b)}',
                          style: const TextStyle(fontSize: 11, color: AppColors.accent, fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: _loadingClasses
                    ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 4),
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
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                                decoration: BoxDecoration(
                                  color: isSelected ? color.withValues(alpha: 0.08) : null,
                                  border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 34, height: 34,
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: isSelected ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(9),
                                      ),
                                      child: Center(child: Icon(Icons.class_rounded, size: 16, color: color)),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Class $cls',
                                              style: TextStyle(fontSize: 12, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600, color: isSelected ? color : AppColors.textPrimary)),
                                          Text('$count students',
                                              style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: color.withValues(alpha: isSelected ? 0.2 : 0.1),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text('$count', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(isSelected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                                        size: 16, color: isSelected ? color : AppColors.textSecondary),
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

        const SizedBox(width: 12),

        // ── Right: Student list OR Ledger ──
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
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
          padding: const EdgeInsets.fromLTRB(12, 10, 16, 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.06),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              Icon(Icons.class_rounded, size: 14, color: color),
              const SizedBox(width: 6),
              Text('Class $cls',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: color)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text('${allStudents.length} students',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
              ),
              const Spacer(),
              SizedBox(
                width: 240,
                height: 36,
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: const TextStyle(fontSize: 12, color: AppColors.textLight),
                    prefixIcon: const Icon(Icons.search_rounded, size: 16, color: AppColors.textLight),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Table header
        Container(
          color: const Color(0xFF1E2532),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(
            children: [
              SizedBox(width: 48, child: Text('S NO.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70))),
              SizedBox(width: 80, child: Text('ADM NO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70))),
              Expanded(child: Text('STUDENT NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70))),
              SizedBox(width: 60, child: Text('GENDER', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70))),
              SizedBox(width: 40),
            ],
          ),
        ),

        // Rows
        Expanded(
          child: _loadingStudents
              ? const Center(child: CircularProgressIndicator(color: AppColors.accent))
              : students.isEmpty
                  ? Center(child: Text('No students found', style: TextStyle(fontSize: 13, color: Colors.grey.shade400)))
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
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 48,
                                    child: Text('${i + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                  ),
                                  SizedBox(
                                    width: 80,
                                    child: Text(s.stuadmno, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
                                  ),
                                  Expanded(
                                    child: Text(s.stuname, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                                  ),
                                  SizedBox(
                                    width: 60,
                                    child: Text(s.stugender, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                  ),
                                  SizedBox(
                                    width: 40,
                                    child: Icon(Icons.chevron_right_rounded, size: 18, color: color.withValues(alpha: 0.7)),
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _selectedStudent = null;
                  _demands = [];
                  _payments = [];
                  _parent = null;
                }),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                color: AppColors.accent,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                tooltip: 'Back to student list',
              ),
              const SizedBox(width: 8),
              CircleAvatar(
                radius: 20,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                backgroundImage: (s.stuphoto ?? '').startsWith('http') ? NetworkImage(s.stuphoto!) : null,
                child: (s.stuphoto ?? '').startsWith('http')
                    ? null
                    : Text(s.stuname[0].toUpperCase(),
                        style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700, fontSize: 14)),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(s.stuname, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    Text('Adm: ${s.stuadmno}  •  Class ${s.stuclass}  •  Father: $fatherName',
                        style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              if (!_loadingLedger) ...[
                _chip('Demand', '₹${_totalDemand.toStringAsFixed(0)}', AppColors.textPrimary),
                const SizedBox(width: 8),
                _chip('Paid', '₹${_totalPaid.toStringAsFixed(0)}', Colors.green.shade700),
                const SizedBox(width: 8),
                _chip('Pending', '₹${_totalPending.toStringAsFixed(0)}', AppColors.error),
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
          color: const Color(0xFF1E2532),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: const Row(
            children: [
              SizedBox(width: 100, child: _TH('DATE')),
              SizedBox(width: 110, child: _TH('DOC.NO')),
              SizedBox(width: 90,  child: _TH('TERM')),
              Expanded(            child: _TH('FEE TYPE')),
              SizedBox(width: 110, child: _TH('REFERENCE')),
              SizedBox(width: 100, child: _TH('DEBIT', align: TextAlign.right)),
              SizedBox(width: 100, child: _TH('CREDIT', align: TextAlign.right)),
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
                            Icon(Icons.receipt_long_outlined, size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 12),
                            Text('No fee demands found for this student',
                                style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100,
                            child: Text(_fmt(r['date'] as String),
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(r['docno'] as String,
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isDemand ? AppColors.accent : Colors.green.shade700)),
                          ),
                          SizedBox(
                            width: 90,
                            child: Text(r['term'] as String,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                          ),
                          Expanded(
                            child: Row(
                              children: [
                                Container(
                                  width: 6, height: 6,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: isDemand ? AppColors.error.withValues(alpha: 0.7) : Colors.green.shade400,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                Expanded(
                                  child: Text(r['feetype'] as String,
                                      style: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
                                      overflow: TextOverflow.ellipsis),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(
                            width: 110,
                            child: Text(r['reference'] as String,
                                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              debit > 0 ? '₹${debit.toStringAsFixed(0)}' : '-',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: debit > 0 ? AppColors.error : AppColors.textSecondary),
                            ),
                          ),
                          SizedBox(
                            width: 100,
                            child: Text(
                              credit > 0 ? '₹${credit.toStringAsFixed(0)}' : '-',
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                  fontSize: 12,
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
          borderRadius: const BorderRadius.only(
              bottomLeft: Radius.circular(12), bottomRight: Radius.circular(12)),
          child: Column(
            children: [
              // Total row — same dark bg as header
              Container(
                color: const Color(0xFF1E2532),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    const SizedBox(width: 100),
                    const SizedBox(width: 110),
                    const SizedBox(width: 90),
                    const Expanded(
                      child: Text('TOTAL',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: Colors.white70, letterSpacing: 0.5)),
                    ),
                    const SizedBox(width: 110),
                    SizedBox(
                      width: 100,
                      child: Text('₹${totalDebit.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: Color(0xFFFF6B6B))),
                    ),
                    SizedBox(
                      width: 100,
                      child: Text('₹${totalCredit.toStringAsFixed(0)}',
                          textAlign: TextAlign.right,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                              color: Color(0xFF4ADE80))),
                    ),
                  ],
                ),
              ),
              // Closing Balance row — slightly lighter dark
              Container(
                color: const Color(0xFF252D3D),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                child: Row(
                  children: [
                    const SizedBox(width: 100),
                    const SizedBox(width: 110),
                    const SizedBox(width: 90),
                    const Expanded(
                      child: Text('CLOSING BALANCE',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                              color: Colors.white70, letterSpacing: 0.5)),
                    ),
                    const SizedBox(width: 110),
                    SizedBox(
                      width: 200,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: closingBalance <= 0
                                ? const Color(0xFF4ADE80).withValues(alpha: 0.15)
                                : const Color(0xFFFF6B6B).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                                color: closingBalance <= 0
                                    ? const Color(0xFF4ADE80).withValues(alpha: 0.4)
                                    : const Color(0xFFFF6B6B).withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            closingBalance <= 0
                                ? '₹${closingBalance.abs().toStringAsFixed(0)}  Advance'
                                : '₹${closingBalance.toStringAsFixed(0)}  Due',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: closingBalance <= 0
                                    ? const Color(0xFF4ADE80)
                                    : const Color(0xFFFF6B6B)),
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


  Widget _chip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8), border: Border.all(color: color.withValues(alpha: 0.2))),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7))),
        Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }


  Widget _emptyState(IconData icon, String msg) => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 48, color: Colors.grey.shade300),
      const SizedBox(height: 12),
      Text(msg, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
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
      Text(text, textAlign: align, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70));
}

