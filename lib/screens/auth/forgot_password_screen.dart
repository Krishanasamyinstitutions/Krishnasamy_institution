import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';

import '../../widgets/app_icon.dart';
class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  bool _emailSent = false;

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _handleReset() async {
    if (!_formKey.currentState!.validate()) return;

    final authProvider = context.read<AuthProvider>();
    await authProvider.resetPassword(_emailController.text.trim());

    if (mounted) {
      setState(() => _emailSent = true);
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

                SizedBox(height: 40.h),

                // Icon
                FadeInDown(
                  delay: const Duration(milliseconds: 100),
                  child: Center(
                    child: Container(
                      width: 80.w,
                      height: 80.h,
                      decoration: BoxDecoration(
                        color: _emailSent
                            ? AppColors.success.withValues(alpha: 0.1)
                            : AppColors.secondary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(22.r),
                      ),
                      child: AppIcon(
                        _emailSent
                            ? 'sms-tracking'
                            : 'password-check',
                        size: 40.sp,
                        color: _emailSent
                            ? AppColors.success
                            : AppColors.secondary,
                      ),
                    ),
                  ),
                ),

                SizedBox(height: 28.h),

                FadeInDown(
                  delay: const Duration(milliseconds: 200),
                  child: Text(
                    _emailSent ? 'Check Your Email' : 'Forgot Password?',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displayMedium,
                  ),
                ),

                SizedBox(height: 12.h),

                FadeInDown(
                  delay: const Duration(milliseconds: 300),
                  child: Text(
                    _emailSent
                        ? 'We\'ve sent a password reset link to\n${_emailController.text.trim()}'
                        : 'No worries! Enter your email address and we\'ll send you a link to reset your password.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.6,
                        ),
                  ),
                ),

                SizedBox(height: 36.h),

                if (!_emailSent) ...[
                  FadeInDown(
                    delay: const Duration(milliseconds: 400),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Email Address',
                            style: Theme.of(context)
                                .textTheme
                                .labelLarge
                                ?.copyWith(fontSize: 13.sp),
                          ),
                          SizedBox(height: 8.h),
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            decoration: InputDecoration(
                              hintText: 'you@school.edu',
                              prefixIcon: AppIcon.linear('sms',
                                  size: 20, color: AppColors.textLight),
                              prefixIconConstraints:
                                  BoxConstraints(minWidth: 52.w, minHeight: 0),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!value.contains('@')) {
                                return 'Please enter a valid email';
                              }
                              return null;
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 28.h),
                  FadeInDown(
                    delay: const Duration(milliseconds: 500),
                    child: Consumer<AuthProvider>(
                      builder: (context, auth, _) {
                        return SizedBox(
                          height: 54.h,
                          child: ElevatedButton(
                            onPressed: auth.isLoading ? null : _handleReset,
                            child: auth.isLoading
                                ? SizedBox(
                                    width: 22.w,
                                    height: 22.h,
                                    child: const CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text('Send Reset Link'),
                          ),
                        );
                      },
                    ),
                  ),
                ] else ...[
                  FadeInUp(
                    child: Column(
                      children: [
                        SizedBox(
                          height: 54.h,
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() => _emailSent = false);
                              _emailController.clear();
                            },
                            child: const Text('Try a Different Email'),
                          ),
                        ),
                        SizedBox(height: 16.h),
                        SizedBox(
                          height: 54.h,
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('Back to Sign In'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
