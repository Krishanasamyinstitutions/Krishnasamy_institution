import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';
import '../../models/payment_model.dart';
import '../../models/student_model.dart';
import '../../widgets/receipt_widget.dart';

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
  Map<int, StudentModel> _stuIdToStudent = {};
  String? _insName;
  String? _insLogoUrl;
  String? _insAddress;
  String? _insMobile;
  String? _insEmail;

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
        SupabaseService.getInstitutionInfo(insId),
      ]);

      final paidData = results[0] as List<Map<String, dynamic>>;
      final failedData = results[1] as List<Map<String, dynamic>>;
      final students = results[2] as List<StudentModel>;

      final stuIdToName = <int, String>{};
      final stuIdToStudent = <int, StudentModel>{};
      for (final s in students) {
        stuIdToName[s.stuId] = s.stuname;
        stuIdToStudent[s.stuId] = s;
      }

      final insInfo = results[3] as ({String? name, String? logo, String? address, String? mobile, String? email});

      setState(() {
        _paidTransactions =
            paidData.map((e) => PaymentModel.fromJson(e)).toList();
        _failedTransactions =
            failedData.map((e) => PaymentModel.fromJson(e)).toList();
        _stuIdToName = stuIdToName;
        _stuIdToStudent = stuIdToStudent;
        _insName = insInfo.name;
        _insLogoUrl = insInfo.logo;
        _insAddress = insInfo.address;
        _insMobile = insInfo.mobile;
        _insEmail = insInfo.email;
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

  Widget _buildDownloadButton(PaymentModel t) {
    return IconButton(
      icon: const Icon(Icons.download_rounded, size: 20, color: AppColors.accent),
      tooltip: 'Download Receipt',
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
      onPressed: () => _showReceiptOptions(t),
    );
  }

  Future<ReceiptData> _buildReceiptData(PaymentModel t) async {
    final stuName = _getStudentName(t);
    final student = t.stuId != null ? _stuIdToStudent[t.stuId] : null;
    final auth = context.read<AuthProvider>();
    final date = t.paydate ?? t.createdat;
    const months = ['January','February','March','April','May','June','July','August','September','October','November','December'];
    final dateStr = '${months[date.month - 1]} ${date.day}, ${date.year}';

    // Fetch fee details from feedemand table
    List<ReceiptTermDetail> feeDetails = [];
    try {
      final details = await SupabaseService.getFeeDetailsByPayId(t.payId);
      if (details.isNotEmpty) {
        // Group by term — show month name from duedate for TUITION/VAN fees
        const monthFeeTypes = ['TUITION FEES', 'TUITION FEE', 'VAN FEES', 'VAN FEE'];
        final termMap = <String, List<ReceiptFeeItem>>{};
        for (final d in details) {
          String term = d['demfeeterm']?.toString() ?? '-';
          final feeType = d['demfeetype']?.toString() ?? d['feegroupname']?.toString() ?? 'Fee';
          final amount = (d['feeamount'] as num?)?.toDouble() ?? 0.0;
          if (monthFeeTypes.contains(feeType.toUpperCase())) {
            final duedate = d['duedate'];
            if (duedate != null) {
              try {
                final dt = DateTime.parse(duedate.toString());
                term = months[dt.month - 1].toUpperCase();
              } catch (_) {}
            }
          }
          termMap.putIfAbsent(term, () => []);
          termMap[term]!.add(ReceiptFeeItem(type: feeType, amount: amount));
        }
        feeDetails = termMap.entries
            .map((e) => ReceiptTermDetail(term: e.key, fees: e.value))
            .toList();
      }
    } catch (e) {
      debugPrint('Error fetching fee details: $e');
    }

    // Fallback if no fee details found
    if (feeDetails.isEmpty) {
      feeDetails = [
        ReceiptTermDetail(
          term: t.yrlabel ?? '-',
          fees: [ReceiptFeeItem(type: 'Payment', amount: t.transtotalamount)],
        ),
      ];
    }

    return ReceiptData(
      receiptNo: t.paynumber ?? '${t.payId}',
      date: dateStr,
      studentName: stuName,
      mobileNo: student?.stumobile ?? '-',
      address: student?.stuaddress ?? '-',
      admissionNo: student?.stuadmno ?? '-',
      className: student?.stuclass ?? '-',
      schoolName: _insName ?? auth.inscode ?? 'Institution',
      schoolAddress: _insAddress ?? '-',
      schoolLogoUrl: _insLogoUrl,
      schoolMobile: _insMobile,
      schoolEmail: _insEmail,
      feeDetails: feeDetails,
      paymentMethod: t.paymethod ?? '-',
      paymentDate: dateStr,
      status: t.isSuccess ? 'paid' : (t.paystatus == 'F' ? 'failed' : 'pending'),
      total: t.transtotalamount,
    );
  }

  void _showReceiptOptions(PaymentModel t) async {
    final receiptData = await _buildReceiptData(t);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        child: SizedBox(
          width: 620,
          height: 920,
          child: Column(
            children: [
              // Action bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _downloadReceiptAsPdf(t);
                      },
                      icon: const Icon(Icons.download_rounded, size: 18),
                      label: const Text('Download'),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _printReceipt(t);
                      },
                      icon: const Icon(Icons.print_rounded, size: 18),
                      label: const Text('Print'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        elevation: 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Receipt preview
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Center(
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: ReceiptWidget(data: receiptData),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<pw.Document> _buildReceiptPdf(PaymentModel t) async {
    final data = await _buildReceiptData(t);

    final font = await PdfGoogleFonts.montserratRegular();
    final fontMedium = await PdfGoogleFonts.montserratMedium();
    final fontSemiBold = await PdfGoogleFonts.montserratSemiBold();
    final fontItalic = await PdfGoogleFonts.montserratItalic();
    final fontPtSerif = await PdfGoogleFonts.pTSerifRegular();

    const primaryBlue = PdfColor.fromInt(0xFF2f5daa);
    const darkBlue = PdfColor.fromInt(0xFF010165);
    const textDark = PdfColor.fromInt(0xFF2a2a2a);
    const textMedium = PdfColor.fromInt(0xFF4c4c4c);
    const headerBg = PdfColor.fromInt(0xFFeaeff6);
    const borderColor = PdfColor.fromInt(0xFFd9d9d9);
    const paidGreen = PdfColor.fromInt(0xFF34c759);
    const dividerColor = PdfColor.fromInt(0xFFACBEDD);

    final sSemiBold = pw.TextStyle(font: fontSemiBold, fontSize: 10, color: textDark);
    final sMedium = pw.TextStyle(font: fontMedium, fontSize: 10, color: textMedium);
    final sMediumDark = pw.TextStyle(font: fontMedium, fontSize: 10, color: textDark);

    pw.Widget labelValue(String label, String value) {
      return pw.Row(
        mainAxisSize: pw.MainAxisSize.min,
        children: [
          pw.Text(label, style: sSemiBold),
          pw.SizedBox(width: 6),
          pw.Text(value, style: sMedium),
        ],
      );
    }

    pw.Widget tableCell(String text, pw.TextStyle style, {pw.Alignment alignment = pw.Alignment.center}) {
      return pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: alignment,
        child: pw.Text(text, style: style),
      );
    }

    // Load logo image if available
    pw.ImageProvider? logoImage;
    if (data.schoolLogoUrl != null) {
      try {
        logoImage = await networkImage(data.schoolLogoUrl!);
      } catch (_) {}
    }

    final pdf = pw.Document();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(60),
        theme: pw.ThemeData.withFont(base: font, bold: fontSemiBold, italic: fontItalic),
        build: (pw.Context ctx) {
          String formatAmount(double amount) {
            if (amount == amount.truncateToDouble()) {
              return amount.toInt().toString().replaceAllMapped(
                RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
            }
            return amount.toStringAsFixed(2).replaceAllMapped(
              RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},');
          }

          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              // Header: Logo + School info (left) | Receipt title + No/Date (right)
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  // Left: Logo + School name + Address
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImage != null)
                          pw.SizedBox(width: 64, height: 64,
                            child: pw.Image(logoImage, fit: pw.BoxFit.cover)),
                        if (logoImage != null) pw.SizedBox(height: 8),
                        pw.Text(data.schoolName, style: pw.TextStyle(font: fontSemiBold, fontSize: 14, color: darkBlue)),
                        pw.SizedBox(height: 6),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Address:  ', style: sSemiBold),
                            pw.Expanded(child: pw.Text(data.schoolAddress, style: sMedium, maxLines: 3)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  // Right: Receipt title + No + Date
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Receipt', style: pw.TextStyle(font: fontSemiBold, fontSize: 32, color: primaryBlue)),
                      pw.SizedBox(height: 12),
                      labelValue('Receipt No:', data.receiptNo),
                      pw.SizedBox(height: 6),
                      labelValue('Date:', data.date),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Container(height: 1, color: dividerColor),
              pw.SizedBox(height: 12),
              // To section
              pw.Text('To:', style: pw.TextStyle(font: fontSemiBold, fontSize: 12, color: textDark)),
              pw.SizedBox(height: 8),
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        labelValue('Name:', data.studentName),
                        pw.SizedBox(height: 6),
                        labelValue('Mobile No:', data.mobileNo),
                        pw.SizedBox(height: 6),
                        pw.Row(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text('Address:', style: sSemiBold),
                            pw.SizedBox(width: 6),
                            pw.Expanded(child: pw.Text(data.address, style: sMedium)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  pw.SizedBox(width: 20),
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      labelValue('Admission No:', data.admissionNo),
                      pw.SizedBox(height: 6),
                      labelValue('Class:', data.className),
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 20),
              // Fee Table with stamp overlay
              pw.Stack(
                children: [
                  pw.Column(
                    children: [
                      pw.Table(
                        border: pw.TableBorder.all(color: borderColor, width: 0.5),
                        columnWidths: {
                          0: const pw.FixedColumnWidth(46),
                          1: const pw.FixedColumnWidth(125),
                          2: const pw.FlexColumnWidth(),
                          3: const pw.FixedColumnWidth(120),
                        },
                        children: [
                          pw.TableRow(
                            decoration: const pw.BoxDecoration(color: headerBg),
                            children: [
                              tableCell('S.No', sSemiBold.copyWith(color: primaryBlue)),
                              tableCell('Term', sSemiBold.copyWith(color: primaryBlue)),
                              tableCell('Fee Type', sSemiBold.copyWith(color: primaryBlue)),
                              tableCell('Amount', sSemiBold.copyWith(color: primaryBlue)),
                            ],
                          ),
                          for (var i = 0; i < data.feeDetails.length; i++)
                            pw.TableRow(
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  alignment: pw.Alignment.topCenter,
                                  child: pw.Text('${i + 1}.', style: sMediumDark),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  alignment: pw.Alignment.topCenter,
                                  child: pw.Text(data.feeDetails[i].term, style: sMediumDark),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: pw.Column(
                                    children: [
                                      for (final fee in data.feeDetails[i].fees)
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                          child: pw.Text(fee.type, style: sMediumDark, textAlign: pw.TextAlign.center),
                                        ),
                                    ],
                                  ),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: pw.Column(
                                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                                    children: [
                                      for (final fee in data.feeDetails[i].fees)
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                          child: pw.Text('\u20B9${formatAmount(fee.amount)}', style: sMediumDark, textAlign: pw.TextAlign.right),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      // Sub Total row
                      pw.Row(
                        children: [
                          pw.SizedBox(width: 172),
                          pw.Expanded(
                            child: pw.Container(
                              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                              decoration: const pw.BoxDecoration(color: primaryBlue),
                              child: pw.Row(
                                children: [
                                  pw.Expanded(
                                    child: pw.Text('Sub Total', style: pw.TextStyle(font: fontSemiBold, fontSize: 10, color: PdfColors.white), textAlign: pw.TextAlign.right),
                                  ),
                                  pw.SizedBox(
                                    width: 119,
                                    child: pw.Text('\u20B9${formatAmount(data.total)}', style: pw.TextStyle(font: fontSemiBold, fontSize: 10, color: PdfColors.white), textAlign: pw.TextAlign.right),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  // Status stamp overlay – between Term and Fee Type columns
                  if (data.status == 'paid' || data.status == 'failed')
                    pw.Positioned(
                      left: 120, top: 40,
                      child: pw.Opacity(
                        opacity: 0.55,
                        child: pw.Transform.rotateBox(
                          angle: -0.40,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                            decoration: pw.BoxDecoration(
                              color: PdfColor.fromInt(data.status == 'paid' ? 0x66c2eecd : 0x66FFD6D6),
                              borderRadius: pw.BorderRadius.circular(10),
                              border: pw.Border.all(
                                color: data.status == 'paid' ? paidGreen : const PdfColor.fromInt(0xFFFF3B30),
                                width: 2.5,
                              ),
                            ),
                            child: pw.Text(
                              data.status == 'paid' ? 'PAID' : 'FAILED',
                              style: pw.TextStyle(
                                font: fontSemiBold,
                                fontSize: 20,
                                color: data.status == 'paid' ? paidGreen : const PdfColor.fromInt(0xFFFF3B30),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              pw.SizedBox(height: 20),
              // Payment info
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  labelValue('Receipt Method:', data.paymentMethod),
                  pw.SizedBox(height: 6),
                  labelValue('Date:', data.paymentDate),
                ],
              ),
              pw.Spacer(),
              // Footer
              pw.Center(
                child: pw.Text('Thank you for your payment.', style: pw.TextStyle(font: fontPtSerif, fontSize: 14, color: textDark)),
              ),
              pw.SizedBox(height: 8),
              if (data.schoolEmail != null || data.schoolMobile != null)
                pw.Center(
                  child: pw.Text(
                    'For any further inquiries, please contact us at '
                    '${data.schoolEmail ?? ''}'
                    '${data.schoolEmail != null && data.schoolMobile != null ? ' or\ncall ' : ''}'
                    '${data.schoolMobile ?? ''}',
                    style: pw.TextStyle(font: fontMedium, fontSize: 10, color: textMedium),
                    textAlign: pw.TextAlign.center,
                  ),
                ),
            ],
          );
        },
      ),
    );
    return pdf;
  }

  Future<void> _downloadReceiptAsPdf(PaymentModel t) async {
    try {
      final pdf = await _buildReceiptPdf(t);
      final bytes = await pdf.save();
      final fileName = 'Receipt_${(t.paynumber ?? '${t.payId}').replaceAll('/', '_')}.pdf';

      final result = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Receipt',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        final file = File(result);
        await file.writeAsBytes(bytes);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Receipt saved to $result'), backgroundColor: AppColors.accent),
          );
        }
      }
    } catch (e) {
      debugPrint('Error downloading receipt: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
  }

  Future<void> _printReceipt(PaymentModel t) async {
    try {
      final pdf = await _buildReceiptPdf(t);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
        name: 'Receipt_${(t.paynumber ?? '${t.payId}').replaceAll('/', '_')}',
      );
    } catch (e) {
      debugPrint('Error printing receipt: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: AppColors.error),
        );
      }
    }
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

        // Tab buttons with colored active states
        ListenableBuilder(
          listenable: _tabController,
          builder: (context, _) {
            final selected = _tabController.index;
            final tabColors = [AppColors.accent, Colors.green.shade600, Colors.red.shade600];
            final tabBgColors = [AppColors.accent.withValues(alpha: 0.1), Colors.green.shade50, Colors.red.shade50];
            final tabIcons = [Icons.list_alt_rounded, Icons.check_circle_rounded, Icons.error_rounded];
            final tabLabels = ['All', 'Paid', 'Failed'];
            final tabCounts = [
              _paidTransactions.length + _failedTransactions.length,
              _paidTransactions.length,
              _failedTransactions.length,
            ];

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              padding: const EdgeInsets.all(4),
              child: Row(
              children: List.generate(3, (i) {
                final isActive = selected == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => _tabController.animateTo(i),
                    child: Container(
                      margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive ? tabColors[i] : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(tabIcons[i], size: 16, color: isActive ? Colors.white : tabColors[i]),
                          const SizedBox(width: 8),
                          Text(tabLabels[i], style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isActive ? Colors.white : AppColors.textPrimary)),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: isActive ? Colors.white.withValues(alpha: 0.25) : tabBgColors[i],
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${tabCounts[i]}',
                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isActive ? Colors.white : tabColors[i]),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
            );
          },
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
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('Pay No')),
                DataColumn(label: Text('Student')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Currency')),
                DataColumn(label: Text('Method')),
                DataColumn(label: Text('Reference')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Download Receipt')),
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
                    DataCell(t.isSuccess ? _buildDownloadButton(t) : const SizedBox.shrink()),
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
                DataColumn(label: Text('S No.')),
                DataColumn(label: Text('Pay No')),
                DataColumn(label: Text('Student')),
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Currency')),
                DataColumn(label: Text('Method')),
                DataColumn(label: Text('Reference')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Download Receipt')),
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
                    DataCell(t.isSuccess ? _buildDownloadButton(t) : const SizedBox.shrink()),
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
