import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class FeesScreen extends StatefulWidget {
  const FeesScreen({super.key});

  @override
  State<FeesScreen> createState() => _FeesScreenState();
}

class _FeesScreenState extends State<FeesScreen> {
  // Fee Group form
  final _fgFormKey = GlobalKey<FormState>();
  final _fgDescController = TextEditingController();
  final _fgBanIdController = TextEditingController();
  String? _fgSelectedYrId;
  String? _fgSelectedYrLabel;
  bool _isSavingGroup = false;
  List<Map<String, dynamic>> _feeGroups = [];

  // Fee Master form
  final _feeFormKey = GlobalKey<FormState>();
  final _feeDescController = TextEditingController();
  final _feeShortController = TextEditingController();
  String? _feeSelectedYrId;
  String? _feeSelectedYrLabel;
  String? _selectedFgId;
  int _feeOptional = 0;
  int _feeCategory = 0;
  bool _isSavingFee = false;

  // Shared
  List<Map<String, dynamic>> _years = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _fgDescController.dispose();
    _fgBanIdController.dispose();
    _feeDescController.dispose();
    _feeShortController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final insId = context.read<AuthProvider>().insId ?? 1;
    final years = await SupabaseService.getYears(insId);
    final feeGroups = await SupabaseService.getFeeGroups(insId);
    if (!mounted) return;
    setState(() {
      _years = years;
      _feeGroups = feeGroups;
      if (years.isNotEmpty) {
        _fgSelectedYrId = years.first['yr_id'].toString();
        _fgSelectedYrLabel = years.first['yrlabel'];
        _feeSelectedYrId = years.first['yr_id'].toString();
        _feeSelectedYrLabel = years.first['yrlabel'];
      }
    });
  }

  Future<void> _saveFeeGroup() async {
    if (!_fgFormKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    setState(() => _isSavingGroup = true);
    try {
      await SupabaseService.addFeeGroup({
        'ins_id': auth.insId ?? 1,
        'yr_id': int.tryParse(_fgSelectedYrId ?? '1') ?? 1,
        'yrlabel': _fgSelectedYrLabel ?? '',
        'fgdesc': _fgDescController.text.trim(),
        'ban_id': int.tryParse(_fgBanIdController.text.trim()) ?? 1,
        'activestatus': 1,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fee group saved'), backgroundColor: AppColors.accent),
        );
        _fgDescController.clear();
        _fgBanIdController.clear();
        _fgFormKey.currentState?.reset();
        final feeGroups = await SupabaseService.getFeeGroups(auth.insId ?? 1);
        setState(() => _feeGroups = feeGroups);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingGroup = false);
    }
  }

  Future<void> _saveFeeMaster() async {
    if (!_feeFormKey.currentState!.validate()) return;
    setState(() => _isSavingFee = true);
    try {
      await SupabaseService.addFeeMaster({
        'yr_id': int.tryParse(_feeSelectedYrId ?? '1') ?? 1,
        'yrlabel': _feeSelectedYrLabel ?? '',
        'feedesc': _feeDescController.text.trim(),
        'feeshort': _feeShortController.text.trim(),
        'fg_id': int.tryParse(_selectedFgId ?? '1') ?? 1,
        'feeoptional': _feeOptional,
        'feecategory': _feeCategory,
        'activestatus': 1,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Fee saved'), backgroundColor: AppColors.accent),
        );
        _feeDescController.clear();
        _feeShortController.clear();
        _feeFormKey.currentState?.reset();
        setState(() {
          _selectedFgId = null;
          _feeOptional = 0;
          _feeCategory = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSavingFee = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Fee Management', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 16),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // LEFT — Fee Groups
              Expanded(child: _buildFeeGroupPanel()),
              const SizedBox(width: 16),
              // RIGHT — Fee Master
              Expanded(child: _buildFeeMasterPanel()),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Fee Group Panel ──────────────────────────────────────────────────────

  Widget _buildFeeGroupPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('Fee Groups', Icons.category_rounded),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Form
                  Form(
                    key: _fgFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Academic Year *'),
                        DropdownButtonFormField<String>(
                          initialValue: _fgSelectedYrId,
                          isExpanded: true,
                          decoration: _dec('Select year'),
                          items: _years.map((y) => DropdownMenuItem(
                            value: y['yr_id'].toString(),
                            child: Text(y['yrlabel']),
                          )).toList(),
                          onChanged: (v) => setState(() {
                            _fgSelectedYrId = v;
                            _fgSelectedYrLabel = _years.firstWhere((y) => y['yr_id'].toString() == v)['yrlabel'];
                          }),
                          validator: (v) => v == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        _fieldLabel('Fee Group Description *'),
                        TextFormField(
                          controller: _fgDescController,
                          decoration: _dec('e.g. SCHOOL FEES'),
                          textCapitalization: TextCapitalization.characters,
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        _fieldLabel('Bank ID *'),
                        TextFormField(
                          controller: _fgBanIdController,
                          decoration: _dec('Enter bank ID'),
                          keyboardType: TextInputType.number,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSavingGroup ? null : _saveFeeGroup,
                            icon: _isSavingGroup
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Save Fee Group'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Fee Master Panel ─────────────────────────────────────────────────────

  Widget _buildFeeMasterPanel() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _panelHeader('Fee Type', Icons.receipt_long_rounded),
          const Divider(height: 1, color: AppColors.border),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Form
                  Form(
                    key: _feeFormKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _fieldLabel('Academic Year *'),
                        DropdownButtonFormField<String>(
                          initialValue: _feeSelectedYrId,
                          isExpanded: true,
                          decoration: _dec('Select year'),
                          items: _years.map((y) => DropdownMenuItem(
                            value: y['yr_id'].toString(),
                            child: Text(y['yrlabel']),
                          )).toList(),
                          onChanged: (v) => setState(() {
                            _feeSelectedYrId = v;
                            _feeSelectedYrLabel = _years.firstWhere((y) => y['yr_id'].toString() == v)['yrlabel'];
                          }),
                          validator: (v) => v == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        _fieldLabel('Fee Group *'),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedFgId,
                          isExpanded: true,
                          decoration: _dec('Select fee group'),
                          items: _feeGroups.map((fg) => DropdownMenuItem(
                            value: fg['fg_id'].toString(),
                            child: Text(fg['fgdesc'] ?? '', overflow: TextOverflow.ellipsis),
                          )).toList(),
                          onChanged: (v) => setState(() => _selectedFgId = v),
                          validator: (v) => v == null ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        _fieldLabel('Fee Description *'),
                        TextFormField(
                          controller: _feeDescController,
                          decoration: _dec('e.g. SCHOOL FEES'),
                          textCapitalization: TextCapitalization.characters,
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        _fieldLabel('Short Name *'),
                        TextFormField(
                          controller: _feeShortController,
                          decoration: _dec('e.g. SCH FEES'),
                          textCapitalization: TextCapitalization.characters,
                          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel('Optional'),
                                  DropdownButtonFormField<int>(
                                    initialValue: _feeOptional,
                                    isExpanded: true,
                                    decoration: _dec(''),
                                    items: const [
                                      DropdownMenuItem(value: 0, child: Text('No')),
                                      DropdownMenuItem(value: 1, child: Text('Yes')),
                                    ],
                                    onChanged: (v) => setState(() => _feeOptional = v ?? 0),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _fieldLabel('Category'),
                                  DropdownButtonFormField<int>(
                                    initialValue: _feeCategory,
                                    isExpanded: true,
                                    decoration: _dec(''),
                                    items: const [
                                      DropdownMenuItem(value: 0, child: Text('Regular')),
                                      DropdownMenuItem(value: 1, child: Text('Optional')),
                                    ],
                                    onChanged: (v) => setState(() => _feeCategory = v ?? 0),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _isSavingFee ? null : _saveFeeMaster,
                            icon: _isSavingFee
                                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Icon(Icons.save_rounded, size: 18),
                            label: const Text('Save Fee'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ─────────────────────────────────────────────────────────────

  Widget _panelHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Row(children: [
        Icon(icon, color: AppColors.accent, size: 20),
        const SizedBox(width: 8),
        Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
      ]),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
    );
  }


  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
    filled: true,
    fillColor: Colors.white,
  );
}
