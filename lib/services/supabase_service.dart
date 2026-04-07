import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/student_model.dart';
import '../models/institution_user_model.dart';
import '../models/payment_model.dart';
import '../models/fee_model.dart';

/// Central Supabase service for all database queries
class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  /// Current institution schema name (e.g. 'kcet20262027')
  static String? _currentSchema;
  static String? get currentSchema => _currentSchema;

  /// Set the schema after login
  static void setSchema(String? schema) {
    _currentSchema = schema;
    debugPrint('SupabaseService schema set to: $schema');
  }

  /// Query from institution-specific schema table
  /// Falls back to public if no schema is set
  static SupabaseQueryBuilder fromSchema(String table) {
    if (_currentSchema != null && _currentSchema!.isNotEmpty) {
      return client.schema(_currentSchema!).from(table);
    }
    return client.from(table);
  }

  // ==================== LICENSE ====================

  /// Verify a license key against the institutionyear table
  static Future<Map<String, dynamic>> verifyLicenseKey(String licenseKey) async {
    try {
      final result = await client.rpc('verify_license_key', params: {
        'p_license_key': licenseKey.trim(),
      });
      debugPrint('License verification result: $result');
      return Map<String, dynamic>.from(result as Map);
    } catch (e) {
      debugPrint('License verification error: $e');
      return {'valid': false, 'message': 'Connection error. Please try again.'};
    }
  }

  // ==================== AUTH ====================

  /// Login institution user by email (or username for super admin), returns user if found
  static Future<InstitutionUserModel?> loginUser({
    required String email,
    required String password,
    int? insId,
    bool isSuperAdmin = false,
  }) async {
    try {
      List<dynamic> result;
      try {
        result = await client.rpc('verify_user_login', params: {
          'p_email': email.trim(),
          'p_plain_password': password,
          'p_is_super_admin': isSuperAdmin,
        });
      } catch (e) {
        // Fallback: old RPC signature without p_is_super_admin
        debugPrint('LOGIN: New RPC failed ($e), trying old signature');
        result = await client.rpc('verify_user_login', params: {
          'p_email': email.trim(),
          'p_plain_password': password,
        });
      }

      debugPrint('Login RPC result: $result');

      if (result.isEmpty) return null;

      final row = result.first as Map<String, dynamic>;
      if (row['is_valid'] != true) return null;

      final useId = row['use_id'];
      final isSuperAdminUser = isSuperAdmin || row['urname']?.toString() == 'Super Admin';

      // Super admin lives in public table, institution users in schema table
      Map<String, dynamic>? response;
      if (isSuperAdminUser) {
        var query = client
            .from('institutionusers')
            .select()
            .eq('use_id', useId)
            .eq('activestatus', 1);
        response = await query.maybeSingle();
      } else {
        // Resolve schema from insId before querying
        if (insId != null) {
          final insRow = await client
              .from('institution')
              .select('inshortname')
              .eq('ins_id', insId)
              .maybeSingle();
          debugPrint('LOGIN: insRow=$insRow for insId=$insId');
          if (insRow != null && insRow['inshortname'] != null) {
            final yearRows = await client
                .from('institutionyear')
                .select('yrlabel')
                .eq('ins_id', insId)
                .eq('activestatus', 1)
                .limit(1);
            debugPrint('LOGIN: yearRows=$yearRows');
            if ((yearRows as List).isNotEmpty) {
              final shortName = (insRow['inshortname'] as String).toLowerCase();
              final yearLabel = (yearRows.first['yrlabel'] as String).replaceAll('-', '');
              final schema = '$shortName$yearLabel';
              debugPrint('LOGIN: Setting schema to $schema');
              setSchema(schema);
            }
          }
        }
        debugPrint('LOGIN: Querying schema=$_currentSchema for use_id=$useId');
        try {
          var query = fromSchema('institutionusers')
              .select()
              .eq('use_id', useId)
              .eq('activestatus', 1);
          if (insId != null) {
            query = query.eq('ins_id', insId);
          }
          response = await query.maybeSingle();
          debugPrint('LOGIN: Schema user response=$response');
        } catch (e) {
          debugPrint('LOGIN: Schema query error: $e');
        }

        // Fallback: try public table if schema lookup returned nothing or failed
        if (response == null) {
          debugPrint('LOGIN: Trying public table fallback');
          try {
            var fallbackQuery = client
                .from('institutionusers')
                .select()
                .eq('use_id', useId)
                .eq('activestatus', 1);
            if (insId != null) {
              fallbackQuery = fallbackQuery.eq('ins_id', insId);
            }
            response = await fallbackQuery.maybeSingle();
            debugPrint('LOGIN: Public fallback response=$response');
          } catch (e) {
            debugPrint('LOGIN: Public fallback error: $e');
          }
        }

        // Last resort: build user from RPC result directly
        if (response == null) {
          debugPrint('LOGIN: All lookups failed, building from RPC result');
          response = {
            'use_id': row['use_id'],
            'ins_id': insId,
            'inscode': '',
            'usename': row['usename'],
            'usemail': row['usemail'],
            'usephone': '',
            'usestadate': DateTime.now().toIso8601String().split('T').first,
            'usedob': '2000-01-01',
            'ur_id': 0,
            'urname': row['urname'],
            'des_id': 0,
            'desname': row['desname'],
            'userepto': 0,
            'activestatus': 1,
          };
        }
      }

      if (response == null) return null;
      return InstitutionUserModel.fromJson(response);
    } catch (e) {
      debugPrint('Login error: $e');
      return null;
    }
  }



  // ==================== SUBSCRIPTION ====================

  /// Check if institution has an active subscription year with valid license key
  /// Returns (isActive, yearLabel, endDate) based on institutionyear table
  static Future<({bool isActive, String? yearLabel, DateTime? endDate})> checkSubscription(int insId) async {
    try {
      final now = DateTime.now().toIso8601String().split('T').first;
      final result = await client
          .from('institutionyear')
          .select('yrlabel, iyrstadate, iyrenddate, iyearsubstatus, iyearlicencekey')
          .eq('ins_id', insId)
          .lte('iyrstadate', now)
          .gte('iyrenddate', now)
          .eq('iyearsubstatus', 1)
          .not('iyearlicencekey', 'is', null)
          .maybeSingle();

      if (result == null) {
        return (isActive: false, yearLabel: null, endDate: null);
      }

      // Verify the license key is not empty
      final licenseKey = result['iyearlicencekey'] as String?;
      if (licenseKey == null || licenseKey.trim().isEmpty) {
        return (isActive: false, yearLabel: null, endDate: null);
      }

      return (
        isActive: true,
        yearLabel: result['yrlabel'] as String?,
        endDate: result['iyrenddate'] != null
            ? DateTime.parse(result['iyrenddate'].toString())
            : null,
      );
    } catch (e) {
      debugPrint('Subscription check error: $e');
      return (isActive: false, yearLabel: null, endDate: null);
    }
  }

  // ==================== MASTER DATA CHECK ====================

  /// Check if essential master data exists for an institution
  static Future<({bool hasFeeGroups, bool hasFeeTypes, bool hasConcessions, bool hasClassFeeDemand})> checkMasterData(int insId) async {
    try {
      final results = await Future.wait([
        fromSchema('feegroup').select('fg_id').eq('ins_id', insId).eq('activestatus', 1).limit(1),
        fromSchema('feetype').select('fee_id').eq('ins_id', insId).eq('activestatus', 1).limit(1),
        fromSchema('concessioncategory').select('con_id').eq('ins_id', insId).eq('activestatus', 1).limit(1),
        fromSchema('classfeedemand').select('cf_id').limit(1),
      ]);
      return (
        hasFeeGroups: (results[0] as List).isNotEmpty,
        hasFeeTypes: (results[1] as List).isNotEmpty,
        hasConcessions: (results[2] as List).isNotEmpty,
        hasClassFeeDemand: (results[3] as List).isNotEmpty,
      );
    } catch (e) {
      debugPrint('Master data check error: $e');
      return (hasFeeGroups: false, hasFeeTypes: false, hasConcessions: false, hasClassFeeDemand: false);
    }
  }

  // ==================== INSTITUTION ====================

  /// Get all institution names for the login dropdown
  static Future<List<Map<String, dynamic>>> getInstitutionNames() async {
    try {
      final result = await client
          .from('institution')
          .select('ins_id, insname')
          .order('insname');
      return List<Map<String, dynamic>>.from(result);
    } catch (e) {
      debugPrint('Get institution names error: $e');
      return [];
    }
  }

  /// Get institution name, logo, and address from the institution table
  static Future<({String? name, String? logo, String? address, String? mobile, String? email})> getInstitutionInfo(int insId) async {
    try {
      final result = await client
          .from('institution')
          .select('insname, inslogo, insaddress1, insaddress2, insaddress3, inspincode, insmobno, insmail')
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
    } catch (e) {
      debugPrint('ERROR creating institution: $e');
      debugPrint('Data sent: $data');
      rethrow;
    }
  }

  // ==================== STUDENTS ====================

  /// Get total active student count for an institution
  static Future<int> getStudentCount(int insId) async {
    try {
      final count = await fromSchema('students')
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
        final batch = await fromSchema('students')
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

  /// Fetch student remarks (stucondesc) as a map keyed by stu_id
  static Future<Map<int, String>> getStudentRemarks(int insId) async {
    try {
      const batchSize = 1000;
      int offset = 0;
      final Map<int, String> result = {};
      while (true) {
        final batch = await fromSchema('students')
            .select('stu_id, stucondesc')
            .eq('ins_id', insId)
            .eq('activestatus', 1)
            .range(offset, offset + batchSize - 1);
        final list = batch as List;
        for (final s in list) {
          final desc = s['stucondesc']?.toString() ?? '';
          if (desc.isNotEmpty) {
            result[s['stu_id'] as int] = desc;
          }
        }
        if (list.length < batchSize) break;
        offset += batchSize;
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching student remarks: $e');
      return {};
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
      final response = await fromSchema('students')
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
      final response = await fromSchema('feetype')
          .select('feedesc')
          .eq('ins_id', insId)
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
        final batch = await fromSchema('students')
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
    final response = await fromSchema('students')
        .insert(data)
        .select('stu_id')
        .maybeSingle();
    if (response == null) throw Exception('Student insert returned no data (check RLS or required columns)');
    return response['stu_id'] as int;
  }

  /// Update an existing student record
  static Future<void> updateStudent(int stuId, Map<String, dynamic> data) async {
    await fromSchema('students').update(data).eq('stu_id', stuId);
  }

  /// Get academic years for an institution
  static Future<List<Map<String, dynamic>>> getYears(int insId) async {
    try {
      final response = await fromSchema('year')
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
      final response = await fromSchema('students')
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
      final response = await fromSchema('concessioncategory')
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
    required int insId,
    String? fatherMobile,
    String? motherMobile,
    String? payMobile,
  }) async {
    if (fatherMobile != null && fatherMobile.isNotEmpty) {
      final result = await fromSchema('parents')
          .select('par_id')
          .eq('ins_id', insId)
          .eq('fathermobile', fatherMobile)
          .eq('activestatus', 1)
          .maybeSingle();
      if (result != null) return result['par_id'] as int;
    }
    if (motherMobile != null && motherMobile.isNotEmpty) {
      final result = await fromSchema('parents')
          .select('par_id')
          .eq('ins_id', insId)
          .eq('mothermobile', motherMobile)
          .eq('activestatus', 1)
          .maybeSingle();
      if (result != null) return result['par_id'] as int;
    }
    if (payMobile != null && payMobile.isNotEmpty) {
      final result = await fromSchema('parents')
          .select('par_id')
          .eq('ins_id', insId)
          .eq('payinchargemob', payMobile)
          .eq('activestatus', 1)
          .maybeSingle();
      if (result != null) return result['par_id'] as int;
    }
    return null;
  }

  /// Insert parent record — returns the new par_id
  static Future<int> saveParent(Map<String, dynamic> data) async {
    final response = await fromSchema('parents')
        .insert(data)
        .select('par_id')
        .maybeSingle();
    if (response == null) throw Exception('Parent insert returned no data (check RLS or required columns)');
    return response['par_id'] as int;
  }

  /// Insert parentdetail record linking student ↔ parent
  static Future<void> saveParentDetail(Map<String, dynamic> data) async {
    await fromSchema('parentdetail').insert(data);
  }

  /// Fetch parent record for a given student (via parentdetail → parents)
  static Future<Map<String, dynamic>?> getStudentParent(int stuId, {String? stuadmno}) async {
    try {
      // Try by stu_id first
      var detail = await fromSchema('parentdetail')
          .select('par_id')
          .eq('stu_id', stuId)
          .maybeSingle();
      // Fallback: try by stuadmno if stu_id lookup returned nothing
      if (detail == null && stuadmno != null && stuadmno.isNotEmpty) {
        detail = await fromSchema('parentdetail')
            .select('par_id')
            .eq('stuadmno', stuadmno)
            .maybeSingle();
      }
      if (detail == null) return null;
      final parId = detail['par_id'] as int;
      final parent = await fromSchema('parents')
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
      final response = await fromSchema('institutionusers')
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
      final response = await fromSchema('institutionusers')
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
      await fromSchema('institutionusers').insert(data);
      return true;
    } catch (e) {
      debugPrint('Error creating institution user: $e');
      debugPrint('User data: $data');
      rethrow;
    }
  }

  /// Terminate (deactivate) an institution user
  static Future<bool> terminateInstitutionUser(int useId, {required String terminatedBy, required String terminatedReason}) async {
    try {
      debugPrint('Terminating user with use_id: $useId');
      final now = DateTime.now().toIso8601String();
      await fromSchema('institutionusers')
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

  /// Terminate (deactivate) a student
  static Future<bool> terminateStudent(int stuId, {required String terminatedBy, required String terminatedReason}) async {
    try {
      debugPrint('Terminating student with stu_id: $stuId');
      final now = DateTime.now().toIso8601String();
      await fromSchema('students')
          .update({
            'activestatus': 9,
            'terminatedby': terminatedBy,
            'terminateddate': now,
            'terminatedreason': terminatedReason,
          })
          .eq('stu_id', stuId);
      debugPrint('Terminate student success');
      return true;
    } catch (e, st) {
      debugPrint('Error terminating student: $e');
      debugPrint('Stack trace: $st');
      return false;
    }
  }

  // ==================== FEE GROUPS ====================

  /// Get all active fee groups for an institution
  static Future<List<Map<String, dynamic>>> getFeeGroups(int insId) async {
    try {
      final response = await fromSchema('feegroup')
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
    final response = await fromSchema('feegroup')
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
      final response = await fromSchema('feetype')
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
    final response = await fromSchema('feetype')
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
      final list = List<Map<String, dynamic>>.from(response as List);
      // If RPC doesn't include demfeeterm, enrich from fallback
      if (list.isNotEmpty && !list.first.containsKey('demfeeterm')) {
        debugPrint('RPC get_fee_demands missing demfeeterm, enriching with fallback');
        final termMap = await _getFeeDemandTermMap(insId);
        for (final row in list) {
          final feeId = row['fee_id'];
          if (feeId != null && termMap.containsKey(feeId)) {
            row['demfeeterm'] = termMap[feeId];
          }
        }
      }
      return list;
    } catch (e) {
      debugPrint('RPC get_fee_demands failed: $e');
      return _getFeeDemandsFallback(insId);
    }
  }

  /// Fetch only fee_id -> demfeeterm mapping for enrichment
  static Future<Map<int, String>> _getFeeDemandTermMap(int insId) async {
    try {
      const batchSize = 1000;
      int offset = 0;
      final Map<int, String> result = {};
      while (true) {
        final batch = await fromSchema('feedemand')
            .select('fee_id, demfeeterm')
            .eq('ins_id', insId)
            .range(offset, offset + batchSize - 1);
        final list = batch as List;
        for (final row in list) {
          final feeId = row['fee_id'] as int?;
          final term = row['demfeeterm']?.toString() ?? '';
          if (feeId != null && term.isNotEmpty) {
            result[feeId] = term;
          }
        }
        if (list.length < batchSize) break;
        offset += batchSize;
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching term map: $e');
      return {};
    }
  }

  static Future<List<Map<String, dynamic>>> _getFeeDemandsFallback(int insId) async {
    try {
      const batchSize = 1000;
      int offset = 0;
      final List<Map<String, dynamic>> allResults = [];
      while (true) {
        final batch = await fromSchema('feedemand')
            .select('fee_id, ins_id, stu_id, feeamount, conamount, paidamount, balancedue, paidstatus, stuclass, courname, stuadmno, demfeetype, demfeeterm, pay_id, activestatus')
            .eq('ins_id', insId)
            .range(offset, offset + batchSize - 1);
        final list = batch as List;
        allResults.addAll(list.cast<Map<String, dynamic>>());
        if (list.length < batchSize) break;
        offset += batchSize;
      }
      return allResults;
    } catch (e) {
      debugPrint('Fallback getFeeDemands failed: $e');
      return [];
    }
  }

  /// Get paid fee demands with payment date (for date-wise tab)
  /// Uses RPC to bypass row limits; falls back to direct query
  static Future<List<Map<String, dynamic>>> getPaidFeeDemands(int insId) async {
    // Skip RPC — it only fetches paidstatus='P' and misses partially paid ('U') rows.
    // Using paginated fallback which includes both 'P' and 'U' with paidamount > 0.

    // Fallback: fetch paid feedemand rows (paginated), then batch-fetch payment dates
    try {
      final demandList = <Map<String, dynamic>>[];
      const batchSize = 1000;
      int offset = 0;
      while (true) {
        final demands = await fromSchema('feedemand')
            .select('fee_id, ins_id, stu_id, feeamount, conamount, paidamount, balancedue, paidstatus, stuclass, courname, stuadmno, demfeetype, demfeeterm, pay_id')
            .eq('ins_id', insId)
            .inFilter('paidstatus', ['P', 'U'])
            .eq('activestatus', 1)
            .gt('paidamount', 0)
            .range(offset, offset + batchSize - 1);
        final rows = List<Map<String, dynamic>>.from(demands as List);
        demandList.addAll(rows);
        if (rows.length < batchSize) break;
        offset += batchSize;
      }
      if (demandList.isEmpty) return [];

      // Collect unique pay_ids and stu_ids
      final payIds = demandList
          .map((d) => d['pay_id'])
          .where((id) => id != null)
          .toSet()
          .toList();
      final stuIds = demandList
          .map((d) => d['stu_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      // Fetch payment dates and student names in parallel
      final Map<int, String> payDateMap = {};
      final Map<int, String> stuNameMap = {};

      final enrichFutures = <Future>[];

      // Payment date futures
      for (var i = 0; i < payIds.length; i += 500) {
        final chunk = payIds.sublist(i, (i + 500).clamp(0, payIds.length));
        enrichFutures.add(fromSchema('payment')
            .select('pay_id, paydate')
            .inFilter('pay_id', chunk)
            .then((payRows) {
          for (final row in (payRows as List)) {
            final id = row['pay_id'] as int?;
            final date = row['paydate']?.toString();
            if (id != null && date != null) payDateMap[id] = date;
          }
        }));
      }

      // Student name futures
      for (var i = 0; i < stuIds.length; i += 500) {
        final chunk = stuIds.sublist(i, (i + 500).clamp(0, stuIds.length));
        enrichFutures.add(fromSchema('students')
            .select('stu_id, stuname')
            .inFilter('stu_id', chunk)
            .then((stuRows) {
          for (final row in (stuRows as List)) {
            final id = row['stu_id'] as int?;
            final name = row['stuname']?.toString();
            if (id != null && name != null) stuNameMap[id] = name;
          }
        }));
      }

      await Future.wait(enrichFutures);

      // Enrich demand rows with paydate and stuname
      for (final d in demandList) {
        final payId = d['pay_id'] as int?;
        if (payId != null) d['paydate'] = payDateMap[payId];
        final stuId = d['stu_id'] as int?;
        if (stuId != null) d['stuname'] = stuNameMap[stuId] ?? '';
      }

      return demandList;
    } catch (e) {
      debugPrint('Error fetching paid fee demands: $e');
      return [];
    }
  }

  /// Fetch paynumber lookup map: pay_id → paynumber
  static Future<Map<int, String>> getPayNumberMap(List<int> payIds, {required int insId}) async {
    if (payIds.isEmpty) return {};
    try {
      final Map<int, String> result = {};
      // Batch in chunks of 500 to avoid query size limits
      for (var i = 0; i < payIds.length; i += 500) {
        final chunk = payIds.sublist(i, (i + 500).clamp(0, payIds.length));
        final response = await fromSchema('payment')
            .select('pay_id, paynumber')
            .eq('ins_id', insId)
            .inFilter('pay_id', chunk);
        for (final row in (response as List)) {
          final id = row['pay_id'] as int?;
          final num = row['paynumber']?.toString();
          if (id != null && num != null) result[id] = num;
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching pay numbers: $e');
      return {};
    }
  }

  /// Fetch total fee demand (sum of feeamount), total collection (sum of transtotalamount), and total pending (sum of balancedue)
  /// Uses RPC for server-side aggregation to avoid PostgREST row limits.
  static Future<Map<String, double>> getFeeTotals(int insId) async {
    try {
      final result = await client.rpc('get_fee_totals', params: {'p_ins_id': insId});
      return {
        'totalDemand': (result['total_demand'] as num?)?.toDouble() ?? 0,
        'totalPaid': (result['total_paid'] as num?)?.toDouble() ?? 0,
        'totalPending': (result['total_pending'] as num?)?.toDouble() ?? 0,
      };
    } catch (e) {
      debugPrint('RPC get_fee_totals failed, using fallback: $e');
    }

    // Fallback: paginate through all rows to avoid 1000-row cap
    try {
      double totalDemand = 0, totalPaid = 0, totalPending = 0;
      const batchSize = 1000;
      int offset = 0;
      while (true) {
        final demandRes = await fromSchema('feedemand')
            .select('feeamount, paidamount, balancedue')
            .eq('ins_id', insId)
            .eq('activestatus', 1)
            .range(offset, offset + batchSize - 1);
        final rows = demandRes as List;
        for (final row in rows) {
          totalDemand += (row['feeamount'] as num?)?.toDouble() ?? 0;
          totalPaid += (row['paidamount'] as num?)?.toDouble() ?? 0;
          totalPending += (row['balancedue'] as num?)?.toDouble() ?? 0;
        }
        if (rows.length < batchSize) break;
        offset += batchSize;
      }

      return {'totalDemand': totalDemand, 'totalPaid': totalPaid, 'totalPending': totalPending};
    } catch (e) {
      debugPrint('Error fetching fee totals: $e');
      return {'totalDemand': 0, 'totalPaid': 0, 'totalPending': 0};
    }
  }

  /// Fetch payment amounts (transtotalamount) for given pay_ids
  static Future<Map<int, double>> getPayAmountMap(List<int> payIds, {required int insId}) async {
    if (payIds.isEmpty) return {};
    try {
      final Map<int, double> result = {};
      for (var i = 0; i < payIds.length; i += 500) {
        final chunk = payIds.sublist(i, (i + 500).clamp(0, payIds.length));
        final response = await fromSchema('payment')
            .select('pay_id, transtotalamount')
            .eq('ins_id', insId)
            .inFilter('pay_id', chunk);
        for (final row in (response as List)) {
          final id = row['pay_id'] as int?;
          final amt = (row['transtotalamount'] as num?)?.toDouble();
          if (id != null && amt != null) result[id] = amt;
        }
      }
      return result;
    } catch (e) {
      debugPrint('Error fetching pay amounts: $e');
      return {};
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

  /// Fetch pending fee demands for the institution via DB function.
  /// Only returns rows for students with activestatus = 1.
  static Future<List<Map<String, dynamic>>> getFeeDemandsPending(int insId) async {
    try {
      final response = await client
          .rpc('get_fee_demands_pending', params: {'p_ins_id': insId});
      if (response == null) return [];
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('getFeeDemandsPending failed: $e');
      return [];
    }
  }

  /// Get fee collection summary for an institution
  /// Fee Collection = sum of transtotalamount from payment table where paystatus='C'
  /// Pending Fees = sum of balancedue from feedemand table where paidstatus='U'
  static Future<FeeSummary> getFeeSummary(int insId) async {
    try {
      // Use RPCs for server-side aggregation (avoids row-limit issues and slow pagination)
      final rpcFuture = client.rpc('get_fee_summary', params: {'p_ins_id': insId});
      final totalsFuture = getFeeTotals(insId);
      final results = await Future.wait<dynamic>([rpcFuture, totalsFuture]);

      final rpcResult = results[0];
      final feeTotals = results[1] as Map<String, double>;

      final totalPending =
          (rpcResult['total_pending'] as num?)?.toDouble() ?? 0;
      final pendingCount = (rpcResult['pending_count'] as num?)?.toInt() ?? 0;

      return FeeSummary(
        totalDue: feeTotals['totalDemand'] ?? 0,
        totalPaid: feeTotals['totalPaid'] ?? 0,
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
      if (response == null) return [];
      final payments = List<Map<String, dynamic>>.from(response as List);
      debugPrint('RPC get_payments_by_date_range returned ${payments.length} rows');
      for (final p in payments) {
        if (p['stuname'] != null && !p.containsKey('students')) {
          p['students'] = {
            'stuname': p['stuname'],
            'stuadmno': p['stuadmno'],
            'stuclass': p['stuclass'],
          };
        }
      }
      // If RPC returns exactly 1000 rows, it may be truncated — fall through to paginated fallback
      if (payments.length == 1000) {
        debugPrint('RPC may be truncated (exactly 1000 rows), using paginated fallback');
      } else {
        return payments;
      }
    } catch (e) {
      debugPrint('RPC get_payments_by_date_range failed, using fallback: $e');
    }

    // Fallback if RPC not yet created (paginated)
    try {
      final from = fromDate.toIso8601String().split('T').first;
      final to = '${toDate.toIso8601String().split('T').first}T23:59:59';
      final payments = <Map<String, dynamic>>[];
      const batchSize = 1000;
      int offset = 0;
      while (true) {
        final response = await fromSchema('payment')
            .select('*')
            .eq('ins_id', insId)
            .eq('activestatus', 1)
            .eq('paystatus', 'C')
            .gte('paydate', from)
            .lte('paydate', to)
            .order('paydate', ascending: false)
            .range(offset, offset + batchSize - 1);
        final rows = List<Map<String, dynamic>>.from(response as List);
        payments.addAll(rows);
        if (rows.length < batchSize) break;
        offset += batchSize;
      }

      // Collect unique stu_ids and fetch student info
      final stuIds = payments
          .map((p) => p['stu_id'])
          .where((id) => id != null)
          .toSet()
          .toList();

      if (stuIds.isNotEmpty) {
        final students = await fromSchema('students')
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
      final response = await fromSchema('feedemand')
          .select('demfeeterm, demfeetype, fee_id, feeamount, conamount, paidamount, balancedue, paidstatus, duedate')
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
            final feeTypes = await fromSchema('feetype')
                .select('fee_id, feedesc, fg_id')
                .inFilter('fee_id', feeIds)
                .eq('activestatus', 1);
            final feeIdToFgId = <int, int>{};
            final fgIds = <int>{};
            for (final ft in (feeTypes as List)) {
              feeIdToFgId[ft['fee_id'] as int] = ft['fg_id'] as int;
              fgIds.add(ft['fg_id'] as int);
            }
            final feeGroups = await fromSchema('feegroup')
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
  /// Returns two maps:
  /// - 'byId': fee_id -> fee group name
  /// - 'byName': fee type name (feedesc) -> fee group name
  static Future<Map<String, Map>> getFeeGroupMaps(int insId) async {
    try {
      final feeTypes = await fromSchema('feetype')
          .select('fee_id, feedesc, fg_id')
          .eq('ins_id', insId)
          .eq('activestatus', 1);
      final feeIdToFgId = <int, int>{};
      final feeDescToFgId = <String, int>{};
      final fgIds = <int>{};
      for (final ft in (feeTypes as List)) {
        final feeId = ft['fee_id'] as int?;
        final fgId = ft['fg_id'] as int?;
        final feedesc = ft['feedesc']?.toString() ?? '';
        if (fgId != null && fgId > 0) {
          if (feeId != null) {
            feeIdToFgId[feeId] = fgId;
          }
          if (feedesc.isNotEmpty) {
            feeDescToFgId[feedesc] = fgId;
          }
          fgIds.add(fgId);
        }
      }
      if (fgIds.isEmpty) return {'byId': {}, 'byName': {}};
      final feeGroups = await fromSchema('feegroup')
          .select('fg_id, fgdesc')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .inFilter('fg_id', fgIds.toList());
      final fgMap = <int, String>{};
      for (final fg in (feeGroups as List)) {
        fgMap[fg['fg_id'] as int] = fg['fgdesc']?.toString() ?? '';
      }
      final byId = <int, String>{};
      for (final entry in feeIdToFgId.entries) {
        final name = fgMap[entry.value] ?? '';
        if (name.isNotEmpty) {
          byId[entry.key] = name;
        }
      }
      final byName = <String, String>{};
      for (final entry in feeDescToFgId.entries) {
        final name = fgMap[entry.value] ?? '';
        if (name.isNotEmpty) {
          byName[entry.key] = name;
        }
      }
      return {'byId': byId, 'byName': byName};
    } catch (e) {
      debugPrint('Error fetching fee group map: $e');
      return {'byId': {}, 'byName': {}};
    }
  }

  /// Get recent payments for an institution
  static Future<List<PaymentModel>> getRecentPayments(int insId,
      {int limit = 10}) async {
    try {
      final response = await fromSchema('payment')
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

  /// Get all transactions for an institution via RPC, with direct table fallback
  static Future<List<Map<String, dynamic>>> getAllTransactions(int insId) async {
    try {
      final response = await client.rpc('fn_get_transactions', params: {'p_ins_id': insId});
      final data = List<Map<String, dynamic>>.from(response as List);
      if (data.isNotEmpty) return data;
    } catch (e) {
      debugPrint('RPC fn_get_transactions failed, falling back to direct query: $e');
    }
    // Fallback: query payment table directly (paginated)
    try {
      final allRows = <Map<String, dynamic>>[];
      const batchSize = 1000;
      int offset = 0;
      while (true) {
        final response = await fromSchema('payment')
            .select()
            .eq('ins_id', insId)
            .order('createdat', ascending: false)
            .range(offset, offset + batchSize - 1);
        final rows = List<Map<String, dynamic>>.from(response as List);
        allRows.addAll(rows);
        if (rows.length < batchSize) break;
        offset += batchSize;
      }
      debugPrint('Payment table fallback returned ${allRows.length} records');
      return allRows;
    } catch (e) {
      debugPrint('Error fetching transactions from payment table: $e');
      return [];
    }
  }

  /// Get failed transactions (filtered from RPC)
  static Future<List<Map<String, dynamic>>> getFailedTransactions(int insId) async {
    final all = await getAllTransactions(insId);
    return all.where((t) => t['paystatus'] == 'F').toList();
  }

  /// Get paid transactions (filtered from RPC)
  static Future<List<Map<String, dynamic>>> getPaidTransactions(int insId) async {
    final all = await getAllTransactions(insId);
    return all.where((t) => t['paystatus'] == 'C').toList();
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
      debugPrint('Designation data: $data');
      rethrow;
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
      debugPrint('Role data: $data');
      rethrow;
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
