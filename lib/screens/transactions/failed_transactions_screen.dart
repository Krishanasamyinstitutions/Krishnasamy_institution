import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/payment_model.dart';
import '../../models/student_model.dart';

class FailedTransactionsScreen extends StatefulWidget {
  const FailedTransactionsScreen({super.key});

  @override
  State<FailedTransactionsScreen> createState() =>
      _FailedTransactionsScreenState();
}

class _FailedTransactionsScreenState extends State<FailedTransactionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _isLoading = false;
  List<PaymentModel> _paidTransactions = [];
  List<PaymentModel> _failedTransactions = [];
  Map<int, String> _stuIdToName = {};

  List<PaymentModel> get _allTransactions {
    final all = [..._paidTransactions, ..._failedTransactions];
    all.sort((a, b) {
      final dateA = a.paydate ?? a.createdat;
      final dateB = b.paydate ?? b.createdat;
      return dateB.compareTo(dateA);
    });
    return all;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _fetchData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _fetchData() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        SupabaseService.getPaidTransactions(insId),
        SupabaseService.getFailedTransactions(insId),
        SupabaseService.getStudents(insId),
      ]);

      final paidData = results[0] as List<Map<String, dynamic>>;
      final failedData = results[1] as List<Map<String, dynamic>>;
      final students = results[2] as List<StudentModel>;

      final stuIdToName = <int, String>{};
      for (final s in students) {
        stuIdToName[s.stuId] = s.stuname;
      }

      setState(() {
        _paidTransactions =
            paidData.map((e) => PaymentModel.fromJson(e)).toList();
        _failedTransactions =
            failedData.map((e) => PaymentModel.fromJson(e)).toList();
        _stuIdToName = stuIdToName;
      });
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _getStudentName(PaymentModel t) {
    if (t.stuId != null && _stuIdToName.containsKey(t.stuId)) {
      return _stuIdToName[t.stuId]!;
    }
    return '-';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Header + Tabs row
        Row(
          children: [
            Icon(Icons.receipt_long_rounded,
                color: AppColors.primary, size: 22),
            const SizedBox(width: 10),
            Text(
              'Transactions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: _fetchData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Tab bar at the top
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(10),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 4,
                  offset: const Offset(0, 1),
                ),
              ],
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            dividerColor: Colors.transparent,
            labelColor: AppColors.textPrimary,
            unselectedLabelColor: AppColors.textSecondary,
            labelStyle:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.list_alt_rounded,
                        size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    const Text('All'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_paidTransactions.length + _failedTransactions.length}',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: Colors.green.shade600),
                    const SizedBox(width: 8),
                    const Text('Paid'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_paidTransactions.length}',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_rounded,
                        size: 16, color: Colors.red.shade600),
                    const SizedBox(width: 8),
                    const Text('Failed'),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_failedTransactions.length}',
                        style: TextStyle(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w700,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Summary cards
        _buildSummaryCards(),
        const SizedBox(height: 16),

        // Tab content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAllTransactionTable(),
                    _buildTransactionTable(_paidTransactions, isPaid: true),
                    _buildTransactionTable(_failedTransactions, isPaid: false),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    final paidTotal = _paidTransactions.fold<double>(
        0, (sum, t) => sum + t.transtotalamount);
    final failedTotal = _failedTransactions.fold<double>(
        0, (sum, t) => sum + t.transtotalamount);

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Total Paid',
            '\u20B9 ${paidTotal.toStringAsFixed(2)}',
            '${_paidTransactions.length} transactions',
            Colors.green,
            Icons.check_circle_outline_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryCard(
            'Total Failed',
            '\u20B9 ${failedTotal.toStringAsFixed(2)}',
            '${_failedTransactions.length} transactions',
            Colors.red,
            Icons.error_outline_rounded,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildSummaryCard(
            'Total Transactions',
            '${_paidTransactions.length + _failedTransactions.length}',
            'All records',
            AppColors.primary,
            Icons.receipt_long_rounded,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
      String title, String value, String subtitle, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllTransactionTable() {
    final transactions = _allTransactions;
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 64, color: AppColors.accent.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No Transactions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                  AppColors.primary.withValues(alpha: 0.05)),
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              dataTextStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Pay No')),
                DataColumn(label: Text('Student')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Currency')),
                DataColumn(label: Text('Method')),
                DataColumn(label: Text('Reference')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Status')),
              ],
              rows: List.generate(transactions.length, (i) {
                final t = transactions[i];
                final stuName = _getStudentName(t);
                final isPaid = t.isSuccess;
                final statusColor = isPaid ? Colors.green : Colors.red;
                final statusText = isPaid ? 'Paid' : 'Failed';
                final date = t.paydate ?? t.createdat;

                return DataRow(
                  cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(t.paynumber ?? '${t.payId}')),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          stuName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(
                      t.transtotalamount.toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )),
                    DataCell(Text(t.transcurrency)),
                    DataCell(Text(t.paymethod ?? '-')),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          t.payreference ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(
                      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}',
                    )),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    )),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTransactionTable(List<PaymentModel> transactions,
      {required bool isPaid}) {
    if (transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPaid
                  ? Icons.payment_rounded
                  : Icons.check_circle_outline_rounded,
              size: 64,
              color: AppColors.accent.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              isPaid ? 'No Paid Transactions' : 'No Failed Transactions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              isPaid
                  ? 'No completed payments found.'
                  : 'All transactions have been processed successfully.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SingleChildScrollView(
          child: SizedBox(
            width: double.infinity,
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(
                  AppColors.primary.withValues(alpha: 0.05)),
              headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              dataTextStyle: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
              columnSpacing: 20,
              columns: const [
                DataColumn(label: Text('#')),
                DataColumn(label: Text('Pay No')),
                DataColumn(label: Text('Student')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Currency')),
                DataColumn(label: Text('Method')),
                DataColumn(label: Text('Reference')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Status')),
              ],
              rows: List.generate(transactions.length, (i) {
                final t = transactions[i];
                final stuName = _getStudentName(t);
                final statusColor = isPaid ? Colors.green : Colors.red;
                final statusText = isPaid ? 'Paid' : 'Failed';
                final date = isPaid ? t.paydate : t.createdat;

                return DataRow(
                  cells: [
                    DataCell(Text('${i + 1}')),
                    DataCell(Text(t.paynumber ?? '${t.payId}')),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 180),
                        child: Text(
                          stuName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(
                      t.transtotalamount.toStringAsFixed(2),
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    )),
                    DataCell(Text(t.transcurrency)),
                    DataCell(Text(t.paymethod ?? '-')),
                    DataCell(
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          t.payreference ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(
                      date != null
                          ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'
                          : '-',
                    )),
                    DataCell(Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor.shade700,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    )),
                  ],
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
