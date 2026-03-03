import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions;
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class StudentsScreen extends StatefulWidget {
  const StudentsScreen({super.key});

  @override
  State<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends State<StudentsScreen> {
  final _formKey = GlobalKey<FormState>();

  // Student Info
  String? _selectedYrId;
  String? _selectedYrLabel;
  List<Map<String, dynamic>> _years = [];
  final _admNoController = TextEditingController();
  final _nameController = TextEditingController();
  String? _selectedGender;
  DateTime? _dob;
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _addressController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController();
  final _pinController = TextEditingController();
  String? _selectedBloodGroup;
  String? _selectedClass;
  List<String> _classes = [];
  String? _selectedConId;
  String? _selectedConDesc;
  List<Map<String, dynamic>> _concessions = [];
  String? _photoUrl;

  // Parent Info
  String _selectedParentTab = 'Father';
  final _fatherNameController = TextEditingController();
  final _fatherMobileController = TextEditingController();
  final _fatherOccController = TextEditingController();
  final _motherNameController = TextEditingController();
  final _motherMobileController = TextEditingController();
  final _motherOccController = TextEditingController();
  final _guardianNameController = TextEditingController();
  final _guardianMobileController = TextEditingController();
  final _guardianOccController = TextEditingController();

  // Payment in charge
  final _payNameController = TextEditingController();
  final _payMobileController = TextEditingController();

  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  final List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  final List<String> _genders = ['Male', 'Female', 'Other'];
  static const List<String> _classOrder = [
    'PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
  ];

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _admNoController.dispose();
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _addressController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _pinController.dispose();
    _fatherNameController.dispose();
    _fatherMobileController.dispose();
    _fatherOccController.dispose();
    _motherNameController.dispose();
    _motherMobileController.dispose();
    _motherOccController.dispose();
    _guardianNameController.dispose();
    _guardianMobileController.dispose();
    _guardianOccController.dispose();
    _payNameController.dispose();
    _payMobileController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;

    final years = await SupabaseService.getYears(insId);
    final concessions = await SupabaseService.getConcessions(insId);
    final rawClasses = await SupabaseService.getClasses(insId);
    final ordered = _classOrder.where((c) => rawClasses.contains(c)).toList();
    final extra = rawClasses.where((c) => !_classOrder.contains(c)).toList();

    if (!mounted) return;
    setState(() {
      _years = years;
      _concessions = concessions;
      _classes = [...ordered, ...extra];
      if (years.isNotEmpty) {
        _selectedYrId = years.first['yr_id'].toString();
        _selectedYrLabel = years.first['yrlabel'];
      }
    });
  }

  void _clearForm() {
    _formKey.currentState?.reset();
    _admNoController.clear();
    _nameController.clear();
    _mobileController.clear();
    _emailController.clear();
    _addressController.clear();
    _cityController.clear();
    _stateController.clear();
    _countryController.clear();
    _pinController.clear();
    _fatherNameController.clear();
    _fatherMobileController.clear();
    _fatherOccController.clear();
    _motherNameController.clear();
    _motherMobileController.clear();
    _motherOccController.clear();
    _guardianNameController.clear();
    _guardianMobileController.clear();
    _guardianOccController.clear();
    _payNameController.clear();
    _payMobileController.clear();
    setState(() {
      _selectedGender = null;
      _selectedBloodGroup = null;
      _selectedClass = null;
      _selectedConId = null;
      _selectedConDesc = null;
      _dob = null;
      _photoUrl = null;
      _selectedParentTab = 'Father';
      if (_years.isNotEmpty) {
        _selectedYrId = _years.first['yr_id'].toString();
        _selectedYrLabel = _years.first['yrlabel'];
      }
    });
  }

  String _genderCode(String? g) {
    if (g == 'Male') return 'M';
    if (g == 'Female') return 'F';
    return 'O';
  }

  Future<void> _saveStudent() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;
    final inscode = auth.inscode ?? '';
    final yrId = int.tryParse(_selectedYrId ?? '1') ?? 1;
    final yrLabel = _selectedYrLabel ?? '';
    final admNo = _admNoController.text.trim();
    final stuName = _nameController.text.trim();
    final stuClass = _selectedClass ?? '';
    final now = DateTime.now().toIso8601String();

    setState(() => _isSaving = true);
    try {
      // 1. Insert into students table
      final stuId = await SupabaseService.addStudent({
        'ins_id': insId,
        'inscode': inscode,
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'stuadmno': admNo,
        'stuadmdate': now.split('T').first,
        'stuname': stuName,
        'stugender': _genderCode(_selectedGender),
        'studob': _dob?.toIso8601String().split('T').first,
        'stumobile': _mobileController.text.trim(),
        'stuemail': _n(_emailController),
        'stuaddress': _n(_addressController),
        'stucity': _n(_cityController),
        'stustate': _n(_stateController),
        'stucountry': _n(_countryController),
        'stupin': _n(_pinController),
        'stubloodgrp': _selectedBloodGroup,
        'stuphoto': _photoUrl,
        'stuclass': stuClass,
        'con_id': _selectedConId != null ? int.tryParse(_selectedConId!) : null,
        'stucondesc': _selectedConDesc,
        'stuser_id': admNo,           // login ID = admission number
        'stuotpstatus': 0,
        'approvedby': '',
        'approveddate': now,
        'suspendedby': '',
        'terminatedby': '',
        'activestatus': 1,
        'createdon': now,
      });

      // 2. Insert into parents table
      final parId = await SupabaseService.saveParent({
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'partype': 'P',
        'fathername': _n(_fatherNameController),
        'fathermobile': _n(_fatherMobileController),
        'fatheroccupation': _n(_fatherOccController),
        'mothername': _n(_motherNameController),
        'mothermobile': _n(_motherMobileController),
        'motheroccupation': _n(_motherOccController),
        'guardianname': _n(_guardianNameController),
        'guardianmobile': _n(_guardianMobileController),
        'guardianoccupation': _n(_guardianOccController),
        'payincharge': _n(_payNameController),
        'payinchargemob': _n(_payMobileController),
        'parotpstatus': 0,
        'approveddate': now,
        'activestatus': 1,
      });

      // 3. Insert into parentdetail table linking student ↔ parent
      await SupabaseService.saveParentDetail({
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'par_id': parId,
        'stu_id': stuId,
        'ins_id': insId,
        'inscode': inscode,
        'stuadmno': admNo,
        'stuname': stuName,
        'stuclass': stuClass,
        'activestatus': 1,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student saved successfully'), backgroundColor: AppColors.accent),
        );
        _clearForm();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving student: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _uploadPhoto() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final ext = (file.extension ?? 'jpg').toLowerCase();
      const mimeMap = {
        'jpg': 'image/jpeg',
        'jpeg': 'image/jpeg',
        'png': 'image/png',
        'webp': 'image/webp',
        'gif': 'image/gif',
      };
      final mimeType = mimeMap[ext] ?? 'image/jpeg';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      await SupabaseService.client.storage
          .from('student-photos')
          .uploadBinary(
            fileName,
            file.bytes!,
            fileOptions: FileOptions(contentType: mimeType),
          );
      final url = SupabaseService.client.storage
          .from('student-photos')
          .getPublicUrl(fileName);
      if (mounted) setState(() => _photoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  String? _n(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top action bar
          Row(
            children: [
              const Spacer(),
              OutlinedButton(
                onPressed: _clearForm,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _isSaving ? null : _saveStudent,
                icon: _isSaving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_rounded, size: 18),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: _showExcelUploadDialog,
                icon: const Icon(Icons.upload_file_rounded, size: 18),
                label: const Text('Excel Upload'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.info,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Scrollable form body
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildStudentInfoSection(),
                  const SizedBox(height: 20),
                  _buildParentInfoSection(),
                  const SizedBox(height: 20),
                  _buildPaymentInChargeSection(),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Student Info ─────────────────────────────────────────────────────────────

  Widget _buildStudentInfoSection() {
    return _section(
      title: 'Student Information',
      icon: Icons.person_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Photo
          Center(
            child: Column(
              children: [
                CircleAvatar(
                  radius: 44,
                  backgroundColor: AppColors.accent.withValues(alpha: 0.1),
                  backgroundImage: _photoUrl != null ? NetworkImage(_photoUrl!) : null,
                  child: _photoUrl == null
                      ? const Icon(Icons.person_rounded, size: 44, color: AppColors.accent)
                      : null,
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: _isUploadingPhoto ? null : _uploadPhoto,
                  icon: _isUploadingPhoto
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.camera_alt_rounded, size: 16),
                  label: Text(_isUploadingPhoto ? 'Uploading...' : 'Upload Photo'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [
              _field(label: 'Academic Year *', child: DropdownButtonFormField<String>(
                value: _selectedYrId,
                decoration: _dec('Select year'),
                items: _years.map((y) => DropdownMenuItem(value: y['yr_id'].toString(), child: Text(y['yrlabel']))).toList(),
                onChanged: (v) => setState(() {
                  _selectedYrId = v;
                  _selectedYrLabel = _years.firstWhere((y) => y['yr_id'].toString() == v)['yrlabel'];
                }),
                validator: (v) => v == null ? 'Required' : null,
              )),
              _field(label: 'Admission Number *', child: TextFormField(
                controller: _admNoController,
                decoration: _dec('Enter admission no'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              )),
              _field(label: 'Student Name *', width: 320, child: TextFormField(
                controller: _nameController,
                decoration: _dec('Enter full name'),
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              )),
              _field(label: 'Gender *', child: DropdownButtonFormField<String>(
                value: _selectedGender,
                decoration: _dec('Select gender'),
                items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => _selectedGender = v),
                validator: (v) => v == null ? 'Required' : null,
              )),
              _field(label: 'Date of Birth *', child: InkWell(
                onTap: () async {
                  final d = await showDatePicker(
                    context: context,
                    initialDate: _dob ?? DateTime(2015),
                    firstDate: DateTime(1990),
                    lastDate: DateTime.now(),
                  );
                  if (d != null) setState(() => _dob = d);
                },
                child: InputDecorator(
                  decoration: _dec('Select DOB'),
                  child: Text(
                    _dob != null
                        ? '${_dob!.day.toString().padLeft(2, '0')}/${_dob!.month.toString().padLeft(2, '0')}/${_dob!.year}'
                        : 'DD/MM/YYYY',
                    style: TextStyle(color: _dob != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
                  ),
                ),
              )),
              _field(label: 'Mobile Number *', child: TextFormField(
                controller: _mobileController,
                decoration: _dec('Enter mobile'),
                keyboardType: TextInputType.phone,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
              )),
              _field(label: 'Email', child: TextFormField(
                controller: _emailController,
                decoration: _dec('Enter email'),
                keyboardType: TextInputType.emailAddress,
              )),
              _field(label: 'Class *', child: DropdownButtonFormField<String>(
                value: _selectedClass,
                decoration: _dec('Select class'),
                items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                onChanged: (v) => setState(() => _selectedClass = v),
                validator: (v) => v == null ? 'Required' : null,
              )),
              _field(label: 'Blood Group', child: DropdownButtonFormField<String>(
                value: _selectedBloodGroup,
                decoration: _dec('Select'),
                items: _bloodGroups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
                onChanged: (v) => setState(() => _selectedBloodGroup = v),
              )),
              _field(label: 'Concession', width: 280, child: DropdownButtonFormField<String>(
                value: _selectedConId,
                decoration: _dec('Select concession'),
                items: _concessions.map((c) => DropdownMenuItem(
                  value: c['con_id'].toString(),
                  child: Text(c['condesc'], overflow: TextOverflow.ellipsis),
                )).toList(),
                onChanged: (v) => setState(() {
                  _selectedConId = v;
                  _selectedConDesc = _concessions.firstWhere((c) => c['con_id'].toString() == v)['condesc'];
                }),
              )),
              _field(label: 'Address', width: 500, child: TextFormField(
                controller: _addressController,
                decoration: _dec('Enter address'),
                maxLines: 2,
              )),
              _field(label: 'City', child: TextFormField(controller: _cityController, decoration: _dec('Enter city'))),
              _field(label: 'State', child: TextFormField(controller: _stateController, decoration: _dec('Enter state'))),
              _field(label: 'Country', child: TextFormField(controller: _countryController, decoration: _dec('Enter country'))),
              _field(label: 'Pin Code', child: TextFormField(
                controller: _pinController,
                decoration: _dec('Enter pin'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              )),
            ],
          ),
        ],
      ),
    );
  }

  // ─── Parent Info ──────────────────────────────────────────────────────────────

  Widget _buildParentInfoSection() {
    return _section(
      title: 'Parent / Guardian Information',
      icon: Icons.family_restroom_rounded,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: ['Father', 'Mother', 'Guardian'].map((tab) {
              final selected = _selectedParentTab == tab;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(tab),
                  selected: selected,
                  onSelected: (_) => setState(() => _selectedParentTab = tab),
                  selectedColor: AppColors.accent,
                  labelStyle: TextStyle(color: selected ? Colors.white : AppColors.textPrimary, fontWeight: FontWeight.w600),
                  backgroundColor: AppColors.border.withValues(alpha: 0.3),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: _selectedParentTab == 'Father'
                ? _parentFields(_fatherNameController, _fatherMobileController, _fatherOccController, 'Father')
                : _selectedParentTab == 'Mother'
                    ? _parentFields(_motherNameController, _motherMobileController, _motherOccController, 'Mother')
                    : _parentFields(_guardianNameController, _guardianMobileController, _guardianOccController, 'Guardian'),
          ),
        ],
      ),
    );
  }

  List<Widget> _parentFields(TextEditingController nameC, TextEditingController mobC, TextEditingController occC, String prefix) => [
    _field(label: '$prefix Name', width: 280, child: TextFormField(controller: nameC, decoration: _dec('Enter $prefix name'))),
    _field(label: '$prefix Mobile', child: TextFormField(controller: mobC, decoration: _dec('Enter mobile'), keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
    _field(label: '$prefix Occupation', child: TextFormField(controller: occC, decoration: _dec('Enter occupation'))),
  ];

  // ─── Payment in Charge ────────────────────────────────────────────────────────

  Widget _buildPaymentInChargeSection() {
    return _section(
      title: 'Payment In Charge',
      icon: Icons.payments_rounded,
      child: Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          _field(label: 'Name', width: 280, child: TextFormField(controller: _payNameController, decoration: _dec('Enter name'))),
          _field(label: 'Mobile Number', child: TextFormField(controller: _payMobileController, decoration: _dec('Enter mobile'), keyboardType: TextInputType.phone, inputFormatters: [FilteringTextInputFormatter.digitsOnly])),
        ],
      ),
    );
  }

  // ─── Excel Upload Dialog ──────────────────────────────────────────────────────

  void _showExcelUploadDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [Icon(Icons.upload_file_rounded, color: AppColors.info), SizedBox(width: 8), Text('Excel Upload (.csv)')]),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Upload a CSV file with student data.'),
            const SizedBox(height: 12),
            Text('Required columns:\nAdm No, Name, Gender, DOB, Mobile, Class', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx),
            icon: const Icon(Icons.upload_file_rounded, size: 18),
            label: const Text('Choose File'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.info, foregroundColor: Colors.white),
          ),
        ],
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  Widget _section({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: AppColors.accent, size: 20),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          ]),
          const SizedBox(height: 4),
          Divider(color: AppColors.border),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _field({required String label, required Widget child, double width = 220}) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
    filled: true,
    fillColor: Colors.white,
  );
}
