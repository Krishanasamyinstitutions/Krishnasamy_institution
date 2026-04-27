import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/supabase_service.dart';
import '../models/institution_user_model.dart';

const _kEmail = 'saved_email';
const _kPassword = 'saved_password';
const _kInsId = 'saved_ins_id';
const _kIsSuperAdmin = 'saved_is_super_admin';
const _kSchema = 'saved_schema';

// Password is kept in the OS secure store (Keychain / Keystore / DPAPI /
// libsecret). Other non-sensitive fields stay in SharedPreferences.
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
);

class AuthProvider extends ChangeNotifier {
  bool _isAuthenticated = false;
  bool _isLoading = false;
  bool _subscriptionActive = false;
  bool _isSuperAdmin = false;
  String? _schema;
  String? _userEmail;
  String? _userName;
  String? _userRole;
  String? _errorMessage;
  int? _insId;
  String? _inscode;
  String? _insName;
  String? _insLogo;
  String? _insAddress;
  String? _yearLabel;
  InstitutionUserModel? _currentUser;

  bool get isAuthenticated => _isAuthenticated;
  bool get isLoading => _isLoading;
  bool get subscriptionActive => _subscriptionActive;
  bool get isSuperAdmin => _isSuperAdmin;
  String? get schema => _schema;
  String? get userEmail => _userEmail;
  String? get userName => _userName;
  String? get userRole => _userRole;
  String? get errorMessage => _errorMessage;
  int? get insId => _insId;
  String? get inscode => _inscode;
  String? get insName => _insName;
  String? get insLogo => _insLogo;
  String? get insAddress => _insAddress;
  String? get yearLabel => _yearLabel;
  InstitutionUserModel? get currentUser => _currentUser;

  Future<bool> login(String email, String password, {int? insId, bool isSuperAdmin = false, String? yearLabel}) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final user = await SupabaseService.loginUser(
        email: email,
        password: password,
        insId: insId,
        isSuperAdmin: isSuperAdmin,
        selectedYearLabel: yearLabel,
      );

      if (user != null) {
        _isAuthenticated = true;
        _isSuperAdmin = isSuperAdmin;
        _currentUser = user;
        _userEmail = user.usemail;
        _userName = user.usename;
        _userRole = isSuperAdmin ? 'Super Admin' : user.desname;
        _insId = user.insId;
        _inscode = user.inscode;
        _isLoading = false;
        notifyListeners();

        // Fetch institution info and set schema
        if (user.insId != null) {
          final insInfo = await SupabaseService.getInstitutionInfo(user.insId!);
          _insName = insInfo.name;
          _insLogo = insInfo.logo;
          _insAddress = insInfo.address;

          // Fetch schema name from institution table
          final insRow = await SupabaseService.client
              .from('institution')
              .select('inshortname')
              .eq('ins_id', user.insId!)
              .maybeSingle();
          if (insRow != null && insRow['inshortname'] != null) {
            // Build schema name: shortname + year (e.g. kcet20262027)
            final selectedYear = yearLabel ?? await _fetchYearLabel(user.insId!);
            final shortName = (insRow['inshortname'] as String).toLowerCase();
            _schema = '$shortName${selectedYear.replaceAll('-', '')}';
            SupabaseService.setSchema(_schema);
            // Schema exposure used to run here on every login — moved to the
            // registration flow only, so we don't hit the RPC thousands of
            // times/day for schemas that are already exposed. If a schema
            // isn't exposed PostgREST will surface a clear PGRST106 error.
          }
          notifyListeners();
        }

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
    // One-time migration: old builds stored the password in SharedPreferences.
    // Move it to secure storage and wipe the plaintext copy.
    final legacyPassword = prefs.getString(_kPassword);
    if (legacyPassword != null) {
      await _secureStorage.write(key: _kPassword, value: legacyPassword);
      await prefs.remove(_kPassword);
    }
    final password = await _secureStorage.read(key: _kPassword);
    final insId = prefs.getInt(_kInsId);
    final isSuperAdmin = prefs.getBool(_kIsSuperAdmin) ?? false;
    if (email == null || password == null) return false;
    return login(email, password, insId: insId, isSuperAdmin: isSuperAdmin);
  }

  /// Save credentials for auto-login on next launch
  Future<void> saveCredentials(String email, String password, {int? insId, bool isSuperAdmin = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kEmail, email);
    await _secureStorage.write(key: _kPassword, value: password);
    await prefs.setBool(_kIsSuperAdmin, isSuperAdmin);
    if (insId != null) {
      await prefs.setInt(_kInsId, insId);
    }
    if (_schema != null) {
      await prefs.setString(_kSchema, _schema!);
    }
  }

  /// Clear saved credentials (call on logout)
  Future<void> clearCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kEmail);
    await prefs.remove(_kPassword); // remove any legacy plaintext copy too
    await prefs.remove(_kInsId);
    await prefs.remove(_kSchema);
    await _secureStorage.delete(key: _kPassword);
  }

  Future<void> logout() async {
    await clearCredentials();
    _isAuthenticated = false;
    _subscriptionActive = false;
    _isSuperAdmin = false;
    _schema = null;
    SupabaseService.setSchema(null);
    _currentUser = null;
    _userEmail = null;
    _userName = null;
    _userRole = null;
    _insId = null;
    _inscode = null;
    _insName = null;
    _insLogo = null;
    _insAddress = null;
    _yearLabel = null;
    _errorMessage = null;
    notifyListeners();
  }

  Future<String> _fetchYearLabel(int insId) async {
    try {
      final result = await SupabaseService.client
          .from('institutionyear')
          .select('yrlabel')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('iyr_id', ascending: false)
          .limit(1)
          .maybeSingle();
      if (result != null && result['yrlabel'] != null) {
        return result['yrlabel'] as String;
      }
    } catch (e) {
      debugPrint('Fetch year label error: $e');
    }
    // Fallback: try year table
    try {
      final result = await SupabaseService.client
          .from('year')
          .select('yrlabel')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('yr_id', ascending: false)
          .limit(1)
          .maybeSingle();
      if (result != null && result['yrlabel'] != null) {
        return result['yrlabel'] as String;
      }
    } catch (_) {}
    return '${DateTime.now().year}-${DateTime.now().year + 1}';
  }

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
