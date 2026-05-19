import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cryptography/cryptography.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../config/device_code_key.dart';
import '../../services/device_service.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_routes.dart';
import '../../utils/app_theme.dart';

/// Pull a clean, human-readable message out of whatever an Edge Function
/// call threw — FunctionException wraps the server's {"error": "..."}
/// body, everything else falls back to a generic line.
String _friendlyError(Object e) {
  if (e is FunctionException) {
    final d = e.details;
    if (d is Map && d['error'] != null) return d['error'].toString();
    return 'Server error (${e.status}). Please try again.';
  }
  return 'Could not reach the server. Check your connection and try again.';
}

/// First-launch gate. Two tabs:
///   1. Enter Code  — user types the code emailed by the office.
///   2. Request Code — fills a form; the Edge Function validates the
///      username, generates a code and emails it to the office.
class DeviceActivationScreen extends StatefulWidget {
  const DeviceActivationScreen({super.key});

  @override
  State<DeviceActivationScreen> createState() => _DeviceActivationScreenState();
}

// Sentinel dropdown value for the trust (office / super-admin) device.
const int _kTrustSentinel = -1;

class _DeviceActivationScreenState extends State<DeviceActivationScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final _codeController = TextEditingController();
  bool _activating = false;
  String? _activateError;

  final _usernameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  List<Map<String, dynamic>> _institutions = [];
  int? _selectedInsId;
  bool _loadingInstitutions = true;
  final String _trustName = 'Super Admin';
  bool _requesting = false;
  String? _requestError;
  bool _requestSent = false;

  String? _deviceId;
  String? _machineName;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadDeviceInfo();
    _loadInstitutions();
  }

  Future<void> _loadDeviceInfo() async {
    final id = await DeviceService.getDeviceId();
    final name = await DeviceService.getMachineName();
    if (!mounted) return;
    setState(() {
      _deviceId = id;
      _machineName = name;
    });
  }

  Future<void> _loadInstitutions() async {
    try {
      final list = await SupabaseService.getInstitutionNames();
      if (!mounted) return;
      setState(() {
        _institutions = list;
        _loadingInstitutions = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingInstitutions = false);
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    _codeController.dispose();
    _usernameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  /// AES-256-GCM decrypt of the encrypted device-code payload. The blob
  /// is base64( 12-byte IV || ciphertext || 16-byte GCM tag ) — the
  /// layout produced by the request-device-code Edge Function.
  Future<String> _decryptPayload(String b64) async {
    final combined = base64Decode(b64);
    final iv = combined.sublist(0, 12);
    final rest = combined.sublist(12);
    final tag = rest.sublist(rest.length - 16);
    final cipherText = rest.sublist(0, rest.length - 16);
    final algorithm = AesGcm.with256bits();
    final secretKey = SecretKey(base64Decode(DeviceCodeKey.base64Key));
    final clear = await algorithm.decrypt(
      SecretBox(cipherText, nonce: iv, mac: Mac(tag)),
      secretKey: secretKey,
    );
    return utf8.decode(clear);
  }

  /// Import the activation code from the file the office sends. The file
  /// holds an AES-encrypted payload (or plain JSON for older codes);
  /// either way we pull the `code` field, fill it in, and activate.
  Future<void> _importCode() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt', 'dat'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final file = result.files.first;
      String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!);
      } else if (file.path != null) {
        content = await File(file.path!).readAsString();
      } else {
        setState(() => _activateError = 'Could not read the selected file');
        return;
      }

      content = content.trim();
      // The office email fences the encrypted block between markers.
      // Extract it if present; otherwise use the whole file content.
      const begin = '-----BEGIN ACTIVATION-----';
      const end = '-----END ACTIVATION-----';
      final bi = content.indexOf(begin);
      final ei = content.indexOf(end);
      String blob = (bi != -1 && ei != -1 && ei > bi)
          ? content.substring(bi + begin.length, ei).trim()
          : content;

      // Plain JSON (legacy / no key) starts with '{'; otherwise it's an
      // AES-encrypted base64 blob that we decrypt first.
      String jsonStr;
      if (blob.startsWith('{')) {
        jsonStr = blob;
      } else {
        jsonStr = await _decryptPayload(blob);
      }

      final decoded = jsonDecode(jsonStr);
      final code = (decoded is Map ? decoded['code'] : null)?.toString();
      if (code == null || code.trim().isEmpty) {
        setState(() => _activateError = 'No activation code found in the file');
        return;
      }
      _codeController.text = code.trim();
      await _activate();
    } catch (e) {
      if (!mounted) return;
      setState(() => _activateError =
          'Invalid file — expected the activation file sent by the office');
    }
  }

  Future<void> _activate() async {
    final code = _codeController.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _activateError = 'Enter the activation code');
      return;
    }
    setState(() {
      _activating = true;
      _activateError = null;
    });
    final result = await DeviceService.activate(code);
    if (!mounted) return;
    if (result.ok) {
      Navigator.pushReplacementNamed(context, AppRoutes.welcome);
    } else {
      setState(() {
        _activating = false;
        _activateError = result.error ?? 'Activation failed';
      });
    }
  }

  Future<void> _requestCode() async {
    if (_selectedInsId == null) {
      setState(() => _requestError = 'Pick your institution or trust');
      return;
    }
    if (_usernameController.text.trim().isEmpty) {
      setState(() => _requestError = 'Username is required');
      return;
    }
    if (_mobileController.text.replaceAll(RegExp(r'\D'), '').length < 10) {
      setState(() => _requestError = 'Enter a valid 10-digit mobile number');
      return;
    }
    final email = _emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _requestError = 'Enter a valid email address');
      return;
    }
    setState(() {
      _requesting = true;
      _requestError = null;
    });
    try {
      final isTrust = _selectedInsId == _kTrustSentinel;
      final insName = isTrust
          ? _trustName
          : _institutions.firstWhere(
              (i) => i['ins_id'] == _selectedInsId,
              orElse: () => const {'insname': null},
            )['insname'] as String?;
      final resp = await SupabaseService.client.functions.invoke(
        'request-device-code',
        body: {
          'insId': isTrust ? null : _selectedInsId,
          'insName': insName,
          'username': _usernameController.text.trim(),
          'mobile': _mobileController.text.trim(),
          'email': _emailController.text.trim(),
          'machineName': _machineName ?? '',
          'deviceId': _deviceId ?? '',
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
        _requestError = _friendlyError(e);
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
                  Icon(Icons.verified_user_rounded,
                      size: 48.sp, color: AppColors.primary),
                  SizedBox(height: 12.h),
                  Text(
                    'Activate this PC',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                  ),
                  SizedBox(height: 16.h),
                  TabBar(
                    controller: _tabController,
                    labelColor: AppColors.primary,
                    indicatorColor: AppColors.primary,
                    tabs: const [
                      Tab(text: 'Request Code'),
                      Tab(text: 'Enter Code'),
                    ],
                  ),
                  SizedBox(height: 16.h),
                  SizedBox(
                    height: 440.h,
                    child: TabBarView(
                      controller: _tabController,
                      children: [_buildRequestCodeTab(), _buildEnterCodeTab()],
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

  Widget _buildEnterCodeTab() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 8.h),
          Text(
            'Enter the activation code, or import the file the office sent you.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
          ),
          SizedBox(height: 12.h),
          OutlinedButton.icon(
            onPressed: _activating ? null : _importCode,
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: BorderSide(color: AppColors.primary),
              padding: EdgeInsets.symmetric(vertical: 12.h),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.r),
              ),
            ),
            icon: const Icon(Icons.upload_file_rounded),
            label: Text('Import Code File',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
          ),
          SizedBox(height: 14.h),
          Row(
            children: [
              const Expanded(child: Divider()),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 10.w),
                child: Text('or enter manually',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11.sp)),
              ),
              const Expanded(child: Divider()),
            ],
          ),
          SizedBox(height: 14.h),
          TextField(
            controller: _codeController,
            autofocus: true,
            textCapitalization: TextCapitalization.characters,
            style: TextStyle(fontFamily: 'monospace', fontSize: 18.sp, letterSpacing: 2),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9\-]')),
              LengthLimitingTextInputFormatter(19),
            ],
            decoration: InputDecoration(
              labelText: 'Activation Code',
              hintText: 'XXXX-XXXX-XXXX-XXXX',
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
                : Text('Activate',
                    style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestCodeTab() {
    if (_loadingInstitutions) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_requestSent) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(16.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.mark_email_read_rounded, size: 56.sp, color: AppColors.success),
              SizedBox(height: 16.h),
              Text('Request sent',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      )),
              SizedBox(height: 8.h),
              Text(
                'The office will email or message your activation code shortly. Switch to the Enter Code tab when you receive it.',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13.sp),
              ),
              SizedBox(height: 16.h),
              TextButton.icon(
                onPressed: () => _tabController.animateTo(1),
                icon: const Icon(Icons.arrow_forward_rounded),
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
          Text(
            'Fill the form and we will email a fresh code to the office. They will forward it to you.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12.sp),
          ),
          SizedBox(height: 12.h),
          DropdownButtonFormField<int>(
            value: _selectedInsId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Institution / Trust',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              isDense: true,
            ),
            items: [
              DropdownMenuItem<int>(
                value: _kTrustSentinel,
                child: Text('★ $_trustName', overflow: TextOverflow.ellipsis),
              ),
              ..._institutions.map<DropdownMenuItem<int>>(
                (i) => DropdownMenuItem<int>(
                  value: i['ins_id'] as int,
                  child: Text(i['insname']?.toString() ?? '—',
                      overflow: TextOverflow.ellipsis),
                ),
              ),
            ],
            onChanged: (v) => setState(() => _selectedInsId = v),
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _usernameController,
            decoration: InputDecoration(
              labelText: 'Username *',
              hintText: 'Your login username / email',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              isDense: true,
            ),
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _mobileController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: 'Mobile *',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              isDense: true,
            ),
          ),
          SizedBox(height: 10.h),
          TextField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: 'Email *',
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
            onPressed: _requesting ? null : _requestCode,
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
            label: Text('Request Activation Code',
                style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600)),
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
