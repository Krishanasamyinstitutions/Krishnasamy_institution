import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import 'package:excel/excel.dart' as xl;
import 'package:supabase_flutter/supabase_flutter.dart' show FileOptions, PostgrestException;
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/student_model.dart';

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
  DateTime? _admDate;
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
  String? _insName;
  String? _insLogo;

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
  bool _isFormEnabled = true;
  List<StudentModel> _students = [];

  static const TextStyle _inputStyle = TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: AppColors.textPrimary);

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
    final insInfo = await SupabaseService.getInstitutionInfo(insId);
    final students = await SupabaseService.getStudents(insId);
    final ordered = _classOrder.where((c) => rawClasses.contains(c)).toList();
    final extra = rawClasses.where((c) => !_classOrder.contains(c)).toList();

    if (!mounted) return;
    setState(() {
      _years = years;
      _concessions = concessions;
      _classes = [...ordered, ...extra];
      _insName = insInfo.name;
      _insLogo = insInfo.logo;
      _students = students;
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
      _admDate = null;
      _dob = null;
      _photoUrl = null;
      _selectedParentTab = 'Father';
      _isFormEnabled = false;
      if (_years.isNotEmpty) {
        _selectedYrId = _years.first['yr_id'].toString();
        _selectedYrLabel = _years.first['yrlabel'];
      }
    });
  }

  void _showSelectStudentDialog() {
    final searchController = TextEditingController();
    List<StudentModel> filtered = List.from(_students);

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(builder: (ctx, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            child: SizedBox(
              width: 560,
              height: 520,
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 16, 16, 12),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(14)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.person_search_rounded, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                        const Expanded(child: Text('Select Student', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                        IconButton(
                          onPressed: () => Navigator.pop(ctx),
                          icon: const Icon(Icons.close_rounded, color: Colors.white, size: 20),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  // Search
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: TextField(
                      controller: searchController,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search by name, admission no, or class...',
                        prefixIcon: const Icon(Icons.search_rounded, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        isDense: true,
                      ),
                      onChanged: (q) {
                        final lower = q.toLowerCase();
                        setDialogState(() {
                          filtered = _students.where((s) =>
                            s.stuname.toLowerCase().contains(lower) ||
                            s.stuadmno.toLowerCase().contains(lower) ||
                            s.stuclass.toLowerCase().contains(lower),
                          ).toList();
                        });
                      },
                    ),
                  ),
                  // List
                  Expanded(
                    child: filtered.isEmpty
                        ? const Center(child: Text('No students found', style: TextStyle(color: AppColors.textSecondary)))
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final s = filtered[i];
                              return ListTile(
                                dense: true,
                                leading: CircleAvatar(
                                  radius: 18,
                                  backgroundColor: AppColors.accent.withValues(alpha: 0.15),
                                  child: Text(s.stuname[0].toUpperCase(), style: const TextStyle(color: AppColors.accent, fontWeight: FontWeight.w700)),
                                ),
                                title: Text(s.stuname, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                                subtitle: Text('${s.stuadmno} · ${s.stuclass}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _populateStudentForm(s); // async — fire and forget
                                },
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        });
      },
    );
  }

  String? _normalizeBloodGroup(String? raw) {
    if (raw == null) return null;
    // Map DB variants like "B+VE", "B-VE", "O+VE" → canonical dropdown values
    const map = {
      'A+VE': 'A+', 'A-VE': 'A-',
      'B+VE': 'B+', 'B-VE': 'B-',
      'AB+VE': 'AB+', 'AB-VE': 'AB-',
      'O+VE': 'O+', 'O-VE': 'O-',
    };
    final upper = raw.trim().toUpperCase();
    final normalized = map[upper] ?? raw.trim();
    return _bloodGroups.contains(normalized) ? normalized : null;
  }

  Future<void> _populateStudentForm(StudentModel s) async {
    // Clear any previously typed/shown data before populating
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
      _admDate = null;
      _dob = null;
      _photoUrl = null;
      _selectedParentTab = 'Father';
      if (_years.isNotEmpty) {
        _selectedYrId = _years.first['yr_id'].toString();
        _selectedYrLabel = _years.first['yrlabel'];
      }
    });

    _admNoController.text = s.stuadmno;
    _nameController.text = s.stuname;
    _mobileController.text = s.stumobile;
    _emailController.text = s.stuemail ?? '';
    _addressController.text = s.stuaddress ?? '';
    _cityController.text = s.stucity ?? '';
    _stateController.text = s.stustate ?? '';
    _countryController.text = s.stucountry ?? '';
    _pinController.text = s.stupin ?? '';

    // Fetch parent data
    final parent = await SupabaseService.getStudentParent(s.stuId);
    if (!mounted) return;

    _fatherNameController.text = parent?['fathername'] ?? '';
    _fatherMobileController.text = parent?['fathermobile'] ?? '';
    _fatherOccController.text = parent?['fatheroccupation'] ?? '';
    _motherNameController.text = parent?['mothername'] ?? '';
    _motherMobileController.text = parent?['mothermobile'] ?? '';
    _motherOccController.text = parent?['motheroccupation'] ?? '';
    _guardianNameController.text = parent?['guardianname'] ?? '';
    _guardianMobileController.text = parent?['guardianmobile'] ?? '';
    _guardianOccController.text = parent?['guardianoccupation'] ?? '';
    _payNameController.text = parent?['payincharge'] ?? '';
    _payMobileController.text = parent?['payinchargemob'] ?? '';

    setState(() {
      _selectedGender = s.gender;
      _selectedBloodGroup = _normalizeBloodGroup(s.stubloodgrp);
      _selectedClass = s.stuclass;
      _admDate = s.stuadmdate;
      _dob = s.studob;
      _photoUrl = s.stuphoto;
      _isFormEnabled = false; // view mode — buttons disabled
    });
  }

  Widget _avatarPlaceholder() {
    final name = _nameController.text.trim();
    if (name.isEmpty) return const Icon(Icons.person_rounded, size: 36, color: AppColors.accent);
    return Center(
      child: Text(
        name[0].toUpperCase(),
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: AppColors.accent),
      ),
    );
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
      final stuId = await SupabaseService.addStudent({
        'ins_id': insId,
        'inscode': inscode,
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'stuadmno': admNo,
        'stuadmdate': (_admDate ?? DateTime.now()).toIso8601String().split('T').first,
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
        'stuser_id': admNo,
        'stuotpstatus': 0,
        'approvedby': '',
        'approveddate': now,
        'suspendedby': '',
        'terminatedby': '',
        'activestatus': 1,
        'createdon': now,
      });

      // Reuse existing parent record if same father/mother mobile already exists
      // (prevents duplicate parent rows when a parent has multiple children)
      final existingParId = await SupabaseService.findParentByMobile(
        fatherMobile: _n(_fatherMobileController),
        motherMobile: _n(_motherMobileController),
        payMobile: _n(_payMobileController),
      );

      final parId = existingParId ?? await SupabaseService.saveParent({
        'ins_id': insId,
        'inscode': inscode,
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
    } on PostgrestException catch (e) {
      if (mounted) {
        final msg = e.code == '23505'
            ? 'Admission number already exists for this institution. Please use a different admission number.'
            : 'Database error: ${e.message}';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red),
        );
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
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final ext = (file.extension ?? 'jpg').toLowerCase();
      const mimeMap = {
        'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
        'png': 'image/png', 'webp': 'image/webp', 'gif': 'image/gif',
      };
      final mimeType = mimeMap[ext] ?? 'image/jpeg';
      final fileName = '${DateTime.now().millisecondsSinceEpoch}.$ext';
      await SupabaseService.client.storage.from('student-photos').uploadBinary(
        fileName, file.bytes!, fileOptions: FileOptions(contentType: mimeType),
      );
      final url = SupabaseService.client.storage.from('student-photos').getPublicUrl(fileName);
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

  // ─── Build ────────────────────────────────────────────────────────────────────

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
              // New button
              ElevatedButton.icon(
                onPressed: () {
                  _clearForm();
                  setState(() => _isFormEnabled = true);
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('New'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const SizedBox(width: 10),
              // Select Student button
              ElevatedButton.icon(
                onPressed: _showSelectStudentDialog,
                icon: const Icon(Icons.person_search_rounded, size: 18),
                label: const Text('Select Student'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.warning,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
              const Spacer(),
              // Cancel — only active when form enabled
              OutlinedButton(
                onPressed: _isFormEnabled ? _clearForm : null,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel'),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                onPressed: (_isFormEnabled && !_isSaving) ? _saveStudent : null,
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
                icon: const Icon(Icons.file_download_rounded, size: 20),
                label: const Text('Import from Excel'),
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

          // ── Split layout: LEFT = Student | RIGHT = Parent + Payment ──
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT — Student Information (fills full height, inner scroll)
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
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              // Left: title + school name
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Row(children: [
                                      Icon(Icons.person_rounded, color: AppColors.accent, size: 20),
                                      SizedBox(width: 8),
                                      Text('Student Information',
                                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                                    ]),
                                    const SizedBox(height: 4),
                                    Row(children: [
                                      if (_insLogo != null)
                                        Image.network(
                                          _insLogo!,
                                          width: 32,
                                          height: 32,
                                          fit: BoxFit.contain,
                                          errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: AppColors.accent, size: 28),
                                        )
                                      else
                                        const Icon(Icons.school_rounded, color: AppColors.accent, size: 28),
                                      const SizedBox(width: 8),
                                      Flexible(
                                        child: Text(
                                          _insName ?? context.read<AuthProvider>().inscode ?? '',
                                          style: const TextStyle(fontSize: 20, color: AppColors.textPrimary, fontWeight: FontWeight.w800),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ]),
                                  ],
                                ),
                              ),
                              // Right: profile photo + upload
                              Column(
                                children: [
                                  Container(
                                    width: 72,
                                    height: 72,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: AppColors.accent.withValues(alpha: 0.1),
                                    ),
                                    child: ClipOval(
                                      child: _photoUrl != null
                                          ? Image.network(
                                              _photoUrl!,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => _avatarPlaceholder(),
                                            )
                                          : _avatarPlaceholder(),
                                    ),
                                  ),
                                  TextButton.icon(
                                    onPressed: (_isFormEnabled && !_isUploadingPhoto) ? _uploadPhoto : null,
                                    icon: _isUploadingPhoto
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                        : const Icon(Icons.camera_alt_rounded, size: 14),
                                    label: Text(_isUploadingPhoto ? 'Uploading...' : 'Upload Photo',
                                        style: const TextStyle(fontSize: 11)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 20),
                          child: Divider(color: AppColors.border),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
                            child: IgnorePointer(
                              ignoring: !_isFormEnabled,
                              child: Opacity(
                                opacity: _isFormEnabled ? 1.0 : 0.65,
                                child: _buildStudentFields(),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 16),

                // RIGHT — Parent + Payment
                Expanded(
                  child: SingleChildScrollView(
                    child: Opacity(
                      opacity: _isFormEnabled ? 1.0 : 0.65,
                      child: Column(
                        children: [
                        _panel(
                          title: 'Parent / Guardian Information',
                          icon: Icons.family_restroom_rounded,
                          child: _buildParentFields(),
                        ),
                        const SizedBox(height: 16),
                        _panel(
                          title: 'Payment In Charge',
                          icon: Icons.payments_rounded,
                          child: _buildPaymentFields(),
                        ),
                        const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Left panel: Student fields ───────────────────────────────────────────────

  Widget _buildStudentFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _row2(
          _fieldFull(label: 'Academic Year *', child: DropdownButtonFormField<String>(
            initialValue: _selectedYrId,
            decoration: _dec('Select year'),
            style: _inputStyle,
            items: _years.map((y) => DropdownMenuItem(value: y['yr_id'].toString(), child: Text(y['yrlabel']))).toList(),
            onChanged: (v) => setState(() {
              _selectedYrId = v;
              _selectedYrLabel = v != null
                  ? _years.firstWhere((y) => y['yr_id'].toString() == v)['yrlabel']
                  : null;
            }),
            validator: (v) => v == null ? 'Required' : null,
          )),
          _fieldFull(label: 'Admission Number *', child: TextFormField(
            controller: _admNoController,
            decoration: _dec('Enter admission no'),
            style: _inputStyle,
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          )),
        ),
        const SizedBox(height: 14),

        _fieldFull(
          label: 'Admission Date *',
          child: InkWell(
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: _admDate ?? DateTime.now(),
                firstDate: DateTime(2000),
                lastDate: DateTime.now(),
              );
              if (d != null) setState(() => _admDate = d);
            },
            child: InputDecorator(
              decoration: _dec('Select admission date').copyWith(
                suffixIcon: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.textSecondary),
              ),
              child: Text(
                _admDate != null
                    ? '${_admDate!.day.toString().padLeft(2, '0')}/${_admDate!.month.toString().padLeft(2, '0')}/${_admDate!.year}'
                    : 'Select admission date',
                style: TextStyle(
                  color: _admDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: _admDate != null ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),

        _row2(
          _fieldFull(label: 'Student Name *', child: TextFormField(
            controller: _nameController,
            decoration: _dec('Enter full name'),
            style: _inputStyle,
            validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
          )),
          _fieldFull(label: 'Gender *', child: DropdownButtonFormField<String>(
            initialValue: _selectedGender,
            decoration: _dec('Select gender'),
            style: _inputStyle,
            items: _genders.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
            onChanged: (v) => setState(() => _selectedGender = v),
            validator: (v) => v == null ? 'Required' : null,
          )),
        ),
        const SizedBox(height: 14),

        _row2(
          _fieldFull(label: 'Date of Birth *', child: InkWell(
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
                style: TextStyle(
                  color: _dob != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6),
                  fontSize: 13,
                  fontWeight: _dob != null ? FontWeight.w700 : FontWeight.normal,
                ),
              ),
            ),
          )),
          _fieldFull(label: 'Mobile Number', child: TextFormField(
            controller: _mobileController,
            decoration: _dec('Enter mobile'),
            style: _inputStyle,
            keyboardType: TextInputType.phone,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          )),
        ),
        const SizedBox(height: 14),

        _row2(
          _fieldFull(label: 'Email', child: TextFormField(
            controller: _emailController,
            decoration: _dec('Enter email'),
            style: _inputStyle,
            keyboardType: TextInputType.emailAddress,
          )),
          _fieldFull(label: 'Class *', child: DropdownButtonFormField<String>(
            initialValue: _selectedClass,
            decoration: _dec('Select class'),
            style: _inputStyle,
            items: _classes.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (v) => setState(() => _selectedClass = v),
            validator: (v) => v == null ? 'Required' : null,
          )),
        ),
        const SizedBox(height: 14),

        _row2(
          _fieldFull(label: 'Blood Group', child: DropdownButtonFormField<String>(
            initialValue: _selectedBloodGroup,
            isExpanded: true,
            decoration: _dec('Select'),
            style: _inputStyle,
            items: _bloodGroups.map((g) => DropdownMenuItem(value: g, child: Text(g))).toList(),
            onChanged: (v) => setState(() => _selectedBloodGroup = v),
          )),
          _fieldFull(label: 'Concession', child: DropdownButtonFormField<String>(
            initialValue: _selectedConId,
            isExpanded: true,
            decoration: _dec('Select concession'),
            style: _inputStyle,
            items: _concessions.map((c) => DropdownMenuItem(
              value: c['con_id'].toString(),
              child: Text(c['condesc'], overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (v) => setState(() {
              _selectedConId = v;
              _selectedConDesc = v != null
                  ? _concessions.firstWhere((c) => c['con_id'].toString() == v)['condesc']
                  : null;
            }),
          )),
        ),
        const SizedBox(height: 14),

        _fieldFull(label: 'Address *', child: TextFormField(
          controller: _addressController,
          decoration: _dec('Enter address'),
          style: _inputStyle,
          maxLines: 2,
          validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
        )),
        const SizedBox(height: 14),

        _row2(
          _fieldFull(label: 'City', child: TextFormField(controller: _cityController, decoration: _dec('Enter city'), style: _inputStyle)),
          _fieldFull(label: 'State', child: TextFormField(controller: _stateController, decoration: _dec('Enter state'), style: _inputStyle)),
        ),
        const SizedBox(height: 14),

        _row2(
          _fieldFull(label: 'Country', child: TextFormField(controller: _countryController, decoration: _dec('Enter country'), style: _inputStyle)),
          _fieldFull(label: 'Pin Code *', child: TextFormField(
            controller: _pinController,
            decoration: _dec('Enter pin'),
            style: _inputStyle,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
          )),
        ),
      ],
    );
  }

  // ─── Right panel: Parent fields ───────────────────────────────────────────────

  Widget _buildParentFields() {
    final controllers = _selectedParentTab == 'Father'
        ? (_fatherNameController, _fatherMobileController, _fatherOccController)
        : _selectedParentTab == 'Mother'
            ? (_motherNameController, _motherMobileController, _motherOccController)
            : (_guardianNameController, _guardianMobileController, _guardianOccController);
    final prefix = _selectedParentTab;

    return Column(
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

        IgnorePointer(
          ignoring: !_isFormEnabled,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _fieldFull(label: '$prefix Name', child: TextFormField(
                controller: controllers.$1,
                decoration: _dec('Enter $prefix name'),
                style: _inputStyle,
              )),
              const SizedBox(height: 14),
              _row2(
                _fieldFull(label: '$prefix Mobile', child: TextFormField(
                  controller: controllers.$2,
                  decoration: _dec('Enter mobile'),
                  style: _inputStyle,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                )),
                _fieldFull(label: '$prefix Occupation', child: TextFormField(
                  controller: controllers.$3,
                  decoration: _dec('Enter occupation'),
                  style: _inputStyle,
                )),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Right panel: Payment fields ──────────────────────────────────────────────

  Widget _buildPaymentFields() {
    return IgnorePointer(
      ignoring: !_isFormEnabled,
      child: _row2(
      _fieldFull(label: 'Name *', child: TextFormField(
        controller: _payNameController,
        decoration: _dec('Enter name'),
        style: _inputStyle,
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      )),
      _fieldFull(label: 'Mobile Number *', child: TextFormField(
        controller: _payMobileController,
        decoration: _dec('Enter mobile'),
        style: _inputStyle,
        keyboardType: TextInputType.phone,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
      )),
    ));
  }

  // ─── Excel Import ─────────────────────────────────────────────────────────────

  /// Known student fields for column mapping
  static const _importFields = <String, String>{
    '': '-- Skip --',
    'stuadmno': 'Adm No',
    'stuname': 'Name',
    'stugender': 'Gender',
    'studob': 'DOB',
    'stumobile': 'Mobile',
    'stuclass': 'Class',
    'stuemail': 'Email',
    'stuaddress': 'Address',
    'stucity': 'City',
    'stustate': 'State',
    'stucountry': 'Country',
    'stupin': 'PIN',
    'stubloodgrp': 'Blood Group',
    'stuadmdate': 'Admission Date',
    'fathername': 'Father Name',
    'fathermobile': 'Father Mobile',
    'fatheroccupation': 'Father Occupation',
    'mothername': 'Mother Name',
    'mothermobile': 'Mother Mobile',
    'motheroccupation': 'Mother Occupation',
    'guardianname': 'Guardian Name',
    'guardianmobile': 'Guardian Mobile',
    'guardianoccupation': 'Guardian Occupation',
    'payincharge': 'Payment In Charge',
    'payinchargemob': 'Payment Mobile',
  };

  /// Auto-map header text to field key (case-insensitive)
  static String _autoMapHeader(String header) {
    final h = header.trim().toLowerCase();
    const map = {
      'adm no': 'stuadmno', 'admission number': 'stuadmno', 'admno': 'stuadmno', 'admission no': 'stuadmno',
      'name': 'stuname', 'student name': 'stuname', 'stuname': 'stuname',
      'gender': 'stugender', 'sex': 'stugender',
      'dob': 'studob', 'date of birth': 'studob', 'birth date': 'studob',
      'mobile': 'stumobile', 'phone': 'stumobile', 'mobile no': 'stumobile', 'phone no': 'stumobile',
      'class': 'stuclass', 'grade': 'stuclass',
      'email': 'stuemail', 'e-mail': 'stuemail',
      'address': 'stuaddress',
      'city': 'stucity', 'town': 'stucity',
      'state': 'stustate',
      'country': 'stucountry',
      'pin': 'stupin', 'pincode': 'stupin', 'pin code': 'stupin', 'zip': 'stupin', 'zip code': 'stupin',
      'blood group': 'stubloodgrp', 'bloodgroup': 'stubloodgrp',
      'admission date': 'stuadmdate', 'adm date': 'stuadmdate',
      'father name': 'fathername', 'fathername': 'fathername',
      'father mobile': 'fathermobile', 'fathermobile': 'fathermobile', 'father phone': 'fathermobile',
      'father occupation': 'fatheroccupation', 'fatheroccupation': 'fatheroccupation',
      'mother name': 'mothername', 'mothername': 'mothername',
      'mother mobile': 'mothermobile', 'mothermobile': 'mothermobile', 'mother phone': 'mothermobile',
      'mother occupation': 'motheroccupation', 'motheroccupation': 'motheroccupation',
      'guardian name': 'guardianname', 'guardianname': 'guardianname',
      'guardian mobile': 'guardianmobile', 'guardianmobile': 'guardianmobile', 'guardian phone': 'guardianmobile',
      'guardian occupation': 'guardianoccupation', 'guardianoccupation': 'guardianoccupation',
      'payment in charge': 'payincharge', 'payincharge': 'payincharge', 'pay name': 'payincharge',
      'payment mobile': 'payinchargemob', 'payinchargemob': 'payinchargemob', 'pay mobile': 'payinchargemob',
    };
    return map[h] ?? '';
  }

  /// Parse a date string in common formats
  static DateTime? _parseDate(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    final t = s.trim();
    // yyyy-MM-dd
    try { return DateTime.parse(t); } catch (_) {}
    // dd/MM/yyyy or dd-MM-yyyy
    final parts = t.split(RegExp(r'[/\-.]'));
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        final year = y < 100 ? (y + 2000) : y;
        if (m >= 1 && m <= 12 && d >= 1 && d <= 31) {
          return DateTime(year, m, d);
        }
      }
    }
    return null;
  }

  /// Normalize gender input to M/F/O
  static String _normalizeGender(String? g) {
    if (g == null) return 'M';
    final v = g.trim().toUpperCase();
    if (v == 'M' || v == 'MALE') return 'M';
    if (v == 'F' || v == 'FEMALE') return 'F';
    return 'O';
  }

  void _showExcelUploadDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ExcelImportDialog(
        years: _years,
        selectedYrId: _selectedYrId,
        selectedYrLabel: _selectedYrLabel,
        onImportDone: () {
          // Refresh student list after import
          _loadDropdowns();
        },
      ),
    );
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────────

  /// Card panel with a labelled header
  Widget _panel({required String title, required IconData icon, required Widget child}) {
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
          const Divider(color: AppColors.border),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  /// Two fields side by side
  Widget _row2(Widget left, Widget right) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }

  /// Field with label that expands to fill available width
  Widget _fieldFull({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }

  InputDecoration _dec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent)),
    filled: true,
    fillColor: Colors.white,
  );
}

// ═══════════════════════════════════════════════════════════════════════════════
// Excel / CSV Import Dialog
// ═══════════════════════════════════════════════════════════════════════════════

class _ExcelImportDialog extends StatefulWidget {
  final List<Map<String, dynamic>> years;
  final String? selectedYrId;
  final String? selectedYrLabel;
  final VoidCallback onImportDone;

  const _ExcelImportDialog({
    required this.years,
    required this.selectedYrId,
    required this.selectedYrLabel,
    required this.onImportDone,
  });

  @override
  State<_ExcelImportDialog> createState() => _ExcelImportDialogState();
}

class _ExcelImportDialogState extends State<_ExcelImportDialog> {
  // 0 = pick file, 1 = preview & map, 2 = importing, 3 = done
  int _step = 0;
  String? _fileName;
  List<String> _headers = [];
  List<List<dynamic>> _rows = [];
  // column index → field key ('' = skip)
  List<String> _mappings = [];
  // import progress
  int _imported = 0;
  int _skipped = 0;
  int _total = 0;
  String? _errorMsg;
  List<String> _importErrors = [];

  // Required field keys
  static const _requiredFields = {'stuadmno', 'stuname', 'stugender', 'studob', 'stumobile', 'stuclass'};

  // ─── File Picking & Parsing ───────────────────────────────────────────────

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv', 'xlsx', 'xls'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    if (file.bytes == null) return;

    final ext = (file.extension ?? '').toLowerCase();
    try {
      List<String> headers;
      List<List<dynamic>> rows;

      if (ext == 'csv') {
        final csvString = utf8.decode(file.bytes!);
        final parsed = const CsvToListConverter().convert(csvString);
        if (parsed.isEmpty) throw Exception('CSV file is empty');
        headers = parsed.first.map((e) => e.toString().trim()).toList();
        rows = parsed.skip(1).where((r) => r.any((c) => c.toString().trim().isNotEmpty)).toList();
      } else {
        final excel = xl.Excel.decodeBytes(file.bytes!);
        final sheetName = excel.tables.keys.first;
        final sheet = excel.tables[sheetName]!;
        if (sheet.rows.isEmpty) throw Exception('Excel file is empty');
        headers = sheet.rows.first.map((c) => c?.value?.toString().trim() ?? '').toList();
        rows = sheet.rows.skip(1)
            .where((r) => r.any((c) => c?.value != null && c!.value.toString().trim().isNotEmpty))
            .map((r) => r.map((c) => c?.value ?? '').toList())
            .toList();
      }

      // Auto-map columns
      final mappings = headers.map((h) => _StudentsScreenState._autoMapHeader(h)).toList();

      setState(() {
        _fileName = file.name;
        _headers = headers;
        _rows = rows;
        _mappings = mappings;
        _step = 1;
        _errorMsg = null;
      });
    } catch (e) {
      setState(() => _errorMsg = 'Failed to parse file: $e');
    }
  }

  // ─── Validation ───────────────────────────────────────────────────────────

  /// Check if a row has all required fields mapped and non-empty
  String? _validateRow(int rowIdx) {
    final row = _rows[rowIdx];
    final missing = <String>[];
    for (final reqKey in _requiredFields) {
      final colIdx = _mappings.indexOf(reqKey);
      if (colIdx < 0 || colIdx >= row.length || row[colIdx].toString().trim().isEmpty) {
        missing.add(_StudentsScreenState._importFields[reqKey] ?? reqKey);
      }
    }
    if (missing.isEmpty) return null;
    return 'Missing: ${missing.join(', ')}';
  }

  /// Get cell value by field key for a row
  String? _cellByKey(List<dynamic> row, String fieldKey) {
    final idx = _mappings.indexOf(fieldKey);
    if (idx < 0 || idx >= row.length) return null;
    final v = row[idx].toString().trim();
    return v.isEmpty ? null : v;
  }

  // ─── Bulk Import ──────────────────────────────────────────────────────────

  Future<void> _startImport() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;
    final inscode = auth.inscode ?? '';
    final yrId = int.tryParse(widget.selectedYrId ?? '1') ?? 1;
    final yrLabel = widget.selectedYrLabel ?? '';
    final now = DateTime.now().toIso8601String();

    setState(() {
      _step = 2;
      _imported = 0;
      _skipped = 0;
      _total = _rows.length;
      _importErrors = [];
    });

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final err = _validateRow(i);
      if (err != null) {
        setState(() {
          _skipped++;
          _importErrors.add('Row ${i + 1}: $err');
        });
        continue;
      }

      try {
        final admNo = _cellByKey(row, 'stuadmno')!;
        final stuName = _cellByKey(row, 'stuname')!;
        final stuClass = _cellByKey(row, 'stuclass')!;
        final dob = _StudentsScreenState._parseDate(_cellByKey(row, 'studob'));
        final admDate = _StudentsScreenState._parseDate(_cellByKey(row, 'stuadmdate'));

        // 1. Insert student
        final stuId = await SupabaseService.addStudent({
          'ins_id': insId,
          'inscode': inscode,
          'yr_id': yrId,
          'yrlabel': yrLabel,
          'stuadmno': admNo,
          'stuadmdate': (admDate ?? DateTime.now()).toIso8601String().split('T').first,
          'stuname': stuName,
          'stugender': _StudentsScreenState._normalizeGender(_cellByKey(row, 'stugender')),
          'studob': dob?.toIso8601String().split('T').first,
          'stumobile': _cellByKey(row, 'stumobile')!,
          'stuemail': _cellByKey(row, 'stuemail'),
          'stuaddress': _cellByKey(row, 'stuaddress'),
          'stucity': _cellByKey(row, 'stucity'),
          'stustate': _cellByKey(row, 'stustate'),
          'stucountry': _cellByKey(row, 'stucountry'),
          'stupin': _cellByKey(row, 'stupin'),
          'stubloodgrp': _cellByKey(row, 'stubloodgrp'),
          'stuclass': stuClass,
          'stuser_id': admNo,
          'stuotpstatus': 0,
          'approvedby': '',
          'approveddate': now,
          'suspendedby': '',
          'terminatedby': '',
          'activestatus': 1,
          'createdon': now,
        });

        // 2. Insert or reuse parent record
        final fatherMob = _cellByKey(row, 'fathermobile');
        final motherMob = _cellByKey(row, 'mothermobile');
        final payMob = _cellByKey(row, 'payinchargemob');

        final existingParId = await SupabaseService.findParentByMobile(
          fatherMobile: fatherMob,
          motherMobile: motherMob,
          payMobile: payMob,
        );

        final parId = existingParId ?? await SupabaseService.saveParent({
          'ins_id': insId,
          'inscode': inscode,
          'yr_id': yrId,
          'yrlabel': yrLabel,
          'partype': 'P',
          'fathername': _cellByKey(row, 'fathername'),
          'fathermobile': fatherMob,
          'fatheroccupation': _cellByKey(row, 'fatheroccupation'),
          'mothername': _cellByKey(row, 'mothername'),
          'mothermobile': motherMob,
          'motheroccupation': _cellByKey(row, 'motheroccupation'),
          'guardianname': _cellByKey(row, 'guardianname'),
          'guardianmobile': _cellByKey(row, 'guardianmobile'),
          'guardianoccupation': _cellByKey(row, 'guardianoccupation'),
          'payincharge': _cellByKey(row, 'payincharge'),
          'payinchargemob': payMob,
          'parotpstatus': 0,
          'approveddate': now,
          'activestatus': 1,
        });

        // 3. Link parent to student
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

        setState(() => _imported++);
      } on PostgrestException catch (e) {
        final msg = e.code == '23505'
            ? 'Duplicate Adm No'
            : 'DB: ${e.message}';
        setState(() {
          _skipped++;
          _importErrors.add('Row ${i + 1}: $msg');
        });
      } catch (e) {
        setState(() {
          _skipped++;
          _importErrors.add('Row ${i + 1}: $e');
        });
      }
    }

    setState(() => _step = 3);
    widget.onImportDone();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.all(40),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 900,
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            const Divider(height: 1),
            Flexible(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final titles = ['Select File', 'Preview & Map Columns', 'Importing...', 'Import Complete'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        children: [
          const Icon(Icons.table_chart_rounded, color: AppColors.info, size: 24),
          const SizedBox(width: 10),
          Text(titles[_step], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
          const Spacer(),
          if (_step != 2)
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case 0: return _buildFilePickStep();
      case 1: return _buildPreviewStep();
      case 2: return _buildImportingStep();
      case 3: return _buildDoneStep();
      default: return const SizedBox();
    }
  }

  // ─── Step 0: File Pick ────────────────────────────────────────────────────

  Widget _buildFilePickStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(32),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.info.withValues(alpha: 0.3), width: 2),
              borderRadius: BorderRadius.circular(12),
              color: AppColors.info.withValues(alpha: 0.03),
            ),
            child: Column(
              children: [
                Icon(Icons.upload_file_rounded, size: 48, color: AppColors.info.withValues(alpha: 0.7)),
                const SizedBox(height: 12),
                const Text('Select a CSV or Excel file', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
                const SizedBox(height: 6),
                const Text('Supported formats: .csv, .xlsx', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Choose File'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.info,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  ),
                ),
              ],
            ),
          ),
          if (_errorMsg != null) ...[
            const SizedBox(height: 12),
            Text(_errorMsg!, style: const TextStyle(color: Colors.red, fontSize: 13)),
          ],
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Required columns:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Adm No, Name, Gender, DOB, Mobile, Class',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                SizedBox(height: 8),
                Text('Optional columns:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                SizedBox(height: 4),
                Text('Email, Address, City, State, Country, PIN, Blood Group, Admission Date',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 1: Preview & Map ────────────────────────────────────────────────

  Widget _buildPreviewStep() {
    // Count valid rows
    int validCount = 0;
    for (int i = 0; i < _rows.length; i++) {
      if (_validateRow(i) == null) validCount++;
    }
    final allRequiredMapped = _requiredFields.every((f) => _mappings.contains(f));

    return Column(
      children: [
        // File info bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
          color: AppColors.info.withValues(alpha: 0.05),
          child: Row(
            children: [
              const Icon(Icons.description_rounded, size: 16, color: AppColors.info),
              const SizedBox(width: 8),
              Text(_fileName ?? '', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(width: 16),
              Text('${_rows.length} rows found', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: validCount == _rows.length ? AppColors.accent.withValues(alpha: 0.1) : Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$validCount valid',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                      color: validCount == _rows.length ? AppColors.accent : Colors.orange[800]),
                ),
              ),
              if (_rows.length - validCount > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_rows.length - validCount} invalid',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.red[700]),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Column mapping row
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Column Mapping', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              const Text('Map each file column to a student field. Required fields are marked with *.',
                  style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
              const SizedBox(height: 8),
              if (!allRequiredMapped)
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded, size: 16, color: Colors.red[700]),
                      const SizedBox(width: 6),
                      Text(
                        'Not all required fields are mapped. Required: ${_requiredFields.map((f) => _StudentsScreenState._importFields[f]).join(', ')}',
                        style: TextStyle(fontSize: 11, color: Colors.red[700]),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        // Data table
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SingleChildScrollView(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 72,
                  dataRowMinHeight: 36,
                  dataRowMaxHeight: 36,
                  columnSpacing: 16,
                  horizontalMargin: 8,
                  headingRowColor: WidgetStateProperty.all(AppColors.info.withValues(alpha: 0.04)),
                  columns: [
                    const DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                    const DataColumn(label: Text('Status', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11))),
                    for (int c = 0; c < _headers.length; c++)
                      DataColumn(
                        label: SizedBox(
                          width: 130,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(_headers[c], style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 11),
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              SizedBox(
                                height: 28,
                                child: DropdownButtonFormField<String>(
                                  initialValue: _mappings[c],
                                  isDense: true,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 6),
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(color: _requiredFields.contains(_mappings[c]) ? AppColors.accent : AppColors.border)),
                                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(4),
                                        borderSide: BorderSide(color: _mappings[c].isNotEmpty ? AppColors.accent : AppColors.border)),
                                  ),
                                  style: const TextStyle(fontSize: 10, color: AppColors.textPrimary),
                                  items: _StudentsScreenState._importFields.entries.map((e) => DropdownMenuItem(
                                    value: e.key,
                                    child: Text(e.key.isEmpty ? '-- Skip --' : '${e.value}${_requiredFields.contains(e.key) ? ' *' : ''}',
                                        style: TextStyle(fontSize: 10, color: e.key.isEmpty ? AppColors.textSecondary : AppColors.textPrimary)),
                                  )).toList(),
                                  onChanged: (val) {
                                    setState(() => _mappings[c] = val ?? '');
                                  },
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                  rows: [
                    for (int r = 0; r < _rows.length; r++)
                      DataRow(
                        color: WidgetStateProperty.all(
                          _validateRow(r) != null ? Colors.red.withValues(alpha: 0.04) : Colors.transparent,
                        ),
                        cells: [
                          DataCell(Text('${r + 1}', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary))),
                          DataCell(
                            _validateRow(r) == null
                                ? const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.accent)
                                : Tooltip(
                                    message: _validateRow(r)!,
                                    child: Icon(Icons.error_rounded, size: 16, color: Colors.red[400]),
                                  ),
                          ),
                          for (int c = 0; c < _headers.length; c++)
                            DataCell(Text(
                              c < _rows[r].length ? _rows[r][c].toString() : '',
                              style: const TextStyle(fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            )),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        // Bottom actions
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => setState(() { _step = 0; _headers = []; _rows = []; _mappings = []; }),
                child: const Text('Back'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: (validCount > 0 && allRequiredMapped) ? _startImport : null,
                icon: const Icon(Icons.upload_rounded, size: 18),
                label: Text('Import $validCount Students'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─── Step 2: Importing ────────────────────────────────────────────────────

  Widget _buildImportingStep() {
    final progress = _total > 0 ? (_imported + _skipped) / _total : 0.0;
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 16),
          SizedBox(
            width: 80, height: 80,
            child: CircularProgressIndicator(
              value: progress,
              strokeWidth: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Importing students...', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Text('${_imported + _skipped} of $_total', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.border,
              valueColor: const AlwaysStoppedAnimation(AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Step 3: Done ─────────────────────────────────────────────────────────

  Widget _buildDoneStep() {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _imported > 0 ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 56,
            color: _imported > 0 ? AppColors.accent : Colors.red,
          ),
          const SizedBox(height: 16),
          Text(
            _imported > 0 ? 'Import Complete!' : 'Import Failed',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700,
                color: _imported > 0 ? AppColors.textPrimary : Colors.red),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _statChip('Imported', '$_imported', AppColors.accent),
              const SizedBox(width: 12),
              _statChip('Skipped', '$_skipped', _skipped > 0 ? Colors.orange : AppColors.textSecondary),
              const SizedBox(width: 12),
              _statChip('Total', '$_total', AppColors.info),
            ],
          ),
          if (_importErrors.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 150),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Errors:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red[700])),
                    const SizedBox(height: 4),
                    for (final err in _importErrors)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2),
                        child: Text(err, style: TextStyle(fontSize: 11, color: Colors.red[600])),
                      ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 11, color: color)),
        ],
      ),
    );
  }
}
