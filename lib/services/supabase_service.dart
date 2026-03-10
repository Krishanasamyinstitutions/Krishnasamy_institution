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

  /// Get institution name, logo, and address from the institution table
  static Future<({String? name, String? logo, String? address, String? mobile, String? email})> getInstitutionInfo(int insId) async {
    try {
      final result = await client
          .from('institution')
          .select('insname, inslogo, insaddress1, insaddress2, insaddress3, cit_id, sta_id, cou_id, inspincode, insmobno, insmail')
          .eq('ins_id', insId)
          .maybeSingle();

      if (result == null) return (name: null, logo: null, address: null, mobile: null, email: null);

      // Build full address from individual columns (split into two lines)
      final line1Parts = <String>[
        if (result['insaddress1'] != null && (result['insaddress1'] as String).isNotEmpty) result['insaddress1'] as String,
        if (result['insaddress2'] != null && (result['insaddress2'] as String).isNotEmpty) result['insaddress2'] as String,
      ];
      final line2Parts = <String>[
        if (result['insaddress3'] != null && (result['insaddress3'] as String).isNotEmpty) result['insaddress3'] as String,
        if (result['inspincode'] != null && (result['inspincode'] as String).isNotEmpty) result['inspincode'] as String,
      ];
      final lines = <String>[
        if (line1Parts.isNotEmpty) line1Parts.join(', '),
        if (line2Parts.isNotEmpty) line2Parts.join(', '),
      ];
      final address = lines.isNotEmpty ? lines.join('\n') : null;

      // inslogo column stores the full public URL directly
      final logoUrl = result['inslogo'] as String?;

      return (
        name: result['insname'] as String?,
        logo: logoUrl,
        address: address,
        mobile: result['insmobno'] as String?,
        email: result['insmail'] as String?,
      );
    } catch (e) {
      debugPrint('Error fetching institution info: $e');
      return (name: null, logo: null, address: null, mobile: null, email: null);
    }
  }

  /// Create a new institution and return the inserted row (with ins_id)
  static Future<Map<String, dynamic>?> createInstitution(Map<String, dynamic> data) async {
    try {
      final response = await client.from('institution').insert(data).select().single();
      return response;
    } catch (e, st) {
      debugPrint('Error creating institution: $e');
      debugPrint('Data: $data');
      debugPrint('Stack: $st');
      return null;
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
      const batchSize = 1000;
      int offset = 0;
      final List<Map<String, dynamic>> allResults = [];

      while (true) {
        final batch = await client
            .from('students')
            .select('*')
            .eq('ins_id', insId)
            .eq('activestatus', 1)
            .order('stuname', ascending: true)
            .range(offset, offset + batchSize - 1);

        final list = batch as List;
        allResults.addAll(list.cast<Map<String, dynamic>>());
        if (list.length < batchSize) break;
        offset += batchSize;
      }

      return allResults.map((e) => StudentModel.fromJson(e)).toList();
    } catch (e) {
      debugPrint('Error fetching students: $e');
      return [];
    }
  }

  /// Count of students per class — one row per class, used for fast class list display
  static Future<Map<String, int>> getStudentCountsByClass(int insId) async {
    try {
      final response = await client.rpc('get_student_counts_by_class', params: {'p_ins_id': insId});
      final map = <String, int>{};
      for (final row in (response as List)) {
        map[row['stuclass']?.toString() ?? ''] = (row['student_count'] as num?)?.toInt() ?? 0;
      }
      if (map.isNotEmpty) return map;
    } catch (e) {
      debugPrint('RPC get_student_counts_by_class failed, using fallback: $e');
    }
    // Fallback: count from direct query
    try {
      final students = await getStudents(insId);
      final map = <String, int>{};
      for (final s in students) {
        final cls = s.stuclass.isNotEmpty ? s.stuclass : 'Unassigned';
        map[cls] = (map[cls] ?? 0) + 1;
      }
      return map;
    } catch (e) {
      debugPrint('Fallback student count failed: $e');
      return {};
    }
  }

  /// Students for a single class — used for lazy drilldown
  static Future<List<StudentModel>> getStudentsByClass(int insId, String className) async {
    try {
      final response = await client.rpc('get_students_by_class', params: {'p_ins_id': insId, 'p_class': className});
      final list = (response as List).map((e) => StudentModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      if (list.isNotEmpty) return list;
    } catch (e) {
      debugPrint('RPC get_students_by_class failed, using fallback: $e');
    }
    // Fallback: direct query filtered by class
    try {
      final response = await client
          .from('students')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .eq('stuclass', className)
          .order('stuname', ascending: true);
      return (response as List).map((e) => StudentModel.fromJson(Map<String, dynamic>.from(e as Map))).toList();
    } catch (e) {
      debugPrint('Fallback getStudentsByClass failed: $e');
      return [];
    }
  }

  /// Get fee types (feedesc) from fee table
  static Future<List<String>> getFeeTypes(int insId) async {
    try {
      final response = await client
          .from('feetype')
          .select('feedesc')
          .eq('activestatus', 1)
          .order('fee_id', ascending: true);
      return (response as List).map((e) => e['feedesc']?.toString() ?? '').where((s) => s.isNotEmpty).toList();
    } catch (e) {
      debugPrint('Error fetching fee types: $e');
      return [];
    }
  }

  /// Lightweight: fetch only stu_id, stuname, stuadmno for name lookups
  static Future<Map<int, Map<String, String>>> getStudentNameMap(int insId) async {
    try {
      const batchSize = 1000;
      int offset = 0;
      final Map<int, Map<String, String>> result = {};
      while (true) {
        final batch = await client
            .from('students')
            .select('stu_id, stuname, stuadmno')
            .eq('ins_id', insId)
            .eq('activestatus', 1)
            .range(offset, offset + batchSize - 1);
        final list = batch as List;
        for (final s in list) {
          result[s['stu_id'] as int] = {
            'stuname': s['stuname'] as String? ?? '',
            'stuadmno': s['stuadmno'] as String? ?? '',
          };
        }
        if (list.length < batchSize) break;
        offset += batchSize;
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching student name map: $e');
      return {};
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
      const classOrder = ['PKG', 'LKG', 'UKG', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII'];
      classes.sort((a, b) {
        final idxA = classOrder.indexOf(a.toUpperCase());
        final idxB = classOrder.indexOf(b.toUpperCase());
        if (idxA >= 0 && idxB >= 0) return idxA.compareTo(idxB);
        if (idxA >= 0) return -1;
        if (idxB >= 0) return 1;
        return a.compareTo(b);
      });
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

  /// Create a new institution user (admin/staff)
  static Future<bool> createInstitutionUser(Map<String, dynamic> data) async {
    try {
      await client.from('institutionusers').insert(data);
      return true;
    } catch (e) {
      debugPrint('Error creating institution user: $e');
      return false;
    }
  }

  /// Terminate (deactivate) an institution user
  static Future<bool> terminateInstitutionUser(int useId, {required String terminatedBy, required String terminatedReason}) async {
    try {
      debugPrint('Terminating user with use_id: $useId');
      final now = DateTime.now().toIso8601String();
      await client
          .from('institutionusers')
          .update({
            'activestatus': 9,
            'terminatedby': terminatedBy,
            'terminateddate': now,
            'terminatedreason': terminatedReason,
          })
          .eq('use_id', useId);
      debugPrint('Terminate user success');
      return true;
    } catch (e, st) {
      debugPrint('Error terminating institution user: $e');
      debugPrint('Stack trace: $st');
      return false;
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
      // RETURNS json (json_agg) — single scalar bypasses PostgREST row limit
      final response = await client.rpc('get_fee_demands', params: {'p_ins_id': insId});
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('RPC get_fee_demands failed: $e');
      return [];
    }
  }

  /// Aggregate summary per class — one row per class, no row-limit issues
  static Future<List<Map<String, dynamic>>> getFeeDemandSummary(int insId) async {
    try {
      final response = await client.rpc('get_fee_demand_summary', params: {'p_ins_id': insId});
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('RPC get_fee_demand_summary failed: $e');
      return [];
    }
  }

  /// Individual demand rows for a single class — used for drilldown
  static Future<List<Map<String, dynamic>>> getFeeDemandsByClass(int insId, String className) async {
    try {
      // RETURNS json (json_agg) — single scalar bypasses PostgREST row limit
      final response = await client.rpc('get_fee_demands_by_class', params: {'p_ins_id': insId, 'p_class': className});
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('RPC get_fee_demands_by_class failed: $e');
      return [];
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

  /// Get payments for an institution within a date range via RPC function
  static Future<List<Map<String, dynamic>>> getPaymentsByDateRange(
    int insId, {
    required DateTime fromDate,
    required DateTime toDate,
  }) async {
    try {
      final from = fromDate.toIso8601String().split('T').first;
      final to = toDate.toIso8601String().split('T').first;

      final response = await client.rpc('get_payments_by_date_range', params: {
        'p_ins_id': insId,
        'p_from_date': from,
        'p_to_date': to,
      });

      // Normalise: wrap flat student fields into nested 'students' map
      // so existing UI code (p['students']['stuname'] etc.) keeps working
      final payments = List<Map<String, dynamic>>.from(response as List);
      for (final p in payments) {
        if (p['stuname'] != null && !p.containsKey('students')) {
          p['students'] = {
            'stuname': p['stuname'],
            'stuadmno': p['stuadmno'],
            'stuclass': p['stuclass'],
          };
        }
      }
      return payments;
    } catch (e) {
      debugPrint('RPC get_payments_by_date_range failed, using fallback: $e');
    }

    // Fallback if RPC not yet created
    try {
      final from = fromDate.toIso8601String().split('T').first;
      final to = '${toDate.toIso8601String().split('T').first}T23:59:59';
      final response = await client
          .from('payment')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .eq('paystatus', 'C')
          .gte('paydate', from)
          .lte('paydate', to)
          .order('paydate', ascending: false);
      final payments = List<Map<String, dynamic>>.from(response as List);

      // Collect unique stu_ids and fetch student info
      final stuIds = payments
          .map((p) => p['stu_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      if (stuIds.isNotEmpty) {
        final students = await client
            .from('students')
            .select('stu_id, stuname, stuadmno, stuclass')
            .inFilter('stu_id', stuIds);
        final stuMap = <int, Map<String, dynamic>>{};
        for (final s in (students as List)) {
          stuMap[s['stu_id'] as int] = s;
        }
        for (final p in payments) {
          final stuId = p['stu_id'];
          if (stuId != null && stuMap.containsKey(stuId)) {
            p['students'] = stuMap[stuId];
          }
        }
      }

      return payments;
    } catch (e) {
      debugPrint('Error fetching payments by date range: $e');
      return [];
    }
  }

  /// Get fee details for a payment, with fee group name lookup
  static Future<List<Map<String, dynamic>>> getFeeDetailsByPayId(int payId, {int? insId}) async {
    try {
      final response = await client
          .from('feedemand')
          .select('demfeeterm, demfeetype, fee_id, feeamount, conamount, paidamount, balancedue, paidstatus')
          .eq('pay_id', payId)
          .eq('activestatus', 1);
      final details = List<Map<String, dynamic>>.from(response as List);

      // Fetch fee group names via fee_id → feetype → feegroup
      if (details.isNotEmpty) {
        try {
          final feeIds = details
              .map((d) => d['fee_id'])
              .where((id) => id != null)
              .toSet()
              .toList();
          if (feeIds.isNotEmpty) {
            final feeTypes = await client
                .from('feetype')
                .select('fee_id, feedesc, fg_id')
                .inFilter('fee_id', feeIds)
                .eq('activestatus', 1);
            final feeIdToFgId = <int, int>{};
            final fgIds = <int>{};
            for (final ft in (feeTypes as List)) {
              feeIdToFgId[ft['fee_id'] as int] = ft['fg_id'] as int;
              fgIds.add(ft['fg_id'] as int);
            }
            final feeGroups = await client
                .from('feegroup')
                .select('fg_id, fgdesc')
                .inFilter('fg_id', fgIds.toList());
            final fgMap = <int, String>{};
            for (final fg in (feeGroups as List)) {
              fgMap[fg['fg_id'] as int] = fg['fgdesc']?.toString() ?? '';
            }
            for (final d in details) {
              final feeId = d['fee_id'] as int?;
              if (feeId != null && feeIdToFgId.containsKey(feeId)) {
                d['feegroupname'] = fgMap[feeIdToFgId[feeId]] ?? '';
              }
            }
          }
        } catch (e) {
          debugPrint('Error fetching fee group names: $e');
        }
      }

      return details;
    } catch (e) {
      debugPrint('Error fetching fee details for pay_id $payId: $e');
      return [];
    }
  }

  /// Get fee group names mapped by fee_id
  static Future<Map<int, String>> getFeeGroupMap(int insId) async {
    try {
      final feeTypes = await client
          .from('feetype')
          .select('fee_id, fg_id')
          .eq('activestatus', 1);
      final feeIdToFgId = <int, int>{};
      final fgIds = <int>{};
      for (final ft in (feeTypes as List)) {
        feeIdToFgId[ft['fee_id'] as int] = ft['fg_id'] as int;
        fgIds.add(ft['fg_id'] as int);
      }
      if (fgIds.isEmpty) return {};
      final feeGroups = await client
          .from('feegroup')
          .select('fg_id, fgdesc')
          .inFilter('fg_id', fgIds.toList());
      final fgMap = <int, String>{};
      for (final fg in (feeGroups as List)) {
        fgMap[fg['fg_id'] as int] = fg['fgdesc']?.toString() ?? '';
      }
      final result = <int, String>{};
      for (final entry in feeIdToFgId.entries) {
        result[entry.key] = fgMap[entry.value] ?? '';
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching fee group map: $e');
      return {};
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

  static Future<List<Map<String, dynamic>>> getPaidTransactions(int insId) async {
    try {
      final response = await client
          .from('payment')
          .select('*')
          .eq('ins_id', insId)
          .eq('paystatus', 'C')
          .order('paydate', ascending: false);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching paid transactions: $e');
      return [];
    }
  }

  // ==================== ROLES ====================

  /// Get active roles for an institution from custuserroles table
  static Future<List<Map<String, dynamic>>> getRoles(int insId) async {
    try {
      final response = await client
          .from('custuserroles')
          .select('ur_id, urname')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('ur_id', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error fetching roles: $e');
      return [];
    }
  }

  // ==================== DESIGNATION ====================

  static Future<List<Map<String, dynamic>>> getDesignations(int insId) async {
    try {
      final response = await client
          .from('staffdesignation')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('des_id', ascending: true);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching designations: $e');
      return [];
    }
  }

  static Future<bool> createDesignation(Map<String, dynamic> data) async {
    try {
      await client.from('staffdesignation').insert(data);
      return true;
    } catch (e) {
      debugPrint('Error creating designation: $e');
      return false;
    }
  }

  static Future<bool> updateDesignation(int desId, Map<String, dynamic> data) async {
    try {
      await client.from('staffdesignation').update(data).eq('des_id', desId);
      return true;
    } catch (e) {
      debugPrint('Error updating designation: $e');
      return false;
    }
  }

  static Future<bool> deleteDesignation(int desId) async {
    try {
      await client.from('staffdesignation').update({'activestatus': 0}).eq('des_id', desId);
      return true;
    } catch (e) {
      debugPrint('Error deleting designation: $e');
      return false;
    }
  }

  // ==================== USER ROLES ====================

  static Future<List<Map<String, dynamic>>> getUserRoles(int insId) async {
    try {
      final response = await client
          .from('custuserroles')
          .select('*')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('ur_id', ascending: true);
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Error fetching user roles: $e');
      return [];
    }
  }

  static Future<bool> createUserRole(Map<String, dynamic> data) async {
    try {
      await client.from('custuserroles').insert(data);
      return true;
    } catch (e) {
      debugPrint('Error creating user role: $e');
      return false;
    }
  }

  static Future<bool> updateUserRole(int urId, Map<String, dynamic> data) async {
    try {
      await client.from('custuserroles').update(data).eq('ur_id', urId);
      return true;
    } catch (e) {
      debugPrint('Error updating user role: $e');
      return false;
    }
  }

  static Future<bool> deleteUserRole(int urId) async {
    try {
      await client.from('custuserroles').update({'activestatus': 0}).eq('ur_id', urId);
      return true;
    } catch (e) {
      debugPrint('Error deleting user role: $e');
      return false;
    }
  }
}
