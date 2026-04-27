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
                    label: const Text('Previous'),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 16.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                const Spacer(),
                if (_currentStep < 2)
                  ElevatedButton.icon(
                    onPressed: () => _goToStep(_currentStep + 1),
                    icon: const Text('Next'),
                    label: AppIcon.linear('Chevron Right', size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 16.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
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

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 20.h),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: List.generate(steps.length * 2 - 1, (index) {
          if (index.isOdd) {
            // Connector line
            final stepBefore = index ~/ 2;
            final isDone = stepBefore < _currentStep;
            return Expanded(
              child: Container(
                height: 3,
                margin: EdgeInsets.symmetric(horizontal: 4.w),
                decoration: BoxDecoration(
                  color: isDone ? AppColors.accent : AppColors.border,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            );
          }

          final stepIndex = index ~/ 2;
          final step = steps[stepIndex];
          final isActive = stepIndex == _currentStep;
          final isDone = stepIndex < _currentStep;

          return GestureDetector(
            onTap: () => _goToStep(stepIndex),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40.w,
                  height: 40.h,
                  decoration: BoxDecoration(
                    color: isDone
                        ? AppColors.accent
                        : isActive
                            ? AppColors.accent.withValues(alpha: 0.15)
                            : AppColors.surface,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(
                      color: isDone || isActive ? AppColors.accent : AppColors.border,
                      width: isActive ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: isDone
                        ? AppIcon('tick-circle', size: 20, color: Colors.white)
                        : AppIcon(
                            step['icon'] as String,
                            size: 20,
                            color: isActive ? AppColors.accent : AppColors.textSecondary,
                          ),
                  ),
                ),
                SizedBox(width: 8.w),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Step ${stepIndex + 1}',
                      style: TextStyle(
                        fontSize: 10.sp,
                        color: isActive || isDone ? AppColors.accent : AppColors.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      step['label'] as String,
                      style: TextStyle(
                        fontSize: 12.sp,
                        color: isActive ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // Step 1: Institution Information
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 20.h),
      child: Container(
        padding: EdgeInsets.all(28.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Form(
          key: _formKeys[0],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                AppIcon('building', color: AppColors.accent, size: 18),
                SizedBox(width: 10.w),
                Text('Institution Information', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700)),
              ]),
              SizedBox(height: 6.h),
              Text('Enter the basic details about your institution', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
              const Divider(height: 28, color: AppColors.border),

              _fieldLabel('Institution Type'),
              DropdownButtonFormField<String>(
                initialValue: _institutionType,
                decoration: _inputDec('Select institution type'),
                isExpanded: true,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp, color: AppColors.textPrimary),
                items: _institutionTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _institutionType = v),
              ),
              SizedBox(height: 16.h),

              // Logo picker
              _fieldLabel('Institution Logo'),
              SizedBox(height: 6.h),
              Row(
                children: [
                  GestureDetector(
                    onTap: _pickLogo,
                    child: Container(
                      width: 80.w, height: 80.h,
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(color: AppColors.border, width: 1.5),
                      ),
                      child: _logoFile != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(11.r),
                              child: Image.file(_logoFile!, fit: BoxFit.cover, width: 80.w, height: 80.h),
                            )
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                AppIcon.linear('gallery-add', size: 28, color: AppColors.textSecondary.withValues(alpha: 0.5)),
                                SizedBox(height: 4.h),
                                Text('Upload', style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary.withValues(alpha: 0.5))),
                              ],
                            ),
                    ),
                  ),
                  SizedBox(width: 16.w),
                  if (_logoFileName != null) ...[
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_logoFileName!, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis),
                        SizedBox(height: 2.h),
                        Text('PNG, JPG, JPEG only', style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary.withValues(alpha: 0.5))),
                      ],
                    ),
                    SizedBox(width: 16.w),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _fieldLabel('Institution Name *'),
                            TextFormField(controller: _institutionNameController, decoration: _inputDec('Enter institution name'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                          ])),
                          SizedBox(width: 14.w),
                          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _fieldLabel('Short Name *'),
                            TextFormField(controller: _institutionShortNameController, decoration: _inputDec('e.g. KCET'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                          ])),
                          SizedBox(width: 14.w),
                          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _fieldLabel('Institution Code *'),
                            TextFormField(controller: _institutionCodeController, decoration: _inputDec('Enter code'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                          ])),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16.h),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Start Date'),
                  InkWell(
                    onTap: _pickInstitutionStartDate,
                    child: InputDecorator(
                      decoration: _inputDec('Select date').copyWith(suffixIcon: AppIcon('calendar-1', size: 18, color: AppColors.textSecondary)),
                      child: Text(
                        _institutionStartDate != null ? _formatDate(_institutionStartDate!) : 'Select date',
                        style: TextStyle(color: _institutionStartDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13.sp, fontWeight: _institutionStartDate != null ? FontWeight.w600 : FontWeight.normal),
                      ),
                    ),
                  ),
                ])),
                SizedBox(width: 14.w),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Authorized Username'),
                  TextFormField(controller: _authorizedUsernameController, decoration: _inputDec('Enter authorized username'), style: _fieldStyle()),
                ])),
                SizedBox(width: 14.w),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Designation'),
                  TextFormField(controller: _designationController, decoration: _inputDec('Enter designation'), style: _fieldStyle()),
                ])),
              ]),
              SizedBox(height: 16.h),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Mobile Number'),
                  TextFormField(controller: _mobileNumberController, decoration: _inputDec('Enter mobile number'), style: _fieldStyle(), keyboardType: TextInputType.phone),
                ])),
                SizedBox(width: 14.w),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Recognized'),
                  DropdownButtonFormField<String>(
                    initialValue: _institutionRecognized,
                    decoration: _inputDec('Select'),
                    style: _fieldStyle(),
                    items: const [DropdownMenuItem(value: 'Yes', child: Text('Yes')), DropdownMenuItem(value: 'No', child: Text('No'))],
                    onChanged: (v) { if (v != null) setState(() => _institutionRecognized = v); },
                  ),
                ])),
                SizedBox(width: 14.w),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Email *'),
                  TextFormField(
                    controller: _emailController,
                    decoration: _inputDec('Enter email address'),
                    style: _fieldStyle(),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) => v == null || v.trim().isEmpty ? 'Email is required' : null,
                  ),
                ])),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  // Step 2: Affiliation & Address
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 20.h),
      child: Column(
        children: [
          // Affiliation card
          Container(
            padding: EdgeInsets.all(28.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Form(
              key: _formKeys[1],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    AppIcon('verify', color: AppColors.accent, size: 18),
                    SizedBox(width: 10.w),
                    Text('Affiliation Information', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700)),
                  ]),
                  SizedBox(height: 6.h),
                  Text('Enter affiliation and recognition details', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  const Divider(height: 28, color: AppColors.border),

                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Institution Affiliation'),
                      TextFormField(controller: _affiliationController, decoration: _inputDec('Enter affiliation'), style: _fieldStyle()),
                    ])),
                    SizedBox(width: 14.w),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Affiliation Number'),
                      TextFormField(controller: _affiliationNumberController, decoration: _inputDec('Enter affiliation number'), style: _fieldStyle()),
                    ])),
                    SizedBox(width: 14.w),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Affiliation Start Year'),
                      InkWell(
                        onTap: _pickAffiliationStartYear,
                        child: InputDecorator(
                          decoration: _inputDec('Select year').copyWith(suffixIcon: AppIcon('calendar-1', size: 18, color: AppColors.textSecondary)),
                          child: Text(
                            _affiliationStartYear != null ? '${_affiliationStartYear!.year}' : 'Select year',
                            style: TextStyle(color: _affiliationStartYear != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13.sp, fontWeight: _affiliationStartYear != null ? FontWeight.w600 : FontWeight.normal),
                          ),
                        ),
                      ),
                    ])),
                  ]),
                ],
              ),
            ),
          ),
          SizedBox(height: 20.h),

          // Address card
          Container(
            padding: EdgeInsets.all(28.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  AppIcon('location', color: AppColors.accent, size: 18),
                  SizedBox(width: 10.w),
                  Text('Address', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700)),
                ]),
                SizedBox(height: 6.h),
                Text('Enter the institution address details', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                const Divider(height: 28, color: AppColors.border),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Address Line 1 *'),
                    TextFormField(controller: _address1Controller, decoration: _inputDec('Enter address line 1'), style: _fieldStyle()),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Address Line 2'),
                    TextFormField(controller: _address2Controller, decoration: _inputDec('Enter address line 2'), style: _fieldStyle()),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Address Line 3'),
                    TextFormField(controller: _address3Controller, decoration: _inputDec('Enter address line 3'), style: _fieldStyle()),
                  ])),
                ]),
                SizedBox(height: 14.h),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Pin Code'),
                    TextFormField(controller: _pinCodeController, decoration: _inputDec('Enter pin code'), style: _fieldStyle(), keyboardType: TextInputType.number),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('City'),
                    TextFormField(controller: _cityController, decoration: _inputDec('Enter city'), style: _fieldStyle()),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('State'),
                    TextFormField(controller: _stateController, decoration: _inputDec('Enter state'), style: _fieldStyle()),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Country'),
                    TextFormField(controller: _countryController, decoration: _inputDec('Enter country'), style: _fieldStyle()),
                  ])),
                ]),
              ],
            ),
          ),
          SizedBox(height: 20.h),

          // Academic Year card
          Container(
            padding: EdgeInsets.all(28.w),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  AppIcon('calendar-1', color: AppColors.accent, size: 18),
                  SizedBox(width: 10.w),
                  Text('Academic Year', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700)),
                ]),
                SizedBox(height: 6.h),
                Text('Set up the academic year for your institution', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                const Divider(height: 28, color: AppColors.border),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Year Label *'),
                    TextFormField(
                      controller: _yearLabelController,
                      decoration: _inputDec('e.g. 2025-2026'),
                      style: _fieldStyle(),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
                    ),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                          style: TextStyle(color: _yearStartDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13.sp),
                        ),
                      ),
                    ),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                          style: TextStyle(color: _yearEndDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13.sp),
                        ),
                      ),
                    ),
                  ])),
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
    return SingleChildScrollView(
      padding: EdgeInsets.symmetric(horizontal: 32.w, vertical: 20.h),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: EdgeInsets.all(32.w),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Form(
            key: _formKeys[2],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  AppIcon('lock', color: AppColors.accent, size: 18),
                  SizedBox(width: 10.w),
                  Text('Account Setup', style: TextStyle(fontSize: 17.sp, fontWeight: FontWeight.w700)),
                ]),
                SizedBox(height: 6.h),
                Text('Create an admin account for your institution', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                const Divider(height: 28, color: AppColors.border),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Name *'),
                    TextFormField(
                      controller: _adminNameController,
                      decoration: _inputDec('Enter admin name').copyWith(
                        prefixIcon: AppIcon.linear('user', size: 18, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                    ),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Designation *'),
                    DropdownButtonFormField<String>(
                      value: _adminDesignation,
                      decoration: _inputDec('Select designation').copyWith(
                        prefixIcon: AppIcon.linear('personalcard', size: 18, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      items: _designationOptions.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
                      onChanged: (v) => setState(() => _adminDesignation = v ?? 'Principal'),
                      validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                    ),
                  ])),
                ]),
                SizedBox(height: 14.h),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Email *'),
                    TextFormField(
                      controller: _adminEmailController,
                      decoration: _inputDec('Enter email').copyWith(
                        prefixIcon: AppIcon.linear('sms', size: 18, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Email is required' : null,
                    ),
                  ])),
                  SizedBox(width: 14.w),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Phone *'),
                    TextFormField(
                      controller: _adminPhoneController,
                      decoration: _inputDec('Enter phone').copyWith(
                        prefixIcon: AppIcon.linear('call', size: 18, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Phone is required' : null,
                    ),
                  ])),
                ]),
                SizedBox(height: 14.h),

                _fieldLabel('Date of Birth *'),
                InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _adminDob ?? DateTime(1990),
                      firstDate: DateTime(1940),
                      lastDate: DateTime.now(),
                    );
                    if (picked != null) setState(() => _adminDob = picked);
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      AppIcon('calendar-1', size: 18, color: AppColors.textSecondary),
                      SizedBox(width: 10.w),
                      Text(
                        _adminDob != null
                            ? '${_adminDob!.day.toString().padLeft(2, '0')}/${_adminDob!.month.toString().padLeft(2, '0')}/${_adminDob!.year}'
                            : 'Select date of birth',
                        style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: _adminDob != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6)),
                      ),
                    ]),
                  ),
                ),
                SizedBox(height: 20.h),

                const Divider(height: 20, color: AppColors.border),
                SizedBox(height: 8.h),

                _fieldLabel('Password *'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _inputDec('Enter password').copyWith(
                    prefixIcon: AppIcon.linear('lock', size: 18, color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      icon: AppIcon(_obscurePassword ? 'eye-slash' : 'eye', size: 18, color: AppColors.textSecondary),
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
                SizedBox(height: 20.h),

                _fieldLabel('Confirm Password *'),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  decoration: _inputDec('Re-enter password').copyWith(
                    prefixIcon: AppIcon.linear('lock', size: 18, color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      icon: AppIcon(_obscureConfirm ? 'eye-slash' : 'eye', size: 18, color: AppColors.textSecondary),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  style: _fieldStyle(),
                  validator: (v) {
                    if (v != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                SizedBox(height: 32.h),

                SizedBox(
                  width: double.infinity,
                  height: 50.h,
                  child: ElevatedButton.icon(
                    onPressed: _isCreating ? null : _handleRegister,
                    icon: _isCreating
                        ? SizedBox(width: 20.w, height: 20.h, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : AppIcon('tick-circle', size: 20),
                    label: Text(_isCreating ? 'Creating...' : 'Create Institution', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: EdgeInsets.only(bottom: 6.h),
      child: Text(label, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.black87)),
    );
  }

  TextStyle _fieldStyle() => TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp, color: AppColors.textPrimary);

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13.sp),
    contentPadding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 12.h),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
    filled: true,
    fillColor: Colors.white,
  );
}
