import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
  String _searchQuery = '';
  final _searchController = TextEditingController();
  List<PaymentModel> _failedTransactions = [];
  Map<int, String> _stuIdToName = {};
  Map<int, StudentModel> _stuIdToStudent = {};
  DateTime? _filterFromDate;
  DateTime? _filterToDate;
  String? _insName;
  String? _insLogoUrl;
  String? _insAddress;
  String? _insMobile;
  String? _insEmail;


  List<PaymentModel> _filterBySearch(List<PaymentModel> list) {
    var filtered = list;
    // Date filter
    if (_filterFromDate != null || _filterToDate != null) {
      filtered = filtered.where((t) {
        final date = t.paydate ?? t.createdat;
        final dateOnly = DateTime(date.year, date.month, date.day);
        if (_filterFromDate != null && dateOnly.isBefore(_filterFromDate!)) return false;
        if (_filterToDate != null && dateOnly.isAfter(_filterToDate!)) return false;
        return true;
      }).toList();
    }
    // Search filter
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((t) {
        final name = _getStudentName(t).toLowerCase();
        final payNo = (t.paynumber ?? '${t.payId}').toLowerCase();
        final ref = (t.payreference ?? '').toLowerCase();
        final method = (t.paymethod ?? '').toLowerCase();
        return name.contains(_searchQuery) || payNo.contains(_searchQuery) || ref.contains(_searchQuery) || method.contains(_searchQuery);
      }).toList();
    }
    return filtered;
  }

  List<PaymentModel> get _allTransactions {
    final all = [..._paidTransactions, ..._failedTransactions];
    all.sort((a, b) {
      final dateA = a.paydate ?? a.createdat;
      final dateB = b.paydate ?? b.createdat;
      return dateB.compareTo(dateA);
    });
    return _filterBySearch(all);
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
        SupabaseService.getAllTransactions(insId),
        SupabaseService.getStudents(insId),
        SupabaseService.getInstitutionInfo(insId),
      ]);

      final allData = results[0] as List<Map<String, dynamic>>;
      final paidData = allData.where((t) => t['paystatus'] == 'C').toList();
      final failedData = allData.where((t) => t['paystatus'] == 'F').toList();
      final students = results[1] as List<StudentModel>;

      final stuIdToName = <int, String>{};
      final stuIdToStudent = <int, StudentModel>{};
      for (final s in students) {
        stuIdToName[s.stuId] = s.stuname;
        stuIdToStudent[s.stuId] = s;
      }

      final insInfo = results[2] as ({String? name, String? logo, String? address, String? mobile, String? email});

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
    // Use stuname from RPC if available, fallback to student map lookup
    if (t.stuname != null && t.stuname!.isNotEmpty) {
      return t.stuname!;
    }
    if (t.stuId != null && _stuIdToName.containsKey(t.stuId)) {
      return _stuIdToName[t.stuId]!;
    }
    return '-';
  }

  Widget _buildDownloadButton(PaymentModel t) {
    final isReconciled = t.reconStatus == 'R';
    if (!isReconciled) {
      return Text('Pending Approval', style: TextStyle(fontSize: 12.sp, color: AppColors.error, fontWeight: FontWeight.w600));
    }
    return TextButton.icon(
      onPressed: () => _showReceiptOptions(t),
      icon: Icon(Icons.download_rounded, size: 18.sp, color: AppColors.accent),
      label: Text('Download', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
      style: TextButton.styleFrom(
        padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
      ),
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
      reconStatus: t.reconStatus ?? 'P',
      total: t.transtotalamount,
    );
  }

  void _showReceiptOptions(PaymentModel t) async {
    final receiptData = await _buildReceiptData(t);
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
        child: SizedBox(
          width: 620,
          height: 920,
          child: Column(
            children: [
              // Action bar
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
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
                    SizedBox(width: 8.w),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.pop(ctx);
                        _printReceipt(t);
                      },
                      icon: Icon(Icons.print_rounded, size: 18.sp),
                      label: const Text('Print'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.accent,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                        elevation: 0,
                        textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: Icon(Icons.close, size: 20.sp),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Receipt preview
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(12.w),
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

    const primaryBlue = PdfColor.fromInt(0xFF6C8EEF);
    const darkBlue = PdfColor.fromInt(0xFF4A6CD4);
    const textDark = PdfColor.fromInt(0xFF2a2a2a);
    const textMedium = PdfColor.fromInt(0xFF4c4c4c);
    const headerBg = PdfColor.fromInt(0xFFE9EEFF);
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
              pw.Text('To:', style: pw.TextStyle(font: fontSemiBold, fontSize: 13, color: textDark)),
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
                      labelValue('Roll No:', data.admissionNo),
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
                              tableCell('Semester', sSemiBold.copyWith(color: primaryBlue)),
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
                              borderRadius: pw.BorderRadius.circular(10.r),
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
                  labelValue('Receipt Method:', data.paymentMethod.toLowerCase() == 'razorpay' ? 'Online' : data.paymentMethod),
                  pw.SizedBox(height: 6),
                  labelValue('Status:', data.status == 'paid' ? 'Paid' : data.status == 'failed' ? 'Failed' : data.status),
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
        // 1. Tab buttons (on top)
        ListenableBuilder(
          listenable: _tabController,
          builder: (context, _) {
            final selected = _tabController.index;
            final tabColors = [AppColors.accent, Colors.green.shade600, Colors.red.shade600];
            final tabBgColors = [AppColors.accent.withValues(alpha: 0.1), Colors.green.shade50, Colors.red.shade50];
            final tabIcons = [Icons.list_alt_rounded, Icons.check_circle_rounded, Icons.error_rounded];
            final tabLabels = ['All', 'Paid', 'Failed'];
            final filteredPaid = _applyDateFilter(_paidTransactions);
            final filteredFailed = _applyDateFilter(_failedTransactions);
            final tabCounts = [
              filteredPaid.length + filteredFailed.length,
              filteredPaid.length,
              filteredFailed.length,
            ];

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
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
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(tabIcons[i], size: 16, color: isActive ? Colors.white : tabColors[i]),
                            SizedBox(width: 8.w),
                            Text(tabLabels[i], style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: isActive ? Colors.white : AppColors.textPrimary)),
                            SizedBox(width: 8.w),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: isActive ? Colors.white.withValues(alpha: 0.25) : tabBgColors[i],
                                borderRadius: BorderRadius.circular(10.r),
                              ),
                              child: Text(
                                '${tabCounts[i]}',
                                style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: isActive ? Colors.white : tabColors[i]),
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
        SizedBox(height: 10.h),

        // 2. Summary cards
        _buildSummaryCards(),
        SizedBox(height: 10.h),

        // 3. Combined header + table card
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12.r),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              children: [
                // Date filter row
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.filter_alt_rounded, size: 16, color: AppColors.textSecondary),
                      SizedBox(width: 8.w),
                      Text('Date Range:', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                      SizedBox(width: 8.w),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _filterFromDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) setState(() => _filterFromDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                              SizedBox(width: 6.w),
                              Text(
                                _filterFromDate != null
                                    ? '${_filterFromDate!.day.toString().padLeft(2, '0')}/${_filterFromDate!.month.toString().padLeft(2, '0')}/${_filterFromDate!.year}'
                                    : 'From',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const Padding(padding: EdgeInsets.symmetric(horizontal: 6), child: Text('—', style: TextStyle(color: AppColors.textSecondary))),
                      InkWell(
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _filterToDate ?? DateTime.now(),
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2030),
                          );
                          if (picked != null) setState(() => _filterToDate = picked);
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.border),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.calendar_today, size: 14, color: AppColors.textSecondary),
                              SizedBox(width: 6.w),
                              Text(
                                _filterToDate != null
                                    ? '${_filterToDate!.day.toString().padLeft(2, '0')}/${_filterToDate!.month.toString().padLeft(2, '0')}/${_filterToDate!.year}'
                                    : 'To',
                                style: TextStyle(fontSize: 13.sp),
                              ),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      ...[
                        ('Today', () { final now = DateTime.now(); setState(() { _filterFromDate = DateTime(now.year, now.month, now.day); _filterToDate = DateTime(now.year, now.month, now.day); }); }),
                        ('7 Days', () { final now = DateTime.now(); setState(() { _filterFromDate = now.subtract(const Duration(days: 7)); _filterToDate = DateTime(now.year, now.month, now.day); }); }),
                        ('30 Days', () { final now = DateTime.now(); setState(() { _filterFromDate = now.subtract(const Duration(days: 30)); _filterToDate = DateTime(now.year, now.month, now.day); }); }),
                        ('All', () { setState(() { _filterFromDate = null; _filterToDate = null; }); }),
                      ].map((e) => Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: InkWell(
                          onTap: e.$2,
                          borderRadius: BorderRadius.circular(6.r),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(6.r),
                              border: Border.all(color: AppColors.border),
                            ),
                            child: Text(e.$1, style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w500)),
                          ),
                        ),
                      )),
                    ],
                  ),
                ),
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: AppColors.border)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long_rounded,
                          color: AppColors.primary, size: 20),
                      SizedBox(width: 8.w),
                      Text(
                        'Transactions',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 260,
                        height: 34,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (v) => setState(() => _searchQuery = v.trim().toLowerCase()),
                          decoration: InputDecoration(
                            hintText: 'Search by name, pay no, reference...',
                            hintStyle: TextStyle(fontSize: 13.sp, color: Colors.grey.shade400),
                            prefixIcon: const Icon(Icons.search_rounded, size: 18),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.close_rounded, size: 16),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                    splashRadius: 14,
                                  )
                                : null,
                            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.border)),
                            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.border)),
                            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8.r), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
                            filled: true,
                            fillColor: AppColors.surface,
                            isDense: true,
                          ),
                          style: TextStyle(fontSize: 13.sp),
                        ),
                      ),
                      SizedBox(width: 8.w),
                      TextButton.icon(
                        onPressed: _fetchData,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Refresh'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                          textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                        ),
                      ),
                    ],
                  ),
                ),
                // Table
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : TabBarView(
                          controller: _tabController,
                          children: [
                            _buildAllTransactionTable(),
                            _buildTransactionTable(_filterBySearch(_paidTransactions), isPaid: true),
                            _buildTransactionTable(_filterBySearch(_failedTransactions), isPaid: false),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  List<PaymentModel> _applyDateFilter(List<PaymentModel> list) {
    if (_filterFromDate == null && _filterToDate == null) return list;
    return list.where((t) {
      final date = t.paydate ?? t.createdat;
      final dateOnly = DateTime(date.year, date.month, date.day);
      if (_filterFromDate != null && dateOnly.isBefore(_filterFromDate!)) return false;
      if (_filterToDate != null && dateOnly.isAfter(_filterToDate!)) return false;
      return true;
    }).toList();
  }

  Widget _buildSummaryCards() {
    final filteredPaid = _applyDateFilter(_paidTransactions);
    final filteredFailed = _applyDateFilter(_failedTransactions);
    final paidTotal = filteredPaid.fold<double>(
        0, (sum, t) => sum + t.transtotalamount);
    final failedTotal = filteredFailed.fold<double>(
        0, (sum, t) => sum + t.transtotalamount);

    return Row(
      children: [
        Expanded(
          child: _buildSummaryCard(
            'Total Paid',
            '\u20B9 ${paidTotal.toStringAsFixed(2)}',
            '${filteredPaid.length} transactions',
            Colors.green,
            Icons.check_circle_outline_rounded,
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: _buildSummaryCard(
            'Total Failed',
            '\u20B9 ${failedTotal.toStringAsFixed(2)}',
            '${filteredFailed.length} transactions',
            Colors.red,
            Icons.error_outline_rounded,
          ),
        ),
        SizedBox(width: 16.w),
        Expanded(
          child: _buildSummaryCard(
            'Total Transactions',
            '${filteredPaid.length + filteredFailed.length}',
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10.r),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          SizedBox(width: 14.w),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13.sp,
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                SizedBox(height: 4.h),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 18.sp,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                SizedBox(height: 2.h),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 13.sp,
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
    final allTransactions = _allTransactions;
    if (allTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.receipt_long_rounded,
                size: 64, color: AppColors.accent.withValues(alpha: 0.5)),
            SizedBox(height: 16.h),
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

    final transactions = allTransactions;

    return SingleChildScrollView(
      child: DataTable(
        dividerThickness: 0,
        headingRowColor: WidgetStateProperty.all(const Color(0xFF6C8EEF)),
        headingTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.sp, color: Colors.white),
        dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
        columnSpacing: 20,
        horizontalMargin: 16,
        headingRowHeight: 42,
        columns: const [
          DataColumn(label: Text('S NO.')),
          DataColumn(label: Text('PAY NO')),
          DataColumn(label: Text('STUDENT')),
          DataColumn(label: Text('AMOUNT')),
          DataColumn(label: Text('CURRENCY')),
          DataColumn(label: Text('METHOD')),
          DataColumn(label: Text('REFERENCE')),
          DataColumn(label: Text('DATE')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('DOWNLOAD RECEIPT')),
        ],
        rows: List.generate(transactions.length, (i) {
          final t = transactions[i];
          final stuName = _getStudentName(t);
          final isPaid = t.isSuccess;
          final statusColor = isPaid ? Colors.green : Colors.red;
          final statusText = isPaid ? 'Paid' : 'Failed';
          final date = t.paydate ?? t.createdat;
          return DataRow(
            color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF2F6FA)),
            cells: [
              DataCell(Text('${i + 1}')),
              DataCell(Text(t.paynumber ?? '${t.payId}')),
              DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(stuName, overflow: TextOverflow.ellipsis))),
              DataCell(Text(t.transtotalamount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text(t.transcurrency)),
              DataCell(Text(t.paymethod ?? '-')),
              DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(t.payreference ?? '-', overflow: TextOverflow.ellipsis))),
              DataCell(Text('${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}')),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.shade50, borderRadius: BorderRadius.circular(8.r)),
                child: Text(statusText, style: TextStyle(color: statusColor.shade700, fontWeight: FontWeight.w600, fontSize: 13.sp)),
              )),
              DataCell(t.isSuccess ? _buildDownloadButton(t) : const SizedBox.shrink()),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildTransactionTable(List<PaymentModel> allItems,
      {required bool isPaid}) {
    if (allItems.isEmpty) {
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
            SizedBox(height: 16.h),
            Text(
              isPaid ? 'No Paid Transactions' : 'No Failed Transactions',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.textSecondary,
                  ),
            ),
            SizedBox(height: 8.h),
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

    final transactions = allItems;

    return SingleChildScrollView(
      child: DataTable(
        dividerThickness: 0,
        headingRowColor: WidgetStateProperty.all(const Color(0xFF6C8EEF)),
        headingTextStyle: TextStyle(fontWeight: FontWeight.w700, fontSize: 13.sp, color: Colors.white),
        dataTextStyle: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary),
        columnSpacing: 20,
        horizontalMargin: 16,
        headingRowHeight: 42,
        columns: const [
          DataColumn(label: Text('S NO.')),
          DataColumn(label: Text('PAY NO')),
          DataColumn(label: Text('STUDENT')),
          DataColumn(label: Text('AMOUNT')),
          DataColumn(label: Text('CURRENCY')),
          DataColumn(label: Text('METHOD')),
          DataColumn(label: Text('REFERENCE')),
          DataColumn(label: Text('DATE')),
          DataColumn(label: Text('STATUS')),
          DataColumn(label: Text('DOWNLOAD RECEIPT')),
        ],
        rows: List.generate(transactions.length, (i) {
          final t = transactions[i];
          final stuName = _getStudentName(t);
          final statusColor = isPaid ? Colors.green : Colors.red;
          final statusText = isPaid ? 'Paid' : 'Failed';
          final date = isPaid ? t.paydate : t.createdat;
          return DataRow(
            color: WidgetStateProperty.all(i.isEven ? Colors.white : const Color(0xFFF2F6FA)),
            cells: [
              DataCell(Text('${i + 1}')),
              DataCell(Text(t.paynumber ?? '${t.payId}')),
              DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 180), child: Text(stuName, overflow: TextOverflow.ellipsis))),
              DataCell(Text(t.transtotalamount.toStringAsFixed(2), style: const TextStyle(fontWeight: FontWeight.w600))),
              DataCell(Text(t.transcurrency)),
              DataCell(Text(t.paymethod ?? '-')),
              DataCell(ConstrainedBox(constraints: const BoxConstraints(maxWidth: 160), child: Text(t.payreference ?? '-', overflow: TextOverflow.ellipsis))),
              DataCell(Text(date != null ? '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}' : '-')),
              DataCell(Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: statusColor.shade50, borderRadius: BorderRadius.circular(8.r)),
                child: Text(statusText, style: TextStyle(color: statusColor.shade700, fontWeight: FontWeight.w600, fontSize: 13.sp)),
              )),
              DataCell(t.isSuccess ? _buildDownloadButton(t) : const SizedBox.shrink()),
            ],
          );
        }),
      ),
    );
  }
}
