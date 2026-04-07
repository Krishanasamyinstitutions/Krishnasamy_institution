import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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


  void _showAddDesignationDialog() {
    final controller = TextEditingController();
    int? reportsTo;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.badge_outlined, size: 18.sp, color: AppColors.accent),
              SizedBox(width: 8.w),
              Text('Add Designation', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Designation Name', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 6.h),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter designation name',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                ),
              ),
              SizedBox(height: 16.h),
              Text('Reports To', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
              SizedBox(height: 6.h),
              DropdownButtonFormField<int?>(
                value: reportsTo,
                decoration: InputDecoration(
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
                ),
                items: [
                  const DropdownMenuItem(value: null, child: Text('None')),
                  ..._designationsList.map((d) => DropdownMenuItem(
                        value: d['des_id'] as int?,
                        child: Text(d['desname'] as String),
                      )),
                ],
                onChanged: (v) => setDialogState(() => reportsTo = v),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: Icon(Icons.add, size: 16.sp, color: Colors.white),
              style: ElevatedButton.styleFrom(backgroundColor: AppColors.accent, padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h)),
              onPressed: () async {
                final name = controller.text.trim();
                if (name.isEmpty) return;
                final auth = Provider.of<AuthProvider>(ctx, listen: false);
                final insId = auth.insId;
                if (insId == null) return;
                final ok = await SupabaseService.createDesignation({
                  'ins_id': insId,
                  'desname': name,
                  'desrepto': reportsTo,
                  'activestatus': 1,
                });
                if (!mounted) return;
                if (ok) {
                  Navigator.pop(ctx);
                  final desigs = await SupabaseService.getDesignations(insId);
                  setState(() {
                    _designationsList = desigs;
                    _selectedDesignation = name;
                    final match = desigs.firstWhere((d) => d['desname'] == name, orElse: () => {});
                    _selectedDesId = match['des_id'] as int?;
                  });
                }
              },
              label: const Text('Add', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
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
              Icon(Icons.admin_panel_settings_rounded,
                  color: AppColors.primary, size: 22.sp),
              SizedBox(width: 10.w),
              Text(
                'User Creation',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          SizedBox(height: 20.h),

          // Form + User list side by side
          LayoutBuilder(builder: (context, constraints) {
            final screenWidth = MediaQuery.of(context).size.width;
            final isCompact = screenWidth <= 1366;
            return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Left: Creation Form
              Expanded(
                flex: 3,
                child: _buildCreationForm(),
              ),
              SizedBox(width: isCompact ? 12.w : 24.w),
              // Right: Existing Users List
              Expanded(
                flex: 7,
                child: _buildUserList(),
              ),
            ],
          );
          }),
        ],
      ),
    );
  }

  Widget _buildCreationForm() {
    return Container(
      padding: EdgeInsets.all(20.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
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
                    size: 18.sp, color: AppColors.accent),
                SizedBox(width: 8.w),
                Text('Create New User',
                    style:
                        TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
              ],
            ),
            SizedBox(height: 20.h),

            // Staff Designation
            Text('Staff Designation *',
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            SizedBox(height: 6.h),
            DropdownButtonFormField<String>(
              value: _selectedDesignation,
              isExpanded: true,
              decoration: _inputDecoration('Select designation'),
              style: _inputStyle,
              items: [
                ..._designationsList.map((d) => DropdownMenuItem(
                      value: d['desname'] as String,
                      child: Text(d['desname'] as String),
                    )),
                DropdownMenuItem(
                  value: '__add_new__',
                  child: Row(
                    children: [
                      Icon(Icons.add_circle_outline, size: 16.sp, color: Color(0xFF00BFA5)),
                      SizedBox(width: 8.w),
                      Text('Add New Designation', style: TextStyle(color: Color(0xFF00BFA5), fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
              onChanged: (v) {
                if (v == '__add_new__') {
                  _showAddDesignationDialog();
                  return;
                }
                final match = _designationsList.firstWhere(
                  (d) => d['desname'] == v,
                  orElse: () => {},
                );
                setState(() {
                  _selectedDesignation = v;
                  _selectedDesId = match['des_id'] as int?;
                });
              },
              validator: (v) => v == null || v == '__add_new__' ? 'Required' : null,
            ),
            SizedBox(height: 16.h),

            // Designation Report To
            Text('Designation Report To',
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            SizedBox(height: 6.h),
            DropdownButtonFormField<int>(
              value: _selectedReportTo,
              isExpanded: true,
              decoration: _inputDecoration('Select reporting person'),
              style: _inputStyle,
              items: [
                const DropdownMenuItem(value: 0, child: Text('None')),
                ..._users.map((u) => DropdownMenuItem(
                      value: u.useId,
                      child: Text('${u.usename} (${u.desname})'),
                    )),
              ],
              onChanged: (v) => setState(() => _selectedReportTo = v),
            ),
            SizedBox(height: 16.h),

            // Role
            Text('Role *',
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            SizedBox(height: 6.h),
            DropdownButtonFormField<String>(
              value: _selectedRole,
              isExpanded: true,
              decoration: _inputDecoration('Select role'),
              style: _inputStyle,
              items: _rolesList
                  .where((r) => (r['urname'] as String) != 'Admin')
                  .map((r) => DropdownMenuItem(
                      value: r['urname'] as String,
                      child: Text(r['urname'] as String)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedRole = v),
              validator: (v) => v == null ? 'Required' : null,
            ),
            SizedBox(height: 16.h),

            // User Name
            Text('User Name *',
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            SizedBox(height: 6.h),
            TextFormField(
              controller: _nameController,
              decoration: _inputDecoration('Enter user name'),
              style: _inputStyle,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            SizedBox(height: 16.h),

            // Email
            Text('Email *',
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            SizedBox(height: 6.h),
            TextFormField(
              controller: _emailController,
              decoration: _inputDecoration('Enter email'),
              style: _inputStyle,
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            SizedBox(height: 16.h),

            // Phone
            Text('Phone *',
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            SizedBox(height: 6.h),
            TextFormField(
              controller: _phoneController,
              decoration: _inputDecoration('Enter phone number'),
              style: _inputStyle,
              keyboardType: TextInputType.phone,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            SizedBox(height: 16.h),

            // Password
            Text('Password *',
                style: TextStyle(
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w800,
                    color: Colors.black)),
            SizedBox(height: 6.h),
            TextFormField(
              controller: _passwordController,
              decoration: _inputDecoration('Enter password'),
              style: _inputStyle,
              obscureText: true,
              validator: (v) =>
                  v == null || v.trim().isEmpty ? 'Required' : null,
            ),
            SizedBox(height: 24.h),

            // Buttons
            Builder(builder: (context) {
              final compact = MediaQuery.of(context).size.width <= 1366;
              final btnPadding = EdgeInsets.symmetric(horizontal: compact ? 20.w : 28.w, vertical: 20.h);
              return Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _clearForm,
                    style: OutlinedButton.styleFrom(
                      padding: btnPadding,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r)),
                    ),
                    child: const Text('Clear'),
                  ),
                ),
                SizedBox(width: 12.w),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _createUser,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: btnPadding,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10.r)),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 20.w,
                            height: 20.h,
                            child: const CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Create User',
                            style: TextStyle(fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            );
            }),
          ],
        ),
      ),
    );
  }

  static final TextStyle _inputStyle = TextStyle(fontWeight: FontWeight.w500, fontSize: 13.sp, color: Color(0xFF555555));

  InputDecoration _inputDecoration(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13.sp),
      contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8.r),
        borderSide: const BorderSide(color: AppColors.accent),
      ),
      filled: true,
      fillColor: Colors.white,
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
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
            child: Row(
              children: [
                Icon(Icons.group_rounded, size: 18.sp, color: AppColors.accent),
                SizedBox(width: 8.w),
                Text('Existing Users', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text('${_users.length} users', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
                ),
                SizedBox(width: 8.w),
                TextButton.icon(
                  onPressed: _fetchUsers,
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
          const Divider(height: 1),
          // Simplified table header
          Container(
            padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
            color: const Color(0xFF6C8EEF),
            child: Row(
              children: [
                SizedBox(width: 50.w, child: Text('S NO.', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                SizedBox(width: 16.w),
                Expanded(flex: 3, child: Text('NAME', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                Expanded(flex: 2, child: Text('DESIGNATION', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                Expanded(flex: 2, child: Text('ROLE', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                SizedBox(width: 70.w, child: Text('STATUS', textAlign: TextAlign.center, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white))),
                SizedBox(width: 30.w),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            Padding(padding: EdgeInsets.all(32.w), child: Center(child: CircularProgressIndicator()))
          else if (_users.isEmpty)
            Padding(padding: EdgeInsets.all(32.w), child: Center(child: Text('No users found', style: TextStyle(color: AppColors.textSecondary))))
          else
            ...List.generate(_users.length, (i) {
              final u = _users[i];
              return InkWell(
                onTap: () => setState(() => _selectedUser = u),
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                  color: i.isEven ? Colors.white : AppColors.surface,
                  child: Row(
                    children: [
                      SizedBox(width: 50.w, child: Text('${i + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                      SizedBox(width: 16.w),
                      Expanded(
                        flex: 3,
                        child: Text(u.usename, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
                      ),
                      Expanded(flex: 2, child: Text(u.desname, style: TextStyle(fontSize: 13.sp))),
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Container(
                              padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                              decoration: BoxDecoration(
                                color: u.urname.toLowerCase() == 'admin' ? AppColors.accent.withValues(alpha: 0.1) : Colors.grey.shade100,
                                borderRadius: BorderRadius.circular(6.r),
                              ),
                              child: Text(u.urname, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: u.urname.toLowerCase() == 'admin' ? AppColors.accent : AppColors.textSecondary)),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 70.w,
                        child: Center(
                          child: Container(
                            padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                            decoration: BoxDecoration(
                              color: u.isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6.r),
                            ),
                            child: Text(u.isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: u.isActive ? AppColors.success : AppColors.error)),
                          ),
                        ),
                      ),
                      SizedBox(width: 30.w, child: Icon(Icons.chevron_right_rounded, size: 18.sp, color: AppColors.textSecondary)),
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
        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 20.w),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16.sp, color: AppColors.accent),
              SizedBox(width: 10.w),
            ],
            SizedBox(
              width: 130.w,
              child: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            ),
            Expanded(
              child: Text(value, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: valueColor ?? AppColors.textPrimary)),
            ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header with back button
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back_rounded, size: 20.sp),
                  onPressed: () => setState(() => _selectedUser = null),
                  tooltip: 'Back to list',
                ),
                SizedBox(width: 4.w),
                Icon(Icons.person_rounded, size: 18.sp, color: AppColors.accent),
                SizedBox(width: 8.w),
                Text('User Details', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
                const Spacer(),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
                  decoration: BoxDecoration(
                    color: u.isActive ? AppColors.success.withValues(alpha: 0.1) : AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: Text(u.isActive ? 'Active' : 'Inactive', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: u.isActive ? AppColors.success : AppColors.error)),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // User avatar + name header
          Padding(
            padding: EdgeInsets.all(20.w),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28.r,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                  child: Text(
                    u.usename.isNotEmpty ? u.usename[0].toUpperCase() : '?',
                    style: TextStyle(fontSize: 22.sp, fontWeight: FontWeight.w700, color: AppColors.accent),
                  ),
                ),
                SizedBox(width: 16.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.usename, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2.h),
                    Text('${u.desname} - ${u.urname}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          // Detail rows
          SizedBox(height: 8.h),
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
          SizedBox(height: 16.h),
          // Terminate button
          if (u.isActive && u.urname.toLowerCase() != 'admin')
            Padding(
              padding: EdgeInsets.fromLTRB(20.w, 0, 20.w, 20.h),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _confirmTerminate(u),
                  icon: Icon(Icons.block_rounded, size: 18.sp),
                  label: const Text('Terminate', style: TextStyle(fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.error,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        title: const Text('Terminate User', style: TextStyle(fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Are you sure you want to terminate "${u.usename}"? This will deactivate their account.'),
            SizedBox(height: 16.h),
            TextField(
              controller: reasonController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: 'Reason for termination *',
                hintText: 'Enter reason...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
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
              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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
