import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/app_search_field.dart';
import 'package:excel/excel.dart' as xl;
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
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
  Map<int, String> _rowErrors = {};
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
    'courname',
    'demfeetype',
    'yr_id',
    'demfeeterm',
    'con_id',
    'feeamount',
    'conamount',
    'duedate',
  ];

  static const Map<String, String> _importFieldLabels = {
    'stuadmno': 'Roll No',
    'stuclass': 'Class',
    'courname': 'Course',
    'demfeetype': 'Fee Type',
    'yr_id': 'Fee Year',
    'demfeeterm': 'Semester',
    'con_id': 'Concession',
    'feeamount': 'Fee Amount',
    'conamount': 'Concession Amount',
    'duedate': 'Due Date',
  };

  static const _requiredFields = {'stuadmno', 'stuclass', 'demfeetype', 'yr_id', 'demfeeterm', 'con_id', 'feeamount', 'conamount', 'duedate'};

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
        const classOrder = ['PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'I Year', 'II Year', 'III Year'];
        summary.sort((a, b) {
          // Course alphabetical first, then class order.
          final aCourse = a['courname']?.toString() ?? '';
          final bCourse = b['courname']?.toString() ?? '';
          final courseCmp = aCourse.compareTo(bCourse);
          if (courseCmp != 0) return courseCmp;
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

  String? _drilldownCourse;

  Future<void> _loadDrilldown(String className, {String? courseName}) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() {
      _drilldownClass = className;
      _drilldownCourse = courseName;
      _loadingDrilldown = true;
      _drilldownDemands = [];
    });
    try {
      final demands = await SupabaseService.getFeeDemandsByClass(insId, className);
      // Filter by course if specified
      final filtered = courseName != null
          ? demands.where((d) => (d['courname']?.toString() ?? d['stuname_course'] ?? '') == courseName || courseName == 'Other').toList()
          : demands;
      if (mounted) {
        setState(() {
          _drilldownDemands = filtered;
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

    final masterData = await SupabaseService.checkMasterData(insId);
    if (!masterData.hasFeeTypes || !masterData.hasClassFeeDemand) {
      if (mounted) {
        final missing = <String>[];
        if (!masterData.hasFeeTypes) missing.add('Fee Types');
        if (!masterData.hasClassFeeDemand) missing.add('Class Fee Demand');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please import master data first: ${missing.join(', ')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

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
        final stuResult = await SupabaseService.fromSchema('students')
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

      await SupabaseService.fromSchema('tempfeedemand').insert(data);

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
          SnackBar(content: Text(friendlyError(e)), backgroundColor: AppColors.error),
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
      final result = await SupabaseService.fromSchema('students')
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
      'admissionno': 'stuadmno', 'admno': 'stuadmno', 'stuadmno': 'stuadmno', 'admissionnumber': 'stuadmno', 'rollno': 'stuadmno', 'roll': 'stuadmno', 'rollnumber': 'stuadmno',
      'class': 'stuclass', 'stuclass': 'stuclass',
      'course': 'courname', 'courname': 'courname', 'coursename': 'courname',
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

    final masterData = await SupabaseService.checkMasterData(insId);
    if (!masterData.hasFeeTypes || !masterData.hasClassFeeDemand) {
      if (mounted) {
        final missing = <String>[];
        if (!masterData.hasFeeTypes) missing.add('Fee Types');
        if (!masterData.hasClassFeeDemand) missing.add('Class Fee Demand');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Please import master data first: ${missing.join(', ')}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    setState(() {
      _importStep = 2;
      _imported = 0;
      _skipped = 0;
      _total = _rows.length;
      _importErrors = [];
    });

    // 1. Pre-fetch all student admno -> stu_id mappings
    final stuList = await SupabaseService.fromSchema('students')
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
        // Final fallback: if there's exactly one year configured, use it.
        // This handles Excel files where yr_id is missing or has values like
        // '2025', 'Year 1', etc. that don't match anything in the year table.
        if (yrId == null && _years.isNotEmpty) {
          yrId = _years.first['yr_id'] as int?;
          yrLabel = _years.first['yrlabel']?.toString();
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
          'courname': _cellByKey(row, 'courname'),
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
        _importErrors.add('Row ${i + 2}: ${_friendlyError(e.toString())}');
      }
    }

    setState(() {});

    // 4. Bulk insert in small batches (Supabase REST has payload limits and
    // long requests time out, so 100/batch is the sweet spot for big imports).
    const int batchSize = 100;
    for (int i = 0; i < batch.length; i += batchSize) {
      final chunk = batch.sublist(i, (i + batchSize).clamp(0, batch.length));
      try {
        await SupabaseService.fromSchema('tempfeedemand').insert(chunk);
        _imported += chunk.length;
      } catch (e) {
        debugPrint('Batch insert failed at $i: $e');
        // Halve the batch on first failure, then per-row as last resort
        try {
          final mid = chunk.length ~/ 2;
          await SupabaseService.fromSchema('tempfeedemand').insert(chunk.sublist(0, mid));
          await SupabaseService.fromSchema('tempfeedemand').insert(chunk.sublist(mid));
          _imported += chunk.length;
        } catch (_) {
          for (final row in chunk) {
            try {
              await SupabaseService.fromSchema('tempfeedemand').insert(row);
              _imported++;
            } catch (e2) {
              _skipped++;
              _importErrors.add('Adm ${row['stuadmno']}: ${_friendlyError(e2.toString())}');
            }
          }
        }
      }
      if (mounted) setState(() {});
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
      _rowErrors = {};
    });
  }

  static String _friendlyError(String msg) {
    final m = msg.toLowerCase();
    if (m.contains('duplicate key') || m.contains('unique constraint')) return 'Duplicate record found';
    if (m.contains('not-null') || m.contains('null value')) {
      final match = RegExp(r'column "(\w+)"').firstMatch(msg);
      return '${match?.group(1) ?? 'Field'} is required';
    }
    if (m.contains('foreign key') || m.contains('fkey')) return 'Invalid reference - check linked values';
    if (m.contains('check constraint')) return 'Invalid value format';
    if (m.contains('value too long')) return 'Value too long for the field';
    if (m.contains('invalid input syntax')) return 'Invalid data format';
    if (m.contains('permission denied')) return 'Permission denied';
    return msg.length > 80 ? '${msg.substring(0, 80)}...' : msg;
  }

  // ─── UI ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          // Card header with title, buttons, breadcrumb, and search
          Container(
            padding: EdgeInsets.fromLTRB(16.w, 10.h, 16.w, 4.h),
            child: Row(
              children: [
                if (_drilldownClass == null && _drilldownStudent == null) ...[
                  AppIcon('receipt-edit', color: AppColors.accent, size: 18),
                  SizedBox(width: 10.w),
                  Text('Fee Demand', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                ],
                if (!_showImport) ...[
                  if (_drilldownClass != null || _drilldownStudent != null) ...[
                    // Back button — solid accent pill
                    InkWell(
                      onTap: () => setState(() {
                        if (_drilldownStudent != null) {
                          _drilldownStudent = null;
                          _drilldownStudentName = null;
                        } else {
                          _drilldownClass = null;
                          _drilldownDemands = [];
                        }
                        _searchQuery = '';
                        _searchController.clear();
                      }),
                      borderRadius: BorderRadius.circular(8.r),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          borderRadius: BorderRadius.circular(8.r),
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
                    // Breadcrumb path (plain text, not button-like)
                    Text('Fee Demand', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                    SizedBox(width: 6.w),
                    AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
                    SizedBox(width: 6.w),
                    if (_drilldownStudent != null) ...[
                      Text('${_drilldownCourse != null ? '$_drilldownCourse > ' : ''}$_drilldownClass', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      SizedBox(width: 6.w),
                      AppIcon.linear('Chevron Right', size: 14, color: AppColors.textSecondary),
                      SizedBox(width: 6.w),
                      Text(
                        '${_drilldownStudentName ?? ''} (${_drilldownStudent})',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                    ] else
                      Text(
                        'Class $_drilldownClass',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                  ] else ...[
                    SizedBox(width: 16.w),
                    Text(
                      '${_classSummary.fold<int>(0, (sum, c) => sum + ((c['student_count'] as num?)?.toInt() ?? 0))} students',
                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary),
                    ),
                  ],
                ],
                const Spacer(),
                if (!_showImport) ...[
                  AppSearchField(
                    controller: _searchController,
                    hintText: 'Search by class...',
                    onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                    width: 260.w,
                    suffixIcon: _searchQuery.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: IconButton(
                              icon: const AppIcon('close-circle', size: 14),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _searchQuery = '');
                              },
                              splashRadius: 12,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          )
                        : null,
                  ),
                  SizedBox(width: 16.w),
                ],
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: () => setState(() {
                      _showImport = !_showImport;
                      if (!_showImport) _resetImport();
                    }),
                    icon: AppIcon(_showImport ? 'close-circle' : 'document-upload', size: 16, color: Colors.white),
                    label: Text(_showImport ? 'Close Import' : 'Import CSV/Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _showImport ? AppColors.error : AppColors.accent,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(horizontal: 18.w),
                      textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                  ),
                ),
                if (!_showImport) ...[
                  SizedBox(width: 8.w),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _loadFeeDemands,
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
              ],
            ),
          ),

          // Content
          Expanded(
            child: _showImport ? _buildImportSection() : _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return _buildDemandsList();
  }

  Widget _buildForm() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
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
                        AppIcon('receipt-2', size: 18, color: AppColors.accent),
                        SizedBox(width: 8.w),
                        Text('Add Fee Demand', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                      ],
                    ),
                    SizedBox(height: 20.h),

                    // Admission No
                    _buildLabel('Roll No *'),
                    TextFormField(
                      controller: _admNoController,
                      decoration: _inputDecoration('Enter admission number'),
                      style: TextStyle(fontSize: 13.sp),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                      onChanged: (v) => _lookupStudentClass(v.trim()),
                    ),
                    SizedBox(height: 16.h),

                    // Class
                    _buildLabel('Class'),
                    DropdownButtonFormField<String>(
                      value: _selectedClass,
                      decoration: _inputDecoration('Select class'),
                      items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                      onChanged: (v) => setState(() => _selectedClass = v),
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 16.h),

                    // Fee Type
                    _buildLabel('Fee Type *'),
                    DropdownButtonFormField<String>(
                      value: _selectedFeeType,
                      decoration: _inputDecoration('Select fee type'),
                      items: _feeTypes.map((f) => DropdownMenuItem(value: f, child: Text(f))).toList(),
                      onChanged: (v) => setState(() => _selectedFeeType = v),
                      validator: (v) => v == null ? 'Required' : null,
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 16.h),

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
                                style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Semester'),
                              TextFormField(
                                controller: _feeTermController,
                                decoration: _inputDecoration('Enter term'),
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),

                    // Concession
                    _buildLabel('Concession'),
                    DropdownButtonFormField<String>(
                      value: _selectedConcession,
                      decoration: _inputDecoration('Select concession'),
                      items: _concessions.map((c) => DropdownMenuItem(value: c['con_id'].toString(), child: Text(c['condesc']?.toString() ?? '-'))).toList(),
                      onChanged: (v) => setState(() => _selectedConcession = v),
                      style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    ),
                    SizedBox(height: 16.h),

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
                                style: TextStyle(fontSize: 13.sp),
                                validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                              ),
                            ],
                          ),
                        ),
                        SizedBox(width: 12.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildLabel('Concession Amount'),
                              TextFormField(
                                controller: _conAmountController,
                                decoration: _inputDecoration('Enter amount'),
                                keyboardType: TextInputType.number,
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 16.h),

                    // Due Date
                    _buildLabel('Due Date'),
                    InkWell(
                      onTap: _pickDueDate,
                      borderRadius: BorderRadius.circular(10.r),
                      child: InputDecorator(
                        decoration: _inputDecoration('').copyWith(
                          suffixIcon: AppIcon('calendar-1', size: 18, color: AppColors.textSecondary),
                        ),
                        child: Text(
                          _dueDate != null
                              ? '${_dueDate!.day.toString().padLeft(2, '0')}/${_dueDate!.month.toString().padLeft(2, '0')}/${_dueDate!.year}'
                              : 'Select date',
                          style: TextStyle(fontSize: 13.sp, color: _dueDate != null ? AppColors.textPrimary : Colors.grey.shade400),
                        ),
                      ),
                    ),
                    SizedBox(height: 24.h),

                    // Buttons
                    Builder(builder: (_) {
                      const btnHeight = 48.0;
                      final btnPadding = EdgeInsets.symmetric(horizontal: 28.w);
                      return Row(
                        children: [
                          Expanded(
                            child: SizedBox(
                              height: btnHeight,
                              child: OutlinedButton.icon(
                                onPressed: _resetForm,
                                icon: const AppIcon('refresh', size: 16, color: AppColors.textPrimary),
                                label: const Text('Clear', style: TextStyle(fontWeight: FontWeight.w600)),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.textPrimary,
                                  side: const BorderSide(color: AppColors.border),
                                  padding: btnPadding,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                                ),
                              ),
                            ),
                          ),
                          SizedBox(width: 12.w),
                          Expanded(
                            flex: 2,
                            child: SizedBox(
                              height: btnHeight,
                              child: ElevatedButton.icon(
                                onPressed: _isSaving ? null : _saveDemand,
                                icon: _isSaving
                                    ? SizedBox(width: 18.w, height: 18.h, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : AppIcon('save-2', size: 18),
                                label: Text(_isSaving ? 'Saving...' : 'Save Fee Demand', style: const TextStyle(fontWeight: FontWeight.w600)),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  padding: btnPadding,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildLabel(String text) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Text(
        text,
        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400),
      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10.r),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      filled: true,
      fillColor: AppColors.surface,
    );
  }

  Widget _buildDemandsList() {
    return _loadingDemands
        ? const Center(child: CircularProgressIndicator())
        : _drilldownStudent != null
            ? _buildStudentFeeDetails()
            : _drilldownClass != null
                ? _buildDrilldownView()
                : _buildClassCards();
  }

  List<Map<String, dynamic>> get _filteredClassSummary {
    if (_searchQuery.isEmpty) return _classSummary;
    return _classSummary.where((c) {
      final cls = c['stuclass']?.toString().toLowerCase() ?? '';
      final course = c['courname']?.toString().toLowerCase() ?? '';
      return cls.contains(_searchQuery) || course.contains(_searchQuery);
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
          'courname': d['courname']?.toString(),
          'total_demand': 0.0,
          'total_concession': 0.0,
          'total_paid': 0.0,
          'total_pending': 0.0,
          'total_fine': 0.0,
          'demand_count': 0,
          'paid_count': 0,
          'unpaid_count': 0,
        };
      }
      final g = grouped[admNo]!;
      final amt = (d['feeamount'] as num?)?.toDouble() ?? 0;
      final con = (d['conamount'] as num?)?.toDouble() ?? 0;
      final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
      // Use reconbalancedue (post-recon outstanding); fall back to balancedue.
      // Paid = paidamount - fineamount when reconciled, else 0.
      final bal = (d['reconbalancedue'] as num?)?.toDouble()
          ?? (d['balancedue'] as num?)?.toDouble() ?? amt;
      final isFullyReconciled = bal <= 0;
      final paid = isFullyReconciled ? (pa - fa) : 0.0;
      g['total_demand'] = (g['total_demand'] as double) + amt;
      g['total_concession'] = (g['total_concession'] as double) + con;
      g['total_paid'] = (g['total_paid'] as double) + paid;
      g['total_fine'] = (g['total_fine'] as double) + (isFullyReconciled ? fa : 0);
      g['total_pending'] = (g['total_pending'] as double) + bal;
      g['demand_count'] = (g['demand_count'] as int) + 1;
      if (isFullyReconciled) {
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
            AppIcon('message-text', size: 48.sp, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            SizedBox(height: 8.h),
            const Text('No fee demands found', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Table header
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              color: AppColors.tableHeadBg,
              child: Row(
                children: [
                  SizedBox(width: 100.w, child: Text('COURSE', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                  SizedBox(width: 80.w, child: Text('CLASS', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                  Expanded(child: Text('STUDENTS', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.center)),
                  Expanded(child: Text('TOTAL DEMAND', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                  Expanded(child: Text('COLLECTED', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                  Expanded(child: Text('FINE', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                  Expanded(child: Text('PENDING', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                  SizedBox(width: 32.w),
                ],
              ),
            ),
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
                  final totalFine = (s['total_fine'] as num?)?.toDouble() ?? 0;
                  final totalPending = (s['total_pending'] as num?)?.toDouble() ?? 0;

                  return InkWell(
                    onTap: () => _loadDrilldown(className, courseName: s['courname']?.toString()),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                      color: i.isEven ? Colors.white : AppColors.surface,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 100.w,
                            child: Text(s['courname']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          ),
                          SizedBox(
                            width: 80.w,
                            child: Text(className, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                          ),
                          Expanded(child: Text('$studentCount', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary), textAlign: TextAlign.center)),
                          Expanded(child: Text('₹${_formatAmount(totalDemand)}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary), textAlign: TextAlign.right)),
                          Expanded(child: Text('₹${_formatAmount(totalPaid)}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.success), textAlign: TextAlign.right)),
                          Expanded(child: Text(totalFine > 0 ? '₹${_formatAmount(totalFine)}' : '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: totalFine > 0 ? Colors.orange : AppColors.textSecondary), textAlign: TextAlign.right)),
                          Expanded(child: Text('₹${_formatAmount(totalPending)}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.warning), textAlign: TextAlign.right)),
                          SizedBox(width: 32.w, child: AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary)),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            // Total footer row
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
              decoration: BoxDecoration(
                color: AppColors.tableHeadBg,
                border: const Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Row(
                children: [
                  SizedBox(width: 100.w, child: Text('TOTAL', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                  SizedBox(width: 80.w),
                  Expanded(child: Text('${summaries.fold<int>(0, (sum, s) => sum + ((s['student_count'] as num?)?.toInt() ?? 0))}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary), textAlign: TextAlign.center)),
                  Expanded(child: Text('₹${_formatAmount(summaries.fold<double>(0, (sum, s) => sum + ((s['total_demand'] as num?)?.toDouble() ?? 0)))}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary), textAlign: TextAlign.right)),
                  Expanded(child: Text('₹${_formatAmount(summaries.fold<double>(0, (sum, s) => sum + ((s['total_paid'] as num?)?.toDouble() ?? 0)))}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.success), textAlign: TextAlign.right)),
                  Expanded(child: Text('₹${_formatAmount(summaries.fold<double>(0, (sum, s) => sum + ((s['total_fine'] as num?)?.toDouble() ?? 0)))}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: Colors.orange), textAlign: TextAlign.right)),
                  Expanded(child: Text('₹${_formatAmount(summaries.fold<double>(0, (sum, s) => sum + ((s['total_pending'] as num?)?.toDouble() ?? 0)))}', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.warning), textAlign: TextAlign.right)),
                  SizedBox(width: 32.w),
                ],
              ),
            ),
          ],
        ),
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
            AppIcon('message-text', size: 48.sp, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            SizedBox(height: 8.h),
            Text(
              _searchQuery.isNotEmpty ? 'No matching students' : 'No students found',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
            children: [
              // Table header
              Container(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                color: AppColors.tableHeadBg,
                child: Row(
                  children: [
                    Expanded(flex: 1, child: Text('ROLL NO', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                    Expanded(flex: 2, child: Text('NAME', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                    Expanded(flex: 1, child: Text('COURSE', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                    Expanded(flex: 1, child: Text('DEMAND', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                    Expanded(flex: 1, child: Text('PAID', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                    Expanded(flex: 1, child: Text('FINE', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                    Expanded(flex: 1, child: Text('PENDING', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.right)),
                    Expanded(flex: 1, child: Text('STATUS', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3), textAlign: TextAlign.center)),
                    SizedBox(width: 28.w),
                  ],
                ),
              ),
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
                    final totalFine = (s['total_fine'] as double?) ?? 0;
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
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 1,
                              child: Text(admNo, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                name.isNotEmpty ? name : '-',
                                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(s['courname']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text('₹${_formatAmount(totalDemand)}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary), textAlign: TextAlign.right),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text('₹${_formatAmount(totalPaid)}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.success), textAlign: TextAlign.right),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text(totalFine > 0 ? '₹${_formatAmount(totalFine)}' : '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: totalFine > 0 ? Colors.orange : AppColors.textSecondary), textAlign: TextAlign.right),
                            ),
                            Expanded(
                              flex: 1,
                              child: Text('₹${_formatAmount(totalPending)}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: totalPending > 0 ? AppColors.warning : AppColors.success), textAlign: TextAlign.right),
                            ),
                            Expanded(
                              flex: 1,
                              child: Center(
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                  decoration: BoxDecoration(
                                    color: allPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6.r),
                                  ),
                                  child: Text(
                                    allPaid ? 'Paid' : 'Unpaid',
                                    style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: allPaid ? AppColors.success : AppColors.warning),
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(width: 28.w, child: AppIcon.linear('Chevron Right', size: 16, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
        ),
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
            AppIcon('message-text', size: 48.sp, color: AppColors.textSecondary.withValues(alpha: 0.4)),
            SizedBox(height: 8.h),
            Text(
              _searchQuery.isNotEmpty ? 'No matching records' : 'No fee demands found',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    double totalAmt = 0, totalPaid = 0, totalFine = 0, totalBal = 0;
    for (final d in demands) {
      totalAmt += (d['feeamount'] as num?)?.toDouble() ?? 0;
      final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
      final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
      final status = d['paidstatus']?.toString() ?? 'U';
      final isPaid = pa > 0 || status == 'P' || status == 'Paid';
      totalPaid += pa - (isPaid ? fa : 0);
      totalFine += isPaid ? fa : 0;
      totalBal += (d['balancedue'] as num?)?.toDouble() ?? 0;
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16.w, 8.h, 16.w, 16.h),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: AppColors.border),
        ),
        child: LayoutBuilder(builder: (context, constraints) {
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              dividerThickness: 0,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
              headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
              dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              columnSpacing: 20,
              horizontalMargin: 16,
              dataRowMinHeight: 36,
              dataRowMaxHeight: 40,
              headingRowHeight: 42,
              columns: const [
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('SEMESTER')),
                DataColumn(label: Text('FEE TYPE')),
                DataColumn(label: Text('AMOUNT'), numeric: true),
                DataColumn(label: Text('PAID'), numeric: true),
                DataColumn(label: Text('FINE'), numeric: true),
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
                  final pa = (d['paidamount'] as num?)?.toDouble() ?? 0;
                  final fa = (d['fineamount'] as num?)?.toDouble() ?? 0;
                  final status = d['paidstatus']?.toString() ?? 'U';
                  final isPaid = pa > 0 || status == 'P' || status == 'Paid';
                  final paid = pa - (isPaid ? fa : 0);
                  final fineDisplay = isPaid ? fa : 0.0;
                  final bal = (d['balancedue'] as num?)?.toDouble() ?? 0;
                  final dueDate = d['duedate']?.toString() ?? '-';
                  final formattedDueDate = _formatDueDate(dueDate);
                  return DataRow(cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(term)),
                    DataCell(Text(feeType, style: const TextStyle(fontWeight: FontWeight.w500))),
                    DataCell(Text('₹${_formatAmount(amt)}')),
                    DataCell(Text('₹${_formatAmount(paid)}', style: TextStyle(color: paid > 0 ? AppColors.success : AppColors.textPrimary))),
                    DataCell(Text(fineDisplay > 0 ? '₹${_formatAmount(fineDisplay)}' : '-', style: TextStyle(color: fineDisplay > 0 ? Colors.orange : AppColors.textSecondary))),
                    DataCell(Text('₹${_formatAmount(bal)}', style: TextStyle(fontWeight: FontWeight.w500, color: bal > 0 ? AppColors.warning : AppColors.success))),
                    DataCell(Text(formattedDueDate, style: TextStyle(fontSize: 13.sp))),
                    DataCell(Container(
                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                      decoration: BoxDecoration(
                        color: isPaid ? AppColors.success.withValues(alpha: 0.1) : AppColors.warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: Text(isPaid ? 'Paid' : 'Pending', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: isPaid ? AppColors.success : AppColors.warning)),
                    )),
                  ]);
                }),
                // Total row
                DataRow(
                  color: WidgetStateProperty.all(AppColors.tableHeadBg),
                  cells: [
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                    DataCell(Text('Total', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text('₹${_formatAmount(totalAmt)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    DataCell(Text('₹${_formatAmount(totalPaid)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.success))),
                    DataCell(Text('₹${_formatAmount(totalFine)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.warning))),
                    DataCell(Text('₹${_formatAmount(totalBal)}', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14.sp, color: AppColors.textPrimary))),
                    const DataCell(Text('')),
                    const DataCell(Text('')),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }),
      ),
    );
  }

  // ─── Import UI ──────────────────────────────────────────────────────────

  Widget _buildImportSection() {
    if (_importStep == 2) return _buildImportProgressStep();
    if (_importStep == 3) return _buildImportDoneStep();

    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title bar
          Row(
            children: [
              AppIcon('document-upload', size: 20, color: AppColors.accent),
              SizedBox(width: 8.w),
              Text('Import Fee Demands', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_fileName != null)
                Text(_fileName!, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
              SizedBox(width: 12.w),
              ElevatedButton.icon(
                onPressed: _pickFile,
                icon: AppIcon('folder-open', size: 16),
                label: const Text('Browse'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: 8.w),
              ElevatedButton.icon(
                onPressed: _exportTemplate,
                icon: AppIcon('grid-1', size: 16),
                label: const Text('Format to Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF217346),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: 8.w),
              ElevatedButton.icon(
                onPressed: _exportSampleData,
                icon: AppIcon('document-download', size: 16),
                label: const Text('Sample Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_errorMsg != null) ...[
            SizedBox(height: 8.h),
            Text(_errorMsg!, style: TextStyle(color: AppColors.error, fontSize: 13.sp)),
          ],
          SizedBox(height: 12.h),

          // Data grid
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8.r),
              ),
              child: Column(
                children: [
                  // Header row
                  Container(
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C8EEF),
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(7.r),
                        topRight: Radius.circular(7.r),
                      ),
                    ),
                    child: Row(
                      children: [
                        _gridHeaderCell('S.No', width: 60, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Roll No *', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Class *', flex: 1),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Course', flex: 1),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Fee Type *', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Year *', flex: 1),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Semester *', flex: 1),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Concession *', flex: 2),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Fee Amt *', flex: 2, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Con. Amt *', flex: 2, center: true),
                        _gridHeaderDivider(),
                        _gridHeaderCell('Due Date *', flex: 2, center: true),
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
                                AppIcon('element-4', size: 48.sp, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                                SizedBox(height: 8.h),
                                Text('No data loaded', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                                SizedBox(height: 4.h),
                                Text('Click Browse to load a CSV or Excel file', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            itemCount: _rows.length,
                            itemBuilder: (context, index) {
                              final row = _rows[index];
                              final isEven = index % 2 == 0;
                              final hasError = _rowErrors.containsKey(index);
                              return Tooltip(
                                message: hasError ? _rowErrors[index]! : '',
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                                  color: hasError ? const Color(0xFFFCE4E4) : (isEven ? Colors.white : AppColors.surface),
                                  child: Row(
                                    children: [
                                      _gridDataCell('${index + 1}', width: 60, center: true),
                                      _gridDataCell(_mappedCell(row, 'stuadmno'), flex: 2),
                                      _gridDataCell(_mappedCell(row, 'stuclass'), flex: 1),
                                      _gridDataCell(_mappedCell(row, 'courname'), flex: 1),
                                      _gridDataCell(_mappedCell(row, 'demfeetype'), flex: 2),
                                      _gridDataCell(_mappedCell(row, 'yr_id'), flex: 1),
                                      _gridDataCell(_mappedCell(row, 'demfeeterm'), flex: 1),
                                      _gridDataCell(_mappedCell(row, 'con_id'), flex: 2),
                                      _gridDataCell(_mappedCell(row, 'feeamount'), flex: 2, center: true),
                                      _gridDataCell(_mappedCell(row, 'conamount'), flex: 2, center: true),
                                      _gridDataCell(_mappedCell(row, 'duedate'), flex: 2, center: true),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),

          SizedBox(height: 12.h),

          // Bottom bar with row count and action buttons
          Row(
            children: [
              Text(
                '${_rows.length} rows',
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _rows.isEmpty ? null : () => _validateImportData(),
                icon: AppIcon.linear('tick-circle', size: 16),
                label: const Text('Validate'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                ),
              ),
              SizedBox(width: 8.w),
              ElevatedButton.icon(
                onPressed: _rows.isNotEmpty && _mappings.contains('stuadmno') && _mappings.contains('feeamount') ? _startImport : null,
                icon: AppIcon('save-2', size: 16),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
              SizedBox(width: 8.w),
              OutlinedButton(
                onPressed: _resetImport,
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
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
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Text(text, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3.w)),
    );
    return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
  }

  Widget _gridHeaderDivider() {
    return Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.15));
  }

  Widget _gridDataCell(String text, {double? width, int flex = 1, bool center = false}) {
    final child = Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
      ),
      child: Text(text, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
    );
    return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
  }

  Future<void> _exportTemplate() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Fee Demands'];
    // Remove default Sheet1
    excel.delete('Sheet1');

    final headers = [
      'Roll No',
      'Class',
      'Course',
      'Fee Type',
      'Fee Year',
      'Semester',
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

  Future<void> _exportSampleData() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Fee Demands'];
    excel.delete('Sheet1');

    final headers = ['Roll No', 'Class', 'Course', 'Fee Type', 'Fee Year', 'Semester', 'Concession', 'Fee Amount', 'Concession Amount', 'Due Date'];
    final sampleRows = [
      ['CS001', 'I Year', 'BSC-CS', 'SCHOOL FEES', '2026-2027', 'I TERM', 'GENERAL', '10080', '0', '2026-05-31'],
      ['CS001', 'I Year', 'BSC-CS', 'TUITION FEES', '2026-2027', 'JUNE', 'GENERAL', '700', '0', '2026-06-30'],
      ['BBA001', 'II Year', 'BBA', 'SCHOOL FEES', '2026-2027', 'I TERM', 'GENERAL', '10080', '2000', '2026-05-31'],
      ['MCA001', 'I Year', 'MCA', 'SCHOOL FEES', '2026-2027', 'I TERM', 'GENERAL', '6500', '0', '2026-05-31'],
    ];

    final headerStyle = xl.CellStyle(
      backgroundColorHex: xl.ExcelColor.fromHexString('#FF2D3748'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFFFF'),
      bold: true,
    );

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(i, 18);
    }
    for (int r = 0; r < sampleRows.length; r++) {
      for (int c = 0; c < sampleRows[r].length; c++) {
        final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
        cell.value = xl.TextCellValue(sampleRows[r][c]);
      }
    }

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Sample Data',
        fileName: 'fee_demand_sample.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (savePath == null) return;
      final bytes = excel.encode();
      if (bytes == null) return;
      await File(savePath).writeAsBytes(bytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Sample data exported successfully'), backgroundColor: AppColors.success),
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
    final errors = <int, String>{};
    for (int i = 0; i < _rows.length; i++) {
      final err = _validateRow(i);
      if (err != null) errors[i] = err;
    }
    setState(() {
      _rowErrors = errors;
    });
    if (errors.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All rows are valid'), backgroundColor: AppColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${errors.length} row(s) have errors — highlighted in red'), backgroundColor: AppColors.error),
      );
    }
  }

  Widget _buildImportProgressStep() {
    final progress = _total > 0 ? (_imported + _skipped) / _total : 0.0;
    return Center(
      child: Container(
        width: 400.w,
        padding: EdgeInsets.all(32.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            SizedBox(height: 20.h),
            Text('Importing... ${_imported + _skipped} / $_total', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
            SizedBox(height: 12.h),
            LinearProgressIndicator(value: progress, backgroundColor: AppColors.border, valueColor: const AlwaysStoppedAnimation(AppColors.accent)),
            SizedBox(height: 8.h),
            Text('$_imported imported, $_skipped skipped', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildImportDoneStep() {
    return Center(
      child: Container(
        width: 500.w,
        padding: EdgeInsets.all(32.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon('tick-circle', size: 64.sp, color: AppColors.success),
            SizedBox(height: 16.h),
            Text('Import Complete', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 12.h),
            Text('$_imported imported successfully, $_skipped skipped', style: TextStyle(fontSize: 13.sp)),
            if (_importErrors.isNotEmpty) ...[
              SizedBox(height: 16.h),
              Container(
                height: 150.h,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: ListView(
                  children: _importErrors.map((e) => Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text(e, style: TextStyle(fontSize: 13.sp, color: AppColors.error)),
                  )).toList(),
                ),
              ),
            ],
            SizedBox(height: 20.h),
            ElevatedButton(
              onPressed: _resetImport,
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
      ),
    );
  }
}
