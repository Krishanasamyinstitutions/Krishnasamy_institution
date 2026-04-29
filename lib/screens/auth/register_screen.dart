import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/app_theme.dart';
import '../../services/supabase_service.dart';

import '../../widgets/app_icon.dart';
class RegisterScreen extends StatefulWidget {
  final VoidCallback? onRegistered;
  const RegisterScreen({super.key, this.onRegistered});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  final _formKeys = [GlobalKey<FormState>(), GlobalKey<FormState>(), GlobalKey<FormState>()];

  // Step 1: Institution Info
  String? _institutionType;
  String _institutionRecognized = 'Yes';
  DateTime? _institutionStartDate;
  File? _logoFile;
  final _institutionNameController = TextEditingController();
  final _institutionShortNameController = TextEditingController();
  final _institutionCodeController = TextEditingController();
  final _authorizedUsernameController = TextEditingController();
  final _designationController = TextEditingController();
  final _mobileNumberController = TextEditingController();

  final List<String> _institutionTypes = [
    'Schools (Primary, Secondary, Higher Secondary)',
    'Colleges',
    'Universities',
    'Polytechnic Institutions',
    'Vocational Training Centers',
    'Coaching Institutes',
  ];

  // Step 2: Affiliation & Address
  DateTime? _affiliationStartYear;
  final _affiliationController = TextEditingController();
  final _affiliationNumberController = TextEditingController();
  final _address1Controller = TextEditingController();
  final _address2Controller = TextEditingController();
  final _address3Controller = TextEditingController();
  final _pinCodeController = TextEditingController();
  final _cityController = TextEditingController();
  final _stateController = TextEditingController();
  final _countryController = TextEditingController();
  final _emailController = TextEditingController();

  // Academic Year
  final _yearLabelController = TextEditingController();
  DateTime? _yearStartDate;
  DateTime? _yearEndDate;

  // Step 3: Account Setup
  String _adminDesignation = 'Principal';
  final List<String> _designationOptions = [
    'Principal', 'Vice Principal', 'Director', 'Chairman',
    'Head Master', 'Administrator', 'Manager',
  ];
  final _adminNameController = TextEditingController();
  final _adminEmailController = TextEditingController();
  final _adminPhoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  DateTime? _adminDob;
  bool _obscurePassword = true;
  bool _obscureConfirm = true;
  bool _isCreating = false;

  @override
  void dispose() {
    _pageController.dispose();
    _institutionNameController.dispose();
    _institutionShortNameController.dispose();
    _institutionCodeController.dispose();
    _authorizedUsernameController.dispose();
    _designationController.dispose();
    _mobileNumberController.dispose();
    _affiliationController.dispose();
    _affiliationNumberController.dispose();
    _address1Controller.dispose();
    _address2Controller.dispose();
    _address3Controller.dispose();
    _pinCodeController.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _countryController.dispose();
    _emailController.dispose();
    _yearLabelController.dispose();
    _adminNameController.dispose();
    _adminEmailController.dispose();
    _adminPhoneController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    _pageController.animateToPage(step, duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    setState(() => _currentStep = step);
  }

  String? _logoFileName;

  Future<void> _pickLogo() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['png', 'jpg', 'jpeg'],
    );
    if (result != null && result.files.single.path != null) {
      final file = result.files.single;
      final ext = file.extension?.toLowerCase() ?? '';
      if (!['png', 'jpg', 'jpeg'].contains(ext)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Only PNG, JPG, JPEG formats are allowed'), backgroundColor: Colors.red),
          );
        }
        return;
      }
      setState(() {
        _logoFile = File(file.path!);
        _logoFileName = file.name;
      });
    }
  }

  Future<void> _handleRegister() async {
    if (!_formKeys[2].currentState!.validate()) return;

    if (_passwordController.text != _confirmPasswordController.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Passwords do not match'), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final itIdMap = {
        'Schools (Primary, Secondary, Higher Secondary)': 1,
        'Colleges': 2,
        'Universities': 3,
        'Polytechnic Institutions': 4,
        'Vocational Training Centers': 5,
        'Coaching Institutes': 6,
      };

      final yrLabel = _yearLabelController.text.trim().isNotEmpty
          ? _yearLabelController.text.trim()
          : '${DateTime.now().year}-${DateTime.now().year + 1}';
      final yrStaDate = _yearStartDate ?? DateTime(DateTime.now().year, 6, 1);
      final yrEndDate = _yearEndDate ?? DateTime(DateTime.now().year + 1, 5, 31);

      // Single atomic RPC call — creates institution rows AND schema in one transaction.
      // If validation fails or schema creation errors out, the database rolls back
      // every insert so no partial data is left behind.
      final result = await SupabaseService.client.rpc('register_institution', params: {
        'p_insname': _institutionNameController.text.trim(),
        'p_inscode': _institutionCodeController.text.trim(),
        'p_inshortname': _institutionShortNameController.text.trim(),
        'p_insstadate': (_institutionStartDate ?? DateTime.now()).toIso8601String().split('T').first,
        'p_insautusername': _authorizedUsernameController.text.trim(),
        'p_insdesignation': _designationController.text.trim().isNotEmpty ? _designationController.text.trim() : 'Principal',
        'p_insmobno': _mobileNumberController.text.trim(),
        'p_insmail': _emailController.text.trim(),
        'p_it_id': itIdMap[_institutionType] ?? 1,
        'p_insrecognised': _institutionRecognized == 'Yes' ? 'Y' : 'N',
        'p_insaffliation': _affiliationController.text.trim(),
        'p_insaffno': _affiliationNumberController.text.trim(),
        'p_insaffstayear': _affiliationStartYear?.year.toString() ?? '',
        'p_insaddress1': _address1Controller.text.trim(),
        'p_insaddress2': _address2Controller.text.trim(),
        'p_insaddress3': _address3Controller.text.trim(),
        'p_inscity': _cityController.text.trim(),
        'p_insstate': _stateController.text.trim(),
        'p_inscountry': _countryController.text.trim(),
        'p_inspincode': _pinCodeController.text.trim(),
        'p_yrlabel': yrLabel,
        'p_yrstadate': yrStaDate.toIso8601String().split('T').first,
        'p_yrenddate': yrEndDate.toIso8601String().split('T').first,
        'p_adminname': _adminNameController.text.trim(),
        'p_adminemail': _adminEmailController.text.trim(),
        'p_adminphone': _adminPhoneController.text.trim(),
        'p_adminpassword': _passwordController.text,
        'p_admindob': _adminDob != null ? _adminDob!.toIso8601String().split('T').first : '2000-01-01',
        'p_admindesignation': _adminDesignation,
      });

      final regResult = result is Map ? result : (result is List && result.isNotEmpty ? result.first : null);
      if (regResult == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Registration failed'), backgroundColor: Colors.red),
          );
          setState(() => _isCreating = false);
        }
        return;
      }

      final schemaName = regResult['schema']?.toString() ?? '';
      debugPrint('Registered ins_id=${regResult['ins_id']}, schema="$schemaName"');

      // Try to expose schema to API (best-effort — fails silently on free tier)
      if (schemaName.isNotEmpty) {
        try {
          await SupabaseService.client.rpc('expose_schema', params: {
            'p_schema': schemaName,
          });
          debugPrint('Schema "$schemaName" exposed to API');
        } catch (e) {
          debugPrint('expose_schema skipped (run manually in SQL Editor): $e');
        }
      }

      // Create the per-institution student photo bucket. Runs via a
      // SECURITY DEFINER RPC so anon can trigger it; logs but doesn't
      // block registration if Supabase can't create the bucket.
      if (regResult['inscode'] != null) {
        try {
          await SupabaseService.client.rpc('ensure_student_photo_bucket', params: {
            'p_inscode': regResult['inscode'].toString(),
          });
          debugPrint('Photo bucket ready for inscode=${regResult['inscode']}');
        } catch (e) {
          debugPrint('ensure_student_photo_bucket skipped: $e');
        }
      }

      // Upload logo if selected
      if (_logoFile != null && regResult['inscode'] != null) {
        try {
          final inscode = regResult['inscode'].toString();
          final ext = _logoFile!.path.split('.').last.toLowerCase();
          final path = 'logos/$inscode.$ext';
          await SupabaseService.client.storage.from('InstitutionLogos').upload(
            path,
            _logoFile!,
            fileOptions: const FileOptions(upsert: true),
          );
          final logoUrl = SupabaseService.client.storage.from('InstitutionLogos').getPublicUrl(path);
          await SupabaseService.client.from('institution').update({'inslogo': logoUrl}).eq('ins_id', regResult['ins_id']);
          debugPrint('Logo uploaded: $logoUrl');
        } catch (e) {
          debugPrint('Logo upload failed: $e');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Institution created, but logo upload failed: $e'),
                backgroundColor: Colors.orange,
                duration: const Duration(seconds: 6),
              ),
            );
          }
        }
      }

      // Show success and stay on super admin dashboard
      if (mounted) {
        setState(() => _isCreating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Institution created successfully!'), backgroundColor: Colors.green),
        );
        widget.onRegistered?.call();
      }
    } catch (e) {
      debugPrint('Registration error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _pickInstitutionStartDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _institutionStartDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _institutionStartDate = picked);
  }

  Future<void> _pickAffiliationStartYear() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _affiliationStartYear ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      helpText: 'Select Affiliation Start Year',
    );
    if (picked != null) setState(() => _affiliationStartYear = DateTime(picked.year));
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Milestone progress bar
          _buildMilestoneProgress(context),

          // Page slider
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (i) => setState(() => _currentStep = i),
              children: [
                _buildStep1(),
                _buildStep2(),
                _buildStep3(),
              ],
            ),
          ),

          // Bottom navigation
          Padding(
            padding: EdgeInsets.fromLTRB(32.w, 0, 32.w, 16.h),
            child: Row(
              children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    onPressed: () => _goToStep(_currentStep - 1),
                    icon: AppIcon.linear('Chevron Left', size: 18),
                    label: const Text('Previous', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(140, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
                const Spacer(),
                if (_currentStep < 2)
                  ElevatedButton.icon(
                    onPressed: () => _goToStep(_currentStep + 1),
                    icon: const Text('Next', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                    label: AppIcon.linear('Chevron Right', size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      minimumSize: const Size(140, 52),
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMilestoneProgress(BuildContext context) {
    final steps = [
      {'icon': 'building', 'label': 'Institution Info'},
      {'icon': 'location', 'label': 'Affiliation & Address'},
      {'icon': 'lock', 'label': 'Account Setup'},
    ];

    Color stateColor(int stepIndex) {
      if (stepIndex < _currentStep) return AppColors.success;
      if (stepIndex == _currentStep) return AppColors.primary;
      return AppColors.textSecondary.withValues(alpha: 0.4);
    }

    final isMobile = MediaQuery.of(context).size.width < 600;
    final circleSize = isMobile ? 36.0 : 40.0;
    final iconSize = isMobile ? 18.0 : 20.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(isMobile ? 16 : 32.w, 20.h, isMobile ? 16 : 32.w, 8.h),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 24.w, vertical: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            final stepBefore = index ~/ 2;
            final isDone = stepBefore < _currentStep;
            final isActiveSegment = stepBefore == _currentStep - 1 || stepBefore == _currentStep;
            return Expanded(
              child: Padding(
                padding: EdgeInsets.only(top: circleSize / 2 - 1.5),
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.success
                        : isActiveSegment
                            ? AppColors.primary.withValues(alpha: 0.4)
                            : AppColors.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final step = steps[stepIndex];
          final isActive = stepIndex == _currentStep;
          final isDone = stepIndex < _currentStep;
          final color = stateColor(stepIndex);

          return GestureDetector(
            onTap: () => _goToStep(stepIndex),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Circle with icon
                Container(
                  width: circleSize,
                  height: circleSize,
                  decoration: BoxDecoration(
                    color: isDone || isActive ? color : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: color,
                      width: isActive ? 2 : 1.5,
                    ),
                  ),
                  child: Center(
                    child: isDone
                        ? AppIcon('tick-circle', size: iconSize, color: Colors.white)
                        : AppIcon(
                            step['icon'] as String,
                            size: iconSize,
                            color: isActive ? Colors.white : color,
                          ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'STEP ${stepIndex + 1}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isMobile ? (step['label'] as String).split(' ').first : step['label'] as String,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: isMobile ? 12 : 13,
                    color: isActive || isDone ? AppColors.textPrimary : AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          );
        }),
      ),
      ),
    );
  }

  // Step 1: Institution Information
  Widget _buildStep1() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32.w, vertical: 20.h),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 16 : 20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Form(
          key: _formKeys[0],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: EdgeInsets.all(8.w),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10.r),
                    ),
                    child: AppIcon('building', color: AppColors.accent, size: 18),
                  ),
                  SizedBox(width: 12.w),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Institution Information',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                      SizedBox(height: 2.h),
                      Text('Enter the basic details about your institution',
                          style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                    ],
                  ),
                ],
              ),
              SizedBox(height: 20.h),

              _formRow(context, [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Type'),
                  SizedBox(
                    height: 48,
                    child: DropdownButtonFormField<String>(
                      initialValue: _institutionType,
                      decoration: _inputDec('Select institution type'),
                      isExpanded: true,
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                      items: _institutionTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                      onChanged: (v) => setState(() => _institutionType = v),
                    ),
                  ),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Name *'),
                  TextFormField(controller: _institutionNameController, decoration: _inputDec('Enter institution name'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                ]),
              ]),
              SizedBox(height: 16.h),

              // Logo picker + Short Name + Institution Code
              _formRow(context, [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _fieldLabel('Institution Logo'),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _pickLogo,
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          height: 48,
                          padding: EdgeInsets.symmetric(horizontal: 14.w),
                          decoration: BoxDecoration(
                            color: _kFieldFill,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: _logoFile != null
                              ? Row(
                                  children: [
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(_logoFile!, width: 36, height: 36, fit: BoxFit.cover),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text('Change',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textPrimary,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                    AppIcon('edit-2', size: 16, color: AppColors.primary),
                                  ],
                                )
                              : Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: AppColors.accent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: AppIcon('camera', size: 16, color: AppColors.accent),
                                    ),
                                    const SizedBox(width: 10),
                                    Flexible(
                                      child: Text('Upload Logo',
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: AppColors.textSecondary,
                                              fontWeight: FontWeight.w600)),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Short Name *'),
                  TextFormField(controller: _institutionShortNameController, decoration: _inputDec('e.g. KCET'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Code *'),
                  TextFormField(controller: _institutionCodeController, decoration: _inputDec('Enter code'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                ]),
              ]),
              SizedBox(height: 16.h),

              _formRow(context, [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Start Date'),
                  InkWell(
                    onTap: _pickInstitutionStartDate,
                    child: InputDecorator(
                      decoration: _inputDec('Select date').copyWith(suffixIcon: AppIcon('calendar-1', size: 18, color: AppColors.textSecondary)),
                      child: Text(
                        _institutionStartDate != null ? _formatDate(_institutionStartDate!) : 'Select date',
                        style: TextStyle(color: _institutionStartDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13, fontWeight: _institutionStartDate != null ? FontWeight.w600 : FontWeight.normal),
                      ),
                    ),
                  ),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Authorized Username'),
                  TextFormField(controller: _authorizedUsernameController, decoration: _inputDec('Enter authorized username'), style: _fieldStyle()),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Designation'),
                  TextFormField(controller: _designationController, decoration: _inputDec('Enter designation'), style: _fieldStyle()),
                ]),
              ]),
              SizedBox(height: 16.h),

              _formRow(context, [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Mobile Number'),
                  TextFormField(controller: _mobileNumberController, decoration: _inputDec('Enter mobile number'), style: _fieldStyle(), keyboardType: TextInputType.phone),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Recognized'),
                  SizedBox(
                    height: 48,
                    child: DropdownButtonFormField<String>(
                      initialValue: _institutionRecognized,
                      decoration: _inputDec('Select'),
                      style: _fieldStyle(),
                      items: const [DropdownMenuItem(value: 'Yes', child: Text('Yes')), DropdownMenuItem(value: 'No', child: Text('No'))],
                      onChanged: (v) { if (v != null) setState(() => _institutionRecognized = v); },
                    ),
                  ),
                ]),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Email *'),
                  TextFormField(
                    controller: _emailController,
                    decoration: _inputDec('Enter email address'),
                    style: _fieldStyle(),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Email is required' : null,
                  ),
                ]),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // Step 2: Affiliation & Address
  Widget _buildStep2() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32.w, vertical: 20.h),
      child: Column(
        children: [
          // Affiliation card
          Container(
            padding: EdgeInsets.all(isMobile ? 16 : 20.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Form(
              key: _formKeys[1],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: EdgeInsets.all(8.w),
                        decoration: BoxDecoration(
                          color: AppColors.accent.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: AppIcon('verify', color: AppColors.accent, size: 18),
                      ),
                      SizedBox(width: 12.w),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Affiliation Information',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                          SizedBox(height: 2.h),
                          Text('Enter affiliation and recognition details',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                        ],
                      ),
                    ],
                  ),
                  SizedBox(height: 20.h),

                  _formRow(context, [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Institution Affiliation'),
                      TextFormField(controller: _affiliationController, decoration: _inputDec('Enter affiliation'), style: _fieldStyle()),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Affiliation Number'),
                      TextFormField(controller: _affiliationNumberController, decoration: _inputDec('Enter affiliation number'), style: _fieldStyle()),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Affiliation Start Year'),
                      InkWell(
                        onTap: _pickAffiliationStartYear,
                        child: InputDecorator(
                          decoration: _inputDec('Select year').copyWith(suffixIcon: AppIcon('calendar-1', size: 18, color: AppColors.textSecondary)),
                          child: Text(
                            _affiliationStartYear != null ? '${_affiliationStartYear!.year}' : 'Select year',
                            style: TextStyle(color: _affiliationStartYear != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13, fontWeight: _affiliationStartYear != null ? FontWeight.w600 : FontWeight.normal),
                          ),
                        ),
                      ),
                    ]),
                  ]),
                ],
              ),
            ),
          ),
          SizedBox(height: 20.h),

          // Address card
          Container(
            padding: EdgeInsets.all(isMobile ? 16 : 20.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: AppIcon('location', color: AppColors.accent, size: 18),
                    ),
                    SizedBox(width: 12.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Address',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text('Enter the institution address details',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 20.h),

                _formRow(context, [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Address Line 1 *'),
                    TextFormField(controller: _address1Controller, decoration: _inputDec('Enter address line 1'), style: _fieldStyle()),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Address Line 2'),
                    TextFormField(controller: _address2Controller, decoration: _inputDec('Enter address line 2'), style: _fieldStyle()),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Address Line 3'),
                    TextFormField(controller: _address3Controller, decoration: _inputDec('Enter address line 3'), style: _fieldStyle()),
                  ]),
                ]),
                SizedBox(height: 14.h),
                _formRow(context, [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Pin Code'),
                    TextFormField(controller: _pinCodeController, decoration: _inputDec('Enter pin code'), style: _fieldStyle(), keyboardType: TextInputType.number),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('City'),
                    TextFormField(controller: _cityController, decoration: _inputDec('Enter city'), style: _fieldStyle()),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('State'),
                    TextFormField(controller: _stateController, decoration: _inputDec('Enter state'), style: _fieldStyle()),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Country'),
                    TextFormField(controller: _countryController, decoration: _inputDec('Enter country'), style: _fieldStyle()),
                  ]),
                ]),
              ],
            ),
          ),
          SizedBox(height: 20.h),

          // Academic Year card
          Container(
            padding: EdgeInsets.all(isMobile ? 16 : 20.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: AppIcon('calendar-1', color: AppColors.accent, size: 18),
                    ),
                    SizedBox(width: 12.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Academic Year',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text('Set up the academic year for your institution',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 20.h),

                _formRow(context, [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Year Label *'),
                    TextFormField(
                      controller: _yearLabelController,
                      decoration: _inputDec('e.g. 2025-2026'),
                      style: _fieldStyle(),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Start Date *'),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(context: context, initialDate: _yearStartDate ?? DateTime(DateTime.now().year, 6, 1), firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (picked != null) setState(() => _yearStartDate = picked);
                      },
                      child: InputDecorator(
                        decoration: _inputDec('Select start date').copyWith(suffixIcon: AppIcon('calendar-1', size: 18, color: AppColors.textSecondary)),
                        child: Text(
                          _yearStartDate != null ? _formatDate(_yearStartDate!) : 'Select start date',
                          style: TextStyle(color: _yearStartDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
                        ),
                      ),
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('End Date *'),
                    InkWell(
                      onTap: () async {
                        final picked = await showDatePicker(context: context, initialDate: _yearEndDate ?? DateTime(DateTime.now().year + 1, 5, 31), firstDate: DateTime(2000), lastDate: DateTime(2100));
                        if (picked != null) setState(() => _yearEndDate = picked);
                      },
                      child: InputDecorator(
                        decoration: _inputDec('Select end date').copyWith(suffixIcon: AppIcon('calendar-1', size: 18, color: AppColors.textSecondary)),
                        child: Text(
                          _yearEndDate != null ? _formatDate(_yearEndDate!) : 'Select end date',
                          style: TextStyle(color: _yearEndDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
                        ),
                      ),
                    ),
                  ]),
                ]),
              ],
            ),
          ),
          SizedBox(height: 20.h),
        ],
      ),
    );
  }

  // Step 3: Account Setup
  Widget _buildStep3() {
    final isMobile = MediaQuery.of(context).size.width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 16 : 32.w, vertical: 20.h),
      child: Container(
        padding: EdgeInsets.all(isMobile ? 16 : 20.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Form(
          key: _formKeys[2],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: EdgeInsets.all(8.w),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10.r),
                      ),
                      child: AppIcon('lock', color: AppColors.accent, size: 18),
                    ),
                    SizedBox(width: 12.w),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Account Setup',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                        SizedBox(height: 2.h),
                        Text('Create an admin account for your institution',
                            style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ],
                ),
                SizedBox(height: 20.h),

                _formRow(context, [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Name *'),
                    TextFormField(
                      controller: _adminNameController,
                      decoration: _inputDec('Enter admin name').copyWith(
                        prefixIcon: AppIcon('user', size: 14, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Designation *'),
                    SizedBox(
                      height: 48,
                      child: DropdownButtonFormField<String>(
                        initialValue: _adminDesignation,
                        decoration: _inputDec('Select designation').copyWith(
                          prefixIcon: AppIcon('personalcard', size: 14, color: AppColors.textSecondary),
                        ),
                        style: _fieldStyle(),
                        items: _designationOptions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                        onChanged: (v) => setState(() => _adminDesignation = v ?? 'Principal'),
                        validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                      ),
                    ),
                  ]),
                ]),
                SizedBox(height: 14.h),

                _formRow(context, [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Email *'),
                    TextFormField(
                      controller: _adminEmailController,
                      decoration: _inputDec('Enter email').copyWith(
                        prefixIcon: AppIcon('sms', size: 12, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Email is required' : null,
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Phone *'),
                    TextFormField(
                      controller: _adminPhoneController,
                      decoration: _inputDec('Enter phone').copyWith(
                        prefixIcon: AppIcon('call', size: 12, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Phone is required' : null,
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Date of Birth *'),
                    SizedBox(
                      height: 48,
                      child: InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _adminDob ?? DateTime(1990),
                            firstDate: DateTime(1940),
                            lastDate: DateTime.now(),
                          );
                          if (picked != null) setState(() => _adminDob = picked);
                        },
                        child: InputDecorator(
                          decoration: _inputDec('Select date of birth').copyWith(
                            prefixIcon: AppIcon('calendar-1', size: 12, color: AppColors.textSecondary),
                          ),
                          child: Text(
                            _adminDob != null
                                ? '${_adminDob!.day.toString().padLeft(2, '0')}/${_adminDob!.month.toString().padLeft(2, '0')}/${_adminDob!.year}'
                                : 'Select date of birth',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _adminDob != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6)),
                          ),
                        ),
                      ),
                    ),
                  ]),
                ]),
                SizedBox(height: 14.h),

                _formRow(context, [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Password *'),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      decoration: _inputDec('Enter password').copyWith(
                        prefixIcon: AppIcon('lock', size: 12, color: AppColors.textSecondary),
                        suffixIcon: IconButton(
                          icon: AppIcon(_obscurePassword ? 'eye-slash' : 'eye', size: 12, color: AppColors.textSecondary),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      style: _fieldStyle(),
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'Password is required';
                        if (v.length < 6) return 'Password must be at least 6 characters';
                        return null;
                      },
                    ),
                  ]),
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Confirm Password *'),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: _obscureConfirm,
                      decoration: _inputDec('Re-enter password').copyWith(
                        prefixIcon: AppIcon('lock', size: 12, color: AppColors.textSecondary),
                        suffixIcon: IconButton(
                          icon: AppIcon(_obscureConfirm ? 'eye-slash' : 'eye', size: 12, color: AppColors.textSecondary),
                          onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                        ),
                      ),
                      style: _fieldStyle(),
                      validator: (v) {
                        if (v != _passwordController.text) return 'Passwords do not match';
                        return null;
                      },
                    ),
                  ]),
                ]),
                SizedBox(height: 32.h),

                Center(
                  child: SizedBox(
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: _isCreating ? null : _handleRegister,
                      icon: _isCreating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : AppIcon('tick-circle', size: 18, color: Colors.white),
                      label: Text(_isCreating ? 'Creating...' : 'Create Institution', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8.h),
      child: Text(label,
          style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
    );
  }

  // Renders [fields] as a Row on desktop and stacks them vertically on mobile.
  Widget _formRow(BuildContext context, List<Widget> fields, {double gap = 14, List<int>? flexes}) {
    final isMobile = MediaQuery.of(context).size.width < 600;
    if (isMobile) {
      final children = <Widget>[];
      for (var i = 0; i < fields.length; i++) {
        children.add(fields[i]);
        if (i < fields.length - 1) children.add(SizedBox(height: gap));
      }
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: children);
    }
    final children = <Widget>[];
    for (var i = 0; i < fields.length; i++) {
      children.add(Expanded(flex: flexes != null && i < flexes.length ? flexes[i] : 1, child: fields[i]));
      if (i < fields.length - 1) children.add(SizedBox(width: gap));
    }
    return Row(children: children);
  }

  TextStyle _fieldStyle() => TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary);

  static const Color _kFieldFill = Color(0xFFF3F4F6);

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.55), fontSize: 13, fontWeight: FontWeight.w500),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
    errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.error)),
    focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: AppColors.error, width: 1.5)),
    filled: true,
    fillColor: Colors.white,
    isDense: false,
    constraints: const BoxConstraints(minHeight: 48, maxHeight: 48),
    suffixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 16, maxHeight: 16),
    prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 16, maxHeight: 16),
  );
}
