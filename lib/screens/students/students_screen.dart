import 'dart:convert';
import 'dart:io';
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
  final StudentModel? initialStudent;
  const StudentsScreen({super.key, this.initialStudent});

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

  bool _isUploadingPhoto = false;
  bool _isFormEnabled = true;
  List<StudentModel> _students = [];
  Map<String, int> _classCounts = {};
  Map<String, List<StudentModel>> _cachedClassStudents = {};
  bool _loadingClassStudents = false;
  StudentModel? _selectedStudent;
  String? _selectedClassFilter; // null = show class list, non-null = show students of that class
  final _searchController = TextEditingController();
  int _studentPage = 0;
  static const int _studentsPerPage = 20;

  // Import state
  bool _showImport = false;
  String? _importFileName;
  List<String> _importHeaders = [];
  List<List<dynamic>> _importRows = [];
  bool _importValidated = false;
  List<String?> _importMappings = [];
  int _importStep = 0; // 0=grid, 2=importing, 3=done
  int _importedCount = 0;
  int _skippedCount = 0;
  int _totalCount = 0;
  List<String> _importErrors = [];
  String? _importErrorMsg;

  static const _importGridKeys = [
    'stuadmno', 'stuname', 'stugender', 'studob', 'stuadmdate', 'stuclass',
    'stumobile', 'stuemail', 'concession',
    'stuaddress', 'stucity', 'stustate', 'stucountry',
    'stupin', 'stubloodgrp',
    'fathername', 'fathermobile', 'fatheroccupation',
    'mothername', 'mothermobile', 'motheroccupation',
    'guardianname', 'guardianmobile', 'guardianoccupation',
    'payincharge', 'payinchargemob',
  ];

  static const Map<String, String> _importGridLabels = {
    'stuadmno': 'Adm No *',
    'stuname': 'Name *',
    'stugender': 'Gender *',
    'studob': 'DOB *',
    'stuadmdate': 'Adm Date',
    'stuclass': 'Class *',
    'stumobile': 'Mobile *',
    'stuemail': 'Email',
    'concession': 'Concession',
    'stuaddress': 'Address',
    'stucity': 'City',
    'stustate': 'State',
    'stucountry': 'Country',
    'stupin': 'Pin Code',
    'stubloodgrp': 'Blood Group',
    'fathername': 'Father Name',
    'fathermobile': 'Father Mobile',
    'fatheroccupation': 'Father Occ.',
    'mothername': 'Mother Name',
    'mothermobile': 'Mother Mobile',
    'motheroccupation': 'Mother Occ.',
    'guardianname': 'Guardian Name',
    'guardianmobile': 'Guardian Mobile',
    'guardianoccupation': 'Guardian Occ.',
    'payincharge': 'Pay In Charge',
    'payinchargemob': 'Pay Mobile',
  };

  final ScrollController _importScrollController = ScrollController();

  static const _importRequiredFields = {'stuadmno', 'stuname', 'stugender', 'studob', 'stumobile', 'stuclass'};

  static const TextStyle _inputStyle = TextStyle(fontWeight: FontWeight.w500, fontSize: 13, color: Color(0xFF555555));

  final List<String> _bloodGroups = ['A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'];
  final List<String> _genders = ['Male', 'Female', 'Other'];
  static const List<String> _classOrder = [
    'PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
  ];

  static const List<Color> _classColors = [
    Color(0xFF6366F1), // PKG - Indigo
    Color(0xFF8B5CF6), // LKG - Violet
    Color(0xFFA855F7), // UKG - Purple
    Color(0xFFEC4899), // I - Pink
    Color(0xFFF43F5E), // II - Rose
    Color(0xFFEF4444), // III - Red
    Color(0xFFF97316), // IV - Orange
    Color(0xFFF59E0B), // V - Amber
    Color(0xFF22C55E), // VI - Green
    Color(0xFF14B8A6), // VII - Teal
    Color(0xFF06B6D4), // VIII - Cyan
    Color(0xFF6C8EEF), // IX - Blue
    Color(0xFF2563EB), // X - Blue dark
    Color(0xFF7C3AED), // XI - Violet dark
    Color(0xFF9333EA), // XII - Purple dark
  ];

  Color _getClassColor(String className) {
    final index = _classOrder.indexOf(className);
    if (index >= 0 && index < _classColors.length) return _classColors[index];
    return AppColors.accent;
  }

  @override
  void initState() {
    super.initState();
    _loadDropdowns();
  }

  @override
  void dispose() {
    _importScrollController.dispose();
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
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadDropdowns() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;

    // Stage 1: parallel — includes class counts so list shows immediately with correct counts
    final results = await Future.wait<dynamic>([
      SupabaseService.getYears(insId),
      SupabaseService.getConcessions(insId),
      SupabaseService.getClasses(insId),
      SupabaseService.getInstitutionInfo(insId),
      SupabaseService.getStudentCountsByClass(insId),
    ]);

    if (!mounted) return;
    final years = results[0] as List<Map<String, dynamic>>;
    final concessions = results[1] as List<Map<String, dynamic>>;
    final rawClasses = results[2] as List<String>;
    final insInfo = results[3] as ({String? name, String? logo, String? address, String? mobile, String? email});
    final classCounts = results[4] as Map<String, int>;
    final ordered = _classOrder.where((c) => rawClasses.contains(c)).toList();
    final extra = rawClasses.where((c) => !_classOrder.contains(c)).toList();

    setState(() {
      _years = years;
      _concessions = concessions;
      _classes = [...ordered, ...extra];
      _classCounts = classCounts;
      _insName = insInfo.name;
      _insLogo = insInfo.logo;
      if (years.isNotEmpty) {
        _selectedYrId = years.first['yr_id'].toString();
        _selectedYrLabel = years.first['yrlabel'];
      }
    });

    // Stage 2: background — load all students for search/export
    final students = await SupabaseService.getStudents(insId);
    if (!mounted) return;
    setState(() => _students = students);

    // Auto-select initial student if provided
    if (widget.initialStudent != null) {
      final s = students.firstWhere(
        (s) => s.stuId == widget.initialStudent!.stuId,
        orElse: () => widget.initialStudent!,
      );
      setState(() {
        _selectedClassFilter = s.stuclass;
        _selectedStudent = s;
      });
      _populateStudentForm(s);
    }
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
      _admDate = null;
      _dob = null;
      _photoUrl = null;
      _selectedParentTab = 'Father';
      if (_years.isNotEmpty) {
        _selectedYrId = _years.first['yr_id'].toString();
        _selectedYrLabel = _years.first['yrlabel'];
      }
    });

    String clean(String? v) => (v == null || v.toUpperCase() == 'NULL') ? '' : v;

    _admNoController.text = s.stuadmno;
    _nameController.text = s.stuname;
    _mobileController.text = s.stumobile;
    _emailController.text = clean(s.stuemail);
    _addressController.text = clean(s.stuaddress);
    _cityController.text = clean(s.stucity);
    _stateController.text = clean(s.stustate);
    _countryController.text = clean(s.stucountry);
    _pinController.text = clean(s.stupin);

    // Fetch parent data
    final parent = await SupabaseService.getStudentParent(s.stuId);
    if (!mounted) return;

    _fatherNameController.text = clean(parent?['fathername']?.toString());
    _fatherMobileController.text = clean(parent?['fathermobile']?.toString());
    _fatherOccController.text = clean(parent?['fatheroccupation']?.toString());
    _motherNameController.text = clean(parent?['mothername']?.toString());
    _motherMobileController.text = clean(parent?['mothermobile']?.toString());
    _motherOccController.text = clean(parent?['motheroccupation']?.toString());
    _guardianNameController.text = clean(parent?['guardianname']?.toString());
    _guardianMobileController.text = clean(parent?['guardianmobile']?.toString());
    _guardianOccController.text = clean(parent?['guardianoccupation']?.toString());
    _payNameController.text = clean(parent?['payincharge']?.toString());
    _payMobileController.text = clean(parent?['payinchargemob']?.toString());

    setState(() {
      _selectedGender = s.gender;
      _selectedBloodGroup = _normalizeBloodGroup(s.stubloodgrp);
      _selectedClass = s.stuclass;
      _selectedConId = s.conId?.toString();
      _admDate = s.stuadmdate;
      _dob = s.studob;
      _photoUrl = s.stuphoto;
      _isFormEnabled = false; // view mode — buttons disabled
    });
  }

  void _clearForm() {
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
      _admDate = null;
      _dob = null;
      _photoUrl = null;
      _selectedParentTab = 'Father';
      _selectedStudent = null;
      _isFormEnabled = true;
      if (_years.isNotEmpty) {
        _selectedYrId = _years.first['yr_id'].toString();
        _selectedYrLabel = _years.first['yrlabel'];
      }
    });
  }

  bool _isSaving = false;

  Future<void> _saveNewStudent() async {
    if (_admNoController.text.trim().isEmpty ||
        _nameController.text.trim().isEmpty ||
        _selectedClass == null ||
        _mobileController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill all required fields (Adm No, Name, Class, Mobile)'), backgroundColor: AppColors.error),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;
    final inscode = auth.inscode ?? '';
    final yrId = int.tryParse(_selectedYrId ?? '1') ?? 1;
    final yrLabel = _selectedYrLabel ?? '';
    final now = DateTime.now().toIso8601String().split('T').first;

    setState(() => _isSaving = true);

    try {
      final stuId = await SupabaseService.addStudent({
        'ins_id': insId,
        'inscode': inscode,
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'stuadmno': _admNoController.text.trim(),
        'stuadmdate': (_admDate ?? DateTime.now()).toIso8601String().split('T').first,
        'stuname': _nameController.text.trim(),
        'stugender': _selectedGender == 'Female' ? 'F' : _selectedGender == 'Male' ? 'M' : 'O',
        'studob': _dob?.toIso8601String().split('T').first,
        'stumobile': _mobileController.text.trim(),
        'stuemail': _emailController.text.trim().isNotEmpty ? _emailController.text.trim() : null,
        'stuaddress': _addressController.text.trim().isNotEmpty ? _addressController.text.trim() : null,
        'stucity': _cityController.text.trim().isNotEmpty ? _cityController.text.trim() : null,
        'stustate': _stateController.text.trim().isNotEmpty ? _stateController.text.trim() : null,
        'stucountry': _countryController.text.trim().isNotEmpty ? _countryController.text.trim() : null,
        'stupin': _pinController.text.trim().isNotEmpty ? _pinController.text.trim() : null,
        'stubloodgrp': _selectedBloodGroup,
        'stuclass': _selectedClass,
        'con_id': _selectedConId != null ? int.tryParse(_selectedConId!) : null,
        'stucondesc': _selectedConId != null ? _concessions.firstWhere((c) => c['con_id'].toString() == _selectedConId, orElse: () => {})['condesc'] : null,
        'stuphoto': _photoUrl,
        'stuser_id': _admNoController.text.trim(),
        'stuotpstatus': 0,
        'approvedby': '',
        'approveddate': now,
        'suspendedby': '',
        'terminatedby': '',
        'activestatus': 1,
        'createdon': now,
      });

      // Save parent
      final fatherMob = _fatherMobileController.text.trim().isNotEmpty ? _fatherMobileController.text.trim() : null;
      final motherMob = _motherMobileController.text.trim().isNotEmpty ? _motherMobileController.text.trim() : null;
      final payMob = _payMobileController.text.trim().isNotEmpty ? _payMobileController.text.trim() : null;

      final existingParId = await SupabaseService.findParentByMobile(
        fatherMobile: fatherMob,
        motherMobile: motherMob,
        payMobile: payMob,
      );

      final parId = existingParId ?? await SupabaseService.saveParent({
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'partype': 'P',
        'fathername': _fatherNameController.text.trim().isNotEmpty ? _fatherNameController.text.trim() : null,
        'fathermobile': fatherMob,
        'fatheroccupation': _fatherOccController.text.trim().isNotEmpty ? _fatherOccController.text.trim() : null,
        'mothername': _motherNameController.text.trim().isNotEmpty ? _motherNameController.text.trim() : null,
        'mothermobile': motherMob,
        'motheroccupation': _motherOccController.text.trim().isNotEmpty ? _motherOccController.text.trim() : null,
        'guardianname': _guardianNameController.text.trim().isNotEmpty ? _guardianNameController.text.trim() : null,
        'guardianmobile': _guardianMobileController.text.trim().isNotEmpty ? _guardianMobileController.text.trim() : null,
        'guardianoccupation': _guardianOccController.text.trim().isNotEmpty ? _guardianOccController.text.trim() : null,
        'payincharge': _payNameController.text.trim().isNotEmpty ? _payNameController.text.trim() : null,
        'payinchargemob': payMob,
        'parotpstatus': 0,
        'approveddate': now,
        'activestatus': 1,
      });

      // Link parent to student
      await SupabaseService.saveParentDetail({
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'par_id': parId,
        'stu_id': stuId,
        'ins_id': insId,
        'inscode': inscode,
        'stuadmno': _admNoController.text.trim(),
        'stuname': _nameController.text.trim(),
        'stuclass': _selectedClass,
        'activestatus': 1,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Student added successfully'), backgroundColor: AppColors.success),
        );
        _clearForm();
        _loadDropdowns();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving student: $e'), backgroundColor: AppColors.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
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

  List<StudentModel> get _filteredStudents {
    final q = _searchController.text.toLowerCase();
    if (q.isEmpty) return _students;
    return _students.where((s) =>
      s.stuname.toLowerCase().contains(q) ||
      s.stuadmno.toLowerCase().contains(q) ||
      s.stuclass.toLowerCase().contains(q),
    ).toList();
  }

  /// Group filtered students by class, ordered by [_classOrder].
  Map<String, List<StudentModel>> get _groupedStudents {
    final students = _filteredStudents;
    final map = <String, List<StudentModel>>{};
    for (final s in students) {
      final cls = s.stuclass.isNotEmpty ? s.stuclass : 'Unassigned';
      map.putIfAbsent(cls, () => []).add(s);
    }
    // Sort keys by _classOrder
    final sortedKeys = map.keys.toList()..sort((a, b) {
      final ai = _classOrder.indexOf(a);
      final bi = _classOrder.indexOf(b);
      final aIdx = ai == -1 ? 999 : ai;
      final bIdx = bi == -1 ? 999 : bi;
      return aIdx.compareTo(bIdx);
    });
    return {for (final k in sortedKeys) k: map[k]!};
  }

  Widget _buildStudentAvatar(StudentModel s, Color classColor, bool isSelected) {
    final bgColor = isSelected
        ? classColor.withValues(alpha: 0.2)
        : classColor.withValues(alpha: 0.1);
    final letter = Text(
      s.stuname.isNotEmpty ? s.stuname[0].toUpperCase() : '?',
      style: TextStyle(color: classColor, fontWeight: FontWeight.w700, fontSize: 13),
    );

    if (s.stuphoto != null && s.stuphoto!.startsWith('http')) {
      return CircleAvatar(
        radius: 16,
        backgroundColor: bgColor,
        child: ClipOval(
          child: Image.network(
            s.stuphoto!,
            width: 32,
            height: 32,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => letter,
          ),
        ),
      );
    }

    return CircleAvatar(
      radius: 16,
      backgroundColor: bgColor,
      child: letter,
    );
  }

  // ─── Import / Export ─────────────────────────────────────────────────────────

  Future<void> _exportClassStudents(String className, List<StudentModel> students) async {
    if (students.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No students to export')));
      return;
    }

    final headers = ['Adm No', 'Student Name', 'Gender', 'DOB', 'Class', 'Mobile', 'Email', 'Address', 'City', 'State', 'Blood Group'];
    final rows = <List<String>>[headers];
    for (final s in students) {
      rows.add([
        s.stuadmno,
        s.stuname,
        s.gender,
        '${s.studob.day.toString().padLeft(2, '0')}/${s.studob.month.toString().padLeft(2, '0')}/${s.studob.year}',
        s.stuclass,
        s.stumobile,
        s.stuemail ?? '',
        s.stuaddress ?? '',
        s.stucity ?? '',
        s.stustate ?? '',
        s.stubloodgrp ?? '',
      ]);
    }

    final csv = const ListToCsvConverter().convert(rows);

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Export Class $className Students',
      fileName: 'Class_${className}_Students.csv',
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );

    if (result != null) {
      final file = File(result);
      await file.writeAsString(csv);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported ${students.length} students to CSV'), backgroundColor: AppColors.success),
        );
      }
    }
  }

  // ─── Left Panel Builders ─────────────────────────────────────────────────────

  Widget _buildClassList() {
    if (_classes.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _classes.length,
      itemBuilder: (context, index) {
        final className = _classes[index];
        // Use background-loaded count if available, else RPC count
        final count = _groupedStudents[className]?.length ?? _classCounts[className] ?? 0;
        final classColor = _getClassColor(className);
        final isSelected = _selectedClassFilter == className;
        return Material(
          color: isSelected ? classColor.withValues(alpha: 0.1) : Colors.transparent,
          child: InkWell(
            onTap: () async {
              setState(() {
                _selectedClassFilter = className;
                _selectedStudent = null;
                _studentPage = 0;
                _searchController.clear();
              });
              // Lazy-load if background load hasn't provided this class yet
              if ((_groupedStudents[className]?.isEmpty ?? true) && _cachedClassStudents[className] == null) {
                setState(() => _loadingClassStudents = true);
                final auth = context.read<AuthProvider>();
                final insId = auth.insId ?? 1;
                final classStudents = await SupabaseService.getStudentsByClass(insId, className);
                if (mounted) {
                  setState(() {
                    _cachedClassStudents[className] = classStudents;
                    _loadingClassStudents = false;
                  });
                }
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                border: const Border(bottom: BorderSide(color: AppColors.border, width: 0.5)),
                color: isSelected ? classColor.withValues(alpha: 0.08) : null,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: isSelected ? classColor.withValues(alpha: 0.2) : classColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Icon(Icons.class_rounded, size: 18, color: classColor)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Class $className', style: TextStyle(fontSize: 13, fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600, color: isSelected ? classColor : AppColors.textPrimary)),
                        Text('$count students', style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: classColor.withValues(alpha: isSelected ? 0.2 : 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('$count', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: classColor)),
                  ),
                  const SizedBox(width: 8),
                  Icon(isSelected ? Icons.check_circle_rounded : Icons.chevron_right_rounded, size: 18, color: isSelected ? classColor : AppColors.textSecondary),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStudentListForClass(String className) {
    final allStudents = _groupedStudents[className]?.isNotEmpty == true
        ? _groupedStudents[className]!
        : _cachedClassStudents[className] ?? [];
    if (_loadingClassStudents && allStudents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final q = _searchController.text.toLowerCase();
    final students = q.isEmpty
        ? allStudents
        : allStudents.where((s) =>
            s.stuname.toLowerCase().contains(q) ||
            s.stuadmno.toLowerCase().contains(q)).toList();
    final classColor = _getClassColor(className);

    return Column(
      children: [
        // Back button + class header
        Container(
          padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
          decoration: BoxDecoration(
            color: classColor.withValues(alpha: 0.06),
          ),
          child: Row(
            children: [
              IconButton(
                onPressed: () => setState(() {
                  _selectedClassFilter = null;
                  _selectedStudent = null;
                  _searchController.clear();
                }),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                color: classColor,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              ),
              Icon(Icons.class_rounded, size: 14, color: classColor.withValues(alpha: 0.7)),
              const SizedBox(width: 6),
              Text('Class $className', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: classColor)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: classColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${allStudents.length}', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: classColor.withValues(alpha: 0.7))),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AppColors.border),
        // Student list
        Expanded(
          child: students.isEmpty
              ? const Center(child: Text('No students found', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: students.length,
                  itemBuilder: (context, index) {
                    final s = students[index];
                    final isSelected = _selectedStudent?.stuId == s.stuId;
                    return Material(
                      color: isSelected ? AppColors.accent.withValues(alpha: 0.1) : Colors.transparent,
                      child: InkWell(
                        onTap: () {
                          setState(() => _selectedStudent = s);
                          _populateStudentForm(s);
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          child: Row(
                            children: [
                              _buildStudentAvatar(s, classColor, isSelected),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.stuname, style: TextStyle(fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600, fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                                    Text(s.stuadmno, style: const TextStyle(fontSize: 10, color: AppColors.textSecondary)),
                                  ],
                                ),
                              ),
                              if (isSelected)
                                const Icon(Icons.check_circle_rounded, size: 16, color: AppColors.accent),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildClassStudentTable(String className) {
    final allStudents = _groupedStudents[className]?.isNotEmpty == true
        ? _groupedStudents[className]!
        : _cachedClassStudents[className] ?? [];
    if (_loadingClassStudents && allStudents.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    final classColor = _getClassColor(className);

    // Search filter
    final q = _searchController.text.toLowerCase();
    final filteredStudents = q.isEmpty
        ? allStudents
        : allStudents.where((s) =>
            s.stuname.toLowerCase().contains(q) ||
            s.stuadmno.toLowerCase().contains(q)).toList();

    // Pagination
    final totalStudents = filteredStudents.length;
    final totalPages = (totalStudents / _studentsPerPage).ceil();
    if (_studentPage >= totalPages && totalPages > 0) _studentPage = totalPages - 1;
    final startIdx = _studentPage * _studentsPerPage;
    final endIdx = (startIdx + _studentsPerPage).clamp(0, totalStudents);
    final pagedStudents = filteredStudents.sublist(startIdx, endIdx);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with back button
          Container(
            padding: const EdgeInsets.fromLTRB(10, 10, 20, 10),
            decoration: BoxDecoration(
              color: classColor.withValues(alpha: 0.04),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(12), topRight: Radius.circular(12)),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: () => setState(() {
                    _selectedClassFilter = null;
                    _selectedStudent = null;
                    _studentPage = 0;
                    _searchController.clear();
                  }),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  color: classColor,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: 'Back to classes',
                ),
                Icon(Icons.class_rounded, size: 20, color: classColor),
                const SizedBox(width: 8),
                Text('Class $className', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: classColor)),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: classColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${allStudents.length} students', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: classColor)),
                ),
                const Spacer(),
                // Search
                SizedBox(
                  width: 200,
                  height: 34,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search...',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search_rounded, size: 16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
                      isDense: true,
                    ),
                    style: const TextStyle(fontSize: 13),
                    onChanged: (_) => setState(() => _studentPage = 0),
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Export $className',
                  child: InkWell(
                    onTap: () => _exportClassStudents(className, allStudents),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: AppColors.success.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.success.withValues(alpha: 0.3)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.file_download_rounded, size: 14, color: AppColors.success),
                          SizedBox(width: 4),
                          Text('Export', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.success)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Table section
          Expanded(
            child: Column(
                  children: [
                    // Table header
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      color: const Color(0xFF6C8EEF),
                      child: const Row(
                        children: [
                          SizedBox(width: 40, child: Text('S NO.', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                          SizedBox(width: 100, child: Text('ADM NO', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                          Expanded(child: Text('STUDENT NAME', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                          SizedBox(width: 80, child: Text('GENDER', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                          SizedBox(width: 120, child: Text('MOBILE', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white))),
                          SizedBox(width: 30),
                        ],
                      ),
                    ),
                    // Student rows
                    Expanded(
                      child: pagedStudents.isEmpty
                          ? const Center(child: Text('No students found', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)))
                          : ListView.builder(
                              padding: EdgeInsets.zero,
                              itemCount: pagedStudents.length,
                              itemBuilder: (context, index) {
                                final s = pagedStudents[index];
                                final serialNo = startIdx + index + 1;
                                return InkWell(
                                  onTap: () {
                                    setState(() => _selectedStudent = s);
                                    _populateStudentForm(s);
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                    color: index.isEven ? Colors.white : AppColors.surface,
                                    child: Row(
                                      children: [
                                        SizedBox(width: 40, child: Text('$serialNo', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                                        SizedBox(width: 100, child: Text(s.stuadmno, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent))),
                                        Expanded(child: Text(s.stuname, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis)),
                                        SizedBox(width: 80, child: Text(s.stugender, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                                        SizedBox(width: 120, child: Text(s.stumobile, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                                        const SizedBox(width: 30, child: Icon(Icons.arrow_forward_ios_rounded, size: 16, color: AppColors.accent)),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    // Pagination footer
                    if (totalStudents > _studentsPerPage)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: AppColors.border, width: 0.5)),
                          borderRadius: BorderRadius.only(
                            bottomLeft: Radius.circular(7),
                            bottomRight: Radius.circular(7),
                          ),
                        ),
                        child: Row(
                          children: [
                            Text(
                              'Showing ${totalStudents == 0 ? 0 : startIdx + 1}–$endIdx of $totalStudents students',
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                            const Spacer(),
                            IconButton(
                              icon: const Icon(Icons.first_page_rounded, size: 20),
                              onPressed: _studentPage > 0 ? () => setState(() => _studentPage = 0) : null,
                              tooltip: 'First page', splashRadius: 18,
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_left_rounded, size: 20),
                              onPressed: _studentPage > 0 ? () => setState(() => _studentPage--) : null,
                              tooltip: 'Previous', splashRadius: 18,
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(6)),
                              child: Text('${_studentPage + 1}/$totalPages', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                            ),
                            IconButton(
                              icon: const Icon(Icons.chevron_right_rounded, size: 20),
                              onPressed: _studentPage < totalPages - 1 ? () => setState(() => _studentPage++) : null,
                              tooltip: 'Next', splashRadius: 18,
                            ),
                            IconButton(
                              icon: const Icon(Icons.last_page_rounded, size: 20),
                              onPressed: _studentPage < totalPages - 1 ? () => setState(() => _studentPage = totalPages - 1) : null,
                              tooltip: 'Last page', splashRadius: 18,
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header
        Row(
          children: [
            Icon(Icons.people_alt_rounded, color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Text('Students', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _showImport = !_showImport;
                if (!_showImport) _resetImport();
              }),
              icon: Icon(_showImport ? Icons.close : Icons.upload_file_rounded, size: 18),
              label: Text(_showImport ? 'Close Import' : 'Import CSV/Excel'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _loadDropdowns,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        Expanded(
          child: _showImport ? _buildStudentImportSection() : Form(
            key: _formKey,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // LEFT — Student List
                SizedBox(
                  width: 260,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.people_alt_rounded, color: AppColors.accent, size: 20),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Students', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('${_students.isNotEmpty ? _students.length : _classCounts.values.fold(0, (s, c) => s + c)}', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 0),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: AppColors.border),
                  // Class list (always visible)
                  Expanded(
                    child: _buildClassList(),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 16),

          // RIGHT — Student Details or Class Table
          Expanded(
            child: _selectedStudent == null
                ? (_selectedClassFilter != null ? _buildClassStudentTable(_selectedClassFilter!) : const SizedBox())
                : Column(
                    children: [
                      // Back breadcrumb
                      if (_selectedStudent != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Row(
                            children: [
                              InkWell(
                                onTap: () => setState(() { _selectedStudent = null; _selectedClassFilter = null; }),
                                borderRadius: BorderRadius.circular(6),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                                      SizedBox(width: 6),
                                      Text('Back to Student List', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent)),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 4),
                              Text(_selectedStudent!.stuname, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                              const SizedBox(width: 6),
                              Text('(${_selectedStudent!.stuadmno})', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                            ],
                          ),
                        ),
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Student Information panel
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.border),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.center,
                                      children: [
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
                                                const SizedBox(height: 6),
                                                Row(children: [
                                                  if (_insLogo != null)
                                                    Image.network(
                                                      _insLogo!,
                                                      width: 48, height: 48, fit: BoxFit.contain,
                                                      errorBuilder: (_, __, ___) => const Icon(Icons.school_rounded, color: AppColors.accent, size: 44),
                                                    )
                                                  else
                                                    const Icon(Icons.school_rounded, color: AppColors.accent, size: 44),
                                                  const SizedBox(width: 8),
                                                  Flexible(
                                                    child: Text(
                                                      _insName ?? context.read<AuthProvider>().insName ?? context.read<AuthProvider>().inscode ?? '',
                                                      style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
                                                      overflow: TextOverflow.ellipsis,
                                                    ),
                                                  ),
                                                ]),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            children: [
                                              Container(
                                                width: 72, height: 72,
                                                decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.accent.withValues(alpha: 0.1)),
                                                child: ClipOval(
                                                  child: _photoUrl != null
                                                      ? Image.network(_photoUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _avatarPlaceholder())
                                                      : _avatarPlaceholder(),
                                                ),
                                              ),
                                              TextButton.icon(
                                                onPressed: (_isFormEnabled && !_isUploadingPhoto) ? _uploadPhoto : null,
                                                icon: _isUploadingPhoto
                                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                                    : const Icon(Icons.camera_alt_rounded, size: 14),
                                                label: Text(_isUploadingPhoto ? 'Uploading...' : 'Upload Photo', style: const TextStyle(fontSize: 13)),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    const Divider(color: AppColors.border),
                                    Expanded(
                                      child: SingleChildScrollView(
                                        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
                                        child: IgnorePointer(
                                          ignoring: !_isFormEnabled,
                                          child: _buildStudentFields(),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            const SizedBox(width: 16),

                            // Parent + Payment panels
                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                    children: [
                                      _panel(title: 'Parent / Guardian Information', icon: Icons.family_restroom_rounded, child: _buildParentFields()),
                                      const SizedBox(height: 16),
                                      _panel(title: 'Payment In Charge', icon: Icons.payments_rounded, child: _buildPaymentFields()),
                                      if (_selectedStudent == null) ...[
                                        const SizedBox(height: 16),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextButton.icon(
                                                onPressed: _isSaving ? null : _clearForm,
                                                icon: const Icon(Icons.close_rounded, size: 16),
                                                label: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w500)),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: AppColors.textSecondary,
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: ElevatedButton.icon(
                                                onPressed: _isSaving ? null : _saveNewStudent,
                                                icon: _isSaving
                                                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                                    : const Icon(Icons.save_rounded, size: 18),
                                                label: Text(_isSaving ? 'Saving...' : 'Save', style: const TextStyle(fontWeight: FontWeight.w600)),
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
                                      ] else if (_selectedStudent!.isActive) ...[
                                      ],
                                      const SizedBox(height: 24),
                                    ],
                                  ),
                              ),
                            ),
                          ],
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
            dropdownColor: Colors.white,
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

        _fieldFull(label: 'Student Name *', child: TextFormField(
          controller: _nameController,
          decoration: _dec('Enter full name'),
          style: _inputStyle,
          validator: (v) => (v == null || v.isEmpty) ? 'Required' : null,
        )),
        const SizedBox(height: 14),

        _row2(
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
          _fieldFull(label: 'Gender *', child: DropdownButtonFormField<String>(
            initialValue: _selectedGender,
            decoration: _dec('Select gender'),
            dropdownColor: Colors.white,
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
            dropdownColor: Colors.white,
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
            dropdownColor: Colors.white,
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
      'concession': 'concession', 'concession category': 'concession',
      'payment in charge': 'payincharge', 'pay in charge': 'payincharge', 'payincharge': 'payincharge', 'pay name': 'payincharge',
      'payment mobile': 'payinchargemob', 'pay mobile': 'payinchargemob', 'payinchargemob': 'payinchargemob',
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

  // ─── Import Logic ───────────────────────────────────────────────────────

  void _resetImport() {
    setState(() {
      _showImport = false;
      _importStep = 0;
      _importFileName = null;
      _importHeaders = [];
      _importRows = [];
      _importMappings = [];
      _importedCount = 0;
      _skippedCount = 0;
      _totalCount = 0;
      _importErrors = [];
      _importErrorMsg = null;
    });
  }

  Future<void> _pickImportFile() async {
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

      final mappings = headers.map((h) {
        final m = _autoMapHeader(h);
        return m.isEmpty ? null : m;
      }).toList();

      setState(() {
        _importFileName = file.name;
        _importHeaders = headers;
        _importRows = rows;
        _importValidated = false;
        _importMappings = mappings;
        _importStep = 1;
        _importErrorMsg = null;
      });
    } catch (e) {
      setState(() => _importErrorMsg = 'Failed to parse file: $e');
    }
  }

  Future<void> _exportStudentTemplate() async {
    final excel = xl.Excel.createExcel();
    final sheet = excel['Students'];
    excel.delete('Sheet1');

    final headers = [
      'Adm No', 'Name', 'Gender', 'DOB', 'Admission Date', 'Class', 'Mobile', 'Email', 'Concession',
      'Address', 'City', 'State', 'Country', 'PIN', 'Blood Group',
      'Father Name', 'Father Mobile', 'Father Occupation',
      'Mother Name', 'Mother Mobile', 'Mother Occupation',
      'Guardian Name', 'Guardian Mobile', 'Guardian Occupation',
      'Payment In Charge', 'Payment Mobile',
    ];

    final headerStyle = xl.CellStyle(
      backgroundColorHex: xl.ExcelColor.fromHexString('#FF2D3748'),
      fontColorHex: xl.ExcelColor.fromHexString('#FFFFFFFF'),
      bold: true,
    );

    for (int i = 0; i < headers.length; i++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = xl.TextCellValue(headers[i]);
      cell.cellStyle = headerStyle;
      sheet.setColumnWidth(i, 18.0);
    }
    sheet.setRowHeight(0, 32);

    try {
      final savePath = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Template',
        fileName: 'student_import_template.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (savePath == null) return;

      final bytes = excel.encode();
      if (bytes == null) return;
      await File(savePath).writeAsBytes(bytes);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template exported successfully'), backgroundColor: AppColors.success),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  String _importMappedCell(List<dynamic> row, String fieldKey) {
    final idx = _importMappings.indexOf(fieldKey);
    if (idx < 0 || idx >= row.length) return '';
    return row[idx].toString().trim();
  }

  String? _importCellByKey(List<dynamic> row, String fieldKey) {
    final idx = _importMappings.indexOf(fieldKey);
    if (idx < 0 || idx >= row.length) return null;
    final v = row[idx].toString().trim();
    return v.isEmpty ? null : v;
  }

  /// Returns null if the value is null, empty, or whitespace-only
  static String? _nullIfEmpty(String? v) {
    if (v == null) return null;
    final trimmed = v.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Validates email format; returns null if invalid
  static String? _validEmail(String? v) {
    final e = _nullIfEmpty(v);
    if (e == null) return null;
    // Basic email check — must contain @ and .
    final regex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return regex.hasMatch(e) ? e : null;
  }

  String? _validateImportRow(int rowIdx) {
    final row = _importRows[rowIdx];
    final missing = <String>[];
    for (final reqKey in _importRequiredFields) {
      final colIdx = _importMappings.indexOf(reqKey);
      if (colIdx < 0 || colIdx >= row.length || row[colIdx].toString().trim().isEmpty) {
        missing.add(_importGridLabels[reqKey] ?? _importFields[reqKey] ?? reqKey);
      }
    }
    if (missing.isEmpty) return null;
    return 'Missing: ${missing.join(', ')}';
  }

  void _validateImportData() {
    final errors = <String>[];
    for (int i = 0; i < _importRows.length; i++) {
      final err = _validateImportRow(i);
      if (err != null) errors.add('Row ${i + 2}: $err');
    }
    if (errors.isEmpty) {
      setState(() => _importValidated = true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('All rows are valid'), backgroundColor: AppColors.success),
      );
    } else {
      setState(() => _importValidated = false);
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          title: Text('${errors.length} validation errors', style: const TextStyle(fontWeight: FontWeight.w700)),
          content: SizedBox(
            width: 400,
            height: 250,
            child: ListView(
              children: errors.map((e) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(e, style: const TextStyle(fontSize: 13, color: AppColors.error)),
              )).toList(),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
          ],
        ),
      );
    }
  }

  Future<void> _startStudentImport() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId ?? 1;
    final inscode = auth.inscode ?? '';
    final yrId = int.tryParse(_selectedYrId ?? '1') ?? 1;
    final yrLabel = _selectedYrLabel ?? '';

    setState(() {
      _importStep = 2;
      _importedCount = 0;
      _skippedCount = 0;
      _totalCount = _importRows.length;
      _importErrors = [];
    });

    // 1. Validate and build staging rows
    final stagingRows = <Map<String, dynamic>>[];
    for (int i = 0; i < _importRows.length; i++) {
      final err = _validateImportRow(i);
      if (err != null) {
        _skippedCount++;
        _importErrors.add('Row ${i + 2}: $err');
        continue;
      }
      final row = _importRows[i];
      final dob = _parseDate(_importCellByKey(row, 'studob'));
      final admDate = _parseDate(_importCellByKey(row, 'stuadmdate'));
      stagingRows.add({
        'ins_id': insId,
        'inscode': inscode,
        'yr_id': yrId,
        'yrlabel': yrLabel,
        'stuadmno': _importCellByKey(row, 'stuadmno'),
        'stuname': _importCellByKey(row, 'stuname'),
        'stugender': _normalizeGender(_importCellByKey(row, 'stugender')),
        'studob': dob?.toIso8601String().split('T').first,
        'stuadmdate': (admDate ?? DateTime.now()).toIso8601String().split('T').first,
        'stuclass': _importCellByKey(row, 'stuclass'),
        'stumobile': _importCellByKey(row, 'stumobile'),
        'stuemail': _validEmail(_importCellByKey(row, 'stuemail')),
        'concession': _nullIfEmpty(_importCellByKey(row, 'concession')),
        'stuaddress': _nullIfEmpty(_importCellByKey(row, 'stuaddress')),
        'stucity': _nullIfEmpty(_importCellByKey(row, 'stucity')),
        'stustate': _nullIfEmpty(_importCellByKey(row, 'stustate')),
        'stucountry': _nullIfEmpty(_importCellByKey(row, 'stucountry')),
        'stupin': _nullIfEmpty(_importCellByKey(row, 'stupin')),
        'stubloodgrp': _nullIfEmpty(_importCellByKey(row, 'stubloodgrp')),
        'fathername': _nullIfEmpty(_importCellByKey(row, 'fathername')),
        'fathermobile': _nullIfEmpty(_importCellByKey(row, 'fathermobile')),
        'fatheroccupation': _nullIfEmpty(_importCellByKey(row, 'fatheroccupation')),
        'mothername': _nullIfEmpty(_importCellByKey(row, 'mothername')),
        'mothermobile': _nullIfEmpty(_importCellByKey(row, 'mothermobile')),
        'motheroccupation': _nullIfEmpty(_importCellByKey(row, 'motheroccupation')),
        'guardianname': _nullIfEmpty(_importCellByKey(row, 'guardianname')),
        'guardianmobile': _nullIfEmpty(_importCellByKey(row, 'guardianmobile')),
        'guardianoccupation': _nullIfEmpty(_importCellByKey(row, 'guardianoccupation')),
        'payincharge': _nullIfEmpty(_importCellByKey(row, 'payincharge')) ?? '-',
        'payinchargemob': _nullIfEmpty(_importCellByKey(row, 'payinchargemob')),
        'status': 'PENDING',
      });
    }

    if (stagingRows.isEmpty) {
      setState(() => _importStep = 3);
      return;
    }

    setState(() {});

    try {
      // 2. Bulk insert into staging table (batches of 200)
      for (int i = 0; i < stagingRows.length; i += 200) {
        final batch = stagingRows.sublist(i, (i + 200).clamp(0, stagingRows.length));
        await SupabaseService.client.from('student_import').insert(batch);
        setState(() {
          _importedCount = i + batch.length;
        });
      }

      // 3. Call DB function to move data to original tables
      setState(() {
        _importedCount = 0;
      });
      final result = await SupabaseService.client.rpc('process_student_import', params: {'p_ins_id': insId});

      if (result is List && result.isNotEmpty) {
        final r = result.first;
        _importedCount = (r['imported'] as num?)?.toInt() ?? 0;
        _skippedCount += (r['skipped'] as num?)?.toInt() ?? 0;
      }

      // 4. Fetch errors from staging table
      final errors = await SupabaseService.client
          .from('student_import')
          .select('imp_id, stuadmno, error_msg, status')
          .eq('ins_id', insId)
          .inFilter('status', ['ERROR', 'NO_PARENT']);
      for (final e in errors) {
        final status = e['status'];
        if (status == 'NO_PARENT') {
          _importErrors.add('Adm ${e['stuadmno']}: No payinchargemob - parent not linked');
        } else {
          _importErrors.add('Adm ${e['stuadmno']}: ${e['error_msg']}');
        }
      }

      // 5. Clean up processed staging rows
      await SupabaseService.client
          .from('student_import')
          .delete()
          .eq('ins_id', insId)
          .inFilter('status', ['DONE', 'ERROR', 'NO_PARENT']);

    } catch (e) {
      _importErrors.add('Import failed: $e');
    }

    setState(() => _importStep = 3);
    _loadDropdowns();
  }

  // ─── Import UI ──────────────────────────────────────────────────────────

  Widget _buildStudentImportSection() {
    if (_importStep == 2) return _buildImportProgressStep();
    if (_importStep == 3) return _buildImportDoneStep();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title bar
          Row(
            children: [
              Icon(Icons.upload_file_rounded, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('Import Students', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_importFileName != null)
                Text(_importFileName!, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _pickImportFile,
                icon: const Icon(Icons.folder_open_rounded, size: 16),
                label: const Text('Browse'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _exportStudentTemplate,
                icon: const Icon(Icons.table_chart_rounded, size: 16),
                label: const Text('Move to Excel'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF217346),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (_importErrorMsg != null) ...[
            const SizedBox(height: 8),
            Text(_importErrorMsg!, style: const TextStyle(color: AppColors.error, fontSize: 13)),
          ],
          const SizedBox(height: 12),

          // Data grid
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.border),
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.hardEdge,
              child: Scrollbar(
                controller: _importScrollController,
                thumbVisibility: true,
                child: SingleChildScrollView(
                  controller: _importScrollController,
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: 54 + _importGridKeys.fold<double>(0, (sum, k) => sum + _gridColWidth(k) + 1),
                    child: Column(
                      children: [
                        // Header row
                        Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF6C8EEF),
                            borderRadius: BorderRadius.only(
                              topLeft: Radius.circular(7),
                              topRight: Radius.circular(7),
                            ),
                          ),
                          child: Row(
                            children: [
                              _gridHeaderCell('S.No', width: 50, center: true),
                              _gridHeaderDivider(),
                              for (final key in _importGridKeys) ...[
                                _gridHeaderCell(_importGridLabels[key] ?? key, width: _gridColWidth(key)),
                                _gridHeaderDivider(),
                              ],
                            ],
                          ),
                        ),
                        // Data rows
                        Expanded(
                          child: _importRows.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.grid_on_rounded, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                                      const SizedBox(height: 8),
                                      const Text('No data loaded', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                      const SizedBox(height: 4),
                                      const Text('Click Browse to load a CSV or Excel file', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                    ],
                                  ),
                                )
                              : ListView.builder(
                                  itemCount: _importRows.length,
                                  itemBuilder: (context, index) {
                                    final row = _importRows[index];
                                    final isEven = index % 2 == 0;
                                    return Container(
                                      color: isEven ? Colors.white : AppColors.surface,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      child: Row(
                                        children: [
                                          _gridDataCell('${index + 1}', width: 50, center: true),
                                          for (final key in _importGridKeys)
                                            _gridDataCell(_importMappedCell(row, key), width: _gridColWidth(key)),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Bottom bar
          Row(
            children: [
              Text(
                '${_importRows.length} rows',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _importRows.isEmpty || _importValidated ? null : _validateImportData,
                icon: Icon(_importValidated ? Icons.check_circle : Icons.check_circle_outline, size: 16),
                label: Text(_importValidated ? 'Validated' : 'Validate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _importRows.isNotEmpty && !_importValidated ? Colors.orange : (_importValidated ? AppColors.success : Colors.grey),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: _importValidated ? _startStudentImport : null,
                icon: const Icon(Icons.save_rounded, size: 16),
                label: const Text('Save'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _resetImport,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                child: const Text('Close'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportProgressStep() {
    final progress = _totalCount > 0 ? (_importedCount + _skippedCount) / _totalCount : 0.0;
    return Center(
      child: Container(
        width: 400,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text('Importing... ${_importedCount + _skippedCount} / $_totalCount', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progress, backgroundColor: AppColors.border, valueColor: const AlwaysStoppedAnimation(AppColors.accent)),
            const SizedBox(height: 8),
            Text('$_importedCount imported, $_skippedCount skipped', style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          ],
        ),
      ),
    );
  }

  Widget _buildImportDoneStep() {
    return Center(
      child: Container(
        width: 500,
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 64, color: AppColors.success),
            const SizedBox(height: 16),
            const Text('Import Complete', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            Text('$_importedCount imported successfully, $_skippedCount skipped', style: const TextStyle(fontSize: 13)),
            if (_importErrors.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                height: 150,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView(
                  children: _importErrors.map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(e, style: const TextStyle(fontSize: 13, color: AppColors.error)),
                  )).toList(),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _resetImport,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }

  double _gridColWidth(String key) {
    switch (key) {
      case 'stuadmno': return 100;
      case 'stuname': return 160;
      case 'stugender': return 80;
      case 'studob': return 100;
      case 'stuadmdate': return 100;
      case 'stuclass': return 70;
      case 'stumobile': return 110;
      case 'stuemail': return 160;
      case 'concession': return 130;
      case 'stuaddress': return 160;
      case 'stucity': return 100;
      case 'stustate': return 100;
      case 'stucountry': return 100;
      case 'stupin': return 80;
      case 'stubloodgrp': return 90;
      case 'fathername': case 'mothername': case 'guardianname': return 140;
      case 'fathermobile': case 'mothermobile': case 'guardianmobile': return 120;
      case 'fatheroccupation': case 'motheroccupation': case 'guardianoccupation': return 120;
      case 'payincharge': return 130;
      case 'payinchargemob': return 120;
      default: return 110;
    }
  }

  Widget _gridHeaderCell(String text, {double? width, int flex = 1, bool center = false}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      child: Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
    );
    return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
  }

  Widget _gridHeaderDivider() {
    return Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.15));
  }

  Widget _gridDataCell(String text, {double? width, int flex = 1, bool center = false}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      alignment: center ? Alignment.center : Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
      ),
      child: Text(text, style: const TextStyle(fontSize: 13, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
    );
    return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
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
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.black)),
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

// _ExcelImportDialog removed — import is now inline grid in _StudentsScreenState
