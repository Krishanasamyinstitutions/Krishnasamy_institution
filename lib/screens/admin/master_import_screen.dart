import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:file_picker/file_picker.dart';
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
            Icon(errors.isEmpty ? Icons.check_circle_rounded : Icons.warning_rounded, size: 64.sp, color: errors.isEmpty ? AppColors.success : AppColors.error),
            SizedBox(height: 16.h),
            Text(errors.isEmpty ? 'Import Complete' : 'Import Completed with Errors', style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
            SizedBox(height: 12.h),
            Text('$imported imported successfully, $skipped skipped', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
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
    _tabCtrl = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListenableBuilder(
          listenable: _tabCtrl,
          builder: (context, _) {
            final selected = _tabCtrl.index;
            final tabLabels = ['Course', 'Class', 'Fee Group', 'Fee Type', 'Concession', 'Class Fee Demand'];
            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12.r),
                border: Border.all(color: AppColors.border),
              ),
              padding: EdgeInsets.all(4.w),
              child: Row(
                children: List.generate(tabLabels.length, (i) {
                  final isActive = selected == i;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => _tabCtrl.animateTo(i),
                      child: Container(
                        margin: EdgeInsets.only(right: i < tabLabels.length - 1 ? 4.w : 0),
                        padding: EdgeInsets.symmetric(vertical: 12.h),
                        decoration: BoxDecoration(
                          color: isActive ? AppColors.accent : Colors.transparent,
                          borderRadius: BorderRadius.circular(10.r),
                        ),
                        child: Center(
                          child: Text(
                            tabLabels[i],
                            style: TextStyle(
                              fontSize: 13.sp,
                              fontWeight: FontWeight.w600,
                              color: isActive ? Colors.white : AppColors.textPrimary,
                            ),
                          ),
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
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
              _CourseTab(),
              _ClassTab(),
              _FeeGroupTab(),
              _FeeTypeTab(),
              _ConcessionTab(),
              _ClassFeeDemandTab(),
            ],
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
    child: Text(text.toUpperCase(), style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3.w)),
  );
  return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
}

Widget _gridHeaderDivider() {
  return Container(width: 1, height: 36.h, color: Colors.white.withValues(alpha: 0.15));
}

Widget _gridDataCell(String text, {double? width, int flex = 1, bool center = false}) {
  final child = Container(
    padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 10.h),
    alignment: center ? Alignment.center : Alignment.centerLeft,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
    ),
    child: Text(text, style: TextStyle(fontSize: 13.sp, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
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
            Icon(Icons.upload_file_rounded, size: 20.sp, color: AppColors.accent),
            SizedBox(width: 8.w),
            Text(title, style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (fileName != null)
              Text(fileName, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
            SizedBox(width: 12.w),
            ElevatedButton.icon(
              onPressed: onBrowse,
              icon: Icon(Icons.folder_open_rounded, size: 16.sp),
              label: const Text('Browse'),
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
              icon: Icon(Icons.table_chart_rounded, size: 16.sp),
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
                icon: Icon(Icons.download_rounded, size: 16.sp),
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
                    Icon(errors.isEmpty ? Icons.check_circle : Icons.warning_rounded, color: errors.isEmpty ? AppColors.success : AppColors.error, size: 18.sp),
                    SizedBox(width: 8.w),
                    Text('$imported imported, $skipped skipped', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13.sp)),
                    const Spacer(),
                    IconButton(icon: Icon(Icons.close, size: 16.sp), onPressed: onDismissResult, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ],
                ),
                if (errors.isNotEmpty) ...[
                  SizedBox(height: 4.h),
                  ...errors.take(5).map((e) => Padding(
                    padding: EdgeInsets.only(top: 2.h),
                    child: Text(e, style: TextStyle(fontSize: 13.sp, color: Colors.red)),
                  )),
                  if (errors.length > 5) Text('... and ${errors.length - 5} more errors', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
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
                    color: const Color(0xFF6C8EEF),
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
                        Icon(Icons.inventory_2_outlined, size: 14.sp, color: AppColors.accent),
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
                                  Icon(Icons.grid_on_rounded, size: 48.sp, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                                  SizedBox(height: 8.h),
                                  Text('No data loaded', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
                                  SizedBox(height: 4.h),
                                  Text('Click Browse to load a CSV or Excel file', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
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
            Text('${displayRows.length} rows${showExisting ? ' (existing)' : ''}', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: rows.isNotEmpty && !saving ? onValidate : null,
              icon: Icon(Icons.check_circle_outline_rounded, size: 16.sp),
              label: const Text('Validate'),
              style: OutlinedButton.styleFrom(
                foregroundColor: rows.isNotEmpty && !saving ? AppColors.accent : AppColors.textSecondary,
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
                  : Icon(Icons.save_rounded, size: 16.sp),
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
  static const _headers = ['Course Name *', 'Order'];
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
      final rows = await SupabaseService.fromSchema('course').select('*').eq('ins_id', insId).order('ordid');
      if (mounted) setState(() {
        _existingRows = (rows as List).map((r) => [r['courname'] ?? '', r['ordid']?.toString() ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    for (int i = 0; i < _rows.length; i++) {
      final name = _rows[i].isNotEmpty ? _rows[i][0]?.toString().trim() ?? '' : '';
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
      if (row.isEmpty || row[0].toString().trim().isEmpty) { _skipped++; continue; }
      try {
        await SupabaseService.fromSchema('course').insert({
          'courname': row[0].toString().trim(),
          'ordid': row.length > 1 ? int.tryParse(row[1].toString().trim()) : null,
          'ins_id': insId,
        });
        _imported++;
      } catch (e) {
        _skipped++;
        _errors.add('${row[0]}: ${_friendlyError(e.toString())}');
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
      existingHeaders: const ['Course Name', 'Order'],
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
  static const _headers = ['Class Name *', 'Course *', 'Order'];
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
      final courses = await SupabaseService.fromSchema('course').select('cour_id, courname').eq('ins_id', insId);
      final courseMap = { for (final c in courses as List) c['cour_id'] as int: c['courname']?.toString() ?? '' };
      final rows = await SupabaseService.fromSchema('class').select('*').eq('ins_id', insId).order('ordid');
      if (mounted) setState(() {
        _existingRows = (rows as List).map((r) => [r['claname'] ?? '', courseMap[r['cour_id']] ?? '${r['cour_id'] ?? ''}', r['ordid']?.toString() ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    for (int i = 0; i < _rows.length; i++) {
      final missing = <String>[];
      final name = _rows[i].isNotEmpty ? _rows[i][0]?.toString().trim() ?? '' : '';
      final course = _rows[i].length > 1 ? _rows[i][1]?.toString().trim() ?? '' : '';
      if (name.isEmpty) missing.add('Class Name');
      if (course.isEmpty) missing.add('Course');
      if (missing.isNotEmpty) rowErrs[i] = 'Missing: ${missing.join(', ')}';
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
      if (row.length < 2 || row[0].toString().trim().isEmpty) { _skipped++; continue; }
      try {
        final courseName = row[1].toString().trim();
        final courseResult = await SupabaseService.fromSchema('course')
            .select('cour_id').eq('ins_id', insId).ilike('courname', courseName).limit(1).maybeSingle();
        if (courseResult == null) { _skipped++; _errors.add('${row[0]}: Course "$courseName" not found'); continue; }
        await SupabaseService.fromSchema('class').insert({
          'claname': row[0].toString().trim(),
          'cour_id': courseResult['cour_id'],
          'ordid': row.length > 2 ? int.tryParse(row[2].toString().trim()) : null,
          'ins_id': insId,
        });
        _imported++;
      } catch (e) {
        _skipped++;
        _errors.add('${row[0]}: ${_friendlyError(e.toString())}');
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
        ['Section A', 'LKG', '1'],
        ['Section B', 'LKG', '2'],
        ['Section A', 'UKG', '1'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Class Name', 'Course', 'Order'],
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
  static const _headers = ['Group Name *', 'Year *'];
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
        _existingRows = groups.map((g) => [g['fgdesc'] ?? '', g['yrlabel'] ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
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
      final result = await _stagingImport(insId: insId, impType: 'FEEGROUP', rows: _rows, colCount: 2);
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
        ['SCHOOL FEES', '2025-2026'],
        ['VAN FEES', '2025-2026'],
        ['HOSTEL FEES', '2025-2026'],
        ['EXAM FEES', '2025-2026'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Group Name', 'Year'],
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
  static const _headers = ['Fee Name *', 'Short Name *', 'Fee Group *', 'Year *', 'Optional *', 'Category *'];
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
      final types = await SupabaseService.fromSchema('feetype').select('*').inFilter('fg_id', fgIds).eq('activestatus', 1).order('fee_id');
      if (mounted) setState(() {
        _existingRows = (types as List).map((t) {
          return [t['feedesc'] ?? '', t['feeshort'] ?? '', fgNameMap[t['fg_id']] ?? '', t['yrlabel'] ?? '', t['feeoptional'] ?? '', t['feecategory'] ?? ''];
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
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
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
      final result = await _stagingImport(insId: insId, impType: 'FEETYPE', rows: _rows, colCount: 6);
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
        ['SCHOOL FEES', 'SCH', 'SCHOOL FEES', '2025-2026', '0', '1'],
        ['VAN FEES', 'VAN', 'VAN FEES', '2025-2026', '1', '1'],
        ['TUITION FEES', 'TUI', 'SCHOOL FEES', '2025-2026', '0', '1'],
        ['BOOK FEES', 'BK', 'SCHOOL FEES', '2025-2026', '0', '1'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Fee Name', 'Short Name', 'Fee Group', 'Year', 'Optional', 'Category'],
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
  static const _headers = ['Concession Name *'];
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
        _existingRows = concessions.map((c) => [c['condesc'] ?? '']).toList();
        _isLoadingExisting = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingExisting = false);
    }
  }

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
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
      final result = await _stagingImport(insId: insId, impType: 'CONCESSION', rows: _rows, colCount: 1);
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
        ['SC/ST'],
        ['Staff Children'],
        ['Merit Scholarship'],
        ['Sibling Discount'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Concession Name'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}

// ═══════════════════════════════════════════════
// 4. CLASS FEE DEMAND TAB
// Columns: Class *, Term, Fee Type *, Amount, Due Date, NOB, BGB, DHB
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
  static const _headers = ['Class *', 'Semester *', 'Fee Type *', 'Amount *', 'Due Date *', 'New/Old *', 'Boys/Girls *', 'Dayscholar/Hostel *'];
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
        const nobLabels = {'1': 'New', '2': 'Old', '3': 'Both'};
        const bgbLabels = {'1': 'Boys', '2': 'Girls', '3': 'Both'};
        const dhbLabels = {'1': 'Dayscholar', '2': 'Hostel', '3': 'Both'};
        _existingRows = sorted.map((r) => [
          r['cfclass'] ?? '',
          r['cfterm'] ?? '',
          r['cffeetype'] ?? '',
          r['cfamount'] ?? '',
          r['cfdduedate'] ?? '',
          nobLabels['${r['cfnob'] ?? ''}'] ?? '${r['cfnob'] ?? ''}',
          bgbLabels['${r['cfbgb'] ?? ''}'] ?? '${r['cfbgb'] ?? ''}',
          dhbLabels['${r['cfdhb'] ?? ''}'] ?? '${r['cfdhb'] ?? ''}',
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
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _isValidated = false; });
  }

  void _validate() {
    final rowErrs = <int, String>{};
    final labels = ['Class', 'Semester', 'Fee Type', 'Amount', 'Due Date', 'New/Old', 'Boys/Girls', 'Dayscholar/Hostel'];
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
      const nobMap = {'new': '1', 'old': '2', 'both': '3', '1': '1', '2': '2', '3': '3'};
      const bgbMap = {'boys': '1', 'girls': '2', 'both': '3', '1': '1', '2': '2', '3': '3'};
      const dhbMap = {'dayscholar': '1', 'hostel': '2', 'both': '3', 'day scholar': '1', '1': '1', '2': '2', '3': '3'};
      final mappedRows = _rows.map((row) {
        final mapped = List<dynamic>.from(row);
        while (mapped.length < 8) mapped.add('');
        final nob = mapped[5].toString().trim().toLowerCase();
        final bgb = mapped[6].toString().trim().toLowerCase();
        final dhb = mapped[7].toString().trim().toLowerCase();
        mapped[5] = nobMap[nob] ?? mapped[5];
        mapped[6] = bgbMap[bgb] ?? mapped[6];
        mapped[7] = dhbMap[dhb] ?? mapped[7];
        return mapped;
      }).toList();
      final result = await _stagingImport(insId: insId, impType: 'CLASSFEEDEMAND', rows: mappedRows, colCount: 8);
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
        ['I', 'I TERM', 'SCHOOL FEES', '10080', '2025-05-31', 'Both', 'Both', 'Both'],
        ['I', 'JUNE', 'TUITION FEES', '700', '2025-06-30', 'Both', 'Both', 'Both'],
        ['XII', 'I TERM', 'SCHOOL FEES', '15410', '2025-05-31', 'Both', 'Both', 'Both'],
        ['XII', 'JUNE', 'VAN FEES', '810', '2025-06-30', 'Both', 'Both', 'Both'],
      ]),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: false,
      onDismissResult: () {},
      onValidate: _rows.isNotEmpty ? _validate : null,
      onClose: _close,
      isValidated: _isValidated,
      existingRows: _existingRows,
      existingHeaders: const ['Class', 'Semester', 'Fee Type', 'Amount', 'Due Date', 'New/Old', 'Boys/Girls', 'Dayscholar/Hostel'],
      isLoadingExisting: _isLoadingExisting,
      rowErrors: _rowErrors,
    );
  }
}
