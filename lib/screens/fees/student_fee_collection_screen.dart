import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:webview_windows/webview_windows.dart';
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
  final _nameController = TextEditingController();
  final _classController = TextEditingController();
  final _remarksController = TextEditingController();
  final _chequeNoController = TextEditingController();
  final _chequeDateController = TextEditingController();
  final _bankNameController = TextEditingController();
  DateTime? _chequeDate;
  List<Map<String, dynamic>> _studentSuggestions = [];

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
    _nameController.dispose();
    _classController.dispose();
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
      _nameController.clear();
      _classController.clear();
      _remarksController.clear();
      _studentSuggestions = [];
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
      final rows = await SupabaseService.client
          .from('students')
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
    setState(() => _studentSuggestions = []);
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

      _nameController.text = student['stuname']?.toString() ?? '';
      _classController.text = student['stuclass']?.toString() ?? '';

      setState(() {
        _student = student;
        _searching = false;
        _loadingDemands = true;
        _studentSuggestions = [];
      });

      // Fetch parent and demands in parallel
      final parentFuture = SupabaseService.getStudentParent(stuId, stuadmno: admNo);
      final demandsFuture = SupabaseService.client
          .from('feedemand')
          .select(
              'dem_id, yr_id, demfeeyear, demfeetype, demfeeterm, feeamount, conamount, balancedue, paidamount, duedate, paidstatus, stuclass')
          .eq('ins_id', insId)
          .eq('stuadmno', admNo)
          .eq('paidstatus', 'U')
          .gt('balancedue', 0)
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
      return 'GENERAL';
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
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: _inputDec('Student Name'),
            onChanged: _searchByName,
          ),
          if (_studentSuggestions.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
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
                    title: Text(s['stuname']?.toString() ?? '', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Adm: ${s['stuadmno']} • Class: ${s['stuclass']}', style: const TextStyle(fontSize: 11)),
                    onTap: () => _selectSuggestion(s),
                  );
                },
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _classController,
            decoration: _inputDec('Class'),
            readOnly: true,
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
          DropdownButtonFormField<String?>(
            value: _selectedTerm,
            isExpanded: true,
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
            ),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('All', style: TextStyle(fontSize: 13))),
              ..._terms.map((t) => DropdownMenuItem<String?>(value: t, child: Text(t, style: const TextStyle(fontSize: 13)))),
            ],
            onChanged: (v) => setState(() => _selectedTerm = v),
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
            children: ['Cash', 'Online', 'Cheque', 'Sponsor'].map((mode) {
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
          if (_paymentMode == 'Cheque') ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cheque No *', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _chequeNoController,
                        decoration: InputDecoration(
                          hintText: 'Enter cheque number',
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Cheque Date *', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _chequeDateController,
                        readOnly: true,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) {
                            _chequeDate = picked;
                            _chequeDateController.text = '${picked.day.toString().padLeft(2, '0')}/${picked.month.toString().padLeft(2, '0')}/${picked.year}';
                          }
                        },
                        decoration: InputDecoration(
                          hintText: 'DD/MM/YYYY',
                          suffixIcon: const Icon(Icons.calendar_today, size: 16),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                          isDense: true,
                        ),
                        style: const TextStyle(fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text('Bank Name *', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextField(
              controller: _bankNameController,
              decoration: InputDecoration(
                hintText: 'Enter bank name',
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                isDense: true,
              ),
              style: const TextStyle(fontSize: 13),
            ),
          ],
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

  bool _processing = false;

  void _onCollectAndReceipt() {
    if (_paymentMode == 'Cheque') {
      if (_chequeNoController.text.trim().isEmpty ||
          _chequeDateController.text.trim().isEmpty ||
          _bankNameController.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please fill Cheque No, Cheque Date and Bank Name'), backgroundColor: Colors.red),
        );
        return;
      }
    }
    final totalNet = _totalNetSelected;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirm Collection',
            style:
                TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                'Student: ${_student!['stuname']} (${_student!['stuadmno']})',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text('Demands selected: ${_selected.length}',
                style: const TextStyle(fontSize: 16)),
            Text('Payment Mode: $_paymentMode',
                style: const TextStyle(fontSize: 16)),
            const SizedBox(height: 8),
            Text(
              'Total: Rs.${totalNet.toStringAsFixed(2)}',
              style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 18,
                  color: AppColors.accent),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel', style: TextStyle(fontSize: 15))),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _processPayment();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
            child: const Text('Confirm', style: TextStyle(fontSize: 15)),
          ),
        ],
      ),
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

  // ── Generate payment number helper ──
  Future<String> _generatePayNumber() async {
    try {
      final rpcResult = await SupabaseService.client.rpc('generate_payment_number');
      return rpcResult as String;
    } catch (_) {
      final sequence = await SupabaseService.client
          .from('sequence')
          .select('seq_id, sequid, seqwidth, seqcurno')
          .limit(1)
          .single();
      final sequid = sequence['sequid'] as String;
      final seqWidth = sequence['seqwidth'] as int;
      final seqCurNo = (sequence['seqcurno'] as num).toInt();
      final newSeqNo = seqCurNo + 1;
      final prefix = sequid.replaceAll(RegExp(r'\d+$'), '');
      final payNumber = '$prefix${newSeqNo.toString().padLeft(seqWidth, '0')}';
      await SupabaseService.client.from('sequence').update({
        'seqcurno': newSeqNo,
      }).eq('seq_id', sequence['seq_id'] as int);
      return payNumber;
    }
  }

  // ── Create paymentdetails + update feedemand ──
  Future<void> _createPaymentDetailsAndUpdateFees(int payId, int? insId) async {
    final payDetailRows = <Map<String, dynamic>>[];
    final feedemandUpdates = <Future>[];

    for (final key in _selected) {
      final d = _allDemands.firstWhere((x) => _demKey(x) == key, orElse: () => {});
      if (d.isEmpty) continue;

      final demId = d['dem_id'] as int;
      final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
      final fine = _fine(key);
      final con = _con(key);
      final net = bal + fine - con;

      payDetailRows.add({
        'pay_id': payId,
        'dem_id': demId,
        'yr_id': d['yr_id'],
        'yrlabel': d['demfeeyear']?.toString() ?? '',
        'ins_id': insId,
        'transcurrency': 'INR',
        'transtotalamount': net,
      });

      final currentPaid = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final newPaid = currentPaid + net;
      final newBalance = bal - net + fine;

      feedemandUpdates.add(
        SupabaseService.client.from('feedemand').update({
          'paidamount': newPaid,
          'balancedue': newBalance <= 0 ? 0 : newBalance,
          'paidstatus': newBalance <= 0 ? 'P' : 'U',
          'pay_id': payId,
        }).eq('dem_id', demId),
      );
    }

    await Future.wait([
      SupabaseService.client.from('paymentdetails').insert(payDetailRows),
      ...feedemandUpdates,
    ]);
  }

  // ── Show success dialog ──
  void _showSuccessDialog(String payNumber, double totalNet) {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.success, size: 56),
            const SizedBox(height: 12),
            const Text('Payment Successful', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('Receipt No: $payNumber', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
            Text('Amount: Rs.${totalNet.toStringAsFixed(2)}', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.accent)),
            Text('Mode: $_paymentMode', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ── Direct payment (Cash / Bank / Cheque) ──
  Future<void> _processDirectPayment() async {
    setState(() => _processing = true);

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final inscode = auth.currentUser?.inscode ?? '';
    final createdBy = auth.currentUser?.usename ?? '';
    final stuId = _student!['stu_id'] as int;
    final totalNet = _totalNetSelected;

    int? payId;

    try {
      final firstDemand = _allDemands.firstWhere((d) => _selected.contains(_demKey(d)));
      final yrId = firstDemand['yr_id'] as int?;
      final yrlabel = firstDemand['demfeeyear']?.toString() ?? '';

      final payData = <String, dynamic>{
        'ins_id': insId,
        'inscode': inscode,
        'stu_id': stuId,
        'yr_id': yrId,
        'yrlabel': yrlabel,
        'transtotalamount': totalNet,
        'transcurrency': 'INR',
        'paydate': DateTime.now().toIso8601String(),
        'paystatus': 'I',
        'paymethod': _paymentMode.toLowerCase(),
        'payreference': '$_paymentMode collection by $createdBy',
        'createdby': createdBy,
      };

      if (_paymentMode == 'Cheque') {
        payData['paychequeno'] = _chequeNoController.text.trim();
        payData['paychequedate'] = _chequeDate != null
            ? '${_chequeDate!.year}-${_chequeDate!.month.toString().padLeft(2, '0')}-${_chequeDate!.day.toString().padLeft(2, '0')}'
            : null;
        payData['paybankname'] = _bankNameController.text.trim();
      }

      final payResponse = await SupabaseService.client.from('payment').insert(payData).select('pay_id').single();

      payId = payResponse['pay_id'] as int;

      await _createPaymentDetailsAndUpdateFees(payId, insId);

      final payNumber = await _generatePayNumber();
      await SupabaseService.client.from('payment').update({
        'paystatus': 'C',
        'paynumber': payNumber,
        'paydate': DateTime.now().toIso8601String(),
      }).eq('pay_id', payId);

      _showSuccessDialog(payNumber, totalNet);
    } catch (e) {
      if (payId != null) {
        try {
          final payNumber = await _generatePayNumber();
          await SupabaseService.client.from('payment').update({
            'paystatus': 'F',
            'paynumber': payNumber,
            'paydate': DateTime.now().toIso8601String(),
          }).eq('pay_id', payId);
        } catch (_) {}
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Payment failed: $e'), backgroundColor: Colors.red),
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

    int? payId;

    try {
      final firstDemand = _allDemands.firstWhere((d) => _selected.contains(_demKey(d)));
      final yrId = firstDemand['yr_id'] as int?;
      final yrlabel = firstDemand['demfeeyear']?.toString() ?? '';

      // 1. Create payment record with status 'I'
      final payResponse = await SupabaseService.client.from('payment').insert({
        'ins_id': insId,
        'inscode': inscode,
        'stu_id': stuId,
        'yr_id': yrId,
        'yrlabel': yrlabel,
        'transtotalamount': totalNet,
        'transcurrency': 'INR',
        'paydate': DateTime.now().toIso8601String(),
        'paystatus': 'I',
        'paymethod': 'razorpay',
        'createdby': createdBy,
      }).select('pay_id').single();

      payId = payResponse['pay_id'] as int;

      // 2. Create Razorpay order via edge function
      final orderResponse = await SupabaseService.client.functions.invoke(
        'create-razorpay-order',
        body: {
          'amount': amountInPaise,
          'currency': 'INR',
          'pay_id': payId,
          'receipt': 'PAY-$payId',
        },
      );

      final orderData = orderResponse.data as Map<String, dynamic>;
      final orderId = orderData['order_id'] as String;

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

      // Write temp HTML file for WebView
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/tbs_razorpay_checkout.html');
      await tempFile.writeAsString(html);

      // 4. Show WebView dialog with Razorpay checkout + polling
      if (mounted) {
        await _showRazorpayWebViewDialog(payId, insId, totalNet, tempFile.path);
      }
    } catch (e) {
      if (payId != null) {
        try {
          final payNumber = await _generatePayNumber();
          await SupabaseService.client.from('payment').update({
            'paystatus': 'F',
            'paynumber': payNumber,
            'paydate': DateTime.now().toIso8601String(),
          }).eq('pay_id', payId);
        } catch (_) {}
      }

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

  Future<void> _showRazorpayWebViewDialog(int payId, int? insId, double totalNet, String htmlPath) async {
    final completer = Completer<String?>(); // 'C', 'F', or null (cancelled)
    final webviewController = WebviewController();

    try {
      await webviewController.initialize();
      await webviewController.setBackgroundColor(Colors.white);
      await webviewController.loadUrl('file:///$htmlPath');
    } catch (e) {
      if (!completer.isCompleted) completer.complete(null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to open payment window: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }

    // Start polling for payment status
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final payRecord = await SupabaseService.client
            .from('payment')
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
          if (rpStatus == 'captured' || rpStatus == 'authorized') {
            timer.cancel();
            await SupabaseService.client.from('payment').update({
              'payreference': rpPaymentId,
            }).eq('pay_id', payId);
            if (!completer.isCompleted) completer.complete('C');
          } else if (rpStatus == 'failed') {
            timer.cancel();
            await SupabaseService.client.from('payment').update({
              'payreference': rpPaymentId,
            }).eq('pay_id', payId);
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          child: SizedBox(
            width: 500,
            height: 620,
            child: Column(
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    color: AppColors.accent,
                    borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.payment, color: Colors.white, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Razorpay Payment  -  Rs.${totalNet.toStringAsFixed(2)}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                        ),
                      ),
                      InkWell(
                        onTap: () {
                          _pollTimer?.cancel();
                          webviewController.dispose();
                          Navigator.pop(ctx);
                          if (!completer.isCompleted) completer.complete(null);
                        },
                        child: const Icon(Icons.close, color: Colors.white, size: 20),
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

    // Close dialog if still open
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
    webviewController.dispose();

    if (result == 'C') {
      await _createPaymentDetailsAndUpdateFees(payId, insId);
      final payNumber = await _generatePayNumber();
      await SupabaseService.client.from('payment').update({
        'paystatus': 'C',
        'paynumber': payNumber,
        'paydate': DateTime.now().toIso8601String(),
      }).eq('pay_id', payId);
      _showSuccessDialog(payNumber, totalNet);
    } else if (result == 'F') {
      final payNumber = await _generatePayNumber();
      await SupabaseService.client.from('payment').update({
        'paystatus': 'F',
        'paynumber': payNumber,
        'paydate': DateTime.now().toIso8601String(),
      }).eq('pay_id', payId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Online payment failed'), backgroundColor: Colors.red),
        );
      }
    } else {
      try {
        final payNumber = await _generatePayNumber();
        await SupabaseService.client.from('payment').update({
          'paystatus': 'F',
          'paynumber': payNumber,
          'paydate': DateTime.now().toIso8601String(),
        }).eq('pay_id', payId);
      } catch (_) {}
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment cancelled'), backgroundColor: Colors.orange),
        );
      }
    }
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
