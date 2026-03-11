import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class FeeDemandApprovalScreen extends StatefulWidget {
  const FeeDemandApprovalScreen({super.key});

  @override
  State<FeeDemandApprovalScreen> createState() =>
      _FeeDemandApprovalScreenState();
}

class _FeeDemandApprovalScreenState extends State<FeeDemandApprovalScreen> {
  List<Map<String, dynamic>> _demands = [];
  bool _loading = false;
  String? _errorMsg;

  // selected by dem_id (as String)
  final Set<String> _selected = {};

  bool _approving = false;

  final _searchController = TextEditingController();
  String _searchQuery = '';
  String? _selectedClass; // null = All Classes

  final _hScrollController = ScrollController();

  // Pagination
  int _currentPage = 1;
  static const int _pageSize = 10;

  // Predefined class order
  static const _classOrder = [
    'PKG', 'LKG', 'UKG',
    'I', 'II', 'III', 'IV', 'V', 'VI',
    'VII', 'VIII', 'IX', 'X', 'XI', 'XII',
  ];

  // Unique class list sorted by predefined order (unknowns appended at end)
  List<String> get _classList {
    final present = _demands
        .map((d) => d['stuclass']?.toString() ?? '')
        .where((c) => c.isNotEmpty && c != '-')
        .toSet();
    final ordered = _classOrder.where(present.contains).toList();
    final rest = present.difference(ordered.toSet()).toList()..sort();
    return [...ordered, ...rest];
  }

  @override
  void initState() {
    super.initState();
    _loadDemands();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadDemands() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() {
      _loading = true;
      _errorMsg = null;
      _selected.clear();
    });

    try {
      final raw = await SupabaseService.getFeeDemandsPending(insId);
      // Stamp each row with a guaranteed unique key (_idx) as fallback
      final demands = raw.asMap().entries.map((e) {
        return {...e.value, '_idx': e.key.toString()};
      }).toList();
      if (mounted) {
        setState(() {
          _demands = demands;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMsg = 'Failed to load data: $e';
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filteredDemands {
    return _demands.where((d) {
      if (_selectedClass != null) {
        if ((d['stuclass']?.toString() ?? '') != _selectedClass) return false;
      }
      if (_searchQuery.isNotEmpty) {
        final admNo = d['stuadmno']?.toString().toLowerCase() ?? '';
        final name =
            (d['stuname'] ?? d['studentname'] ?? '').toString().toLowerCase();
        if (!admNo.contains(_searchQuery) && !name.contains(_searchQuery)) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  int get _totalPages {
    final count = _filteredDemands.length;
    return count == 0 ? 1 : ((count + _pageSize - 1) ~/ _pageSize);
  }

  List<Map<String, dynamic>> get _pagedDemands {
    final filtered = _filteredDemands;
    final start = (_currentPage - 1) * _pageSize;
    if (start >= filtered.length) return [];
    final end = (start + _pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  void _goToPage(int page) {
    final clamped = page.clamp(1, _totalPages);
    if (clamped != _currentPage) setState(() => _currentPage = clamped);
  }

  // Use temp_id (from tempfeedemand) with _idx fallback
  String _demKey(Map<String, dynamic> d) {
    final tempId = d['temp_id']?.toString() ?? '';
    return tempId.isNotEmpty ? tempId : (d['_idx']?.toString() ?? '');
  }

  bool _isApproved(Map<String, dynamic> d) {
    final v = d['isapproved'] ?? d['approved'];
    return v == true;
  }

  void _toggleSelectAll(bool? value) {
    final keys = _pagedDemands
        .where((d) => !_isApproved(d))
        .map(_demKey)
        .where((k) => k.isNotEmpty)
        .toSet();
    setState(() {
      if (value == true) {
        _selected.addAll(keys);
      } else {
        _selected.removeAll(keys);
      }
    });
  }

  void _toggleOne(String key, bool? value) {
    setState(() {
      if (value == true) {
        _selected.add(key);
      } else {
        _selected.remove(key);
      }
    });
  }

  Future<void> _approve() async {
    if (_selected.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: const Text('Confirm Approval',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: Text(
          'Approve ${_selected.length} fee demand${_selected.length == 1 ? '' : 's'}?',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Approve'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _approving = true);

    try {
      final tempIds = _selected
          .map((k) => int.tryParse(k))
          .whereType<int>()
          .toList();

      if (tempIds.isNotEmpty) {
        await SupabaseService.client
            .from('tempfeedemand')
            .update({'isapproved': true}).inFilter('temp_id', tempIds);
      }

      if (mounted) {
        setState(() {
          _selected.clear();
          _approving = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fee demands approved successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        _loadDemands();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _approving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error approving: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildActionBar(),
        const SizedBox(height: 16),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _errorMsg != null
                  ? _buildError()
                  : _buildTable(),
        ),
        if (!_loading && _errorMsg == null && _filteredDemands.isNotEmpty)
          _buildPagination(),
      ],
    );
  }

  Widget _buildActionBar() {
    final paged = _pagedDemands;
    final selectablePaged = paged.where((d) => !_isApproved(d)).toList();
    final allSelected = selectablePaged.isNotEmpty &&
        selectablePaged.every((d) => _selected.contains(_demKey(d)));
    final someSelected = _selected.isNotEmpty && !allSelected;

    return Row(
      children: [
        // Select All checkbox + label
        Row(
          children: [
            Checkbox(
              value: allSelected ? true : (someSelected ? null : false),
              tristate: true,
              onChanged: (v) => _toggleSelectAll(v ?? true),
              activeColor: AppColors.accent,
            ),
            const Text(
              'Select All',
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary),
            ),
          ],
        ),
        const SizedBox(width: 16),

        // Approve button
        ElevatedButton.icon(
          onPressed: _selected.isEmpty || _approving ? null : _approve,
          icon: _approving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.check_circle_outline_rounded, size: 18),
          label: Text(_approving
              ? 'Approving...'
              : 'Approve (${_selected.length})'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.accent.withValues(alpha: 0.4),
            disabledForegroundColor: Colors.white70,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),

        const SizedBox(width: 16),

        // Class filter dropdown
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String?>(
              value: _selectedClass,
              hint: const Text('All Classes',
                  style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
              style: const TextStyle(
                  fontSize: 12, color: AppColors.textPrimary),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: AppColors.textSecondary),
              isDense: true,
              onChanged: (v) => setState(() {
                _selectedClass = v;
                _selected.clear();
                _currentPage = 1;
              }),
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('All Classes',
                      style: TextStyle(fontSize: 12)),
                ),
                ..._classList.map((cls) => DropdownMenuItem<String?>(
                      value: cls,
                      child: Text('Class $cls',
                          style: const TextStyle(fontSize: 12)),
                    )),
              ],
            ),
          ),
        ),

        const Spacer(),

        // Search
        SizedBox(
          width: 260,
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              hintText: 'Search by student name or admission number...',
              hintStyle:
                  TextStyle(fontSize: 12, color: Colors.grey.shade400),
              prefixIcon: const Icon(Icons.search_rounded, size: 18),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded, size: 16),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: AppColors.border)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: AppColors.accent, width: 1.5)),
              filled: true,
              fillColor: AppColors.surface,
              isDense: true,
            ),
            style: const TextStyle(fontSize: 12),
            onChanged: (v) {
              setState(() {
                _searchQuery = v.trim().toLowerCase();
                _currentPage = 1;
              });
            },
          ),
        ),
        const SizedBox(width: 12),

        // Refresh
        IconButton(
          onPressed: _loading ? null : _loadDemands,
          icon: const Icon(Icons.refresh_rounded, size: 20),
          tooltip: 'Refresh',
          color: AppColors.textSecondary,
        ),

        // Count
        Text(
          '${_filteredDemands.length} record${_filteredDemands.length == 1 ? '' : 's'}',
          style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline_rounded,
              size: 48, color: AppColors.error),
          const SizedBox(height: 8),
          Text(_errorMsg!,
              style: const TextStyle(color: AppColors.textSecondary)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _loadDemands, child: const Text('Retry')),
        ],
      ),
    );
  }

  // ── Column width constants ────────────────────────────────────────────────
  static const double _wAdmNo = 90.0;
  static const double _wName = 150.0;
  static const double _wClass = 70.0;
  static const double _wYear = 80.0;
  static const double _wTerm = 90.0;
  static const double _wType = 100.0;
  static const double _wCategory = 90.0;
  static const double _wFeeAmt = 90.0;
  static const double _wConcession = 90.0;
  static const double _wBalance = 115.0;
  static const double _wCreatedBy = 120.0;
  static const double _wStatus = 85.0;

  static const double _colGap = 16.0; // gap between Balance Due & Created By

  // Total table width: horizontal padding(16) + checkbox(40) + all columns + gap
  static const double _tableWidth = 16 +
      40 +
      _wAdmNo +
      _wName +
      _wClass +
      _wYear +
      _wTerm +
      _wType +
      _wCategory +
      _wFeeAmt +
      _wConcession +
      _wBalance +
      _colGap +
      _wCreatedBy +
      _wStatus;

  Widget _buildTable() {
    final demands = _pagedDemands;

    if (_filteredDemands.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_rounded,
                size: 48,
                color: AppColors.textSecondary.withValues(alpha: 0.4)),
            const SizedBox(height: 8),
            Text(
              _searchQuery.isNotEmpty
                  ? 'No matching records'
                  : 'No fee demands found',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    const scrollbarH = 18.0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tableH = constraints.maxHeight - scrollbarH;
          return Column(
            children: [
              // ── Table (header + rows) ──────────────────────────────────
              SizedBox(
                height: tableH,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  controller: _hScrollController,
                  child: SizedBox(
                    width: _tableWidth,
                    child: Column(
                      children: [
                        // Header
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 11),
                          decoration: const BoxDecoration(
                            color: AppColors.primaryDark,
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(14)),
                          ),
                          child: Row(
                            children: [
                              const SizedBox(width: 40),
                              _headerCell('Adm No', _wAdmNo),
                              _headerCell('Student Name', _wName),
                              _headerCell('Class', _wClass, center: true),
                              _headerCell('Year', _wYear, center: true),
                              _headerCell('Fee Term', _wTerm, center: true),
                              _headerCell('Fee Type', _wType),
                              _headerCell('Category', _wCategory),
                              _headerCell('Fee Amount', _wFeeAmt, right: true),
                              _headerCell('Concession', _wConcession,
                                  right: true),
                              _headerCell('Balance Due', _wBalance,
                                  right: true),
                              const SizedBox(width: _colGap),
                              _headerCell('Created By', _wCreatedBy),
                              _headerCell('Status', _wStatus, center: true),
                            ],
                          ),
                        ),
                        const Divider(height: 1),
                        // Rows
                        Expanded(
                          child: ListView.separated(
                            padding: EdgeInsets.zero,
                            itemCount: demands.length,
                            separatorBuilder: (_, __) =>
                                const Divider(height: 1),
                            itemBuilder: (context, i) =>
                                _buildRow(demands[i]),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Custom Windows-style scrollbar ────────────────────────
              _buildWinScrollbar(
                  constraints.maxWidth, _tableWidth, scrollbarH),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWinScrollbar(
      double viewportW, double contentW, double barH) {
    return ListenableBuilder(
      listenable: _hScrollController,
      builder: (context, _) {
        final canScroll = contentW > viewportW;
        final maxScroll = canScroll ? contentW - viewportW : 1.0;
        final offset = (_hScrollController.hasClients && canScroll)
            ? _hScrollController.offset.clamp(0.0, maxScroll)
            : 0.0;
        final ratio = canScroll ? offset / maxScroll : 0.0;

        // Track width = viewport minus two arrow buttons
        const btnW = 18.0;
        final trackW = viewportW - btnW * 2;
        final thumbW =
            canScroll ? (viewportW / contentW * trackW).clamp(30.0, trackW) : trackW;
        final thumbLeft = ratio * (trackW - thumbW);

        void scrollBy(double delta) {
          if (!_hScrollController.hasClients) return;
          _hScrollController.jumpTo(
              (_hScrollController.offset + delta).clamp(0.0, maxScroll));
        }

        return Container(
          height: barH,
          decoration: const BoxDecoration(
            color: Color(0xFFD4D0C8),
            border: Border(top: BorderSide(color: Color(0xFF808080))),
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(13)),
          ),
          child: Row(
            children: [
              // Left arrow
              _winArrowBtn(
                  '◄', canScroll ? () => scrollBy(-60) : null, btnW, barH),

              // Track + thumb
              Expanded(
                child: GestureDetector(
                  onTapDown: (d) {
                    if (!canScroll) return;
                    final newScroll =
                        (d.localPosition.dx / trackW * maxScroll)
                            .clamp(0.0, maxScroll);
                    _hScrollController.jumpTo(newScroll);
                  },
                  child: Stack(
                    clipBehavior: Clip.hardEdge,
                    children: [
                      // Track
                      Positioned.fill(
                        child: Container(color: const Color(0xFFD4D0C8)),
                      ),
                      // Thumb
                      if (canScroll)
                        Positioned(
                          left: thumbLeft,
                          top: 1,
                          bottom: 1,
                          width: thumbW,
                          child: GestureDetector(
                            onHorizontalDragUpdate: (d) {
                              final scale =
                                  maxScroll / (trackW - thumbW);
                              scrollBy(d.delta.dx * scale);
                            },
                            child: _winThumb(thumbW),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // Right arrow
              _winArrowBtn(
                  '►', canScroll ? () => scrollBy(60) : null, btnW, barH),
            ],
          ),
        );
      },
    );
  }

  Widget _winArrowBtn(
      String label, VoidCallback? onTap, double w, double h) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: w,
        height: h,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFFD4D0C8),
          border: Border.all(color: const Color(0xFF808080), width: 0.5),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 9,
              color: onTap != null ? Colors.black87 : Colors.grey),
        ),
      ),
    );
  }

  Widget _winThumb(double w) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFD4D0C8),
        border: Border.all(color: const Color(0xFF808080), width: 0.5),
      ),
      child: Center(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(
            3,
            (_) => Container(
              width: 1,
              height: 8,
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: const BoxDecoration(
                border: Border(
                  left: BorderSide(color: Colors.white, width: 1),
                  right: BorderSide(color: Color(0xFF808080), width: 1),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerCell(String label, double width,
      {bool center = false, bool right = false}) {
    return SizedBox(
      width: width,
      child: Text(
        label,
        style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.white),
        textAlign: right
            ? TextAlign.right
            : center
                ? TextAlign.center
                : TextAlign.left,
      ),
    );
  }

  Widget _buildRow(Map<String, dynamic> d) {
    final key = _demKey(d);
    final isSelected = _selected.contains(key);

    final isApproved = _isApproved(d);

    final admNo = d['stuadmno']?.toString() ?? '-';
    // stuname comes from students join; fallback to inline field
    final name = (d['stuname'] ?? d['studentname'] ?? '').toString();
    final cls = d['stuclass']?.toString() ?? '-';
    // tempfeedemand stores year as demfeeyear (text label)
    final year = (d['demfeeyear'] ?? d['acayear'] ?? d['academicyear'] ?? d['year'] ?? '-').toString();
    // tempfeedemand: demfeeterm
    final term = (d['demfeeterm'] ?? d['feeterm'] ?? d['feetermname'] ?? d['termname'] ?? '-').toString();
    // tempfeedemand: demfeetype
    final type = (d['demfeetype'] ?? d['feetype'] ?? d['feetypename'] ?? d['typename'] ?? '-').toString();
    // tempfeedemand: demconcategory
    final category = (d['demconcategory'] ?? d['category'] ?? d['feecategory'] ?? d['categoryname'] ?? '-').toString();
    final feeAmt = (d['feeamount'] as num?)?.toDouble() ?? 0;
    final concession = (d['conamount'] as num?)?.toDouble() ?? 0;
    // use stored balancedue if available
    final balance = (d['balancedue'] as num?)?.toDouble() ?? (feeAmt - concession);
    final createdBy =
        (d['createdby'] ?? d['created_by'] ?? d['createdbyname'] ?? '-')
            .toString();
    // isapproved is boolean in tempfeedemand
    final approvedVal = d['isapproved'] ?? d['approved'];
    final status = approvedVal == true ? 'A'
        : (approvedVal == false || approvedVal == 'False' || approvedVal == 'false') ? 'P'
        : (d['approvalstatus']?.toString() ?? 'P');

    return InkWell(
      onTap: (key.isNotEmpty && !isApproved) ? () => _toggleOne(key, !isSelected) : null,
      child: Container(
        color: isApproved
            ? Colors.grey.shade50
            : isSelected
                ? AppColors.accent.withValues(alpha: 0.06)
                : null,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: isApproved ? false : isSelected,
                  onChanged: (key.isNotEmpty && !isApproved) ? (v) => _toggleOne(key, v) : null,
                  activeColor: AppColors.accent,
                ),
              ),
              // Adm No
              SizedBox(
                width: _wAdmNo,
                child: Text(admNo,
                    style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary)),
              ),
              // Student Name
              SizedBox(
                width: _wName,
                child: Text(name.isNotEmpty ? name : '-',
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ),
              // Class
              SizedBox(
                width: _wClass,
                child: Text(cls,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center),
              ),
              // Year
              SizedBox(
                width: _wYear,
                child: Text(year,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis),
              ),
              // Fee Term
              SizedBox(
                width: _wTerm,
                child: Text(term,
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis),
              ),
              // Fee Type
              SizedBox(
                width: _wType,
                child: Text(type,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              // Category
              SizedBox(
                width: _wCategory,
                child: Text(category,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              // Fee Amount
              SizedBox(
                width: _wFeeAmt,
                child: Text('₹${_fmt(feeAmt)}',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right),
              ),
              // Concession
              SizedBox(
                width: _wConcession,
                child: Text('₹${_fmt(concession)}',
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.right),
              ),
              // Balance Due
              SizedBox(
                width: _wBalance,
                child: Text('₹${_fmt(balance)}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.right),
              ),
              const SizedBox(width: _colGap),
              // Created By
              SizedBox(
                width: _wCreatedBy,
                child: Text(createdBy,
                    style: const TextStyle(fontSize: 12),
                    overflow: TextOverflow.ellipsis),
              ),
              // Status
              SizedBox(
                width: _wStatus,
                child: _statusBadge(status),
              ),
            ],
          ),
        ),
    );
  }

  Widget _buildPagination() {
    final total = _filteredDemands.length;
    final totalPages = _totalPages;
    final start = (_currentPage - 1) * _pageSize + 1;
    final end = (_currentPage * _pageSize).clamp(0, total);

    // Build list of page numbers to show (max 7 buttons with ellipsis)
    List<int?> pages = [];
    if (totalPages <= 7) {
      pages = List.generate(totalPages, (i) => i + 1);
    } else {
      pages.add(1);
      if (_currentPage > 3) pages.add(null); // ellipsis
      for (int i = (_currentPage - 1).clamp(2, totalPages - 1);
          i <= (_currentPage + 1).clamp(2, totalPages - 1);
          i++) {
        pages.add(i);
      }
      if (_currentPage < totalPages - 2) pages.add(null); // ellipsis
      pages.add(totalPages);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
      child: Row(
        children: [
          Text(
            'Showing $start–$end of $total records',
            style: const TextStyle(
                fontSize: 12, color: AppColors.textSecondary),
          ),
          const Spacer(),
          // Prev button
          _pageBtn(
            label: '‹',
            onTap: _currentPage > 1 ? () => _goToPage(_currentPage - 1) : null,
          ),
          const SizedBox(width: 4),
          // Page number buttons
          ...pages.map((p) {
            if (p == null) {
              return const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Text('…',
                    style: TextStyle(
                        fontSize: 12, color: AppColors.textSecondary)),
              );
            }
            final isActive = p == _currentPage;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: _pageBtn(
                label: '$p',
                onTap: isActive ? null : () => _goToPage(p),
                active: isActive,
              ),
            );
          }),
          const SizedBox(width: 4),
          // Next button
          _pageBtn(
            label: '›',
            onTap: _currentPage < totalPages
                ? () => _goToPage(_currentPage + 1)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _pageBtn(
      {required String label, VoidCallback? onTap, bool active = false}) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 30,
        height: 30,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? AppColors.primaryDark : AppColors.surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: active ? AppColors.primaryDark : AppColors.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: active ? FontWeight.w700 : FontWeight.w400,
            color: active
                ? Colors.white
                : onTap != null
                    ? AppColors.textPrimary
                    : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final (label, bg, fg) = switch (status.toUpperCase()) {
      'A' => ('Approved', const Color(0xFFE6F4EA), AppColors.success),
      'R' => ('Rejected', const Color(0xFFFCE8E6), AppColors.error),
      'P' || _ => ('Pending', const Color(0xFFFFF8E1), const Color(0xFFE65100)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 10, fontWeight: FontWeight.w600, color: fg),
          textAlign: TextAlign.center),
    );
  }

  String _fmt(double v) {
    return v.toStringAsFixed(0);
  }
}
