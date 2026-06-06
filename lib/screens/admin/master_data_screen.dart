import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_icon.dart';
import 'master_import_screen.dart';

/// Master Data — Course and Class masters in the Fee-Master CRUD style:
/// a left Add/Edit form + right table, with a top-right "Import CSV/Excel"
/// button that opens the bulk importer. A single sidebar entry with internal
/// Course / Class tabs (same layout as Admission Master).
class MasterDataScreen extends StatelessWidget {
  const MasterDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
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
                    const AppIcon('document-upload', size: 20, color: AppColors.primary),
                    SizedBox(width: 10.w),
                    Text('Master Data',
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
                  Tab(text: 'Course'),
                  Tab(text: 'Class'),
                ],
              ),
              Divider(height: 1.h, color: AppColors.border),
              const Expanded(
                child: TabBarView(
                  children: [
                    _CourseMasterPanel(),
                    _ClassMasterPanel(),
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

// ── shared bits (mirrors fee_master_screen) ────────────────────────────────
InputDecoration _dec(String label) => InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
    );

void _snack(BuildContext ctx, String msg, Color color) {
  ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(msg), backgroundColor: color));
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

/// Auto-assigned display order = max(ordid) + 1 over the already-loaded active
/// rows. Order is generated, not entered by hand.
int _nextOrder(List<Map<String, dynamic>> rows) {
  var mx = 0;
  for (final r in rows) {
    final o = (r['ordid'] is num) ? (r['ordid'] as num).toInt() : int.tryParse(r['ordid']?.toString() ?? '');
    if (o != null && o > mx) mx = o;
  }
  return mx + 1;
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
/// MasterImportScreen: Course = 2, Class = 3.
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
// COURSE
// ══════════════════════════════════════════════════════════════════════════
class _CourseMasterPanel extends StatefulWidget {
  const _CourseMasterPanel();
  @override
  State<_CourseMasterPanel> createState() => _CourseMasterPanelState();
}

class _CourseMasterPanelState extends State<_CourseMasterPanel> with AutomaticKeepAliveClientMixin {
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
      final res = await SupabaseService.fromSchema('course')
          .select('*').eq('ins_id', _insId).eq('activestatus', 1);
      final list = List<Map<String, dynamic>>.from(res as List)
        ..sort((a, b) {
          final oa = (a['ordid'] is num) ? (a['ordid'] as num).toInt() : 1 << 30;
          final ob = (b['ordid'] is num) ? (b['ordid'] as num).toInt() : 1 << 30;
          if (oa != ob) return oa.compareTo(ob);
          return (a['courname'] ?? '').toString().toLowerCase().compareTo((b['courname'] ?? '').toString().toLowerCase());
        });
      if (!mounted) return;
      setState(() {
        _rows = list;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _edit(Map<String, dynamic> r) {
    setState(() {
      _editId = r['cour_id'] is int ? r['cour_id'] as int : int.tryParse(r['cour_id'].toString());
      _name.text = r['courname']?.toString() ?? '';
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
    if (name.isEmpty) return _snack(context, 'Enter a course name.', AppColors.warning);
    if (_rows.any((r) => (r['courname']?.toString().trim().toLowerCase() ?? '') == name.toLowerCase() &&
        (r['cour_id']?.toString() ?? '') != (_editId?.toString() ?? ''))) {
      return _snack(context, '"$name" already exists.', AppColors.warning);
    }
    setState(() => _saving = true);
    try {
      if (_editId != null) {
        await SupabaseService.fromSchema('course').update({
          'courname': name,
        }).eq('cour_id', _editId!);
        if (mounted) _snack(context, 'Course updated.', AppColors.success);
      } else {
        await SupabaseService.fromSchema('course').insert({
          'cour_id': await _nextId('course', 'cour_id'),
          'courname': name,
          'ordid': _nextOrder(_rows),
          'ins_id': _insId,
          'activestatus': 1,
        });
        if (mounted) _snack(context, 'Course added.', AppColors.success);
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
    if (!await _confirmDelete(context, 'course')) return;
    try {
      await SupabaseService.fromSchema('course').update({'activestatus': 0}).eq('cour_id', id);
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
          _importBar(context, title: 'Course', tabIndex: 2, saving: _saving, onReturn: _load),
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
                        Text(_editId != null ? 'Edit Course' : 'Add Course', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                        SizedBox(height: 12.h),
                        TextField(controller: _name, style: TextStyle(fontSize: 13.sp), decoration: _dec('Course Name *'), onSubmitted: (_) => _add()),
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
                      Expanded(child: Text('COURSE NAME', style: _h())),
                      SizedBox(width: 90.w, child: Text('ACTION', textAlign: TextAlign.center, style: _h())),
                    ],
                    body: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _rows.isEmpty
                            ? Center(child: Text('No courses', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
                            : ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.5)),
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  final id = r['cour_id'] is int ? r['cour_id'] as int : int.tryParse(r['cour_id'].toString()) ?? 0;
                                  return Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                                    child: Row(children: [
                                      SizedBox(width: 50.w, child: Text('${i + 1}', style: _c())),
                                      Expanded(child: Text(r['courname']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
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
// CLASS
// ══════════════════════════════════════════════════════════════════════════
class _ClassMasterPanel extends StatefulWidget {
  const _ClassMasterPanel();
  @override
  State<_ClassMasterPanel> createState() => _ClassMasterPanelState();
}

class _ClassMasterPanelState extends State<_ClassMasterPanel> with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();
  String? _courId;
  String? _succId;
  List<Map<String, dynamic>> _rows = [];
  List<Map<String, dynamic>> _courses = [];
  Map<String, String> _courName = {}; // cour_id → courname
  Map<String, String> _claName = {};  // cla_id  → claname
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
      final results = await Future.wait([
        SupabaseService.fromSchema('class').select('*').eq('ins_id', _insId).eq('activestatus', 1),
        SupabaseService.fromSchema('course').select('cour_id, courname, ordid').eq('ins_id', _insId).eq('activestatus', 1),
      ]);
      final classRows = List<Map<String, dynamic>>.from((results[0] as List).cast<Map<String, dynamic>>());
      final courseRows = List<Map<String, dynamic>>.from((results[1] as List).cast<Map<String, dynamic>>());
      final courName = {for (final c in courseRows) c['cour_id'].toString(): (c['courname'] ?? '').toString()};
      final courOrd = <String, int>{
        for (final c in courseRows)
          if (c['ordid'] != null) c['cour_id'].toString(): (c['ordid'] as num).toInt(),
      };
      final claName = {for (final r in classRows) r['cla_id'].toString(): (r['claname'] ?? '').toString()};
      // Sort by course order → class order → class name, matching the Students sidebar.
      classRows.sort((a, b) {
        final ca = courOrd[a['cour_id']?.toString()] ?? 1 << 30;
        final cb = courOrd[b['cour_id']?.toString()] ?? 1 << 30;
        if (ca != cb) return ca.compareTo(cb);
        final oa = (a['ordid'] is num) ? (a['ordid'] as num).toInt() : 1 << 30;
        final ob = (b['ordid'] is num) ? (b['ordid'] as num).toInt() : 1 << 30;
        if (oa != ob) return oa.compareTo(ob);
        return (a['claname'] ?? '').toString().toLowerCase().compareTo((b['claname'] ?? '').toString().toLowerCase());
      });
      courseRows.sort((a, b) {
        final oa = (a['ordid'] is num) ? (a['ordid'] as num).toInt() : 1 << 30;
        final ob = (b['ordid'] is num) ? (b['ordid'] as num).toInt() : 1 << 30;
        if (oa != ob) return oa.compareTo(ob);
        return (a['courname'] ?? '').toString().toLowerCase().compareTo((b['courname'] ?? '').toString().toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _rows = classRows;
        _courses = courseRows;
        _courName = courName;
        _claName = claName;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _edit(Map<String, dynamic> r) {
    setState(() {
      _editId = r['cla_id'] is int ? r['cla_id'] as int : int.tryParse(r['cla_id'].toString());
      _name.text = r['claname']?.toString() ?? '';
      _courId = r['cour_id']?.toString();
      _succId = r['succeedingclass']?.toString();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editId = null;
      _name.clear();
      _courId = null;
      _succId = null;
    });
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) return _snack(context, 'Enter a class name.', AppColors.warning);
    if (_rows.any((r) => (r['claname']?.toString().trim().toLowerCase() ?? '') == name.toLowerCase() &&
        (r['cla_id']?.toString() ?? '') != (_editId?.toString() ?? ''))) {
      return _snack(context, '"$name" already exists.', AppColors.warning);
    }
    setState(() => _saving = true);
    try {
      final payload = {
        'claname': name,
        'cour_id': _courId == null ? null : int.tryParse(_courId!),
        'succeedingclass': _succId == null ? null : int.tryParse(_succId!),
      };
      if (_editId != null) {
        await SupabaseService.fromSchema('class').update(payload).eq('cla_id', _editId!);
        if (mounted) _snack(context, 'Class updated.', AppColors.success);
      } else {
        await SupabaseService.fromSchema('class').insert({
          'cla_id': await _nextId('class', 'cla_id'),
          ...payload,
          'ordid': _nextOrder(_rows),
          'ins_id': _insId,
          'activestatus': 1,
        });
        if (mounted) _snack(context, 'Class added.', AppColors.success);
      }
      _cancelEdit();
      await _load();
    } catch (e) {
      if (mounted) _snack(context, 'Save failed. ${friendlyError(e)}', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(int id) async {
    if (!await _confirmDelete(context, 'class')) return;
    try {
      await SupabaseService.fromSchema('class').update({'activestatus': 0}).eq('cla_id', id);
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
          _importBar(context, title: 'Class', tabIndex: 3, saving: _saving, onReturn: _load),
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
                        Text(_editId != null ? 'Edit Class' : 'Add Class', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                        SizedBox(height: 12.h),
                        TextField(controller: _name, style: TextStyle(fontSize: 13.sp), decoration: _dec('Class Name *'), onSubmitted: (_) => _add()),
                        SizedBox(height: 10.h),
                        DropdownButtonFormField<String>(
                          initialValue: _courId,
                          isExpanded: true,
                          style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                          decoration: _dec('Course'),
                          items: [
                            const DropdownMenuItem<String>(value: null, child: Text('None')),
                            ..._courses.map((c) => DropdownMenuItem(value: c['cour_id'].toString(), child: Text(c['courname']?.toString() ?? '', overflow: TextOverflow.ellipsis))),
                          ],
                          // Changing the course resets the succeeding class — it
                          // must belong to the same course.
                          onChanged: (v) => setState(() {
                            _courId = v;
                            _succId = null;
                          }),
                        ),
                        SizedBox(height: 10.h),
                        Builder(builder: (_) {
                          // Succeeding class is scoped to the selected course
                          // (no course selected → no options to choose from).
                          final succClasses = _rows.where((r) =>
                              r['cla_id']?.toString() != _editId?.toString() &&
                              _courId != null &&
                              r['cour_id']?.toString() == _courId).toList();
                          final succValue =
                              succClasses.any((r) => r['cla_id'].toString() == _succId) ? _succId : null;
                          return DropdownButtonFormField<String>(
                            initialValue: succValue,
                            isExpanded: true,
                            style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                            decoration: _dec('Succeeding Class'),
                            items: [
                              const DropdownMenuItem<String>(value: null, child: Text('None')),
                              ...succClasses.map((r) => DropdownMenuItem(value: r['cla_id'].toString(), child: Text(r['claname']?.toString() ?? '', overflow: TextOverflow.ellipsis))),
                            ],
                            onChanged: (v) => setState(() => _succId = v),
                          );
                        }),
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
                      Expanded(flex: 2, child: Text('CLASS NAME', style: _h())),
                      Expanded(flex: 2, child: Text('COURSE', style: _h())),
                      Expanded(flex: 2, child: Text('SUCCEEDING', style: _h())),
                      SizedBox(width: 90.w, child: Text('ACTION', textAlign: TextAlign.center, style: _h())),
                    ],
                    body: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _rows.isEmpty
                            ? Center(child: Text('No classes', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
                            : ListView.separated(
                                itemCount: _rows.length,
                                separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.5)),
                                itemBuilder: (_, i) {
                                  final r = _rows[i];
                                  final id = r['cla_id'] is int ? r['cla_id'] as int : int.tryParse(r['cla_id'].toString()) ?? 0;
                                  return Padding(
                                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                                    child: Row(children: [
                                      SizedBox(width: 50.w, child: Text('${i + 1}', style: _c())),
                                      Expanded(flex: 2, child: Text(r['claname']?.toString() ?? '', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                                      Expanded(flex: 2, child: Text(_courName['${r['cour_id'] ?? ''}'] ?? '', style: _c())),
                                      Expanded(flex: 2, child: Text(_claName['${r['succeedingclass'] ?? ''}'] ?? '', style: _c())),
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
