import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class FeeCollectionScreen extends StatefulWidget {
  const FeeCollectionScreen({super.key});

  @override
  State<FeeCollectionScreen> createState() => _FeeCollectionScreenState();
}

class _FeeCollectionScreenState extends State<FeeCollectionScreen> {
  bool _isLoading = false;
  List<_ClassGroup> _classGroups = [];
  String? _selectedClass; // null = class view, non-null = student drilldown

  @override
  void initState() {
    super.initState();
    _fetchData();
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);

    final demands = await SupabaseService.getFeeDemands(insId);

    // Group by class
    final Map<String, List<Map<String, dynamic>>> grouped = {};
    for (final d in demands) {
      final cls = d['stuclass']?.toString() ?? 'Unknown';
      grouped.putIfAbsent(cls, () => []).add(d);
    }

    final classGroups = grouped.entries.map((e) {
      double totalDemand = 0;
      double totalPaid = 0;
      double totalPending = 0;
      double totalConcession = 0;
      final Set<String> studentAdmNos = {};

      for (final d in e.value) {
        final fee = (d['feeamount'] as num?)?.toDouble() ?? 0;
        final con = (d['conamount'] as num?)?.toDouble() ?? 0;
        final paid = (d['paidamount'] as num?)?.toDouble() ?? 0;
        final balance = (d['balancedue'] as num?)?.toDouble() ?? 0;
        totalDemand += fee;
        totalConcession += con;
        totalPaid += paid;
        totalPending += balance;
        final admNo = d['stuadmno']?.toString() ?? '';
        if (admNo.isNotEmpty) studentAdmNos.add(admNo);
      }

      return _ClassGroup(
        className: e.key,
        demands: e.value,
        totalDemand: totalDemand,
        totalConcession: totalConcession,
        totalPaid: totalPaid,
        totalPending: totalPending,
        studentCount: studentAdmNos.length,
      );
    }).toList();

    // Sort classes naturally
    classGroups.sort((a, b) => _compareClass(a.className, b.className));

    if (mounted) {
      setState(() {
        _classGroups = classGroups;
        _isLoading = false;
      });
    }
  }

  int _compareClass(String a, String b) {
    final numA = int.tryParse(a.replaceAll(RegExp(r'[^0-9]'), ''));
    final numB = int.tryParse(b.replaceAll(RegExp(r'[^0-9]'), ''));
    if (numA != null && numB != null) return numA.compareTo(numB);
    return a.compareTo(b);
  }

  String _formatCurrency(double amount) {
    final str = amount.toStringAsFixed(0);
    final pattern = RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))');
    final formatted = str.replaceAllMapped(pattern, (m) => '${m[1]},');
    return '₹$formatted';
  }

  // Get student-level data for a class
  List<_StudentDemand> _getStudentsForClass(String className) {
    final classGroup = _classGroups.firstWhere(
      (g) => g.className == className,
      orElse: () => _ClassGroup(
        className: className,
        demands: [],
        totalDemand: 0,
        totalConcession: 0,
        totalPaid: 0,
        totalPending: 0,
        studentCount: 0,
      ),
    );

    // Group demands by student admno
    final Map<String, List<Map<String, dynamic>>> byStudent = {};
    for (final d in classGroup.demands) {
      final admNo = d['stuadmno']?.toString() ?? 'Unknown';
      byStudent.putIfAbsent(admNo, () => []).add(d);
    }

    return byStudent.entries.map((e) {
      double totalFee = 0;
      double totalCon = 0;
      double totalPaid = 0;
      double totalBalance = 0;
      String studentName = '-';

      for (final d in e.value) {
        totalFee += (d['feeamount'] as num?)?.toDouble() ?? 0;
        totalCon += (d['conamount'] as num?)?.toDouble() ?? 0;
        totalPaid += (d['paidamount'] as num?)?.toDouble() ?? 0;
        totalBalance += (d['balancedue'] as num?)?.toDouble() ?? 0;
        final stu = d['students'];
        if (stu is Map && stu['stuname'] != null) {
          studentName = stu['stuname'].toString();
        }
      }

      return _StudentDemand(
        admNo: e.key,
        studentName: studentName,
        feeAmount: totalFee,
        concession: totalCon,
        paidAmount: totalPaid,
        balance: totalBalance,
      );
    }).toList()
      ..sort((a, b) => a.admNo.compareTo(b.admNo));
  }

  @override
  Widget build(BuildContext context) {
    // Overall summary
    double grandDemand = 0;
    double grandPaid = 0;
    double grandPending = 0;
    int grandStudents = 0;
    for (final g in _classGroups) {
      grandDemand += g.totalDemand;
      grandPaid += g.totalPaid;
      grandPending += g.totalPending;
      grandStudents += g.studentCount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Summary cards
        Row(
          children: [
            _buildSummaryCard('Total Demand', _isLoading ? '...' : _formatCurrency(grandDemand),
                Icons.request_quote_rounded, AppColors.info),
            const SizedBox(width: 12),
            _buildSummaryCard('Total Collected', _isLoading ? '...' : _formatCurrency(grandPaid),
                Icons.account_balance_wallet_rounded, AppColors.success),
            const SizedBox(width: 12),
            _buildSummaryCard('Total Pending', _isLoading ? '...' : _formatCurrency(grandPending),
                Icons.pending_actions_rounded, AppColors.warning),
            const SizedBox(width: 12),
            _buildSummaryCard('Total Students', _isLoading ? '...' : '$grandStudents',
                Icons.people_alt_rounded, AppColors.accent),
          ],
        ),
        const SizedBox(height: 16),

        // Main table area
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(
                    children: [
                      if (_selectedClass != null) ...[
                        InkWell(
                          onTap: () => setState(() => _selectedClass = null),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Icon(Icons.arrow_back_rounded, size: 18, color: AppColors.accent),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Icon(
                        _selectedClass == null ? Icons.class_rounded : Icons.people_alt_rounded,
                        color: AppColors.accent, size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _selectedClass == null
                            ? 'Class-wise Fee Demand'
                            : 'Class $_selectedClass — Student Fee Details',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                      ),
                      const Spacer(),
                      InkWell(
                        onTap: _fetchData,
                        borderRadius: BorderRadius.circular(6),
                        child: Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20),
                  child: Divider(color: AppColors.border),
                ),

                // Content
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _selectedClass == null
                          ? _buildClassTable()
                          : _buildStudentTable(_selectedClass!),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ==================== CLASS-WISE TABLE ====================

  Widget _buildClassTable() {
    if (_classGroups.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off_rounded, size: 48, color: AppColors.textLight),
            SizedBox(height: 8),
            Text('No fee demands found', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Table header
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              SizedBox(width: 36, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Class', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 1, child: Text('Students', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Total Demand', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Pending', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 1, child: Text('% Paid', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            ],
          ),
        ),

        // Rows
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: _classGroups.length,
            itemBuilder: (context, index) {
              final group = _classGroups[index];
              final pct = group.totalDemand > 0
                  ? ((group.totalPaid / group.totalDemand) * 100).toStringAsFixed(0)
                  : '0';

              return InkWell(
                onTap: () => setState(() => _selectedClass = group.className),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                  ),
                  child: Row(
                    children: [
                      SizedBox(width: 36, child: Text('${index + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                      Expanded(
                        flex: 2,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: AppColors.accent.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(group.className, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent)),
                            ),
                            const SizedBox(width: 6),
                            const Icon(Icons.chevron_right_rounded, size: 16, color: AppColors.textLight),
                          ],
                        ),
                      ),
                      Expanded(flex: 1, child: Text('${group.studentCount}', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text(_formatCurrency(group.totalDemand), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                      Expanded(flex: 2, child: Text(_formatCurrency(group.totalPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.success))),
                      Expanded(
                        flex: 2,
                        child: Text(
                          _formatCurrency(group.totalPending),
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: group.totalPending > 0 ? AppColors.warning : AppColors.textSecondary),
                        ),
                      ),
                      Expanded(
                        flex: 1,
                        child: Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: int.parse(pct) >= 80
                                  ? AppColors.success.withValues(alpha: 0.1)
                                  : int.parse(pct) >= 50
                                      ? AppColors.warning.withValues(alpha: 0.1)
                                      : AppColors.error.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '$pct%',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: int.parse(pct) >= 80
                                    ? AppColors.success
                                    : int.parse(pct) >= 50
                                        ? AppColors.warning
                                        : AppColors.error,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== STUDENT DRILLDOWN TABLE ====================

  Widget _buildStudentTable(String className) {
    final students = _getStudentsForClass(className);

    if (students.isEmpty) {
      return const Center(
        child: Text('No student demands found for this class', style: TextStyle(color: AppColors.textSecondary)),
      );
    }

    return Column(
      children: [
        // Table header
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Row(
            children: [
              SizedBox(width: 36, child: Text('#', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              SizedBox(width: 100, child: Text('Adm No', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 3, child: Text('Student Name', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Fee Amount', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 1, child: Text('Concession', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Paid', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              Expanded(flex: 2, child: Text('Balance', textAlign: TextAlign.right, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
              SizedBox(width: 80, child: Text('Status', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
            ],
          ),
        ),

        // Student rows
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            itemCount: students.length + 1, // +1 for totals row
            itemBuilder: (context, index) {
              if (index == students.length) {
                // Totals row
                double tFee = 0, tCon = 0, tPaid = 0, tBal = 0;
                for (final s in students) {
                  tFee += s.feeAmount;
                  tCon += s.concession;
                  tPaid += s.paidAmount;
                  tBal += s.balance;
                }
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.03),
                    border: const Border(top: BorderSide(color: AppColors.border, width: 1.5)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 36),
                      const SizedBox(width: 100),
                      Expanded(flex: 3, child: Text('Total (${students.length} students)', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      Expanded(flex: 2, child: Text(_formatCurrency(tFee), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      Expanded(flex: 1, child: Text(_formatCurrency(tCon), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textSecondary))),
                      Expanded(flex: 2, child: Text(_formatCurrency(tPaid), textAlign: TextAlign.right, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.success))),
                      Expanded(flex: 2, child: Text(_formatCurrency(tBal), textAlign: TextAlign.right, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: tBal > 0 ? AppColors.warning : AppColors.success))),
                      const SizedBox(width: 80),
                    ],
                  ),
                );
              }

              final s = students[index];
              final isPaid = s.balance <= 0;
              final isPartial = s.paidAmount > 0 && s.balance > 0;

              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppColors.border.withValues(alpha: 0.5))),
                ),
                child: Row(
                  children: [
                    SizedBox(width: 36, child: Text('${index + 1}', style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    SizedBox(width: 100, child: Text(s.admNo, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.textPrimary))),
                    Expanded(flex: 3, child: Text(s.studentName, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
                    Expanded(flex: 2, child: Text(_formatCurrency(s.feeAmount), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.textPrimary))),
                    Expanded(flex: 1, child: Text(_formatCurrency(s.concession), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary))),
                    Expanded(flex: 2, child: Text(_formatCurrency(s.paidAmount), textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: AppColors.success))),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _formatCurrency(s.balance),
                        textAlign: TextAlign.right,
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: s.balance > 0 ? AppColors.warning : AppColors.textSecondary),
                      ),
                    ),
                    SizedBox(
                      width: 80,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? AppColors.success.withValues(alpha: 0.1)
                                : isPartial
                                    ? AppColors.warning.withValues(alpha: 0.1)
                                    : AppColors.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            isPaid ? 'Paid' : isPartial ? 'Partial' : 'Unpaid',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: isPaid ? AppColors.success : isPartial ? AppColors.warning : AppColors.error,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ==================== SHARED WIDGETS ====================

  Widget _buildSummaryCard(String label, String value, IconData icon, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
                  Text(label, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==================== DATA CLASSES ====================

class _ClassGroup {
  final String className;
  final List<Map<String, dynamic>> demands;
  final double totalDemand;
  final double totalConcession;
  final double totalPaid;
  final double totalPending;
  final int studentCount;

  _ClassGroup({
    required this.className,
    required this.demands,
    required this.totalDemand,
    required this.totalConcession,
    required this.totalPaid,
    required this.totalPending,
    required this.studentCount,
  });
}

class _StudentDemand {
  final String admNo;
  final String studentName;
  final double feeAmount;
  final double concession;
  final double paidAmount;
  final double balance;

  _StudentDemand({
    required this.admNo,
    required this.studentName,
    required this.feeAmount,
    required this.concession,
    required this.paidAmount,
    required this.balance,
  });
}
