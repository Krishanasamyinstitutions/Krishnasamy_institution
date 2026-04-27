import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:animate_do/animate_do.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../utils/app_theme.dart';
import '../../services/supabase_service.dart';
import '../../widgets/app_icon.dart';

/// Three-step forgot-password flow for institution users (admin/staff/
/// accountant). The OTP is sent via the `send-password-reset-otp` Supabase
/// Edge Function so the BulkSMSGateway credentials never live in the app
/// binary. The Edge Function generates the OTP, stores it in
/// institutionusers.usemobotp + mobotp_at, then sends the SMS.
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

enum _Step { email, otp, password }

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _Step _step = _Step.email;
  bool _isLoading = false;
  String? _errorMessage;
  String? _maskedPhone;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _requestOtp() async {
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = 'Enter a valid email address');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final resp = await SupabaseService.client.functions.invoke(
        'send-password-reset-otp', body: {'email': email},
      );
      final data = resp.data;
      // Surface server-side detail when the function rejects the request
      // — without it, "Could not send OTP" gives the user no clue whether
      // it's a missing function deploy, missing secret, or gateway issue.
      if (resp.status >= 400) {
        setState(() {
          _isLoading = false;
          _errorMessage = data is Map
              ? (data['error']?.toString() ?? 'Server error (${resp.status})')
              : 'Server error (${resp.status})';
        });
        return;
      }
      if (data is Map && data['error'] != null) {
        setState(() {
          _isLoading = false;
          _errorMessage = data['error'].toString();
        });
        return;
      }
      setState(() {
        _isLoading = false;
        _step = _Step.otp;
        _maskedPhone = (data is Map ? data['masked'] : null)?.toString();
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'OTP request failed: $e';
      });
    }
  }

  Future<void> _verifyOtp() async {
    final otp = int.tryParse(_otpController.text.trim());
    if (otp == null || otp < 100000 || otp > 999999) {
      setState(() => _errorMessage = 'Enter the 6-digit OTP from SMS');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final ok = await SupabaseService.client.rpc('verify_password_reset_otp', params: {
        'p_email': _emailController.text.trim(),
        'p_otp': otp,
      });
      if (ok == true) {
        setState(() { _isLoading = false; _step = _Step.password; });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Invalid or expired OTP. Try again or request a new one.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Verification failed. Try again.';
      });
    }
  }

  Future<void> _resetPassword() async {
    final pwd = _newPasswordController.text;
    final confirm = _confirmPasswordController.text;
    if (pwd.length < 6) {
      setState(() => _errorMessage = 'Password must be at least 6 characters');
      return;
    }
    if (pwd != confirm) {
      setState(() => _errorMessage = 'Passwords do not match');
      return;
    }
    setState(() { _isLoading = true; _errorMessage = null; });
    try {
      final ok = await SupabaseService.client.rpc('complete_password_reset', params: {
        'p_email': _emailController.text.trim(),
        'p_new_password': pwd,
      });
      if (ok == true) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Password reset successful. Please sign in with your new password.'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Reset failed. Restart the process and try again.';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Could not save the new password. Try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(40.w),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                SizedBox(height: 30.h),
                _buildIcon(),
                SizedBox(height: 24.h),
                _buildTitle(),
                SizedBox(height: 10.h),
                _buildSubtitle(),
                SizedBox(height: 28.h),
                if (_errorMessage != null) ...[
                  Container(
                    padding: EdgeInsets.all(12.w),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(10.r),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(children: [
                      Icon(Icons.error_outline, color: Colors.red.shade700, size: 18.sp),
                      SizedBox(width: 8.w),
                      Expanded(child: Text(_errorMessage!,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13.sp))),
                    ]),
                  ),
                  SizedBox(height: 18.h),
                ],
                if (_step == _Step.email) _buildEmailForm(),
                if (_step == _Step.otp) _buildOtpForm(),
                if (_step == _Step.password) _buildPasswordForm(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcon() {
    final iconName = switch (_step) {
      _Step.email => 'sms-tracking',
      _Step.otp => 'shield-tick',
      _Step.password => 'password-check',
    };
    return Center(
      child: Container(
        width: 80.w,
        height: 80.w,
        decoration: BoxDecoration(
          color: AppColors.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: AppIcon(iconName, size: 40, color: AppColors.accent),
      ),
    );
  }

  Widget _buildTitle() {
    final title = switch (_step) {
      _Step.email => 'Forgot Password?',
      _Step.otp => 'Enter the OTP',
      _Step.password => 'Set a New Password',
    };
    return Text(title, textAlign: TextAlign.center, style: Theme.of(context).textTheme.displayMedium);
  }

  Widget _buildSubtitle() {
    final text = switch (_step) {
      _Step.email =>
        'Enter your registered email. We\'ll send a 6-digit OTP to the mobile number on file.',
      _Step.otp =>
        _maskedPhone != null && _maskedPhone!.isNotEmpty
            ? 'OTP sent to $_maskedPhone. Enter the 6-digit code below.'
            : 'Enter the 6-digit code we sent to your mobile.',
      _Step.password => 'Create a new password (minimum 6 characters).',
    };
    return Text(text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5));
  }

  Widget _buildEmailForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Email Address', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
      TextFormField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        decoration: InputDecoration(
          hintText: 'you@school.edu',
          prefixIcon: const AppIcon.linear('sms', size: 20, color: AppColors.textLight),
          prefixIconConstraints: BoxConstraints(minWidth: 52.w, minHeight: 0),
        ),
      ),
      SizedBox(height: 24.h),
      SizedBox(
        height: 52.h,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _requestOtp,
          child: _isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Send OTP'),
        ),
      ),
    ]);
  }

  Widget _buildOtpForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('OTP', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
      TextFormField(
        controller: _otpController,
        keyboardType: TextInputType.number,
        maxLength: 6,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          hintText: '6-digit OTP',
          counterText: '',
          prefixIcon: const AppIcon.linear('shield-tick', size: 20, color: AppColors.textLight),
          prefixIconConstraints: BoxConstraints(minWidth: 52.w, minHeight: 0),
        ),
      ),
      SizedBox(height: 8.h),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton(
          onPressed: _isLoading ? null : _requestOtp,
          child: const Text('Resend OTP'),
        ),
      ),
      SizedBox(height: 16.h),
      SizedBox(
        height: 52.h,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _verifyOtp,
          child: _isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Verify OTP'),
        ),
      ),
    ]);
  }

  Widget _buildPasswordForm() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('New Password', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
      TextFormField(
        controller: _newPasswordController,
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          hintText: 'At least 6 characters',
          prefixIcon: const AppIcon.linear('lock', size: 20, color: AppColors.textLight),
          prefixIconConstraints: BoxConstraints(minWidth: 52.w, minHeight: 0),
          suffixIcon: IconButton(
            icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined),
            onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
          ),
        ),
      ),
      SizedBox(height: 16.h),
      Text('Confirm Password', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600)),
      SizedBox(height: 8.h),
      TextFormField(
        controller: _confirmPasswordController,
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          hintText: 'Re-enter password',
          prefixIcon: const AppIcon.linear('lock', size: 20, color: AppColors.textLight),
          prefixIconConstraints: BoxConstraints(minWidth: 52.w, minHeight: 0),
        ),
      ),
      SizedBox(height: 24.h),
      SizedBox(
        height: 52.h,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _resetPassword,
          child: _isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : const Text('Reset Password'),
        ),
      ),
    ]);
  }
}
