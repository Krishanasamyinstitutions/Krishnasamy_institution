import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/supabase_service.dart';
import '../../services/admission_service.dart';
import '../../models/admission_model.dart';
import '../../widgets/app_icon.dart';

/// Class Allocation — batch-allocate admitted (PENDING) admissions into classes.
/// Pick a course, assign each student a class via the grid, then Save to move
/// them all into students/parents/parentdetail at once.
class ClassAllocationScreen extends StatefulWidget {
  const ClassAllocationScreen({super.key});

  @override
  State<ClassAllocationScreen> createState() => _ClassAllocationScreenState();
}

class _ClassAllocationScreenState extends State<ClassAllocationScreen> {
  List<AdmissionModel> _pending = [];
  List<Map<String, dynamic>> _courseList = []; // {cour_id, courname}
  List<Map<String, dynamic>> _classList = [];  // {claname, cour_id}

  String? _selectedCourse;
  String _orderBy = 'Reg. No';
  final Map<int, String?> _rowClass = {}; // adm_id -> chosen class
  bool _loading = true;
  bool _saving = false;

  static const _orderOptions = ['Reg. No', 'Student Name', 'Sex + Student Name'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  int get _insId => context.read<AuthProvider>().insId ?? 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    final insId = _insId;
    try {
      final results = await Future.wait<dynamic>([
        AdmissionService.getAdmissions(insId),
        SupabaseService.fromSchema('course').select('cour_id, courname').eq('ins_id', insId).eq('activestatus', 1),
        SupabaseService.fromSchema('class').select('claname, cour_id').eq('ins_id', insId).eq('activestatus', 1),
      ]);
      if (!mounted) return;
      setState(() {
        _pending = (results[0] as List<AdmissionModel>).where((a) => a.isPending).toList();
        _courseList = List<Map<String, dynamic>>.from(results[1] as List);
        _classList = List<Map<String, dynamic>>.from(results[2] as List);
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Failed to load. ${friendlyError(e)}', AppColors.error);
      }
    }
  }

  // ── options ───────────────────────────────────────────────────────
  List<String> get _courseNames =>
      (_courseList.map((e) => e['courname']?.toString().trim() ?? '')
          .where((s) => s.isNotEmpty).toSet().toList()
        ..sort());

  List<String> _classNamesFor(String? courname) {
    Iterable<Map<String, dynamic>> src = _classList;
    if (courname != null && courname.trim().isNotEmpty) {
      final cm = _courseList.firstWhere(
        (c) => (c['courname']?.toString().trim() ?? '') == courname.trim(),
        orElse: () => const {},
      );
      final courId = cm['cour_id'];
      src = courId == null
          ? const <Map<String, dynamic>>[]
          : _classList.where((cl) => cl['cour_id'] == courId);
    }
    return (src.map((e) => e['claname']?.toString().trim() ?? '')
        .where((s) => s.isNotEmpty).toSet().toList()
      ..sort());
  }

  /// Pending admissions for the selected course, sorted by the Order By choice.
  List<AdmissionModel> get _rows {
    if (_selectedCourse == null) return [];
    final list = _pending
        .where((a) => (a.courname?.trim() ?? '') == _selectedCourse)
        .toList();
    list.sort((a, b) {
      switch (_orderBy) {
        case 'Student Name':
          return a.stuname.toLowerCase().compareTo(b.stuname.toLowerCase());
        case 'Sex + Student Name':
          final s = a.stugender.compareTo(b.stugender);
          return s != 0 ? s : a.stuname.toLowerCase().compareTo(b.stuname.toLowerCase());
        default: // Reg. No
          return a.admno.compareTo(b.admno);
      }
    });
    return list;
  }

  // ── actions ───────────────────────────────────────────────────────
  /// Pick one class and apply it to every student in the current course filter.
  Future<void> _autoFill() async {
    final options = _classNamesFor(_selectedCourse);
    if (options.isEmpty) {
      _snack('No classes available for $_selectedCourse.', AppColors.warning);
      return;
    }
    String? picked = options.length == 1 ? options.first : null;
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Auto Fill class'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Apply one class to all ${_rows.length} student(s) in $_selectedCourse.',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              SizedBox(height: 14.h),
              DropdownButtonFormField<String>(
                initialValue: picked,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Class'),
                items: options.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                onChanged: (v) => setLocal(() => picked = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () { if (picked != null) Navigator.pop(ctx, picked); },
              child: const Text('Apply to all'),
            ),
          ],
        ),
      ),
    );
    if (chosen == null) return;
    setState(() {
      for (final a in _rows) {
        _rowClass[a.admId] = chosen;
      }
    });
  }

  Future<void> _save() async {
    final toAllocate = _rows.where((a) => (_rowClass[a.admId] ?? '').isNotEmpty).toList();
    if (toAllocate.isEmpty) {
      _snack('Assign a class to at least one student first.', AppColors.warning);
      return;
    }
    final by = context.read<AuthProvider>().userName;
    setState(() => _saving = true);
    int done = 0;
    final failures = <String>[];
    for (final a in toAllocate) {
      try {
        await AdmissionService.allocateClass(
          admId: a.admId,
          className: _rowClass[a.admId]!,
          stuadmno: a.admno,
          allocatedBy: by,
        );
        done++;
      } catch (e) {
        failures.add('${a.admno} ${a.stuname}: ${friendlyError(e)}');
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _rowClass.clear();
    await _load();
    if (!mounted) return;
    if (failures.isEmpty) {
      _snack('Allocated $done student(s).', AppColors.success);
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Allocated $done, ${failures.length} failed'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [for (final f in failures) Padding(
                  padding: EdgeInsets.only(bottom: 4.h),
                  child: Text('• $f', style: TextStyle(fontSize: 12.sp, color: AppColors.error)),
                )],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    }
  }

  void _snack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
  }

  // ── build ─────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Container(
        decoration: AppCard.decoration(),
        child: Column(
          children: [
            _header(),
            Divider(height: 1.h, color: AppColors.border),
            _controls(),
            Divider(height: 1.h, color: AppColors.border),
            _tableHeader(),
            Expanded(child: _body()),
            Divider(height: 1.h, color: AppColors.border),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 14.h),
      child: Row(
        children: [
          const AppIcon('book-1', size: 20, color: AppColors.primary),
          SizedBox(width: 10.w),
          Text('Class Allocation',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(width: 10.w),
          Text('Admitted — pending allocation',
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          const Spacer(),
          Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 3.h),
            decoration: BoxDecoration(
              color: AppColors.warning.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12.r),
            ),
            child: Text('${_pending.length} pending',
                style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.warning)),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: EdgeInsets.all(14.w),
      child: Row(
        children: [
          _miniLabel('Course'),
          SizedBox(width: 8.w),
          SizedBox(width: 240.w, child: _courseDropdown()),
          SizedBox(width: 20.w),
          _miniLabel('Order By'),
          SizedBox(width: 8.w),
          SizedBox(width: 200.w, child: _orderDropdown()),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: _selectedCourse == null ? null : _autoFill,
            icon: const Icon(Icons.auto_fix_high, size: 16),
            label: const Text('Auto Fill'),
          ),
        ],
      ),
    );
  }

  Widget _miniLabel(String t) => Text(t,
      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary));

  Widget _courseDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedCourse,
      isExpanded: true,
      decoration: _dec(),
      hint: Text('Select course', style: TextStyle(fontSize: 13.sp, color: AppColors.textLight)),
      items: _courseNames.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
      onChanged: (v) => setState(() {
        _selectedCourse = v;
        _rowClass.clear();
      }),
    );
  }

  Widget _orderDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _orderBy,
      isExpanded: true,
      decoration: _dec(),
      items: _orderOptions.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: (v) => setState(() => _orderBy = v ?? 'Reg. No'),
    );
  }

  Widget _tableHeader() {
    TextStyle s() => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
    return Container(
      color: AppColors.tableHeadBg,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      child: Row(
        children: [
          SizedBox(width: 140.w, child: Text('Reg. No', style: s())),
          Expanded(flex: 3, child: Text('Student Name', style: s())),
          SizedBox(width: 80.w, child: Text('Sex', style: s())),
          Expanded(flex: 2, child: Text('Course', style: s())),
          SizedBox(width: 220.w, child: Text('Class', style: s())),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_selectedCourse == null) {
      return Center(
        child: Text('Select a course to list admitted students',
            style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
      );
    }
    final rows = _rows;
    if (rows.isEmpty) {
      return Center(
        child: Text('No pending admissions for $_selectedCourse',
            style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
      );
    }
    final options = _classNamesFor(_selectedCourse);
    return ListView.separated(
      itemCount: rows.length,
      separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border),
      itemBuilder: (_, i) => _row(rows[i], options),
    );
  }

  Widget _row(AdmissionModel a, List<String> options) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
      child: Row(
        children: [
          SizedBox(width: 140.w, child: Text(a.admno, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
          Expanded(flex: 3, child: Text(a.stuname, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
          SizedBox(width: 80.w, child: Text(a.genderLabel, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
          Expanded(flex: 2, child: Text(a.courname ?? '—', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
          SizedBox(
            width: 220.w,
            child: DropdownButtonFormField<String>(
              initialValue: options.contains(_rowClass[a.admId]) ? _rowClass[a.admId] : null,
              isExpanded: true,
              isDense: true,
              decoration: _dec(),
              hint: Text('Select class', style: TextStyle(fontSize: 12.sp, color: AppColors.textLight)),
              items: options.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (v) => setState(() => _rowClass[a.admId] = v),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionBar() {
    final count = _rows.where((a) => (_rowClass[a.admId] ?? '').isNotEmpty).length;
    return Padding(
      padding: EdgeInsets.all(14.w),
      child: Row(
        children: [
          if (count > 0)
            Text('$count selected for allocation',
                style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _saving || count == 0 ? null : _save,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: Text(_saving ? 'Allocating…' : 'Save Allocation'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  InputDecoration _dec() => InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8.r),
            borderSide: const BorderSide(color: AppColors.border)),
      );
}
