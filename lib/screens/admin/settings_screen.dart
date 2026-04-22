import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_icon.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs (pill style — same pattern as Master Data / Reports)
        ListenableBuilder(
          listenable: _tabController,
          builder: (context, _) {
            final selected = _tabController.index;
            const tabLabels = ['Payment Sequence', 'Fine Rules'];
            const tabIcons = ['receipt-1', 'judge'];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tabLabels.length; i++) ...[
                      GestureDetector(
                        onTap: () => _tabController.animateTo(i),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected == i ? AppColors.tabSelected : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(tabIcons[i], size: 16, color: selected == i ? AppColors.textOnPrimary : AppColors.textPrimary),
                              const SizedBox(width: 8),
                              Text(
                                tabLabels[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected == i ? AppColors.textOnPrimary : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i < tabLabels.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        // Content (white card — same as Master Data / Reports)
        Expanded(
          child: Container(
            decoration: AppCard.decoration(),
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(top: 8),
            child: TabBarView(
              controller: _tabController,
              children: const [
                _PaymentSequenceTab(),
                _FineRulesTab(),
              ],
            ),
          ),
        ),
      ],
    );
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
                        Text('${_designations.length} records', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                        SizedBox(width: 12.w),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: _fetchDesignations,
                            icon: AppIcon('refresh', size: 16, color: Colors.white),
                            label: const Text('Refresh'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: EdgeInsets.symmetric(horizontal: 18.w),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                              textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    color: AppColors.tableHeadBg,
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('S NO.', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                        Expanded(flex: 3, child: Text('DESIGNATION NAME', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                        Expanded(flex: 3, child: Text('REPORTS TO', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                        SizedBox(width: 80.w, child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: CircularProgressIndicator()))
                  else if (_designations.isEmpty)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: Text('No designations found', style: TextStyle(color: AppColors.textPrimary))))
                  else
                    ..._designations.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final des = entry.value;
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                        color: idx.isEven ? Colors.white : AppColors.surface,
                        child: Row(
                          children: [
                            SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
                            Expanded(flex: 3, child: Text(des['desname']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500))),
                            Expanded(flex: 3, child: Text(_getDesignationName(des['desrepto'] as int?), style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
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
                        Text('${_roles.length} records', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                        SizedBox(width: 12.w),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: _fetchRoles,
                            icon: AppIcon('refresh', size: 16, color: Colors.white),
                            label: const Text('Refresh'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: EdgeInsets.symmetric(horizontal: 18.w),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                              textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                    color: AppColors.tableHeadBg,
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('S NO.', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                        Expanded(flex: 3, child: Text('ROLE NAME', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                        Expanded(flex: 2, child: Text('INS CODE', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                        SizedBox(width: 80.w, child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3))),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: CircularProgressIndicator()))
                  else if (_roles.isEmpty)
                    Padding(padding: EdgeInsets.all(40.w), child: Center(child: Text('No roles found', style: TextStyle(color: AppColors.textPrimary))))
                  else
                    ..._roles.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final role = entry.value;
                      return Container(
                        padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                        color: idx.isEven ? Colors.white : AppColors.surface,
                        child: Row(
                          children: [
                            SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
                            Expanded(flex: 3, child: Text(role['urname']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500))),
                            Expanded(flex: 2, child: Text(role['inscode']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary))),
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
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
            // Header
            Container(
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 14.h),
              child: Row(
                children: [
                  Icon(Icons.receipt_long_rounded, color: AppColors.accent, size: 20.sp),
                  SizedBox(width: 8.w),
                  Text('Payment Sequence', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                  const Spacer(),
                  Text('Number Width:', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                  SizedBox(width: 8.w),
                  SizedBox(
                    width: 60.w,
                    height: 34,
                    child: TextFormField(
                      controller: _widthController,
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        hintText: '4',
                        contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.border)),
                        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.border)),
                        isDense: true,
                      ),
                      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
                  SizedBox(width: 6.w),
                  Text('(e.g. 4 = 0001)', style: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary)),
                ],
              ),
            ),
            // Table
            if (_feeGroups.isEmpty)
              Padding(
                padding: EdgeInsets.all(24.w),
                child: Center(
                  child: Text('No fee groups found. Import fee groups first in Master Data.', style: TextStyle(color: AppColors.textPrimary)),
                ),
              )
            else
              Padding(
                padding: EdgeInsets.all(16.w),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8.r),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: DataTable(
                dividerThickness: 0,
                headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
                headingTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.sp, color: AppColors.textPrimary, letterSpacing: 0.3),
                dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                columnSpacing: 20,
                horizontalMargin: 16,
                headingRowHeight: 42,
                columns: const [
                  DataColumn(label: Text('S NO.')),
                  DataColumn(label: Text('FEE GROUP')),
                  DataColumn(label: Text('PREFIX')),
                  DataColumn(label: Text('PREVIEW')),
                  DataColumn(label: Text('CURRENT')),
                  DataColumn(label: Text('ACTION')),
                ],
                rows: List.generate(_feeGroups.length, (idx) {
                  final fg = _feeGroups[idx];
                  final fgId = fg['fg_id'] as int;
                  final fgDesc = fg['fgdesc']?.toString() ?? '';
                  final seq = _getSequenceForFg(fgId);
                  final hasSeq = seq != null;
                  final width = int.tryParse(_widthController.text.trim()) ?? 4;

                  final autoPrefix = fgDesc.split(' ').map((w) => w.isNotEmpty ? w[0] : '').join().toUpperCase().substring(0, fgDesc.split(' ').map((w) => w.isNotEmpty ? w[0] : '').join().length.clamp(0, 3));

                  final prefix = hasSeq ? (seq['seqprefix']?.toString() ?? '') : autoPrefix;
                  final curNo = hasSeq ? (seq['seqcurno'] ?? 0) : 0;
                  final preview = '$prefix${'1'.padLeft(width, '0')}';

                  return DataRow(
                    color: WidgetStateProperty.all(idx.isEven ? Colors.white : AppColors.surface),
                    cells: [
                      DataCell(Text('${idx + 1}')),
                      DataCell(Text(fgDesc)),
                      DataCell(
                        hasSeq
                            ? Text(prefix, style: TextStyle(fontWeight: FontWeight.w700, color: AppColors.primary))
                            : SizedBox(
                                width: 100.w,
                                height: 32.h,
                                child: TextFormField(
                                  initialValue: autoPrefix,
                                  textCapitalization: TextCapitalization.characters,
                                  decoration: InputDecoration(
                                    hintText: 'Prefix',
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 6.h),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r), borderSide: BorderSide(color: AppColors.border)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6.r), borderSide: BorderSide(color: AppColors.border)),
                                    isDense: true,
                                  ),
                                  style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                  onChanged: (v) => _editedPrefixes[fgId] = v.trim().toUpperCase(),
                                ),
                              ),
                      ),
                      DataCell(Text(preview, style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600))),
                      DataCell(Text('$curNo')),
                      DataCell(
                        hasSeq
                            ? Icon(Icons.check_circle_rounded, color: AppColors.success, size: 20.sp)
                            : ElevatedButton(
                                onPressed: _isSaving
                                    ? null
                                    : () => _saveSequenceForFg(fgId, fgDesc, _editedPrefixes[fgId] ?? autoPrefix),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                                  minimumSize: Size.zero,
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6.r)),
                                ),
                                child: Text('Create', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                              ),
                      ),
                    ],
                  );
                }),
                    ),
                  ),
                ),
              ),
          ],
        ),
    );
  }

}

// ==================== Fine Rules Tab ====================

class _FineRulesTab extends StatefulWidget {
  const _FineRulesTab();

  @override
  State<_FineRulesTab> createState() => _FineRulesTabState();
}

class _FineRulesTabState extends State<_FineRulesTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<Map<String, dynamic>> _rules = [];
  bool _loading = true;

  final _ruleNameCtrl = TextEditingController();
  final _fromDaysCtrl = TextEditingController();
  final _toDaysCtrl = TextEditingController();
  final _fineValueCtrl = TextEditingController();
  String _fineType = 'FIXED';
  String _feeType = '';
  List<String> _feeTypes = [];
  int? _editingId;

  @override
  void initState() {
    super.initState();
    _loadRules();
    _loadFeeTypes();
  }

  @override
  void dispose() {
    _ruleNameCtrl.dispose();
    _fromDaysCtrl.dispose();
    _toDaysCtrl.dispose();
    _fineValueCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRules() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      final result = await SupabaseService.fromSchema('finerule')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('from_days');
      if (mounted) setState(() { _rules = List<Map<String, dynamic>>.from(result); _loading = false; });
    } catch (e) {
      debugPrint('Error loading fine rules: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadFeeTypes() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      // Only show fee types where fines are applicable (feefineapplicable = 1)
      final response = await SupabaseService.fromSchema('feetype')
          .select('feedesc')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .eq('feefineapplicable', 1)
          .order('fee_id', ascending: true);
      final types = (response as List)
          .map((e) => e['feedesc']?.toString() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _feeTypes = types;
          if (types.isNotEmpty && (_feeType == 'ALL' || !types.contains(_feeType))) {
            _feeType = types.first;
          }
        });
      }
    } catch (e) {
      debugPrint('Error loading fine-applicable fee types: $e');
    }
  }

  void _clearForm() {
    _ruleNameCtrl.clear();
    _fromDaysCtrl.clear();
    _toDaysCtrl.clear();
    _fineValueCtrl.clear();
    _fineType = 'FIXED';
    _feeType = _feeTypes.isNotEmpty ? _feeTypes.first : '';
    _editingId = null;
  }

  void _editRule(Map<String, dynamic> rule) {
    setState(() {
      _editingId = rule['fr_id'] as int?;
      _ruleNameCtrl.text = rule['rulename']?.toString() ?? '';
      _fromDaysCtrl.text = rule['from_days']?.toString() ?? '';
      _toDaysCtrl.text = rule['to_days']?.toString() ?? '';
      _fineValueCtrl.text = rule['fine_value']?.toString() ?? '';
      _fineType = rule['fine_type']?.toString() ?? 'FIXED';
      final ruleFeeType = rule['feetype']?.toString() ?? '';
      _feeType = (ruleFeeType.isNotEmpty && _feeTypes.contains(ruleFeeType))
          ? ruleFeeType
          : (_feeTypes.isNotEmpty ? _feeTypes.first : '');
    });
  }

  Future<void> _saveRule() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    final ruleName = _ruleNameCtrl.text.trim();
    final fromDays = int.tryParse(_fromDaysCtrl.text.trim());
    final toDays = _toDaysCtrl.text.trim().isEmpty ? null : int.tryParse(_toDaysCtrl.text.trim());
    final fineValue = double.tryParse(_fineValueCtrl.text.trim());

    if (ruleName.isEmpty || fromDays == null || fineValue == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill Rule Name, From Days, and Fine Value'), backgroundColor: Colors.red),
      );
      return;
    }

    final data = {
      'ins_id': insId,
      'rulename': ruleName,
      'feetype': _feeType,
      'from_days': fromDays,
      'to_days': toDays,
      'fine_type': _fineType,
      'fine_value': fineValue,
      'activestatus': 1,
      'createdby': auth.userName ?? 'Admin',
    };

    try {
      if (_editingId != null) {
        await SupabaseService.fromSchema('finerule').update(data).eq('fr_id', _editingId!);
      } else {
        await SupabaseService.fromSchema('finerule').insert(data);
      }
      _clearForm();
      _loadRules();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(_editingId != null ? 'Rule updated' : 'Rule created'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _deleteRule(int frId) async {
    try {
      await SupabaseService.fromSchema('finerule').update({'activestatus': 0}).eq('fr_id', frId);
      _loadRules();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rule deleted'), backgroundColor: AppColors.success));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: Form
        SizedBox(
          width: 350.w,
          child: SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Container(
              padding: EdgeInsets.all(20.w),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppIcon.linear('judge', size: 20, color: AppColors.accent),
                      SizedBox(width: 8.w),
                      Text(_editingId != null ? 'Edit Fine Rule' : 'Add Fine Rule',
                          style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                    ],
                  ),
                  SizedBox(height: 20.h),
                  _fieldLabel('Rule Name', required: true),
                  SizedBox(height: 6.h),
                  TextField(
                    controller: _ruleNameCtrl,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    decoration: _fieldDecoration(hint: 'e.g., 1 Week Overdue'),
                  ),
                  SizedBox(height: 14.h),
                  _fieldLabel('Fee Type'),
                  SizedBox(height: 6.h),
                  DropdownButtonFormField<String>(
                    value: _feeType,
                    isExpanded: true,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    decoration: _fieldDecoration(),
                    items: _feeTypes.map((f) => DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontSize: 13.sp)))).toList(),
                    onChanged: (v) => setState(() => _feeType = v ?? 'ALL'),
                  ),
                  SizedBox(height: 14.h),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('From Days', required: true),
                            SizedBox(height: 6.h),
                            TextField(
                              controller: _fromDaysCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                              decoration: _fieldDecoration(hint: '1'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _fieldLabel('To Days'),
                            SizedBox(height: 6.h),
                            TextField(
                              controller: _toDaysCtrl,
                              keyboardType: TextInputType.number,
                              style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                              decoration: _fieldDecoration(hint: '7'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 14.h),
                  _fieldLabel('Fine Type'),
                  SizedBox(height: 6.h),
                  DropdownButtonFormField<String>(
                    value: _fineType,
                    isExpanded: true,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    decoration: _fieldDecoration(),
                    items: const [
                      DropdownMenuItem(value: 'FIXED', child: Text('Fixed Amount (Rs.)')),
                      DropdownMenuItem(value: 'PERCENT', child: Text('Percentage (%)')),
                    ],
                    onChanged: (v) => setState(() => _fineType = v ?? 'FIXED'),
                  ),
                  SizedBox(height: 14.h),
                  _fieldLabel(_fineType == 'FIXED' ? 'Fine Amount (Rs.)' : 'Fine Percentage (%)', required: true),
                  SizedBox(height: 6.h),
                  TextField(
                    controller: _fineValueCtrl,
                    keyboardType: TextInputType.number,
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
                    decoration: _fieldDecoration(hint: _fineType == 'FIXED' ? '50' : '2'),
                  ),
                  SizedBox(height: 22.h),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _saveRule,
                          icon: Icon(_editingId != null ? Icons.save_rounded : Icons.add_rounded, size: 18.sp),
                          label: Text(_editingId != null ? 'Update' : 'Add Rule', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.accent,
                            foregroundColor: Colors.white,
                            padding: EdgeInsets.symmetric(vertical: 14.h),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                          ),
                        ),
                      ),
                      if (_editingId != null) ...[
                        SizedBox(width: 8.w),
                        TextButton(
                          onPressed: () => setState(() => _clearForm()),
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
        // Right: Rules list
        Expanded(
          child: Padding(
            padding: EdgeInsets.all(16.w),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: EdgeInsets.all(16.w),
                    child: Row(
                      children: [
                        AppIcon.linear('task-square', size: 20, color: AppColors.accent),
                        SizedBox(width: 8.w),
                        Text('Fine Rules', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Text('${_rules.length} rules', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                        SizedBox(width: 8.w),
                        SizedBox(
                          height: 40,
                          child: ElevatedButton.icon(
                            onPressed: _loadRules,
                            icon: AppIcon('refresh', size: 16, color: Colors.white),
                            label: const Text('Refresh'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF10B981),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: EdgeInsets.symmetric(horizontal: 18.w),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                              textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_loading)
                    const Expanded(child: Center(child: CircularProgressIndicator()))
                  else if (_rules.isEmpty)
                    Expanded(child: Center(child: Text('No fine rules configured', style: TextStyle(color: AppColors.textPrimary, fontSize: 13.sp))))
                  else
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(16.w, 0, 16.w, 16.w),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(10.r),
                          child: Container(
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.border),
                              borderRadius: BorderRadius.circular(10.r),
                            ),
                            child: LayoutBuilder(
                              builder: (ctx, constraints) => SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                                  child: SingleChildScrollView(
                                child: DataTable(
                                  headingRowColor: WidgetStateProperty.all(AppColors.tableHeadBg),
                                  headingTextStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3),
                                  dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                                  dataRowColor: WidgetStateProperty.resolveWith<Color?>((states) {
                                    if (states.contains(WidgetState.hovered)) return AppColors.primaryLight.withValues(alpha: 0.4);
                                    return null;
                                  }),
                                  columnSpacing: 48.w,
                                  horizontalMargin: 24.w,
                                  headingRowHeight: 48,
                                  dataRowMinHeight: 52,
                                  dataRowMaxHeight: 52,
                                  dividerThickness: 0.6,
                                  columns: const [
                                    DataColumn(label: Text('RULE NAME')),
                                    DataColumn(label: Text('FEE TYPE')),
                                    DataColumn(label: Text('FROM'), numeric: true),
                                    DataColumn(label: Text('TO'), numeric: true),
                                    DataColumn(label: Text('TYPE')),
                                    DataColumn(label: Text('VALUE'), numeric: true),
                                    DataColumn(label: Text('ACTIONS')),
                                  ],
                                  rows: List<DataRow>.generate(_rules.length, (i) {
                                    final r = _rules[i];
                                    final fineType = r['fine_type']?.toString() ?? 'FIXED';
                                    final fineValue = (r['fine_value'] as num?)?.toDouble() ?? 0;
                                    final isFixed = fineType == 'FIXED';
                                    final zebra = i.isOdd ? const Color(0xFFF8FAFF) : Colors.white;
                                    return DataRow(
                                      color: WidgetStateProperty.resolveWith<Color?>((states) {
                                        if (states.contains(WidgetState.hovered)) return AppColors.primaryLight.withValues(alpha: 0.35);
                                        return zebra;
                                      }),
                                      cells: [
                                        DataCell(Text(
                                          r['rulename']?.toString() ?? '',
                                          style: TextStyle(fontSize: 12.5.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                        )),
                                        DataCell(_chip(
                                          label: r['feetype']?.toString() ?? 'ALL',
                                          color: AppColors.accent,
                                        )),
                                        DataCell(Text('${r['from_days'] ?? 0}')),
                                        DataCell(Text(
                                          r['to_days'] != null ? '${r['to_days']}' : '∞',
                                          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
                                        )),
                                        DataCell(_chip(
                                          label: isFixed ? 'Fixed' : 'Percent',
                                          color: isFixed ? AppColors.success : AppColors.warning,
                                        )),
                                        DataCell(Text(
                                          isFixed ? '₹${fineValue.toStringAsFixed(0)}' : '${fineValue.toStringAsFixed(1)}%',
                                          style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textSecondary),
                                        )),
                                        DataCell(Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _actionBtn(
                                              iconName: 'edit-2',
                                              color: AppColors.accent,
                                              tooltip: 'Edit',
                                              onTap: () => _editRule(r),
                                            ),
                                            SizedBox(width: 6.w),
                                            _actionBtn(
                                              iconName: 'trash',
                                              color: AppColors.error,
                                              tooltip: 'Delete',
                                              onTap: () => _deleteRule(r['fr_id'] as int),
                                            ),
                                          ],
                                        )),
                                      ],
                                    );
                                  }),
                                ),
                                ),
                              ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _fieldLabel(String text, {bool required = false}) {
    return Text(
      required ? '$text *' : text,
      style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.black),
    );
  }

  InputDecoration _fieldDecoration({String? hint}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textPrimary.withValues(alpha: 0.6), fontSize: 13.sp),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.border)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.border)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.accent)),
      filled: true,
      fillColor: Colors.white,
    );
  }

  Widget _chip({required String label, required Color color}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20.r),
        border: Border.all(color: color.withValues(alpha: 0.3), width: 0.8),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.2),
      ),
    );
  }

  Widget _actionBtn({required String iconName, required Color color, required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8.r),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8.r),
          child: Padding(
            padding: EdgeInsets.all(7.w),
            child: AppIcon.linear(iconName, size: 14, color: color),
          ),
        ),
      ),
    );
  }
}
