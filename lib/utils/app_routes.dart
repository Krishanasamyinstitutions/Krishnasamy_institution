import 'package:flutter/material.dart';
import '../screens/splash/splash_screen.dart';
import '../screens/onboarding/onboarding_screen.dart';
import '../screens/welcome/welcome_screen.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/register_screen.dart';
import '../screens/auth/activation_screen.dart';
import '../screens/auth/forgot_password_screen.dart';
import '../screens/auth/subscription_expired_screen.dart';
import '../screens/dashboard/dashboard_screen.dart';

class AppRoutes {
  static const String splash = '/';
  static const String activation = '/activation';
  static const String subscriptionExpired = '/subscription-expired';
  static const String onboarding = '/onboarding';
  static const String welcome = '/welcome';
  static const String login = '/login';
  static const String register = '/register';
  static const String forgotPassword = '/forgot-password';
  static const String dashboard = '/dashboard';

  static Map<String, WidgetBuilder> get routes => {
        splash: (context) => const SplashScreen(),
        activation: (context) => const ActivationScreen(),
        subscriptionExpired: (context) => const SubscriptionExpiredScreen(),
        onboarding: (context) => const OnboardingScreen(),
        welcome: (context) => const WelcomeScreen(),
        login: (context) => const LoginScreen(),
        register: (context) => const RegisterScreen(),
        forgotPassword: (context) => const ForgotPasswordScreen(),
        dashboard: (context) => const DashboardScreen(),
      };
}
