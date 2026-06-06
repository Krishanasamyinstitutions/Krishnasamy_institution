import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_icon.dart';
import '../admin/master_import_screen.dart';
import '../admin/settings_screen.dart' show PaymentSequenceTab, FineRulesTab;

/// Fee Master — clean CRUD (Admission-Master style) for the fee lookups:
/// Fee Group, Fee Type, Concession, Class Fee Demand, Payment Sequence, Fine
/// Rules. Each tab is a left "Add" form + right table. Payment Sequence and
/// Fine Rules were previously in a standalone "Sequence Creation" sidebar
/// entry; they live here now so all fee configuration is in one place.
class FeeMasterScreen extends StatelessWidget {
  const FeeMasterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Padding(
        padding: EdgeInsets.all(16.w),
        child: Container(
          decoration: AppCard.decoration(),
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(18.w, 14.h, 18.w, 6.h),
                child: Row(
                  children: [
                    const AppIcon('receipt-discount', size: 20, color: AppColors.primary),
                    SizedBox(width: 10.w),
                    Text('Fee Master',
                        style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
              ),
              TabBar(
                isScrollable: true,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.textSecondary,
                indicatorColor: AppColors.accent,
                labelStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700),
                tabs: const [
                  Tab(text: 'Fee Group'),
                  Tab(text: 'Fee Type'),
                  Tab(text: 'Semester'),
                  Tab(text: 'Class Fee Demand'),
                  Tab(text: 'Payment Sequence'),
                  Tab(text: 'Fine Rules'),
                ],
              ),
              Divider(height: 1.h, color: AppColors.border),
              const Expanded(
                child: TabBarView(
                  children: [
                    _FeeGroupPanel(),
                    _FeeTypePanel(),
                    _SemesterPanel(),
                    _ClassFeeDemandPanel(),
                    PaymentSequenceTab(),
                    FineRulesTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── shared bits ───────────────────────────────────────────────────────────
InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
    );

void _snack(BuildContext ctx, String msg, Color color) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
}

Future<Map<String, dynamic>?> _currentYear(int insId) async {
  final years = await SupabaseService.getYears(insId);
  return years.isNotEmpty ? years.first : null;
}

/// Next id for a per-schema master = max(idCol) + 1. These tables have
/// sequence-backed triggers, but explicit-id imports leave the sequence
/// behind, so supplying an explicit id avoids primary-key collisions.
Future<int> _nextId(String table, String idCol) async {
  final res = await SupabaseService.fromSchema(table)
      .select(idCol).order(idCol, ascending: false).limit(1).maybeSingle();
  final cur = res?[idCol];
  final n = cur is int ? cur : int.tryParse(cur?.toString() ?? '0') ?? 0;
  return n + 1;
}

Widget _tableShell({required List<Widget> headerCells, required Widget body}) {
  return Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12.r),
      border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
    ),
    child: Column(
      children: [
        Container(
          color: AppColors.tableHeadBg,
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
          child: Row(children: headerCells),
        ),
        Expanded(child: body),
      ],
    ),
  );
}

TextStyle _h() => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
TextStyle _c() => TextStyle(fontSize: 12.sp, color: AppColors.textSecondary);

Future<bool> _confirmDelete(BuildContext ctx, String what) async {
  final ok = await showDialog<bool>(
    context: ctx,
    builder: (c) => AlertDialog(
      title: Text('Delete $what'),
      content: Text('Remove this $what?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Delete', style: TextStyle(color: AppColors.error))),
      ],
    ),
  );
  return ok == true;
}

/// Top-right "Import CSV/Excel" button that opens the bulk importer
/// ([MasterImportScreen]) full-screen at [tabIndex], then runs [onReturn]
/// (the panel's _load) so imported rows appear on return. Tab indices match
/// MasterImportScreen: Fee Group = 4, Fee Type = 5, Class Fee Demand = 7.
Widget _importBar(BuildContext context,
    {required String title, required int tabIndex, required bool saving, required Future<void> Function() onReturn}) {
  return Align(
    alignment: Alignment.centerRight,
    child: ElevatedButton.icon(
      onPressed: saving
          ? null
          : () async {
              await Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (_) => Scaffold(
                    backgroundColor: AppColors.surface,
                    appBar: AppBar(
                      backgroundColor: Colors.white,
                      foregroundColor: AppColors.textPrimary,
                      elevation: 0,
                      shape: const Border(bottom: BorderSide(color: AppColors.border)),
                      title: Row(children: [
                        const AppIcon('document-upload', size: 20, color: AppColors.primary),
                        SizedBox(width: 10.w),
                        Text('Import $title',
                            style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      ]),
                    ),
                    body: Padding(
                      padding: EdgeInsets.all(16.w),
                      child: MasterImportScreen(initialTabIndex: tabIndex, showInternalTabs: false),
                    ),
                  ),
                ),
              );
              await onReturn();
            },
      icon: const AppIcon('document-upload', size: 16, color: Colors.white),
      label: const Text('Import CSV/Excel'),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
        textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

// ══════════════════════════════════════════════════════════════════════════
// FEE GROUP
// ══════════════════════════════════════════════════════════════════════════
class _FeeGroupPanel extends StatefulWidget {
  const _FeeGroupPanel();
  @override
  State<_FeeGroupPanel> createState() => _FeeGroupPanelState();
}

class _FeeGroupPanelState extends State<_FeeGroupPanel> with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();
  List<Map<String, dynamic>> _rows = [];
  int? _editId; // non-null while editing an existing row
  bool _loading = true, _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  int get _insId => context.read<AuthProvider>().insId ?? 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.fromSchema('feegroup')
          .select('*').eq('ins_id', _insId).eq('activestatus', 1).order('fg_id', ascending: true);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _edit(Map<String, dynamic> r) {
    setState(() {
      _editId = r['fg_id'] is int ? r['fg_id'] as int : int.tryParse(r['fg_id'].toString());
      _name.text = r['fgdesc']?.toString() ?? '';
    });
  }

  void _cancelEdit() {
    setState(() {
      _editId = null;
      _name.clear();
    });
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack(context, 'Enter a group name.', AppColors.warning);
    if (_rows.any((r) => (r['fgdesc']?.toString().trim().toLowerCase() ?? '') == name.toLowerCase() &&
        (r['fg_id']?.toString() ?? '') != (_editId?.toString() ?? ''))) {
      return _snack(context, '"$name" already exists.', AppColors.warning);
    }
    setState(() => _saving = true);
    try {
      if (_editId != null) {
        await SupabaseService.fromSchema('feegroup').update({'fgdesc': name}).eq('fg_id', _editId!);
        if (mounted) _snack(context, 'Fee group updated.', AppColors.success);
      } else {
        final yr = await _currentYear(_insId);
        await SupabaseService.fromSchema('feegroup').insert({
          'fg_id': await _nextId('feegroup', 'fg_id'),
          'fgdesc': name,
          'ins_id': _insId,
          'yr_id': yr != null ? int.tryParse(yr['yr_id'].toString()) ?? 0 : 0,
          'yrlabel': yr?['yrlabel']?.toString() ?? '',
          'activestatus': 1,
        });
        if (mounted) _snack(context, 'Fee group added.', AppColors.success);
      }
      _name.clear();
      _editId = null;
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Save failed. ${friendlyError(e)}', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(int id) async {
    if (!await _confirmDelete(context, 'fee group')) return;
    try {
      await SupabaseService.fromSchema('feegroup').update({'activestatus': 0}).eq('fg_id', id);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Delete failed. ${friendlyError(e)}', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _importBar(context, title: 'Fee Group', tabIndex: 4, saving: _saving, onReturn: _load),
          SizedBox(height: 12.h),
          Expanded(
            child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320.w,
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_editId != null ? 'Edit Fee Group' : 'Add Fee Group', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 12.h),
                  TextField(controller: _name, style: TextStyle(fontSize: 13.sp), decoration: _dec('Group Name *'), onSubmitted: (_) => _add()),
                  SizedBox(height: 14.h),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _add,
                        icon: Icon(_editId != null ? Icons.save : Icons.add, size: 16),
                        label: Text(_editId != null ? 'Update' : 'Add'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                      ),
                    ),
                    if (_editId != null) ...[
                      SizedBox(width: 8.w),
                      OutlinedButton(onPressed: _saving ? null : _cancelEdit, child: const Text('Cancel')),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: _tableShell(
              headerCells: [
                SizedBox(width: 50.w, child: Text('S.No', style: _h())),
                Expanded(child: Text('GROUP NAME', style: _h())),
                SizedBox(width: 110.w, child: Text('YEAR', style: _h())),
                SizedBox(width: 90.w, child: Text('ACTION', textAlign: TextAlign.center, style: _h())),
              ],
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(child: Text('No fee groups', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.5)),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final id = r['fg_id'] is int ? r['fg_id'] as int : int.tryParse(r['fg_id'].toString()) ?? 0;
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                              child: Row(children: [
                                SizedBox(width: 50.w, child: Text('${i + 1}', style: _c())),
                                Expanded(child: Text(r['fgdesc']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                                SizedBox(width: 110.w, child: Text(r['yrlabel']?.toString() ?? '', style: _c())),
                                SizedBox(width: 90.w, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  InkWell(onTap: () => _edit(r), child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('edit-2', size: 16, color: AppColors.primary))),
                                  SizedBox(width: 8.w),
                                  InkWell(onTap: () => _delete(id), child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('trash', size: 16, color: AppColors.error))),
                                ])),
                              ]),
                            );
                          },
                        ),
            ),
          ),
        ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// FEE TYPE
// ══════════════════════════════════════════════════════════════════════════
class _FeeTypePanel extends StatefulWidget {
  const _FeeTypePanel();
  @override
  State<_FeeTypePanel> createState() => _FeeTypePanelState();
}

class _FeeTypePanelState extends State<_FeeTypePanel> with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();
  final _short = TextEditingController();
  String? _fgId;
  String _fine = 'No';
  List<Map<String, dynamic>> _feeGroups = [];
  List<Map<String, dynamic>> _rows = [];
  Map<int, String> _fgName = {};
  int? _editId; // non-null while editing an existing row
  bool _loading = true, _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  void _edit(Map<String, dynamic> r) {
    setState(() {
      _editId = r['fee_id'] is int ? r['fee_id'] as int : int.tryParse(r['fee_id'].toString());
      _name.text = r['feedesc']?.toString() ?? '';
      _short.text = r['feeshort']?.toString() ?? '';
      _fgId = r['fg_id']?.toString();
      _fine = '${r['feefineapplicable'] ?? 0}' == '1' ? 'Yes' : 'No';
    });
  }

  void _cancelEdit() {
    setState(() {
      _editId = null;
      _name.clear();
      _short.clear();
      _fine = 'No';
    });
  }

  int get _insId => context.read<AuthProvider>().insId ?? 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final groups = await SupabaseService.getFeeGroups(_insId);
      final fgList = List<Map<String, dynamic>>.from(groups);
      final fgIds = fgList.map((g) => g['fg_id'] as int).toList();
      final types = fgIds.isEmpty
          ? <dynamic>[]
          : await SupabaseService.fromSchema('feetype').select('*').inFilter('fg_id', fgIds).eq('activestatus', 1).order('fee_id', ascending: true);
      if (!mounted) return;
      setState(() {
        _feeGroups = fgList;
        _fgName = {for (final g in fgList) g['fg_id'] as int: g['fgdesc']?.toString() ?? ''};
        _rows = List<Map<String, dynamic>>.from(types);
        _fgId ??= fgList.isNotEmpty ? fgList.first['fg_id'].toString() : null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack(context, 'Enter a fee name.', AppColors.warning);
    if (_fgId == null) return _snack(context, 'Add a Fee Group first.', AppColors.warning);
    setState(() => _saving = true);
    try {
      if (_editId != null) {
        await SupabaseService.fromSchema('feetype').update({
          'feedesc': name,
          'feeshort': _short.text.trim(),
          'fg_id': int.tryParse(_fgId!),
          'feefineapplicable': _fine == 'Yes' ? 1 : 0,
        }).eq('fee_id', _editId!);
        if (mounted) _snack(context, 'Fee type updated.', AppColors.success);
      } else {
        final yr = await _currentYear(_insId);
        await SupabaseService.fromSchema('feetype').insert({
          'fee_id': await _nextId('feetype', 'fee_id'),
          'feedesc': name,
          'feeshort': _short.text.trim(),
          'fg_id': int.tryParse(_fgId!),
          'feefineapplicable': _fine == 'Yes' ? 1 : 0,
          'yr_id': yr != null ? int.tryParse(yr['yr_id'].toString()) ?? 0 : 0,
          'yrlabel': yr?['yrlabel']?.toString() ?? '',
          'ins_id': _insId,
          'activestatus': 1,
        });
        if (mounted) _snack(context, 'Fee type added.', AppColors.success);
      }
      _name.clear();
      _short.clear();
      _editId = null;
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Save failed. ${friendlyError(e)}', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(int id) async {
    if (!await _confirmDelete(context, 'fee type')) return;
    try {
      await SupabaseService.fromSchema('feetype').update({'activestatus': 0}).eq('fee_id', id);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Delete failed. ${friendlyError(e)}', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _importBar(context, title: 'Fee Type', tabIndex: 5, saving: _saving, onReturn: _load),
          SizedBox(height: 12.h),
          Expanded(
            child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320.w,
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_editId != null ? 'Edit Fee Type' : 'Add Fee Type', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 12.h),
                  TextField(controller: _name, style: TextStyle(fontSize: 13.sp), decoration: _dec('Fee Name *')),
                  SizedBox(height: 10.h),
                  TextField(controller: _short, style: TextStyle(fontSize: 13.sp), decoration: _dec('Short Name')),
                  SizedBox(height: 10.h),
                  DropdownButtonFormField<String>(
                    initialValue: _fgId,
                    isExpanded: true,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    decoration: _dec('Fee Group *'),
                    items: _feeGroups.map((g) => DropdownMenuItem(value: g['fg_id'].toString(), child: Text(g['fgdesc']?.toString() ?? '', overflow: TextOverflow.ellipsis))).toList(),
                    onChanged: (v) => setState(() => _fgId = v),
                  ),
                  SizedBox(height: 10.h),
                  DropdownButtonFormField<String>(
                    initialValue: _fine,
                    isExpanded: true,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    decoration: _dec('Fine Applicable'),
                    items: const [DropdownMenuItem(value: 'No', child: Text('No')), DropdownMenuItem(value: 'Yes', child: Text('Yes'))],
                    onChanged: (v) => setState(() => _fine = v ?? 'No'),
                  ),
                  SizedBox(height: 14.h),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _add,
                        icon: Icon(_editId != null ? Icons.save : Icons.add, size: 16),
                        label: Text(_editId != null ? 'Update' : 'Add'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                      ),
                    ),
                    if (_editId != null) ...[
                      SizedBox(width: 8.w),
                      OutlinedButton(onPressed: _saving ? null : _cancelEdit, child: const Text('Cancel')),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: _tableShell(
              headerCells: [
                SizedBox(width: 50.w, child: Text('S.No', style: _h())),
                Expanded(flex: 3, child: Text('FEE NAME', style: _h())),
                SizedBox(width: 80.w, child: Text('SHORT', style: _h())),
                Expanded(flex: 2, child: Text('FEE GROUP', style: _h())),
                SizedBox(width: 60.w, child: Text('FINE', style: _h())),
                SizedBox(width: 90.w, child: Text('ACTION', textAlign: TextAlign.center, style: _h())),
              ],
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(child: Text('No fee types', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.5)),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final id = r['fee_id'] is int ? r['fee_id'] as int : int.tryParse(r['fee_id'].toString()) ?? 0;
                            final fine = '${r['feefineapplicable'] ?? 0}' == '1' ? 'Yes' : 'No';
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                              child: Row(children: [
                                SizedBox(width: 50.w, child: Text('${i + 1}', style: _c())),
                                Expanded(flex: 3, child: Text(r['feedesc']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                                SizedBox(width: 80.w, child: Text(r['feeshort']?.toString() ?? '', style: _c())),
                                Expanded(flex: 2, child: Text(_fgName[r['fg_id']] ?? '', style: _c())),
                                SizedBox(width: 60.w, child: Text(fine, style: _c())),
                                SizedBox(width: 90.w, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  InkWell(onTap: () => _edit(r), child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('edit-2', size: 16, color: AppColors.primary))),
                                  SizedBox(width: 8.w),
                                  InkWell(onTap: () => _delete(id), child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('trash', size: 16, color: AppColors.error))),
                                ])),
                              ]),
                            );
                          },
                        ),
            ),
          ),
        ],
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// SEMESTER
// ══════════════════════════════════════════════════════════════════════════
class _SemesterPanel extends StatefulWidget {
  const _SemesterPanel();
  @override
  State<_SemesterPanel> createState() => _SemesterPanelState();
}

class _SemesterPanelState extends State<_SemesterPanel> with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();
  final _short = TextEditingController();
  String _type = 'S'; // S = Semester, M = Monthly, Y = Yearly
  List<Map<String, dynamic>> _rows = [];
  int? _editId; // non-null while editing an existing row
  bool _loading = true, _saving = false;

  // Type flag ↔ label, shared by the Add dropdown and the table.
  static const _typeLabels = {'S': 'Semester', 'M': 'Monthly', 'Y': 'Yearly'};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _short.dispose();
    super.dispose();
  }

  int get _insId => context.read<AuthProvider>().insId ?? 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final res = await SupabaseService.fromSchema('semester')
          .select('*').eq('ins_id', _insId).eq('activestatus', 1).order('sem_id', ascending: true);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from(res as List);
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _edit(Map<String, dynamic> r) {
    setState(() {
      _editId = r['sem_id'] is int ? r['sem_id'] as int : int.tryParse(r['sem_id'].toString());
      _name.text = r['semname']?.toString() ?? '';
      _short.text = r['semshort']?.toString() ?? '';
      final t = r['semtype']?.toString().trim() ?? '';
      _type = _typeLabels.containsKey(t) ? t : 'S';
    });
  }

  void _cancelEdit() {
    setState(() {
      _editId = null;
      _name.clear();
      _short.clear();
      _type = 'S';
    });
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack(context, 'Enter a semester name.', AppColors.warning);
    if (_rows.any((r) => (r['semname']?.toString().trim().toLowerCase() ?? '') == name.toLowerCase() &&
        (r['sem_id']?.toString() ?? '') != (_editId?.toString() ?? ''))) {
      return _snack(context, '"$name" already exists.', AppColors.warning);
    }
    setState(() => _saving = true);
    try {
      final short = _short.text.trim();
      if (_editId != null) {
        await SupabaseService.fromSchema('semester').update({
          'semname': name,
          'semshort': short.isEmpty ? null : short,
          'semtype': _type,
        }).eq('sem_id', _editId!);
        if (mounted) _snack(context, 'Semester updated.', AppColors.success);
      } else {
        await SupabaseService.fromSchema('semester').insert({
          'sem_id': await _nextId('semester', 'sem_id'),
          'semname': name,
          'semshort': short.isEmpty ? null : short,
          'semtype': _type,
          'ins_id': _insId,
          'activestatus': 1,
        });
        if (mounted) _snack(context, 'Semester added.', AppColors.success);
      }
      _name.clear();
      _short.clear();
      _type = 'S';
      _editId = null;
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Save failed. ${friendlyError(e)}', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(int id) async {
    if (!await _confirmDelete(context, 'semester')) return;
    try {
      await SupabaseService.fromSchema('semester').update({'activestatus': 0}).eq('sem_id', id);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Delete failed. ${friendlyError(e)}', AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320.w,
            child: Container(
              padding: EdgeInsets.all(16.w),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border.withValues(alpha: 0.6)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_editId != null ? 'Edit Semester' : 'Add Semester', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                  SizedBox(height: 12.h),
                  TextField(controller: _name, style: TextStyle(fontSize: 13.sp), decoration: _dec('Semester Name *'), onSubmitted: (_) => _add()),
                  SizedBox(height: 10.h),
                  TextField(controller: _short, style: TextStyle(fontSize: 13.sp), decoration: _dec('Short Name')),
                  SizedBox(height: 10.h),
                  DropdownButtonFormField<String>(
                    initialValue: _type,
                    isExpanded: true,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    decoration: _dec('Type *'),
                    items: _typeLabels.entries.map((e) => DropdownMenuItem(value: e.key, child: Text(e.value))).toList(),
                    onChanged: (v) => setState(() => _type = v ?? 'S'),
                  ),
                  SizedBox(height: 14.h),
                  Row(children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _saving ? null : _add,
                        icon: Icon(_editId != null ? Icons.save : Icons.add, size: 16),
                        label: Text(_editId != null ? 'Update' : 'Add'),
                        style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
                      ),
                    ),
                    if (_editId != null) ...[
                      SizedBox(width: 8.w),
                      OutlinedButton(onPressed: _saving ? null : _cancelEdit, child: const Text('Cancel')),
                    ],
                  ]),
                ],
              ),
            ),
          ),
          SizedBox(width: 16.w),
          Expanded(
            child: _tableShell(
              headerCells: [
                SizedBox(width: 50.w, child: Text('S.No', style: _h())),
                Expanded(flex: 2, child: Text('SEMESTER NAME', style: _h())),
                SizedBox(width: 90.w, child: Text('SHORT', style: _h())),
                SizedBox(width: 100.w, child: Text('TYPE', style: _h())),
                SizedBox(width: 90.w, child: Text('ACTION', textAlign: TextAlign.center, style: _h())),
              ],
              body: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _rows.isEmpty
                      ? Center(child: Text('No semesters', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
                      : ListView.separated(
                          itemCount: _rows.length,
                          separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.5)),
                          itemBuilder: (_, i) {
                            final r = _rows[i];
                            final id = r['sem_id'] is int ? r['sem_id'] as int : int.tryParse(r['sem_id'].toString()) ?? 0;
                            final type = _typeLabels[r['semtype']?.toString().trim()] ?? 'Semester';
                            return Padding(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                              child: Row(children: [
                                SizedBox(width: 50.w, child: Text('${i + 1}', style: _c())),
                                Expanded(flex: 2, child: Text(r['semname']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                                SizedBox(width: 90.w, child: Text(r['semshort']?.toString() ?? '', style: _c())),
                                SizedBox(width: 100.w, child: Text(type, style: _c())),
                                SizedBox(width: 90.w, child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  InkWell(onTap: () => _edit(r), child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('edit-2', size: 16, color: AppColors.primary))),
                                  SizedBox(width: 8.w),
                                  InkWell(onTap: () => _delete(id), child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('trash', size: 16, color: AppColors.error))),
                                ])),
                              ]),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

// ══════════════════════════════════════════════════════════════════════════
// CLASS FEE DEMAND
// ══════════════════════════════════════════════════════════════════════════

class _FeeLine {
  String? feeType;
  final amount = TextEditingController();
  bool applyAll = false;
  bool fromExisting = false; // true once loaded from a saved classfeedemand row
  // An apply-to-all fee is locked (read-only) once it has been created/saved —
  // its demand is already generated for every student.
  bool get locked => fromExisting && applyAll;
  void dispose() => amount.dispose();
}

class _ClassFeeDemandPanel extends StatefulWidget {
  const _ClassFeeDemandPanel();
  @override
  State<_ClassFeeDemandPanel> createState() => _ClassFeeDemandPanelState();
}

class _ClassFeeDemandPanelState extends State<_ClassFeeDemandPanel> with AutomaticKeepAliveClientMixin {
  String? _cls;
  String? _sem;
  String? _admId; // null => all admission types
  DateTime? _due;
  bool _editMode = false; // false = New (blank grid), true = Edit (prefilled)
  final List<_FeeLine> _lines = [];

  List<String> _classNames = [];
  List<String> _semesters = [];
  List<String> _feeTypeNames = [];
  List<Map<String, dynamic>> _admTypes = [];
  Map<String, String> _admName = {};
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true, _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    for (var i = 0; i < 5; i++) {
      _lines.add(_FeeLine());
    }
    _load();
  }

  @override
  void dispose() {
    for (final l in _lines) {
      l.dispose();
    }
    super.dispose();
  }

  int get _insId => context.read<AuthProvider>().insId ?? 1;

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        SupabaseService.fromSchema('classfeedemand').select('*'),
        SupabaseService.fromSchema('class').select('claname').eq('ins_id', _insId).eq('activestatus', 1),
        SupabaseService.fromSchema('feetype').select('feedesc').eq('activestatus', 1),
        SupabaseService.fromSchema('admissiontype').select('adm_id, admname').eq('ins_id', _insId).eq('activestatus', 1),
        SupabaseService.fromSchema('semester').select('semname').eq('ins_id', _insId).eq('activestatus', 1),
      ]);
      if (!mounted) return;
      setState(() {
        _rows = List<Map<String, dynamic>>.from((results[0] as List).cast<Map<String, dynamic>>());
        _classNames = (results[1] as List).map((e) => e['claname']?.toString().trim() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
        _feeTypeNames = (results[2] as List).map((e) => e['feedesc']?.toString().trim() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
        _admTypes = List<Map<String, dynamic>>.from((results[3] as List).cast<Map<String, dynamic>>());
        _semesters = (results[4] as List).map((e) => e['semname']?.toString().trim() ?? '').where((s) => s.isNotEmpty).toSet().toList()..sort();
        _admName = {for (final a in _admTypes) a['adm_id'].toString(): a['admname']?.toString() ?? ''};
        _cls ??= _classNames.isNotEmpty ? _classNames.first : null;
        if (_cls != null) _reloadGrid();
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  double get _total => _lines.fold(0.0, (s, l) => s + (double.tryParse(l.amount.text.trim()) ?? 0));


  String _amtStr(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toString();

  /// Rebuild the grid for the current Class / Semester / Admn Type selection:
  /// one row per active fee type, with AMOUNT (and ALL) pre-filled from any
  /// existing classfeedemand record that matches the selection. Fee types
  /// without an existing record show a blank amount. Called inside an existing
  /// setState whenever Class, Semester or Admn Type changes.
  void _loadLinesForSelection() {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    // Existing records matching the current selection (class + sem + adm type).
    final existing = <String, Map<String, dynamic>>{};
    for (final r in _rows) {
      if ((r['cfclass']?.toString() ?? '') != _cls) continue;
      if (_sem != null && (r['cfterm']?.toString() ?? '') != _sem) continue;
      final admMatch = _admId == null
          ? r['admissiontype'] == null
          : r['admissiontype']?.toString() == _admId;
      if (!admMatch) continue;
      existing[r['cffeetype']?.toString() ?? ''] = r;
    }
    for (final ft in _feeTypeNames) {
      final line = _FeeLine()..feeType = ft;
      final r = existing[ft];
      if (r != null) {
        final amt = r['cfamount'];
        final n = amt is num ? amt : double.tryParse(amt?.toString() ?? '');
        if (n != null) line.amount.text = _amtStr(n);
        line.applyAll = r['collectible'] == true; // restore the ALL tick
        line.fromExisting = true; // mark as a saved row (locks if apply-to-all)
      }
      _lines.add(line);
    }
    if (_lines.isEmpty) {
      for (var i = 0; i < 5; i++) {
        _lines.add(_FeeLine());
      }
    }
  }

  /// Blank grid for NEW mode: one row per fee type, no amounts / ticks, nothing
  /// marked as existing (so nothing is locked).
  void _blankLines() {
    for (final l in _lines) {
      l.dispose();
    }
    _lines.clear();
    for (final ft in _feeTypeNames) {
      _lines.add(_FeeLine()..feeType = ft);
    }
    if (_lines.isEmpty) {
      for (var i = 0; i < 5; i++) {
        _lines.add(_FeeLine());
      }
    }
  }

  /// Rebuild the grid for the current selection per the active mode: New shows
  /// blank rows, Edit prefills from saved classfeedemand.
  void _reloadGrid() => _editMode ? _loadLinesForSelection() : _blankLines();

  Future<void> _save() async {
    if (_cls == null || _sem == null || _due == null) {
      return _snack(context, 'Select Class, Semester and Pay-On-or-Before date.', AppColors.warning);
    }
    final lines = _lines.where((l) => l.feeType != null && l.amount.text.trim().isNotEmpty).toList();
    if (lines.isEmpty) return _snack(context, 'Add at least one fee line.', AppColors.warning);
    final auth = context.read<AuthProvider>(); // capture before async gaps
    setState(() => _saving = true);
    int done = 0;
    int demCount = 0;
    final fails = <String>[];

    // Idempotent save: replace the template rows for THIS Class + Semester +
    // Admn Type so unticking/editing persists instead of leaving stale rows
    // (an insert-only save left the old collectible=true row behind, so the
    // ALL tick reappeared on reload).
    try {
      var del = SupabaseService.fromSchema('classfeedemand').delete().eq('cfclass', _cls!).eq('cfterm', _sem!);
      del = _admId != null ? del.eq('admissiontype', int.parse(_admId!)) : del.isFilter('admissiontype', null);
      await del;
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      return _snack(context, 'Save failed clearing old rows. ${friendlyError(e)}', AppColors.error);
    }

    for (final l in lines) {
      try {
        await SupabaseService.fromSchema('classfeedemand').insert({
          'cf_id': await _nextId('classfeedemand', 'cf_id'),
          'cfclass': _cls,
          'cfterm': _sem,
          'cffeetype': l.feeType,
          'cfamount': double.tryParse(l.amount.text.trim()),
          'cfdduedate': _due!.toIso8601String().split('T').first,
          'admissiontype': _admId != null ? int.tryParse(_admId!) : null,
          'collectible': l.applyAll,
        });
        done++;
      } catch (e) {
        fails.add('${l.feeType}: ${friendlyError(e)}');
      }
    }
    // New mode: stage a tempfeedemand per student for EVERY fee line (→ Fee
    // Demand Approval → feedemand). Edit mode: push the edited amounts straight
    // into the students' existing feedemand rows instead of staging new ones.
    if (fails.isEmpty) {
      try {
        demCount = _editMode
            ? await _propagateToFeedemand(lines, auth)
            : await _generateTempDemands(lines, auth);
      } catch (e) {
        fails.add('Demand ${_editMode ? 'update' : 'generation'}: ${friendlyError(e)}');
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (fails.isEmpty) {
      final ticked = lines.where((l) => l.applyAll).length;
      _snack(
        context,
        _editMode
            ? 'Updated $done fee line(s)${demCount > 0 ? ' • $demCount student demand(s) updated' : ''}.'
            : 'Saved $done fee line(s)${demCount > 0 ? ' • $demCount demand(s) sent for approval ($ticked collectible)' : ''}.',
        AppColors.success,
      );
      setState(() {
        for (final l in _lines) {
          l.dispose();
        }
        _lines
          ..clear()
          ..addAll(List.generate(5, (_) => _FeeLine()));
      });
    }
    await _load();
    if (fails.isNotEmpty && mounted) _snack(context, 'Saved $done, ${fails.length} failed. ${fails.first}', AppColors.error);
  }

  /// Stage a tempfeedemand row for every active student in the class × each fee
  /// line (→ Fee Demand Approval, isapproved=false). collectible = line.applyAll
  /// and is carried into feedemand by the approval trigger. temp_id/demno are
  /// filled by the schema's set_temp_id trigger.
  Future<int> _generateTempDemands(List<_FeeLine> lines, AuthProvider auth, {String? forClass}) async {
    final cls = forClass ?? _cls!;
    final insId = auth.insId ?? 1;
    final years = await SupabaseService.getYears(insId);
    final yr = years.isNotEmpty ? years.first : null;
    final yrId = yr != null ? int.tryParse(yr['yr_id'].toString()) ?? 0 : 0;
    final yrLabel = yr?['yrlabel']?.toString() ?? '';
    var studentsQuery = SupabaseService.fromSchema('students')
        .select('stu_id, stuadmno, courname')
        .eq('ins_id', insId)
        .eq('stuclass', cls)
        .eq('activestatus', 1);
    // Restrict to the chosen admission type (null = All).
    if (_admId != null) {
      final admName = _admTypes
          .firstWhere((a) => a['adm_id'].toString() == _admId, orElse: () => const {})['admname']
          ?.toString();
      if (admName != null && admName.isNotEmpty) {
        studentsQuery = studentsQuery.eq('admname', admName);
      }
    }
    final studentsRes = await studentsQuery;
    final students = List<Map<String, dynamic>>.from(studentsRes as List);
    if (students.isEmpty) return 0;
    final rows = <Map<String, dynamic>>[];
    final due = _due!.toIso8601String().split('T').first;
    for (final s in students) {
      for (final l in lines) {
        final amt = double.tryParse(l.amount.text.trim()) ?? 0;
        rows.add({
          'ins_id': insId,
          'inscode': auth.inscode ?? '',
          'yr_id': yrId,
          'stu_id': s['stu_id'],
          'stuadmno': s['stuadmno'],
          'stuclass': cls,
          'courname': s['courname'],
          'demfeeyear': yrLabel,
          'demfeeterm': _sem,
          'demfeetype': l.feeType,
          'feeamount': amt,
          'balancedue': amt,
          'duedate': due,
          'createdby': auth.userName,
          'isapproved': false,
          'activestatus': 1,
          'collectible': l.applyAll,
        });
      }
    }
    if (rows.isEmpty) return 0;
    await SupabaseService.fromSchema('tempfeedemand').insert(rows);
    return rows.length;
  }

  /// Edit mode: push the edited Class Fee Demand amounts into the students'
  /// existing UNPAID feedemand rows (same class + term + fee type, restricted to
  /// the chosen admission type). Recomputes balancedue = amount - concession -
  /// paid. Returns the number of student demand rows updated.
  Future<int> _propagateToFeedemand(List<_FeeLine> lines, AuthProvider auth) async {
    final insId = auth.insId ?? 1;
    // Resolve the admno set for the chosen admission type (null = all students).
    Set<String>? allowed;
    if (_admId != null) {
      final admName = _admTypes
          .firstWhere((a) => a['adm_id'].toString() == _admId, orElse: () => const {})['admname']
          ?.toString();
      final studs = await SupabaseService.fromSchema('students')
          .select('stuadmno')
          .eq('ins_id', insId)
          .eq('stuclass', _cls!)
          .eq('activestatus', 1)
          .eq('admname', admName ?? '');
      allowed = {for (final s in (studs as List)) (s as Map)['stuadmno'].toString()};
    }

    var updated = 0;
    for (final l in lines) {
      final amt = double.tryParse(l.amount.text.trim()) ?? 0;
      final res = await SupabaseService.fromSchema('feedemand')
          .select('dem_id, stuadmno, conamount, paidamount')
          .eq('ins_id', insId)
          .eq('stuclass', _cls!)
          .eq('demfeeterm', _sem!)
          .eq('demfeetype', l.feeType!)
          .eq('paidstatus', 'U')
          .eq('activestatus', 1);
      for (final r in (res as List)) {
        final m = r as Map;
        if (allowed != null && !allowed.contains(m['stuadmno'].toString())) continue;
        final con = (m['conamount'] as num?)?.toDouble() ?? 0;
        final paid = (m['paidamount'] as num?)?.toDouble() ?? 0;
        final bal = (amt - con - paid) > 0 ? (amt - con - paid) : 0;
        await SupabaseService.fromSchema('feedemand').update({
          'feeamount': amt,
          'balancedue': bal,
          'reconbalancedue': bal,
          'collectible': l.applyAll,
        }).eq('dem_id', m['dem_id']);
        updated++;
      }
    }
    return updated;
  }

  /// Copy the current grid's fee lines (amounts + ALL ticks) to one or more
  /// other classes for the same Semester + Admn Type. Replaces each target's
  /// existing template rows (idempotent) and stages tempfeedemand for that
  /// class's students.
  Future<void> _copyFee() async {
    final lines = _lines.where((l) => l.feeType != null && l.amount.text.trim().isNotEmpty).toList();
    if (lines.isEmpty) return _snack(context, 'Enter fee amounts to copy.', AppColors.warning);
    if (_sem == null || _due == null) {
      return _snack(context, 'Select Semester and Pay-On-or-Before before copying.', AppColors.warning);
    }
    final targets = await _pickTargetClasses();
    if (targets == null || targets.isEmpty) return;

    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    final due = _due!.toIso8601String().split('T').first;
    final admType = _admId != null ? int.tryParse(_admId!) : null;
    var classesDone = 0, demTotal = 0;
    final fails = <String>[];
    for (final cls in targets) {
      try {
        // Idempotent: clear this target's template rows for the selection.
        var del = SupabaseService.fromSchema('classfeedemand').delete().eq('cfclass', cls).eq('cfterm', _sem!);
        del = admType != null ? del.eq('admissiontype', admType) : del.isFilter('admissiontype', null);
        await del;
        for (final l in lines) {
          await SupabaseService.fromSchema('classfeedemand').insert({
            'cf_id': await _nextId('classfeedemand', 'cf_id'),
            'cfclass': cls,
            'cfterm': _sem,
            'cffeetype': l.feeType,
            'cfamount': double.tryParse(l.amount.text.trim()),
            'cfdduedate': due,
            'admissiontype': admType,
            'collectible': l.applyAll,
          });
        }
        demTotal += await _generateTempDemands(lines, auth, forClass: cls);
        classesDone++;
      } catch (e) {
        fails.add('$cls: ${friendlyError(e)}');
      }
    }
    if (!mounted) return;
    setState(() => _saving = false);
    _snack(
      context,
      fails.isEmpty
          ? 'Copied fees to $classesDone class(es) • $demTotal demand(s) staged.'
          : 'Copied to $classesDone, ${fails.length} failed. ${fails.first}',
      fails.isEmpty ? AppColors.success : AppColors.error,
    );
    await _load();
  }

  /// Multi-select dialog of target classes (excludes the source class).
  Future<List<String>?> _pickTargetClasses() async {
    final picked = <String>{};
    return showDialog<List<String>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final options = _classNames.where((c) => c != _cls).toList();
          return AlertDialog(
            title: Text('Copy fees to classes', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
            content: SizedBox(
              width: 360.w,
              height: 360.h,
              child: options.isEmpty
                  ? Center(child: Text('No other classes', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
                  : ListView(
                      children: [
                        Padding(
                          padding: EdgeInsets.only(bottom: 4.h),
                          child: Text('From ${_cls ?? ''} • ${_sem ?? ''} • ${_admId == null ? 'All' : (_admName[_admId] ?? '')}',
                              style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                        ),
                        for (final c in options)
                          CheckboxListTile(
                            dense: true,
                            value: picked.contains(c),
                            title: Text(c, style: TextStyle(fontSize: 13.sp)),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (v) => setLocal(() => v == true ? picked.add(c) : picked.remove(c)),
                          ),
                      ],
                    ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              ElevatedButton(
                onPressed: picked.isEmpty ? null : () => Navigator.pop(ctx, picked.toList()),
                style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white),
                child: Text('Copy to ${picked.length}'),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _delete(int id) async {
    if (!await _confirmDelete(context, 'fee line')) return;
    try {
      await SupabaseService.fromSchema('classfeedemand').delete().eq('cf_id', id);
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Delete failed. ${friendlyError(e)}', AppColors.error);
    }
  }

  String _fmt(DateTime d) => '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _importBar(context, title: 'Class Fee Demand', tabIndex: 7, saving: _saving, onReturn: _load),
          SizedBox(height: 12.h),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: _creation()),
                SizedBox(width: 16.w),
                Expanded(flex: 2, child: _existing()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _modeButton(String label, IconData icon, bool active, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8.r),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
        decoration: BoxDecoration(
          color: active ? AppColors.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(8.r),
          border: Border.all(color: active ? AppColors.primary : AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15.sp, color: active ? Colors.white : AppColors.textSecondary),
          SizedBox(width: 6.w),
          Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: active ? Colors.white : AppColors.textSecondary)),
        ]),
      ),
    );
  }

  Widget _creation() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: 10.h),
          child: Row(children: [
            _modeButton('New', Icons.add, !_editMode, () => setState(() {
              _editMode = false;
              _reloadGrid();
            })),
            SizedBox(width: 10.w),
            _modeButton('Edit', Icons.edit, _editMode, () => setState(() {
              _editMode = true;
              _reloadGrid();
            })),
            SizedBox(width: 10.w),
            OutlinedButton.icon(
              onPressed: _saving ? null : _copyFee,
              icon: const Icon(Icons.copy_all, size: 15),
              label: const Text('Copy Fee'),
            ),
            SizedBox(width: 12.w),
            Text(_editMode ? 'Editing saved demand for this selection' : 'Creating a new demand',
                style: TextStyle(fontSize: 11.sp, color: AppColors.textLight)),
          ]),
        ),
        Container(
          padding: EdgeInsets.all(12.w),
          decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.border.withValues(alpha: 0.6))),
          child: Wrap(spacing: 12.w, runSpacing: 10.h, children: [
            SizedBox(width: 190.w, child: DropdownButtonFormField<String>(initialValue: _cls, isExpanded: true, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary), decoration: _dec('Class *'), items: _classNames.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() {
              _cls = v;
              _reloadGrid();
            }))),
            SizedBox(width: 170.w, child: DropdownButtonFormField<String>(initialValue: _sem, isExpanded: true, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary), decoration: _dec('Semester *'), items: _semesters.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(), onChanged: (v) => setState(() {
              _sem = v;
              _reloadGrid();
            }))),
            SizedBox(width: 190.w, child: DropdownButtonFormField<String>(initialValue: _admId, isExpanded: true, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary), decoration: _dec('Admn Type'), items: [const DropdownMenuItem<String>(value: null, child: Text('All')), ..._admTypes.map((a) => DropdownMenuItem(value: a['adm_id'].toString(), child: Text(a['admname']?.toString() ?? '', overflow: TextOverflow.ellipsis)))], onChanged: (v) => setState(() {
              _admId = v;
              _reloadGrid();
            }))),
            SizedBox(width: 180.w, child: InkWell(onTap: () async {
              final now = DateTime.now();
              final p = await showDatePicker(context: context, initialDate: _due ?? now, firstDate: DateTime(now.year - 1), lastDate: DateTime(now.year + 5));
              if (p != null) setState(() => _due = p);
            }, child: InputDecorator(decoration: _dec('Pay On or Before *'), child: Text(_due == null ? 'Select' : _fmt(_due!), style: TextStyle(fontSize: 13.sp, color: _due == null ? AppColors.textLight : AppColors.textPrimary))))),
          ]),
        ),
        SizedBox(height: 12.h),
        Expanded(
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12.r), border: Border.all(color: AppColors.border.withValues(alpha: 0.6))),
            child: Column(children: [
              Container(color: AppColors.tableHeadBg, padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h), child: Row(children: [
                Expanded(flex: 3, child: Text('FEE TYPE', style: _h())),
                SizedBox(width: 140.w, child: Text('AMOUNT', style: _h())),
                SizedBox(width: 70.w, child: Text('ALL', textAlign: TextAlign.center, style: _h())),
                SizedBox(width: 44.w, child: Text('', style: _h())),
              ])),
              Expanded(child: ListView.separated(itemCount: _lines.length, separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.4)), itemBuilder: (_, i) {
                final l = _lines[i];
                return Padding(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 5.h), child: Row(children: [
                  Expanded(flex: 3, child: Padding(padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 10.h), child: Text(l.feeType ?? '', overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary)))),
                  SizedBox(width: 8.w),
                  SizedBox(width: 132.w, child: TextField(controller: l.amount, keyboardType: TextInputType.number, inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))], style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary), decoration: _dec(''), onChanged: (_) => setState(() {}))),
                  SizedBox(width: 70.w, child: Center(child: Tooltip(message: l.locked ? 'Apply-to-all fee is locked once created' : 'Apply this fee to all students in the class', child: Checkbox(value: l.applyAll, visualDensity: VisualDensity.compact, onChanged: l.locked ? null : (v) => setState(() => l.applyAll = v ?? false))))),
                  SizedBox(width: 44.w),
                ]));
              })),
              Divider(height: 1.h, color: AppColors.border),
              Padding(padding: EdgeInsets.all(12.w), child: Row(children: [
                Text('Tick ALL to demand a fee for every student', style: TextStyle(fontSize: 11.sp, color: AppColors.textLight)),
                const Spacer(),
                Text('Total  ', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                Text(_total.toStringAsFixed(2), style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.primary)),
                SizedBox(width: 16.w),
                ElevatedButton.icon(onPressed: _saving ? null : _save, icon: _saving ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.save, size: 16), label: const Text('Save'), style: ElevatedButton.styleFrom(backgroundColor: AppColors.success, foregroundColor: Colors.white)),
              ])),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _existing() {
    final filtered = _cls == null ? _rows : _rows.where((r) => (r['cfclass']?.toString() ?? '') == _cls).toList();
    return _tableShell(
      headerCells: [
        SizedBox(width: 70.w, child: Text('TERM', style: _h())),
        Expanded(flex: 2, child: Text('FEE TYPE', style: _h())),
        SizedBox(width: 70.w, child: Text('AMT', style: _h())),
        Expanded(child: Text('ADM', style: _h())),
        SizedBox(width: 44.w, child: Text('', style: _h())),
      ],
      body: filtered.isEmpty
          ? Center(child: Text('No fee demands', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
          : ListView.separated(itemCount: filtered.length, separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.5)), itemBuilder: (_, i) {
              final r = filtered[i];
              final id = r['cf_id'] is int ? r['cf_id'] as int : int.tryParse(r['cf_id'].toString()) ?? 0;
              return Padding(padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h), child: Row(children: [
                SizedBox(width: 70.w, child: Text(r['cfterm']?.toString() ?? '', style: TextStyle(fontSize: 12.sp, color: AppColors.textPrimary))),
                Expanded(flex: 2, child: Text(r['cffeetype']?.toString() ?? '', style: _c())),
                SizedBox(width: 70.w, child: Text(r['cfamount']?.toString() ?? '', style: _c())),
                Expanded(child: Text(_admName['${r['admissiontype'] ?? ''}'] ?? 'All', style: _c())),
                SizedBox(width: 44.w, child: Center(child: InkWell(onTap: () => _delete(id), child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('trash', size: 15, color: AppColors.error))))),
              ]));
            }),
    );
  }
}
