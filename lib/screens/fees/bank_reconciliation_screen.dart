import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:csv/csv.dart';
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
      final pending = await SupabaseService.fromSchema('payment')
          .select('pay_id, paynumber, transtotalamount, paydate, paymethod, payreference, stu_id, createdby, recon_status')
          .eq('ins_id', insId)
          .eq('paystatus', 'C')
          .eq('recon_status', 'P')
          .eq('activestatus', 1)
          .order('paydate', ascending: false);

      final reconciled = await SupabaseService.fromSchema('payment')
          .select('pay_id, paynumber, transtotalamount, paydate, paymethod, payreference, stu_id, createdby, recon_status, reconciled_by, reconciled_date, bank_reference')
          .eq('ins_id', insId)
          .eq('paystatus', 'C')
          .eq('recon_status', 'R')
          .eq('activestatus', 1)
          .order('reconciled_date', ascending: false)
          .limit(100);

      // Fetch student names for display
      final allPayments = [...pending, ...reconciled];
      final stuIds = allPayments.map((p) => p['stu_id']).toSet().toList();
      Map<int, String> stuNames = {};
      if (stuIds.isNotEmpty) {
        try {
          final students = await SupabaseService.fromSchema('students')
              .select('stu_id, stuname, stuadmno')
              .inFilter('stu_id', stuIds);
          for (final s in students) {
            stuNames[s['stu_id'] as int] = '${s['stuname']} (${s['stuadmno']})';
          }
        } catch (_) {}
      }

      // Attach student names
      for (final p in pending) {
        p['student_display'] = stuNames[p['stu_id']] ?? 'Student #${p['stu_id']}';
      }
      for (final p in reconciled) {
        p['student_display'] = stuNames[p['stu_id']] ?? 'Student #${p['stu_id']}';
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

      final csv = 'Date,Reference/UTR,Amount\n'
          '31/03/2026,UTR123456789,4200.00\n'
          '31/03/2026,UTR987654321,335.00\n'
          '31/03/2026,UTR555666777,2000.00\n';

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

      // Parse CSV: expect columns like Date, Reference, Amount, Description
      final headers = rows.first.map((h) => h.toString().toLowerCase().trim()).toList();
      final dateIdx = headers.indexWhere((h) => h.contains('date'));
      final refIdx = headers.indexWhere((h) => h.contains('ref') || h.contains('transaction') || h.contains('utr'));
      final amountIdx = headers.indexWhere((h) => h.contains('amount') || h.contains('credit'));
      final descIdx = headers.indexWhere((h) => h.contains('desc') || h.contains('narration') || h.contains('particular'));

      final bankRows = <Map<String, dynamic>>[];
      for (int i = 1; i < rows.length; i++) {
        final row = rows[i];
        if (row.length < 2) continue;
        bankRows.add({
          'date': dateIdx >= 0 && dateIdx < row.length ? row[dateIdx].toString() : '',
          'reference': refIdx >= 0 && refIdx < row.length ? row[refIdx].toString() : '',
          'amount': amountIdx >= 0 && amountIdx < row.length ? double.tryParse(row[amountIdx].toString().replaceAll(',', '')) ?? 0 : 0,
          'description': descIdx >= 0 && descIdx < row.length ? row[descIdx].toString() : '',
          'matched_pay_id': null,
        });
      }

      // Auto-match by amount
      for (final bankRow in bankRows) {
        final amount = bankRow['amount'] as double;
        if (amount <= 0) continue;
        for (final payment in _pendingPayments) {
          final payAmount = (payment['transtotalamount'] as num?)?.toDouble() ?? 0;
          if ((payAmount - amount).abs() < 0.01 && bankRow['matched_pay_id'] == null) {
            bankRow['matched_pay_id'] = payment['pay_id'];
            break;
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

  Future<void> _reconcileSelected() async {
    if (_selectedForRecon.isEmpty) return;

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final userName = auth.userName ?? 'Admin';
    if (insId == null) return;

    setState(() => _isLoading = true);
    int count = 0;

    for (final payId in _selectedForRecon) {
      try {
        await SupabaseService.fromSchema('payment').update({
          'recon_status': 'R',
          'reconciled_by': userName,
          'reconciled_date': DateTime.now().toIso8601String(),
        }).eq('pay_id', payId).eq('ins_id', insId);
        count++;
      } catch (e) {
        debugPrint('Reconcile error for pay_id $payId: $e');
      }
    }

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

    for (final row in matched) {
      try {
        await SupabaseService.fromSchema('payment').update({
          'recon_status': 'R',
          'reconciled_by': userName,
          'reconciled_date': DateTime.now().toIso8601String(),
          'bank_reference': row['reference']?.toString() ?? '',
          'bank_date': row['date']?.toString(),
        }).eq('pay_id', row['matched_pay_id']).eq('ins_id', insId);
        count++;
      } catch (e) {
        debugPrint('Bank reconcile error: $e');
      }
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
      children: [
        // Tab bar
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: AppColors.border)),
          ),
          child: TabBar(
            controller: _tabController,
            labelColor: AppColors.primary,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.primary,
            tabs: [
              Tab(text: 'Pending (${_pendingPayments.length})'),
              const Tab(text: 'Bank Statement'),
              Tab(text: 'Reconciled (${_reconciledPayments.length})'),
            ],
          ),
        ),

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
    return Column(
      children: [
        // Actions bar
        Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              Text('${_selectedForRecon.length} selected', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: _selectedForRecon.isEmpty ? null : _reconcileSelected,
                icon: Icon(Icons.check_circle_rounded, size: 18.sp),
                label: Text('Approve Selected', style: TextStyle(fontSize: 13.sp)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                ),
              ),
              SizedBox(width: 8.w),
              OutlinedButton.icon(
                onPressed: _loadPayments,
                icon: Icon(Icons.refresh_rounded, size: 18.sp),
                label: Text('Refresh', style: TextStyle(fontSize: 13.sp)),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                ),
              ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: _pendingPayments.isEmpty
              ? Center(child: Text('No pending payments for reconciliation', style: TextStyle(color: AppColors.textSecondary)))
              : SingleChildScrollView(
                  child: Column(
                    children: [
                      // Header
                      Container(
                        padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                        color: AppColors.primary,
                        child: Row(
                          children: [
                            SizedBox(width: 40.w, child: Checkbox(
                              value: _selectedForRecon.length == _pendingPayments.length && _pendingPayments.isNotEmpty,
                              onChanged: (v) {
                                setState(() {
                                  if (v == true) {
                                    _selectedForRecon.addAll(_pendingPayments.map((p) => p['pay_id'] as int));
                                  } else {
                                    _selectedForRecon.clear();
                                  }
                                });
                              },
                              fillColor: WidgetStateProperty.all(Colors.white),
                              checkColor: AppColors.primary,
                            )),
                            Expanded(flex: 2, child: Text('PAY NO', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                            Expanded(flex: 3, child: Text('STUDENT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                            Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                            Expanded(flex: 2, child: Text('METHOD', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                            Expanded(flex: 2, child: Text('DATE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                            Expanded(flex: 2, child: Text('REFERENCE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                          ],
                        ),
                      ),
                      // Rows
                      ..._pendingPayments.asMap().entries.map((entry) {
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
                              Expanded(flex: 2, child: Text(p['paynumber']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent))),
                              Expanded(flex: 3, child: Text(p['student_display']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp))),
                              Expanded(flex: 2, child: Text('Rs.${(p['transtotalamount'] as num?)?.toStringAsFixed(2) ?? '0'}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600))),
                              Expanded(flex: 2, child: Text(p['paymethod']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp))),
                              Expanded(flex: 2, child: Text(_formatDate(p['paydate']?.toString()), style: TextStyle(fontSize: 13.sp))),
                              Expanded(flex: 2, child: Text(p['payreference']?.toString() ?? '-', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis)),
                            ],
                          ),
                        );
                      }),
                    ],
                  ),
                ),
        ),
      ],
    );
  }

  // ── Tab 2: Bank Statement Upload ──
  Widget _buildBankStatementTab() {
    return Column(
      children: [
        Padding(
          padding: EdgeInsets.all(16.w),
          child: Row(
            children: [
              ElevatedButton.icon(
                onPressed: _uploadBankStatement,
                icon: Icon(Icons.upload_file_rounded, size: 18.sp),
                label: Text('Upload Bank Statement (CSV)', style: TextStyle(fontSize: 13.sp)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                ),
              ),
              SizedBox(width: 12.w),
              ElevatedButton.icon(
                onPressed: _downloadSampleTemplate,
                icon: Icon(Icons.grid_on_rounded, size: 18.sp),
                label: Text('Format to Excel', style: TextStyle(fontSize: 13.sp)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.success,
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 12.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                ),
              ),
              const Spacer(),
              if (_bankStatementRows.isNotEmpty) ...[
                Text('${_bankStatementRows.where((r) => r['matched_pay_id'] != null).length} matched', style: TextStyle(fontSize: 13.sp, color: AppColors.success, fontWeight: FontWeight.w600)),
                SizedBox(width: 16.w),
                ElevatedButton.icon(
                  onPressed: _reconcileFromBankMatch,
                  icon: Icon(Icons.check_circle_rounded, size: 18.sp),
                  label: Text('Reconcile Matched', style: TextStyle(fontSize: 13.sp)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8.r)),
                  ),
                ),
              ],
            ],
          ),
        ),
        // Table header always visible
        Container(
          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
          color: AppColors.primary,
          child: Row(
            children: [
              SizedBox(width: 40.w, child: Text('S.NO', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              Expanded(flex: 2, child: Text('DATE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              Expanded(flex: 3, child: Text('REFERENCE/UTR', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
              Expanded(flex: 2, child: Text('MATCHED WITH', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
            ],
          ),
        ),
        Expanded(
          child: _bankStatementRows.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.cloud_upload_outlined, size: 48.sp, color: AppColors.textLight),
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
                        final matchedPay = isMatched
                            ? _pendingPayments.firstWhere((p) => p['pay_id'] == row['matched_pay_id'], orElse: () => {})
                            : null;

                        return Container(
                          padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                          color: isMatched ? AppColors.success.withValues(alpha: 0.05) : (idx.isEven ? Colors.white : AppColors.surface),
                          child: Row(
                            children: [
                              SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                              Expanded(flex: 2, child: Text(row['date']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp))),
                              Expanded(flex: 3, child: Text(row['reference']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp))),
                              Expanded(flex: 2, child: Text('Rs.${(row['amount'] as num?)?.toStringAsFixed(2) ?? '0'}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600))),
                              Expanded(
                                flex: 2,
                                child: isMatched
                                    ? Row(
                                        children: [
                                          Icon(Icons.link_rounded, size: 14.sp, color: AppColors.success),
                                          SizedBox(width: 4.w),
                                          Text(matchedPay?['paynumber']?.toString() ?? '?', style: TextStyle(fontSize: 12.sp, color: AppColors.success, fontWeight: FontWeight.w600)),
                                        ],
                                      )
                                    : Text('No match', style: TextStyle(fontSize: 12.sp, color: AppColors.textLight)),
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
    );
  }

  // ── Tab 3: Reconciled Payments ──
  Widget _buildReconciledTab() {
    return _reconciledPayments.isEmpty
        ? Center(child: Text('No reconciled payments yet', style: TextStyle(color: AppColors.textSecondary)))
        : SingleChildScrollView(
            padding: EdgeInsets.all(16.w),
            child: Column(
              children: [
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
                  color: AppColors.primary,
                  child: Row(
                    children: [
                      SizedBox(width: 40.w, child: Text('#', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                      Expanded(flex: 2, child: Text('PAY NO', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                      Expanded(flex: 3, child: Text('STUDENT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                      Expanded(flex: 2, child: Text('AMOUNT', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                      Expanded(flex: 2, child: Text('RECONCILED BY', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                      Expanded(flex: 2, child: Text('RECONCILED DATE', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                      Expanded(flex: 2, child: Text('BANK REF', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: Colors.white))),
                    ],
                  ),
                ),
                ..._reconciledPayments.asMap().entries.map((entry) {
                  final idx = entry.key;
                  final p = entry.value;
                  return Container(
                    padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                    color: idx.isEven ? Colors.white : AppColors.surface,
                    child: Row(
                      children: [
                        SizedBox(width: 40.w, child: Text('${idx + 1}', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary))),
                        Expanded(flex: 2, child: Text(p['paynumber']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.success))),
                        Expanded(flex: 3, child: Text(p['student_display']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp))),
                        Expanded(flex: 2, child: Text('Rs.${(p['transtotalamount'] as num?)?.toStringAsFixed(2) ?? '0'}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600))),
                        Expanded(flex: 2, child: Text(p['reconciled_by']?.toString() ?? '-', style: TextStyle(fontSize: 13.sp))),
                        Expanded(flex: 2, child: Text(_formatDate(p['reconciled_date']?.toString()), style: TextStyle(fontSize: 13.sp))),
                        Expanded(flex: 2, child: Text(p['bank_reference']?.toString() ?? '-', style: TextStyle(fontSize: 12.sp, color: AppColors.textSecondary))),
                      ],
                    ),
                  );
                }),
              ],
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
}
