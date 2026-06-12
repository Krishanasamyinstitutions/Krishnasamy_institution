import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/card_title_block.dart';

/// Fee Concession — per-student concession entry. Look up a student, see every
/// unpaid fee demand with its fee definition, enter a concession per fee type
/// (Balance updates live), then Save to write conamount + balancedue back to
/// feedemand. Modeled on the legacy "Concession Entry" screen.
class FeeConcessionScreen extends StatefulWidget {
  const FeeConcessionScreen({super.key});

  @override
  State<FeeConcessionScreen> createState() => _FeeConcessionScreenState();
}

class _ConRow {
  final int demId;
  final String feeType;
  final String term;
  final String cls;
  final double feeAmount;
  final double paidAmount;
  final TextEditingController conCtrl;
  _ConRow({
    required this.demId,
    required this.feeType,
    required this.term,
    required this.cls,
    required this.feeAmount,
    required this.paidAmount,
    required double concession,
  }) : conCtrl = TextEditingController(text: concession > 0 ? concession.toStringAsFixed(0) : '');

  double get concession {
    final c = double.tryParse(conCtrl.text.trim()) ?? 0;
    final max = feeAmount - paidAmount;
    return c < 0 ? 0 : (c > max ? max : c);
  }

  double get balance {
    final b = feeAmount - paidAmount - concession;
    return b > 0 ? b : 0;
  }

  void dispose() => conCtrl.dispose();
}

class _FeeConcessionScreenState extends State<FeeConcessionScreen> {
  final _searchCtrl = TextEditingController();
  Map<String, dynamic>? _student;
  List<_ConRow> _rows = [];
  List<Map<String, dynamic>> _suggestions = [];
  List<Map<String, dynamic>> _conTypes = []; // concessioncategory master
  // Sentinel for the explicit "None" (no concession) option, so it stays a
  // real selectable value distinct from "unset". While _conTypeId is null
  // (unset) the dropdown shows its grey "Select Concession" placeholder; once
  // a value is picked (including None) the field turns amber.
  static const _kNone = '__none__';
  String? _conTypeId; // selected concession type (con_id); null = unset
  bool _loading = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConTypes();
    _searchFocus.addListener(() {
      if (!_searchFocus.hasFocus) _hideSuggestions();
    });
  }

  Future<void> _loadConTypes() async {
    try {
      final res = await SupabaseService.fromSchema('concessioncategory')
          .select('con_id, condesc')
          .eq('ins_id', _insId)
          .eq('activestatus', 1)
          .order('condesc', ascending: true);
      if (mounted) setState(() => _conTypes = List<Map<String, dynamic>>.from(res as List));
    } catch (_) {}
  }

  @override
  void dispose() {
    _hideSuggestions();
    _searchFocus.dispose();
    _searchCtrl.dispose();
    for (final r in _rows) {
      r.dispose();
    }
    super.dispose();
  }

  int get _insId => context.read<AuthProvider>().insId ?? 1;

  Future<void> _suggest(String q) async {
    final term = q.trim();
    if (term.length < 2) {
      setState(() => _suggestions = []);
      _hideSuggestions();
      return;
    }
    try {
      final rows = await SupabaseService.fromSchema('students')
          .select('stu_id, stuname, stuadmno, stuclass, courname, admname')
          .eq('ins_id', _insId)
          .eq('activestatus', 1)
          .or('stuadmno.ilike.$term%,stuname.ilike.%$term%')
          .limit(12);
      if (!mounted) return;
      setState(() => _suggestions = List<Map<String, dynamic>>.from(rows));
      if (_suggestions.isNotEmpty && _searchFocus.hasFocus) {
        _showSuggestions();
      } else {
        _hideSuggestions();
      }
    } catch (_) {}
  }

  void _pick(Map<String, dynamic> s) {
    _searchCtrl.text = s['stuadmno']?.toString() ?? '';
    _hideSuggestions();
    setState(() => _suggestions = []);
    _searchFocus.unfocus();
    _load(s);
  }

  Future<void> _search() async {
    final q = _searchCtrl.text.trim();
    if (q.isEmpty) return;
    _hideSuggestions();
    setState(() {
      _error = null;
      _suggestions = [];
    });
    try {
      var rows = await SupabaseService.fromSchema('students')
          .select('stu_id, stuname, stuadmno, stuclass, courname, admname')
          .eq('ins_id', _insId)
          .eq('stuadmno', q)
          .eq('activestatus', 1)
          .limit(1);
      if ((rows as List).isEmpty) {
        rows = await SupabaseService.fromSchema('students')
            .select('stu_id, stuname, stuadmno, stuclass, courname, admname')
            .eq('ins_id', _insId)
            .eq('activestatus', 1)
            .ilike('stuname', '%$q%')
            .limit(1);
      }
      if ((rows as List).isEmpty) {
        setState(() {
          _error = 'No student found matching "$q"';
          _student = null;
        });
        return;
      }
      await _load(Map<String, dynamic>.from(rows.first as Map));
    } catch (e) {
      setState(() => _error = friendlyError(e));
    }
  }

  Future<void> _load(Map<String, dynamic> student) async {
    _hideSuggestions();
    setState(() {
      _loading = true;
      _student = student;
      for (final r in _rows) {
        r.dispose();
      }
      _rows = [];
    });
    try {
      final admno = student['stuadmno']?.toString() ?? '';
      final res = await SupabaseService.fromSchema('feedemand')
          .select('dem_id, stuclass, demfeeterm, demfeetype, feeamount, conamount, paidamount, balancedue, con_id, collectible')
          .eq('ins_id', _insId)
          .eq('stuadmno', admno)
          .eq('activestatus', 1)
          .eq('paidstatus', 'U')
          .order('demfeeterm', ascending: true)
          .order('demfeetype', ascending: true);
      final list = (res as List).map((e) {
        final m = e as Map<String, dynamic>;
        return _ConRow(
          demId: m['dem_id'] is int ? m['dem_id'] as int : int.tryParse(m['dem_id'].toString()) ?? 0,
          feeType: m['demfeetype']?.toString() ?? '',
          term: m['demfeeterm']?.toString() ?? '',
          cls: m['stuclass']?.toString() ?? '',
          feeAmount: (m['feeamount'] as num?)?.toDouble() ?? 0,
          paidAmount: (m['paidamount'] as num?)?.toDouble() ?? 0,
          concession: (m['conamount'] as num?)?.toDouble() ?? 0,
        );
      }).toList();
      // Pre-select the concession type already on the student's demands (if any).
      String? existingConId;
      for (final e in (res as List)) {
        final cid = (e as Map)['con_id'];
        if (cid != null) {
          existingConId = cid.toString();
          break;
        }
      }
      if (!mounted) return;
      setState(() {
        _rows = list;
        if (existingConId != null && _conTypes.any((t) => t['con_id'].toString() == existingConId)) {
          _conTypeId = existingConId;
        }
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  double get _totalCon => _rows.fold(0.0, (s, r) => s + r.concession);
  double get _totalBal => _rows.fold(0.0, (s, r) => s + r.balance);
  double get _totalDef => _rows.fold(0.0, (s, r) => s + r.feeAmount);

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() => _saving = true);
    try {
      final conId = (_conTypeId != null && _conTypeId != _kNone) ? int.tryParse(_conTypeId!) : null;
      for (final r in _rows) {
        await SupabaseService.fromSchema('feedemand').update({
          'con_id': r.concession > 0 ? conId : null,
          'conamount': r.concession,
          'balancedue': r.balance,
          'reconbalancedue': r.balance,
        }).eq('dem_id', r.demId);
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Concession saved.', AppColors.success);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        _snack('Save failed. ${friendlyError(e)}', AppColors.error);
      }
    }
  }

  void _clear() {
    setState(() {
      _searchCtrl.clear();
      _student = null;
      for (final r in _rows) {
        r.dispose();
      }
      _rows = [];
      _suggestions = [];
      _conTypeId = null; // back to unset so the placeholder shows again
      _error = null;
    });
  }

  void _snack(String m, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  final LayerLink _searchFieldLink = LayerLink();
  final FocusNode _searchFocus = FocusNode();
  OverlayEntry? _suggestionOverlay;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.of(context).size.width <= 1366;
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _topBar(compact),
          SizedBox(height: 12.h),
          Expanded(
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8.r),
                border: Border.all(color: AppColors.border),
              ),
              child: _student == null
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search, size: 32.sp, color: AppColors.textLight),
                          SizedBox(height: 8.h),
                          Text(
                            _error ?? 'Search a student by Register No or Name',
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: _error != null ? AppColors.error : AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _grid(),
            ),
          ),
          if (_student != null) ...[
            SizedBox(height: 12.h),
            _footer(),
          ],
        ],
      ),
    );
  }

  /// Single-row top bar: title block + search field (with auto-popup) +
  /// concession dropdown + Clear button. No Search button — typing triggers
  /// the suggestion popup, selecting a suggestion loads the student.
  Widget _topBar(bool compact) {
    final btnHeight = compact ? 36.0 : 44.0;
    final searchWidth = compact ? 260.0 : 340.0;
    final dropWidth = compact ? 200.0 : 240.0;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 4.h),
      child: Row(children: [
        const CardTitleBlock(
          icon: 'receipt-discount',
          title: 'Fee Concession',
          subtitle: 'apply concession against a student\'s fee demands',
        ),
        const Spacer(),
        if (_student != null) ...[
          _studentChip(),
          SizedBox(width: 12.w),
        ],
        // Search field with anchored auto-popup
        CompositedTransformTarget(
          link: _searchFieldLink,
          child: SizedBox(
            width: searchWidth,
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocus,
              style: _fieldTextStyle(context).copyWith(color: _searchCtrl.text.trim().isNotEmpty ? AppColors.accent : null, fontWeight: FontWeight.w600),
              decoration: _filledFieldDec(context, 'Register No or Student Name', filled: _searchCtrl.text.trim().isNotEmpty).copyWith(
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textLight),
                suffixIcon: _searchCtrl.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close, size: 16),
                        splashRadius: 16,
                        onPressed: () {
                          _searchCtrl.clear();
                          _hideSuggestions();
                          setState(() => _suggestions = []);
                        },
                      ),
              ),
              onChanged: (v) {
                setState(() {});
                _suggest(v);
              },
              onSubmitted: (_) => _search(),
            ),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          width: dropWidth,
          child: DropdownButtonFormField<String>(
            initialValue: _conTypeId,
            isExpanded: true,
            style: _fieldTextStyle(context),
            dropdownColor: Colors.white,
            borderRadius: BorderRadius.circular(12.r),
            elevation: 6,
            icon: Icon(Icons.arrow_drop_down, color: AppColors.textSecondary),
            decoration: _filledFieldDec(context, 'Select Concession', filled: _conTypeId != null),
            hint: Text('Select Concession',
                style: TextStyle(
                    color: AppColors.textPrimary.withValues(alpha: 0.6),
                    fontSize: compact ? 11 : 14)),
            items: [
              DropdownMenuItem<String>(
                  value: _kNone,
                  child: Text('None',
                      style: TextStyle(fontSize: compact ? 11 : 14, fontWeight: FontWeight.w600))),
              ..._conTypes.map((t) => DropdownMenuItem(
                    value: t['con_id'].toString(),
                    child: Text(t['condesc']?.toString() ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: compact ? 11 : 14, fontWeight: FontWeight.w600)),
                  )),
            ],
            selectedItemBuilder: (context) => [
              Align(alignment: Alignment.centerLeft, child: Text('None', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 11 : 14, fontWeight: FontWeight.w600, color: AppColors.accent))),
              ..._conTypes.map((t) => Align(alignment: Alignment.centerLeft, child: Text(t['condesc']?.toString() ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 11 : 14, fontWeight: FontWeight.w600, color: AppColors.accent)))),
            ],
            onChanged: (v) => setState(() => _conTypeId = v),
          ),
        ),
        SizedBox(width: 8.w),
        SizedBox(
          height: btnHeight,
          child: ElevatedButton.icon(
            onPressed: _clear,
            icon: const Icon(Icons.refresh, size: 16),
            label: const Text('Clear'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: compact ? 16.w : 22.w),
              textStyle: TextStyle(fontSize: compact ? 11.sp : 13.sp, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 6.r : 8.r)),
            ),
          ),
        ),
      ]),
    );
  }

  void _showSuggestions() {
    _hideSuggestions();
    if (_suggestions.isEmpty) return;
    final overlay = Overlay.of(context, rootOverlay: true);
    _suggestionOverlay = OverlayEntry(
      builder: (_) {
        final compact = MediaQuery.of(context).size.width <= 1366;
        final width = compact ? 260.0 : 340.0;
        final fieldHeight = compact ? 38.0 : 50.0;
        return Positioned(
          width: width,
          child: CompositedTransformFollower(
            link: _searchFieldLink,
            showWhenUnlinked: false,
            offset: Offset(0, fieldHeight),
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(12.r),
              color: Colors.white,
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: 480.h),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.symmetric(vertical: 4.h),
                  itemCount: _suggestions.length,
                  itemBuilder: (_, i) {
                    final s = _suggestions[i];
                    final name = (s['stuname']?.toString() ?? '').toUpperCase();
                    final admno = s['stuadmno']?.toString() ?? '';
                    final cls = s['stuclass']?.toString() ?? '';
                    final selected = i == 0;
                    return InkWell(
                      onTap: () => _pick(s),
                      hoverColor: AppColors.accent.withValues(alpha: 0.06),
                      child: Container(
                        color: selected ? AppColors.tableHeadBg : Colors.transparent,
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                        child: Row(children: [
                          Expanded(
                            child: Text(
                              name,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: compact ? 11 : 14,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textPrimary,
                                letterSpacing: 0.2,
                              ),
                            ),
                          ),
                          SizedBox(width: 8.w),
                          Text(
                            admno,
                            style: TextStyle(
                              fontSize: compact ? 10 : 12,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          if (cls.isNotEmpty) ...[
                            SizedBox(width: 6.w),
                            Text('•',
                                style: TextStyle(
                                    fontSize: compact ? 10 : 12,
                                    color: AppColors.textLight)),
                            SizedBox(width: 6.w),
                            Text(
                              cls,
                              style: TextStyle(
                                fontSize: compact ? 10 : 12,
                                fontWeight: FontWeight.w600,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ]),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_suggestionOverlay!);
  }

  void _hideSuggestions() {
    _suggestionOverlay?.remove();
    _suggestionOverlay = null;
  }

  Widget _studentChip() {
    final s = _student!;
    final initial = (s['stuname']?.toString().trim().isNotEmpty ?? false)
        ? s['stuname'].toString().trim().substring(0, 1).toUpperCase()
        : '?';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 28.w,
          height: 28.w,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(6.r),
          ),
          child: Text(initial, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: Colors.white)),
        ),
        SizedBox(width: 8.w),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${s['stuname']}',
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
            Text('Adm No: ${s['stuadmno']}  •  ${s['stuclass'] ?? ''}',
                style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
          ],
        ),
      ]),
    );
  }

  Widget _grid() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 32.sp, color: AppColors.textLight),
            SizedBox(height: 8.h),
            Text('No unpaid fee demands for this student',
                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          ],
        ),
      );
    }
    TextStyle h() => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3);
    TextStyle c() => TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary);
    return Column(
      children: [
        Container(
          color: AppColors.tableHeadBg,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          child: Row(children: [
            SizedBox(width: 80.w, child: Text('TERM', style: h())),
            Expanded(flex: 3, child: Text('FEE TYPE', style: h())),
            SizedBox(width: 110.w, child: Text('FEE DEF', textAlign: TextAlign.right, style: h())),
            SizedBox(width: 140.w, child: Text('CONCESSION', textAlign: TextAlign.right, style: h())),
            SizedBox(width: 110.w, child: Text('BALANCE', textAlign: TextAlign.right, style: h())),
          ]),
        ),
        Expanded(
          child: FocusTraversalGroup(
            child: ListView.separated(
            itemCount: _rows.length,
            separatorBuilder: (_, __) => Divider(height: 1, color: AppColors.border.withValues(alpha: 0.5)),
            itemBuilder: (_, i) {
              final r = _rows[i];
              return Container(
                color: i.isEven ? Colors.white : AppColors.surface,
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                child: Row(children: [
                  SizedBox(width: 80.w, child: Text(r.term, style: c())),
                  Expanded(
                      flex: 3,
                      child: Text(r.feeType,
                          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary))),
                  SizedBox(
                      width: 110.w,
                      child: Text(r.feeAmount.toStringAsFixed(2), textAlign: TextAlign.right, style: c())),
                  SizedBox(
                    width: 140.w,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8.w),
                      child: TextField(
                        controller: r.conCtrl,
                        textAlign: TextAlign.right,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: r.conCtrl.text.trim().isNotEmpty ? AppColors.accent : AppColors.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6.r),
                              borderSide: BorderSide(color: r.conCtrl.text.trim().isNotEmpty ? AppColors.accent : AppColors.border, width: 1.5)),
                          enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6.r),
                              borderSide: BorderSide(color: r.conCtrl.text.trim().isNotEmpty ? AppColors.accent : AppColors.border, width: 1.5)),
                          focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6.r),
                              borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ),
                  SizedBox(
                      width: 110.w,
                      child: Text(r.balance.toStringAsFixed(2),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary))),
                ]),
              );
            },
          ),
          ),
        ),
      ],
    );
  }

  Widget _footer() {
    final compact = MediaQuery.of(context).size.width <= 1366;
    Widget tot(String label, double v, Color color) => Row(mainAxisSize: MainAxisSize.min, children: [
          Text('$label  ',
              style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          Text(v.toStringAsFixed(2),
              style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w800, color: color)),
        ]);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        tot('Total Fee:', _totalDef, AppColors.textPrimary),
        SizedBox(width: 24.w),
        tot('Concession:', _totalCon, AppColors.accentDark),
        SizedBox(width: 24.w),
        tot('Balance:', _totalBal, AppColors.primary),
        const Spacer(),
        SizedBox(
          height: compact ? 36.0 : 44.0,
          child: ElevatedButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? SizedBox(width: 14.w, height: 14.w, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.save, size: 16),
            label: const Text('Save Concession'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: EdgeInsets.symmetric(horizontal: compact ? 16.w : 22.w),
              textStyle: TextStyle(fontSize: compact ? 11.sp : 13.sp, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(compact ? 6.r : 8.r)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── design helpers (mirrors fee_master_screen) ─────────────────────────────
  InputDecoration _filledFieldDec(BuildContext context, String hint, {bool filled = false}) {
    final compact = MediaQuery.of(context).size.width <= 1366;
    final textSize = compact ? 11.0 : 14.0;
    final hPad = compact ? 8.0 : 14.0;
    final vPad = compact ? 5.0 : 14.0;
    final radius = compact ? 5.0 : 8.0;
    final idle = filled ? AppColors.accent : AppColors.border;
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.6), fontSize: textSize),
      contentPadding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: idle, width: 1.5)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: BorderSide(color: idle, width: 1.5)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(radius), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  TextStyle _fieldTextStyle(BuildContext context) {
    final compact = MediaQuery.of(context).size.width <= 1366;
    return TextStyle(fontWeight: FontWeight.w600, fontSize: compact ? 11 : 14, color: const Color(0xFF333333));
  }
}
