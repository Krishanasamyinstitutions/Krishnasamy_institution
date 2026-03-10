import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class FeeDemandScreen extends StatefulWidget {
  const FeeDemandScreen({super.key});

  @override
  State<FeeDemandScreen> createState() => _FeeDemandScreenState();
}

class _FeeDemandScreenState extends State<FeeDemandScreen> {
  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _admNoController = TextEditingController();
  final _feeAmountController = TextEditingController();
  final _conAmountController = TextEditingController();
  final _balanceDueController = TextEditingController();
  DateTime? _dueDate;

  String? _selectedClass;
  String? _selectedFeeType;
  String? _selectedFeeYear;
  final _feeTermController = TextEditingController();
  String? _selectedConcessionCategory;
  String? _selectedConcession;
  List<String> _classes = [];
  List<String> _feeTypes = [];
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _concessions = [];
  List<String> _concessionList = [];

  bool _isLoading = false;
  bool _isSaving = false;

  // Import state
  bool _showImport = false;
  String? _fileName;
  List<String> _headers = [];
  List<List<dynamic>> _rows = [];
  List<String?> _mappings = [];
  int _importStep = 0; // 0=pick, 1=map, 2=importing, 3=done
  int _imported = 0;
  int _skipped = 0;
  int _total = 0;
  List<String> _importErrors = [];
  String? _errorMsg;

  // Fee demand list
  List<Map<String, dynamic>> _classSummary = [];
  bool _loadingDemands = false;
  String? _drilldownClass;
  List<Map<String, dynamic>> _drilldownDemands = [];
  bool _loadingDrilldown = false;
  String? _drilldownStudent; // selected student adm no for 3rd level

  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _importFieldKeys = [
    'stuadmno',
    'stuclass',
    'demfeetype',
    'yr_id',
    'demfeeterm',
    'demconcategory',
    'con_id',
    'feeamount',
    'conamount',
    'balancedue',
    'duedate',
  ];

  static const Map<String, String> _importFieldLabels = {
    'stuadmno': 'Admission No',
    'stuclass': 'Class',
    'demfeetype': 'Fee Type',
    'yr_id': 'Fee Year',
    'demfeeterm': 'Fee Term',
    'demconcategory': 'Category',
    'con_id': 'Concession',
    'feeamount': 'Fee Amount',
    'conamount': 'Concession Amount',
    'balancedue': 'Balance Due',
    'duedate': 'Due Date',
  };

  static const _requiredFields = {'stuadmno', 'demfeetype', 'feeamount'};

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
    _loadFeeDemands();
  }

  @override
  void dispose() {
    _admNoController.dispose();
    _feeAmountController.dispose();
    _conAmountController.dispose();
    _balanceDueController.dispose();
    _feeTermController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        SupabaseService.getClasses(insId),
        SupabaseService.getYears(insId),
        SupabaseService.getConcessions(insId),
        SupabaseService.getFeeTypes(insId),
      ]);

      if (!mounted) return;
      setState(() {
        _classes = results[0] as List<String>;
        _years = results[1] as List<Map<String, dynamic>>;
        _concessions = results[2] as List<Map<String, dynamic>>;
        _concessionList = _concessions
            .map((c) => c['condesc']?.toString())
            .where((s) => s != null && s.isNotEmpty)
            .cast<String>()
            .toList();
        _feeTypes = results[3] as List<String>;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error loading dropdowns: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadFeeDemands() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _loadingDemands = true);
    try {
      final summary = await SupabaseService.getFeeDemandSummary(insId);
      if (mounted) {
        setState(() {
          _classSummary = summary;
          _loadingDemands = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading fee demands: $e');
      if (mounted) setState(() => _loadingDemands = false);
    }
  }

  Future<void> _loadDrilldown(String className) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() {
      _drilldownClass = className;
      _loadingDrilldown = true;
      _drilldownDemands = [];
    });
    try {
      final demands = await SupabaseService.getFeeDemandsByClass(insId, className);
      if (mounted) {
        setState(() {
          _drilldownDemands = demands;
          _loadingDrilldown = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading drilldown: $e');
      if (mounted) setState(() => _loadingDrilldown = false);
    }
  }

  Future<void> _saveDemand() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final inscode = auth.inscode;
    if (insId == null) return;

    setState(() => _isSaving = true);
    try {
      // Look up the year label for the selected yr_id
      String? yearLabel;
      if (_selectedFeeYear != null) {
        final yearEntry = _years.firstWhere(
          (y) => y['yr_id'].toString() == _selectedFeeYear,
          orElse: () => <String, dynamic>{},
        );
        yearLabel = yearEntry['yrlabel']?.toString();
      }

      final data = {
        'ins_id': insId,
        'inscode': inscode ?? '',
        'stuadmno': _admNoController.text.trim(),
        'stuclass': _selectedClass,
        'demfeetype': _selectedFeeType,
        'yr_id': _selectedFeeYear != null ? int.tryParse(_selectedFeeYear!) : null,
        'demfeeyear': yearLabel,
        'demfeeterm': _feeTermController.text.trim(),
        'demconcategory': _selectedConcessionCategory,
        'con_id': _selectedConcession != null ? int.tryParse(_selectedConcession!) : null,
        'feeamount': double.tryParse(_feeAmountController.text.trim()) ?? 0,
        'conamount': double.tryParse(_conAmountController.text.trim()) ?? 0,
        'balancedue': double.tryParse(_balanceDueController.text.trim()) ?? ((double.tryParse(_feeAmountController.text.trim()) ?? 0) - (double.tryParse(_conAmountController.text.trim()) ?? 0)),
        'duedate': _dueDate?.toIso8601String().split('T').first,
        'paidstatus': 'U',
        'paidamount': 0,
        'activestatus': 1,
        'createdat': DateTime.now().toIso8601String(),
        'createdby': auth.userName,
      };

      await SupabaseService.client.from('feedemand').insert(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fee demand saved successfully'), backgroundColor: AppColors.success),
        );
        _resetForm();
        _loadFeeDemands();
      }
    } catch (e) {
      debugPrint('Error saving fee demand: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _admNoController.clear();
    _feeAmountController.clear();
    _conAmountController.clear();
    _balanceDueController.clear();
    setState(() {
      _selectedClass = null;
      _selectedFeeType = null;
      _selectedFeeYear = null;
      _feeTermController.clear();
      _selectedConcessionCategory = null;
      _selectedConcession = null;
      _dueDate = null;
    });
  }

  Future<void> _pickDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) setState(() => _dueDate = picked);
  }

  // ─── Import Logic ───────────────────────────────────────────────────────

  static String? _autoMapHeader(String header) {
    final h = header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    const aliases = {
      'admissionno': 'stuadmno', 'admno': 'stuadmno', 'stuadmno': 'stuadmno', 'admissionnumber': 'stuadmno',
      'class': 'stuclass', 'stuclass': 'stuclass',
      'feetype': 'demfeetype', 'demfeetype': 'demfeetype', 'type': 'demfeetype',
      'feeyear': 'yr_id', 'yrid': 'yr_id', 'year': 'yr_id',
      'feeterm': 'demfeeterm', 'demfeeterm': 'demfeeterm', 'term': 'demfeeterm',
      'category': 'demconcategory', 'demconcategory': 'demconcategory',
      'concession': 'con_id', 'conid': 'con_id', 'concessioncategory': 'con_id', 'con': 'con_id',
      'feeamount': 'feeamount', 'amount': 'feeamount', 'fee': 'feeamount',
      'concessionamount': 'conamount', 'conamount': 'conamount', 'conamt': 'conamount',
      'balancedue': 'balancedue', 'balance': 'balancedue', 'baldue': 'balancedue',
      'duedate': 'duedate', 'due': 'duedate',
    };
    return aliases[h];
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    try {
      List<String> headers;
      List<List<dynamic>> rows;

      if (ext == 'csv') {
        final csvString = utf8.decode(file.bytes!);
        final parsed = const CsvToListConverter().convert(csvString);
        if (parsed.isEmpty) throw Exception('CSV file is empty');
        headers = parsed.first.map((e) => e.toString().trim()).toList();
        rows = parsed.skip(1).where((r) => r.any((c) => c.toString().trim().isNotEmpty)).toList();
      } else {
        final excel = xl.Excel.decodeBytes(file.bytes!);
        final sheetName = excel.tables.keys.first;
        final sheet = excel.tables[sheetName]!;
        if (sheet.rows.isEmpty) throw Exception('Excel file is empty');
        headers = sheet.rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
        rows = sheet.rows.skip(1)
            .where((r) => r.any((c) => c?.value != null && c!.value.toString().trim().isNotEmpty))
            .map((r) => r.map((c) => c?.value ?? '').toList())
            .toList();
      }

      final mappings = headers.map((h) => _autoMapHeader(h)).toList();

      setState(() {
        _fileName = file.name;
        _headers = headers;
        _rows = rows;
        _mappings = mappings;
        _importStep = 1;
        _errorMsg = null;
      });
    } catch (e) {
      setState(() => _errorMsg = 'Failed to parse file: $e');
    }
  }

  String? _validateRow(int rowIdx) {
    final row = _rows[rowIdx];
    final missing = <String>[];
    for (final reqKey in _requiredFields) {
      final colIdx = _mappings.indexOf(reqKey);
      if (colIdx < 0 || colIdx >= row.length || row[colIdx].toString().trim().isEmpty) {
        missing.add(_importFieldLabels[reqKey] ?? reqKey);
      }
    }
    if (missing.isEmpty) return null;
    return 'Missing: ${missing.join(', ')}';
  }

  String? _cellByKey(List<dynamic> row, String fieldKey) {
    final idx = _mappings.indexOf(fieldKey);
    if (idx < 0 || idx >= row.length) return null;
    final v = row[idx].toString().trim();
    return v.isEmpty ? null : v;
  }

  Future<void> _startImport() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;
    final now = DateTime.now().toIso8601String();

    setState(() {
      _importStep = 2;
      _imported = 0;
      _skipped = 0;
      _total = _rows.length;
      _importErrors = [];
    });

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final err = _validateRow(i);
      if (err != null) {
        setState(() {
          _skipped++;
          _importErrors.add('Row ${i + 2}: $err');
        });
        continue;
      }

      try {
        final feeAmount = double.tryParse(_cellByKey(row, 'feeamount') ?? '0') ?? 0;
        final conAmount = double.tryParse(_cellByKey(row, 'conamount') ?? '0') ?? 0;

        final yrRaw = _cellByKey(row, 'yr_id');
        int? yrId;
        String? yrLabel;

        // Try matching by yr_id (integer)
        final yrInt = int.tryParse(yrRaw ?? '');
        if (yrInt != null) {
          // Check if it's a yr_id
          final byId = _years.firstWhere(
            (y) => y['yr_id'] == yrInt,
            orElse: () => <String, dynamic>{},
          );
          if (byId.isNotEmpty) {
            yrId = yrInt;
            yrLabel = byId['yrlabel']?.toString();
          }
        }

        // If not found by id, try matching by label (e.g. "2025-2026")
        if (yrId == null && yrRaw != null) {
          final byLabel = _years.firstWhere(
            (y) => y['yrlabel']?.toString() == yrRaw,
            orElse: () => <String, dynamic>{},
          );
          if (byLabel.isNotEmpty) {
            yrId = byLabel['yr_id'] as int?;
            yrLabel = byLabel['yrlabel']?.toString();
          }
        }

        // Try partial match (e.g. "2025" matches "2025-2026")
        if (yrId == null && yrRaw != null) {
          final byPartial = _years.firstWhere(
            (y) => y['yrlabel']?.toString().startsWith(yrRaw) == true,
            orElse: () => <String, dynamic>{},
          );
          if (byPartial.isNotEmpty) {
            yrId = byPartial['yr_id'] as int?;
            yrLabel = byPartial['yrlabel']?.toString();
          }
        }

        final data = {
          'ins_id': insId,
          'inscode': auth.inscode ?? '',
          'stuadmno': _cellByKey(row, 'stuadmno'),
          'stuclass': _cellByKey(row, 'stuclass'),
          'demfeetype': _cellByKey(row, 'demfeetype'),
          'yr_id': yrId,
          'demfeeyear': yrLabel ?? yrRaw ?? '',
          'demfeeterm': _cellByKey(row, 'demfeeterm'),
          'demconcategory': _cellByKey(row, 'demconcategory'),
          'con_id': int.tryParse(_cellByKey(row, 'con_id') ?? ''),
          'feeamount': feeAmount,
          'conamount': conAmount,
          'balancedue': double.tryParse(_cellByKey(row, 'balancedue') ?? '') ?? (feeAmount - conAmount),
          'duedate': _cellByKey(row, 'duedate'),
          'paidstatus': 'U',
          'paidamount': 0,
          'activestatus': 1,
          'createdat': now,
          'createdby': auth.userName,
        };

        // Remove null values
        data.removeWhere((k, v) => v == null);

        // Duplicate check: Admission No + Fee Type + Fee Year + Fee Term
        final admNo = data['stuadmno']?.toString() ?? '';
        final feeType = data['demfeetype']?.toString() ?? '';
        final feeYear = data['demfeeyear']?.toString() ?? '';
        final feeTerm = data['demfeeterm']?.toString() ?? '';

        if (admNo.isNotEmpty && feeType.isNotEmpty) {
          var query = SupabaseService.client
              .from('feedemand')
              .select('dem_id')
              .eq('ins_id', insId)
              .eq('stuadmno', admNo)
              .eq('demfeetype', feeType);
          if (feeYear.isNotEmpty) query = query.eq('demfeeyear', feeYear);
          if (feeTerm.isNotEmpty) query = query.eq('demfeeterm', feeTerm);

          final existing = await query.maybeSingle();
          if (existing != null) {
            setState(() {
              _skipped++;
              _importErrors.add('Row ${i + 2}: Duplicate - $admNo / $feeType / $feeYear / $feeTerm already exists');
            });
            continue;
          }
        }

        await SupabaseService.client.from('feedemand').insert(data);
        setState(() => _imported++);
      } catch (e) {
        setState(() {
          _skipped++;
          _importErrors.add('Row ${i + 2}: $e');
        });
      }
    }

    setState(() => _importStep = 3);
    _loadFeeDemands();
  }

  void _resetImport() {
    setState(() {
      _showImport = false;
      _importStep = 0;
      _fileName = null;
      _headers = [];
      _rows = [];
      _mappings = [];
      _imported = 0;
      _skipped = 0;
      _total = 0;
      _importErrors = [];
      _errorMsg = null;
    });
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.request_page_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Text('Fee Demand', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _showImport = !_showImport;
                if (!_showImport) _resetImport();
              }),
              icon: Icon(_showImport ? Icons.close : Icons.upload_file_rounded, size: 18),
              label: Text(_showImport ? 'Close Import' : 'Import CSV/Excel'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _loadFeeDemands,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Expanded(
          child: _showImport ? _buildImportSection() : _buildMainContent(),
        ),
      ],
    );
  }

  Widget _buildMainContent() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Form
        SizedBox(
          width: 400,
          child: _buildForm(),
        ),
        const SizedBox(width: 16),
        // Right: Fee demands list
        Expanded(child: _buildDemandsList()),
      ],
    );
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.receipt_long_rounded, size: 18, color: AppColors.accent),
                        const SizedBox(width: 8),
                        const Text('Add Fee Demand', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Admission No
                    _buildLabel('Admission No *'),
                    TextFormField(
                      controller: _admNoController,
                      decoration: _inputDecoration('Enter admission number'),
                      style: const TextStyle(fontSize: 13),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),

                    // Class
                    _buildLabel('Class'),
                    DropdownButtonFormField<String>(
                      value: _selectedClass,
                      decoration: _inputDecoration('Select class'),
                      items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => _selectedClass = v),
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 16),

                    // Fee Type
                    _buildLabel('Fee Type *'),
                    DropdownButtonFormField<String>(
                      value: _selectedFeeType,
                      decoration: _inputDecoration('Select fee type'),
                      items: _feeTypes.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                      onChanged: (v) => setState(() => _selectedFeeType = v),
                      validator: (v) => v == null ? 'Required' : null,
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 16),

                    // Fee Year & Fee Term (side by side)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Fee Year'),
                              DropdownButtonFormField<String>(
                                value: _selectedFeeYear,
                                decoration: _inputDecoration('Select year'),
                                items: _years.map((y) => DropdownMenuItem(value: y['yr_id'].toString(), child: Text(y['yrlabel']?.toString() ?? '-'))).toList(),
                                onChanged: (v) => setState(() => _selectedFeeYear = v),
                                style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Fee Term'),
                              TextFormField(
                                controller: _feeTermController,
                                decoration: _inputDecoration('Enter term'),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Category
                    _buildLabel('Category'),
                    DropdownButtonFormField<String>(
                      value: _selectedConcessionCategory,
                      decoration: _inputDecoration('Select category'),
                      items: const [
                        DropdownMenuItem(value: 'General', child: Text('General')),
                        DropdownMenuItem(value: 'Concession', child: Text('Concession')),
                      ],
                      onChanged: (v) => setState(() => _selectedConcessionCategory = v),
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 16),

                    // Concession
                    _buildLabel('Concession'),
                    DropdownButtonFormField<String>(
                      value: _selectedConcession,
                      decoration: _inputDecoration('Select concession'),
                      items: _concessions.map((c) => DropdownMenuItem(value: c['con_id'].toString(), child: Text(c['condesc']?.toString() ?? '-'))).toList(),
                      onChanged: (v) => setState(() => _selectedConcession = v),
                      style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 16),

                    // Fee Amount & Concession Amount (side by side)
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Fee Amount *'),
                              TextFormField(
                                controller: _feeAmountController,
                                decoration: _inputDecoration('Enter amount'),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Concession Amount'),
                              TextFormField(
                                controller: _conAmountController,
                                decoration: _inputDecoration('Enter amount'),
                                keyboardType: TextInputType.number,
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // Balance Due
                    _buildLabel('Balance Due'),
                    TextFormField(
                      controller: _balanceDueController,
                      decoration: _inputDecoration('Enter balance due'),
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Due Date
                    _buildLabel('Due Date'),
                    InkWell(
                      onTap: _pickDueDate,
                      borderRadius: BorderRadius.circular(10),
                      child: InputDecorator(
                        decoration: _inputDecoration('').copyWith(
                          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.textSecondary),
                        ),
                        child: Text(
                          _dueDate != null
                              ? '${_dueDate!.day.toString().padLeft(2, '0')}/${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.year}'
                              : 'Select date',
                          style: TextStyle(fontSize: 13, color: _dueDate != null ? AppColors.textPrimary : Colors.grey.shade400),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: _resetForm,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                            child: const Text('Clear'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: _isSaving ? null : _saveDemand,
                            icon: _isSaving
                                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_rounded, size: 18),
                            label: Text(_isSaving ? 'Saving...' : 'Save Fee Demand', style: const TextStyle(fontWeight: FontWeight.w600)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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

  Widget _buildLabel(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      filled: true,
      fillColor: AppColors.surface,
    );
  }

  Widget _buildDemandsList() {
    return Column(
      children: [
        // Search field
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              if (_drilldownStudent != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _drilldownStudent = null;
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: Text('Class $_drilldownClass', style: const TextStyle(fontSize: 12)),
                )
              else if (_drilldownClass != null)
                TextButton.icon(
                  onPressed: () => setState(() {
                    _drilldownClass = null;
                    _drilldownDemands = [];
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                  icon: const Icon(Icons.arrow_back_rounded, size: 16),
                  label: const Text('All Classes', style: TextStyle(fontSize: 12)),
                ),
              if (_drilldownClass != null) const SizedBox(width: 8),
              Icon(Icons.list_alt_rounded, size: 18, color: AppColors.accent),
              const SizedBox(width: 8),
              Text(
                _drilldownStudent != null
                    ? 'Student $_drilldownStudent'
                    : _drilldownClass != null
                        ? 'Class $_drilldownClass'
                        : 'Fee Demands',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              SizedBox(
                width: 250,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search...',
                    hintStyle: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 16),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
                    filled: true,
                    fillColor: AppColors.surface,
                    isDense: true,
                  ),
                  style: const TextStyle(fontSize: 12),
                  onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _drilldownStudent != null
                    ? '${_filteredStudentDemands.length} records'
                    : _drilldownClass != null
                        ? '${_studentSummary.length} students'
                        : '${_classSummary.fold<int>(0, (sum, c) => sum + ((c['student_count'] as num?)?.toInt() ?? 0))} students',
                style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Content
        Expanded(
          child: _loadingDemands
              ? const Center(child: CircularProgressIndicator())
              : _drilldownStudent != null
                  ? _buildStudentFeeDetails()
                  : _drilldownClass != null
                      ? _buildDrilldownView()
                      : _buildClassCards(),
        ),
      ],
    );
  }

  List<Map<String, dynamic>> get _filteredClassSummary {
    if (_searchQuery.isEmpty) return _classSummary;
    return _classSummary.where((c) {
      final cls = c['stuclass']?.toString().toLowerCase() ?? '';
      return cls.contains(_searchQuery);
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredDrilldownDemands {
    final source = _drilldownDemands;
    if (_searchQuery.isEmpty) return source;
    return source.where((d) {
      final admNo = d['stuadmno']?.toString().toLowerCase() ?? '';
      final feeType = d['demfeetype']?.toString().toLowerCase() ?? '';
      final term = d['demfeeterm']?.toString().toLowerCase() ?? '';
      return admNo.contains(_searchQuery) || feeType.contains(_searchQuery) || term.contains(_searchQuery);
    }).toList();
  }

  /// Aggregate drilldown demands by student for the intermediate student-wise view
  List<Map<String, dynamic>> get _studentSummary {
    final Map<String, Map<String, dynamic>> grouped = {};
    for (final d in _drilldownDemands) {
      final admNo = d['stuadmno']?.toString() ?? '-';
      if (!grouped.containsKey(admNo)) {
        grouped[admNo] = {
          'stuadmno': admNo,
          'stuname': d['stuname'] ?? d['studentname'] ?? '',
          'total_demand': 0.0,
          'total_concession': 0.0,
          'total_paid': 0.0,
          'total_pending': 0.0,
          'demand_count': 0,
          'paid_count': 0,
          'unpaid_count': 0,
        };
      }
      final g = grouped[admNo]!;
      final amt = (d['feeamount'] as num?)?.toDouble() ?? 0;
      final con = (d['conamount'] as num?)?.toDouble() ?? 0;
      final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
      final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final status = d['paidstatus']?.toString() ?? 'U';
      g['total_demand'] = (g['total_demand'] as double) + amt;
      g['total_concession'] = (g['total_concession'] as double) + con;
      g['total_paid'] = (g['total_paid'] as double) + paid;
      g['total_pending'] = (g['total_pending'] as double) + bal;
      g['demand_count'] = (g['demand_count'] as int) + 1;
      if (status == 'Paid' || status == 'P') {
        g['paid_count'] = (g['paid_count'] as int) + 1;
      } else {
        g['unpaid_count'] = (g['unpaid_count'] as int) + 1;
      }
    }
    final list = grouped.values.toList();
    if (_searchQuery.isNotEmpty) {
      return list.where((s) {
        final admNo = s['stuadmno']?.toString().toLowerCase() ?? '';
        final name = s['stuname']?.toString().toLowerCase() ?? '';
        return admNo.contains(_searchQuery) || name.contains(_searchQuery);
      }).toList();
    }
    return list;
  }

  /// Fee demands for the selected student
  List<Map<String, dynamic>> get _filteredStudentDemands {
    if (_drilldownStudent == null) return [];
    final source = _drilldownDemands.where((d) => d['stuadmno']?.toString() == _drilldownStudent).toList();
    if (_searchQuery.isEmpty) return source;
    return source.where((d) {
      final feeType = d['demfeetype']?.toString().toLowerCase() ?? '';
      final term = d['demfeeterm']?.toString().toLowerCase() ?? '';
      return feeType.contains(_searchQuery) || term.contains(_searchQuery);
    }).toList();
  }

  Widget _buildClassCards() {
    final summaries = _filteredClassSummary;
    if (summaries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            const Text('No fee demands found', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 100, child: Text('Class', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(child: Text('Students', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                Expanded(child: Text('Total Demand', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                Expanded(child: Text('Collected', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                Expanded(child: Text('Pending', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                SizedBox(width: 32),
              ],
            ),
          ),
          const Divider(height: 1),
          // List rows
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: summaries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = summaries[i];
                final className = s['stuclass']?.toString() ?? '-';
                final studentCount = (s['student_count'] as num?)?.toInt() ?? 0;
                final totalDemand = (s['total_demand'] as num?)?.toDouble() ?? 0;
                final totalPaid = (s['total_paid'] as num?)?.toDouble() ?? 0;
                final totalPending = (s['total_pending'] as num?)?.toDouble() ?? 0;

                return InkWell(
                  onTap: () => _loadDrilldown(className),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text('Class $className', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.primary), textAlign: TextAlign.center),
                          ),
                        ),
                        Expanded(child: Text('$studentCount', style: const TextStyle(fontSize: 12), textAlign: TextAlign.center)),
                        Expanded(child: Text('₹${_formatAmount(totalDemand)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.right)),
                        Expanded(child: Text('₹${_formatAmount(totalPaid)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success), textAlign: TextAlign.right)),
                        Expanded(child: Text('₹${_formatAmount(totalPending)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.warning), textAlign: TextAlign.right)),
                        const SizedBox(width: 32, child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary)),
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

  String _formatAmount(double amount) {
    if (amount >= 100000) return '${(amount / 100000).toStringAsFixed(1)}L';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(0);
  }

  /// Level 2: Student-wise summary for selected class
  Widget _buildDrilldownView() {
    if (_loadingDrilldown) {
      return const Center(child: CircularProgressIndicator());
    }

    final students = _studentSummary;
    if (students.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty ? 'No matching students' : 'No students found',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 80, child: Text('Adm No', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(flex: 2, child: Text('Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700))),
                Expanded(child: Text('Demand', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                Expanded(child: Text('Paid', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                Expanded(child: Text('Pending', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.right)),
                SizedBox(width: 70, child: Text('Status', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700), textAlign: TextAlign.center)),
                SizedBox(width: 28),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: students.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final s = students[i];
                final admNo = s['stuadmno']?.toString() ?? '-';
                final name = s['stuname']?.toString() ?? '';
                final totalDemand = (s['total_demand'] as double?) ?? 0;
                final totalPaid = (s['total_paid'] as double?) ?? 0;
                final totalPending = (s['total_pending'] as double?) ?? 0;
                final unpaidCount = (s['unpaid_count'] as int?) ?? 0;
                final allPaid = unpaidCount == 0;

                return InkWell(
                  onTap: () => setState(() {
                    _drilldownStudent = admNo;
                    _searchQuery = '';
                    _searchController.clear();
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 80,
                          child: Text(admNo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                        Expanded(
                          flex: 2,
                          child: Text(
                            name.isNotEmpty ? name : '-',
                            style: const TextStyle(fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Expanded(
                          child: Text('₹${_formatAmount(totalDemand)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600), textAlign: TextAlign.right),
                        ),
                        Expanded(
                          child: Text('₹${_formatAmount(totalPaid)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.success), textAlign: TextAlign.right),
                        ),
                        Expanded(
                          child: Text('₹${_formatAmount(totalPending)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: totalPending > 0 ? AppColors.warning : AppColors.success), textAlign: TextAlign.right),
                        ),
                        SizedBox(
                          width: 70,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: allPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                allPaid ? 'Paid' : 'Unpaid',
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: allPaid ? AppColors.success : AppColors.warning),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 28, child: Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textSecondary)),
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

  /// Level 3: Individual fee details for selected student
  Widget _buildStudentFeeDetails() {
    final demands = _filteredStudentDemands;
    if (demands.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty ? 'No matching records' : 'No fee demands found',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(4),
      itemCount: demands.length,
      itemBuilder: (context, i) {
        final d = demands[i];
        final admNo = d['stuadmno']?.toString() ?? '-';
        final feeType = d['demfeetype']?.toString() ?? '-';
        final term = d['demfeeterm']?.toString() ?? '-';
        final amt = (d['feeamount'] as num?)?.toDouble() ?? 0;
        final con = (d['conamount'] as num?)?.toDouble() ?? 0;
        final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
        final status = d['paidstatus']?.toString() ?? 'U';
        final isPaid = status == 'Paid' || status == 'P';

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(admNo, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(feeType, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Term: $term', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                  ],
                ),
              ),
              Expanded(
                flex: 4,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        const Text('Amount', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text('₹${amt.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Concession', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text('₹${con.toStringAsFixed(0)}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                    Column(
                      children: [
                        const Text('Balance', style: TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                        const SizedBox(height: 2),
                        Text('₹${bal.toStringAsFixed(0)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: bal > 0 ? AppColors.warning : AppColors.success)),
                      ],
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isPaid ? 'Paid' : 'Unpaid',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : AppColors.warning),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── Import UI ──────────────────────────────────────────────────────────

  Widget _buildImportSection() {
    if (_importStep == 2) return _buildImportProgressStep();
    if (_importStep == 3) return _buildImportDoneStep();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title bar
          Row(
            children: [
              Icon(Icons.upload_file_rounded, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('Import Fee Demands', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_fileName != null)
                Text(_fileName!, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _pickFile,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('Browse'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _exportTemplate,
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text('Move to Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF217346),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 8),
            Text(_errorMsg!, style: const TextStyle(color: AppColors.error, fontSize: 12)),
          ],
          const SizedBox(height: 12),

          // Data grid
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  // Header row
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B2A4A),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(7),
                        topRight: Radius.circular(7),
                      ),
                    ),
                    child: Row(
                      children: [
                        _gridHeaderCell('S.No', width: 45, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Adm No *', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Class', flex: 1),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Fee Type *', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Year', flex: 1),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Term', flex: 1),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Category', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Concession', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Fee Amt *', flex: 2, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Con. Amt', flex: 2, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Bal. Due', flex: 2, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Due Date', flex: 2, center: true),
                      ],
                    ),
                  ),
                  // Data rows
                  Expanded(
                    child: _rows.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.grid_on_rounded, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                                const SizedBox(height: 8),
                                const Text('No data loaded', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                const SizedBox(height: 4),
                                const Text('Click Browse to load a CSV or Excel file', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final isEven = index % 2 == 0;
                              return Container(
                                decoration: BoxDecoration(
                                  color: isEven ? Colors.white : AppColors.surface,
                                  border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                                ),
                                child: Row(
                                  children: [
                                    _gridDataCell('${index + 1}', width: 45, center: true),
                                    _gridDataCell(_mappedCell(row, 'stuadmno'), flex: 2),
                                    _gridDataCell(_mappedCell(row, 'stuclass'), flex: 1),
                                    _gridDataCell(_mappedCell(row, 'demfeetype'), flex: 2),
                                    _gridDataCell(_mappedCell(row, 'yr_id'), flex: 1),
                                    _gridDataCell(_mappedCell(row, 'demfeeterm'), flex: 1),
                                    _gridDataCell(_mappedCell(row, 'demconcategory'), flex: 2),
                                    _gridDataCell(_mappedCell(row, 'con_id'), flex: 2),
                                    _gridDataCell(_mappedCell(row, 'feeamount'), flex: 2, center: true),
                                    _gridDataCell(_mappedCell(row, 'conamount'), flex: 2, center: true),
                                    _gridDataCell(_mappedCell(row, 'balancedue'), flex: 2, center: true),
                                    _gridDataCell(_mappedCell(row, 'duedate'), flex: 2, center: true),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Bottom bar with row count and action buttons
          Row(
            children: [
              Text(
                '${_rows.length} rows',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: _rows.isEmpty ? null : () => _validateImportData(),
                icon: const Icon(Icons.check_circle_outline, size: 16),
                label: const Text('Validate'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _rows.isNotEmpty && _mappings.contains('stuadmno') && _mappings.contains('feeamount') ? _startImport : null,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _resetImport,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _mappedCell(List<dynamic> row, String fieldKey) {
    final idx = _mappings.indexOf(fieldKey);
    if (idx < 0 || idx >= row.length) return '';
    return row[idx].toString().trim();
  }

  Widget _gridHeaderCell(String text, {double? width, int flex = 1, bool center = false}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
    );
    return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
  }

  Widget _gridHeaderDivider() {
    return Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.15));
  }

  Widget _gridDataCell(String text, {double? width, int flex = 1, bool center = false}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
    );
    return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
  }

  Future<void> _exportTemplate() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Fee Demands'];
    // Remove default Sheet1
    excel.delete('Sheet1');

    final headers = [
      'Admission No',
      'Class',
      'Fee Type',
      'Fee Year',
      'Fee Term',
      'Category',
      'Concession',
      'Fee Amount',
      'Concession Amount',
      'Balance Due',
      'Due Date',
    ];

    for (int i = 0; i < headers.length; i++) {
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).value = xl.TextCellValue(headers[i]);
    }

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Template',
        fileName: 'fee_demand_template.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (savePath == null) return;

      final bytes = excel.encode();
      if (bytes == null) return;
      await File(savePath).writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template exported successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  void _validateImportData() {
    final errors = <String>[];
    for (int i = 0; i < _rows.length; i++) {
      final err = _validateRow(i);
      if (err != null) errors.add('Row ${i + 2}: $err');
    }
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All rows are valid'), backgroundColor: AppColors.success),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('${errors.length} validation errors', style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 400,
            height: 250,
            child: ListView(
              children: errors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(e, style: const TextStyle(fontSize: 12, color: AppColors.error)),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Widget _buildImportProgressStep() {
    final progress = _total > 0 ? (_imported + _skipped) / _total : 0.0;
    return Center(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Importing... ${_imported + _skipped} / $_total', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, backgroundColor: AppColors.border, valueColor: const AlwaysStoppedAnimation(AppColors.accent)),
            const SizedBox(height: 8),
            Text('$_imported imported, $_skipped skipped', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildImportDoneStep() {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 64, color: AppColors.success),
            const SizedBox(height: 16),
            const Text('Import Complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('$_imported imported successfully, $_skipped skipped', style: const TextStyle(fontSize: 13)),
            if (_importErrors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                height: 150,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  children: _importErrors.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(e, style: const TextStyle(fontSize: 11, color: AppColors.error)),
                  )).toList(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _resetImport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}
