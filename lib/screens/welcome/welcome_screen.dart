import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';

class _PinkPalette {
  static const Color frame = Color(0xFF001530);
  static const Color primary = Color(0xFF002147);
  static const Color accent = Color(0xFFD2913C);
  static const Color soft = Color(0xFFF0D2A5);

  static const LinearGradient buttonGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE5A85C), Color(0xFFB5752A)],
  );

  static const LinearGradient avatarGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFFE8B06B), Color(0xFFA76920)],
  );

  static const LinearGradient panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF002147), Color(0xFF001530)],
  );
}

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  bool _isSuperAdmin = false;

  List<Map<String, dynamic>> _institutions = [];
  int? _selectedInsId;
  bool _loadingInstitutions = true;

  List<Map<String, dynamic>> _availableYears = [];
  String? _selectedYear;
  bool _loadingYears = false;

  @override
  void initState() {
    super.initState();
    _loadInstitutions();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _loadInstitutions() async {
    final institutions = await SupabaseService.getInstitutionNames();
    if (!mounted) return;
    setState(() {
      _institutions = institutions;
      _loadingInstitutions = false;
    });
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
      final seen = <String>{};
      final years = <Map<String, dynamic>>[];
      for (final y in rawYears) {
        final label = y['yrlabel']?.toString() ?? '';
        if (label.isEmpty || seen.contains(label)) continue;
        seen.add(label);
        years.add(y);
      }
      if (mounted) {
        setState(() {
          _availableYears = years;
          _selectedYear =
              years.isNotEmpty ? years.first['yrlabel']?.toString() : null;
          _loadingYears = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingYears = false);
    }
  }

  void _switchTab(bool superAdmin) {
    if (_isSuperAdmin == superAdmin) return;
    setState(() {
      _isSuperAdmin = superAdmin;
      _emailController.clear();
      _passwordController.clear();
      _selectedInsId = null;
      _availableYears = [];
      _selectedYear = null;
    });
    context.read<AuthProvider>().clearError();
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
    final isDesktop = size.width > 900;
    final baseTheme = Theme.of(context);

    return Theme(
      data: baseTheme.copyWith(
        textTheme: GoogleFonts.robotoCondensedTextTheme(baseTheme.textTheme),
        primaryTextTheme:
            GoogleFonts.robotoCondensedTextTheme(baseTheme.primaryTextTheme),
        inputDecorationTheme: baseTheme.inputDecorationTheme.copyWith(
          hintStyle: GoogleFonts.robotoCondensed(
            color: Colors.grey.shade400,
            fontSize: 17,
          ),
          labelStyle: GoogleFonts.robotoCondensed(),
        ),
      ),
      child: DefaultTextStyle.merge(
        style: GoogleFonts.robotoCondensed(color: _PinkPalette.frame),
        child: Scaffold(
          backgroundColor: _PinkPalette.frame,
          body: Stack(
            children: [
              // Gradient backdrop
              Positioned.fill(
                child: Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF003166),
                        Color(0xFF001F42),
                        Color(0xFF00091E),
                      ],
                      stops: [0.0, 0.55, 1.0],
                    ),
                  ),
                ),
              ),

              // Abstract decorative elements
              Positioned.fill(
                child: CustomPaint(painter: _AbstractBackgroundPainter()),
              ),

              // Soft amber glow — top right
              Positioned(
                top: -120,
                right: -120,
                child: Container(
                  width: 360,
                  height: 360,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _PinkPalette.accent.withValues(alpha: 0.28),
                        _PinkPalette.accent.withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
              // Soft navy glow — bottom left
              Positioned(
                bottom: -160,
                left: -160,
                child: Container(
                  width: 460,
                  height: 460,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        const Color(0xFF003E80).withValues(alpha: 0.45),
                        const Color(0xFF003E80).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(isDesktop ? 40.w : 16.w),
                    child: ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: isDesktop ? 720 : 520),
                      child: FadeIn(
                        duration: const Duration(milliseconds: 500),
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(24.r),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.22),
                                blurRadius: 80,
                                spreadRadius: 4,
                              ),
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.12),
                                blurRadius: 30,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(24.r),
                            child: Container(
                              decoration: const BoxDecoration(
                                color: Colors.white,
                              ),
                              child: IntrinsicHeight(
                                child: isDesktop
                                    ? Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.stretch,
                                        children: [
                                          SizedBox(
                                            width: 280.w,
                                            child: _buildTabPanel(),
                                          ),
                                          Expanded(child: _buildFormPanel()),
                                        ],
                                      )
                                    : Column(
                                        children: [
                                          SizedBox(
                                            height: 180.h,
                                            child:
                                                _buildTabPanel(compact: true),
                                          ),
                                          _buildFormPanel(),
                                        ],
                                      ),
                              ),
                            ),
                          ),
                        ),
                      ),
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

  Widget _buildTabPanel({bool compact = false}) {
    return Stack(
      children: [
        Container(
          decoration: const BoxDecoration(gradient: _PinkPalette.panelGradient),
        ),
        // Decorative geometric shapes (triangles)
        Positioned(
          top: -60,
          left: -60,
          child: Transform.rotate(
            angle: 0.785,
            child: Container(
              width: 220.w,
              height: 220.w,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(28.r),
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -80,
          left: -40,
          child: Transform.rotate(
            angle: 0.785,
            child: Container(
              width: 260.w,
              height: 260.w,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(32.r),
              ),
            ),
          ),
        ),
        if (!compact)
          Positioned(
            right: -1,
            top: 0,
            bottom: 0,
            child: CustomPaint(
              size: Size(60.w, double.infinity),
              painter: _ArrowCutPainter(color: Colors.white),
            ),
          ),
        // Tabs
        Padding(
          padding: EdgeInsets.all(compact ? 20.w : 28.w),
          child: compact
              ? Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildTab('Institute\nLogin', !_isSuperAdmin,
                        () => _switchTab(false),
                        compact: true),
                    SizedBox(width: 12.w),
                    _buildTab('Super Admin\nLogin', _isSuperAdmin,
                        () => _switchTab(true),
                        compact: true),
                  ],
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FadeInLeft(
                      child: Row(
                        children: [
                          SizedBox(
                            width: 80.w,
                            height: 80.w,
                            child: Image.asset(
                              'assets/images/educore360_logo.png',
                              fit: BoxFit.contain,
                              errorBuilder: (_, __, ___) => Icon(Icons.school_rounded,
                                  color: const Color(0xFF002147), size: 36.sp),
                            ),
                          ),
                          SizedBox(width: 10.w),
                          Text(
                            'EduCore360',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20.sp,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Transform.translate(
                      offset: Offset(-24.w, 0),
                      child: SizedBox(
                        width: 180.w,
                        child: _buildTab('INSTITUTE\nLOGIN', !_isSuperAdmin,
                            () => _switchTab(false)),
                      ),
                    ),
                    SizedBox(height: 24.h),
                    Transform.translate(
                      offset: Offset(-24.w, 0),
                      child: SizedBox(
                        width: 180.w,
                        child: _buildTab('SUPER ADMIN\nLOGIN', _isSuperAdmin,
                            () => _switchTab(true)),
                      ),
                    ),
                    const Spacer(),
                    FadeInLeft(
                      delay: const Duration(milliseconds: 200),
                      child: Text(
                        'Empowering Education\nThrough Intelligent\nAdministration',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12.sp,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildTab(String label, bool isActive, VoidCallback onTap,
      {bool compact = false}) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 14.w : 22.w,
            vertical: compact ? 10.h : 16.h,
          ),
          decoration: BoxDecoration(
            color: isActive ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(30.r),
              bottomLeft: Radius.circular(30.r),
              topRight: Radius.circular(compact ? 30.r : 8.r),
              bottomRight: Radius.circular(compact ? 30.r : 8.r),
            ),
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 12,
                      offset: const Offset(-2, 4),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedSize(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: isActive
                    ? Padding(
                        padding: EdgeInsets.only(right: 8.w),
                        child: Container(
                          width: compact ? 18.w : 22.w,
                          height: compact ? 18.w : 22.w,
                          decoration: const BoxDecoration(
                            gradient: _PinkPalette.buttonGradient,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                            size: compact ? 12.sp : 14.sp,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              Flexible(
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: isActive ? _PinkPalette.primary : Colors.white,
                    fontSize: compact ? 12.sp : 14.sp,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFormPanel() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(horizontal: 40.w, vertical: 36.h),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar
            Center(
              child: FadeInDown(
                child: Container(
                  width: 82.w,
                  height: 82.w,
                  decoration: BoxDecoration(
                    gradient: _PinkPalette.avatarGradient,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: _PinkPalette.accent.withValues(alpha: 0.35),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Builder(builder: (_) {
                    String? logoUrl;
                    if (!_isSuperAdmin && _selectedInsId != null) {
                      final ins = _institutions.firstWhere(
                        (e) => e['ins_id'] == _selectedInsId,
                        orElse: () => const {},
                      );
                      final v = ins['inslogo'];
                      if (v is String && v.isNotEmpty) logoUrl = v;
                    }
                    if (logoUrl != null) {
                      return ClipOval(
                        child: Image.network(
                          logoUrl,
                          width: 82.w,
                          height: 82.w,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person_rounded,
                            color: Colors.white,
                            size: 44.sp,
                          ),
                        ),
                      );
                    }
                    return Icon(
                      _isSuperAdmin
                          ? Icons.admin_panel_settings_rounded
                          : Icons.person_rounded,
                      color: Colors.white,
                      size: 44.sp,
                    );
                  }),
                ),
              ),
            ),
            SizedBox(height: 14.h),
            Center(
              child: Text(
                'LOGIN',
                style: TextStyle(
                  color: _PinkPalette.primary,
                  fontSize: 22.sp,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 4,
                ),
              ),
            ),
            SizedBox(height: 6.h),
            Center(
              child: Text(
                _isSuperAdmin ? 'Super Admin Access' : 'Institution Access',
                style: TextStyle(
                  color: _PinkPalette.accent.withValues(alpha: 0.7),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ),
            SizedBox(height: 28.h),

            // Error
            Consumer<AuthProvider>(
              builder: (context, auth, _) {
                if (auth.errorMessage == null) return const SizedBox.shrink();
                return Padding(
                  padding: EdgeInsets.only(bottom: 14.h),
                  child: Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10.r),
                      border:
                          Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded,
                            color: Colors.red.shade600, size: 18.sp),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Text(
                            auth.errorMessage!,
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontSize: 13.sp,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),

            // Institution dropdown (institute login only)
            if (!_isSuperAdmin) ...[
              _loadingInstitutions
                  ? Padding(
                      padding: EdgeInsets.symmetric(vertical: 8.h),
                      child: const LinearProgressIndicator(
                        color: _PinkPalette.accent,
                        backgroundColor: _PinkPalette.soft,
                      ),
                    )
                  : _buildUnderlineDropdown<int>(
                      value: _selectedInsId,
                      hint: 'Select Institution',
                      icon: Icons.school_outlined,
                      items: _institutions.map((ins) {
                        return DropdownMenuItem<int>(
                          value: ins['ins_id'] as int,
                          child: Text(ins['insname'] ?? '',
                              overflow: TextOverflow.ellipsis),
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
                      validator: (value) =>
                          value == null ? 'Please select an institution' : null,
                    ),
              SizedBox(height: 16.h),
              if (_availableYears.isNotEmpty) ...[
                _loadingYears
                    ? const LinearProgressIndicator(
                        color: _PinkPalette.accent,
                        backgroundColor: _PinkPalette.soft,
                      )
                    : _buildUnderlineDropdown<String>(
                        value: _selectedYear,
                        hint: 'Academic Year',
                        icon: Icons.calendar_today_outlined,
                        items: _availableYears.map((y) {
                          final label = y['yrlabel']?.toString() ?? '';
                          return DropdownMenuItem<String>(
                            value: label,
                            child: Text(label, overflow: TextOverflow.ellipsis),
                          );
                        }).toList(),
                        onChanged: (value) =>
                            setState(() => _selectedYear = value),
                      ),
                SizedBox(height: 16.h),
              ],
            ],

            // Email / Username
            _buildUnderlineField(
              controller: _emailController,
              hint: _isSuperAdmin ? 'Username' : 'Email',
              icon: _isSuperAdmin
                  ? Icons.person_outline_rounded
                  : Icons.email_outlined,
              keyboardType: _isSuperAdmin
                  ? TextInputType.text
                  : TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return _isSuperAdmin
                      ? 'Please enter your username'
                      : 'Please enter your email';
                }
                if (!_isSuperAdmin && !value.contains('@')) {
                  return 'Please enter a valid email';
                }
                return null;
              },
            ),
            SizedBox(height: 20.h),

            // Password
            _buildUnderlineField(
              controller: _passwordController,
              hint: 'Password',
              icon: Icons.lock_outline_rounded,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              // Submitting from the password field with Enter triggers
              // the same path as clicking the LOGIN button.
              onFieldSubmitted: (_) => _handleLogin(),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  size: 18.sp,
                  color: _PinkPalette.accent.withValues(alpha: 0.6),
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
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
            SizedBox(height: 16.h),

            // Forgot password (right aligned, on its own row)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    Navigator.pushNamed(context, AppRoutes.forgotPassword),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 4.w, vertical: 8.h),
                ),
                child: Text(
                  'Forgot Password?',
                  style: TextStyle(
                    color: _PinkPalette.accent,
                    fontSize: 13.sp,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

            SizedBox(height: 18.h),

            // Full-width LOGIN button (replaces the old Explore Demo slot)
            Consumer<AuthProvider>(
              builder: (context, auth, _) {
                return MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: auth.isLoading ? null : _handleLogin,
                    child: Container(
                      padding: EdgeInsets.symmetric(vertical: 16.h),
                      decoration: BoxDecoration(
                        gradient: _PinkPalette.buttonGradient,
                        borderRadius: BorderRadius.circular(30.r),
                        boxShadow: [
                          BoxShadow(
                            color: _PinkPalette.accent.withValues(alpha: 0.4),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Center(
                        child: auth.isLoading
                            ? SizedBox(
                                width: 22.w,
                                height: 22.w,
                                child: const CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Text(
                                'LOGIN',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 15.sp,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2.0,
                                ),
                              ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnderlineField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    TextInputType? keyboardType,
    Widget? suffixIcon,
    String? Function(String?)? validator,
    TextInputAction? textInputAction,
    void Function(String)? onFieldSubmitted,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      onFieldSubmitted: onFieldSubmitted,
      style: TextStyle(
        fontSize: 17.sp,
        color: _PinkPalette.frame,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: Colors.grey.shade400,
          fontSize: 17.sp,
        ),
        prefixIcon: Icon(icon,
            size: 22.sp, color: _PinkPalette.accent.withValues(alpha: 0.7)),
        suffixIcon: suffixIcon,
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 16.h),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: _PinkPalette.accent, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildUnderlineDropdown<T>({
    required T? value,
    required String hint,
    required IconData icon,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? Function(T?)? validator,
  }) {
    return DropdownButtonFormField<T>(
      value: value,
      isExpanded: true,
      style: TextStyle(
        fontSize: 17.sp,
        color: _PinkPalette.frame,
        fontWeight: FontWeight.w500,
      ),
      icon: Icon(Icons.keyboard_arrow_down_rounded,
          size: 24.sp, color: _PinkPalette.accent.withValues(alpha: 0.7)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 17.sp),
        prefixIcon: Icon(icon,
            size: 22.sp, color: _PinkPalette.accent.withValues(alpha: 0.7)),
        filled: false,
        contentPadding: EdgeInsets.symmetric(vertical: 16.h),
        border: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: _PinkPalette.accent, width: 2),
        ),
        errorBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: Colors.red),
        ),
      ),
      items: items,
      onChanged: onChanged,
      validator: validator,
    );
  }
}

class _ArrowCutPainter extends CustomPainter {
  final Color color;

  _ArrowCutPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    final path = Path()
      ..moveTo(size.width, 0)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height / 2)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Faint abstract decoration drawn behind the welcome card: dot grid,
/// rotated outline squares, and a couple of thin diagonal accent lines.
class _AbstractBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Dot grid
    final dotPaint = Paint()..color = Colors.white.withValues(alpha: 0.05);
    const spacing = 36.0;
    for (double y = spacing; y < size.height; y += spacing) {
      for (double x = spacing; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), 1.2, dotPaint);
      }
    }

    // Rotated outline squares
    final outlinePaint = Paint()
      ..color = const Color(0xFFD2913C).withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    void drawRotatedSquare(Offset center, double side, double radians) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(radians);
      final r = side / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(-r, -r, side, side),
          const Radius.circular(12),
        ),
        outlinePaint,
      );
      canvas.restore();
    }

    drawRotatedSquare(Offset(size.width * 0.12, size.height * 0.78), 140, 0.6);
    drawRotatedSquare(Offset(size.width * 0.88, size.height * 0.18), 110, -0.5);
    drawRotatedSquare(Offset(size.width * 0.78, size.height * 0.86), 80, 0.4);

    // Thin diagonal accent strokes
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1.0;
    canvas.drawLine(
      Offset(0, size.height * 0.3),
      Offset(size.width * 0.55, -40),
      linePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.45, size.height + 40),
      Offset(size.width, size.height * 0.4),
      linePaint,
    );

    // A subtle amber arc top-left
    final arcPaint = Paint()
      ..color = const Color(0xFFD2913C).withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    canvas.drawCircle(const Offset(-60, -60), 220, arcPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
