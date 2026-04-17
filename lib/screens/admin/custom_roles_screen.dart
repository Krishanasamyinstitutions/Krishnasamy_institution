import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class CustomRolesScreen extends StatefulWidget {
  const CustomRolesScreen({super.key});

  @override
  State<CustomRolesScreen> createState() => _CustomRolesScreenState();
}

class _CustomRolesScreenState extends State<CustomRolesScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _roles = [];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int? _editingUrId;

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
    return Padding(
      padding: EdgeInsets.all(20.w),
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
                children: [
                  // Header
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
                  // Table header
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
                  // Data rows
                  if (_isLoading)
                    Padding(
                      padding: EdgeInsets.all(40.w),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_roles.isEmpty)
                    Padding(
                      padding: EdgeInsets.all(40.w),
                      child: Center(child: Text('No roles found', style: TextStyle(color: AppColors.textSecondary))),
                    )
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
                                  InkWell(
                                    onTap: () => _editRole(role),
                                    borderRadius: BorderRadius.circular(6.r),
                                    child: Padding(
                                      padding: EdgeInsets.all(4.w),
                                      child: Icon(Icons.edit_rounded, size: 16.sp, color: AppColors.accent),
                                    ),
                                  ),
                                  SizedBox(width: 8.w),
                                  InkWell(
                                    onTap: () => _deleteRole(role['ur_id'] as int),
                                    borderRadius: BorderRadius.circular(6.r),
                                    child: Padding(
                                      padding: EdgeInsets.all(4.w),
                                      child: Icon(Icons.delete_rounded, size: 16.sp, color: Colors.red),
                                    ),
                                  ),
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
