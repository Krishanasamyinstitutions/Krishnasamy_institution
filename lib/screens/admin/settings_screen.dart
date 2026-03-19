import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

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
      children: [
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.border),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: Colors.white,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
            indicator: BoxDecoration(
              color: AppColors.accent,
              borderRadius: BorderRadius.circular(10),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            padding: const EdgeInsets.all(4),
            tabs: const [
              Tab(text: 'Staff Designation'),
              Tab(text: 'Custom Roles'),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: const [
              _StaffDesignationTab(),
              _CustomRolesTab(),
            ],
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
      labelStyle: const TextStyle(fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Form panel
          SizedBox(
            width: 360,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                        Icon(Icons.badge_rounded, color: AppColors.accent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          _editingDesId != null ? 'Edit Designation' : 'Add Designation',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('Designation Name'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      value: _selectedReportTo,
                      decoration: _inputDecoration('Reports To'),
                      items: [
                        const DropdownMenuItem<int?>(value: null, child: Text('None', style: TextStyle(fontSize: 13))),
                        ..._designations.map((d) => DropdownMenuItem<int?>(
                              value: d['des_id'] as int,
                              child: Text(d['desname']?.toString() ?? '', style: const TextStyle(fontSize: 13)),
                            )),
                      ],
                      onChanged: (v) => setState(() => _selectedReportTo = v),
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveDesignation,
                            icon: Icon(_editingDesId != null ? Icons.save : Icons.add, size: 18),
                            label: Text(_editingDesId != null ? 'Update' : 'Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        if (_editingDesId != null) ...[
                          const SizedBox(width: 8),
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
          const SizedBox(width: 24),
          // Table panel
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.05),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.badge_rounded, size: 18, color: AppColors.accent),
                        const SizedBox(width: 8),
                        const Text('Designations', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${_designations.length} records', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        IconButton(icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary), onPressed: _fetchDesignations),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: const Color(0xFF6C8EEF),
                    child: const Row(
                      children: [
                        SizedBox(width: 40, child: Text('S NO.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('DESIGNATION NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('REPORTS TO', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                        SizedBox(width: 80, child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  else if (_designations.isEmpty)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No designations found', style: TextStyle(color: AppColors.textSecondary))))
                  else
                    ..._designations.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final des = entry.value;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        color: idx.isEven ? Colors.white : AppColors.surface,
                        child: Row(
                          children: [
                            SizedBox(width: 40, child: Text('${idx + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                            Expanded(flex: 3, child: Text(des['desname']?.toString() ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                            Expanded(flex: 3, child: Text(_getDesignationName(des['desrepto'] as int?), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                            SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(onTap: () => _editDesignation(des), borderRadius: BorderRadius.circular(6), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_rounded, size: 16, color: AppColors.accent))),
                                  const SizedBox(width: 8),
                                  InkWell(onTap: () => _deleteDesignation(des['des_id'] as int), borderRadius: BorderRadius.circular(6), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_rounded, size: 16, color: Colors.red))),
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
      labelStyle: const TextStyle(fontSize: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Form panel
          SizedBox(
            width: 360,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
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
                        Icon(Icons.security_rounded, color: AppColors.accent, size: 22),
                        const SizedBox(width: 8),
                        Text(
                          _editingUrId != null ? 'Edit Role' : 'Add Role',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _nameController,
                      decoration: _inputDecoration('Role Name'),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                    const SizedBox(height: 24),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _isLoading ? null : _saveRole,
                            icon: Icon(_editingUrId != null ? Icons.save : Icons.add, size: 18),
                            label: Text(_editingUrId != null ? 'Update' : 'Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                        if (_editingUrId != null) ...[
                          const SizedBox(width: 8),
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
          const SizedBox(width: 24),
          // Table panel
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.05),
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.admin_panel_settings_rounded, size: 18, color: AppColors.accent),
                        const SizedBox(width: 8),
                        const Text('Custom Roles', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                        const Spacer(),
                        Text('${_roles.length} records', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        IconButton(icon: const Icon(Icons.refresh, size: 18, color: AppColors.textSecondary), onPressed: _fetchRoles),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: const Color(0xFF6C8EEF),
                    child: const Row(
                      children: [
                        SizedBox(width: 40, child: Text('S NO.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('ROLE NAME', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 2, child: Text('INS CODE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                        SizedBox(width: 80, child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white))),
                      ],
                    ),
                  ),
                  if (_isLoading)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                  else if (_roles.isEmpty)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No roles found', style: TextStyle(color: AppColors.textSecondary))))
                  else
                    ..._roles.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final role = entry.value;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        color: idx.isEven ? Colors.white : AppColors.surface,
                        child: Row(
                          children: [
                            SizedBox(width: 40, child: Text('${idx + 1}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                            Expanded(flex: 3, child: Text(role['urname']?.toString() ?? '-', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500))),
                            Expanded(flex: 2, child: Text(role['inscode']?.toString() ?? '-', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                            SizedBox(
                              width: 80,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(onTap: () => _editRole(role), borderRadius: BorderRadius.circular(6), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.edit_rounded, size: 16, color: AppColors.accent))),
                                  const SizedBox(width: 8),
                                  InkWell(onTap: () => _deleteRole(role['ur_id'] as int), borderRadius: BorderRadius.circular(6), child: const Padding(padding: EdgeInsets.all(4), child: Icon(Icons.delete_rounded, size: 16, color: Colors.red))),
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
