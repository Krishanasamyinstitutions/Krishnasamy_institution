import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class StaffDesignationScreen extends StatefulWidget {
  const StaffDesignationScreen({super.key});

  @override
  State<StaffDesignationScreen> createState() => _StaffDesignationScreenState();
}

class _StaffDesignationScreenState extends State<StaffDesignationScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _designations = [];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  int? _selectedReportTo;


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

    final success = await SupabaseService.createDesignation({
      'ins_id': insId,
      'desname': _nameController.text.trim(),
      'desrepto': _selectedReportTo,
      'activestatus': 1,
    });

    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Designation created'), backgroundColor: AppColors.success),
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
    return Padding(
      padding: const EdgeInsets.all(20),
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
                          'Add Designation',
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
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
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
                children: [
                  // Header
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
                        Text('${_designations.length} records', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        const SizedBox(width: 12),
                        TextButton.icon(
                          onPressed: _fetchDesignations,
                          icon: const Icon(Icons.refresh_rounded, size: 16),
                          label: const Text('Refresh'),
                          style: TextButton.styleFrom(
                            foregroundColor: AppColors.textSecondary,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Table header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    color: const Color(0xFF6C8EEF),
                    child: const Row(
                      children: [
                        SizedBox(width: 40, child: Text('S NO.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('DESIGNATION NAME', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                        Expanded(flex: 3, child: Text('REPORTS TO', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                        SizedBox(width: 80, child: Text('ACTIONS', textAlign: TextAlign.center, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                      ],
                    ),
                  ),
                  // Data rows
                  if (_isLoading)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_designations.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('No designations found', style: TextStyle(color: AppColors.textSecondary))),
                    )
                  else
                    ..._designations.asMap().entries.map((entry) {
                      final idx = entry.key;
                      final des = entry.value;
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        decoration: BoxDecoration(
                          color: idx.isEven ? Colors.white : AppColors.surface,
                          border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                        ),
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
                                  InkWell(
                                    onTap: () => _deleteDesignation(des['des_id'] as int),
                                    borderRadius: BorderRadius.circular(6),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.delete_rounded, size: 16, color: Colors.red),
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
