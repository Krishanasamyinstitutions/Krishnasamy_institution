import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_theme.dart';

/// Product-license gate. Shown by the splash when no active row exists
/// in public.tbsannuallicense, or when the most recent row is expired.
///
/// Two paths:
///   1. Enter Code  — institution types the code already sent by office
///                    → activate_product_license RPC flips alpermit='Y'.
///   2. Request     — institution fills a form; the Edge Function
///                    generates a fresh code, pre-seeds the row, and
///                    emails the code to the office for forwarding.
class ProductActivationScreen extends StatefulWidget {
  final bool expired;
  const ProductActivationScreen({super.key, this.expired = false});

  @override
  State<ProductActivationScreen> createState() => _ProductActivationScreenState();
}

class _ProductActivationScreenState extends State<ProductActivationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _codeController = TextEditingController();
  bool _activating = false;
  String? _activateError;

  final _insNameController = TextEditingController();
  final _contactController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  bool _requesting = false;
  String? _requestError;
  bool _requestSent = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _insNameController.dispose();
    _contactController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _activate() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _activateError = 'Enter the product license code');
      return;
    }
    setState(() {
      _activating = true;
      _activateError = null;
    });
    try {
      final result = await SupabaseService.client.rpc('activate_product_license', params: {
        'p_code': code,
        'p_user': 'app',
      });
      final map = Map<String, dynamic>.from(result as Map);
      final state = map['state']?.toString();
      if (state == 'activated' || state == 'already_active') {
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, AppRoutes.onboarding);
      } else {
        if (!mounted) return;
        setState(() {
          _activating = false;
          _activateError = 'Unexpected response: $state';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString().replaceFirst(RegExp(r'^.*?:\s*'), '');
      setState(() {
        _activating = false;
        _activateError = msg;
      });
    }
  }

  Future<void> _request() async {
    if (_insNameController.text.trim().isEmpty) {
      setState(() => _requestError = 'Institution / business name is required');
      return;
    }
    if (_contactController.text.trim().isEmpty) {
      setState(() => _requestError = 'Contact person is required');
      return;
    }
    setState(() {
      _requesting = true;
      _requestError = null;
    });
    try {
      String machineName;
      try {
        machineName = Platform.localHostname;
      } catch (_) {
        machineName = '';
      }
      final resp = await SupabaseService.client.functions.invoke(
        'request-product-license',
        body: {
          'insName': _insNameController.text.trim(),
          'contact': _contactController.text.trim(),
          'mobile': _mobileController.text.trim(),
          'email': _emailController.text.trim(),
          'machineName': machineName,
        },
      );
      if (!mounted) return;
      if (resp.status >= 400) {
        final data = resp.data;
        setState(() {
          _requesting = false;
          _requestError = data is Map
              ? (data['error']?.toString() ?? 'Server error (${resp.status})')
              : 'Server error (${resp.status})';
        });
        return;
      }
      setState(() {
        _requesting = false;
        _requestSent = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _requestError = 'Request failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF003166), Color(0xFF002147), Color(0xFF00152E)],
          ),
        ),
        child: Center(
          child: SingleChildScrollView(
            child: Container(
              width: 560.w,
              padding: EdgeInsets.all(32.w),
              margin: EdgeInsets.symmetric(horizontal: 24.w, vertical: 24.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16.r),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    widget.expired ? Icons.lock_clock_rounded : Icons.workspace_premium_rounded,
                    size: 48.sp,
                    color: AppColors.primary,
                  ),
                  SizedBox(height: 12.h),
                  Text(
                    widget.expired ? 'License Expired' : 'Activate Product',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                  ),
                  SizedBox(height: 6.h),
                  Text(
                    widget.expired
                        ? 'Your annual license has expired. Enter a new code from the office, or request one below.'
                        : 'Enter the product license code, or request a new one from the office.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
                  ),
                  SizedBox(height: 14.h),
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(text: 'Enter Code'),
                      Tab(text: 'Request Code'),
                    ],
                  ),
                  SizedBox(height: 14.h),
                  SizedBox(
                    height: 380.h,
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildEnterTab(), _buildRequestTab()],
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

  Widget _buildEnterTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 8.h),
          TextField(
            controller: _codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(fontFamily: 'monospace', fontSize: 16.sp, letterSpacing: 1.5),
            decoration: InputDecoration(
              labelText: 'License Code',
              hintText: 'EDU-PROD-YYYY-XXXXXXXX',
              prefixIcon: const Icon(Icons.vpn_key_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            onSubmitted: (_) => _activate(),
          ),
          if (_activateError != null) ...[
            SizedBox(height: 12.h),
            _errorBox(_activateError!),
          ],
          SizedBox(height: 16.h),
          ElevatedButton(
            onPressed: _activating ? null : _activate,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            child: _activating
                ? SizedBox(
                    height: 20.h,
                    width: 20.h,
                    child: const CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text('Activate', style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTab() {
    if (_requestSent) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_read_rounded, size: 56.sp, color: AppColors.success),
              SizedBox(height: 16.h),
              Text(
                'Request sent',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
              ),
              SizedBox(height: 8.h),
              Text(
                'The office will email or message your license code shortly. Switch to the Enter Code tab when you receive it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
              ),
              SizedBox(height: 16.h),
              TextButton.icon(
                onPressed: () => _tabController.animateTo(0),
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Go to Enter Code'),
              ),
            ],
          ),
        ),
      );
    }
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 8.h),
          TextField(
            controller: _insNameController,
            decoration: InputDecoration(
              labelText: 'Institution / Business *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              isDense: true,
            ),
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _contactController,
            decoration: InputDecoration(
              labelText: 'Contact Person *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              isDense: true,
            ),
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            decoration: InputDecoration(
              labelText: 'Mobile',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              isDense: true,
            ),
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              isDense: true,
            ),
          ),
          if (_requestError != null) ...[
            SizedBox(height: 12.h),
            _errorBox(_requestError!),
          ],
          SizedBox(height: 14.h),
          ElevatedButton.icon(
            onPressed: _requesting ? null : _request,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14.h),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
            ),
            icon: _requesting
                ? SizedBox(
                    height: 18.h,
                    width: 18.h,
                    child: const CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                : const Icon(Icons.send_rounded),
            label: Text(
              'Request License Code',
              style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBox(String msg) {
    return Container(
      padding: EdgeInsets.all(10.w),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(8.r),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16.sp, color: Colors.red.shade700),
          SizedBox(width: 8.w),
          Expanded(
            child: Text(msg, style: TextStyle(color: Colors.red.shade700, fontSize: 12.sp)),
          ),
        ],
      ),
    );
  }
}
