import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/student_model.dart';
import '../models/institution_user_model.dart';
import '../models/payment_model.dart';
import '../models/fee_model.dart';

/// Central Supabase service for all database queries
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  // ==================== AUTH ====================

  /// Login institution user by email, returns user if found
  static Future<InstitutionUserModel?> loginUser({
    required String email,
    required String password,
  }) async {
    try {
      final response = await client
          .from('institutionusers')
          .select()
          .eq('usemail', email.trim().toLowerCase())
          .eq('activestatus', 1)
          .maybeSingle();

      if (response == null) return null;

      final user = InstitutionUserModel.fromJson(response);

      // Check password (plain text comparison for now, matching mobile app pattern)
      if (user.usepassword == null || user.usepassword != password) {
        // Try verify_password RPC if available
        try {
          final verifyResult = await client.rpc('verify_password', params: {
            'plain_password': password,
            'hashed_password': user.usepassword,
          });
          final isValid = verifyResult == true ||
              verifyResult == 'true' ||
              verifyResult == 't' ||
              verifyResult.toString() == 'true';
          if (!isValid) return null;
        } catch (_) {
          // If RPC not available, fall back to direct comparison
          if (user.usepassword != password) return null;
        }
      }

      return user;
    } catch (e) {
      debugPrint('Login error: $e');
      return null;
    }
  }

  // ==================== STUDENTS ====================

  /// Get total active student count for an institution
  static Future<int> getStudentCount(int insId) async {
    try {
      final response = await client
          .from('students')
          .select('stu_id')
          .eq('ins_id', insId)
          .eq('activestatus', 1);
      return (response as List).length;
    } catch (e) {
      debugPrint('Error getting student count: $e');
      return 0;
    }
  }

  /// Get all active students for an institution
  static Future<List<StudentModel>> getStudents(int insId) async {
    try {
      final response = await client
          .from('students')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('stuname', ascending: true);
      return (response as List)
          .map((e) => StudentModel.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error fetching students: $e');
      return [];
    }
  }

  // ==================== TEACHERS / STAFF ====================

  /// Get total active staff count for an institution
  static Future<int> getTeacherCount(int insId) async {
    try {
      final response = await client
          .from('institutionusers')
          .select('use_id')
          .eq('ins_id', insId)
          .eq('activestatus', 1);
      return (response as List).length;
    } catch (e) {
      debugPrint('Error getting teacher count: $e');
      return 0;
    }
  }

  /// Get all active staff for an institution
  static Future<List<InstitutionUserModel>> getInstitutionUsers(
      int insId) async {
    try {
      final response = await client
          .from('institutionusers')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('usename', ascending: true);
      return (response as List)
          .map((e) => InstitutionUserModel.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error fetching institution users: $e');
      return [];
    }
  }

  // ==================== FEES ====================

  /// Get fee collection summary for an institution
  static Future<FeeSummary> getFeeSummary(int insId) async {
    try {
      final response = await client
          .from('feedemand')
          .select('feeamount, conamount, paidamount, balancedue, paidstatus')
          .eq('ins_id', insId)
          .eq('activestatus', 1);

      double totalDue = 0;
      double totalPaid = 0;
      double totalPending = 0;
      int pendingCount = 0;

      for (final row in (response as List)) {
        final feeamount = (row['feeamount'] as num?)?.toDouble() ?? 0;
        final conamount = (row['conamount'] as num?)?.toDouble() ?? 0;
        final paidamount = (row['paidamount'] as num?)?.toDouble() ?? 0;
        final balancedue = (row['balancedue'] as num?)?.toDouble() ?? 0;

        totalDue += feeamount - conamount;
        totalPaid += paidamount;
        totalPending += balancedue;

        if (row['paidstatus'] == 'U' && balancedue > 0) {
          pendingCount++;
        }
      }

      return FeeSummary(
        totalDue: totalDue,
        totalPaid: totalPaid,
        totalPending: totalPending,
        pendingCount: pendingCount,
      );
    } catch (e) {
      debugPrint('Error fetching fee summary: $e');
      return FeeSummary(
          totalDue: 0, totalPaid: 0, totalPending: 0, pendingCount: 0);
    }
  }

  // ==================== PAYMENTS ====================

  /// Get recent payments for an institution
  static Future<List<PaymentModel>> getRecentPayments(int insId,
      {int limit = 10}) async {
    try {
      final response = await client
          .from('payment')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('createdat', ascending: false)
          .limit(limit);
      return (response as List)
          .map((e) => PaymentModel.fromJson(e))
          .toList();
    } catch (e) {
      debugPrint('Error fetching recent payments: $e');
      return [];
    }
  }
}
