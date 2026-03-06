import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/payment_model.dart';

class FailedTransactionsScreen extends StatefulWidget {
  const FailedTransactionsScreen({super.key});

  @override
  State<FailedTransactionsScreen> createState() =>
      _FailedTransactionsScreenState();
}

class _FailedTransactionsScreenState extends State<FailedTransactionsScreen> {
  bool _isLoading = false;
  List<PaymentModel> _failedTransactions = [];

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
    try {
      final data = await SupabaseService.getFailedTransactions(insId);
      setState(() {
        _failedTransactions =
            data.map((e) => PaymentModel.fromJson(e)).toList();
      });
    } catch (e) {
      debugPrint('Error loading failed transactions: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_failedTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_outline_rounded,
                size: 64, color: AppColors.accent.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              'No Failed Transactions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'All transactions have been processed successfully.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppColors.textSecondary.withValues(alpha: 0.7),
                  ),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Header row
        Row(
          children: [
            Icon(Icons.error_outline_rounded,
                color: Colors.red.shade400, size: 22),
            const SizedBox(width: 10),
            Text(
              'Failed Transactions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${_failedTransactions.length}',
                style: TextStyle(
                  color: Colors.red.shade700,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
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

        // Table
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SingleChildScrollView(
                  child: DataTable(
                    headingRowColor:
                        WidgetStateProperty.all(AppColors.primary.withValues(alpha: 0.05)),
                    headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    dataTextStyle: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                    columnSpacing: 24,
                    columns: const [
                      DataColumn(label: Text('#')),
                      DataColumn(label: Text('Pay ID')),
                      DataColumn(label: Text('Student ID')),
                      DataColumn(label: Text('Amount')),
                      DataColumn(label: Text('Currency')),
                      DataColumn(label: Text('Method')),
                      DataColumn(label: Text('Reference')),
                      DataColumn(label: Text('Date')),
                      DataColumn(label: Text('Status')),
                    ],
                    rows: List.generate(_failedTransactions.length, (i) {
                      final t = _failedTransactions[i];
                      return DataRow(
                        cells: [
                          DataCell(Text('${i + 1}')),
                          DataCell(Text('${t.payId}')),
                          DataCell(Text('${t.stuId ?? '-'}')),
                          DataCell(Text(
                            t.transtotalamount.toStringAsFixed(2),
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          )),
                          DataCell(Text(t.transcurrency)),
                          DataCell(Text(t.paymethod ?? '-')),
                          DataCell(Text(t.payreference ?? '-')),
                          DataCell(Text(
                            t.paydate != null
                                ? '${t.paydate!.day.toString().padLeft(2, '0')}/${t.paydate!.month.toString().padLeft(2, '0')}/${t.paydate!.year}'
                                : '-',
                          )),
                          DataCell(Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Failed',
                              style: TextStyle(
                                color: Colors.red.shade700,
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
          ),
        ),
      ],
    );
  }
}
