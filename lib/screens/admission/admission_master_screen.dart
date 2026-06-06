import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../utils/friendly_error.dart';
import '../../services/admission_service.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/master_crud_panel.dart';

/// Admission Master — manage the admission lookups (Admission Type, Quota,
/// Community) used by the admission form. Each tab is a simple add/list/delete
/// over its per-schema master table.
class AdmissionMasterScreen extends StatelessWidget {
  const AdmissionMasterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 5,
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
                    const AppIcon('category', size: 20, color: AppColors.primary),
                    SizedBox(width: 10.w),
                    Text('Admission Master',
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
                  Tab(text: 'Admission Type'),
                  Tab(text: 'Quota'),
                  Tab(text: 'Community'),
                  Tab(text: 'Concession'),
                  Tab(text: 'Reg No'),
                ],
              ),
              Divider(height: 1.h, color: AppColors.border),
              const Expanded(
                child: TabBarView(
                  children: [
                    MasterCrudPanel(table: 'admissiontype', idCol: 'adm_id', nameCol: 'admname', title: 'Admission Type', importTabIndex: 0),
                    MasterCrudPanel(table: 'quota', idCol: 'quo_id', nameCol: 'quoname', title: 'Quota', importTabIndex: 1),
                    MasterCrudPanel(table: 'community', idCol: 'com_id', nameCol: 'comname', title: 'Community'),
                    MasterCrudPanel(table: 'concessioncategory', idCol: 'con_id', nameCol: 'condesc', title: 'Concession', importTabIndex: 6, includeCreatedBy: false),
                    _RegNoPanel(),
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

/// Register Number Sequencing — richer master (name, prefix/suffix, range, width).
class _RegNoPanel extends StatefulWidget {
  const _RegNoPanel();

  @override
  State<_RegNoPanel> createState() => _RegNoPanelState();
}

class _RegNoPanelState extends State<_RegNoPanel> with AutomaticKeepAliveClientMixin {
  final _name = TextEditingController();
  final _affix = TextEditingController();
  final _start = TextEditingController(text: '1');
  final _end = TextEditingController();
  final _width = TextEditingController(text: '4');
  final _division = TextEditingController();
  String _mode = 'Prefix';
  List<Map<String, dynamic>> _rows = [];
  bool _loading = true;
  bool _saving = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final c in [_name, _affix, _start, _end, _width, _division]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await AdmissionService.getMasterRows('regnoseq', 'rns_id');
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _snack('Enter a name.', AppColors.warning);
      return;
    }
    final auth = context.read<AuthProvider>();
    setState(() => _saving = true);
    try {
      final id = await AdmissionService.nextMasterId('regnoseq', 'rns_id');
      await AdmissionService.addMasterRow('regnoseq', {
        'rns_id': id,
        'rnsname': name,
        'rnsmode': _mode == 'Prefix' ? 'P' : 'S',
        'rnsaffix': _affix.text.trim().isEmpty ? null : _affix.text.trim(),
        'rnsstart': int.tryParse(_start.text.trim()),
        'rnsend': _end.text.trim().isEmpty ? null : int.tryParse(_end.text.trim()),
        'rnswidth': int.tryParse(_width.text.trim()),
        'rnscurrent': 0,
        'division': _division.text.trim().isEmpty ? null : _division.text.trim(),
        'ins_id': auth.insId,
        'activestatus': 1,
        'createdby': auth.userName,
      });
      for (final c in [_name, _affix, _division]) {
        c.clear();
      }
      _start.text = '1';
      _width.text = '4';
      _end.clear();
      setState(() => _mode = 'Prefix');
      _snack('Register sequence added.', AppColors.success);
      await _load();
    } catch (e) {
      _snack('Add failed. ${friendlyError(e)}', AppColors.error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete(int id, String name) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Register Sequence'),
        content: Text('Remove "$name"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete', style: TextStyle(color: AppColors.error))),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await AdmissionService.deleteMasterRow('regnoseq', 'rns_id', id);
      _snack('Removed.', AppColors.success);
      await _load();
    } catch (e) {
      _snack('Delete failed. ${friendlyError(e)}', AppColors.error);
    }
  }

  void _snack(String m, Color c) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m), backgroundColor: c));
  }

  InputDecoration _dec(String label) => InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 12.h),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
      );

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.all(16.w),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 340.w, child: _form()),
          SizedBox(width: 16.w),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _form() {
    return Container(
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
          Text('Register Number Sequencing',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          SizedBox(height: 12.h),
          TextField(controller: _name, style: TextStyle(fontSize: 13.sp), decoration: _dec('Name *')),
          SizedBox(height: 10.h),
          DropdownButtonFormField<String>(
            initialValue: _mode,
            decoration: _dec('Mode'),
            items: const [
              DropdownMenuItem(value: 'Prefix', child: Text('Prefix')),
              DropdownMenuItem(value: 'Suffix', child: Text('Suffix')),
            ],
            onChanged: (v) => setState(() => _mode = v ?? 'Prefix'),
          ),
          SizedBox(height: 10.h),
          TextField(controller: _affix, style: TextStyle(fontSize: 13.sp), decoration: _dec('Prefix / Suffix value')),
          SizedBox(height: 10.h),
          Row(
            children: [
              Expanded(child: TextField(controller: _start, keyboardType: TextInputType.number, style: TextStyle(fontSize: 13.sp), decoration: _dec('Start No'))),
              SizedBox(width: 8.w),
              Expanded(child: TextField(controller: _end, keyboardType: TextInputType.number, style: TextStyle(fontSize: 13.sp), decoration: _dec('End No'))),
              SizedBox(width: 8.w),
              Expanded(child: TextField(controller: _width, keyboardType: TextInputType.number, style: TextStyle(fontSize: 13.sp), decoration: _dec('Width'))),
            ],
          ),
          SizedBox(height: 10.h),
          TextField(controller: _division, style: TextStyle(fontSize: 13.sp), maxLines: 2, decoration: _dec('Division')),
          SizedBox(height: 14.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _saving ? null : _add,
              icon: _saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.add, size: 16),
              label: const Text('Add'),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, foregroundColor: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _list() {
    TextStyle h() => TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary);
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
            child: Row(
              children: [
                Expanded(flex: 3, child: Text('NAME', style: h())),
                SizedBox(width: 64.w, child: Text('PRE/SUF', style: h())),
                SizedBox(width: 64.w, child: Text('AFFIX', style: h())),
                SizedBox(width: 56.w, child: Text('START', style: h())),
                SizedBox(width: 56.w, child: Text('END', style: h())),
                SizedBox(width: 36.w, child: Text('W', style: h())),
                SizedBox(width: 44.w, child: Text('', style: h())),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _rows.isEmpty
                    ? Center(child: Text('No register sequences', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)))
                    : ListView.separated(
                        itemCount: _rows.length,
                        separatorBuilder: (_, __) => Divider(height: 1.h, color: AppColors.border.withValues(alpha: 0.5)),
                        itemBuilder: (_, i) {
                          final r = _rows[i];
                          final id = r['rns_id'] is int ? r['rns_id'] as int : int.tryParse(r['rns_id'].toString()) ?? 0;
                          final name = r['rnsname']?.toString() ?? '';
                          final mode = (r['rnsmode']?.toString() ?? 'P') == 'P' ? 'Prefix' : 'Suffix';
                          TextStyle c() => TextStyle(fontSize: 12.sp, color: AppColors.textSecondary);
                          return Padding(
                            padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 9.h),
                            child: Row(
                              children: [
                                Expanded(flex: 3, child: Text(name, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                                SizedBox(width: 64.w, child: Text(mode, style: c())),
                                SizedBox(width: 64.w, child: Text(r['rnsaffix']?.toString() ?? '-', style: c())),
                                SizedBox(width: 56.w, child: Text(r['rnsstart']?.toString() ?? '-', style: c())),
                                SizedBox(width: 56.w, child: Text(r['rnsend']?.toString() ?? '-', style: c())),
                                SizedBox(width: 36.w, child: Text(r['rnswidth']?.toString() ?? '-', style: c())),
                                SizedBox(
                                  width: 44.w,
                                  child: Center(
                                    child: InkWell(
                                      onTap: () => _delete(id, name),
                                      borderRadius: BorderRadius.circular(6.r),
                                      child: Padding(padding: EdgeInsets.all(4.w), child: const AppIcon('trash', size: 16, color: AppColors.error)),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
