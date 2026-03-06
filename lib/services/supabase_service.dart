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

  // ==================== INSTITUTION ====================

  /// Get institution name and logo from the institution table
  static Future<({String? name, String? logo})> getInstitutionInfo(int insId) async {
    try {
      final result = await client
          .from('institution')
          .select('insname, inslogo')
          .eq('ins_id', insId)
          .maybeSingle();
      return (
        name: result?['insname'] as String?,
        logo: result?['inslogo'] as String?,
      );
    } catch (e) {
      debugPrint('Error fetching institution info: $e');
      return (name: null, logo: null);
    }
  }

  // ==================== STUDENTS ====================

  /// Get total active student count for an institution
  static Future<int> getStudentCount(int insId) async {
    try {
      final count = await client
          .from('students')
          .count()
          .eq('ins_id', insId)
          .eq('activestatus', 1);
      return count;
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

  /// Add a new student record — returns the new stu_id
  static Future<int> addStudent(Map<String, dynamic> data) async {
    final response = await client
        .from('students')
        .insert(data)
        .select('stu_id')
        .maybeSingle();
    if (response == null) throw Exception('Student insert returned no data (check RLS or required columns)');
    return response['stu_id'] as int;
  }

  /// Update an existing student record
  static Future<void> updateStudent(int stuId, Map<String, dynamic> data) async {
    await client.from('students').update(data).eq('stu_id', stuId);
  }

  /// Get academic years for an institution
  static Future<List<Map<String, dynamic>>> getYears(int insId) async {
    try {
      final response = await client
          .from('year')
          .select('yr_id, yrlabel')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('yr_id', ascending: false);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching years: $e');
      return [];
    }
  }

  /// Get distinct class names for an institution
  static Future<List<String>> getClasses(int insId) async {
    try {
      final response = await client
          .from('students')
          .select('stuclass')
          .eq('ins_id', insId)
          .eq('activestatus', 1);
      final classes = (response as List)
          .map((r) => r['stuclass']?.toString() ?? '')
          .where((c) => c.isNotEmpty)
          .toSet()
          .toList();
      classes.sort();
      return classes;
    } catch (e) {
      debugPrint('Error fetching classes: $e');
      return [];
    }
  }

  /// Get concession categories for an institution
  static Future<List<Map<String, dynamic>>> getConcessions(int insId) async {
    try {
      final response = await client
          .from('concessioncategory')
          .select('con_id, condesc')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('con_id', ascending: true);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching concessions: $e');
      return [];
    }
  }

  /// Find an existing parent record — checks fathermobile, then mothermobile,
  /// then payinchargemob in order. Returns par_id of first match, or null.
  static Future<int?> findParentByMobile({
    String? fatherMobile,
    String? motherMobile,
    String? payMobile,
  }) async {
    if (fatherMobile != null && fatherMobile.isNotEmpty) {
      final result = await client
          .from('parents')
          .select('par_id')
          .eq('fathermobile', fatherMobile)
          .eq('activestatus', 1)
          .maybeSingle();
      if (result != null) return result['par_id'] as int;
    }
    if (motherMobile != null && motherMobile.isNotEmpty) {
      final result = await client
          .from('parents')
          .select('par_id')
          .eq('mothermobile', motherMobile)
          .eq('activestatus', 1)
          .maybeSingle();
      if (result != null) return result['par_id'] as int;
    }
    if (payMobile != null && payMobile.isNotEmpty) {
      final result = await client
          .from('parents')
          .select('par_id')
          .eq('payinchargemob', payMobile)
          .eq('activestatus', 1)
          .maybeSingle();
      if (result != null) return result['par_id'] as int;
    }
    return null;
  }

  /// Insert parent record — returns the new par_id
  static Future<int> saveParent(Map<String, dynamic> data) async {
    final response = await client
        .from('parents')
        .insert(data)
        .select('par_id')
        .maybeSingle();
    if (response == null) throw Exception('Parent insert returned no data (check RLS or required columns)');
    return response['par_id'] as int;
  }

  /// Insert parentdetail record linking student ↔ parent
  static Future<void> saveParentDetail(Map<String, dynamic> data) async {
    await client.from('parentdetail').insert(data);
  }

  /// Fetch parent record for a given student (via parentdetail → parents)
  static Future<Map<String, dynamic>?> getStudentParent(int stuId) async {
    try {
      final detail = await client
          .from('parentdetail')
          .select('par_id')
          .eq('stu_id', stuId)
          .maybeSingle();
      if (detail == null) return null;
      final parId = detail['par_id'] as int;
      final parent = await client
          .from('parents')
          .select('*')
          .eq('par_id', parId)
          .maybeSingle();
      return parent;
    } catch (e) {
      debugPrint('Error fetching student parent: $e');
      return null;
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

  // ==================== FEE GROUPS ====================

  /// Get all active fee groups for an institution
  static Future<List<Map<String, dynamic>>> getFeeGroups(int insId) async {
    try {
      final response = await client
          .from('feegroup')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('fg_id', ascending: true);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching fee groups: $e');
      return [];
    }
  }

  /// Insert a fee group — returns the new fg_id
  static Future<int> addFeeGroup(Map<String, dynamic> data) async {
    final response = await client
        .from('feegroup')
        .insert(data)
        .select('fg_id')
        .maybeSingle();
    if (response == null) throw Exception('Fee group insert returned no data');
    return response['fg_id'] as int;
  }

  // ==================== FEE MASTER ====================

  /// Get all active fee master records for an institution
  static Future<List<Map<String, dynamic>>> getFeesMaster(int insId) async {
    try {
      // feetype has no ins_id — filter via fee group IDs belonging to this institution
      final feeGroups = await getFeeGroups(insId);
      if (feeGroups.isEmpty) return [];
      final fgIds = feeGroups.map((fg) => fg['fg_id'] as int).toList();
      final response = await client
          .from('feetype')
          .select('*')
          .inFilter('fg_id', fgIds)
          .eq('activestatus', 1)
          .order('fee_id', ascending: true);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching fees master: $e');
      return [];
    }
  }

  /// Insert a fee master record — returns the new fee_id
  static Future<int> addFeeMaster(Map<String, dynamic> data) async {
    final response = await client
        .from('feetype')
        .insert(data)
        .select('fee_id')
        .maybeSingle();
    if (response == null) throw Exception('Fee insert returned no data');
    return response['fee_id'] as int;
  }

  // ==================== FEES ====================

  /// Get all fee demands for an institution (with student name)
  static Future<List<Map<String, dynamic>>> getFeeDemands(int insId) async {
    try {
      final response = await client
          .from('feedemand')
          .select('*, students(stuname)')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('stuclass', ascending: true);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching fee demands: $e');
      // Fallback without student join
      try {
        final response = await client
            .from('feedemand')
            .select('*')
            .eq('ins_id', insId)
            .eq('activestatus', 1)
            .order('stuclass', ascending: true);
        return List<Map<String, dynamic>>.from(response as List);
      } catch (e2) {
        debugPrint('Error fetching fee demands (fallback): $e2');
        return [];
      }
    }
  }

  /// Get fee collection summary for an institution
  /// Fee Collection = sum of transtotalamount from payment table where paystatus='C'
  /// Pending Fees = sum of balancedue from feedemand table where paidstatus='U'
  static Future<FeeSummary> getFeeSummary(int insId) async {
    try {
      // Use RPC for server-side aggregation of pending balance (avoids 1000-row cap)
      final rpcResult = await client
          .rpc('get_fee_summary', params: {'p_ins_id': insId});

      final totalPending =
          (rpcResult['total_pending'] as num?)?.toDouble() ?? 0;
      final pendingCount = (rpcResult['pending_count'] as num?)?.toInt() ?? 0;

      // Fetch total due from feedemand
      final feedemandResponse = await client
          .from('feedemand')
          .select('feeamount, conamount')
          .eq('ins_id', insId);

      double totalDue = 0;
      for (final row in (feedemandResponse as List)) {
        final feeamount = (row['feeamount'] as num?)?.toDouble() ?? 0;
        final conamount = (row['conamount'] as num?)?.toDouble() ?? 0;
        totalDue += feeamount - conamount;
      }

      // Fetch total collection from payment table where paystatus='C' (Completed)
      final paymentResponse = await client
          .from('payment')
          .select('transtotalamount')
          .eq('ins_id', insId)
          .eq('paystatus', 'C')
          .eq('activestatus', 1);

      double totalPaid = 0;
      for (final row in (paymentResponse as List)) {
        totalPaid += (row['transtotalamount'] as num?)?.toDouble() ?? 0;
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

  /// Get payments for an institution within a date range
  static Future<List<Map<String, dynamic>>> getPaymentsByDateRange(
    int insId, {
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final from = fromDate.toIso8601String().split('T').first;
      final to = toDate.toIso8601String().split('T').first;
      final response = await client
          .from('payment')
          .select('*, students!inner(stuname, stuadmno, stuclass)')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .eq('paystatus', 'C')
          .gte('paydate', from)
          .lte('paydate', to)
          .order('paydate', ascending: false);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching payments by date range: $e');
      // Fallback without student join (in case of FK issue)
      try {
        final from = fromDate.toIso8601String().split('T').first;
        final to = toDate.toIso8601String().split('T').first;
        final response = await client
            .from('payment')
            .select('*')
            .eq('ins_id', insId)
            .eq('activestatus', 1)
            .eq('paystatus', 'C')
            .gte('paydate', from)
            .lte('paydate', to)
            .order('paydate', ascending: false);
        return List<Map<String, dynamic>>.from(response as List);
      } catch (e2) {
        debugPrint('Error fetching payments (fallback): $e2');
        return [];
      }
    }
  }

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

  /// Get failed transactions for an institution
  static Future<List<Map<String, dynamic>>> getFailedTransactions(int insId) async {
    try {
      final response = await client
          .from('payment')
          .select('*')
          .eq('ins_id', insId)
          .eq('paystatus', 'F')
          .order('createdat', ascending: false);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching failed transactions: $e');
      return [];
    }
  }
}
