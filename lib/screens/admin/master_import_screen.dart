import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
import '../../widgets/app_icon.dart';
import 'package:excel/excel.dart' as xl;
import '../../utils/app_theme.dart';
import '../../services/supabase_service.dart';
import 'package:provider/provider.dart';
import '../../utils/auth_provider.dart';

void _showImportResultDialog(BuildContext context, {required int imported, required int skipped, List<String> errors = const [], VoidCallback? onDone}) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => Center(
      child: Container(
        width: 420.w,
        padding: EdgeInsets.all(32.w),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10.r),
          border: Border.all(color: AppColors.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(errors.isEmpty ? 'tick-circle' : 'warning-2', size: 64.sp, color: errors.isEmpty ? AppColors.success : AppColors.error),
            SizedBox(height: 16.h),
            Text(errors.isEmpty ? 'Import Complete' : 'Import Completed with Errors', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 12.h),
            Text('$imported imported successfully, $skipped skipped', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
            if (errors.isNotEmpty) ...[
              SizedBox(height: 16.h),
              Container(
                height: 150.h,
                padding: EdgeInsets.all(12.w),
                decoration: BoxDecoration(
                  color: AppColors.error.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: ListView(
                  children: errors.map((e) => Padding(
                    padding: EdgeInsets.only(bottom: 4.h),
                    child: Text(e, style: TextStyle(fontSize: 13.sp, color: AppColors.error)),
                  )).toList(),
                ),
              ),
            ],
            SizedBox(height: 20.h),
            ElevatedButton(
              onPressed: () { Navigator.pop(ctx); onDone?.call(); },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
              ),
              child: Text('Done', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    ),
  );
}

class MasterImportScreen extends StatefulWidget {
  const MasterImportScreen({super.key});
  @override
  State<MasterImportScreen> createState() => _MasterImportScreenState();
}

class _MasterImportScreenState extends State<MasterImportScreen> with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 8, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Tabs (pill style, same as Reports)
        ListenableBuilder(
          listenable: _tabCtrl,
          builder: (context, _) {
            final selected = _tabCtrl.index;
            final tabLabels = ['Course', 'Class', 'Fee Group', 'Fee Type', 'Concession', 'Class Fee Demand', 'Admission Type', 'Quota'];
            final tabIcons = ['teacher', 'book-1', 'category-2', 'receipt-1', 'receipt-discount', 'note-2', 'user-tick', 'ticket'];
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (var i = 0; i < tabLabels.length; i++) ...[
                      GestureDetector(
                        onTap: () => _tabCtrl.animateTo(i),
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
        // Content (white card)
        Expanded(
          child: Container(
            decoration: AppCard.decoration(),
            clipBehavior: Clip.antiAlias,
            margin: const EdgeInsets.only(top: 8),
            child: TabBarView(
              controller: _tabCtrl,
              children: const [
                _CourseTab(),
                _ClassTab(),
                _FeeGroupTab(),
                _FeeTypeTab(),
                _ConcessionTab(),
                _ClassFeeDemandTab(),
                _AdmissionTypeTab(),
                _QuotaTab(),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════
// STAGING TABLE IMPORT HELPER
// ═══════════════════════════════════════════════

Future<Map<String, int>> _stagingImport({
  required int insId,
  required String impType,
  required List<List<dynamic>> rows,
  required int colCount,
}) async {
  // 1. Clear old pending rows
  await SupabaseService.client.from('master_import').delete().eq('ins_id', insId).eq('imp_type', impType).eq('status', 'PENDING');

  // 2. Bulk insert into staging table in batches of 500
  for (int i = 0; i < rows.length; i += 500) {
    final batch = rows.sublist(i, (i + 500).clamp(0, rows.length));
    final records = batch.map((row) {
      final map = <String, dynamic>{
        'imp_type': impType,
        'ins_id': insId,
      };
      for (int c = 0; c < colCount; c++) {
        final val = c < row.length ? row[c].toString().trim() : '';
        map['col${c + 1}'] = val.isEmpty ? null : val;
      }
      return map;
    }).toList();
    await SupabaseService.client.from('master_import').insert(records);
  }

  // 3. Call processing function
  final result = await SupabaseService.client.rpc('process_master_import', params: {'p_ins_id': insId});
  final list = result is List ? result : [result];
  final r = list.isNotEmpty ? list.first : {};
  return {
    'total': r['total'] ?? 0,
    'imported': r['imported'] ?? 0,
    'skipped': r['skipped'] ?? 0,
  };
}

Future<List<String>> _getImportErrors(int insId, String impType) async {
  final errors = await SupabaseService.client
      .from('master_import')
      .select('imp_id, error_msg')
      .eq('ins_id', insId)
      .eq('imp_type', impType)
      .eq('status', 'ERROR')
      .order('imp_id')
      .limit(20);
  return (errors as List).map((e) => 'Row ${e['imp_id']}: ${_friendlyError(e['error_msg']?.toString() ?? 'Unknown error')}').toList();
}

String _friendlyError(String msg) {
  final m = msg.toLowerCase();
  if (m.contains('duplicate key') || m.contains('unique constraint')) return 'Duplicate record found';
  if (m.contains('not-null') || m.contains('null value')) {
    final match = RegExp(r'column "(\w+)"').firstMatch(msg);
    return '${match?.group(1) ?? 'Field'} is required';
  }
  if (m.contains('foreign key') || m.contains('fkey')) return 'Invalid reference - check linked values';
  if (m.contains('check constraint')) return 'Invalid value format';
  if (m.contains('value too long')) return 'Value too long for the field';
  if (m.contains('invalid input syntax')) return 'Invalid data format';
  if (m.contains('permission denied')) return 'Permission denied';
  return msg.length > 80 ? '${msg.substring(0, 80)}...' : msg;
}

// ═══════════════════════════════════════════════
// GENERIC HELPERS
// ═══════════════════════════════════════════════

List<List<dynamic>> _parseExcel(String path) {
  final bytes = File(path).readAsBytesSync();
  final excel = xl.Excel.decodeBytes(bytes);
  final sheet = excel.tables[excel.tables.keys.first]!;
  return sheet.rows.map((r) => r.map((c) => c?.value?.toString().trim() ?? '').toList()).toList();
}

Future<void> _exportSampleData(String sheetName, List<String> headers, List<List<String>> sampleRows) async {
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Sample Data',
    fileName: '${sheetName.toLowerCase().replaceAll(' ', '_')}_sample.xlsx',
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (savePath == null) return;
  final workbook = xl.Excel.createExcel();
  final sheet = workbook[sheetName];
  final headerStyle = xl.CellStyle(
    bold: true,
    backgroundColorHex: xl.ExcelColor.fromHexString('#1B2A4A'),
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
  );
  for (int i = 0; i < headers.length; i++) {
    final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
    cell.value = xl.TextCellValue(headers[i]);
    cell.cellStyle = headerStyle;
    sheet.setColumnWidth(i, 20);
  }
  for (int r = 0; r < sampleRows.length; r++) {
    for (int c = 0; c < sampleRows[r].length; c++) {
      final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: c, rowIndex: r + 1));
      cell.value = xl.TextCellValue(sampleRows[r][c]);
    }
  }
  workbook.delete('Sheet1');
  final bytes = workbook.encode();
  if (bytes != null) File(savePath).writeAsBytesSync(bytes);
}

Future<void> _exportTemplate(String sheetName, List<String> headers) async {
  final savePath = await FilePicker.platform.saveFile(
    dialogTitle: 'Save Template',
    fileName: '${sheetName.toLowerCase().replaceAll(' ', '_')}_template.xlsx',
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
  );
  if (savePath == null) return;
  final workbook = xl.Excel.createExcel();
  final sheet = workbook[sheetName];
  final headerStyle = xl.CellStyle(
    bold: true,
    backgroundColorHex: xl.ExcelColor.fromHexString('#1B2A4A'),
    fontColorHex: xl.ExcelColor.fromHexString('#FFFFFF'),
  );
  for (int i = 0; i < headers.length; i++) {
    final cell = sheet.cell(xl.CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
    cell.value = xl.TextCellValue(headers[i]);
    cell.cellStyle = headerStyle;
    sheet.setColumnWidth(i, 18);
  }
  workbook.delete('Sheet1');
  final bytes = workbook.encode();
  if (bytes != null) File(savePath).writeAsBytesSync(bytes);
}

Widget _gridHeaderCell(String text, {double? width, int flex = 1, bool center = false}) {
  final child = Container(
    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 12.h),
    alignment: center ? Alignment.center : Alignment.centerLeft,
    child: Text(text.toUpperCase(), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.textPrimary, letterSpacing: 0.3.w)),
  );
  return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
}

Widget _gridHeaderDivider() {
  return Container(width: 1, height: 36.h, color: AppColors.border);
}

Widget _gridDataCell(String text, {double? width, int flex = 1, bool center = false}) {
  final child = Container(
    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
    alignment: center ? Alignment.center : Alignment.centerLeft,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
    ),
    child: Text(text, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary), overflow: TextOverflow.ellipsis),
  );
  return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
}

Widget _buildImportCard({
  required String title,
  required List<String> headers,
  required List<List<dynamic>> rows,
  required VoidCallback onBrowse,
  required VoidCallback? onSave,
  required VoidCallback onTemplate,
  required bool saving,
  String? fileName,
  int imported = 0,
  int skipped = 0,
  List<String> errors = const [],
  bool showResult = false,
  VoidCallback? onDismissResult,
  VoidCallback? onValidate,
  VoidCallback? onClose,
  bool isValidated = false,
  List<List<dynamic>> existingRows = const [],
  List<String> existingHeaders = const [],
  bool isLoadingExisting = false,
  VoidCallback? onSampleDownload,
  Map<int, String> rowErrors = const {},
}) {
  final bool showExisting = rows.isEmpty && existingRows.isNotEmpty;
  final displayHeaders = showExisting ? existingHeaders : headers;
  final displayRows = showExisting ? existingRows : rows;
  return Container(
    padding: EdgeInsets.all(16.w),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10.r),
      border: Border.all(color: AppColors.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title bar
        Row(
          children: [
            AppIcon('document-upload', size: 20, color: AppColors.accent),
            SizedBox(width: 8.w),
            Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (fileName != null)
              Text(fileName, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
            SizedBox(width: 12.w),
            ElevatedButton.icon(
              onPressed: onBrowse,
              icon: AppIcon('document-upload', size: 16),
              label: const Text('Import'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(width: 8.w),
            ElevatedButton.icon(
              onPressed: onTemplate,
              icon: AppIcon('grid-1', size: 16),
              label: const Text('Format to Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF217346),
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
              ),
            ),
            if (onSampleDownload != null) ...[
              SizedBox(width: 8.w),
              ElevatedButton.icon(
                onPressed: onSampleDownload,
                icon: AppIcon('document-download', size: 16),
                label: const Text('Sample Data'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFE65100),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ],
        ),
        if (showResult) ...[
          SizedBox(height: 8.h),
          Container(
            padding: EdgeInsets.all(10.w),
            decoration: BoxDecoration(
              color: errors.isEmpty ? const Color(0xFFE6F4EA) : const Color(0xFFFCE4E4),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    AppIcon(errors.isEmpty ? 'tick-circle' : 'warning-2', color: errors.isEmpty ? AppColors.success : AppColors.error, size: 18),
                    SizedBox(width: 8.w),
                    Text('$imported imported, $skipped skipped', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp)),
                    const Spacer(),
                    IconButton(icon: AppIcon.linear('close-circle', size: 16), onPressed: onDismissResult, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ],
                ),
                if (errors.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  ...errors.take(5).map((e) => Padding(
                    padding: EdgeInsets.only(top: 2.h),
                    child: Text(e, style: TextStyle(fontSize: 13.sp, color: Colors.red)),
                  )),
                  if (errors.length > 5) Text('... and ${errors.length - 5} more errors', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                ],
              ],
            ),
          ),
        ],
        SizedBox(height: 12.h),

        // Data grid
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8.r),
            ),
            child: Column(
              children: [
                // Header row
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.tableHeadBg,
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(7.r),
                      topRight: Radius.circular(7.r),
                    ),
                  ),
                  child: Row(
                    children: [
                      _gridHeaderCell('S.No', width: 60.w, center: true),
                      ...displayHeaders.expand((h) => [
                        _gridHeaderDivider(),
                        _gridHeaderCell(h),
                      ]),
                    ],
                  ),
                ),
                // Existing records label
                if (showExisting)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    color: AppColors.accent.withValues(alpha: 0.06),
                    child: Row(
                      children: [
                        AppIcon.linear('box-1', size: 14, color: AppColors.accent),
                        SizedBox(width: 6.w),
                        Text('Existing Records (${existingRows.length})', style: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
                      ],
                    ),
                  ),
                // Data rows
                Expanded(
                  child: isLoadingExisting && rows.isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : displayRows.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIcon('element-4', size: 48.sp, color: AppColors.textPrimary.withValues(alpha: 0.3)),
                                  SizedBox(height: 8.h),
                                  Text('No data loaded', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                                  SizedBox(height: 4.h),
                                  Text('Click Browse to load a CSV or Excel file', style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary)),
                                ],
                              ),
                            )
                          : ListView.builder(
                              itemCount: displayRows.length,
                              itemBuilder: (_, i) {
                                final hasError = !showExisting && rowErrors.containsKey(i);
                                return Tooltip(
                                  message: hasError ? rowErrors[i]! : '',
                                  child: Container(
                                    padding: EdgeInsets.zero,
                                    color: hasError ? const Color(0xFFFCE4E4) : (i.isEven ? Colors.white : AppColors.surface),
                                    child: Row(
                                      children: [
                                        _gridDataCell('${i + 1}', width: 60.w, center: true),
                                        ...List.generate(displayHeaders.length, (j) =>
                                          _gridDataCell(j < displayRows[i].length ? displayRows[i][j].toString() : ''),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
        ),

        SizedBox(height: 12.h),

        // Bottom bar
        Row(
          children: [
            Text('${displayRows.length} rows${showExisting ? ' (existing)' : ''}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textPrimary)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: rows.isNotEmpty && !saving ? onValidate : null,
              icon: AppIcon.linear('tick-circle', size: 16),
              label: const Text('Validate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: rows.isNotEmpty && !saving ? AppColors.accent : AppColors.textPrimary,
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                textStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(width: 8.w),
            ElevatedButton.icon(
              onPressed: saving ? null : (isValidated ? onSave : null),
              icon: saving
                  ? SizedBox(width: 14.w, height: 14.h, child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : AppIcon('save-2', size: 16),
              label: Text(saving ? 'Saving...' : 'Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: isValidated ? AppColors.accent : Colors.grey.shade300,
                foregroundColor: Colors.white,
                padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600),
              ),
            ),
            SizedBox(width: 8.w),
            OutlinedButton(
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
                textStyle: TextStyle(fontSize: 12.sp, fontWeight: FontWeight.w600),
              ),
              child: const Text('Close'),
            ),
          ],
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════
// 1. FEE GROUP TAB
// ═══════════════════════════════════════════════
// COURSE TAB
// ═══════════════════════════════════════════════

class _CourseTab extends StatefulWidget {
  const _CourseTab();
  @override
  State<_CourseTab> createState() => _CourseTabState();
}

class _CourseTabState extends State<_CourseTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['Course ID *', 'Course Name *', 'Order'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final rows = await SupabaseService.fromSchema('course').select('*').eq('ins_id', insId).order('cour_id', ascending: true);
      if (mounted) setState(() {
        _existingRows = (rows as List).map((r) => [r['cour_id']?.toString() ?? '', r['courname'] ?? '', r['ordid']?.toString() ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    for (int i = 0; i < _rows.length; i++) {
      final idRaw = _rows[i].isNotEmpty ? _rows[i][0]?.toString().trim() ?? '' : '';
      final name = _rows[i].length > 1 ? _rows[i][1]?.toString().trim() ?? '' : '';
      if (idRaw.isEmpty || int.tryParse(idRaw) == null) { rowErrs[i] = 'Invalid Course ID'; continue; }
      if (name.isEmpty) rowErrs[i] = 'Missing: Course Name';
    }
    setState(() { _rowErrors = rowErrs; _isValidated = rowErrs.isEmpty; });
    if (rowErrs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rowErrs.length} row(s) have errors'), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation passed! Click Save to import.'), backgroundColor: Colors.green));
    }
  }

  void _close() {
    setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    for (final row in _rows) {
      if (row.length < 2 || row[1].toString().trim().isEmpty) { _skipped++; continue; }
      try {
        final courId = int.tryParse(row[0].toString().trim());
        if (courId == null) { _skipped++; _errors.add('Row with name ${row[1]}: invalid Course ID'); continue; }
        await SupabaseService.fromSchema('course').insert({
          'cour_id': courId,
          'courname': row[1].toString().trim(),
          'ordid': row.length > 2 ? int.tryParse(row[2].toString().trim()) : null,
          'ins_id': insId,
        });
        _imported++;
      } catch (e) {
        _skipped++;
        _errors.add('${row[1]}: ${_friendlyError(e.toString())}');
      }
    }
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Courses',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Course', _headers),
      onSampleDownload: () => _exportSampleData('Course', _headers, [
        ['Pre-KG', '1'],
        ['LKG', '2'],
        ['UKG', '3'],
        ['I', '4'],
        ['II', '5'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Course ID', 'Course Name', 'Order'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

// ═══════════════════════════════════════════════
// CLASS TAB
// ═══════════════════════════════════════════════

class _ClassTab extends StatefulWidget {
  const _ClassTab();
  @override
  State<_ClassTab> createState() => _ClassTabState();
}

class _ClassTabState extends State<_ClassTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['Class ID *', 'Class Name *', 'Succeeding Class', 'Order'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final rows = await SupabaseService.fromSchema('class').select('*').eq('ins_id', insId).order('cla_id', ascending: true);
      if (mounted) setState(() {
        _existingRows = (rows as List).map((r) => [r['cla_id']?.toString() ?? '', r['claname'] ?? '', r['succeedingclass']?.toString() ?? '', r['ordid']?.toString() ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    for (int i = 0; i < _rows.length; i++) {
      final missing = <String>[];
      final idRaw = _rows[i].isNotEmpty ? _rows[i][0]?.toString().trim() ?? '' : '';
      final name = _rows[i].length > 1 ? _rows[i][1]?.toString().trim() ?? '' : '';
      final course = _rows[i].length > 2 ? _rows[i][2]?.toString().trim() ?? '' : '';
      if (idRaw.isEmpty || int.tryParse(idRaw) == null) { rowErrs[i] = 'Invalid Class ID'; continue; }
      if (name.isEmpty) missing.add('Class Name');
      // Succeeding Class is optional (terminal class has no successor)
      if (missing.isNotEmpty) rowErrs[i] = 'Missing: ${missing.join(', ')}';
      // Suppress unused variable warning
      // ignore: unused_local_variable
      final _ = course;
    }
    setState(() { _rowErrors = rowErrs; _isValidated = rowErrs.isEmpty; });
    if (rowErrs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rowErrs.length} row(s) have errors'), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation passed! Click Save to import.'), backgroundColor: Colors.green));
    }
  }

  void _close() {
    setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    for (final row in _rows) {
      if (row.isEmpty || row[1].toString().trim().isEmpty) { _skipped++; continue; }
      try {
        final claId = int.tryParse(row[0].toString().trim());
        if (claId == null) { _skipped++; _errors.add('Row: invalid Class ID'); continue; }
        final succeedingRaw = row.length > 2 ? row[2].toString().trim() : '';
        await SupabaseService.fromSchema('class').insert({
          'cla_id': claId,
          'claname': row[1].toString().trim(),
          'succeedingclass': succeedingRaw.isEmpty ? null : succeedingRaw,
          'ordid': row.length > 3 ? int.tryParse(row[3].toString().trim()) : null,
          'ins_id': insId,
        });
        _imported++;
      } catch (e) {
        _skipped++;
        _errors.add('${row[1]}: ${_friendlyError(e.toString())}');
      }
    }
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Classes',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Class', _headers),
      onSampleDownload: () => _exportSampleData('Class', _headers, [
        ['1', 'I Year', 'II Year', '1'],
        ['2', 'II Year', 'III Year', '2'],
        ['3', 'III Year', '', '3'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Class ID', 'Class Name', 'Succeeding Class', 'Order'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

// ═══════════════════════════════════════════════

class _FeeGroupTab extends StatefulWidget {
  const _FeeGroupTab();
  @override
  State<_FeeGroupTab> createState() => _FeeGroupTabState();
}

class _FeeGroupTabState extends State<_FeeGroupTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['Fee Group ID *', 'Group Name *', 'Year *'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final groups = await SupabaseService.getFeeGroups(insId);
      if (mounted) setState(() {
        _existingRows = groups.map((g) => [g['fg_id']?.toString() ?? '', g['fgdesc'] ?? '', g['yrlabel'] ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    final labels = _headers.map((h) => h.replaceAll(' *', '').replaceAll('*', '')).toList();
    for (int i = 0; i < _rows.length; i++) {
      final missing = <String>[];
      for (int j = 0; j < labels.length; j++) {
        final val = _rows[i].length > j ? _rows[i][j]?.toString().trim() ?? '' : '';
        if (val.isEmpty) missing.add(labels[j]);
      }
      if (missing.isNotEmpty) rowErrs[i] = 'Missing: ${missing.join(', ')}';
    }
    setState(() { _rowErrors = rowErrs; _isValidated = rowErrs.isEmpty; });
    if (rowErrs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rowErrs.length} row(s) have errors — highlighted in red'), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation passed! Click Save to import.'), backgroundColor: Colors.green));
    }
  }

  void _close() {
    setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    try {
      final result = await _stagingImport(insId: insId, impType: 'FEEGROUP', rows: _rows, colCount: 3);
      _imported = result['imported'] ?? 0;
      _skipped = result['skipped'] ?? 0;
      if (_skipped > 0) _errors = await _getImportErrors(insId, 'FEEGROUP');
    } catch (e) {
      _errors = ['Import failed: ${_friendlyError(e.toString())}'];
    }
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) {
      _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Fee Groups',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Fee Group', _headers),
      onSampleDownload: () => _exportSampleData('Fee Group', _headers, [
        ['1', 'SCHOOL FEES', '2025-2026'],
        ['2', 'VAN FEES', '2025-2026'],
        ['3', 'HOSTEL FEES', '2025-2026'],
        ['4', 'EXAM FEES', '2025-2026'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Fee Group ID', 'Group Name', 'Year'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

// ═══════════════════════════════════════════════
// 2. FEE TYPE TAB
// Columns: Fee Name *, Short Name *, Fee Group *, Optional, Category
// ═══════════════════════════════════════════════

class _FeeTypeTab extends StatefulWidget {
  const _FeeTypeTab();
  @override
  State<_FeeTypeTab> createState() => _FeeTypeTabState();
}

class _FeeTypeTabState extends State<_FeeTypeTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['Fee ID *', 'Fee Name *', 'Short Name *', 'Fee Group *', 'Year *', 'Optional *', 'Category *', 'Fine Applicable *'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final feeGroups = await SupabaseService.getFeeGroups(insId);
      if (feeGroups.isEmpty) { if (mounted) setState(() => _isLoadingExisting = false); return; }
      final fgIds = feeGroups.map((fg) => fg['fg_id'] as int).toList();
      final fgNameMap = { for (final fg in feeGroups) fg['fg_id'] as int: fg['fgdesc']?.toString() ?? '' };
      final types = await SupabaseService.fromSchema('feetype').select('*').inFilter('fg_id', fgIds).eq('activestatus', 1).order('fee_id', ascending: true);
      if (mounted) setState(() {
        const fineLabels = {'1': 'Yes', '0': 'No'};
        _existingRows = (types as List).map((t) {
          return [
            t['fee_id']?.toString() ?? '',
            t['feedesc'] ?? '',
            t['feeshort'] ?? '',
            fgNameMap[t['fg_id']] ?? '',
            t['yrlabel'] ?? '',
            t['feeoptional'] ?? '',
            t['feecategory'] ?? '',
            fineLabels['${t['feefineapplicable'] ?? 0}'] ?? 'No',
          ];
        }).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    final labels = _headers.map((h) => h.replaceAll(' *', '').replaceAll('*', '')).toList();
    for (int i = 0; i < _rows.length; i++) {
      final missing = <String>[];
      for (int j = 0; j < labels.length; j++) {
        final val = _rows[i].length > j ? _rows[i][j]?.toString().trim() ?? '' : '';
        if (val.isEmpty) missing.add(labels[j]);
      }
      if (missing.isNotEmpty) rowErrs[i] = 'Missing: ${missing.join(', ')}';
    }
    setState(() { _rowErrors = rowErrs; _isValidated = rowErrs.isEmpty; });
    if (rowErrs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rowErrs.length} row(s) have errors — highlighted in red'), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation passed! Click Save to import.'), backgroundColor: Colors.green));
    }
  }

  void _close() { setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; }); }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    try {
      const fineMap = {'yes': '1', 'y': '1', 'true': '1', '1': '1', 'no': '0', 'n': '0', 'false': '0', '0': '0', '': '0'};
      final mappedRows = _rows.map((row) {
        final mapped = List<dynamic>.from(row);
        while (mapped.length < 8) {
          mapped.add('');
        }
        // Fine Applicable is now col 8 (index 7) after prepending Fee ID.
        final fine = mapped[7].toString().trim().toLowerCase();
        mapped[7] = fineMap[fine] ?? mapped[7];
        return mapped;
      }).toList();
      final result = await _stagingImport(insId: insId, impType: 'FEETYPE', rows: mappedRows, colCount: 8);
      _imported = result['imported'] ?? 0;
      _skipped = result['skipped'] ?? 0;
      if (_skipped > 0) _errors = await _getImportErrors(insId, 'FEETYPE');
    } catch (e) {
      _errors = ['Import failed: ${_friendlyError(e.toString())}'];
    }
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) {
      _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Fee Types',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Fee Type', _headers),
      onSampleDownload: () => _exportSampleData('Fee Type', _headers, [
        ['1', 'SCHOOL FEES', 'SCH', 'SCHOOL FEES', '2025-2026', '0', '1', 'Yes'],
        ['2', 'VAN FEES', 'VAN', 'VAN FEES', '2025-2026', '1', '1', 'No'],
        ['3', 'TUITION FEES', 'TUI', 'SCHOOL FEES', '2025-2026', '0', '1', 'Yes'],
        ['4', 'BOOK FEES', 'BK', 'SCHOOL FEES', '2025-2026', '0', '1', 'No'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Fee ID', 'Fee Name', 'Short Name', 'Fee Group', 'Year', 'Optional', 'Category', 'Fine Applicable'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

// ═══════════════════════════════════════════════
// 3. CONCESSION TAB
// Columns: Concession Name *, Order
// ═══════════════════════════════════════════════

class _ConcessionTab extends StatefulWidget {
  const _ConcessionTab();
  @override
  State<_ConcessionTab> createState() => _ConcessionTabState();
}

class _ConcessionTabState extends State<_ConcessionTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['Concession ID *', 'Concession Name *'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final concessions = await SupabaseService.getConcessions(insId);
      if (mounted) setState(() {
        _existingRows = concessions.map((c) => [c['con_id']?.toString() ?? '', c['condesc'] ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    final labels = _headers.map((h) => h.replaceAll(' *', '').replaceAll('*', '')).toList();
    for (int i = 0; i < _rows.length; i++) {
      final missing = <String>[];
      for (int j = 0; j < labels.length; j++) {
        final val = _rows[i].length > j ? _rows[i][j]?.toString().trim() ?? '' : '';
        if (val.isEmpty) missing.add(labels[j]);
      }
      if (missing.isNotEmpty) rowErrs[i] = 'Missing: ${missing.join(', ')}';
    }
    setState(() { _rowErrors = rowErrs; _isValidated = rowErrs.isEmpty; });
    if (rowErrs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rowErrs.length} row(s) have errors — highlighted in red'), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation passed! Click Save to import.'), backgroundColor: Colors.green));
    }
  }

  void _close() { setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; }); }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    try {
      final result = await _stagingImport(insId: insId, impType: 'CONCESSION', rows: _rows, colCount: 2);
      _imported = result['imported'] ?? 0;
      _skipped = result['skipped'] ?? 0;
      if (_skipped > 0) _errors = await _getImportErrors(insId, 'CONCESSION');
    } catch (e) {
      _errors = ['Import failed: ${_friendlyError(e.toString())}'];
    }
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) {
      _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Concessions',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Concession', _headers),
      onSampleDownload: () => _exportSampleData('Concession', _headers, [
        ['1', 'SC/ST'],
        ['2', 'Staff Children'],
        ['3', 'Merit Scholarship'],
        ['4', 'Sibling Discount'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Concession ID', 'Concession Name'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

// ═══════════════════════════════════════════════
// 4. CLASS FEE DEMAND TAB
// Columns: Class *, Term, Fee Type *, Amount, Due Date, Admission Type
// ═══════════════════════════════════════════════

class _ClassFeeDemandTab extends StatefulWidget {
  const _ClassFeeDemandTab();
  @override
  State<_ClassFeeDemandTab> createState() => _ClassFeeDemandTabState();
}

class _ClassFeeDemandTabState extends State<_ClassFeeDemandTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['CF ID *', 'Class *', 'Semester *', 'Fee Type *', 'Amount *', 'Due Date *', 'Admission Type *'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final rows = await SupabaseService.fromSchema('classfeedemand').select('*');
      if (mounted) setState(() {
        const classOrder = {'PKG': 0, 'LKG': 1, 'UKG': 2, 'I': 3, 'II': 4, 'III': 5, 'IV': 6, 'V': 7, 'VI': 8, 'VII': 9, 'VIII': 10, 'IX': 11, 'X': 12, 'XI': 13, 'XII': 14};
        final sorted = List<Map<String, dynamic>>.from(rows as List);
        sorted.sort((a, b) {
          final ca = classOrder[a['cfclass']?.toString() ?? ''] ?? 99;
          final cb = classOrder[b['cfclass']?.toString() ?? ''] ?? 99;
          if (ca != cb) return ca.compareTo(cb);
          return (a['cfterm']?.toString() ?? '').compareTo(b['cfterm']?.toString() ?? '');
        });
        const admTypeLabels = {'1': 'New', '2': 'Old', '3': 'Both'};
        _existingRows = sorted.map((r) => [
          r['cf_id']?.toString() ?? '',
          r['cfclass'] ?? '',
          r['cfterm'] ?? '',
          r['cffeetype'] ?? '',
          r['cfamount'] ?? '',
          r['cfdduedate'] ?? '',
          admTypeLabels['${r['admissiontype'] ?? ''}'] ?? '${r['admissiontype'] ?? ''}',
        ]).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    final labels = ['CF ID', 'Class', 'Semester', 'Fee Type', 'Amount', 'Due Date', 'Admission Type'];
    for (int i = 0; i < _rows.length; i++) {
      final idRaw = _rows[i].isNotEmpty ? _rows[i][0]?.toString().trim() ?? '' : '';
      if (idRaw.isEmpty || int.tryParse(idRaw) == null) { rowErrs[i] = 'Invalid CF ID'; continue; }
      final missing = <String>[];
      for (int j = 1; j < labels.length; j++) {
        final val = _rows[i].length > j ? _rows[i][j]?.toString().trim() ?? '' : '';
        if (val.isEmpty) missing.add(labels[j]);
      }
      if (missing.isNotEmpty) rowErrs[i] = 'Missing: ${missing.join(', ')}';
    }
    setState(() { _rowErrors = rowErrs; _isValidated = rowErrs.isEmpty; });
    if (rowErrs.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${rowErrs.length} row(s) have errors — highlighted in red'), backgroundColor: Colors.red));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Validation passed! Click Save to import.'), backgroundColor: Colors.green));
    }
  }

  void _close() { setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; }); }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    try {
      const admTypeMap = {'new': '1', 'old': '2', 'both': '3', '1': '1', '2': '2', '3': '3'};
      final mappedRows = _rows.map((row) {
        final mapped = List<dynamic>.from(row);
        while (mapped.length < 7) mapped.add('');
        // Admission Type is now col 7 (index 6) after prepending CF ID.
        final adm = mapped[6].toString().trim().toLowerCase();
        mapped[6] = admTypeMap[adm] ?? mapped[6];
        return mapped;
      }).toList();
      final result = await _stagingImport(insId: insId, impType: 'CLASSFEEDEMAND', rows: mappedRows, colCount: 7);
      _imported = result['imported'] ?? 0;
      _skipped = result['skipped'] ?? 0;
      if (_skipped > 0) _errors = await _getImportErrors(insId, 'CLASSFEEDEMAND');
    } catch (e) {
      _errors = ['Import failed: ${_friendlyError(e.toString())}'];
    }
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) {
      _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Class Fee Demand',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Class Fee Demand', _headers),
      onSampleDownload: () => _exportSampleData('Class Fee Demand', _headers, [
        ['1', 'I', 'I TERM', 'SCHOOL FEES', '10080', '2025-05-31', 'Both'],
        ['2', 'I', 'JUNE', 'TUITION FEES', '700', '2025-06-30', 'Both'],
        ['3', 'XII', 'I TERM', 'SCHOOL FEES', '15410', '2025-05-31', 'Both'],
        ['4', 'XII', 'JUNE', 'VAN FEES', '810', '2025-06-30', 'Both'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['CF ID', 'Class', 'Semester', 'Fee Type', 'Amount', 'Due Date', 'Admission Type'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

// ═══════════════════════════════════════════════
// ADMISSION TYPE / QUOTA — simple lookup tables
// (ids are user-supplied; no auto-trigger)
// ═══════════════════════════════════════════════

Future<Map<String, int>> _directLookupImport({
  required int insId,
  required String table,
  required String idCol,
  required String nameCol,
  required List<List<dynamic>> rows,
  required bool hasInsId,
  required List<String> errorsOut,
}) async {
  int imported = 0;
  int skipped = 0;
  for (int i = 0; i < rows.length; i++) {
    try {
      final row = rows[i];
      final idRaw = row.isNotEmpty ? row[0].toString().trim() : '';
      final name = row.length > 1 ? row[1].toString().trim() : '';
      final id = int.tryParse(idRaw);
      if (id == null || name.isEmpty) {
        skipped++;
        errorsOut.add('Row ${i + 2}: invalid id or name');
        continue;
      }
      final record = <String, dynamic>{
        idCol: id,
        nameCol: name,
        'activestatus': 1,
      };
      if (hasInsId) record['ins_id'] = insId;
      await SupabaseService.fromSchema(table).upsert(record, onConflict: idCol);
      imported++;
    } catch (e) {
      skipped++;
      errorsOut.add('Row ${i + 2}: ${_friendlyError(e.toString())}');
    }
  }
  return {'imported': imported, 'skipped': skipped};
}

class _AdmissionTypeTab extends StatefulWidget {
  const _AdmissionTypeTab();
  @override
  State<_AdmissionTypeTab> createState() => _AdmissionTypeTabState();
}

class _AdmissionTypeTabState extends State<_AdmissionTypeTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['Adm ID *', 'Admission Name *'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _loadExisting(); }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    if (auth.insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final rows = await SupabaseService.fromSchema('admissiontype').select('adm_id, admname').eq('activestatus', 1).order('adm_id', ascending: true);
      if (mounted) setState(() {
        _existingRows = (rows as List).map((r) => [r['adm_id']?.toString() ?? '', r['admname']?.toString() ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final errs = <int, String>{};
    for (int i = 0; i < _rows.length; i++) {
      final idRaw = _rows[i].isNotEmpty ? _rows[i][0]?.toString().trim() ?? '' : '';
      final name = _rows[i].length > 1 ? _rows[i][1]?.toString().trim() ?? '' : '';
      if (idRaw.isEmpty || int.tryParse(idRaw) == null) { errs[i] = 'Invalid Adm ID'; continue; }
      if (name.isEmpty) { errs[i] = 'Missing Admission Name'; }
    }
    setState(() { _rowErrors = errs; _isValidated = errs.isEmpty; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(errs.isEmpty ? 'Validation passed' : '${errs.length} row(s) have errors'),
      backgroundColor: errs.isEmpty ? Colors.green : Colors.red,
    ));
  }

  void _close() { setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; }); }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    final errs = <String>[];
    final result = await _directLookupImport(
      insId: insId, table: 'admissiontype', idCol: 'adm_id', nameCol: 'admname',
      rows: _rows, hasInsId: true, errorsOut: errs,
    );
    _imported = result['imported'] ?? 0;
    _skipped = result['skipped'] ?? 0;
    _errors = errs;
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) {
      _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Admission Types',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Admission Type', _headers),
      onSampleDownload: () => _exportSampleData('Admission Type', _headers, [
        ['1', 'GOVERNMENT QUOTA'],
        ['2', 'MANAGEMENT QUOTA'],
        ['3', 'NRI QUOTA'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Adm ID', 'Admission Name'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

class _QuotaTab extends StatefulWidget {
  const _QuotaTab();
  @override
  State<_QuotaTab> createState() => _QuotaTabState();
}

class _QuotaTabState extends State<_QuotaTab> with AutomaticKeepAliveClientMixin {
  List<List<dynamic>> _rows = [];
  String? _fileName;
  bool _saving = false;
  bool _isValidated = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  Map<int, String> _rowErrors = {};
  static const _headers = ['Quo ID *', 'Quota Name *'];
  List<List<dynamic>> _existingRows = [];
  bool _isLoadingExisting = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() { super.initState(); _loadExisting(); }

  Future<void> _loadExisting() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId;
    if (insId == null) return;
    setState(() => _isLoadingExisting = true);
    try {
      final rows = await SupabaseService.fromSchema('quota').select('quo_id, quoname').eq('ins_id', insId).eq('activestatus', 1).order('quo_id', ascending: true);
      if (mounted) setState(() {
        _existingRows = (rows as List).map((r) => [r['quo_id']?.toString() ?? '', r['quoname']?.toString() ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (_) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    List<List<dynamic>> parsed;
    try {
      parsed = _parseExcel(result.files.single.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not read file: $e'), backgroundColor: Colors.red),
        );
      }
      return;
    }
    if (parsed.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File has no data rows. Add at least one row below the header.'), backgroundColor: Colors.orange),
        );
      }
      return;
    }
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final errs = <int, String>{};
    for (int i = 0; i < _rows.length; i++) {
      final idRaw = _rows[i].isNotEmpty ? _rows[i][0]?.toString().trim() ?? '' : '';
      final name = _rows[i].length > 1 ? _rows[i][1]?.toString().trim() ?? '' : '';
      if (idRaw.isEmpty || int.tryParse(idRaw) == null) { errs[i] = 'Invalid Quo ID'; continue; }
      if (name.isEmpty) { errs[i] = 'Missing Quota Name'; }
    }
    setState(() { _rowErrors = errs; _isValidated = errs.isEmpty; });
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(errs.isEmpty ? 'Validation passed' : '${errs.length} row(s) have errors'),
      backgroundColor: errs.isEmpty ? Colors.green : Colors.red,
    ));
  }

  void _close() { setState(() { _rows = []; _fileName = null; _isValidated = false; _errors = []; _rowErrors = {}; }); }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    final errs = <String>[];
    final result = await _directLookupImport(
      insId: insId, table: 'quota', idCol: 'quo_id', nameCol: 'quoname',
      rows: _rows, hasInsId: true, errorsOut: errs,
    );
    _imported = result['imported'] ?? 0;
    _skipped = result['skipped'] ?? 0;
    _errors = errs;
    setState(() { _saving = false; _rows = []; _fileName = null; _isValidated = false; });
    if (mounted) {
      _showImportResultDialog(context, imported: _imported, skipped: _skipped, errors: _errors, onDone: _loadExisting);
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Quota',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty && _isValidated ? _save : null,
      onTemplate: () => _exportTemplate('Quota', _headers),
      onSampleDownload: () => _exportSampleData('Quota', _headers, [
        ['1', 'GENERAL'],
        ['2', 'OBC'],
        ['3', 'SC'],
        ['4', 'ST'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Quo ID', 'Quota Name'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

