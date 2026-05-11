import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

import '../../widgets/app_icon.dart';

/// Bank account master for the active institution. Each row represents a
/// beneficiary account a fee group can route to (school's main account,
/// transport vendor, hostel, etc.). The screen lists existing accounts on
/// the left and shows an add/edit form on the right.
class BankDetailsScreen extends StatefulWidget {
  const BankDetailsScreen({super.key});

  @override
  State<BankDetailsScreen> createState() => _BankDetailsScreenState();
}

class _BankDetailsScreenState extends State<BankDetailsScreen> {
  bool _isLoading = false;
  bool _isSaving = false;
  List<Map<String, dynamic>> _banks = [];
  List<Map<String, dynamic>> _feeGroups = [];
  bool _loadingFeeGroups = false;

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _branchController = TextEditingController();
  final _ifscController = TextEditingController();
  final _addr1Controller = TextEditingController();
  final _addr2Controller = TextEditingController();
  final _addr3Controller = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _accNoController = TextEditingController();
  final _accHolderController = TextEditingController();

  int? _editingBanId;

  @override
  void initState() {
    super.initState();
    _fetchBanks();
    _fetchFeeGroups();
  }

  Future<void> _fetchFeeGroups() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _loadingFeeGroups = true);
    final groups = await SupabaseService.getFeeGroups(insId);
    if (!mounted) return;
    setState(() {
      _feeGroups = groups;
      _loadingFeeGroups = false;
    });
  }

  Future<void> _assignBank(int fgId, int? banId) async {
    final ok = await SupabaseService.setFeeGroupBank(fgId, banId);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bank account assigned'), backgroundColor: AppColors.success),
      );
      _fetchFeeGroups();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to assign bank account'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _branchController.dispose();
    _ifscController.dispose();
    _addr1Controller.dispose();
    _addr2Controller.dispose();
    _addr3Controller.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _accNoController.dispose();
    _accHolderController.dispose();
    super.dispose();
  }

  Future<void> _fetchBanks() async {
    setState(() => _isLoading = true);
    final data = await SupabaseService.getBanks();
    if (mounted) {
      setState(() {
        _banks = data;
        _isLoading = false;
      });
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _nameController.clear();
    _branchController.clear();
    _ifscController.clear();
    _addr1Controller.clear();
    _addr2Controller.clear();
    _addr3Controller.clear();
    _mobileController.clear();
    _emailController.clear();
    _accNoController.clear();
    _accHolderController.clear();
    setState(() => _editingBanId = null);
  }

  void _loadIntoForm(Map<String, dynamic> b) {
    _nameController.text = b['banname']?.toString() ?? '';
    _branchController.text = b['banbranch']?.toString() ?? '';
    _ifscController.text = b['ifsccode']?.toString() ?? '';
    _addr1Controller.text = b['banaddress1']?.toString() ?? '';
    _addr2Controller.text = b['banaddress2']?.toString() ?? '';
    _addr3Controller.text = b['banaddress3']?.toString() ?? '';
    _mobileController.text = b['banmobile']?.toString() ?? '';
    _emailController.text = b['banemail']?.toString() ?? '';
    _accNoController.text = b['banaccno']?.toString() ?? '';
    _accHolderController.text = b['banaccholder']?.toString() ?? '';
    setState(() => _editingBanId = b['ban_id'] as int?);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);

    final data = <String, dynamic>{
      'banname': _nameController.text.trim(),
      'banbranch': _branchController.text.trim(),
      'ifsccode': _ifscController.text.trim().toUpperCase(),
      'banaddress1': _addr1Controller.text.trim(),
      'banaddress2': _addr2Controller.text.trim().isEmpty ? null : _addr2Controller.text.trim(),
      'banaddress3': _addr3Controller.text.trim().isEmpty ? null : _addr3Controller.text.trim(),
      'banmobile': _mobileController.text.trim().isEmpty ? null : _mobileController.text.trim(),
      'banemail': _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
      'banaccno': _accNoController.text.trim(),
      'banaccholder': _accHolderController.text.trim(),
      'activestatus': 1,
    };

    bool ok;
    if (_editingBanId != null) {
      ok = await SupabaseService.updateBank(_editingBanId!, data);
    } else {
      ok = (await SupabaseService.addBank(data)) != null;
    }

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_editingBanId != null ? 'Bank account updated' : 'Bank account added'),
          backgroundColor: AppColors.success,
        ),
      );
      _resetForm();
      _fetchBanks();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to save bank account'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _confirmDelete(Map<String, dynamic> b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete bank account?'),
        content: Text('Remove "${b['banname']}" (${b['banaccno']})? Existing fee groups and payments referencing it stay intact but the account stops appearing in dropdowns.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final banId = b['ban_id'] as int?;
    if (banId == null) return;
    if (await SupabaseService.deleteBank(banId)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bank account removed'), backgroundColor: AppColors.success),
      );
      if (_editingBanId == banId) _resetForm();
      _fetchBanks();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.of(context).size.width < 900;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Padding(
        padding: EdgeInsets.all(isMobile ? 16 : 24.w),
        child: isMobile
            ? Column(
                children: [
                  _buildList(),
                  const SizedBox(height: 16),
                  Expanded(child: _buildForm()),
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(flex: 3, child: _buildList()),
                  SizedBox(width: 16.w),
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildForm(),
                        SizedBox(height: 16.h),
                        Expanded(child: _buildAssignmentsPanel()),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildList() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppIcon('bank', size: 18, color: AppColors.accent),
              SizedBox(width: 8.w),
              Text('Bank Accounts',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const Spacer(),
              Text('${_banks.length}',
                  style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary)),
            ],
          ),
          SizedBox(height: 12.h),
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_banks.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No bank accounts yet. Add one on the right.',
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _banks.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (_, i) {
                  final b = _banks[i];
                  final selected = b['ban_id'] == _editingBanId;
                  return InkWell(
                    onTap: () => _loadIntoForm(b),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: selected ? AppColors.accent.withValues(alpha: 0.08) : null,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: selected ? AppColors.accent.withValues(alpha: 0.4) : AppColors.border),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(b['banname'] ?? '',
                                    style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                SizedBox(height: 2.h),
                                Text('${b['banbranch'] ?? ''} • ${b['ifsccode'] ?? ''}',
                                    style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                                SizedBox(height: 2.h),
                                Text('A/c ${b['banaccno']} — ${b['banaccholder']}',
                                    style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary)),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Edit',
                            onPressed: () => _loadIntoForm(b),
                            icon: const AppIcon('edit-2', size: 16, color: AppColors.textSecondary),
                          ),
                          IconButton(
                            tooltip: 'Delete',
                            onPressed: () => _confirmDelete(b),
                            icon: const AppIcon('trash', size: 16, color: Colors.red),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildForm() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  AppIcon(_editingBanId != null ? 'edit-2' : 'add', size: 18, color: AppColors.accent),
                  SizedBox(width: 8.w),
                  Text(_editingBanId != null ? 'Edit Bank Account' : 'Add Bank Account',
                      style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                  const Spacer(),
                  if (_editingBanId != null)
                    TextButton.icon(
                      onPressed: _resetForm,
                      icon: const AppIcon('add', size: 14, color: AppColors.textSecondary),
                      label: const Text('New'),
                    ),
                ],
              ),
              SizedBox(height: 12.h),
              _row([
                _field('Bank Name *', _nameController, hint: 'HDFC Bank', required: true),
                _field('Branch *', _branchController, hint: 'Cuddalore Main', required: true),
              ]),
              SizedBox(height: 10.h),
              _row([
                _field('IFSC Code *', _ifscController, hint: 'HDFC0001234', required: true),
                _field('Account Holder *', _accHolderController, hint: 'KCET College', required: true),
              ]),
              SizedBox(height: 10.h),
              _row([
                _field('Account Number *', _accNoController, hint: '1234567890', required: true),
                _field('Mobile', _mobileController, hint: '+91…'),
              ]),
              SizedBox(height: 10.h),
              _row([
                _field('Email', _emailController, hint: 'finance@school.in'),
                _field('Address Line 1 *', _addr1Controller, required: true),
              ]),
              SizedBox(height: 10.h),
              _row([
                _field('Address Line 2', _addr2Controller),
                _field('Address Line 3', _addr3Controller),
              ]),
              SizedBox(height: 18.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _resetForm,
                      icon: const AppIcon('close-circle', size: 16),
                      label: const Text('Clear'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isSaving ? null : _save,
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                          : AppIcon(_editingBanId != null ? 'tick-circle' : 'add', size: 16, color: Colors.white),
                      label: Text(_editingBanId != null ? 'Update' : 'Add'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAssignmentsPanel() {
    return Container(
      padding: EdgeInsets.all(16.w),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const AppIcon('category-2', size: 18, color: AppColors.accent),
              SizedBox(width: 8.w),
              Text('Fee Group Assignments',
                  style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              const Spacer(),
              Text(
                'Route each fee group to a bank',
                style: TextStyle(fontSize: 11.sp, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
              ),
            ],
          ),
          SizedBox(height: 12.h),
          if (_loadingFeeGroups)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator()))
          else if (_feeGroups.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No fee groups yet. Import fee groups in Master Data first.',
                    style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
              ),
            )
          else
            Expanded(
              child: ListView.separated(
                itemCount: _feeGroups.length,
                separatorBuilder: (_, __) => const Divider(height: 12),
                itemBuilder: (_, i) {
                  final fg = _feeGroups[i];
                  final fgId = fg['fg_id'] as int?;
                  final currentBanId = fg['ban_id'] as int?;
                  return Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(fg['fgdesc']?.toString() ?? '',
                                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700)),
                            if (fg['yrlabel'] != null)
                              Text(fg['yrlabel'].toString(),
                                  style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary)),
                          ],
                        ),
                      ),
                      SizedBox(width: 12.w),
                      Expanded(
                        flex: 4,
                        child: DropdownButtonFormField<int?>(
                          value: currentBanId,
                          isExpanded: true,
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                          hint: const Text('— No account —'),
                          items: [
                            const DropdownMenuItem<int?>(value: null, child: Text('— No account —')),
                            for (final b in _banks)
                              DropdownMenuItem<int?>(
                                value: b['ban_id'] as int?,
                                child: Text(
                                  '${b['banname']} • ${b['banaccno']}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: fgId == null ? null : (v) => _assignBank(fgId, v),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(List<Widget> children) {
    return Row(
      children: [
        for (int i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(width: 12.w),
          Expanded(child: children[i]),
        ],
      ],
    );
  }

  Widget _field(String label, TextEditingController c, {String? hint, bool required = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
        SizedBox(height: 4.h),
        TextFormField(
          controller: c,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 10.h),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          ),
          style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
          validator: required ? (v) => (v == null || v.trim().isEmpty) ? 'Required' : null : null,
        ),
      ],
    );
  }
}
