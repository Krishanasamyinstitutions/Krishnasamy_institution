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
  DateTime? _dueDate;

  String? _selectedClass;
  String? _selectedFeeType;
  String? _selectedFeeYear;
  final _feeTermController = TextEditingController();
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
  String? _drilldownStudentName; // selected student name for 3rd level

  // Search
  final _searchController = TextEditingController();
  String _searchQuery = '';

  static const _importFieldKeys = [
    'stuadmno',
    'stuclass',
    'demfeetype',
    'yr_id',
    'demfeeterm',
    'con_id',
    'feeamount',
    'conamount',
    'duedate',
  ];

  static const Map<String, String> _importFieldLabels = {
    'stuadmno': 'Admission No',
    'stuclass': 'Class',
    'demfeetype': 'Fee Type',
    'yr_id': 'Fee Year',
    'demfeeterm': 'Fee Term',
    'con_id': 'Concession',
    'feeamount': 'Fee Amount',
    'conamount': 'Concession Amount',
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
      final classes = results[0] as List<String>;
      const classOrder = ['PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];
      classes.sort((a, b) {
        final aIdx = classOrder.indexOf(a);
        final bIdx = classOrder.indexOf(b);
        return (aIdx == -1 ? 999 : aIdx).compareTo(bIdx == -1 ? 999 : bIdx);
      });
      setState(() {
        _classes = classes;
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
        const classOrder = ['PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];
        summary.sort((a, b) {
          final aClass = a['stuclass']?.toString() ?? '';
          final bClass = b['stuclass']?.toString() ?? '';
          final aIdx = classOrder.indexOf(aClass);
          final bIdx = classOrder.indexOf(bClass);
          return (aIdx == -1 ? 999 : aIdx).compareTo(bIdx == -1 ? 999 : bIdx);
        });
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

      final feeAmount = double.tryParse(_feeAmountController.text.trim()) ?? 0;
      final conAmount = double.tryParse(_conAmountController.text.trim()) ?? 0;

      // Lookup stu_id from admission number
      final admNo = _admNoController.text.trim();
      int? stuId;
      if (admNo.isNotEmpty) {
        final stuResult = await SupabaseService.client
            .from('students')
            .select('stu_id')
            .eq('ins_id', insId)
            .eq('stuadmno', admNo)
            .eq('activestatus', 1)
            .maybeSingle();
        stuId = stuResult?['stu_id'] as int?;
      }

      final data = {
        'ins_id': insId,
        'inscode': inscode ?? '',
        'stuadmno': admNo,
        'stu_id': stuId,
        'stuclass': _selectedClass,
        'demfeetype': _selectedFeeType,
        'yr_id': _selectedFeeYear != null ? int.tryParse(_selectedFeeYear!) : null,
        'demfeeyear': yearLabel,
        'demfeeterm': _feeTermController.text.trim(),
        'con_id': _selectedConcession != null ? int.tryParse(_selectedConcession!) : null,
        'feeamount': feeAmount,
        'conamount': conAmount,
        'balancedue': feeAmount,
        'duedate': _dueDate?.toIso8601String().split('T').first,
        'activestatus': 1,
        'createdat': DateTime.now().toIso8601String(),
        'createdby': auth.userName,
        'isapproved': false,
      };

      await SupabaseService.client.from('tempfeedemand').insert(data);

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

  Future<void> _lookupStudentClass(String admNo) async {
    if (admNo.isEmpty) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    try {
      final result = await SupabaseService.client
          .from('students')
          .select('stuclass')
          .eq('ins_id', insId)
          .eq('stuadmno', admNo)
          .eq('activestatus', 1)
          .maybeSingle();
      if (mounted && result != null) {
        setState(() => _selectedClass = result['stuclass']?.toString());
      }
    } catch (_) {}
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _admNoController.clear();
    _feeAmountController.clear();
    _conAmountController.clear();

    setState(() {
      _selectedClass = null;
      _selectedFeeType = null;
      _selectedFeeYear = null;
      _feeTermController.clear();
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
      'concession': 'con_id', 'conid': 'con_id', 'concessioncategory': 'con_id', 'con': 'con_id',
      'feeamount': 'feeamount', 'amount': 'feeamount', 'fee': 'feeamount', 'feeamt': 'feeamount', 'fee amount': 'feeamount', 'fee amt': 'feeamount',
      'concessionamount': 'conamount', 'conamount': 'conamount', 'conamt': 'conamount', 'con amt': 'conamount', 'con. amt': 'conamount', 'concession amount': 'conamount',
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

    // 1. Pre-fetch all student admno -> stu_id mappings
    final stuList = await SupabaseService.client
        .from('students')
        .select('stu_id, stuadmno')
        .eq('ins_id', insId)
        .eq('activestatus', 1);
    final stuMap = <String, int>{};
    for (final s in stuList) {
      stuMap[s['stuadmno']?.toString() ?? ''] = s['stu_id'] as int;
    }

    // 2. Pre-fetch concession name -> con_id mappings
    final conMap = <String, int>{};
    for (final c in _concessions) {
      final desc = c['condesc']?.toString().toUpperCase() ?? '';
      final id = c['con_id'] as int?;
      if (desc.isNotEmpty && id != null) conMap[desc] = id;
    }

    // 3. Build all rows in memory
    final batch = <Map<String, dynamic>>[];
    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final err = _validateRow(i);
      if (err != null) {
        _skipped++;
        _importErrors.add('Row ${i + 2}: $err');
        continue;
      }

      try {
        final feeAmount = double.tryParse(_cellByKey(row, 'feeamount') ?? '0') ?? 0;
        final conAmount = double.tryParse(_cellByKey(row, 'conamount') ?? '0') ?? 0;

        final yrRaw = _cellByKey(row, 'yr_id');
        int? yrId;
        String? yrLabel;

        final yrInt = int.tryParse(yrRaw ?? '');
        if (yrInt != null) {
          final byId = _years.firstWhere(
            (y) => y['yr_id'] == yrInt,
            orElse: () => <String, dynamic>{},
          );
          if (byId.isNotEmpty) {
            yrId = yrInt;
            yrLabel = byId['yrlabel']?.toString();
          }
        }
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

        final admNoRaw = _cellByKey(row, 'stuadmno');
        final stuId = stuMap[admNoRaw];

        final conName = _cellByKey(row, 'con_id');
        int? conId;
        if (conName != null && conName.isNotEmpty) {
          conId = int.tryParse(conName) ?? conMap[conName.toUpperCase()];
        }

        final data = {
          'ins_id': insId,
          'inscode': auth.inscode ?? '',
          'stuadmno': admNoRaw,
          'stu_id': stuId,
          'stuclass': _cellByKey(row, 'stuclass'),
          'demfeetype': _cellByKey(row, 'demfeetype'),
          'yr_id': yrId,
          'demfeeyear': yrLabel ?? yrRaw ?? '',
          'demfeeterm': _cellByKey(row, 'demfeeterm'),
          'con_id': conId,
          'feeamount': feeAmount,
          'conamount': conAmount,
          'balancedue': feeAmount,
          'duedate': _cellByKey(row, 'duedate'),
          'activestatus': 1,
          'createdat': now,
          'createdby': auth.userName,
          'isapproved': false,
        };
        data.removeWhere((k, v) => v == null);
        batch.add(data);
      } catch (e) {
        _skipped++;
        _importErrors.add('Row ${i + 2}: $e');
      }
    }

    setState(() {});

    // 4. Bulk insert in batches of 500
    for (int i = 0; i < batch.length; i += 500) {
      final chunk = batch.sublist(i, (i + 500).clamp(0, batch.length));
      try {
        await SupabaseService.client.from('tempfeedemand').insert(chunk);
        _imported += chunk.length;
      } catch (e) {
        // If batch fails, try one by one
        for (final row in chunk) {
          try {
            await SupabaseService.client.from('tempfeedemand').insert(row);
            _imported++;
          } catch (e2) {
            _skipped++;
            _importErrors.add('Adm ${row['stuadmno']}: $e2');
          }
        }
      }
      setState(() {});
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
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _loadFeeDemands,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
    return _buildDemandsList();
  }

  Widget _buildForm() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
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
                      onChanged: (v) => _lookupStudentClass(v.trim()),
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
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
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
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
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
                    _drilldownStudentName = null;
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
              Text(
                _drilldownStudent != null
                    ? '${_drilldownStudentName ?? ''} (Adm No: $_drilldownStudent)'
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF6C8EEF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 100, child: Text('CLASS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                Expanded(child: Text('STUDENTS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center)),
                Expanded(child: Text('TOTAL DEMAND', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
                Expanded(child: Text('COLLECTED', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
                Expanded(child: Text('PENDING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
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
              separatorBuilder: (_, __) => const SizedBox.shrink(),
              itemBuilder: (context, i) {
                final s = summaries[i];
                final className = s['stuclass']?.toString() ?? '-';
                final studentCount = (s['student_count'] as num?)?.toInt() ?? 0;
                final totalDemand = (s['total_demand'] as num?)?.toDouble() ?? 0;
                final totalPaid = (s['total_paid'] as num?)?.toDouble() ?? 0;
                final totalPending = (s['total_pending'] as num?)?.toDouble() ?? 0;

                return InkWell(
                  onTap: () => _loadDrilldown(className),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: i.isEven ? Colors.white : const Color(0xFFF7FAFC),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 100,
                          child: Text('Class $className', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
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

  String _formatDueDate(String dateStr) {
    if (dateStr == '-' || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day.toString().padLeft(2, '0')}-${months[dt.month - 1]}-${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _formatAmount(double amount) {
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (match) => '${match[1]},',
      );
    }
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+\.)'),
      (match) => '${match[1]},',
    );
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF6C8EEF),
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: const Row(
              children: [
                SizedBox(width: 80, child: Text('ADM NO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                Expanded(flex: 2, child: Text('NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                Expanded(child: Text('DEMAND', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
                Expanded(child: Text('PAID', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
                Expanded(child: Text('PENDING', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.right)),
                SizedBox(width: 70, child: Text('STATUS', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white), textAlign: TextAlign.center)),
                SizedBox(width: 28),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.separated(
              padding: EdgeInsets.zero,
              itemCount: students.length,
              separatorBuilder: (_, __) => const SizedBox.shrink(),
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
                    _drilldownStudentName = name;
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
  static const _termOrder = [
    'I TERM', 'II TERM', 'III TERM',
    'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER',
    'NOVEMBER', 'DECEMBER', 'JANUARY', 'FEBRUARY', 'MARCH',
    'APRIL', 'MAY',
  ];

  int _termIndex(String term) {
    final idx = _termOrder.indexOf(term.toUpperCase());
    return idx >= 0 ? idx : _termOrder.length;
  }

  Widget _buildStudentFeeDetails() {
    final demands = List<Map<String, dynamic>>.from(_filteredStudentDemands)
      ..sort((a, b) {
        final ta = a['demfeeterm']?.toString() ?? '';
        final tb = b['demfeeterm']?.toString() ?? '';
        final ftA = a['demfeetype']?.toString() ?? '';
        final ftB = b['demfeetype']?.toString() ?? '';
        final cmp = ftA.compareTo(ftB);
        if (cmp != 0) return cmp;
        return _termIndex(ta).compareTo(_termIndex(tb));
      });
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

    double totalAmt = 0, totalPaid = 0, totalBal = 0;
    for (final d in demands) {
      totalAmt += (d['feeamount'] as num?)?.toDouble() ?? 0;
      totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
      totalBal += (d['balancedue'] as num?)?.toDouble() ?? 0;
    }

    return LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              dividerThickness: 0,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFF6C8EEF)),
              headingTextStyle: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              dataTextStyle: const TextStyle(fontSize: 12, color: AppColors.textPrimary),
              columnSpacing: 20,
              horizontalMargin: 16,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('TERM')),
                DataColumn(label: Text('FEE TYPE')),
                DataColumn(label: Text('AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('BALANCE'), numeric: true),
                DataColumn(label: Text('DUE DATE')),
                DataColumn(label: Text('STATUS')),
              ],
              rows: [
                ...demands.asMap().entries.map((entry) {
                  final i = entry.key;
                  final d = entry.value;
                  final term = d['demfeeterm']?.toString() ?? '-';
                  final feeType = d['demfeetype']?.toString() ?? '-';
                  final amt = (d['feeamount'] as num?)?.toDouble() ?? 0;
                  final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
                  final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  final status = d['paidstatus']?.toString() ?? 'U';
                  final isPaid = status == 'Paid' || status == 'P';
                  final dueDate = d['duedate']?.toString() ?? '-';
                  final formattedDueDate = _formatDueDate(dueDate);
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(term)),
                    DataCell(Text(feeType, style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(Text('₹${_formatAmount(amt)}')),
                    DataCell(Text('₹${_formatAmount(paid)}', style: TextStyle(color: paid > 0 ? AppColors.success : AppColors.textPrimary))),
                    DataCell(Text('₹${_formatAmount(bal)}', style: TextStyle(fontWeight: FontWeight.w500, color: bal > 0 ? AppColors.warning : AppColors.success))),
                    DataCell(Text(formattedDueDate, style: const TextStyle(fontSize: 11))),
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
                // Total row
                DataRow(
                  color: WidgetStateProperty.all(const Color(0xFF6C8EEF)),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    const DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text('₹${_formatAmount(totalAmt)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text('₹${_formatAmount(totalPaid)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    DataCell(Text('₹${_formatAmount(totalBal)}', style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white))),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  // ─── Import UI ──────────────────────────────────────────────────────────

  Widget _buildImportSection() {
    if (_importStep == 2) return _buildImportProgressStep();
    if (_importStep == 3) return _buildImportDoneStep();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
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
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                      color: const Color(0xFF6C8EEF),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(7),
                        topRight: Radius.circular(7),
                      ),
                    ),
                    child: Row(
                      children: [
                        _gridHeaderCell('S.No', width: 60, center: true),
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
                        _gridHeaderCell('Concession', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Fee Amt *', flex: 2, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Con. Amt', flex: 2, center: true),
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
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                color: isEven ? Colors.white : AppColors.surface,
                                child: Row(
                                  children: [
                                    _gridDataCell('${index + 1}', width: 60, center: true),
                                    _gridDataCell(_mappedCell(row, 'stuadmno'), flex: 2),
                                    _gridDataCell(_mappedCell(row, 'stuclass'), flex: 1),
                                    _gridDataCell(_mappedCell(row, 'demfeetype'), flex: 2),
                                    _gridDataCell(_mappedCell(row, 'yr_id'), flex: 1),
                                    _gridDataCell(_mappedCell(row, 'demfeeterm'), flex: 1),
                                    _gridDataCell(_mappedCell(row, 'con_id'), flex: 2),
                                    _gridDataCell(_mappedCell(row, 'feeamount'), flex: 2, center: true),
                                    _gridDataCell(_mappedCell(row, 'conamount'), flex: 2, center: true),
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
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _resetImport,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
      'Concession',
      'Fee Amount',
      'Concession Amount',
      'Due Date',
    ];

    final headerStyle = xl.CellStyle(
      backgroundColorHex: xl.ExcelColor.fromHexString('#FF2D3748'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFFFF'),
      bold: true,
    );

    const columnWidths = [18.0, 12.0, 18.0, 14.0, 12.0, 16.0, 16.0, 16.0, 20.0, 16.0, 14.0];

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(i, columnWidths[i]);
    }
    sheet.setRowHeight(0, 32);

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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
          borderRadius: BorderRadius.circular(10),
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
          borderRadius: BorderRadius.circular(10),
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
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
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
