import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
import '../../widgets/app_icon.dart';
import 'package:excel/excel.dart' hide Border, BorderStyle;
import 'dart:io';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class BankReconciliationScreen extends StatefulWidget {
  const BankReconciliationScreen({super.key});

  @override
  State<BankReconciliationScreen> createState() => _BankReconciliationScreenState();
}

class _BankReconciliationScreenState extends State<BankReconciliationScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _pendingPayments = [];
  List<Map<String, dynamic>> _reconciledPayments = [];
  List<Map<String, dynamic>> _bankStatementRows = [];
  bool _isLoading = false;
  final Set<int> _selectedForRecon = {};
  String _methodFilter = 'All';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPayments();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadPayments() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    try {
      // Single RPC call for all bank recon data
      List pending;
      List reconciled;
      try {
        final rpcResult = await SupabaseService.client.rpc('get_bank_recon_data', params: {'p_ins_id': insId});
        final data = rpcResult as Map<String, dynamic>? ?? {};
        pending = List<Map<String, dynamic>>.from(data['pending'] ?? []);
        reconciled = List<Map<String, dynamic>>.from(data['reconciled'] ?? []);
        // Build student_display from RPC data (already has stuname, stuadmno)
        for (final p in pending) {
          p['student_display'] = '${p['stuname'] ?? ''} (${p['stuadmno'] ?? ''})'.trim();
          if (p['student_display'] == '()') p['student_display'] = 'Student #${p['stu_id']}';
        }
        for (final p in reconciled) {
          p['student_display'] = '${p['stuname'] ?? ''} (${p['stuadmno'] ?? ''})'.trim();
          if (p['student_display'] == '()') p['student_display'] = 'Student #${p['stu_id']}';
        }
      } catch (e) {
        debugPrint('RPC get_bank_recon_data failed, using fallback: $e');
        // Fallback to direct queries
        final results = await Future.wait([
          SupabaseService.fromSchema('payment')
              .select('pay_id, paynumber, transtotalamount, paydate, paymethod, payreference, paychequeno, payorderid, stu_id, createdby, recon_status')
              .eq('ins_id', insId).eq('paystatus', 'C').eq('recon_status', 'P').eq('activestatus', 1).order('paydate', ascending: false),
          SupabaseService.fromSchema('payment')
              .select('pay_id, paynumber, transtotalamount, paydate, paymethod, payreference, stu_id, createdby, recon_status, reconciled_by, reconciled_date, bank_reference')
              .eq('ins_id', insId).eq('paystatus', 'C').eq('recon_status', 'R').eq('activestatus', 1).order('reconciled_date', ascending: false).limit(100),
        ]);
        pending = results[0]; reconciled = results[1];
        final allPayments = [...pending, ...reconciled];
        final stuIds = allPayments.map((p) => p['stu_id']).toSet().toList();
        Map<int, String> stuNames = {};
        if (stuIds.isNotEmpty) {
          try {
            final students = await SupabaseService.fromSchema('students').select('stu_id, stuname, stuadmno').inFilter('stu_id', stuIds);
            for (final s in students) { stuNames[s['stu_id'] as int] = '${s['stuname']} (${s['stuadmno']})'; }
          } catch (_) {}
        }
        for (final p in pending) { p['student_display'] = stuNames[p['stu_id']] ?? 'Student #${p['stu_id']}'; }
        for (final p in reconciled) { p['student_display'] = stuNames[p['stu_id']] ?? 'Student #${p['stu_id']}'; }
      }

      if (mounted) {
        setState(() {
          _pendingPayments = List<Map<String, dynamic>>.from(pending);
          _reconciledPayments = List<Map<String, dynamic>>.from(reconciled);
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Load payments error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _downloadSampleTemplate() async {
    try {
      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Bank Statement Template',
        fileName: 'bank_statement_template.csv',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (result == null) return;

      final csv = 'Date,Narration,Chq/Ref No,Value Date,Withdrawal,Deposit,Balance\n'
          '01/04/2026,UPI/412345678901/STUDENT NAME/SBI,412345678901,01/04/2026,,4200.00,154200.00\n'
          '01/04/2026,NEFT/HDFC001234/PARENT NAME,HDFC001234,01/04/2026,,6100.00,160300.00\n'
          '01/04/2026,CHQ CLG/123456,123456,01/04/2026,,2000.00,162300.00\n';

      await File(result).writeAsString(csv);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Template saved successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _uploadBankStatement() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    if (result == null || result.files.single.path == null) return;

    try {
      final file = File(result.files.single.path!);
      final csvString = await file.readAsString();
      final rows = const CsvToListConverter().convert(csvString, eol: '\n');

      if (rows.length < 2) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('CSV file is empty or has no data rows'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      // Parse CSV: handle Indian bank format
      final headers = rows.first.map((h) => h.toString().toLowerCase().trim()).toList();
      final dateIdx = headers.indexWhere((h) => h.contains('date') && !h.contains('value'));
      final refIdx = headers.indexWhere((h) => h.contains('ref') || h.contains('chq') || h.contains('transaction') || h.contains('utr'));
      final narrationIdx = headers.indexWhere((h) => h.contains('narration') || h.contains('desc') || h.contains('particular'));
      // Try Deposit/Credit column first, then Amount
      int amountIdx = headers.indexWhere((h) => h.contains('deposit') || h.contains('credit'));
      if (amountIdx < 0) amountIdx = headers.indexWhere((h) => h.contains('amount'));

      final bankRows = <Map<String, dynamic>>[];
      final usedPayIds = <int>{};

      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 2) continue;
        final amount = amountIdx >= 0 && amountIdx < row.length
            ? double.tryParse(row[amountIdx].toString().replaceAll(',', '').trim()) ?? 0
            : 0;
        if (amount <= 0) continue; // Skip withdrawals/zero entries

        bankRows.add({
          'date': dateIdx >= 0 && dateIdx < row.length ? row[dateIdx].toString().trim() : '',
          'reference': refIdx >= 0 && refIdx < row.length ? row[refIdx].toString().trim() : '',
          'narration': narrationIdx >= 0 && narrationIdx < row.length ? row[narrationIdx].toString().trim() : '',
          'amount': amount,
          'matched_pay_id': null,
          'match_type': '',
        });
      }

      // Auto-match: reference and amount must both match
      for (final bankRow in bankRows) {
        final bankRef = (bankRow['reference']?.toString() ?? '').trim();
        final bankNarration = (bankRow['narration']?.toString() ?? '').trim();
        final amount = bankRow['amount'] as double;

        if (bankRef.isEmpty) continue;

        final normalizedBankRef = _normalizeReference(bankRef);
        final normalizedNarration = _normalizeReference(bankNarration);

        // Match only when both reference and amount line up
        if (bankRef.isNotEmpty) {
          for (final payment in _pendingPayments) {
            if (usedPayIds.contains(payment['pay_id'])) continue;
            final payMethod = payment['paymethod']?.toString() ?? '';
            final payRef = payment['payreference']?.toString() ?? '';
            final chequeNo = payment['paychequeno']?.toString() ?? '';
            final payAmount = (payment['transtotalamount'] as num?)?.toDouble() ?? 0;
            final isAmountMatch = (payAmount - amount).abs() < 0.01;

            // Bank and Razorpay references: reference and amount must both match
            if ((payMethod == 'qr_upi' || payMethod == 'razorpay') &&
                isAmountMatch &&
                _normalizeReference(payRef).contains(normalizedBankRef)) {
              bankRow['matched_pay_id'] = payment['pay_id'];
              bankRow['match_type'] = payMethod == 'razorpay'
                  ? 'Razorpay + Amount Match'
                  : 'UTR + Amount Match';
              usedPayIds.add(payment['pay_id'] as int);
              break;
            }

            // Cheque: cheque number must match, and total of grouped receipts must match bank amount
            if (payMethod == 'cheque' &&
                chequeNo.isNotEmpty &&
                normalizedBankRef.contains(_normalizeReference(chequeNo))) {
              // Find all payments with this cheque number
              final chequePayments = _pendingPayments
                  .where((p) => p['paychequeno']?.toString() == chequeNo && !usedPayIds.contains(p['pay_id']))
                  .toList();
              final chequePayIds = chequePayments
                  .map((p) => p['pay_id'] as int)
                  .toList();
              final chequeTotal = chequePayments.fold<double>(
                0,
                (sum, p) => sum + ((p['transtotalamount'] as num?)?.toDouble() ?? 0),
              );

              if ((chequeTotal - amount).abs() < 0.01 && chequePayIds.isNotEmpty) {
                bankRow['matched_pay_id'] = payment['pay_id'];
                bankRow['matched_pay_ids'] = chequePayIds;
                bankRow['match_type'] = 'Cheque + Amount Match (${chequePayIds.length} receipts)';
                usedPayIds.addAll(chequePayIds);
                break;
              }
            }

            // Narration-derived reference also needs amount match
            if (bankNarration.isNotEmpty && payRef.isNotEmpty) {
              final normalizedPayRef = _normalizeReference(payRef);
              if (normalizedPayRef.isNotEmpty &&
                  isAmountMatch &&
                  normalizedNarration.contains(normalizedPayRef)) {
                bankRow['matched_pay_id'] = payment['pay_id'];
                bankRow['match_type'] = 'Narration + Amount Match';
                usedPayIds.add(payment['pay_id'] as int);
                break;
              }
            }
          }
        }
      }

      setState(() => _bankStatementRows = bankRows);
      _tabController.animateTo(1); // Switch to Bank Statement tab
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error reading CSV: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  /// Batch reconcile via RPC; falls back to per-row updates if the RPC
  /// is not yet deployed. Returns the number of payments marked.
  Future<int> _reconcilePaymentsBatch({
    required int insId,
    required String userName,
    required List<int> payIds,
    String? bankRef,
    String? bankDate,
  }) async {
    if (payIds.isEmpty) return 0;
    final schema = SupabaseService.currentSchema;
    try {
      if (schema != null) {
        final result = await SupabaseService.client.rpc('reconcile_payments_batch', params: {
          'p_schema': schema,
          'p_ins_id': insId,
          'p_pay_ids': payIds,
          'p_user': userName,
          'p_bank_ref': bankRef,
          'p_bank_date': bankDate,
        });
        return (result as num?)?.toInt() ?? payIds.length;
      }
    } catch (e) {
      debugPrint('reconcile_payments_batch RPC failed, using fallback: $e');
    }

    final now = DateTime.now().toIso8601String();
    await Future.wait(payIds.map((payId) =>
      SupabaseService.fromSchema('payment').update({
        'recon_status': 'R',
        'reconciled_by': userName,
        'reconciled_date': now,
        if (bankRef != null) 'bank_reference': bankRef,
        if (bankDate != null) 'bank_date': bankDate,
      }).eq('pay_id', payId).eq('ins_id', insId)
    ));
    try {
      final demands = await SupabaseService.fromSchema('feedemand')
          .select('dem_id, balancedue')
          .eq('ins_id', insId)
          .inFilter('pay_id', payIds);
      if ((demands as List).isNotEmpty) {
        await Future.wait(demands.map((d) {
          final demId = d['dem_id'];
          return demId != null
              ? SupabaseService.fromSchema('feedemand')
                  .update({'reconbalancedue': d['balancedue']})
                  .eq('dem_id', demId)
                  .eq('ins_id', insId)
              : Future.value();
        }));
      }
    } catch (e) {
      debugPrint('Fallback feedemand update error: $e');
    }
    return payIds.length;
  }

  Future<void> _reconcileSelected() async {
    if (_selectedForRecon.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final userName = auth.userName ?? 'Admin';
    if (insId == null) return;

    setState(() => _isLoading = true);
    final payIdList = _selectedForRecon.toList();
    final count = await _reconcilePaymentsBatch(
      insId: insId,
      userName: userName,
      payIds: payIdList,
    );

    _selectedForRecon.clear();
    await _loadPayments();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count payment(s) reconciled successfully'), backgroundColor: AppColors.success),
      );
    }
  }

  Future<void> _reconcileFromBankMatch() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final userName = auth.userName ?? 'Admin';
    if (insId == null) return;

    final matched = _bankStatementRows.where((r) => r['matched_pay_id'] != null).toList();
    if (matched.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No matched transactions to reconcile'), backgroundColor: Colors.orange),
      );
      return;
    }

    setState(() => _isLoading = true);
    int count = 0;

    // One batch call per bank-statement row (may cover multiple pay_ids).
    for (final row in matched) {
      final payIds = row['matched_pay_ids'] as List<int>? ?? [row['matched_pay_id'] as int];
      count += await _reconcilePaymentsBatch(
        insId: insId,
        userName: userName,
        payIds: payIds,
        bankRef: row['reference']?.toString(),
        bankDate: row['date']?.toString(),
      );
    }

    await _loadPayments();
    setState(() => _bankStatementRows.clear());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count payment(s) reconciled from bank statement'), backgroundColor: AppColors.success),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Pill-style tabs (matches Fee Collection/Reports)
        ListenableBuilder(
          listenable: _tabController,
          builder: (context, _) {
            final selected = _tabController.index;
            final tabLabels = [
              'Pending (${_pendingPayments.length})',
              'Bank Statement',
              'Reconciled (${_reconciledPayments.length})',
            ];
            final tabIcons = ['clock', 'document-upload', 'tick-square'];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tabLabels.length; i++) ...[
                      GestureDetector(
                        onTap: () => _tabController.animateTo(i),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: selected == i ? AppColors.tabSelected : Colors.transparent,
                            borderRadius: BorderRadius.circular(22),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppIcon(tabIcons[i], size: 16, color: selected == i ? AppColors.textOnPrimary : AppColors.textPrimary),
                              const SizedBox(width: 8),
                              Text(
                                tabLabels[i],
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: selected == i ? AppColors.textOnPrimary : AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (i < tabLabels.length - 1) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            );
          },
        ),
        SizedBox(height: 6.h),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildPendingTab(),
                    _buildBankStatementTab(),
                    _buildReconciledTab(),
                  ],
                ),
        ),
      ],
    );
  }

  // ── Tab 1: Pending Reconciliation ──
  Widget _buildPendingTab() {
    final filteredPending = _filteredPayments(_pendingPayments);
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            // Title + actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AppIcon.linear('clock', size: 18, color: AppColors.accent),
                  SizedBox(width: 8.w),
                  Text('Pending Payments', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(width: 12.w),
                  Text('${_selectedForRecon.length} selected', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                  const Spacer(),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _selectedForRecon.isEmpty ? null : _reconcileSelected,
                      icon: AppIcon('tick-circle', size: 16, color: Colors.white),
                      label: Text('Approve Selected', style: TextStyle(fontSize: 13.sp)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  SizedBox(width: 8.w),
                  SizedBox(
                    height: 40,
                    child: ElevatedButton.icon(
                      onPressed: _loadPayments,
                      icon: AppIcon('refresh', size: 16, color: Colors.white),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: EdgeInsets.symmetric(horizontal: 18.w),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Table wrapped in inner rounded card
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: filteredPending.isEmpty
                      ? Center(child: Text('No pending payments for reconciliation', style: TextStyle(color: AppColors.textSecondary)))
                      : Column(
                          children: [
                        // Header
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                          color: AppColors.tableHeadBg,
                          child: Row(
                            children: [
                              SizedBox(width: 40.w, child: Checkbox(
                                value: filteredPending.isNotEmpty && filteredPending.every((p) => _selectedForRecon.contains(p['pay_id'] as int)),
                                onChanged: (v) {
                                  setState(() {
                                    if (v == true) {
                                      _selectedForRecon.addAll(filteredPending.map((p) => p['pay_id'] as int));
                                    } else {
                                      for (final p in filteredPending) {
                                        _selectedForRecon.remove(p['pay_id'] as int);
                                      }
                                    }
                                  });
                                },
                                activeColor: AppColors.accent,
                              )),
                              Expanded(flex: 2, child: Text('PAY NO', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                              Expanded(flex: 3, child: Text('STUDENT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                              Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                              Expanded(flex: 2, child: Text('METHOD', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                              Expanded(flex: 2, child: Text('DATE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                              Expanded(flex: 2, child: Text('REFERENCE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                            ],
                          ),
                        ),
                        // Rows
                        Expanded(
                          child: SingleChildScrollView(
                            child: Column(
                              children: [
                                ...filteredPending.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final p = entry.value;
                                  final payId = p['pay_id'] as int;
                                  final isSelected = _selectedForRecon.contains(payId);
                                  return Container(
                                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                                    color: isSelected ? AppColors.accent.withValues(alpha: 0.05) : (idx.isEven ? Colors.white : AppColors.surface),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 40.w, child: Checkbox(
                                          value: isSelected,
                                          onChanged: (v) {
                                            setState(() {
                                              if (v == true) { _selectedForRecon.add(payId); } else { _selectedForRecon.remove(payId); }
                                            });
                                          },
                                          activeColor: AppColors.accent,
                                        )),
                                        Expanded(flex: 2, child: Text(p['paynumber']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 3, child: Text(p['student_display']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 2, child: Text('Rs.${(p['transtotalamount'] as num?)?.toStringAsFixed(2) ?? '0'}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 2, child: Text(_methodLabel(p['paymethod']?.toString()), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 2, child: Text(_formatDate(p['paydate']?.toString()), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 2, child: Text(p['payreference']?.toString() ?? '-', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab 2: Bank Statement Upload ──
  Widget _buildBankStatementTab() {
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AppIcon.linear('document-upload', size: 18, color: AppColors.accent),
                  SizedBox(width: 8.w),
                  Text('Bank Statement', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(width: 12.w),
                  if (_bankStatementRows.isNotEmpty) ...[
                Text('${_bankStatementRows.where((r) => r['matched_pay_id'] != null).length} matched', style: TextStyle(fontSize: 13.sp, color: AppColors.success, fontWeight: FontWeight.w600)),
                SizedBox(width: 16.w),
                SizedBox(
                  height: 40,
                  child: ElevatedButton.icon(
                    onPressed: _reconcileFromBankMatch,
                    icon: AppIcon('tick-circle', size: 16, color: Colors.white),
                    label: Text('Reconcile Matched', style: TextStyle(fontSize: 13.sp)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.success,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: EdgeInsets.symmetric(horizontal: 18.w),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                      textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
              const Spacer(),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _uploadBankStatement,
                  icon: AppIcon('document-upload', size: 16, color: Colors.white),
                  label: Text('Upload Bank Statement (CSV)', style: TextStyle(fontSize: 13.sp)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(horizontal: 18.w),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              SizedBox(width: 8.w),
              SizedBox(
                height: 40,
                child: ElevatedButton.icon(
                  onPressed: _downloadSampleTemplate,
                  icon: AppIcon('element-4', size: 16, color: Colors.white),
                  label: Text('Format to Excel', style: TextStyle(fontSize: 13.sp)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: EdgeInsets.symmetric(horizontal: 18.w),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                    textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
        // Table in a rounded card
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                children: [
                  // Table header
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    color: AppColors.tableHeadBg,
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('S.NO', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('DATE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('REFERENCE/UTR', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('MATCHED WITH', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 1, child: Text('MATCH TYPE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _bankStatementRows.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                AppIcon.linear('cloud-add', size: 48.sp, color: AppColors.textLight),
                                SizedBox(height: 12.h),
                                Text('Upload a bank statement CSV to match with pending payments', style: TextStyle(color: AppColors.textSecondary)),
                              ],
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                ..._bankStatementRows.asMap().entries.map((entry) {
                                  final idx = entry.key;
                                  final row = entry.value;
                                  final isMatched = row['matched_pay_id'] != null;

                                  return Container(
                                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                                    color: isMatched ? AppColors.success.withValues(alpha: 0.05) : (idx.isEven ? Colors.white : AppColors.surface),
                                    child: Row(
                                      children: [
                                        SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 2, child: Text(row['date']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 2, child: Text(row['reference']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(flex: 2, child: Text('Rs.${(row['amount'] as num?)?.toStringAsFixed(2) ?? '0'}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                        Expanded(
                                          flex: 2,
                                          child: isMatched
                                              ? Builder(builder: (_) {
                                                  final payIds = row['matched_pay_ids'] as List<int>? ?? [row['matched_pay_id'] as int];
                                                  final payNos = payIds.map((id) {
                                                    final p = _pendingPayments.firstWhere((p) => p['pay_id'] == id, orElse: () => {});
                                                    return p.isNotEmpty ? p['paynumber']?.toString() ?? '$id' : '$id';
                                                  }).join(', ');
                                                  return Row(
                                                    children: [
                                                      AppIcon('link-1', size: 14, color: AppColors.success),
                                                      SizedBox(width: 4.w),
                                                      Flexible(child: Text(payNos, style: TextStyle(fontSize: 12.sp, color: AppColors.success, fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis)),
                                                    ],
                                                  );
                                                })
                                              : Text('No match', style: TextStyle(fontSize: 12.sp, color: AppColors.textLight)),
                                        ),
                                        Expanded(
                                          flex: 1,
                                          child: isMatched
                                              ? Text(row['match_type']?.toString() ?? '', style: TextStyle(fontSize: 11.sp, color: AppColors.accent, fontWeight: FontWeight.w500))
                                              : const SizedBox.shrink(),
                                        ),
                                      ],
                                    ),
                                  );
                                }),
                              ],
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
        ),
      ),
    );
  }

  // ── Tab 3: Reconciled Payments ──
  Widget _buildReconciledTab() {
    final filteredReconciled = _filteredPayments(_reconciledPayments);
    return Padding(
      padding: EdgeInsets.zero,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  AppIcon.linear('tick-square', size: 18, color: AppColors.accent),
                  SizedBox(width: 8.w),
                  Text('Reconciled Payments', style: TextStyle(fontSize: 14.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
                  SizedBox(width: 8.w),
                  Text('${filteredReconciled.length} records', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: filteredReconciled.isEmpty
            ? Center(child: Text('No reconciled payments yet', style: TextStyle(color: AppColors.textSecondary)))
            : Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                    color: AppColors.tableHeadBg,
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('#', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('PAY NO', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 3, child: Text('STUDENT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('METHOD', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('RECONCILED BY', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('RECONCILED DATE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                        Expanded(flex: 2, child: Text('BANK REF', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary))),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          ...filteredReconciled.asMap().entries.map((entry) {
                            final idx = entry.key;
                            final p = entry.value;
                            return Container(
                              padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                              color: idx.isEven ? Colors.white : AppColors.surface,
                              child: Row(
                                children: [
                                  SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text(p['paynumber']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 3, child: Text(p['student_display']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text('Rs.${(p['transtotalamount'] as num?)?.toStringAsFixed(2) ?? '0'}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text(_methodLabel(p['paymethod']?.toString()), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text(p['reconciled_by']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text(_formatDate(p['reconciled_date']?.toString()), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                  Expanded(flex: 2, child: Text(p['bank_reference']?.toString() ?? '-', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary))),
                                ],
                              ),
                            );
                          }),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null || dateStr.isEmpty) return '-';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _normalizeReference(String value) {
    return value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();
  }

  List<Map<String, dynamic>> _filteredPayments(List<Map<String, dynamic>> payments) {
    if (_methodFilter == 'All') return payments;
    return payments.where((payment) => _methodCategory(payment['paymethod']?.toString()) == _methodFilter).toList();
  }

  String _methodCategory(String? rawMethod) {
    final method = (rawMethod ?? '').toLowerCase().trim();
    if (method == 'cash') return 'Cash';
    if (method == 'razorpay') return 'Razorpay';
    return 'Bank';
  }

  String _methodLabel(String? rawMethod) {
    final method = (rawMethod ?? '').toLowerCase().trim();
    switch (method) {
      case 'cash':
        return 'Cash';
      case 'razorpay':
        return 'Razorpay';
      case 'qr_upi':
        return 'Bank';
      case 'cheque':
        return 'Bank';
      case 'online':
        return 'Bank';
      default:
        return method.isEmpty ? '-' : _methodCategory(method);
    }
  }
}
