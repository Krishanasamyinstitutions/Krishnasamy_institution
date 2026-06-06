import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/supabase_service.dart';
import '../../services/admission_service.dart';
import '../../widgets/app_icon.dart';

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
      _snack('Pick a Register Sequence first.', AppColors.warning);
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
            _toolbar(),
            Divider(height: 1.h, color: AppColors.border),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: _wReg + _wName + _wSex + _wCourse + _wClass + _wType + _wBatch + _wDob + _wAdm + _wYear + _wDel + 32,
                        child: Column(
                          children: [
                            _tableHeader(),
                            Expanded(
                              child: ListView.builder(
                                itemCount: _rows.length,
                                itemBuilder: (_, i) => _rowWidget(i),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            Divider(height: 1.h, color: AppColors.border),
            _actionBar(),
          ],
        ),
      ),
    );
  }

  Widget _header() => Padding(
        padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 14.h),
        child: Row(
          children: [
            const AppIcon('profile-add', size: 20, color: AppColors.primary),
            SizedBox(width: 10.w),
            Text('Fast Admission', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
            SizedBox(width: 10.w),
            Text('bulk entry — allocate classes later', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
          ],
        ),
      );

  Widget _toolbar() {
    return Padding(
      padding: EdgeInsets.all(12.w),
      child: Row(
        children: [
          Text('Register Sequence', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          SizedBox(width: 8.w),
          SizedBox(width: 180.w, child: _regSeqDropdown()),
          SizedBox(width: 10.w),
          _lastRegNoChip(),
          SizedBox(width: 8.w),
          OutlinedButton.icon(
            onPressed: _autoNumber,
            icon: const Icon(Icons.format_list_numbered, size: 16),
            label: const Text('Fill Reg Nos'),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _regSeqDropdown() => DropdownButtonFormField<String>(
        initialValue: _selectedRegSeqId,
        isExpanded: true,
        decoration: _cellDec(),
        hint: Text('Sequence', style: TextStyle(fontSize: 12.sp, color: AppColors.textLight)),
        items: _regSeqs.map((s) => DropdownMenuItem(value: s['rns_id'].toString(), child: Text(s['rnsname']?.toString() ?? '', overflow: TextOverflow.ellipsis))).toList(),
        onChanged: (v) => setState(() => _selectedRegSeqId = v),
      );

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
              Text('Last Reg No: ', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
              Text(_lastRegNo ?? '—',
                  style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.primary)),
            ],
          ),
        ),
      );

  Widget _tableHeader() {
    TextStyle s() => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
    Widget c(String t, double w) => SizedBox(width: w, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6.w), child: Text(t, style: s())));
    return Container(
      color: AppColors.tableHeadBg,
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      child: Row(
        children: [
          c('Reg. No', _wReg), c('Student Name', _wName), c('Sex', _wSex), c('Course', _wCourse),
          c('Class', _wClass), c('Adm Type', _wType), c('Batch', _wBatch), c('Birth Date', _wDob),
          c('Join Date', _wAdm), c('Adm Year', _wYear), c('', _wDel),
        ],
      ),
    );
  }

  Widget _rowWidget(int i) {
    final r = _rows[i];
    return Container(
      decoration: BoxDecoration(
        color: i.isEven ? Colors.white : AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.4))),
      ),
      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h),
      child: Row(
        children: [
          _cell(_wReg, _textCell(r.regNo)),
          _cell(_wName, _textCell(r.name)),
          _cell(_wSex, _dropCell(r.sex, _sexOptions.entries.map((e) => MapEntry(e.key, e.key)).toList(), (v) => setState(() => r.sex = v))),
          _cell(_wCourse, _dropCell(r.course, _courses.map((e) => MapEntry(e, e)).toList(), (v) => setState(() => r.course = v))),
          _cell(_wClass, _dropCell(r.cls, _classes.map((e) => MapEntry(e, e)).toList(), (v) => setState(() => r.cls = v))),
          _cell(_wType, _dropCell(r.admType, _admTypes.map((e) => MapEntry(e['admname'].toString(), e['admname'].toString())).toList(), (v) => setState(() => r.admType = v))),
          _cell(_wBatch, _textCell(r.batch)),
          _cell(_wDob, _dateCell(r.dob, (d) => setState(() => r.dob = d))),
          _cell(_wAdm, _dateCell(r.admDate, (d) => setState(() => r.admDate = d))),
          _cell(_wYear, _textCell(r.admYear)),
          _cell(_wDel, Center(
            child: InkWell(
              onTap: () => _removeRow(i),
              borderRadius: BorderRadius.circular(6.r),
              child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('trash', size: 15, color: AppColors.error)),
            ),
          )),
        ],
      ),
    );
  }

  Widget _cell(double w, Widget child) => SizedBox(width: w, child: Padding(padding: EdgeInsets.symmetric(horizontal: 3.w), child: child));

  InputDecoration _cellDec() => InputDecoration(
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r), borderSide: const BorderSide(color: AppColors.border)),
      );

  Widget _textCell(TextEditingController c) => TextField(
        controller: c,
        style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary),
        decoration: _cellDec(),
      );

  Widget _dropCell(String? value, List<MapEntry<String, String>> items, ValueChanged<String?> onChanged) {
    final values = items.map((e) => e.key).toList();
    return DropdownButtonFormField<String>(
      initialValue: values.contains(value) ? value : null,
      isExpanded: true,
      style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary),
      decoration: _cellDec(),
      items: items.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12.sp)))).toList(),
      onChanged: onChanged,
    );
  }

  Widget _dateCell(DateTime? value, ValueChanged<DateTime> onPick) {
    return InkWell(
      onTap: () async {
        final now = DateTime.now();
        final picked = await showDatePicker(context: context, initialDate: value ?? DateTime(now.year - 17), firstDate: DateTime(1950), lastDate: DateTime(now.year + 5));
        if (picked != null) onPick(picked);
      },
      child: InputDecorator(
        decoration: _cellDec(),
        child: Text(value == null ? '—' : _fmt(value), style: TextStyle(fontSize: 12.sp, color: value == null ? AppColors.textLight : AppColors.textPrimary)),
      ),
    );
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  Widget _actionBar() {
    final count = _rows.where((r) => !r.isBlank).length;
    return Padding(
      padding: EdgeInsets.all(12.w),
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
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }
}
