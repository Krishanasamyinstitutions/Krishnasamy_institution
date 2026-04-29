import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';

import '../../widgets/app_icon.dart';
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;

  List<Map<String, dynamic>> _institutions = [];
  int? _selectedInsId;
  bool _loadingInstitutions = true;
  bool _isSuperAdmin = false;
  List<Map<String, dynamic>> _availableYears = [];
  String? _selectedYear;
  bool _loadingYears = false;

  @override
  void initState() {
    super.initState();
    _loadInstitutions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments as String?;
    _isSuperAdmin = args == 'super_admin';
  }

  Future<void> _loadInstitutions() async {
    if (_isSuperAdmin) {
      setState(() => _loadingInstitutions = false);
      return;
    }
    final institutions = await SupabaseService.getInstitutionNames();
    if (!mounted) return;
    setState(() {
      _institutions = institutions;
      _loadingInstitutions = false;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadYears(int insId) async {
    setState(() => _loadingYears = true);
    try {
      final result = await SupabaseService.client
          .from('institutionyear')
          .select('yrlabel, iyrstadate, iyrenddate')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('iyr_id', ascending: false);
      final rawYears = List<Map<String, dynamic>>.from(result);
      // Deduplicate by yrlabel — the Material DropdownButton crashes if two
      // items share the same value. Defensive against duplicate rows in
      // public.institutionyear.
      final seen = <String>{};
      final years = <Map<String, dynamic>>[];
      for (final y in rawYears) {
        final label = y['yrlabel']?.toString() ?? '';
        if (label.isEmpty || seen.contains(label)) continue;
        seen.add(label);
        years.add(y);
      }
      // Default the dropdown to the year whose [iyrstadate, iyrenddate]
      // contains today. Prevents accountants from silently logging into a
      // past year and posting fees to the wrong schema. They can still
      // pick historical years from the dropdown to view old data.
      final today = DateTime.now();
      String? currentYearLabel;
      for (final y in years) {
        final start = DateTime.tryParse(y['iyrstadate']?.toString() ?? '');
        final end = DateTime.tryParse(y['iyrenddate']?.toString() ?? '');
        if (start == null || end == null) continue;
        final endInclusive = DateTime(end.year, end.month, end.day, 23, 59, 59);
        if (!today.isBefore(start) && !today.isAfter(endInclusive)) {
          currentYearLabel = y['yrlabel']?.toString();
          break;
        }
      }
      if (mounted) {
        setState(() {
          _availableYears = years;
          _selectedYear = currentYearLabel
              ?? (years.isNotEmpty ? years.first['yrlabel']?.toString() : null);
          _loadingYears = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingYears = false);
    }
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isSuperAdmin && _selectedInsId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select an institution')),
      );
      return;
    }

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
      insId: _isSuperAdmin ? null : _selectedInsId,
      isSuperAdmin: _isSuperAdmin,
      yearLabel: _selectedYear,
    );

    if (success && mounted) {
      await authProvider.saveCredentials(
        _emailController.text.trim(),
        _passwordController.text,
        insId: _isSuperAdmin ? null : _selectedInsId,
        isSuperAdmin: _isSuperAdmin,
      );
      if (mounted) {
        Navigator.pushReplacementNamed(
          context,
          _isSuperAdmin ? AppRoutes.superAdminDashboard : AppRoutes.dashboard,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 600;

    return Scaffold(
      body: Row(
        children: [
          // Left decorative panel (desktop only)
          if (isDesktop)
            Expanded(
              flex: 5,
              child: _buildLeftPanel(context),
            ),

          // Right form panel
          Expanded(
            flex: isDesktop ? 4 : 1,
            child: _buildFormPanel(context),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftPanel(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.splashGradient),
      child: Stack(
        children: [
          // Decorative grid dots
          ...List.generate(48, (index) {
            final row = index ~/ 6;
            final col = index % 6;
            return Positioned(
              top: 60.0 + (row * 80),
              left: 40.0 + (col * 80),
              child: Container(
                width: 3.w,
                height: 3.h,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.06),
                ),
              ),
            );
          }),

          Center(
            child: Padding(
              padding: EdgeInsets.all(64.w),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeInLeft(
                    child: SizedBox(
                      width: 128.w,
                      height: 128.h,
                      child: Image.asset(
                        'assets/images/educore360_logo.png',
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => AppIcon('teacher',
                          size: 56.sp,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ),
                  SizedBox(height: 32.h),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 200),
                    child: Text(
                      'Welcome to\nEduCore360',
                      textAlign: TextAlign.center,
                      style:
                          Theme.of(context).textTheme.displayMedium?.copyWith(
                                color: Colors.white,
                                height: 1.2,
                              ),
                    ),
                  ),
                  SizedBox(height: 16.h),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 400),
                    child: Text(
                      'Your complete school administration\nplatform for modern education.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: Colors.white.withValues(alpha: 0.6),
                            height: 1.6,
                          ),
                    ),
                  ),
                  SizedBox(height: 48.h),
                  FadeInLeft(
                    delay: const Duration(milliseconds: 600),
                    child: _buildFeatureList(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureList(BuildContext context) {
    final features = [
      {'icon': 'shield-tick', 'text': 'Enterprise-grade security'},
      {'icon': 'monitor', 'text': 'Access from any device'},
      {'icon': '24-support', 'text': '24/7 dedicated support'},
    ];

    return Column(
      children: features.map((f) {
        return Padding(
          padding: EdgeInsets.only(bottom: 16.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36.w,
                height: 36.h,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10.r),
                ),
                child: AppIcon(
                  f['icon'] as String,
                  color: AppColors.accent,
                  size: 18,
                ),
              ),
              SizedBox(width: 14.w),
              Text(
                f['text'] as String,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _buildFormPanel(BuildContext context) {
    return Container(
      color: AppColors.surface,
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(40.w),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Back button
                  FadeInDown(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const AppIcon.linear('Chevron Left'),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white,
                          side: const BorderSide(color: AppColors.border),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: 32.h),

                  FadeInDown(
                    delay: const Duration(milliseconds: 100),
                    child: Text(
                      _isSuperAdmin ? 'Super Admin' : 'Sign In',
                      style: Theme.of(context).textTheme.displayMedium,
                    ),
                  ),
                  SizedBox(height: 8.h),
                  FadeInDown(
                    delay: const Duration(milliseconds: 200),
                    child: Text(
                      _isSuperAdmin
                          ? 'Enter your super admin credentials'
                          : 'Enter your credentials to access the dashboard',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                  ),

                  SizedBox(height: 36.h),

                  // Error message
                  Consumer<AuthProvider>(
                    builder: (context, auth, _) {
                      if (auth.errorMessage != null) {
                        return FadeInDown(
                          child: Container(
                            padding: EdgeInsets.all(14.w),
                            margin: EdgeInsets.only(bottom: 20.h),
                            decoration: BoxDecoration(
                              color: AppColors.error.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(12.r),
                              border: Border.all(
                                color: AppColors.error.withValues(alpha: 0.3),
                              ),
                            ),
                            child: Row(
                              children: [
                                AppIcon.linear('info-circle',
                                    color: AppColors.error, size: 20),
                                SizedBox(width: 10.w),
                                Expanded(
                                  child: Text(
                                    auth.errorMessage!,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: AppColors.error),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // Institution dropdown (only for institution login)
                  if (!_isSuperAdmin) ...[
                    FadeInDown(
                      delay: const Duration(milliseconds: 250),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Institution',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontSize: 13.sp),
                          ),
                          SizedBox(height: 8.h),
                          _loadingInstitutions
                              ? const LinearProgressIndicator()
                              : DropdownButtonFormField<int>(
                                  value: _selectedInsId,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    hintText: 'Select your institution',
                                    prefixIcon: AppIcon.linear('teacher',
                                        size: 20, color: AppColors.textLight),
                                    prefixIconConstraints: BoxConstraints(
                                        minWidth: 52.w, minHeight: 0),
                                  ),
                                  items: _institutions.map((ins) {
                                    return DropdownMenuItem<int>(
                                      value: ins['ins_id'] as int,
                                      child: Text(ins['insname'] ?? '', overflow: TextOverflow.ellipsis),
                                    );
                                  }).toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      _selectedInsId = value;
                                      _selectedYear = null;
                                      _availableYears = [];
                                    });
                                    if (value != null) _loadYears(value);
                                  },
                                  validator: (value) {
                                    if (value == null) {
                                      return 'Please select an institution';
                                    }
                                    return null;
                                  },
                                ),
                        ],
                      ),
                    ),
                    SizedBox(height: 20.h),
                    // Year dropdown (shows after institution selected)
                    if (_availableYears.isNotEmpty)
                      FadeInDown(
                        delay: const Duration(milliseconds: 300),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Academic Year', style: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 13.sp)),
                            SizedBox(height: 8.h),
                            _loadingYears
                                ? const LinearProgressIndicator()
                                : DropdownButtonFormField<String>(
                                    value: _selectedYear,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      hintText: 'Select academic year',
                                      prefixIcon: AppIcon.linear('calendar', size: 20, color: AppColors.textLight),
                                      prefixIconConstraints: BoxConstraints(minWidth: 52.w, minHeight: 0),
                                    ),
                                    items: _availableYears.map((y) {
                                      final label = y['yrlabel']?.toString() ?? '';
                                      return DropdownMenuItem<String>(value: label, child: Text(label, overflow: TextOverflow.ellipsis));
                                    }).toList(),
                                    onChanged: (value) => setState(() => _selectedYear = value),
                                  ),
                          ],
                        ),
                      ),
                    if (_availableYears.isNotEmpty) SizedBox(height: 20.h),
                  ],

                  // Email / Username field
                  FadeInDown(
                    delay: const Duration(milliseconds: 300),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _isSuperAdmin ? 'Username' : 'Email Address',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontSize: 13.sp),
                        ),
                        SizedBox(height: 8.h),
                        TextFormField(
                          controller: _emailController,
                          keyboardType: _isSuperAdmin ? TextInputType.text : TextInputType.emailAddress,
                          decoration: InputDecoration(
                            hintText: _isSuperAdmin ? 'Enter username' : 'admin@edudesk.com',
                            prefixIcon: AppIcon(
                                _isSuperAdmin ? 'user' : 'sms',
                                size: 20, color: AppColors.textLight),
                            prefixIconConstraints: BoxConstraints(
                                minWidth: 52.w, minHeight: 0),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return _isSuperAdmin ? 'Please enter your username' : 'Please enter your email';
                            }
                            if (!_isSuperAdmin && !value.contains('@')) {
                              return 'Please enter a valid email';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 20.h),

                  // Password field
                  FadeInDown(
                    delay: const Duration(milliseconds: 400),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Password',
                          style: Theme.of(context)
                              .textTheme
                              .labelLarge
                              ?.copyWith(fontSize: 13.sp),
                        ),
                        SizedBox(height: 8.h),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscurePassword,
                          decoration: InputDecoration(
                            hintText: '••••••••',
                            prefixIcon: AppIcon.linear('lock',
                                size: 20, color: AppColors.textLight),
                            prefixIconConstraints: BoxConstraints(
                                minWidth: 52.w, minHeight: 0),
                            suffixIcon: IconButton(
                              icon: AppIcon(
                                _obscurePassword
                                    ? 'eye-slash'
                                    : 'eye',
                                size: 20,
                                color: AppColors.textLight,
                              ),
                              onPressed: () {
                                setState(() {
                                  _obscurePassword = !_obscurePassword;
                                });
                              },
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Please enter your password';
                            }
                            if (value.length < 6) {
                              return 'Password must be at least 6 characters';
                            }
                            return null;
                          },
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 16.h),

                  // Remember me & Forgot password
                  FadeInDown(
                    delay: const Duration(milliseconds: 500),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            SizedBox(
                              width: 20.w,
                              height: 20.h,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (v) =>
                                    setState(() => _rememberMe = v ?? false),
                                activeColor: AppColors.accent,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(4.r),
                                ),
                              ),
                            ),
                            SizedBox(width: 8.w),
                            Text(
                              'Remember me',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontSize: 13.sp),
                            ),
                          ],
                        ),
                        TextButton(
                          onPressed: () => Navigator.pushNamed(
                              context, AppRoutes.forgotPassword),
                          child: Text(
                            'Forgot Password?',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: AppColors.accent,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13.sp,
                                ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  SizedBox(height: 28.h),

                  // Sign in button
                  FadeInDown(
                    delay: const Duration(milliseconds: 600),
                    child: Consumer<AuthProvider>(
                      builder: (context, auth, _) {
                        return SizedBox(
                          height: 54.h,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accent,
                              padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                            ),
                            child: auth.isLoading
                                ? SizedBox(
                                    width: 22.w,
                                    height: 22.h,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : Text(
                                    'Sign In',
                                    style: TextStyle(
                                      fontSize: 16.sp,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                          ),
                        );
                      },
                    ),
                  ),

                  SizedBox(height: 28.h),

                  SizedBox(height: 24.h),

                  // Demo hint
                  FadeInDown(
                    delay: const Duration(milliseconds: 800),
                    child: Container(
                      padding: EdgeInsets.all(14.w),
                      decoration: BoxDecoration(
                        color: AppColors.info.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12.r),
                        border: Border.all(
                          color: AppColors.info.withValues(alpha: 0.15),
                        ),
                      ),
                      child: Row(
                        children: [
                          AppIcon.linear('info-circle',
                              color: AppColors.info.withValues(alpha: 0.7),
                              size: 18.sp),
                          SizedBox(width: 10.w),
                          Expanded(
                            child: Text(
                              _isSuperAdmin
                                  ? 'Demo: superadmin / admin123'
                                  : 'Demo: admin@edudesk.com / admin123',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: AppColors.info,
                                    fontSize: 13.sp,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
