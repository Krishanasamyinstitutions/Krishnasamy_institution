import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../widgets/receipt_widget.dart';

/// Shared A5 receipt PDF builder. Lives outside any screen so multiple call
/// sites (Daily Collection, Student Fee Collection success dialog, Failed
/// Transactions) can produce identical receipts without duplicating ~350 lines
/// of pw.Widget code each.
Future<pw.Document> buildReceiptPdf(ReceiptData data) async {
  final font = await PdfGoogleFonts.montserratRegular();
  final fontMedium = await PdfGoogleFonts.montserratMedium();
  final fontSemiBold = await PdfGoogleFonts.montserratSemiBold();
  final fontItalic = await PdfGoogleFonts.montserratItalic();
  final fontPtSerif = await PdfGoogleFonts.pTSerifRegular();

  const primaryBlue = PdfColor.fromInt(0xFF6C8EEF);
  const darkBlue = PdfColor.fromInt(0xFF4A6CD4);
  const textDark = PdfColor.fromInt(0xFF2a2a2a);
  const textMediumC = PdfColor.fromInt(0xFF4c4c4c);
  const headerBg = PdfColor.fromInt(0xFFE9EEFF);
  const borderColor = PdfColor.fromInt(0xFFd9d9d9);
  const paidGreen = PdfColor.fromInt(0xFF34c759);
  const dividerColor = PdfColor.fromInt(0xFFACBEDD);

  final sSemiBold = pw.TextStyle(font: fontSemiBold, fontSize: 10, color: textDark);
  final sMedium = pw.TextStyle(font: fontMedium, fontSize: 10, color: textMediumC);
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

  pw.ImageProvider? logoImage;
  if (data.schoolLogoUrl != null) {
    try { logoImage = await networkImage(data.schoolLogoUrl!); } catch (_) {}
  }

  String formatAmount(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toString().replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
    }
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+\.)'), (m) => '${m[1]},');
  }

  const int maxItemsPerPage = 8;
  final totalItems = data.feeDetails.length;
  final totalPages = (totalItems / maxItemsPerPage).ceil().clamp(1, 100);

  final pdf = pw.Document();

  for (int page = 0; page < totalPages; page++) {
    final startIdx = page * maxItemsPerPage;
    final endIdx = (startIdx + maxItemsPerPage).clamp(0, totalItems);
    final pageItems = data.feeDetails.sublist(startIdx, endIdx);
    final isFirstPage = page == 0;
    final isLastPage = page == totalPages - 1;

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(40),
        theme: pw.ThemeData.withFont(base: font, bold: fontSemiBold, italic: fontItalic),
        build: (pw.Context ctx) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (logoImage != null)
                          pw.SizedBox(width: 64, height: 64, child: pw.Image(logoImage, fit: pw.BoxFit.cover)),
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
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(data.reconStatus == 'P' ? 'Acknowledgement' : 'Receipt', style: pw.TextStyle(font: fontSemiBold, fontSize: 32, color: primaryBlue)),
                      pw.SizedBox(height: 12),
                      labelValue('Receipt No:', data.receiptNo),
                      pw.SizedBox(height: 6),
                      labelValue('Date:', data.date),
                      if (totalPages > 1) ...[
                        pw.SizedBox(height: 6),
                        pw.Text('Page ${page + 1} of $totalPages', style: pw.TextStyle(font: fontMedium, fontSize: 9, color: textMediumC)),
                      ],
                    ],
                  ),
                ],
              ),
              pw.SizedBox(height: 12),
              pw.Container(height: 1, color: dividerColor),
              pw.SizedBox(height: 12),
              if (isFirstPage) ...[
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
                              pw.Expanded(child: pw.Text(
                                (data.address.trim().isNotEmpty && data.address.trim() != '-' && data.address.trim().toLowerCase() != 'null') ? data.address : 'NA',
                                style: sMedium,
                              )),
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
              ],
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
                          for (var i = 0; i < pageItems.length; i++)
                            pw.TableRow(
                              children: [
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  alignment: pw.Alignment.topCenter,
                                  child: pw.Text('${startIdx + i + 1}.', style: sMediumDark),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  alignment: pw.Alignment.topCenter,
                                  child: pw.Text(pageItems[i].term, style: sMediumDark),
                                ),
                                pw.Container(
                                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                  child: pw.Column(
                                    children: [
                                      for (final fee in pageItems[i].fees)
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
                                      for (final fee in pageItems[i].fees)
                                        pw.Padding(
                                          padding: const pw.EdgeInsets.symmetric(vertical: 2),
                                          child: pw.Text('₹${formatAmount(fee.amount)}', style: sMediumDark, textAlign: pw.TextAlign.right),
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                      if (isLastPage)
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
                                      child: pw.Text('Total', style: pw.TextStyle(font: fontSemiBold, fontSize: 10, color: PdfColors.white), textAlign: pw.TextAlign.right),
                                    ),
                                    pw.SizedBox(
                                      width: 119,
                                      child: pw.Text('₹${formatAmount(data.total)}', style: pw.TextStyle(font: fontSemiBold, fontSize: 10, color: PdfColors.white), textAlign: pw.TextAlign.right),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                  if (data.reconStatus == 'P')
                    pw.Positioned(
                      left: 90, top: 40,
                      child: pw.Opacity(
                        opacity: 0.55,
                        child: pw.Transform.rotateBox(
                          angle: -0.40,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                            decoration: pw.BoxDecoration(
                              color: const PdfColor.fromInt(0x66ffe7b5),
                              borderRadius: pw.BorderRadius.circular(10.r),
                              border: pw.Border.all(color: const PdfColor.fromInt(0xffe09100), width: 2.5),
                            ),
                            child: pw.Text(
                              'SUBJECT TO\nREALIZATION',
                              style: pw.TextStyle(font: fontSemiBold, fontSize: 16, color: const PdfColor.fromInt(0xffb86b00)),
                              textAlign: pw.TextAlign.center,
                            ),
                          ),
                        ),
                      ),
                    )
                  else if (data.status == 'paid')
                    pw.Positioned(
                      left: 120, top: 40,
                      child: pw.Opacity(
                        opacity: 0.55,
                        child: pw.Transform.rotateBox(
                          angle: -0.40,
                          child: pw.Container(
                            padding: const pw.EdgeInsets.symmetric(horizontal: 18, vertical: 5),
                            decoration: pw.BoxDecoration(
                              color: const PdfColor.fromInt(0x66c2eecd),
                              borderRadius: pw.BorderRadius.circular(10.r),
                              border: pw.Border.all(color: paidGreen, width: 2.5),
                            ),
                            child: pw.Text('PAID', style: pw.TextStyle(font: fontSemiBold, fontSize: 20, color: paidGreen)),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              if (isLastPage) ...[
                pw.SizedBox(height: 20),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    labelValue('Receipt Method:', data.paymentMethod.toLowerCase() == 'razorpay' ? 'Online' : data.paymentMethod),
                    pw.SizedBox(height: 6),
                    labelValue('Status:', data.status == 'paid' ? 'Paid' : data.status == 'failed' ? 'Failed' : data.status),
                    if (ReceiptWidget.isOnlineMethod(data.paymentMethod) &&
                        ReceiptWidget.formatReference(data.paymentReference).isNotEmpty) ...[
                      pw.SizedBox(height: 6),
                      labelValue('Reference:', ReceiptWidget.formatReference(data.paymentReference)),
                    ],
                  ],
                ),
                pw.Spacer(),
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
                      style: pw.TextStyle(font: fontMedium, fontSize: 10, color: textMediumC),
                      textAlign: pw.TextAlign.center,
                    ),
                  ),
              ] else ...[
                pw.Spacer(),
                pw.Center(
                  child: pw.Text('Continued on next page...', style: pw.TextStyle(font: fontItalic, fontSize: 10, color: textMediumC)),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
  return pdf;
}
