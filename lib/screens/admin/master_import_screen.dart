import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as xl;
import '../../utils/app_theme.dart';
import '../../services/supabase_service.dart';
import 'package:provider/provider.dart';
import '../../utils/auth_provider.dart';

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
    _tabCtrl = TabController(length: 4, vsync: this);
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
        Container(
          color: AppColors.surfaceCard,
          child: TabBar(
            controller: _tabCtrl,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textSecondary,
            indicatorColor: AppColors.accent,
            tabs: const [
              Tab(text: 'Fee Group'),
              Tab(text: 'Fee Type'),
              Tab(text: 'Concession'),
              Tab(text: 'Class Fee Demand'),
            ],
          ),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabCtrl,
            children: const [
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
// GENERIC HELPERS
// ═══════════════════════════════════════════════

List<List<dynamic>> _parseExcel(String path) {
  final bytes = File(path).readAsBytesSync();
  final excel = xl.Excel.decodeBytes(bytes);
  final sheet = excel.tables[excel.tables.keys.first]!;
  return sheet.rows.map((r) => r.map((c) => c?.value?.toString().trim() ?? '').toList()).toList();
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
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
    alignment: center ? Alignment.center : Alignment.centerLeft,
    child: Text(text, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
  );
  return width != null ? SizedBox(width: width, child: child) : Expanded(flex: flex, child: child);
}

Widget _gridHeaderDivider() {
  return Container(width: 1, height: 36, color: Colors.white.withValues(alpha: 0.15));
}

Widget _gridDataCell(String text, {double? width, int flex = 1, bool center = false}) {
  final child = Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
    alignment: center ? Alignment.center : Alignment.centerLeft,
    decoration: BoxDecoration(
      border: Border(right: BorderSide(color: AppColors.border.withValues(alpha: 0.3))),
    ),
    child: Text(text, style: const TextStyle(fontSize: 11, color: AppColors.textPrimary), overflow: TextOverflow.ellipsis),
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
}) {
  return Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: AppColors.border),
    ),
    margin: const EdgeInsets.all(16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title bar
        Row(
          children: [
            Icon(Icons.upload_file_rounded, size: 20, color: AppColors.accent),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const Spacer(),
            if (fileName != null)
              Text(fileName, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              onPressed: onBrowse,
              icon: const Icon(Icons.folder_open_rounded, size: 16),
              label: const Text('Browse'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: onTemplate,
              icon: const Icon(Icons.table_chart_rounded, size: 16),
              label: const Text('Move to Excel'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF217346),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        if (showResult) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: errors.isEmpty ? const Color(0xFFE6F4EA) : const Color(0xFFFCE4E4),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(errors.isEmpty ? Icons.check_circle : Icons.warning_rounded, color: errors.isEmpty ? AppColors.success : AppColors.error, size: 18),
                    const SizedBox(width: 8),
                    Text('$imported imported, $skipped skipped', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    const Spacer(),
                    IconButton(icon: const Icon(Icons.close, size: 16), onPressed: onDismissResult, padding: EdgeInsets.zero, constraints: const BoxConstraints()),
                  ],
                ),
                if (errors.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...errors.take(5).map((e) => Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(e, style: const TextStyle(fontSize: 11, color: Colors.red)),
                  )),
                  if (errors.length > 5) Text('... and ${errors.length - 5} more errors', style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),

        // Data grid
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              children: [
                // Header row
                Container(
                  decoration: const BoxDecoration(
                    color: Color(0xFF1B2A4A),
                    borderRadius: BorderRadius.only(
                      topLeft: Radius.circular(7),
                      topRight: Radius.circular(7),
                    ),
                  ),
                  child: Row(
                    children: [
                      _gridHeaderCell('S.No', width: 60, center: true),
                      ...headers.expand((h) => [
                        _gridHeaderDivider(),
                        _gridHeaderCell(h),
                      ]),
                    ],
                  ),
                ),
                // Data rows
                Expanded(
                  child: rows.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.grid_on_rounded, size: 48, color: AppColors.textSecondary.withValues(alpha: 0.3)),
                              const SizedBox(height: 8),
                              const Text('No data loaded', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                              const SizedBox(height: 4),
                              const Text('Click Browse to load a CSV or Excel file', style: TextStyle(fontSize: 11, color: AppColors.textSecondary)),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: rows.length,
                          itemBuilder: (_, i) {
                            return Container(
                              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 0),
                              color: i.isEven ? Colors.white : AppColors.surface,
                              child: Row(
                                children: [
                                  _gridDataCell('${i + 1}', width: 60, center: true),
                                  ...List.generate(headers.length, (j) =>
                                    _gridDataCell(j < rows[i].length ? rows[i][j].toString() : ''),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Bottom bar
        Row(
          children: [
            Text('${rows.length} rows', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
            const Spacer(),
            ElevatedButton.icon(
              onPressed: saving ? null : onSave,
              icon: saving
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_rounded, size: 16),
              label: Text(saving ? 'Saving...' : 'Save'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

// ═══════════════════════════════════════════════
// Helper: resolve yrlabel → yr_id
// ═══════════════════════════════════════════════
Future<Map<String, int>> _buildYearMap(int insId) async {
  final years = await SupabaseService.getYears(insId);
  final map = <String, int>{};
  for (final y in years) {
    map[y['yrlabel'].toString().trim()] = y['yr_id'] as int;
  }
  return map;
}

// ═══════════════════════════════════════════════
// 1. FEE GROUP TAB
// Columns: Group Name *, Year *, Bank ID
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
  bool _showResult = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  static const _headers = ['Group Name *', 'Year *', 'Bank ID'];

  @override
  bool get wantKeepAlive => true;

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _showResult = false; });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    final yearMap = await _buildYearMap(insId);

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final fgdesc = row.isNotEmpty ? row[0].toString().trim() : '';
      final yrLabel = row.length > 1 ? row[1].toString().trim() : '';
      final banId = row.length > 2 ? int.tryParse(row[2].toString().trim()) : null;
      if (fgdesc.isEmpty) { _skipped++; _errors.add('Row ${i + 1}: Empty group name'); continue; }
      final yrId = yearMap[yrLabel];
      if (yrId == null) { _skipped++; _errors.add('Row ${i + 1}: Year "$yrLabel" not found'); continue; }
      try {
        await SupabaseService.client.from('feegroup').insert({
          'fgdesc': fgdesc,
          'ban_id': banId,
          'ins_id': insId,
          'yr_id': yrId,
          'yrlabel': yrLabel,
          'activestatus': 1,
        });
        _imported++;
      } catch (e) {
        _skipped++; _errors.add('Row ${i + 1}: $e');
      }
    }
    setState(() { _saving = false; _showResult = true; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Fee Groups',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty ? _save : null,
      onTemplate: () => _exportTemplate('Fee Group', _headers),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: _showResult,
      onDismissResult: () => setState(() => _showResult = false),
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
  bool _showResult = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  static const _headers = ['Fee Name *', 'Short Name *', 'Fee Group *', 'Year *', 'Optional', 'Category'];

  @override
  bool get wantKeepAlive => true;

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _showResult = false; });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;
    final yearMap = await _buildYearMap(insId);

    // Fetch fee groups for lookup
    final fgList = await SupabaseService.client.from('feegroup').select('fg_id, fgdesc').eq('ins_id', insId).eq('activestatus', 1);
    final fgMap = <String, int>{};
    for (final fg in fgList) {
      fgMap[fg['fgdesc'].toString().toUpperCase().trim()] = fg['fg_id'] as int;
    }

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final feedesc = row.isNotEmpty ? row[0].toString().trim() : '';
      final feeshort = row.length > 1 ? row[1].toString().trim() : '';
      final fgName = row.length > 2 ? row[2].toString().trim().toUpperCase() : '';
      final yrLabel = row.length > 3 ? row[3].toString().trim() : '';
      final feeoptional = row.length > 4 ? int.tryParse(row[4].toString().trim()) : null;
      final feecategory = row.length > 5 ? int.tryParse(row[5].toString().trim()) : null;

      if (feedesc.isEmpty || feeshort.isEmpty) { _skipped++; _errors.add('Row ${i + 1}: Missing fee name or short name'); continue; }
      final fgId = fgMap[fgName];
      if (fgId == null) { _skipped++; _errors.add('Row ${i + 1}: Fee group "$fgName" not found'); continue; }
      final yrId = yearMap[yrLabel];
      if (yrId == null) { _skipped++; _errors.add('Row ${i + 1}: Year "$yrLabel" not found'); continue; }
      try {
        await SupabaseService.client.from('feetype').insert({
          'feedesc': feedesc,
          'feeshort': feeshort,
          'fg_id': fgId,
          'feeoptional': feeoptional,
          'feecategory': feecategory,
          'yr_id': yrId,
          'yrlabel': yrLabel,
          'activestatus': 1,
        });
        _imported++;
      } catch (e) {
        _skipped++; _errors.add('Row ${i + 1}: $e');
      }
    }
    setState(() { _saving = false; _showResult = true; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Fee Types',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty ? _save : null,
      onTemplate: () => _exportTemplate('Fee Type', _headers),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: _showResult,
      onDismissResult: () => setState(() => _showResult = false),
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
  bool _showResult = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  static const _headers = ['Concession Name *', 'Order'];

  @override
  bool get wantKeepAlive => true;

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _showResult = false; });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final insId = auth.insId ?? 0;

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final condesc = row.isNotEmpty ? row[0].toString().trim() : '';
      final ordid = row.length > 1 ? int.tryParse(row[1].toString().trim()) : null;
      if (condesc.isEmpty) { _skipped++; _errors.add('Row ${i + 1}: Empty concession name'); continue; }
      try {
        await SupabaseService.client.from('concessioncategory').insert({
          'condesc': condesc,
          'ins_id': insId,
          'ordid': ordid,
          'activestatus': 1,
        });
        _imported++;
      } catch (e) {
        _skipped++; _errors.add('Row ${i + 1}: $e');
      }
    }
    setState(() { _saving = false; _showResult = true; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Concessions',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty ? _save : null,
      onTemplate: () => _exportTemplate('Concession', _headers),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: _showResult,
      onDismissResult: () => setState(() => _showResult = false),
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
  bool _showResult = false;
  int _imported = 0, _skipped = 0;
  List<String> _errors = [];
  static const _headers = ['Class *', 'Term', 'Fee Type *', 'Amount', 'Due Date', 'NOB', 'BGB', 'DHB'];

  @override
  bool get wantKeepAlive => true;

  Future<void> _browse() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['xlsx', 'xls', 'csv']);
    if (result == null) return;
    final parsed = _parseExcel(result.files.single.path!);
    if (parsed.length < 2) return;
    setState(() { _fileName = result.files.single.name; _rows = parsed.sublist(1); _showResult = false; });
  }

  Future<void> _save() async {
    if (_rows.isEmpty) return;
    setState(() { _saving = true; _errors = []; _imported = 0; _skipped = 0; });

    for (int i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final cfclass = row.isNotEmpty ? row[0].toString().trim() : '';
      final cfterm = row.length > 1 ? row[1].toString().trim() : '';
      final cffeetype = row.length > 2 ? row[2].toString().trim() : '';
      final cfamount = row.length > 3 ? double.tryParse(row[3].toString().trim()) : null;
      final dueDateStr = row.length > 4 ? row[4].toString().trim() : '';
      final cfnob = row.length > 5 ? int.tryParse(row[5].toString().trim()) : null;
      final cfbgb = row.length > 6 ? int.tryParse(row[6].toString().trim()) : null;
      final cfdhb = row.length > 7 ? int.tryParse(row[7].toString().trim()) : null;

      if (cfclass.isEmpty || cffeetype.isEmpty) { _skipped++; _errors.add('Row ${i + 1}: Missing class or fee type'); continue; }

      final data = <String, dynamic>{
        'cfclass': cfclass,
        'cfterm': cfterm.isNotEmpty ? cfterm : null,
        'cffeetype': cffeetype,
        'cfamount': cfamount,
        'cfnob': cfnob,
        'cfbgb': cfbgb,
        'cfdhb': cfdhb,
      };
      if (dueDateStr.isNotEmpty) {
        try { data['cfdduedate'] = DateTime.parse(dueDateStr).toIso8601String().split('T').first; } catch (_) {}
      }

      try {
        await SupabaseService.client.from('classfeedemand').insert(data);
        _imported++;
      } catch (e) {
        _skipped++; _errors.add('Row ${i + 1}: $e');
      }
    }
    setState(() { _saving = false; _showResult = true; });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildImportCard(
      title: 'Import Class Fee Demand',
      headers: _headers,
      rows: _rows.map((r) => List.generate(_headers.length, (j) => j < r.length ? r[j] : '')).toList(),
      onBrowse: _browse,
      onSave: _rows.isNotEmpty ? _save : null,
      onTemplate: () => _exportTemplate('Class Fee Demand', _headers),
      saving: _saving, fileName: _fileName, imported: _imported, skipped: _skipped, errors: _errors, showResult: _showResult,
      onDismissResult: () => setState(() => _showResult = false),
    );
  }
}
