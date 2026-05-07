import 'package:flutter/material.dart';
import 'package:animate_do/animate_do.dart';
import 'package:provider/provider.dart';
import '../../services/supabase_service.dart';
import '../../utils/app_theme.dart';
import '../../utils/app_routes.dart';
import '../../utils/auth_provider.dart';

import '../../widgets/app_icon.dart';

// Match welcome_screen.dart's palette exactly so the activation/renewal
// screen visually belongs in the same flow as sign-in and forgot-password.
class _Palette {
  static const Color primary = Color(0xFF002147);
  static const Color accent = Color(0xFFD2913C);
  static const Color textBody = Color(0xFF111827);
  static const Color textMuted = Color(0xFF6B7280);

  static const LinearGradient panelGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF1E3A6B), Color(0xFF002147), Color(0xFF000A1A)],
    stops: [0.0, 0.55, 1.0],
  );
}

class SubscriptionExpiredScreen extends StatefulWidget {
  const SubscriptionExpiredScreen({super.key});

  @override
  State<SubscriptionExpiredScreen> createState() => _SubscriptionExpiredScreenState();
}

class _SubscriptionExpiredScreenState extends State<SubscriptionExpiredScreen> {
  final _codeController = TextEditingController();
  bool _activating = false;
  bool _requesting = false;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  /// Send a renewal-request email via the `request-activation-code` Edge Function.
  Future<void> _requestRenewal() async {
    final auth = context.read<AuthProvider>();
    final insName = auth.insName ?? '';
    final inscode = auth.inscode ?? '';
    final email = auth.userEmail ?? '';

    setState(() => _requesting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await SupabaseService.client.functions.invoke(
        'request-activation-code',
        body: {
          'purpose': 'renewal',
          'insName': insName,
          'inscode': inscode,
          'email': email,
        },
      );
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Request sent. The office will email you a new activation code shortly.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Could not send request: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _activateCode() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final code = _codeController.text.trim();
    final messenger = ScaffoldMessenger.of(context);

    if (insId == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Institution not identified. Sign out and log in again.'), backgroundColor: Colors.red),
      );
      return;
    }
    if (code.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Please enter the activation code first.'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _activating = true);
    try {
      final result = await SupabaseService.client.rpc(
        'activate_subscription_code',
        params: {'p_ins_id': insId, 'p_license_key': code},
      );
      final res = result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};

      if (res['ok'] == true) {
        if (mounted) {
          messenger.showSnackBar(
            const SnackBar(
              content: Text('Activation successful. Please sign in.'),
              backgroundColor: Colors.green,
            ),
          );
          await auth.logout();
          await Future.delayed(const Duration(milliseconds: 600));
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(context, AppRoutes.welcome, (_) => false);
          }
        }
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(res['reason']?.toString() ?? 'Activation failed.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Activation error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _activating = false);
    }
  }

  Future<void> _backToSignIn() async {
    final auth = context.read<AuthProvider>();
    await auth.logout();
    if (!mounted) return;
    Navigator.pushNamedAndRemoveUntil(context, AppRoutes.welcome, (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isDesktop = size.width > 900;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FB),
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Same diagonal-stripe background image as the welcome / forgot
          // password screens so this flow visually belongs to the same group.
          Positioned.fill(
            child: Image.asset(
              'assets/images/vimal-s-J69ERsG93hI-unsplash.jpg',
              fit: BoxFit.cover,
              alignment: Alignment.center,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(isDesktop ? 40 : 16),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: isDesktop ? 1080 : 520),
                  child: FadeIn(
                    duration: const Duration(milliseconds: 500),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 32,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: IntrinsicHeight(
                          child: isDesktop
                              ? Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(flex: 5, child: _buildHeroPanel()),
                                    Expanded(flex: 6, child: _buildFormPanel()),
                                  ],
                                )
                              : Column(
                                  children: [
                                    _buildHeroPanel(compact: true),
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
        ],
      ),
    );
  }

  Widget _buildHeroPanel({bool compact = false}) {
    return Container(
      padding: EdgeInsets.all(compact ? 24 : 36),
      decoration: const BoxDecoration(gradient: _Palette.panelGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + brand
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  width: 44,
                  height: 44,
                  color: Colors.white,
                  padding: const EdgeInsets.all(6),
                  child: Image.asset(
                    'assets/images/educore360_logo.png',
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const AppIcon(
                      'teacher',
                      size: 24,
                      color: _Palette.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'EduCore360',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          SizedBox(height: compact ? 32 : 56),
          const Text(
            'Run your\ninstitution with\nclarity.',
            style: TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.w800,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'A unified administration platform for fees,\nstudents, staff and reporting.',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  Widget _buildFormPanel() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Back to sign in
          FadeInDown(
            child: Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _backToSignIn,
                icon: const Icon(Icons.chevron_left_rounded, size: 18, color: _Palette.accent),
                label: const Text(
                  'Back to sign in',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: _Palette.accent,
                  ),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          FadeInDown(
            delay: const Duration(milliseconds: 100),
            child: const Text(
              'Subscription Expired',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: _Palette.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          FadeInDown(
            delay: const Duration(milliseconds: 200),
            child: const Text(
              'Enter your activation code below or request a new one from our office.',
              style: TextStyle(
                fontSize: 13,
                color: _Palette.textMuted,
                height: 1.5,
              ),
            ),
          ),

          const SizedBox(height: 28),

          FadeInDown(
            delay: const Duration(milliseconds: 300),
            child: const Text(
              'Activation Code',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _Palette.textBody),
            ),
          ),
          const SizedBox(height: 8),
          FadeInDown(
            delay: const Duration(milliseconds: 350),
            child: TextField(
              controller: _codeController,
              enabled: !_activating,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'EDU-XXXXXX-XXXXXX',
                prefixIcon: AppIcon('key', size: 20, color: AppColors.textLight),
                prefixIconConstraints: BoxConstraints(minWidth: 52, minHeight: 0),
              ),
            ),
          ),

          const SizedBox(height: 24),

          FadeInDown(
            delay: const Duration(milliseconds: 400),
            child: SizedBox(
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _activating ? null : _activateCode,
                icon: _activating
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                      )
                    : const AppIcon('tick-circle', size: 16, color: Colors.white),
                label: const Text('Activate'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _Palette.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          FadeInDown(
            delay: const Duration(milliseconds: 500),
            child: Row(
              children: [
                const Expanded(child: Divider()),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    'or',
                    style: TextStyle(
                      color: _Palette.textMuted.withValues(alpha: 0.7),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const Expanded(child: Divider()),
              ],
            ),
          ),

          const SizedBox(height: 16),

          FadeInDown(
            delay: const Duration(milliseconds: 600),
            child: SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: _requesting ? null : _requestRenewal,
                icon: _requesting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : const AppIcon('sms', size: 16),
                label: const Text(
                  'Request Activation Code',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _Palette.accent,
                  side: BorderSide(color: _Palette.accent.withValues(alpha: 0.4)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
