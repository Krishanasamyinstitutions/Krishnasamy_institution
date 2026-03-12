import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

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
  const StudentFeeCollectionScreen({super.key});

  @override
  State<StudentFeeCollectionScreen> createState() =>
      _StudentFeeCollectionScreenState();
}

class _StudentFeeCollectionScreenState
    extends State<StudentFeeCollectionScreen> {
  final _admNoController = TextEditingController();
  final _remarksController = TextEditingController();

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

  @override
  void dispose() {
    _admNoController.dispose();
    _remarksController.dispose();
    for (final c in _fineCtrl.values) c.dispose();
    for (final c in _conCtrl.values) c.dispose();
    super.dispose();
  }

  void _clear() {
    for (final c in _fineCtrl.values) c.dispose();
    for (final c in _conCtrl.values) c.dispose();
    _fineCtrl.clear();
    _conCtrl.clear();
    setState(() {
      _admNoController.clear();
      _remarksController.clear();
      _student = null;
      _parent = null;
      _allDemands = [];
      _errorMsg = null;
      _selectedTerm = null;
      _selected.clear();
      _paymentMode = 'Cash';
    });
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
      final studentRows = await SupabaseService.client
          .from('students')
          .select('stu_id, stuname, stuadmno, stuclass, stugender, stumobile, stuphoto')
          .eq('ins_id', insId)
          .eq('stuadmno', admNo)
          .eq('activestatus', 1)
          .limit(1);

      if ((studentRows as List).isEmpty) {
        setState(() {
          _errorMsg = 'No student found with admission no "$admNo"';
          _searching = false;
        });
        return;
      }

      final student = Map<String, dynamic>.from(studentRows.first as Map);
      final stuId = student['stu_id'] as int;

      setState(() {
        _student = student;
        _searching = false;
        _loadingDemands = true;
      });

      // Fetch parent and demands in parallel
      final parentFuture = SupabaseService.getStudentParent(stuId);
      final demandsFuture = SupabaseService.client
          .from('feedemand')
          .select(
              'dem_id, demfeetype, demfeeterm, feeamount, conamount, balancedue, duedate, paidstatus, stuclass, demconcategory')
          .eq('ins_id', insId)
          .eq('stuadmno', admNo)
          .eq('paidstatus', 'U')
          .order('duedate', ascending: true);

      final parent = await parentFuture;
      final demandList =
          List<Map<String, dynamic>>.from((await demandsFuture) as List);

      // Sort by term order
      demandList.sort((a, b) => _termIndex(a['demfeeterm']?.toString() ?? '')
          .compareTo(_termIndex(b['demfeeterm']?.toString() ?? '')));

      // Create per-row controllers
      for (final d in demandList) {
        final key = d['dem_id']?.toString() ?? '';
        if (key.isNotEmpty) {
          _fineCtrl[key] = TextEditingController();
          _conCtrl[key] = TextEditingController();
        }
      }

      setState(() {
        _parent = parent;
        _allDemands = demandList;
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
    return bal + _fine(key) - _con(key);
  }

  double get _totalNetSelected {
    return _selected.fold(0.0, (sum, key) {
      final d = _allDemands.firstWhere(
          (x) => _demKey(x) == key,
          orElse: () => {});
      if (d.isEmpty) return sum;
      return sum + _netAmt(d);
    });
  }

  String get _studentCategory {
    if (_allDemands.isNotEmpty) {
      return _allDemands.first['demconcategory']?.toString() ?? 'GENERAL';
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header
        Row(
          children: [
            const Icon(Icons.payments_rounded, color: AppColors.accent, size: 22),
            const SizedBox(width: 10),
            Text('Fee Collection',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    )),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _clear,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Clear'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textSecondary,
                side: BorderSide(color: AppColors.border),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                textStyle: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Body
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Left Panel ──
              SizedBox(
                width: 300,
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _buildStudentLookup(),
                      if (_student != null) ...[
                        const SizedBox(height: 12),
                        _buildStudentCard(),
                        const SizedBox(height: 12),
                        _buildTermFilter(),
                        const SizedBox(height: 12),
                        _buildPaymentDetails(),
                      ],
                    ],
                  ),
                ),
              ),

              const SizedBox(width: 16),

              // ── Right Panel ──
              Expanded(child: _buildDemandsPanel()),
            ],
          ),
        ),
      ],
    );
  }

  // ── Student Lookup ──
  Widget _buildStudentLookup() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Student Lookup',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _admNoController,
                  onSubmitted: (_) => _search(),
                  decoration: _inputDec('Admission No'),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                width: 46,
                child: ElevatedButton(
                  onPressed: _searching ? null : _search,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: EdgeInsets.zero,
                  ),
                  child: _searching
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.search_rounded, size: 20),
                ),
              ),
            ],
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(_errorMsg!,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.error)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Student Card ──
  Widget _buildStudentCard() {
    final name = _student!['stuname']?.toString() ?? '-';
    final admNo = _student!['stuadmno']?.toString() ?? '-';
    final className = _student!['stuclass']?.toString() ?? '-';
    final photo = _student!['stuphoto']?.toString() ?? '';
    final fatherName = _parent?['fathername']?.toString() ?? '-';

    return _card(
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: AppColors.accent.withValues(alpha: 0.12),
                backgroundImage:
                    photo.startsWith('http') ? NetworkImage(photo) : null,
                child: photo.startsWith('http')
                    ? null
                    : Text(
                        name[0].toUpperCase(),
                        style: const TextStyle(
                            color: AppColors.accent,
                            fontWeight: FontWeight.w700,
                            fontSize: 18),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('Adm No: $admNo',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),
          _detailRow(Icons.person_outline_rounded, 'Father', fatherName),
          const SizedBox(height: 8),
          _detailRow(Icons.school_outlined, 'Class', className),
          const SizedBox(height: 8),
          _detailRow(
              Icons.group_outlined, 'Category', _studentCategory),
        ],
      ),
    );
  }

  // ── Term Filter ──
  Widget _buildTermFilter() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filter by Term',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _termChip('All', _selectedTerm == null, () {
                setState(() => _selectedTerm = null);
              }),
              ..._terms.map((t) => _termChip(t, _selectedTerm == t, () {
                    setState(() => _selectedTerm = t);
                  })),
            ],
          ),
        ],
      ),
    );
  }

  // ── Payment Details ──
  Widget _buildPaymentDetails() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Payment Details',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textPrimary,
                  )),
          const SizedBox(height: 10),
          Text('Payment Mode',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: ['Cash', 'Bank', 'Online', 'Cheque'].map((mode) {
              final sel = _paymentMode == mode;
              return GestureDetector(
                onTap: () => setState(() => _paymentMode = mode),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel
                        ? AppColors.accent
                        : AppColors.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: sel
                            ? AppColors.accent
                            : AppColors.border),
                  ),
                  child: Text(mode,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: sel
                              ? Colors.white
                              : AppColors.textSecondary)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Text('Remarks',
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          TextField(
            controller: _remarksController,
            maxLines: 2,
            decoration: _inputDec('Optional remarks...'),
            style: const TextStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ── Demands Panel ──
  Widget _buildDemandsPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Panel header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: AppColors.border)),
            ),
            child: Row(
              children: [
                Text('Pending Fee Demands',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        )),
                if (_allDemands.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${_filteredDemands.length} of ${_allDemands.length} items',
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w600),
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
                size: 52, color: Colors.grey.shade300),
            const SizedBox(height: 12),
            Text('Search a student to view pending fees',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade400)),
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
                size: 52, color: Colors.green.shade300),
            const SizedBox(height: 12),
            Text('No pending fee demands',
                style:
                    TextStyle(fontSize: 13, color: Colors.grey.shade500)),
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
          color: const Color(0xFF1E2532),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 32,
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
                ),
              ),
              const _THCell('Term', flex: 2),
              const _THCell('Fee Type', flex: 3),
              const _THCell('Due Date', flex: 2),
              const _THCell('Fee Amt', flex: 2),
              const _THCell('Bal. Amt', flex: 2),
              const _THCell('Fine', flex: 2),
              const _THCell('Con/Refund', flex: 2),
              const _THCell('Net Amt', flex: 2),
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
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    SizedBox(
                      width: 32,
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
                      ),
                    ),
                    _TDCell(d['demfeeterm']?.toString() ?? '-',
                        flex: 2,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary)),
                    _TDCell(d['demfeetype']?.toString() ?? '-',
                        flex: 3,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                    _TDCell(shortDate,
                        flex: 2,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary)),
                    _TDCell(feeAmt.toStringAsFixed(2),
                        flex: 2,
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textPrimary)),
                    _TDCell(bal.toStringAsFixed(2),
                        flex: 2,
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFFE87722))),
                    // Fine editable
                    Expanded(
                      flex: 2,
                      child: _numField(_fineCtrl[key], () => setState(() {})),
                    ),
                    // Con/Refund editable
                    Expanded(
                      flex: 2,
                      child:
                          _numField(_conCtrl[key], () => setState(() {})),
                    ),
                    // Net Amt
                    Expanded(
                      flex: 2,
                      child: Text(
                        netAmt.toStringAsFixed(2),
                        style: TextStyle(
                            fontSize: 12,
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
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.border)),
            borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(12),
                bottomRight: Radius.circular(12)),
          ),
          child: Row(
            children: [
              Text(
                '${_selected.length} of ${demands.length} selected',
                style: const TextStyle(
                    fontSize: 12, color: AppColors.textSecondary),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('Net Amount: ',
                        style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary)),
                    Text(
                      'Rs.${_totalNetSelected.toStringAsFixed(2)}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: AppColors.accent),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed:
                    _selected.isEmpty ? null : _onCollectAndReceipt,
                icon: const Icon(Icons.receipt_long_rounded, size: 16),
                label: const Text('Collect & Receipt'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.grey.shade200,
                  disabledForegroundColor: AppColors.textSecondary,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  textStyle: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _onCollectAndReceipt() {
    final totalNet = _totalNetSelected;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirm Collection',
            style:
                TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Student: ${_student!['stuname']} (${_student!['stuadmno']})'),
            const SizedBox(height: 6),
            Text('Demands selected: ${_selected.length}'),
            Text(
                'Payment Mode: $_paymentMode'),
            const SizedBox(height: 6),
            Text(
              'Total: Rs.${totalNet.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: AppColors.accent),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  // ── Helpers ──

  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  InputDecoration _inputDec(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          const TextStyle(fontSize: 13, color: AppColors.textLight),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide:
              const BorderSide(color: AppColors.accent, width: 1.5)),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 8),
        Text('$label  ',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary)),
        Expanded(
          child: Text(value,
              style: const TextStyle(
                  fontSize: 12,
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
            const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.accent : AppColors.surface,
          borderRadius: BorderRadius.circular(20),
          border:
              Border.all(color: selected ? AppColors.accent : AppColors.border),
        ),
        child: Text(label,
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: selected ? Colors.white : AppColors.textSecondary)),
      ),
    );
  }

  Widget _numField(TextEditingController? ctrl, VoidCallback onChange) {
    if (ctrl == null) return const SizedBox();
    return SizedBox(
      height: 32,
      child: TextField(
        controller: ctrl,
        onChanged: (_) => onChange(),
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
        ],
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: '0',
          hintStyle: const TextStyle(
              fontSize: 12, color: AppColors.textLight),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppColors.border)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(color: AppColors.border)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
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
  const _THCell(this.text, {this.flex = 1});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70)),
    );
  }
}

class _TDCell extends StatelessWidget {
  final String text;
  final int flex;
  final TextStyle? style;
  const _TDCell(this.text, {this.flex = 1, this.style});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: style ??
              const TextStyle(fontSize: 12, color: AppColors.textSecondary),
          overflow: TextOverflow.ellipsis),
    );
  }
}
