import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/supabase_service.dart';
import '../../services/admission_service.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/focusable_tap.dart';

/// Fast Admission — spreadsheet-style bulk entry. Each row is a quick admission
/// captured into public.admission (PENDING); allocate classes later in the
/// Class Allocation screen. Supports register-sequence auto-numbering.
class FastAdmissionScreen extends StatefulWidget {
  const FastAdmissionScreen({super.key});

  @override
  State<FastAdmissionScreen> createState() => _FastAdmissionScreenState();
}

class _FastRow {
  final regNo = TextEditingController();
  final name = TextEditingController();
  final batch = TextEditingController();
  final admYear = TextEditingController();
  String? sex; // M | F | T
  String? course;
  String? cls;
  String? admType;
  DateTime? dob;
  DateTime admDate = DateTime.now();

  void dispose() {
    regNo.dispose();
    name.dispose();
    batch.dispose();
    admYear.dispose();
  }

  bool get isBlank => name.text.trim().isEmpty && regNo.text.trim().isEmpty;
}

class _FastAdmissionScreenState extends State<FastAdmissionScreen> {
  final List<_FastRow> _rows = [];
  List<String> _courses = [];
  List<String> _classes = [];
  List<Map<String, dynamic>> _admTypes = [];
  List<Map<String, dynamic>> _years = [];
  List<Map<String, dynamic>> _regSeqs = [];
  String? _selectedYrId;
  String? _selectedYrLabel;
  String? _selectedRegSeqId;
  String? _lastRegNo; // last admission reg no — shown inline next to the label
  bool _loading = true;
  bool _saving = false;

  static const _sexOptions = {'M': 'Male', 'F': 'Female', 'T': 'Other'};

  @override
  void initState() {
    super.initState();
    _load();
    _refreshLastRegNo();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  int get _insId => context.read<AuthProvider>().insId ?? 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    final insId = _insId;
    try {
      final results = await Future.wait<dynamic>([
        SupabaseService.fromSchema('course').select('courname').eq('ins_id', insId).eq('activestatus', 1),
        SupabaseService.fromSchema('class').select('claname').eq('ins_id', insId).eq('activestatus', 1),
        SupabaseService.getAdmissionTypes(insId),
        SupabaseService.getYears(insId),
        SupabaseService.fromSchema('regnoseq').select('*').eq('activestatus', 1).order('rns_id', ascending: true),
      ]);
      if (!mounted) return;
      setState(() {
        _courses = (results[0] as List).map((e) => e['courname']?.toString().trim() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
        _classes = (results[1] as List).map((e) => e['claname']?.toString().trim() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
        _admTypes = List<Map<String, dynamic>>.from(results[2] as List);
        _years = results[3] as List<Map<String, dynamic>>;
        _regSeqs = List<Map<String, dynamic>>.from(results[4] as List);
        if (_years.isNotEmpty) {
          _selectedYrId = _years.first['yr_id'].toString();
          _selectedYrLabel = _years.first['yrlabel']?.toString();
        }
        if (_rows.isEmpty) {
          for (var i = 0; i < 8; i++) {
            _rows.add(_FastRow());
          }
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        _snack('Failed to load. ${friendlyError(e)}', AppColors.error);
      }
    }
  }

  void _addRow() => setState(() => _rows.add(_FastRow()));

  void _removeRow(int i) => setState(() => _rows.removeAt(i).dispose());

  int _seqNext(Map<String, dynamic> seq) {
    final cur = (seq['rnscurrent'] as num?)?.toInt() ?? 0;
    final start = (seq['rnsstart'] as num?)?.toInt() ?? 1;
    return cur < start ? start : cur + 1;
  }

  String _seqFormat(Map<String, dynamic> seq, int n) {
    final width = (seq['rnswidth'] as num?)?.toInt() ?? 0;
    final padded = n.toString().padLeft(width, '0');
    final affix = seq['rnsaffix']?.toString() ?? '';
    return (seq['rnsmode']?.toString() ?? 'P') == 'P' ? '$affix$padded' : '$padded$affix';
  }

  /// Fill Reg No for every non-blank row sequentially from the chosen sequence.
  void _autoNumber() {
    if (_selectedRegSeqId == null) {
      _snack('Pick an Admission Sequence first.', AppColors.warning);
      return;
    }
    final seq = _regSeqs.firstWhere((s) => s['rns_id'].toString() == _selectedRegSeqId, orElse: () => const {});
    if (seq.isEmpty) return;
    var n = _seqNext(seq);
    setState(() {
      for (final r in _rows) {
        if (r.isBlank) continue;
        r.regNo.text = _seqFormat(seq, n);
        n++;
      }
    });
  }

  /// Fetch the most-recent admission reg no and store it for the inline label.
  Future<void> _refreshLastRegNo() async {
    try {
      final res = await SupabaseService.client
          .from('admission')
          .select('admno')
          .eq('ins_id', _insId)
          .order('adm_id', ascending: false)
          .limit(1)
          .maybeSingle();
      final last = res?['admno']?.toString();
      if (!mounted) return;
      setState(() => _lastRegNo = (last == null || last.isEmpty) ? null : last);
    } catch (_) {
      // leave the previous value in place on failure
    }
  }

  Future<void> _saveAll() async {
    final auth = context.read<AuthProvider>();
    final entries = _rows.where((r) => !r.isBlank).toList();
    if (entries.isEmpty) {
      _snack('Enter at least one row.', AppColors.warning);
      return;
    }
    // validate
    final problems = <String>[];
    for (var i = 0; i < entries.length; i++) {
      final r = entries[i];
      final miss = <String>[];
      if (r.regNo.text.trim().isEmpty) miss.add('Reg No');
      if (r.name.text.trim().isEmpty) miss.add('Name');
      if (r.sex == null) miss.add('Sex');
      if (r.dob == null) miss.add('Birth Date');
      if (miss.isNotEmpty) problems.add('Row ${_rows.indexOf(r) + 1}: ${miss.join(', ')}');
    }
    if (problems.isNotEmpty) {
      _snack('Fill required fields — ${problems.first}${problems.length > 1 ? ' (+${problems.length - 1} more)' : ''}', AppColors.error);
      return;
    }

    setState(() => _saving = true);
    int done = 0;
    int maxSeqNum = 0;
    final failures = <String>[];
    for (final r in entries) {
      try {
        await AdmissionService.addAdmission({
          'ins_id': auth.insId ?? 1,
          'inscode': auth.inscode ?? '',
          'yr_id': int.tryParse(_selectedYrId ?? '0') ?? 0,
          'yrlabel': _selectedYrLabel ?? '',
          'admno': r.regNo.text.trim(),
          'admdate': r.admDate.toIso8601String().split('T').first,
          'admsource': 'WALK-IN',
          'stuname': r.name.text.trim(),
          'stugender': r.sex,
          'studob': r.dob?.toIso8601String().split('T').first,
          'courname': r.course,
          'stuclass': r.cls,
          'admname': r.admType,
          'batch': r.batch.text.trim().isEmpty ? null : r.batch.text.trim(),
          'admittyear': r.admYear.text.trim().isEmpty ? null : r.admYear.text.trim(),
          'createdby': auth.userName,
        });
        done++;
      } catch (e) {
        failures.add('${r.regNo.text.trim()} ${r.name.text.trim()}: ${friendlyError(e)}');
      }
    }
    // bump the register sequence by the number of rows numbered from it
    if (_selectedRegSeqId != null) {
      final seq = _regSeqs.firstWhere((s) => s['rns_id'].toString() == _selectedRegSeqId, orElse: () => const {});
      if (seq.isNotEmpty) {
        maxSeqNum = _seqNext(seq) + done - 1;
        try {
          await AdmissionService.bumpRegSeqCurrent(int.parse(_selectedRegSeqId!), maxSeqNum);
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _refreshLastRegNo();

    if (failures.isEmpty) {
      _snack('Saved $done admission(s).', AppColors.success);
      // reset to fresh blank rows
      for (final r in _rows) {
        r.dispose();
      }
      setState(() {
        _rows.clear();
        for (var i = 0; i < 8; i++) {
          _rows.add(_FastRow());
        }
        _selectedRegSeqId = null;
      });
      _load();
    } else {
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Saved $done, ${failures.length} failed'),
          content: SizedBox(
            width: 460,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [for (final f in failures) Padding(padding: EdgeInsets.only(bottom: 4.h), child: Text('• $f', style: TextStyle(fontSize: 12.sp, color: AppColors.error)))],
              ),
            ),
          ),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      );
    }
  }

  void _snack(String m, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  // ── columns ───────────────────────────────────────────────────────
  static const _wReg = 130.0, _wName = 190.0, _wSex = 80.0, _wCourse = 150.0,
      _wClass = 120.0, _wType = 130.0, _wBatch = 80.0, _wDob = 115.0, _wAdm = 115.0, _wYear = 90.0, _wDel = 44.0;

  // Page shell per admission-design.md § 1: outer white card with padding,
  // inner bordered table card matches Section Allocation pattern.
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            // Outer white card.
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(16.w, 4.h, 16.w, 12.h),
              child: Column(
                children: [
                  _topBar(),
                  SizedBox(height: 8.h),
                  // Inner bordered table card.
                  Expanded(
                    child: Container(
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : LayoutBuilder(builder: (ctx, constraints) {
                              // Scale columns so they fill the inner card
                              // when viewport is wider than the base width;
                              // otherwise keep base sizes (allow H scroll).
                              const baseSum = _wReg + _wName + _wSex + _wCourse + _wClass + _wType + _wBatch + _wDob + _wAdm + _wYear + _wDel + 32;
                              final viewport = constraints.maxWidth;
                              final scale = viewport > baseSum ? viewport / baseSum : 1.0;
                              final tableW = scale > 1 ? viewport : baseSum;
                              return SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                physics: scale > 1 ? const NeverScrollableScrollPhysics() : null,
                                child: SizedBox(
                                  width: tableW,
                                  child: Column(
                                    children: [
                                      _tableHeader(scale),
                                      Expanded(
                                        child: FocusTraversalGroup(
                                          child: ListView.builder(
                                            itemCount: _rows.length,
                                            itemBuilder: (_, i) => _rowWidget(i, scale),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            }),
                    ),
                  ),
                  SizedBox(height: 8.h),
                  _actionBar(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Single top bar: icon + "Fast Admission" + subtitle on the left,
  /// pushed-right Sequence dropdown + Last-no chip + navy Fill button.
  Widget _topBar() {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      child: Row(
        children: [
          const AppIcon('profile-add', size: 20, color: AppColors.primary),
          SizedBox(width: 10.w),
          Text('Fast Admission',
              style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(width: 10.w),
          Text('bulk entry — allocate sections later',
              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          const Spacer(),
          SizedBox(width: 200.w, child: _regSeqDropdown()),
          SizedBox(width: 10.w),
          _lastRegNoChip(),
          SizedBox(width: 10.w),
          // Sized to match the Import CSV/Excel button used elsewhere in the
          // project (compact / expanded responsive).
          Builder(builder: (context) {
            final compact = MediaQuery.of(context).size.width <= 1366;
            final btnHeight = compact ? 30.0 : 40.0;
            final iconSize = compact ? 12.0 : 16.0;
            final hPad = compact ? 10.0 : 18.0;
            final radius = compact ? 6.0 : 10.0;
            final textSize = compact ? 11.0 : 13.0;
            return SizedBox(
              height: btnHeight,
              child: ElevatedButton.icon(
                onPressed: _autoNumber,
                icon: Icon(Icons.format_list_numbered, size: iconSize, color: Colors.white),
                label: const Text('Fill Admission Nos'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: EdgeInsets.symmetric(horizontal: hPad),
                  textStyle: TextStyle(fontSize: textSize, fontWeight: FontWeight.w600),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _regSeqDropdown() => DropdownButtonFormField<String>(
        initialValue: _selectedRegSeqId,
        isExpanded: true,
        dropdownColor: Colors.white,
        borderRadius: BorderRadius.circular(12),
        elevation: 6,
        icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
        style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
        decoration: _topBarDec(filled: _selectedRegSeqId != null),
        hint: Text('Select Sequence', style: TextStyle(fontSize: 13.sp, color: AppColors.textLight)),
        items: _regSeqs.map((s) => DropdownMenuItem(
              value: s['rns_id'].toString(),
              child: Text(s['rnsname']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
            )).toList(),
        selectedItemBuilder: (context) => _regSeqs.map((s) => Align(alignment: Alignment.centerLeft, child: Text(s['rnsname']?.toString() ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent)))).toList(),
        onChanged: (v) => setState(() => _selectedRegSeqId = v),
      );

  // Taller decoration for the top-bar Sequence dropdown so it lines up with
  // the navy Fill button visually.
  InputDecoration _topBarDec({bool filled = false, String? hint}) {
    final compact = MediaQuery.of(context).size.width <= 1366;
    final hPad = compact ? 10.0 : 14.0;
    final vPad = compact ? 8.0 : 14.0;
    final radius = compact ? 6.0 : 8.0;
    final idle = filled ? AppColors.accent : AppColors.border;
    return InputDecoration(
      contentPadding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      filled: true,
      fillColor: Colors.white,
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.6), fontSize: 13.sp),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: idle, width: 1.5)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: BorderSide(color: idle, width: 1.5)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radius),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
    );
  }

  /// Inline display of the last admission reg no, sitting next to the
  /// Register Sequence label. Tap to refresh.
  Widget _lastRegNoChip() => InkWell(
        onTap: _refreshLastRegNo,
        borderRadius: BorderRadius.circular(8.r),
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8.r),
            border: Border.all(color: AppColors.primary.withValues(alpha: 0.20)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.history, size: 14.sp, color: AppColors.primary),
              SizedBox(width: 6.w),
              Text('Last Admission No: ', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              Text(_lastRegNo ?? '—',
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      );

  Widget _tableHeader(double scale) {
    TextStyle s() => TextStyle(
        fontSize: 12.sp,
        fontWeight: FontWeight.w700,
        color: AppColors.textPrimary,
        letterSpacing: 0.3);
    Widget c(String t, double w) => SizedBox(width: w * scale, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6.w), child: Text(t, style: s())));
    return Container(
      color: AppColors.tableHeadBg,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      child: Row(
        children: [
          c('ADMISSION NO', _wReg), c('STUDENT NAME', _wName), c('SEX', _wSex), c('COURSE', _wCourse),
          c('CLASS', _wClass), c('ADM TYPE', _wType), c('BATCH', _wBatch), c('BIRTH DATE', _wDob),
          c('JOIN DATE', _wAdm), c('ADM YEAR', _wYear), c('', _wDel),
        ],
      ),
    );
  }

  Widget _rowWidget(int i, double scale) {
    final r = _rows[i];
    double w(double base) => base * scale;
    return FocusTraversalGroup(
      child: Container(
      decoration: BoxDecoration(
        color: i.isEven ? Colors.white : AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.4))),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 7.h),
      child: Row(
        children: [
          _cell(w(_wReg), _textCell(r.regNo)),
          _cell(w(_wName), _textCell(r.name)),
          _cell(w(_wSex), _dropCell(r.sex, _sexOptions.entries.map((e) => MapEntry(e.key, e.key)).toList(), (v) => setState(() => r.sex = v), hint: 'Select sex')),
          _cell(w(_wCourse), _dropCell(r.course, _courses.map((e) => MapEntry(e, e)).toList(), (v) => setState(() => r.course = v), hint: 'Select course')),
          _cell(w(_wClass), _dropCell(r.cls, _classes.map((e) => MapEntry(e, e)).toList(), (v) => setState(() => r.cls = v), hint: 'Select class')),
          _cell(w(_wType), _dropCell(r.admType, _admTypes.map((e) => MapEntry(e['admname'].toString(), e['admname'].toString())).toList(), (v) => setState(() => r.admType = v), hint: 'Select type')),
          _cell(w(_wBatch), _textCell(r.batch)),
          _cell(w(_wDob), _dateCell(r.dob, (d) => setState(() => r.dob = d))),
          _cell(w(_wAdm), _dateCell(r.admDate, (d) => setState(() => r.admDate = d))),
          _cell(w(_wYear), _textCell(r.admYear)),
          _cell(w(_wDel), Center(
            child: InkWell(
              onTap: () => _removeRow(i),
              borderRadius: BorderRadius.circular(6.r),
              child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('trash', size: 15, color: AppColors.error)),
            ),
          )),
        ],
      ),
      ),
    );
  }

  Widget _cell(double w, Widget child) => SizedBox(width: w, child: Padding(padding: EdgeInsets.symmetric(horizontal: 3.w), child: child));

  InputDecoration _cellDec({bool filled = false, String? hint}) {
    final idle = filled ? AppColors.accent : AppColors.border;
    return InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
        filled: true,
        fillColor: Colors.white,
        hintText: hint,
        hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.6), fontSize: 11.sp),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r), borderSide: BorderSide(color: idle, width: 1.5)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r), borderSide: BorderSide(color: idle, width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
      );
  }

  Widget _textCell(TextEditingController c) {
    final filled = c.text.trim().isNotEmpty;
    return TextField(
        controller: c,
        style: TextStyle(fontSize: 11.sp, color: filled ? AppColors.accent : AppColors.textPrimary, fontWeight: filled ? FontWeight.w600 : null),
        decoration: _cellDec(filled: filled),
        onChanged: (_) => setState(() {}),
      );
  }

  Widget _dropCell(String? value, List<MapEntry<String, String>> items, ValueChanged<String?> onChanged, {String? hint}) {
    final values = items.map((e) => e.key).toList();
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : null,
      isExpanded: true,
      dropdownColor: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 6,
      icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
      style: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary),
      decoration: _cellDec(filled: values.contains(value), hint: hint),
      items: items.map((e) => DropdownMenuItem(
            value: e.key,
            child: Text(e.value, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
          )).toList(),
      selectedItemBuilder: (context) => items.map((e) => Align(alignment: Alignment.centerLeft, child: Text(e.value, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600, color: AppColors.accent)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _dateCell(DateTime? value, ValueChanged<DateTime> onPick) {
    final filled = value != null;
    return FocusableTap(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(context: context, initialDate: value ?? DateTime(now.year - 17), firstDate: DateTime(1950), lastDate: DateTime(now.year + 5));
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: _cellDec(filled: filled),
        child: Text(value == null ? '—' : _fmt(value), style: TextStyle(fontSize: 11.sp, color: value == null ? AppColors.textLight : AppColors.accent, fontWeight: value == null ? null : FontWeight.w600)),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  Widget _actionBar() {
    final count = _rows.where((r) => !r.isBlank).length;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h),
      child: Row(
        children: [
          OutlinedButton.icon(onPressed: _addRow, icon: const Icon(Icons.add, size: 16), label: const Text('Add Row')),
          SizedBox(width: 10.w),
          Text('$count filled', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: _saving || count == 0 ? null : _saveAll,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: Text(_saving ? 'Saving…' : 'Save All'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
