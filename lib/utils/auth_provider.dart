import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/institution_user_model.dart';

const _kEmail = 'saved_email';
const _kPassword = 'saved_password';

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  String? _userEmail;
  String? _userName;
  String? _userRole;
  String? _errorMessage;
  int? _insId;
  String? _inscode;
  InstitutionUserModel? _currentUser;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get userRole => _userRole;
  String? get errorMessage => _errorMessage;
  int? get insId => _insId;
  String? get inscode => _inscode;
  InstitutionUserModel? get currentUser => _currentUser;

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await SupabaseService.loginUser(
        email: email,
        password: password,
      );

      if (user != null) {
        _isAuthenticated = true;
        _currentUser = user;
        _userEmail = user.usemail;
        _userName = user.usename;
        _userRole = user.desname;
        _insId = user.insId;
        _inscode = user.inscode;
        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _errorMessage = 'Invalid email or password. Please try again.';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _errorMessage = 'Login failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> register(
      String name, String email, String password, String role) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      // For now, registration is handled by the admin creating users in Supabase
      _errorMessage =
          'Registration is managed by the institution admin. Please contact your administrator.';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _errorMessage = 'Registration failed: ${e.toString()}';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> resetPassword(String email) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    // Password reset would need to be handled via Supabase or admin
    _isLoading = false;
    notifyListeners();
  }

  /// Auto-login using saved credentials — returns true if successful
  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString(_kEmail);
    final password = prefs.getString(_kPassword);
    if (email == null || password == null) return false;
    return login(email, password);
  }

  /// Save credentials for auto-login on next launch
  Future<void> saveCredentials(String email, String password) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, email);
    await prefs.setString(_kPassword, password);
  }

  /// Clear saved credentials (call on logout)
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmail);
    await prefs.remove(_kPassword);
  }

  Future<void> logout() async {
    await clearCredentials();
    _isAuthenticated = false;
    _currentUser = null;
    _userEmail = null;
    _userName = null;
    _userRole = null;
    _insId = null;
    _inscode = null;
    _errorMessage = null;
    notifyListeners();
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
