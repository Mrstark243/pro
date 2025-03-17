import 'package:shared_preferences/shared_preferences.dart';
import '../services/database_helper.dart';

class AuthService {
  static final AuthService _instance = AuthService._internal();
  factory AuthService() => _instance;

  final _dbHelper = DatabaseHelper();
  static const String _isLoggedInKey = 'isLoggedIn';
  static const String _userEmailKey = 'userEmail';
  static const String _userRoleKey = 'userRole';

  AuthService._internal();

  Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_isLoggedInKey) ?? false;
  }

  Future<Map<String, dynamic>?> getCurrentUser() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool(_isLoggedInKey) ?? false;
    if (!isLoggedIn) return null;

    final email = prefs.getString(_userEmailKey);
    final role = prefs.getString(_userRoleKey);
    if (email == null || role == null) return null;

    return {
      'email': email,
      'role': role,
    };
  }

  Future<void> login(String email, String password) async {
    final user = await _dbHelper.authenticateUser(email, password);
    if (user != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_isLoggedInKey, true);
      await prefs.setString(_userEmailKey, email);
      await prefs.setString(_userRoleKey, user['role']);
    }
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_isLoggedInKey, false);
    await prefs.remove(_userEmailKey);
    await prefs.remove(_userRoleKey);
  }
} 