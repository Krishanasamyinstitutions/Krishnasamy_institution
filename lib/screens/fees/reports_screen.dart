import 'dart:io';
import 'package:flutter/material.dart';
import 'package:excel/excel.dart' as xl;
import 'package:file_picker/file_picker.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

const _termOrder = [
  'I SEMESTER', 'I TERM', 'II SEMESTER', 'II TERM', 'III SEMESTER', 'III TERM',
  'IV SEMESTER', 'V SEMESTER', 'VI SEMESTER',
  'JUNE', 'JULY', 'AUGUST', 'SEPTEMBER', 'OCTOBER',
  'NOVEMBER', 'DECEMBER', 'JANUARY', 'FEBRUARY',
  'MARCH', 'APRIL', 'MAY',
];

int _termIndex(String t) {
  final idx = _termOrder.indexWhere((x) => x.toLowerCase() == t.toLowerCase());
  return idx >= 0 ? idx : _termOrder.length;
}

String _formatDate(DateTime d) => '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
String _formatDateCompact(DateTime d) => '${d.day.toString().padLeft(2, '0')}${d.month.toString().padLeft(2, '0')}${d.year}';

String _formatNumber(double v) {
  if (v == 0) return '0';
  final s = v.toStringAsFixed(0);
  final result = StringBuffer();
  int count = 0;
  for (int i = s.length - 1; i >= 0; i--) {
    if (count == 3 || (count > 3 && (count - 3) % 2 == 0)) result.write(',');
    result.write(s[i]);
    count++;
  }
  return result.toString().split('').reversed.join();
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Data
  List<Map<String, dynamic>> _allDemands = [];
  bool _loading = false;
  String? _error;

  // Filters
  List<String> _courses = [];
  List<String> _classes = [];
  List<String> _feeTypes = [];
  String? _selectedCourse;
  String? _selectedClass;
  String? _selectedFeeType;

  // Institution info
  String _insName = '';
  String _insAddress = '';
  String _insPhone = '';
  String _insEmail = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Fetch fee report data via RPC (single call, no pagination needed)
  Future<List<Map<String, dynamic>>> _fetchFeeDemandsDirectly(int insId) async {
    try {
      final result = await SupabaseService.client.rpc('get_fee_report_data', params: {'p_ins_id': insId});
      if (result != null) return List<Map<String, dynamic>>.from(result as List);
    } catch (e) {
      debugPrint('RPC get_fee_report_data failed, using fallback: $e');
    }
    // Fallback: direct query
    const batchSize = 1000;
    int offset = 0;
    final allResults = <Map<String, dynamic>>[];
    while (true) {
      final batch = await SupabaseService.fromSchema('feedemand')
          .select('fee_id, stu_id, feeamount, conamount, paidamount, fineamount, balancedue, reconbalancedue, paidstatus, stuclass, courname, stuadmno, demfeetype, demfeeterm, activestatus')
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .range(offset, offset + batchSize - 1);
      final list = batch as List;
      allResults.addAll(list.cast<Map<String, dynamic>>());
      if (list.length < batchSize) break;
      offset += batchSize;
    }
    // Enrich with student names
    final stuIds = allResults.map((d) => d['stu_id']).where((id) => id != null).toSet().toList();
    final Map<int, String> stuNameMap = {};
    for (int i = 0; i < stuIds.length; i += 200) {
      final chunk = stuIds.sublist(i, (i + 200).clamp(0, stuIds.length));
      final students = await SupabaseService.fromSchema('students').select('stu_id, stuname').inFilter('stu_id', chunk);
      for (final s in students) { stuNameMap[s['stu_id'] as int] = s['stuname']?.toString() ?? ''; }
    }
    for (final d in allResults) { d['stuname'] = stuNameMap[d['stu_id'] as int?] ?? d['stuadmno']?.toString() ?? ''; }
    return allResults;
  }

  Future<void> _loadData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([
        _fetchFeeDemandsDirectly(insId),
        SupabaseService.getInstitutionInfo(insId),
      ]);
      final demands = results[0] as List<Map<String, dynamic>>;
      final insInfo = results[1] as ({String? name, String? logo, String? address, String? mobile, String? email});

      // Extract filters
      final courseSet = <String>{};
      final classSet = <String>{};
      final feeTypeSet = <String>{};
      for (final d in demands) {
        final c = d['courname']?.toString() ?? '';
        final cl = d['stuclass']?.toString() ?? '';
        final ft = d['demfeetype']?.toString() ?? '';
        if (c.isNotEmpty) courseSet.add(c);
        if (cl.isNotEmpty) classSet.add(cl);
        if (ft.isNotEmpty) feeTypeSet.add(ft);
      }

      if (mounted) setState(() {
        _allDemands = demands;
        _courses = courseSet.toList()..sort();
        _classes = classSet.toList()..sort();
        _feeTypes = feeTypeSet.toList()..sort();
        _insName = insInfo.name ?? '';
        _insAddress = insInfo.address?.replaceAll('\n', ', ') ?? '';
        _insPhone = insInfo.mobile ?? '';
        _insEmail = insInfo.email ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; });
    }
  }

  List<Map<String, dynamic>> get _filteredDemands {
    return _allDemands.where((d) {
      if (_selectedCourse != null && d['courname']?.toString() != _selectedCourse) return false;
      if (_selectedClass != null && d['stuclass']?.toString() != _selectedClass) return false;
      if (_selectedFeeType != null && d['demfeetype']?.toString() != _selectedFeeType) return false;
      return true;
    }).toList();
  }

  // Get dynamic term columns from actual data
  List<String> _getTermColumns(List<Map<String, dynamic>> demands) {
    final terms = <String>{};
    for (final d in demands) {
      final t = d['demfeeterm']?.toString() ?? '';
      if (t.isNotEmpty) terms.add(t);
    }
    final sorted = terms.toList()..sort((a, b) => _termIndex(a).compareTo(_termIndex(b)));
    return sorted;
  }

  // Build student-wise pivot data with total and remarks
  // showPending=true uses reconbalancedue (reconciled pending), showPending=false uses feeamount (demanded)
  List<Map<String, dynamic>> _buildPivotData(List<Map<String, dynamic>> demands, List<String> terms, {required bool showPending}) {
    final Map<String, Map<String, dynamic>> studentMap = {};
    final Map<String, Set<String>> studentRemarks = {};
    for (final d in demands) {
      final admNo = d['stuadmno']?.toString() ?? '';
      if (admNo.isEmpty) continue;
      final term = d['demfeeterm']?.toString() ?? '';
      final feeType = d['demfeetype']?.toString() ?? '';
      final amount = showPending
          ? (d['reconbalancedue'] as num?)?.toDouble() ?? (d['balancedue'] as num?)?.toDouble() ?? 0
          : (d['feeamount'] as num?)?.toDouble() ?? 0;

      studentMap.putIfAbsent(admNo, () => {
        'stuadmno': admNo,
        'stuname': d['stuname']?.toString() ?? d['stuadmno']?.toString() ?? '',
        'courname': d['courname']?.toString() ?? '',
        'stuclass': d['stuclass']?.toString() ?? '',
      });

      if (term.isNotEmpty) {
        studentMap[admNo]![term] = (studentMap[admNo]![term] as double? ?? 0) + amount;
      }

      // Accumulate fine from the fineamount column
      final fine = (d['fineamount'] as num?)?.toDouble() ?? 0;
      studentMap[admNo]!['_fine'] = ((studentMap[admNo]!['_fine'] as double?) ?? 0) + fine;

      // Collect fee type remarks for pending amounts
      if (amount > 0 && feeType.isNotEmpty) {
        studentRemarks.putIfAbsent(admNo, () => <String>{}).add(feeType);
      }
    }

    // Calculate total and add remarks
    for (final entry in studentMap.entries) {
      double total = 0;
      for (final t in terms) {
        total += (entry.value[t] as double?) ?? 0;
      }
      entry.value['_total'] = total;
      entry.value['_remarks'] = (studentRemarks[entry.key] ?? {}).join(', ');
    }

    final list = studentMap.values.toList();
    list.sort((a, b) => (a['stuadmno'] as String).compareTo(b['stuadmno'] as String));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Tabs (pill style)
        ListenableBuilder(
          listenable: _tabController,
          builder: (context, _) {
            final selected = _tabController.index;
            final tabLabels = ['Collection Statement', 'Pending - Course wise', 'Pending - Year wise'];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                border: Border(bottom: BorderSide(color: AppColors.border)),
              ),
              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
              child: Row(
                children: [
                  ...List.generate(tabLabels.length, (i) => Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: GestureDetector(
                      onTap: () => _tabController.animateTo(i),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
                        decoration: BoxDecoration(
                          color: selected == i ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(20.r),
                          border: Border.all(color: selected == i ? AppColors.accent : AppColors.border),
                        ),
                        child: Text(tabLabels[i], style: TextStyle(
                          fontSize: 13.sp, fontWeight: FontWeight.w600,
                          color: selected == i ? Colors.white : AppColors.textSecondary,
                        )),
                      ),
                    ),
                  )),
                  const Spacer(),
                  if (_loading) SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent)),
                ],
              ),
            );
          },
        ),
        // Filters
        _buildFilters(),
        // Content
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
                  ? Center(child: Text('Error: $_error'))
                  : TabBarView(
                      controller: _tabController,
                      children: [
                        _buildCollectionStatement(),
                        _buildPendingCourseWise(),
                        _buildPendingYearWise(),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildFilters() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        children: [
          // Course filter
          SizedBox(
            width: 160.w,
            child: DropdownButtonFormField<String?>(
              value: _selectedCourse,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Course',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('All Courses', style: TextStyle(fontSize: 13.sp))),
                ..._courses.map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontSize: 13.sp)))),
              ],
              onChanged: (v) => setState(() { _selectedCourse = v; _selectedClass = null; }),
            ),
          ),
          SizedBox(width: 12.w),
          // Class filter
          SizedBox(
            width: 160.w,
            child: DropdownButtonFormField<String?>(
              key: ValueKey(_selectedCourse),
              value: _selectedClass,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Class',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('All Classes', style: TextStyle(fontSize: 13.sp))),
                ...(_selectedCourse != null
                    ? _classes.where((c) => _allDemands.any((d) => d['courname']?.toString() == _selectedCourse && d['stuclass']?.toString() == c))
                    : _classes
                ).map((c) => DropdownMenuItem(value: c, child: Text(c, style: TextStyle(fontSize: 13.sp)))),
              ],
              onChanged: (v) => setState(() => _selectedClass = v),
            ),
          ),
          SizedBox(width: 12.w),
          // Fee Type filter
          SizedBox(
            width: 160.w,
            child: DropdownButtonFormField<String?>(
              value: _selectedFeeType,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: 'Fee Type',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 8.h),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r)),
              ),
              style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
              items: [
                DropdownMenuItem<String?>(value: null, child: Text('All Fee Types', style: TextStyle(fontSize: 13.sp))),
                ..._feeTypes.map((f) => DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontSize: 13.sp)))),
              ],
              onChanged: (v) => setState(() => _selectedFeeType = v),
            ),
          ),
          const Spacer(),
          // Reset
          TextButton.icon(
            onPressed: () => setState(() { _selectedCourse = null; _selectedClass = null; _selectedFeeType = null; }),
            icon: Icon(Icons.refresh_rounded, size: 16.sp),
            label: Text('Reset', style: TextStyle(fontSize: 13.sp)),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 1: COLLECTION STATEMENT (fee amounts by term)
  // ═══════════════════════════════════════════════
  Widget _buildCollectionStatement() {
    final demands = _filteredDemands;
    final terms = _getTermColumns(demands);
    final pivotData = _buildPivotData(demands, terms, showPending: true);
    if (pivotData.isEmpty) return _emptyState('No fee data found');

    // Calculate totals per term
    final Map<String, double> termTotals = {};
    for (final row in pivotData) {
      for (final t in terms) {
        termTotals[t] = (termTotals[t] ?? 0) + (row[t] as double? ?? 0);
      }
    }

    return _buildReportTable(
      title: 'PENDING FEE REPORT AS ON ${_formatDate(DateTime.now())}',
      subtitle: 'FEE TYPE : ${_selectedFeeType ?? 'ALL FEE TYPE'}',
      terms: terms,
      pivotData: pivotData,
      termTotals: termTotals,
      showPending: true,
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 2: PENDING - COURSE WISE
  // ═══════════════════════════════════════════════
  Widget _buildPendingCourseWise() {
    final demands = _filteredDemands.where((d) {
      final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
      return balance > 0;
    }).toList();
    final terms = _getTermColumns(demands);

    // Group by course
    final Map<String, List<Map<String, dynamic>>> courseGroups = {};
    for (final d in demands) {
      final course = d['courname']?.toString() ?? 'Unknown';
      courseGroups.putIfAbsent(course, () => []).add(d);
    }

    if (courseGroups.isEmpty) return _emptyState('No pending fees found');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Export button
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                Text('PENDING FEE REPORT - COURSE WISE',
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _exportPendingReport(demands, terms, 'Course_Wise'),
                  icon: Icon(Icons.download_rounded, size: 16.sp),
                  label: Text('Export Excel', style: TextStyle(fontSize: 13.sp)),
                ),
              ],
            ),
          ),
          ...courseGroups.entries.map((entry) {
            final courseName = entry.key;
            final courseDemands = entry.value;
            final pivotData = _buildPivotData(courseDemands, terms, showPending: true);
            final Map<String, double> termTotals = {};
            for (final row in pivotData) {
              for (final t in terms) {
                termTotals[t] = (termTotals[t] ?? 0) + (row[t] as double? ?? 0);
              }
            }
            final grandTotal = termTotals.values.fold<double>(0, (s, v) => s + v);

            return Container(
              margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
                    ),
                    child: Row(
                      children: [
                        Text(courseName, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.accent)),
                        const Spacer(),
                        Text('${pivotData.length} students', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                        SizedBox(width: 16.w),
                        Text('Total Pending: ${_formatNumber(grandTotal)}',
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.red)),
                      ],
                    ),
                  ),
                  _buildDataTable(terms, pivotData, termTotals),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // TAB 3: PENDING - YEAR WISE
  // ═══════════════════════════════════════════════
  Widget _buildPendingYearWise() {
    final demands = _filteredDemands.where((d) {
      final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
      return balance > 0;
    }).toList();
    final terms = _getTermColumns(demands);

    // Group by class (year)
    final Map<String, List<Map<String, dynamic>>> classGroups = {};
    for (final d in demands) {
      final cls = d['stuclass']?.toString() ?? 'Unknown';
      classGroups.putIfAbsent(cls, () => []).add(d);
    }

    if (classGroups.isEmpty) return _emptyState('No pending fees found');

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: EdgeInsets.all(12.w),
            child: Row(
              children: [
                Text('PENDING FEE REPORT - YEAR WISE',
                    style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                const Spacer(),
                TextButton.icon(
                  onPressed: () => _exportPendingReport(demands, terms, 'Year_Wise'),
                  icon: Icon(Icons.download_rounded, size: 16.sp),
                  label: Text('Export Excel', style: TextStyle(fontSize: 13.sp)),
                ),
              ],
            ),
          ),
          ...classGroups.entries.map((entry) {
            final className = entry.key;
            final classDemands = entry.value;
            final pivotData = _buildPivotData(classDemands, terms, showPending: true);
            final Map<String, double> termTotals = {};
            for (final row in pivotData) {
              for (final t in terms) {
                termTotals[t] = (termTotals[t] ?? 0) + (row[t] as double? ?? 0);
              }
            }
            final grandTotal = termTotals.values.fold<double>(0, (s, v) => s + v);

            return Container(
              margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10.r),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(10.r)),
                    ),
                    child: Row(
                      children: [
                        Text(className, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.accent)),
                        const Spacer(),
                        Text('${pivotData.length} students', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                        SizedBox(width: 16.w),
                        Text('Total Pending: ${_formatNumber(grandTotal)}',
                            style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.red)),
                      ],
                    ),
                  ),
                  _buildDataTable(terms, pivotData, termTotals),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // SHARED TABLE BUILDER
  // ═══════════════════════════════════════════════
  Widget _buildReportTable({
    required String title,
    required String subtitle,
    required List<String> terms,
    required List<Map<String, dynamic>> pivotData,
    required Map<String, double> termTotals,
    required bool showPending,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title & export
        Padding(
          padding: EdgeInsets.all(12.w),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  Text(subtitle, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                ],
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: () => _exportCollectionStatement(pivotData, terms, termTotals),
                icon: Icon(Icons.download_rounded, size: 16.sp),
                label: Text('Export Excel', style: TextStyle(fontSize: 13.sp)),
              ),
            ],
          ),
        ),
        // Totals row
        Container(
          margin: EdgeInsets.symmetric(horizontal: 12.w),
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8.r),
          ),
          child: Row(
            children: [
              Text('${pivotData.length} Students', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
              const Spacer(),
              ...terms.map((t) => Padding(
                padding: EdgeInsets.only(left: 12.w),
                child: Column(
                  children: [
                    Text(t, style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary)),
                    Text(_formatNumber(termTotals[t] ?? 0),
                        style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                  ],
                ),
              )),
            ],
          ),
        ),
        SizedBox(height: 8.h),
        // Data table
        Expanded(child: _buildDataTable(terms, pivotData, termTotals)),
      ],
    );
  }

  Widget _buildDataTable(List<String> terms, List<Map<String, dynamic>> pivotData, Map<String, double> termTotals, {bool grouped = false}) {
    // Group by course + class for display
    final Map<String, List<Map<String, dynamic>>> classGroups = {};
    for (final row in pivotData) {
      final course = row['courname']?.toString() ?? '';
      final cls = row['stuclass']?.toString() ?? 'Unknown';
      final key = course.isNotEmpty ? '$course - $cls' : cls;
      classGroups.putIfAbsent(key, () => []).add(row);
    }

    final allRows = <DataRow>[];
    int sno = 0;

    for (final entry in classGroups.entries) {
      final classStudents = entry.value;
      final Map<String, double> classTotals = {};
      double classGrandTotal = 0;
      double classTotalFine = 0;

      for (final row in classStudents) {
        sno++;
        final rowTotal = (row['_total'] as double?) ?? 0;
        final rowFine = (row['_fine'] as double?) ?? 0;
        classGrandTotal += rowTotal;
        classTotalFine += rowFine;
        allRows.add(DataRow(
          cells: [
            DataCell(Text('$sno', style: TextStyle(fontSize: 11.sp))),
            DataCell(Text(row['stuclass']?.toString() ?? '', style: TextStyle(fontSize: 11.sp))),
            DataCell(Text(row['stuadmno']?.toString() ?? '', style: TextStyle(fontSize: 11.sp))),
            DataCell(Text(row['stuname']?.toString() ?? '', style: TextStyle(fontSize: 11.sp))),
            ...terms.map((t) {
              final val = (row[t] as double?) ?? 0;
              if (val > 0) classTotals[t] = (classTotals[t] ?? 0) + val;
              return DataCell(Text(val > 0 ? _formatNumber(val) : '', style: TextStyle(fontSize: 11.sp)));
            }),
            DataCell(Text(rowFine > 0 ? _formatNumber(rowFine) : '', style: TextStyle(fontSize: 11.sp, color: Colors.orange))),
            DataCell(Text(rowTotal > 0 ? _formatNumber(rowTotal) : '', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w600))),
            DataCell(Text(row['_remarks']?.toString() ?? '', style: TextStyle(fontSize: 10.sp, color: AppColors.textSecondary))),
          ],
        ));
      }

      // Class total row
      allRows.add(DataRow(
        color: WidgetStateProperty.all(const Color(0xFFE2E8F0)),
        cells: [
          DataCell(Text('', style: TextStyle(fontSize: 11.sp))),
          DataCell(Text('Total', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700))),
          DataCell(Text('', style: TextStyle(fontSize: 11.sp))),
          DataCell(Text('', style: TextStyle(fontSize: 11.sp))),
          ...terms.map((t) => DataCell(Text(
            (classTotals[t] ?? 0) > 0 ? _formatNumber(classTotals[t]!) : '',
            style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700),
          ))),
          DataCell(Text(classTotalFine > 0 ? _formatNumber(classTotalFine) : '', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700, color: Colors.orange))),
          DataCell(Text(classGrandTotal > 0 ? _formatNumber(classGrandTotal) : '', style: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700))),
          DataCell(Text('', style: TextStyle(fontSize: 11.sp))),
        ],
      ));
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF1E2532)),
          headingTextStyle: TextStyle(fontSize: 11.sp, fontWeight: FontWeight.w700, color: Colors.white),
          dataTextStyle: TextStyle(fontSize: 11.sp, color: AppColors.textPrimary),
          columnSpacing: 14, horizontalMargin: 10, dataRowMinHeight: 30, dataRowMaxHeight: 34, headingRowHeight: 36,
          columns: [
            const DataColumn(label: Text('Sno')),
            const DataColumn(label: Text('Class')),
            const DataColumn(label: Text('Admn. No')),
            const DataColumn(label: Text('Student Name')),
            ...terms.map((t) => DataColumn(label: Text(t), numeric: true)),
            const DataColumn(label: Text('Fine'), numeric: true),
            const DataColumn(label: Text('Total'), numeric: true),
            const DataColumn(label: Text('Remarks')),
          ],
          rows: allRows,
        ),
      ),
    );
  }

  Widget _emptyState(String message) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assessment_outlined, size: 48.sp, color: AppColors.textSecondary.withValues(alpha: 0.4)),
          SizedBox(height: 12.h),
          Text(message, style: TextStyle(fontSize: 14.sp, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════
  // EXCEL EXPORT: COLLECTION STATEMENT
  // ═══════════════════════════════════════════════
  Future<void> _exportCollectionStatement(List<Map<String, dynamic>> pivotData, List<String> terms, Map<String, double> termTotals) async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Pending Fees'];
      excel.delete('Sheet1');

      final darkHeader = xl.CellStyle(
        bold: true, fontSize: 14,
        backgroundColorHex: xl.ExcelColor.fromHexString('#1E2532'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      final subHeader = xl.CellStyle(bold: true, fontSize: 11);
      final colHeader = xl.CellStyle(
        bold: true, fontSize: 10,
        backgroundColorHex: xl.ExcelColor.fromHexString('#2D3748'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      );
      final totalStyle = xl.CellStyle(bold: true, fontSize: 11);
      final numStyle = xl.CellStyle(fontSize: 10, horizontalAlign: xl.HorizontalAlign.Right);

      // Columns: Sno, Class, Admn. No, Student Name, [terms], Total, Remarks
      final totalCols = 4 + terms.length + 3;

      // Institution header
      int row = 0;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(_insName);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = darkHeader;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(_insAddress);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = xl.CellStyle(horizontalAlign: xl.HorizontalAlign.Center);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
      final contactLine = [if (_insPhone.isNotEmpty) 'Ph: $_insPhone', if (_insEmail.isNotEmpty) 'Email: $_insEmail'].join('  |  ');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(contactLine);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = xl.CellStyle(horizontalAlign: xl.HorizontalAlign.Right);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;

      // Title
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('PENDING FEE REPORT AS ON ${_formatDate(DateTime.now())}');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = subHeader;
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('FEE TYPE : ${_selectedFeeType ?? 'ALL FEE TYPE'}');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = subHeader;
      row++;
      row++; // blank row

      // Column headers: Sno, Class, Admn. No, Student Name, [terms], Total, Remarks
      final headers = ['Sno', 'Class', 'Admn. No', 'Student Name', ...terms, 'Fine', 'Total', 'Remarks'];
      for (int c = 0; c < headers.length; c++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value = xl.TextCellValue(headers[c]);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = colHeader;
      }
      row++;

      // Group by course + class
      final Map<String, List<Map<String, dynamic>>> classGroups = {};
      for (final s in pivotData) {
        final course = s['courname']?.toString() ?? '';
        final cls = s['stuclass']?.toString() ?? 'Unknown';
        final key = course.isNotEmpty ? '$course - $cls' : cls;
        classGroups.putIfAbsent(key, () => []).add(s);
      }

      int sno = 0;
      for (final entry in classGroups.entries) {
        final classStudents = entry.value;
        final Map<String, double> classTotals = {};
        double classGrandTotal = 0;

        for (final student in classStudents) {
          sno++;
          final rowTotal = (student['_total'] as double?) ?? 0;
          classGrandTotal += rowTotal;

          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.IntCellValue(sno);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue(student['stuclass']?.toString() ?? '');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.TextCellValue(student['stuadmno']?.toString() ?? '');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.TextCellValue(student['stuname']?.toString() ?? '');
          for (int c = 0; c < terms.length; c++) {
            final val = (student[terms[c]] as double?) ?? 0;
            if (val > 0) {
              classTotals[terms[c]] = (classTotals[terms[c]] ?? 0) + val;
              sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).value = xl.IntCellValue(val.toInt());
              sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).cellStyle = numStyle;
            }
          }
          if (rowTotal > 0) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).value = xl.IntCellValue(rowTotal.toInt());
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).cellStyle = numStyle;
          }
          final rowFine = (student['_fine'] as double?) ?? 0;
          if (rowFine > 0) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + terms.length, rowIndex: row)).value = xl.IntCellValue(rowFine.toInt());
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + terms.length, rowIndex: row)).cellStyle = numStyle;
          }
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + terms.length, rowIndex: row)).value = xl.TextCellValue(student['_remarks']?.toString() ?? '');
          row++;
        }

        // Class total row
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue('Total');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = totalStyle;
        for (int c = 0; c < terms.length; c++) {
          final val = classTotals[terms[c]] ?? 0;
          if (val > 0) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).value = xl.IntCellValue(val.toInt());
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).cellStyle = totalStyle;
          }
        }
        if (classGrandTotal > 0) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).value = xl.IntCellValue(classGrandTotal.toInt());
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).cellStyle = totalStyle;
        }
        row++;
      }

      // Column widths
      sheet.setColumnWidth(0, 6);
      sheet.setColumnWidth(1, 8);
      sheet.setColumnWidth(2, 10);
      sheet.setColumnWidth(3, 22);
      for (int c = 0; c < terms.length; c++) {
        sheet.setColumnWidth(4 + c, 12);
      }
      sheet.setColumnWidth(4 + terms.length, 8);
      sheet.setColumnWidth(5 + terms.length, 10);
      sheet.setColumnWidth(6 + terms.length, 25);

      await _saveExcel(excel, 'Pending_Fee_Report_${_formatDateCompact(DateTime.now())}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red));
    }
  }

  // ═══════════════════════════════════════════════
  // EXCEL EXPORT: PENDING REPORT
  // ═══════════════════════════════════════════════
  Future<void> _exportPendingReport(List<Map<String, dynamic>> demands, List<String> terms, String groupBy) async {
    try {
      final excel = xl.Excel.createExcel();
      final sheet = excel['Pending Fees'];
      excel.delete('Sheet1');

      final darkHeader = xl.CellStyle(
        bold: true, fontSize: 14,
        backgroundColorHex: xl.ExcelColor.fromHexString('#1E2532'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
        horizontalAlign: xl.HorizontalAlign.Center,
      );
      final subHeader = xl.CellStyle(bold: true, fontSize: 11);
      final colHeader = xl.CellStyle(
        bold: true, fontSize: 10,
        backgroundColorHex: xl.ExcelColor.fromHexString('#2D3748'),
        fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
      );
      final totalStyle = xl.CellStyle(bold: true, fontSize: 11);
      final numStyle = xl.CellStyle(fontSize: 10, horizontalAlign: xl.HorizontalAlign.Right);

      // Columns: Sno, Class, Admn. No, Student Name, [terms], Total, Remarks
      final totalCols = 4 + terms.length + 3;
      int row = 0;

      // Institution header
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(_insName);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = darkHeader;
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(_insAddress);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = xl.CellStyle(horizontalAlign: xl.HorizontalAlign.Center);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;
      final contactLine = [if (_insPhone.isNotEmpty) 'Ph: $_insPhone', if (_insEmail.isNotEmpty) 'Email: $_insEmail'].join('  |  ');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue(contactLine);
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = xl.CellStyle(horizontalAlign: xl.HorizontalAlign.Right);
      sheet.merge(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row), xl.CellIndex.indexByColumnRow(columnIndex: totalCols - 1, rowIndex: row));
      row++;

      // Title
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('PENDING FEE REPORT AS ON ${_formatDate(DateTime.now())}');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = subHeader;
      row++;
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.TextCellValue('FEE TYPE : ${_selectedFeeType ?? 'ALL FEE TYPE'}');
      sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).cellStyle = subHeader;
      row++;
      row++; // blank row

      // Column headers
      final headers = ['Sno', 'Class', 'Admn. No', 'Student Name', ...terms, 'Fine', 'Total', 'Remarks'];
      for (int c = 0; c < headers.length; c++) {
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).value = xl.TextCellValue(headers[c]);
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: row)).cellStyle = colHeader;
      }
      row++;

      // Group by course + class
      final Map<String, List<Map<String, dynamic>>> classGroups = {};
      for (final d in demands) {
        final course = d['courname']?.toString() ?? '';
        final cls = d['stuclass']?.toString() ?? 'Unknown';
        final key = course.isNotEmpty ? '$course - $cls' : cls;
        classGroups.putIfAbsent(key, () => []).add(d);
      }

      int sno = 0;
      for (final entry in classGroups.entries) {
        final classStudents = entry.value;
        final pivotData = _buildPivotData(classStudents, terms, showPending: true);
        final Map<String, double> classTotals = {};
        double classGrandTotal = 0;

        for (final student in pivotData) {
          sno++;
          final rowTotal = (student['_total'] as double?) ?? 0;
          classGrandTotal += rowTotal;

          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: row)).value = xl.IntCellValue(sno);
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue(student['stuclass']?.toString() ?? '');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: row)).value = xl.TextCellValue(student['stuadmno']?.toString() ?? '');
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: row)).value = xl.TextCellValue(student['stuname']?.toString() ?? '');
          for (int c = 0; c < terms.length; c++) {
            final val = (student[terms[c]] as double?) ?? 0;
            if (val > 0) {
              classTotals[terms[c]] = (classTotals[terms[c]] ?? 0) + val;
              sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).value = xl.IntCellValue(val.toInt());
              sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).cellStyle = numStyle;
            }
          }
          if (rowTotal > 0) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).value = xl.IntCellValue(rowTotal.toInt());
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).cellStyle = numStyle;
          }
          final rowFine = (student['_fine'] as double?) ?? 0;
          if (rowFine > 0) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + terms.length, rowIndex: row)).value = xl.IntCellValue(rowFine.toInt());
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + terms.length, rowIndex: row)).cellStyle = numStyle;
          }
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 6 + terms.length, rowIndex: row)).value = xl.TextCellValue(student['_remarks']?.toString() ?? '');
          row++;
        }

        // Class total row
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).value = xl.TextCellValue('Total');
        sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: row)).cellStyle = totalStyle;
        for (int c = 0; c < terms.length; c++) {
          final val = classTotals[terms[c]] ?? 0;
          if (val > 0) {
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).value = xl.IntCellValue(val.toInt());
            sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 4 + c, rowIndex: row)).cellStyle = totalStyle;
          }
        }
        if (classGrandTotal > 0) {
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).value = xl.IntCellValue(classGrandTotal.toInt());
          sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: 5 + terms.length, rowIndex: row)).cellStyle = totalStyle;
        }
        row++;
      }

      // Column widths
      sheet.setColumnWidth(0, 6);
      sheet.setColumnWidth(1, 8);
      sheet.setColumnWidth(2, 10);
      sheet.setColumnWidth(3, 22);
      for (int c = 0; c < terms.length; c++) {
        sheet.setColumnWidth(4 + c, 12);
      }
      sheet.setColumnWidth(4 + terms.length, 8);
      sheet.setColumnWidth(5 + terms.length, 10);
      sheet.setColumnWidth(6 + terms.length, 25);

      await _saveExcel(excel, 'Pending_${groupBy}_${_formatDateCompact(DateTime.now())}');
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export error: $e'), backgroundColor: Colors.red));
    }
  }

  Future<void> _saveExcel(xl.Excel excel, String fileName) async {
    final bytes = excel.encode();
    if (bytes == null) return;

    final result = await FilePicker.platform.saveFile(
      dialogTitle: 'Save Report',
      fileName: '$fileName.xlsx',
      type: FileType.custom,
      allowedExtensions: ['xlsx'],
    );
    if (result == null) return;

    final file = File(result);
    await file.writeAsBytes(bytes);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Report saved: ${file.path}'), backgroundColor: Colors.green),
      );
    }
  }
}
