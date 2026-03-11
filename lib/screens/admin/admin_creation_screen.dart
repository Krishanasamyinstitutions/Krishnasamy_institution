import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/institution_user_model.dart';

class AdminCreationScreen extends StatefulWidget {
  const AdminCreationScreen({super.key});

  @override
  State<AdminCreationScreen> createState() => _AdminCreationScreenState();
}

class _AdminCreationScreenState extends State<AdminCreationScreen> {
  bool _isLoading = false;
  List<InstitutionUserModel> _users = [];

  // Form controllers
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();

  String? _selectedDesignation;
  int? _selectedDesId;
  int? _selectedReportTo;
  String? _selectedRole;
  InstitutionUserModel? _selectedUser; // for drilldown

  List<Map<String, dynamic>> _designationsList = [];
  List<Map<String, dynamic>> _rolesList = [];

  @override
  void initState() {
    super.initState();
    _fetchUsers();
    _fetchDesignations();
    _fetchRoles();
  }

  Future<void> _fetchDesignations() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    final list = await SupabaseService.getDesignations(insId);
    if (mounted) setState(() => _designationsList = list);
  }

  Future<void> _fetchRoles() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    final list = await SupabaseService.getRoles(insId);
    if (mounted) setState(() => _rolesList = list);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _fetchUsers() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    try {
      final users = await SupabaseService.getInstitutionUsers(insId);
      setState(() => _users = users);
    } catch (e) {
      debugPrint('Error loading users: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _createUser() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedDesignation == null || _selectedRole == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields')),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final inscode = auth.inscode;
    if (insId == null) return;

    final roleData = _rolesList.firstWhere((r) => r['urname'] == _selectedRole);

    final data = {
      'ins_id': insId,
      'inscode': inscode ?? '',
      'usename': _nameController.text.trim(),
      'usemail': _emailController.text.trim(),
      'usephone': _phoneController.text.trim(),
      'usepassword': _passwordController.text.trim(),
      'usestadate': DateTime.now().toIso8601String().split('T').first,
      'useotpstatus': 0,
      'usedob': '2000-01-01',
      'ur_id': roleData['ur_id'],
      'urname': _selectedRole,
      'des_id': _selectedDesId,
      'desname': _selectedDesignation,
      'userepto': _selectedReportTo ?? 0,
      'activestatus': 1,
    };

    setState(() => _isLoading = true);
    final success = await SupabaseService.createInstitutionUser(data);
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('User created successfully!'),
            backgroundColor: Colors.green,
          ),
        );
        _clearForm();
        _fetchUsers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to create user. Please try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _clearForm() {
    _nameController.clear();
    _emailController.clear();
    _phoneController.clear();
    _passwordController.clear();
    setState(() {
      _selectedDesignation = null;
      _selectedDesId = null;
      _selectedReportTo = null;
      _selectedRole = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.admin_panel_settings_rounded,
                  color: AppColors.primary, size: 22),
              const SizedBox(width: 10),
              Text(
                'User Creation',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Form + User list side by side
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Creation Form
              SizedBox(
                width: 340,
                child: _buildCreationForm(),
              ),
              const SizedBox(width: 24),
              // Right: Existing Users List
              Expanded(
                child: _buildUserList(),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCreationForm() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.person_add_rounded,
                    size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text('Create New User',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 20),

            // Staff Designation
            const Text('Staff Designation *',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedDesignation,
              decoration: _inputDecoration('Select designation'),
              items: _designationsList
                  .map((d) => DropdownMenuItem(
                        value: d['desname'] as String,
                        child: Text(d['desname'] as String),
                      ))
                  .toList(),
              onChanged: (v) {
                final match = _designationsList.firstWhere(
                  (d) => d['desname'] == v,
                  orElse: () => {},
                );
                setState(() {
                  _selectedDesignation = v;
                  _selectedDesId = match['des_id'] as int?;
                });
              },
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Designation Report To
            const Text('Designation Report To',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<int>(
              value: _selectedReportTo,
              decoration: _inputDecoration('Select reporting person'),
              items: [
                const DropdownMenuItem(value: 0, child: Text('None')),
                ..._users.map((u) => DropdownMenuItem(
                      value: u.useId,
                      child: Text('${u.usename} (${u.desname})'),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedReportTo = v),
            ),
            const SizedBox(height: 16),

            // Role
            const Text('Role *',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              decoration: _inputDecoration('Select role'),
              items: _rolesList
                  .map((r) => DropdownMenuItem(
                      value: r['urname'] as String,
                      child: Text(r['urname'] as String)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedRole = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // User Name
            const Text('User Name *',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _nameController,
              decoration: _inputDecoration('Enter user name'),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Email
            const Text('Email *',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _emailController,
              decoration: _inputDecoration('Enter email'),
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Phone
            const Text('Phone *',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _phoneController,
              decoration: _inputDecoration('Enter phone number'),
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Password
            const Text('Password *',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary)),
            const SizedBox(height: 6),
            TextFormField(
              controller: _passwordController,
              decoration: _inputDecoration('Enter password'),
              obscureText: true,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            const SizedBox(height: 24),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearForm,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Create User',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(fontSize: 13, color: Colors.grey.shade400),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
      ),
      filled: true,
      fillColor: AppColors.surface,
    );
  }

  Widget _buildUserList() {
    // If a user is selected, show drilldown
    if (_selectedUser != null) {
      return _buildUserDetail(_selectedUser!);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              children: [
                Icon(Icons.group_rounded, size: 18, color: AppColors.accent),
                const SizedBox(width: 8),
                const Text('Existing Users', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('${_users.length} users', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
                ),
                const SizedBox(width: 8),
                IconButton(icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textSecondary), onPressed: _fetchUsers),
              ],
            ),
          ),
          const Divider(height: 1),
          // Simplified table header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: AppColors.primary.withValues(alpha: 0.03),
            child: const Row(
              children: [
                SizedBox(width: 36, child: Text('S No.', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                Expanded(flex: 3, child: Text('Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Designation', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                Expanded(flex: 2, child: Text('Role', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                SizedBox(width: 70, child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                SizedBox(width: 30),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
          else if (_users.isEmpty)
            const Padding(padding: EdgeInsets.all(32), child: Center(child: Text('No users found', style: TextStyle(color: AppColors.textSecondary))))
          else
            ...List.generate(_users.length, (i) {
              final u = _users[i];
              return InkWell(
                onTap: () => setState(() => _selectedUser = u),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 36, child: Text('${i + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      Expanded(
                        flex: 3,
                        child: Text(u.usename, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(flex: 2, child: Text(u.desname, style: const TextStyle(fontSize: 12))),
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: u.urname.toLowerCase() == 'admin' ? AppColors.accent.withValues(alpha: 0.1) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(u.urname, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: u.urname.toLowerCase() == 'admin' ? AppColors.accent : AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 70,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: u.isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(u.isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: u.isActive ? AppColors.success : AppColors.error)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 30, child: Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary)),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildUserDetail(InstitutionUserModel u) {
    final reportTo = u.userepto > 0
        ? _users.where((x) => x.useId == u.userepto).map((x) => x.usename).firstOrNull
        : null;

    Widget detailRow(String label, String value, {IconData? icon, Color? valueColor}) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: AppColors.accent),
              const SizedBox(width: 10),
            ],
            SizedBox(
              width: 130,
              child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(value, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: valueColor ?? AppColors.textPrimary)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with back button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 20),
                  onPressed: () => setState(() => _selectedUser = null),
                  tooltip: 'Back to list',
                ),
                const SizedBox(width: 4),
                const Text('User Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: u.isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(u.isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: u.isActive ? AppColors.success : AppColors.error)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // User avatar + name header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                  child: Text(
                    u.usename.isNotEmpty ? u.usename[0].toUpperCase() : '?',
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.accent),
                  ),
                ),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.usename, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('${u.desname} - ${u.urname}', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Detail rows
          const SizedBox(height: 8),
          detailRow('Email', u.usemail, icon: Icons.email_rounded),
          Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border.withValues(alpha: 0.5)),
          detailRow('Phone', u.usephone, icon: Icons.phone_rounded),
          Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border.withValues(alpha: 0.5)),
          detailRow('Designation', u.desname, icon: Icons.badge_rounded),
          Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border.withValues(alpha: 0.5)),
          detailRow('Role', u.urname, icon: Icons.security_rounded, valueColor: u.urname.toLowerCase() == 'admin' ? AppColors.accent : null),
          Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border.withValues(alpha: 0.5)),
          detailRow('Reports To', reportTo ?? 'None', icon: Icons.supervisor_account_rounded),
          Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border.withValues(alpha: 0.5)),
          detailRow('Start Date', '${u.usestadate.day.toString().padLeft(2, '0')}/${u.usestadate.month.toString().padLeft(2, '0')}/${u.usestadate.year}', icon: Icons.calendar_today_rounded),
          Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border.withValues(alpha: 0.5)),
          detailRow('Date of Birth', '${u.usedob.day.toString().padLeft(2, '0')}/${u.usedob.month.toString().padLeft(2, '0')}/${u.usedob.year}', icon: Icons.cake_rounded),
          if (u.usecategory != null && u.usecategory!.isNotEmpty) ...[
            Divider(height: 1, indent: 20, endIndent: 20, color: AppColors.border.withValues(alpha: 0.5)),
            detailRow('Category', u.usecategory!, icon: Icons.category_rounded),
          ],
          const SizedBox(height: 16),
          // Terminate button
          if (u.isActive && u.urname.toLowerCase() != 'admin')
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmTerminate(u),
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Terminate', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _confirmTerminate(InstitutionUserModel u) {
    final reasonController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Terminate User', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to terminate "${u.usename}"? This will deactivate their account.'),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for termination *',
                hintText: 'Enter reason...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final reason = reasonController.text.trim();
              if (reason.isEmpty) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Please enter a reason'), backgroundColor: Colors.red),
                );
                return;
              }
              Navigator.pop(ctx);
              _terminateUser(u, reason);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Terminate'),
          ),
        ],
      ),
    );
  }

  Future<void> _terminateUser(InstitutionUserModel u, String reason) async {
    setState(() => _isLoading = true);
    final auth = context.read<AuthProvider>();
    final terminatedBy = auth.userName ?? '';
    final success = await SupabaseService.terminateInstitutionUser(u.useId, terminatedBy: terminatedBy, terminatedReason: reason);
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('User terminated successfully'), backgroundColor: Colors.green),
        );
        setState(() => _selectedUser = null);
        _fetchUsers();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to terminate user'), backgroundColor: Colors.red),
        );
      }
    }
  }
}
