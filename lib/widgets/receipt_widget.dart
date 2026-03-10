import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Data model matching the React ReceiptData interface
class ReceiptData {
  final String receiptNo;
  final String date;
  final String studentName;
  final String mobileNo;
  final String address;
  final String admissionNo;
  final String className;
  final String schoolName;
  final String schoolAddress;
  final String? schoolLogoUrl;
  final String? schoolMobile;
  final String? schoolEmail;
  final List<ReceiptTermDetail> feeDetails;
  final String paymentMethod;
  final String paymentDate;
  final String status; // 'paid' or 'pending'
  final double total;

  const ReceiptData({
    required this.receiptNo,
    required this.date,
    required this.studentName,
    required this.mobileNo,
    required this.address,
    required this.admissionNo,
    required this.className,
    required this.schoolName,
    required this.schoolAddress,
    this.schoolLogoUrl,
    this.schoolMobile,
    this.schoolEmail,
    required this.feeDetails,
    required this.paymentMethod,
    required this.paymentDate,
    required this.status,
    required this.total,
  });
}

class ReceiptTermDetail {
  final String term;
  final List<ReceiptFeeItem> fees;

  const ReceiptTermDetail({required this.term, required this.fees});
}

class ReceiptFeeItem {
  final String type;
  final double amount;

  const ReceiptFeeItem({required this.type, required this.amount});
}

/// Flutter receipt widget matching the Figma design exactly
/// Page size: 595 x 842 (A4 points)
class ReceiptWidget extends StatelessWidget {
  final ReceiptData data;

  const ReceiptWidget({super.key, required this.data});

  // Colors from Figma
  static const _primaryBlue = Color(0xFF2f5daa);
  static const _darkBlue = Color(0xFF010165);
  static const _textDark = Color(0xFF2a2a2a);
  static const _textMedium = Color(0xFF4c4c4c);
  static const _headerBg = Color(0xFFeaeff6);
  static const _borderColor = Color(0xFFd9d9d9);
  static const _paidGreen = Color(0xFF34c759);
  static const _paidGreenBg = Color(0xFFc2eecd);
  static const _dividerColor = Color(0xFFACBEDD);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 595,
      height: 842,
      color: Colors.white,
      child: Stack(
        children: [
          // Watermark (center of fee table area)
          if (data.schoolLogoUrl != null)
            Positioned(
              left: (595 - 228) / 2,
              top: 278 + (286 - 228) / 2,
              child: Opacity(
                opacity: 0.05,
                child: Image.network(
                  data.schoolLogoUrl!,
                  width: 228,
                  height: 228,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 60),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 60),
                // Header row: Logo + School info (left) | Receipt title + No/Date (right)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Left: Logo + School name + Address
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (data.schoolLogoUrl != null)
                            SizedBox(
                              width: 64,
                              height: 64,
                              child: Image.network(
                                data.schoolLogoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                              ),
                            ),
                          if (data.schoolLogoUrl != null) const SizedBox(height: 8),
                          Text(
                            data.schoolName,
                            style: GoogleFonts.montserrat(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _darkBlue,
                            ),
                          ),
                          const SizedBox(height: 6),
                          // School address
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Address:  ',
                                style: GoogleFonts.montserrat(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _textDark,
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  data.schoolAddress,
                                  maxLines: 3,
                                  style: GoogleFonts.montserrat(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color: _textMedium,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Right: Receipt title + No + Date
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Receipt',
                          style: GoogleFonts.montserrat(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            color: _primaryBlue,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _labelValue('Receipt No:', data.receiptNo),
                        const SizedBox(height: 6),
                        _labelValue('Date:', data.date),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Divider
                Container(height: 1, color: _dividerColor),
                const SizedBox(height: 12),
                // To section
                Text(
                  'To:',
                  style: GoogleFonts.montserrat(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: _textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Left: Name, Mobile, Address
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _labelValue('Name:', data.studentName),
                          const SizedBox(height: 6),
                          _labelValue('Mobile No:', data.mobileNo),
                          const SizedBox(height: 6),
                          _wrappedLabelValue('Address:', data.address),
                        ],
                      ),
                    ),
                    const SizedBox(width: 20),
                    // Right: Admission No, Class
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        _labelValue('Admission No:', data.admissionNo),
                        const SizedBox(height: 6),
                        _labelValue('Class:', data.className),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                // Fee Table
                _buildFeeTable(),
                const Spacer(),
                // Payment info
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _labelValue('Receipt Method:', data.paymentMethod),
                    const SizedBox(height: 6),
                    _labelValue('Date:', data.paymentDate),
                  ],
                ),
                const Spacer(),
                // Footer
                Center(
                  child: Text(
                    'Thank you for your payment.',
                    style: GoogleFonts.ptSerif(
                      fontSize: 14,
                      color: _textDark,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (data.schoolEmail != null || data.schoolMobile != null)
                  Center(
                    child: RichText(
                      textAlign: TextAlign.center,
                      text: TextSpan(
                        style: GoogleFonts.montserrat(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _textMedium,
                          height: 1.6,
                        ),
                        children: [
                          const TextSpan(text: 'For any further inquiries, please contact us at '),
                          if (data.schoolEmail != null)
                            TextSpan(
                              text: data.schoolEmail!,
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _textMedium,
                              ),
                            ),
                          if (data.schoolEmail != null && data.schoolMobile != null)
                            const TextSpan(text: ' or\ncall '),
                          if (data.schoolEmail == null && data.schoolMobile != null)
                            const TextSpan(text: ''),
                          if (data.schoolMobile != null)
                            TextSpan(
                              text: data.schoolMobile!,
                              style: GoogleFonts.montserrat(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _textMedium,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 40),
              ],
            ),
          ),

          // Status stamp overlay (rotated, centered on fee table)
          if (data.status == 'paid' || data.status == 'failed')
            Positioned(
              left: 0,
              right: 0,
              top: 340,
              child: Center(
                child: Opacity(
                  opacity: 0.55,
                  child: Transform.rotate(
                    angle: -30 * pi / 180,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
                      decoration: BoxDecoration(
                        color: data.status == 'paid' ? _paidGreenBg.withValues(alpha: 0.4) : const Color(0xFFFFD6D6).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: data.status == 'paid' ? _paidGreen : const Color(0xFFFF3B30),
                          width: 2.5,
                        ),
                      ),
                      child: Text(
                        data.status == 'paid' ? 'PAID' : 'FAILED',
                        style: GoogleFonts.montserrat(
                          fontSize: 22,
                          fontWeight: FontWeight.w600,
                          color: data.status == 'paid' ? _paidGreen : const Color(0xFFFF3B30),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _wrappedLabelValue(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _textDark,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            style: GoogleFonts.montserrat(
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: _textMedium,
            ),
          ),
        ),
      ],
    );
  }

  Widget _labelValue(String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.w600,
            color: _textDark,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          value,
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: _textMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildFeeTable() {
    return Stack(
      children: [
        Column(
          children: [
            // Table Header
            Container(
              decoration: BoxDecoration(
                color: _headerBg,
                border: Border.all(color: _borderColor, width: 1),
              ),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _headerCell('S.No', width: 46),
                    Container(width: 1, color: _borderColor),
                    _headerCell('Term', width: 124),
                    Container(width: 1, color: _borderColor),
                    _headerCell('Fee Type', flex: true),
                    Container(width: 1, color: _borderColor),
                    _headerCell('Amount', width: 119),
                  ],
                ),
              ),
            ),
            // Data Rows
            for (var i = 0; i < data.feeDetails.length; i++)
              _buildDataRow(i, data.feeDetails[i]),
            // Sub Total Row
            Row(
              children: [
                // Empty left area (no blue background)
                const SizedBox(width: 172),
                // Blue Sub Total area
                Expanded(
                  child: Container(
                    decoration: const BoxDecoration(
                      color: _primaryBlue,
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(4),
                        bottomRight: Radius.circular(4),
                      ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Sub Total',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 119,
                          child: Text(
                            '\u20B9${_formatAmount(data.total)}',
                            textAlign: TextAlign.right,
                            style: GoogleFonts.montserrat(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _headerCell(String text, {double? width, bool flex = false}) {
    final child = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      alignment: Alignment.center,
      child: Text(
        text,
        style: GoogleFonts.montserrat(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: _primaryBlue,
        ),
      ),
    );
    return flex ? Expanded(child: child) : SizedBox(width: width, child: child);
  }

  Widget _buildDataRow(int index, ReceiptTermDetail term) {
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: _borderColor, width: 1),
          right: BorderSide(color: _borderColor, width: 1),
          bottom: BorderSide(color: _borderColor, width: 1),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // S.No
            _dataCell('${index + 1}.', width: 46, alignTop: true),
            // Vertical divider
            Container(width: 1, color: _borderColor),
            // Term
            _dataCell(term.term, width: 124, alignTop: true),
            // Vertical divider
            Container(width: 1, color: _borderColor),
            // Fee Type column
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var fee in term.fees)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        fee.type,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.montserrat(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _textDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Vertical divider
            Container(width: 1, color: _borderColor),
            // Amount column (right-aligned)
            SizedBox(
              width: 119,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var fee in term.fees)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      child: Text(
                        '\u20B9${_formatAmount(fee.amount)}',
                        textAlign: TextAlign.right,
                        style: GoogleFonts.montserrat(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: _textDark,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dataCell(String text, {double? width, bool alignTop = false}) {
    return SizedBox(
      width: width,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        alignment: alignTop ? Alignment.topCenter : Alignment.center,
        child: Text(
          text,
          style: GoogleFonts.montserrat(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: _textDark,
          ),
        ),
      ),
    );
  }


  String _formatAmount(double amount) {
    if (amount == amount.truncateToDouble()) {
      return amount.toInt().toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
        (m) => '${m[1]},',
      );
    }
    return amount.toStringAsFixed(2).replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+\.)'),
      (m) => '${m[1]},',
    );
  }
}
