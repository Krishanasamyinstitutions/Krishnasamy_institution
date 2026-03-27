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
  Map<String, dynamic>? _sequence;

  final _formKey = GlobalKey<FormState>();
  final _prefixController = TextEditingController();
  final _startController = TextEditingController();
  final _widthController = TextEditingController();

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _fetchSequence();
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _startController.dispose();
    _widthController.dispose();
    super.dispose();
  }

  Future<void> _fetchSequence() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    try {
      final result = await SupabaseService.client
          .from('sequence')
          .select()
          .eq('ins_id', insId)
          .maybeSingle();
      if (mounted) {
        setState(() {
          _sequence = result;
          if (result != null) {
            _prefixController.text = result['seqprefix']?.toString() ?? '';
            _startController.text = result['seqstart']?.toString() ?? '1';
            _widthController.text = result['seqwidth']?.toString() ?? '4';
          } else {
            _prefixController.text = 'PAY';
            _startController.text = '1';
            _widthController.text = '4';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSequence() async {
    if (!_formKey.currentState!.validate()) return;

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isSaving = true);

    try {
      final prefix = _prefixController.text.trim().toUpperCase();
      final start = int.parse(_startController.text.trim());
      final width = int.parse(_widthController.text.trim());
      final sequid = '$prefix${start.toString().padLeft(width, '0')}';

      final data = <String, dynamic>{
        'ins_id': insId,
        'seqprefix': prefix,
        'sequid': sequid,
        'seqstart': start,
        'seqcurno': _sequence != null ? _sequence!['seqcurno'] ?? 0 : 0,
        'seqwidth': width,
      };

      if (_sequence != null) return;

      data['seqcurno'] = 0;
      await SupabaseService.client.from('sequence').insert(data);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_sequence != null ? 'Sequence updated' : 'Sequence created'),
            backgroundColor: AppColors.success,
          ),
        );
        _fetchSequence();
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

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final prefix = _prefixController.text.trim().toUpperCase();
    final width = int.tryParse(_widthController.text.trim()) ?? 4;
    final start = int.tryParse(_startController.text.trim()) ?? 1;
    final preview = '$prefix${start.toString().padLeft(width, '0')}';
    final hasSequence = _sequence != null;

    return SingleChildScrollView(
      padding: EdgeInsets.all(24.w),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.receipt_long_rounded, color: AppColors.primary),
              ),
              SizedBox(width: 16.w),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Payment Sequence',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                  ),
                  SizedBox(height: 2.h),
                  Text(
                    'Configure how payment numbers are generated',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColors.textSecondary,
                        ),
                  ),
                ],
              ),
            ],
          ),

          SizedBox(height: 24.h),

          Container(
            constraints: const BoxConstraints(maxWidth: 500),
            padding: EdgeInsets.all(24.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Prefix', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 8.h),
                  TextFormField(
                    controller: _prefixController,
                    textCapitalization: TextCapitalization.characters,
                    enabled: !hasSequence,
                    decoration: InputDecoration(
                      hintText: 'e.g. PAY, RCT, INV',
                      prefixIcon: Icon(Icons.text_fields_rounded, size: 20.sp, color: AppColors.textLight),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Prefix is required';
                      return null;
                    },
                  ),

                  SizedBox(height: 20.h),

                  Text('Start Number', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 8.h),
                  TextFormField(
                    controller: _startController,
                    keyboardType: TextInputType.number,
                    enabled: !hasSequence,
                    decoration: InputDecoration(
                      hintText: 'e.g. 1',
                      prefixIcon: Icon(Icons.pin_rounded, size: 20.sp, color: AppColors.textLight),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Start number is required';
                      if (int.tryParse(v.trim()) == null) return 'Must be a number';
                      return null;
                    },
                  ),

                  SizedBox(height: 20.h),

                  Text('Number Width (zero-padding)', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(height: 8.h),
                  TextFormField(
                    controller: _widthController,
                    keyboardType: TextInputType.number,
                    enabled: !hasSequence,
                    decoration: InputDecoration(
                      hintText: 'e.g. 4 for 0001',
                      prefixIcon: Icon(Icons.format_list_numbered_rounded, size: 20.sp, color: AppColors.textLight),
                    ),
                    onChanged: (_) => setState(() {}),
                    validator: (v) {
                      if (v == null || v.trim().isEmpty) return 'Width is required';
                      final n = int.tryParse(v.trim());
                      if (n == null || n < 1 || n > 10) return 'Must be 1-10';
                      return null;
                    },
                  ),

                  SizedBox(height: 24.h),

                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.all(16.w),
                    decoration: BoxDecoration(
                      color: AppColors.primaryLight,
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: Column(
                      children: [
                        Text(hasSequence ? 'Current Format' : 'Preview', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
                        SizedBox(height: 4.h),
                        Text(
                          preview,
                          style: TextStyle(
                            fontSize: 22.sp,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                            letterSpacing: 2,
                          ),
                        ),
                        if (hasSequence) ...[
                          SizedBox(height: 8.h),
                          Text(
                            'Current number: ${_sequence!['seqcurno'] ?? 0}',
                            style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),

                  if (hasSequence) ...[
                    SizedBox(height: 16.h),
                    Container(
                      width: double.infinity,
                      padding: EdgeInsets.all(12.w),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20.sp),
                          SizedBox(width: 8.w),
                          Text(
                            'Sequence already configured for this year',
                            style: TextStyle(fontSize: 13.sp, color: AppColors.success, fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (!hasSequence) ...[
                    SizedBox(height: 24.h),
                    SizedBox(
                      width: double.infinity,
                      height: 48.h,
                      child: ElevatedButton.icon(
                        onPressed: _isSaving ? null : _saveSequence,
                        icon: _isSaving
                            ? SizedBox(width: 18.w, height: 18.h, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : const Icon(Icons.save_rounded, size: 20),
                        label: const Text('Create Sequence'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
                          elevation: 0,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
