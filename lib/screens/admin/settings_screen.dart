import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return const _PaymentSequenceTab();
  }
}

// ==================== Tab 1: Staff Designation ====================

class _StaffDesignationTab extends StatefulWidget {
  const _StaffDesignationTab();

  @override
  State<_StaffDesignationTab> createState() => _StaffDesignationTabState();
}

class _StaffDesignationTabState extends State<_StaffDesignationTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = false;
  List<Map<String, dynamic>> _designations = [];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int? _selectedReportTo;
  int? _editingDesId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchDesignations();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchDesignations() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    final data = await SupabaseService.getDesignations(insId);
    if (mounted) {
      setState(() {
        _designations = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveDesignation() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);

    bool success;
    if (_editingDesId != null) {
      success = await SupabaseService.updateDesignation(_editingDesId!, {
        'desname': _nameController.text.trim(),
        'desrepto': _selectedReportTo,
      });
    } else {
      success = await SupabaseService.createDesignation({
        'ins_id': insId,
        'desname': _nameController.text.trim(),
        'desrepto': _selectedReportTo,
        'activestatus': 1,
      });
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_editingDesId != null ? 'Designation updated' : 'Designation created'), backgroundColor: AppColors.success),
        );
        _resetForm();
        _fetchDesignations();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save designation'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _editDesignation(Map<String, dynamic> des) {
    setState(() {
      _editingDesId = des['des_id'] as int;
      _nameController.text = des['desname']?.toString() ?? '';
      _selectedReportTo = des['desrepto'] as int?;
    });
  }

  Future<void> _deleteDesignation(int desId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Designation'),
        content: const Text('Are you sure you want to delete this designation?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    final success = await SupabaseService.deleteDesignation(desId);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Designation deleted'), backgroundColor: AppColors.success),
        );
        _fetchDesignations();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete designation'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _resetForm() {
    _nameController.clear();
    _selectedReportTo = null;
    _editingDesId = null;
  }

  String _getDesignationName(int? desId) {
    if (desId == null) return '-';
    final match = _designations.where((d) => d['des_id'] == desId);
    return match.isNotEmpty ? (match.first['desname']?.toString() ?? '-') : '-';
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13.sp),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Form panel
          SizedBox(
            width: 360.w,
            child: Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_rounded, color: AppColors.accent, size: 22.sp),
                        SizedBox(width: 8.w),
                        Text(
                          _editingDesId != null ? 'Edit Designation' : 'Add Designation',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('Designation Name'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    SizedBox(height: 16.h),
                    DropdownButtonFormField<int?>(
                      value: _selectedReportTo,
                      decoration: _inputDecoration('Reports To'),
                      items: [
                        DropdownMenuItem<int?>(value: null, child: Text('None', style: TextStyle(fontSize: 13.sp))),
                        ..._designations.map((d) => DropdownMenuItem<int?>(
                              value: d['des_id'] as int,
                              child: Text(d['desname']?.toString() ?? '', style: TextStyle(fontSize: 13.sp)),
                            )),
                      ],
                      onChanged: (v) => setState(() => _selectedReportTo = v),
                    ),
                    SizedBox(height: 24.h),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveDesignation,
                            icon: Icon(_editingDesId != null ? Icons.save : Icons.add, size: 18.sp),
                            label: Text(_editingDesId != null ? 'Update' : 'Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                            ),
                          ),
                        ),
                        if (_editingDesId != null) ...[
                          SizedBox(width: 8.w),
                          TextButton(
                            onPressed: () => setState(() => _resetForm()),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 24.w),
          // Table panel
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.badge_rounded, size: 18.sp, color: AppColors.accent),
                        SizedBox(width: 8.w),
                        Text('Designations', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${_designations.length} records', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                        SizedBox(width: 12.w),
                        TextButton.icon(
                          onPressed: _fetchDesignations,
                          icon: Icon(Icons.refresh_rounded, size: 16.sp),
                          label: const Text('Refresh'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                            textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    color: const Color(0xFF6C8EEF),
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('S NO.', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('DESIGNATION NAME', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('REPORTS TO', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                        SizedBox(width: 80.w, child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: CircularProgressIndicator()))
                  else if (_designations.isEmpty)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: Text('No designations found', style: TextStyle(color: AppColors.textSecondary))))
                  else
                    ..._designations.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final des = entry.value;
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                        color: idx.isEven ? Colors.white : AppColors.surface,
                        child: Row(
                          children: [
                            SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                            Expanded(flex: 3, child: Text(des['desname']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500))),
                            Expanded(flex: 3, child: Text(_getDesignationName(des['desrepto'] as int?), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                            SizedBox(
                              width: 80.w,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(onTap: () => _editDesignation(des), borderRadius: BorderRadius.circular(6.r), child: Padding(padding: EdgeInsets.all(4.w), child: Icon(Icons.edit_rounded, size: 16.sp, color: AppColors.accent))),
                                  SizedBox(width: 8.w),
                                  InkWell(onTap: () => _deleteDesignation(des['des_id'] as int), borderRadius: BorderRadius.circular(6.r), child: Padding(padding: EdgeInsets.all(4.w), child: Icon(Icons.delete_rounded, size: 16.sp, color: Colors.red))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Tab 2: Custom Roles ====================

class _CustomRolesTab extends StatefulWidget {
  const _CustomRolesTab();

  @override
  State<_CustomRolesTab> createState() => _CustomRolesTabState();
}

class _CustomRolesTabState extends State<_CustomRolesTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = false;
  List<Map<String, dynamic>> _roles = [];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int? _editingUrId;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchRoles();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _fetchRoles() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    final data = await SupabaseService.getUserRoles(insId);
    if (mounted) {
      setState(() {
        _roles = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveRole() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final inscode = auth.inscode;
    if (insId == null) return;

    setState(() => _isLoading = true);

    bool success;
    if (_editingUrId != null) {
      success = await SupabaseService.updateUserRole(_editingUrId!, {
        'urname': _nameController.text.trim(),
      });
    } else {
      success = await SupabaseService.createUserRole({
        'ins_id': insId,
        'inscode': inscode ?? '',
        'urname': _nameController.text.trim(),
        'activestatus': 1,
      });
    }

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_editingUrId != null ? 'Role updated' : 'Role created'), backgroundColor: AppColors.success),
        );
        _resetForm();
        _fetchRoles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to save role'), backgroundColor: Colors.red),
        );
        setState(() => _isLoading = false);
      }
    }
  }

  void _editRole(Map<String, dynamic> role) {
    setState(() {
      _editingUrId = role['ur_id'] as int;
      _nameController.text = role['urname']?.toString() ?? '';
    });
  }

  Future<void> _deleteRole(int urId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Role'),
        content: const Text('Are you sure you want to delete this role?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete', style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm != true) return;

    final success = await SupabaseService.deleteUserRole(urId);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Role deleted'), backgroundColor: AppColors.success),
        );
        _fetchRoles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to delete role'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _resetForm() {
    _nameController.clear();
    _editingUrId = null;
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(fontSize: 13.sp),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
      contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: EdgeInsets.only(top: 4.h),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Form panel
          SizedBox(
            width: 360.w,
            child: Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.security_rounded, color: AppColors.accent, size: 22.sp),
                        SizedBox(width: 8.w),
                        Text(
                          _editingUrId != null ? 'Edit Role' : 'Add Role',
                          style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    SizedBox(height: 20.h),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('Role Name'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    SizedBox(height: 24.h),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveRole,
                            icon: Icon(_editingUrId != null ? Icons.save : Icons.add, size: 18.sp),
                            label: Text(_editingUrId != null ? 'Update' : 'Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                            ),
                          ),
                        ),
                        if (_editingUrId != null) ...[
                          SizedBox(width: 8.w),
                          TextButton(
                            onPressed: () => setState(() => _resetForm()),
                            child: const Text('Cancel'),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(width: 24.w),
          // Table panel
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(12.r)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings_rounded, size: 18.sp, color: AppColors.accent),
                        SizedBox(width: 8.w),
                        Text('Custom Roles', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${_roles.length} records', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                        SizedBox(width: 12.w),
                        TextButton.icon(
                          onPressed: _fetchRoles,
                          icon: Icon(Icons.refresh_rounded, size: 16.sp),
                          label: const Text('Refresh'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                            textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    color: const Color(0xFF6C8EEF),
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('S NO.', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('ROLE NAME', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 2, child: Text('INS CODE', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                        SizedBox(width: 80.w, child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: CircularProgressIndicator()))
                  else if (_roles.isEmpty)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: Text('No roles found', style: TextStyle(color: AppColors.textSecondary))))
                  else
                    ..._roles.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final role = entry.value;
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                        color: idx.isEven ? Colors.white : AppColors.surface,
                        child: Row(
                          children: [
                            SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                            Expanded(flex: 3, child: Text(role['urname']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500))),
                            Expanded(flex: 2, child: Text(role['inscode']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                            SizedBox(
                              width: 80.w,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(onTap: () => _editRole(role), borderRadius: BorderRadius.circular(6.r), child: Padding(padding: EdgeInsets.all(4.w), child: Icon(Icons.edit_rounded, size: 16.sp, color: AppColors.accent))),
                                  SizedBox(width: 8.w),
                                  InkWell(onTap: () => _deleteRole(role['ur_id'] as int), borderRadius: BorderRadius.circular(6.r), child: Padding(padding: EdgeInsets.all(4.w), child: Icon(Icons.delete_rounded, size: 16.sp, color: Colors.red))),
                                ],
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ==================== Tab 3: Payment Sequence ====================

class _PaymentSequenceTab extends StatefulWidget {
  const _PaymentSequenceTab();

  @override
  State<_PaymentSequenceTab> createState() => _PaymentSequenceTabState();
}

class _PaymentSequenceTabState extends State<_PaymentSequenceTab> with AutomaticKeepAliveClientMixin {
  bool _isLoading = false;
  bool _isSaving = false;
  List<Map<String, dynamic>> _feeGroups = [];
  List<Map<String, dynamic>> _sequences = [];
  final _widthController = TextEditingController(text: '5');
  final Map<int, String> _editedPrefixes = {};

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  @override
  void dispose() {
    _widthController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }

    setState(() => _isLoading = true);
    try {
      final fgResult = await SupabaseService.fromSchema('feegroup')
          .select('fg_id, fgdesc')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('fgdesc');
      final seqResult = await SupabaseService.fromSchema('sequence')
          .select()
          .eq('ins_id', insId);
      if (mounted) {
        setState(() {
          _feeGroups = List<Map<String, dynamic>>.from(fgResult);
          _sequences = List<Map<String, dynamic>>.from(seqResult);
          if (_sequences.isNotEmpty) {
            _widthController.text = _sequences.first['seqwidth']?.toString() ?? '4';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Sequence fetch error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Map<String, dynamic>? _getSequenceForFg(int fgId) {
    try {
      return _sequences.firstWhere((s) => s['fg_id'] == fgId);
    } catch (_) {
      return null;
    }
  }

  Future<void> _saveSequenceForFg(int fgId, String fgDesc, String prefix) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isSaving = true);
    try {
      final width = int.tryParse(_widthController.text.trim()) ?? 4;
      final sequid = '${prefix.toUpperCase()}${'1'.padLeft(width, '0')}';

      // Get year info
      final yearResult = await SupabaseService.fromSchema('year')
          .select('yr_id, yrlabel')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('yr_id', ascending: false)
          .limit(1)
          .maybeSingle();
      final yrId = yearResult?['yr_id'] ?? 0;
      final yrLabel = yearResult?['yrlabel']?.toString() ?? '';

      await SupabaseService.fromSchema('sequence').insert({
        'ins_id': insId,
        'mod_id': 0,
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'actname': fgDesc,
        'seqname': prefix.toUpperCase(),
        'isprefix': 'Y',
        'seqprefix': prefix.toUpperCase(),
        'seqstart': 1,
        'seqwidth': width,
        'sequid': sequid,
        'seqcurno': 0,
        'fg_id': fgId,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sequence created for $fgDesc'), backgroundColor: AppColors.success),
        );
        _fetchData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
    if (mounted) setState(() => _isSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: AppColors.primaryLight, borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
              ),
              SizedBox(width: 16.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Payment Sequence', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  SizedBox(height: 2.h),
                  Text('Configure receipt number prefix per fee group', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppColors.textSecondary)),
                ],
              ),
            ],
          ),

          SizedBox(height: 16.h),

          // Global width setting
          Container(
            constraints: const BoxConstraints(maxWidth: 300),
            child: Row(
              children: [
                Text('Number Width:', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                SizedBox(width: 12.w),
                SizedBox(
                  width: 80.w,
                  child: TextFormField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      hintText: '4',
                      contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
                      isDense: true,
                    ),
                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                  ),
                ),
                SizedBox(width: 8.w),
                Text('(e.g. 4 = 0001)', style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
              ],
            ),
          ),

          SizedBox(height: 24.h),

          if (_feeGroups.isEmpty)
            Container(
              padding: EdgeInsets.all(24.w),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Center(
                child: Text('No fee groups found. Import fee groups first in Master Data.', style: TextStyle(color: AppColors.textSecondary)),
              ),
            )
          else
            // Fee group sequence table
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.only(topLeft: Radius.circular(11.r), topRight: Radius.circular(11.r)),
                    ),
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('S.No', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                        Expanded(flex: 3, child: Text('FEE GROUP', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                        Expanded(flex: 2, child: Text('PREFIX', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                        Expanded(flex: 2, child: Text('PREVIEW', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                        Expanded(flex: 1, child: Text('CURRENT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                        SizedBox(width: 80.w, child: Text('ACTION', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white), textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                  // Rows
                  ..._feeGroups.asMap().entries.map((entry) {
                    final idx = entry.key;
                    final fg = entry.value;
                    final fgId = fg['fg_id'] as int;
                    final fgDesc = fg['fgdesc']?.toString() ?? '';
                    final seq = _getSequenceForFg(fgId);
                    final hasSeq = seq != null;
                    final width = int.tryParse(_widthController.text.trim()) ?? 4;

                    // Auto-generate prefix from first letters of each word
                    final autoPrefix = fgDesc.split(' ').map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase().substring(0, fgDesc.split(' ').map((w) => w.isNotEmpty ? w[0] : '').join().length.clamp(0, 3));

                    final prefix = hasSeq ? (seq['seqprefix']?.toString() ?? '') : autoPrefix;
                    final curNo = hasSeq ? (seq['seqcurno'] ?? 0) : 0;
                    final preview = '$prefix${'1'.padLeft(width, '0')}';

                    return Container(
                      padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                      color: idx.isEven ? Colors.white : AppColors.surface,
                      child: Row(
                        children: [
                          SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                          Expanded(flex: 3, child: Text(fgDesc, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500))),
                          Expanded(
                            flex: 2,
                            child: hasSeq
                                ? Text(prefix, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.primary))
                                : SizedBox(
                                    height: 36.h,
                                    child: TextFormField(
                                      initialValue: autoPrefix,
                                      textCapitalization: TextCapitalization.characters,
                                      decoration: InputDecoration(
                                        hintText: 'Prefix',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r)),
                                        isDense: true,
                                      ),
                                      style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
                                      onChanged: (v) => _editedPrefixes[fgId] = v.trim().toUpperCase(),
                                    ),
                                  ),
                          ),
                          Expanded(flex: 2, child: Text(preview, style: TextStyle(fontSize: 13.sp, color: AppColors.accent, fontWeight: FontWeight.w600))),
                          Expanded(flex: 1, child: Text('$curNo', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                          SizedBox(
                            width: 80.w,
                            child: hasSeq
                                ? Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20.sp)
                                : ElevatedButton(
                                    onPressed: _isSaving
                                        ? null
                                        : () => _saveSequenceForFg(fgId, fgDesc, _editedPrefixes[fgId] ?? autoPrefix),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.accent,
                                      foregroundColor: Colors.white,
                                      padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                                      minimumSize: Size.zero,
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
                                    ),
                                    child: Text('Create', style: TextStyle(fontSize: 11.sp)),
                                  ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
        ],
      ),
    );
  }

}
