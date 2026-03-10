import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

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
  final _institutionNameController = TextEditingController();
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

  // Step 3: Account Setup
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
      // 1. Map institution type to it_id
      final itIdMap = {
        'Schools (Primary, Secondary, Higher Secondary)': 1,
        'Colleges': 2,
        'Universities': 3,
        'Polytechnic Institutions': 4,
        'Vocational Training Centers': 5,
        'Coaching Institutes': 6,
      };

      // 1. Create institution
      final insData = <String, dynamic>{
        'insname': _institutionNameController.text.trim(),
        'inscode': _institutionCodeController.text.trim(),
        'insstadate': (_institutionStartDate ?? DateTime.now()).toIso8601String().split('T').first,
        'insautusername': _authorizedUsernameController.text.trim(),
        'insdesignation': _designationController.text.trim().isNotEmpty ? _designationController.text.trim() : 'Admin',
        'insmobno': _mobileNumberController.text.trim(),
        'insmail': _emailController.text.trim(),
        'it_id': itIdMap[_institutionType] ?? 1,
        'insrecognised': _institutionRecognized == 'Yes' ? 'Y' : 'N',
        'insaffliation': _affiliationController.text.trim(),
        'insaffno': _affiliationNumberController.text.trim(),
        'insaffstayear': _affiliationStartYear?.year.toString(),
        'insaddress1': _address1Controller.text.trim(),
        'insaddress2': _address2Controller.text.trim(),
        'insaddress3': _address3Controller.text.trim(),
        'inscity': _cityController.text.trim(),
        'insstate': _stateController.text.trim(),
        'inscountry': _countryController.text.trim(),
        'inspincode': _pinCodeController.text.trim(),
        'insipaddress': '0.0.0.0',
        'inssername': 'default',
        'insserurl': 'default',
        'updatedby': _authorizedUsernameController.text.trim(),
        'activestatus': 1,
      };

      final insResult = await SupabaseService.createInstitution(insData);
      if (insResult == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to create institution'), backgroundColor: Colors.red),
          );
          setState(() => _isCreating = false);
        }
        return;
      }

      final insId = insResult['ins_id'] as int;
      final insCode = insResult['inscode']?.toString() ?? '';

      // 2. Create default designation & role for the new institution
      final desResult = await SupabaseService.createDesignation({
        'ins_id': insId,
        'desname': 'Chairman',
        'activestatus': 1,
      });
      final roleResult = await SupabaseService.createUserRole({
        'ins_id': insId,
        'urname': 'Admin',
        'activestatus': 1,
      });

      // Fetch the created des_id and ur_id
      final designations = await SupabaseService.getDesignations(insId);
      final roles = await SupabaseService.getUserRoles(insId);
      final desId = designations.isNotEmpty ? designations.first['des_id'] as int : 1;
      final urId = roles.isNotEmpty ? roles.first['ur_id'] as int : 1;

      // 3. Create admin user in institutionusers
      final userData = {
        'ins_id': insId,
        'inscode': insCode,
        'usename': _adminNameController.text.trim(),
        'usemail': _adminEmailController.text.trim(),
        'usephone': _adminPhoneController.text.trim(),
        'usepassword': _passwordController.text,
        'usestadate': DateTime.now().toIso8601String().split('T').first,
        'useotpstatus': 0,
        'usedob': _adminDob != null ? _adminDob!.toIso8601String().split('T').first : '2000-01-01',
        'ur_id': urId,
        'urname': 'Admin',
        'des_id': desId,
        'desname': 'Chairman',
        'userepto': 0,
        'activestatus': 1,
      };

      final userSuccess = await SupabaseService.createInstitutionUser(userData);
      if (!userSuccess) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Institution created but failed to create admin user'), backgroundColor: Colors.orange),
          );
          setState(() => _isCreating = false);
        }
        return;
      }

      // 3. Auto-login with the new admin user
      if (mounted) {
        final authProvider = context.read<AuthProvider>();
        final loginSuccess = await authProvider.login(
          userData['usemail'] as String,
          _passwordController.text,
        );

        setState(() => _isCreating = false);

        if (loginSuccess && mounted) {
          Navigator.pushReplacementNamed(context, AppRoutes.dashboard);
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Account created! Please login with your credentials.'), backgroundColor: Colors.green),
          );
          Navigator.pop(context);
        }
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
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 800;

    return Scaffold(
      body: Row(
        children: [
          if (isDesktop)
            Expanded(
              flex: 4,
              child: _buildLeftPanel(context),
            ),
          Expanded(
            flex: isDesktop ? 7 : 1,
            child: _buildRightPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(BuildContext context) {
    final stepLabels = ['Institution Info', 'Affiliation & Address', 'Account Setup'];
    final stepDescs = ['Basic institution details', 'Affiliation and address', 'Set up your password'];

    return Container(
      decoration: const BoxDecoration(gradient: AppColors.splashGradient),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(48),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FadeInLeft(
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.school_rounded, size: 36, color: AppColors.secondary),
                ),
              ),
              const SizedBox(height: 28),
              FadeInLeft(
                delay: const Duration(milliseconds: 200),
                child: Text(
                  'Join EduDesk',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              FadeInLeft(
                delay: const Duration(milliseconds: 400),
                child: Text(
                  'Set up your institution and start\nmanaging efficiently.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.white.withValues(alpha: 0.6), height: 1.6),
                ),
              ),
              const SizedBox(height: 48),
              FadeInLeft(
                delay: const Duration(milliseconds: 600),
                child: Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                  ),
                  child: Column(
                    children: List.generate(3, (i) {
                      final isActive = i == _currentStep;
                      final isDone = i < _currentStep;
                      return Padding(
                        padding: EdgeInsets.only(bottom: i < 2 ? 16 : 0),
                        child: Row(
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isDone
                                    ? AppColors.accent.withValues(alpha: 0.3)
                                    : isActive
                                        ? AppColors.accent.withValues(alpha: 0.2)
                                        : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Center(
                                child: isDone
                                    ? const Icon(Icons.check_rounded, size: 18, color: AppColors.accent)
                                    : Text('${i + 1}', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isActive ? AppColors.accent : Colors.white.withValues(alpha: 0.3))),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(stepLabels[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? Colors.white.withValues(alpha: 0.9) : Colors.white.withValues(alpha: 0.4))),
                                Text(stepDescs[i], style: TextStyle(fontSize: 11, color: isActive ? Colors.white.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.2))),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRightPanel(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Column(
        children: [
          // Top bar with back button and stepper dots
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: Row(
              children: [
                IconButton(
                  onPressed: _currentStep > 0 ? () => _goToStep(_currentStep - 1) : () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const Spacer(),
                // Step indicator dots
                Row(
                  children: List.generate(3, (i) {
                    final isActive = i == _currentStep;
                    final isDone = i < _currentStep;
                    return GestureDetector(
                      onTap: () => _goToStep(i),
                      child: Container(
                        width: isActive ? 32 : 10,
                        height: 10,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        decoration: BoxDecoration(
                          color: isDone ? AppColors.accent : isActive ? AppColors.accent : AppColors.border,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    );
                  }),
                ),
                const Spacer(),
                Text('Step ${_currentStep + 1} of 3', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
          const SizedBox(height: 16),

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
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 24),
            child: Row(
              children: [
                if (_currentStep > 0)
                  OutlinedButton.icon(
                    onPressed: () => _goToStep(_currentStep - 1),
                    icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    label: const Text('Previous'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      side: const BorderSide(color: AppColors.border),
                    ),
                  ),
                const Spacer(),
                // Sign in link
                if (_currentStep == 0)
                  Row(
                    children: [
                      Text('Already have an account? ', style: Theme.of(context).textTheme.bodyMedium),
                      TextButton(
                        onPressed: () => Navigator.pushReplacementNamed(context, AppRoutes.login),
                        style: TextButton.styleFrom(padding: EdgeInsets.zero, minimumSize: Size.zero, tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                        child: Text('Sign In', style: TextStyle(color: AppColors.accent, fontWeight: FontWeight.w600)),
                      ),
                      const SizedBox(width: 20),
                    ],
                  ),
                if (_currentStep < 2)
                  ElevatedButton.icon(
                    onPressed: () => _goToStep(_currentStep + 1),
                    icon: const Text('Next'),
                    label: const Icon(Icons.arrow_forward_rounded, size: 18),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Step 1: Institution Information
  Widget _buildStep1() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border),
        ),
        child: Form(
          key: _formKeys[0],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                Icon(Icons.domain_add_rounded, color: AppColors.accent, size: 22),
                const SizedBox(width: 10),
                const Text('Institution Information', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 6),
              const Text('Enter the basic details about your institution', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              const Divider(height: 28, color: AppColors.border),

              _fieldLabel('Institution Type'),
              DropdownButtonFormField<String>(
                initialValue: _institutionType,
                decoration: _inputDec('Select institution type'),
                isExpanded: true,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary),
                items: _institutionTypes.map((t) => DropdownMenuItem(value: t, child: Text(t, overflow: TextOverflow.ellipsis))).toList(),
                onChanged: (v) => setState(() => _institutionType = v),
              ),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Name *'),
                  TextFormField(controller: _institutionNameController, decoration: _inputDec('Enter institution name'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                ])),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Institution Code *'),
                  TextFormField(controller: _institutionCodeController, decoration: _inputDec('Enter institution code'), style: _fieldStyle(), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                ])),
              ]),
              const SizedBox(height: 16),

              _fieldLabel('Institution Start Date'),
              InkWell(
                onTap: _pickInstitutionStartDate,
                child: InputDecorator(
                  decoration: _inputDec('Select date').copyWith(suffixIcon: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.textSecondary)),
                  child: Text(
                    _institutionStartDate != null ? _formatDate(_institutionStartDate!) : 'Select date',
                    style: TextStyle(color: _institutionStartDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13, fontWeight: _institutionStartDate != null ? FontWeight.w600 : FontWeight.normal),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Authorized Username'),
                  TextFormField(controller: _authorizedUsernameController, decoration: _inputDec('Enter authorized username'), style: _fieldStyle()),
                ])),
                const SizedBox(width: 14),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Designation'),
                  TextFormField(controller: _designationController, decoration: _inputDec('Enter designation'), style: _fieldStyle()),
                ])),
              ]),
              const SizedBox(height: 16),

              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _fieldLabel('Mobile Number'),
                  TextFormField(controller: _mobileNumberController, decoration: _inputDec('Enter mobile number'), style: _fieldStyle(), keyboardType: TextInputType.phone),
                ])),
                const SizedBox(width: 14),
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
              ]),
              const SizedBox(height: 14),
              _fieldLabel('Email *'),
              TextFormField(
                controller: _emailController,
                decoration: _inputDec('Enter email address'),
                style: _fieldStyle(),
                keyboardType: TextInputType.emailAddress,
                validator: (v) => v == null || v.trim().isEmpty ? 'Email is required' : null,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Step 2: Affiliation & Address
  Widget _buildStep2() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        children: [
          // Affiliation card
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Form(
              key: _formKeys[1],
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Icon(Icons.verified_rounded, color: AppColors.accent, size: 22),
                    const SizedBox(width: 10),
                    const Text('Affiliation Information', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 6),
                  const Text('Enter affiliation and recognition details', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                  const Divider(height: 28, color: AppColors.border),

                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Institution Affiliation'),
                      TextFormField(controller: _affiliationController, decoration: _inputDec('Enter affiliation'), style: _fieldStyle()),
                    ])),
                    const SizedBox(width: 14),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      _fieldLabel('Affiliation Number'),
                      TextFormField(controller: _affiliationNumberController, decoration: _inputDec('Enter affiliation number'), style: _fieldStyle()),
                    ])),
                  ]),
                  const SizedBox(height: 16),

                  _fieldLabel('Affiliation Start Year'),
                  InkWell(
                    onTap: _pickAffiliationStartYear,
                    child: InputDecorator(
                      decoration: _inputDec('Select year').copyWith(suffixIcon: const Icon(Icons.calendar_month_rounded, size: 18, color: AppColors.textSecondary)),
                      child: Text(
                        _affiliationStartYear != null ? '${_affiliationStartYear!.year}' : 'Select year',
                        style: TextStyle(color: _affiliationStartYear != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13, fontWeight: _affiliationStartYear != null ? FontWeight.w600 : FontWeight.normal),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Address card
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.location_on_rounded, color: AppColors.accent, size: 22),
                  const SizedBox(width: 10),
                  const Text('Address', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                const Text('Enter the institution address details', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const Divider(height: 28, color: AppColors.border),

                _fieldLabel('Address Line 1 *'),
                TextFormField(controller: _address1Controller, decoration: _inputDec('Enter address line 1'), style: _fieldStyle()),
                const SizedBox(height: 16),

                _fieldLabel('Address Line 2'),
                TextFormField(controller: _address2Controller, decoration: _inputDec('Enter address line 2'), style: _fieldStyle()),
                const SizedBox(height: 16),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Address Line 3'),
                    TextFormField(controller: _address3Controller, decoration: _inputDec('Enter address line 3'), style: _fieldStyle()),
                  ])),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Pin Code'),
                    TextFormField(controller: _pinCodeController, decoration: _inputDec('Enter pin code'), style: _fieldStyle(), keyboardType: TextInputType.number),
                  ])),
                ]),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('City'),
                    TextFormField(controller: _cityController, decoration: _inputDec('Enter city'), style: _fieldStyle()),
                  ])),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('State'),
                    TextFormField(controller: _stateController, decoration: _inputDec('Enter state'), style: _fieldStyle()),
                  ])),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Country'),
                    TextFormField(controller: _countryController, decoration: _inputDec('Enter country'), style: _fieldStyle()),
                  ])),
                ]),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  // Step 3: Account Setup
  Widget _buildStep3() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500),
          padding: const EdgeInsets.all(32),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppColors.border),
          ),
          child: Form(
            key: _formKeys[2],
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.lock_rounded, color: AppColors.accent, size: 22),
                  const SizedBox(width: 10),
                  const Text('Account Setup', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 6),
                const Text('Create an admin account for your institution', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                const Divider(height: 28, color: AppColors.border),

                _fieldLabel('Admin Name *'),
                TextFormField(
                  controller: _adminNameController,
                  decoration: _inputDec('Enter admin name').copyWith(
                    prefixIcon: const Icon(Icons.person_outline_rounded, size: 18, color: AppColors.textSecondary),
                  ),
                  style: _fieldStyle(),
                  validator: (v) => v == null || v.trim().isEmpty ? 'Name is required' : null,
                ),
                const SizedBox(height: 14),

                Row(children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Email *'),
                    TextFormField(
                      controller: _adminEmailController,
                      decoration: _inputDec('Enter email').copyWith(
                        prefixIcon: const Icon(Icons.email_outlined, size: 18, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      keyboardType: TextInputType.emailAddress,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Email is required' : null,
                    ),
                  ])),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _fieldLabel('Admin Phone *'),
                    TextFormField(
                      controller: _adminPhoneController,
                      decoration: _inputDec('Enter phone').copyWith(
                        prefixIcon: const Icon(Icons.phone_outlined, size: 18, color: AppColors.textSecondary),
                      ),
                      style: _fieldStyle(),
                      keyboardType: TextInputType.phone,
                      validator: (v) => v == null || v.trim().isEmpty ? 'Phone is required' : null,
                    ),
                  ])),
                ]),
                const SizedBox(height: 14),

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
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.border),
                    ),
                    child: Row(children: [
                      const Icon(Icons.calendar_today_rounded, size: 18, color: AppColors.textSecondary),
                      const SizedBox(width: 10),
                      Text(
                        _adminDob != null
                            ? '${_adminDob!.day.toString().padLeft(2, '0')}/${_adminDob!.month.toString().padLeft(2, '0')}/${_adminDob!.year}'
                            : 'Select date of birth',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _adminDob != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.6)),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(height: 20),

                const Divider(height: 20, color: AppColors.border),
                const SizedBox(height: 8),

                _fieldLabel('Password *'),
                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: _inputDec('Enter password').copyWith(
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.textSecondary),
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
                const SizedBox(height: 20),

                _fieldLabel('Confirm Password *'),
                TextFormField(
                  controller: _confirmPasswordController,
                  obscureText: _obscureConfirm,
                  decoration: _inputDec('Re-enter password').copyWith(
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 18, color: AppColors.textSecondary),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirm ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 18, color: AppColors.textSecondary),
                      onPressed: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    ),
                  ),
                  style: _fieldStyle(),
                  validator: (v) {
                    if (v != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isCreating ? null : _handleRegister,
                    icon: _isCreating
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.check_circle_rounded, size: 20),
                    label: Text(_isCreating ? 'Creating...' : 'Create Institution', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.black87)),
    );
  }

  TextStyle _fieldStyle() => const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textPrimary);

  InputDecoration _inputDec(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.6), fontSize: 13),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
    filled: true,
    fillColor: Colors.white,
  );
}
