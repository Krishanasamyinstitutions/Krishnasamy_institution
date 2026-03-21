import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class NoticesScreen extends StatefulWidget {
  const NoticesScreen({super.key});

  @override
  State<NoticesScreen> createState() => _NoticesScreenState();
}

class _NoticesScreenState extends State<NoticesScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _notices = [];
  Map<String, dynamic>? _selectedNotice;
  bool _showCreateForm = false;

  @override
  void initState() {
    super.initState();
    _fetchNotices();
  }

  Future<void> _fetchNotices() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.client
          .from('notice')
          .select()
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .order('createdat', ascending: false);

      final all = List<Map<String, dynamic>>.from(data);
      final today = DateTime.now();
      final todayStr = '${today.year}-${today.month.toString().padLeft(2,'0')}-${today.day.toString().padLeft(2,'0')}';

      // Auto-expire notices past their todate
      final expiredIds = all
          .where((n) {
            final toDate = n['noticetodate']?.toString();
            return toDate != null && toDate.isNotEmpty && toDate.compareTo(todayStr) < 0;
          })
          .map((n) => n['notice_id'] ?? n['id'])
          .where((id) => id != null)
          .toList();

      if (expiredIds.isNotEmpty) {
        try {
          await SupabaseService.client
              .from('notice')
              .update({'activestatus': 9})
              .inFilter('notice_id', expiredIds);
        } catch (_) {}
      }

      final active = all.where((n) {
        final toDate = n['noticetodate']?.toString();
        if (toDate == null || toDate.isEmpty) return true;
        return toDate.compareTo(todayStr) >= 0;
      }).toList();

      if (mounted) {
        setState(() {
          _notices = active;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error fetching notices: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return '-';
    try {
      final dt = DateTime.parse(dateStr);
      return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
    } catch (_) {
      return dateStr;
    }
  }

  String _timeAgo(String? dateStr) {
    if (dateStr == null) return '';
    try {
      final dt = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(dt);
      if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} months ago';
      if (diff.inDays > 0) return '${diff.inDays} days ago';
      if (diff.inHours > 0) return '${diff.inHours} hours ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes} min ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }

  Color _priorityColor(String? priority) {
    switch (priority?.toLowerCase()) {
      case 'high':
      case 'urgent':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.accent;
    }
  }

  IconData _categoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'exam':
        return Icons.quiz_rounded;
      case 'holiday':
        return Icons.beach_access_rounded;
      case 'event':
        return Icons.event_rounded;
      case 'fee':
        return Icons.payments_rounded;
      case 'result':
        return Icons.assessment_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_showCreateForm) return _buildCreateForm();
    if (_selectedNotice != null) return _buildNoticeDetail(_selectedNotice!);
    return _buildNoticeList();
  }

  Widget _buildNoticeList() {
    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              const Text('Notices & Announcements', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('${_notices.length} notices', style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.accent)),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: () => setState(() => _showCreateForm = true),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Create Notice', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  elevation: 0,
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: _fetchNotices,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _notices.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      padding: EdgeInsets.zero,
                      itemCount: _notices.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => _buildNoticeCard(_notices[index]),
                    ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_off_rounded, size: 64, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 16),
          const Text('No notices yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
          const SizedBox(height: 6),
          const Text('Notices and announcements will appear here', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            onPressed: () => setState(() => _showCreateForm = true),
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text('Create First Notice'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoticeCard(Map<String, dynamic> notice) {
    final title = notice['noticetitle']?.toString() ?? notice['title']?.toString() ?? 'Untitled';
    final desc = notice['noticedesc']?.toString() ?? notice['description']?.toString() ?? '';
    final date = notice['createdat']?.toString() ?? notice['noticedate']?.toString();
    final priority = notice['noticepriority']?.toString() ?? notice['priority']?.toString();
    final category = notice['noticecategory']?.toString() ?? notice['category']?.toString();

    return InkWell(
      onTap: () => setState(() => _selectedNotice = notice),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _priorityColor(priority).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_categoryIcon(category), size: 20, color: _priorityColor(priority)),
            ),
            const SizedBox(width: 12),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (priority != null)
                        Container(
                          margin: const EdgeInsets.only(left: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _priorityColor(priority).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(priority, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _priorityColor(priority))),
                        ),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right_rounded, size: 18, color: AppColors.textSecondary),
                    ],
                  ),
                  if (desc.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(desc, style: const TextStyle(fontSize: 13, color: AppColors.textSecondary, height: 1.3), maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 11, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(_formatDate(date), style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                      const SizedBox(width: 10),
                      Icon(Icons.access_time_rounded, size: 11, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(_timeAgo(date), style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                      if (category != null) ...[
                        const SizedBox(width: 10),
                        Icon(Icons.label_rounded, size: 11, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                        const SizedBox(width: 4),
                        Text(category, style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoticeDetail(Map<String, dynamic> notice) {
    final title = notice['noticetitle']?.toString() ?? notice['title']?.toString() ?? 'Untitled';
    final desc = notice['noticedesc']?.toString() ?? notice['description']?.toString() ?? '';
    final date = notice['createdat']?.toString() ?? notice['noticedate']?.toString();
    final priority = notice['noticepriority']?.toString() ?? notice['priority']?.toString();
    final category = notice['noticecategory']?.toString() ?? notice['category']?.toString();
    final createdBy = notice['createdby']?.toString();
    final target = notice['noticetarget']?.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: () => setState(() => _selectedNotice = null),
                tooltip: 'Back to notices',
              ),
              const SizedBox(width: 4),
              const Text('Notice Details', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (priority != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _priorityColor(priority).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(priority, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: _priorityColor(priority))),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Detail card
        Expanded(
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title row
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: _priorityColor(priority).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(_categoryIcon(category), size: 24, color: _priorityColor(priority)),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (category != null) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(category, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.accent)),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Text(_formatDate(date), style: const TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                                const SizedBox(width: 8),
                                Text(_timeAgo(date), style: TextStyle(fontSize: 13, color: AppColors.textSecondary.withValues(alpha: 0.6))),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 32, color: AppColors.border),

                  // Description
                  Text(desc, style: const TextStyle(fontSize: 14, height: 1.7, color: AppColors.textPrimary)),

                  if (target != null && target.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        const Icon(Icons.people_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        const Text('Target: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Text(target, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],

                  if (createdBy != null && createdBy.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        const Text('Posted by: ', style: TextStyle(fontSize: 13, color: AppColors.textSecondary)),
                        Text(createdBy, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ─── Create Notice Form ──────────────────────────────────────────────────────

  Widget _buildCreateForm() {
    return _CreateNoticeForm(
      onBack: () => setState(() => _showCreateForm = false),
      onCreated: () {
        setState(() => _showCreateForm = false);
        _fetchNotices();
      },
    );
  }
}

// ─── Create Notice Form Widget ─────────────────────────────────────────────────

class _CreateNoticeForm extends StatefulWidget {
  final VoidCallback onBack;
  final VoidCallback onCreated;

  const _CreateNoticeForm({required this.onBack, required this.onCreated});

  @override
  State<_CreateNoticeForm> createState() => _CreateNoticeFormState();
}

class _CreateNoticeFormState extends State<_CreateNoticeForm> {
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  String _priority = 'Normal';
  String _category = 'General';
  DateTime? _fromDate;
  DateTime? _toDate;
  String _targetType = 'All Students';
  List<String> _selectedClasses = [];
  List<String> _availableClasses = [];
  bool _isLoadingClasses = false;
  bool _isSending = false;

  static const _priorities = ['Normal', 'Medium', 'High', 'Urgent'];
  static const _categories = ['General', 'Exam', 'Holiday', 'Event', 'Fee', 'Result'];
  static const _targetTypes = ['All Students', 'Specific Classes', 'Staff'];

  @override
  void initState() {
    super.initState();
    _loadClasses();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _pickDate(bool isFrom) async {
    final initial = isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now().add(const Duration(days: 7)));
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          if (_toDate != null && _toDate!.isBefore(picked)) _toDate = null;
        } else {
          _toDate = picked;
        }
      });
    }
  }

  Future<void> _loadClasses() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoadingClasses = true);
    try {
      final classes = await SupabaseService.getClasses(insId);
      if (mounted) setState(() { _availableClasses = classes; _isLoadingClasses = false; });
    } catch (e) {
      debugPrint('Error loading classes: $e');
      if (mounted) setState(() => _isLoadingClasses = false);
    }
  }

  Future<void> _submitNotice() async {
    final title = _titleController.text.trim();
    final desc = _descController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a notice title'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (desc.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a notice description'), backgroundColor: AppColors.error),
      );
      return;
    }
    if (_targetType == 'Specific Classes' && _selectedClasses.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one class'), backgroundColor: AppColors.error),
      );
      return;
    }

    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    final userName = auth.userName ?? 'Admin';
    if (insId == null) return;

    setState(() => _isSending = true);

    try {
      final targetLabel = _targetType == 'All Students'
          ? 'All Students'
          : _targetType == 'Staff'
              ? 'Staff'
              : _selectedClasses.join(', ');

      // Insert notice
      await SupabaseService.client.from('notice').insert({
        'ins_id': insId,
        'noticetitle': title,
        'noticedesc': desc,
        'noticepriority': _priority,
        'noticecategory': _category,
        'noticetarget': targetLabel,
        'noticefromdate': _fromDate?.toIso8601String(),
        'noticetodate': _toDate?.toIso8601String(),
        'createdby': userName,
        'createdat': DateTime.now().toIso8601String(),
        'noticefromdate': _fromDate?.toIso8601String().split('T').first,
        'noticetodate': _toDate?.toIso8601String().split('T').first,
        'activestatus': 1,
      });

      // Send notification to targeted audience
      List<Map<String, dynamic>> targetStudents = [];
      if (_targetType == 'Staff') {
        // Send to institution users (staff)
        final users = await SupabaseService.getInstitutionUsers(insId);
        if (users.isNotEmpty) {
          final staffNotifications = users.map((u) => {
            'ins_id': insId,
            'stu_id': null,
            'notititle': title,
            'notibody': desc,
            'notitype': 'notice',
            'isread': 0,
            'activestatus': 1,
          }).toList();
          await SupabaseService.client.from('notification').insert(staffNotifications);
        }
      } else if (_targetType == 'All Students') {
        final allStudents = await SupabaseService.getStudents(insId);
        targetStudents = allStudents.map((s) => {'stu_id': s.stuId, 'stuname': s.stuname}).toList();
      } else {
        final allStudents = await SupabaseService.getStudents(insId);
        targetStudents = allStudents
            .where((s) => _selectedClasses.contains(s.stuclass))
            .map((s) => {'stu_id': s.stuId, 'stuname': s.stuname})
            .toList();
      }

      // Batch insert notifications for each student
      if (targetStudents.isNotEmpty) {
        final notifications = targetStudents.map((s) => {
          'ins_id': insId,
          'stu_id': s['stu_id'],
          'notititle': title,
          'notibody': desc,
          'notitype': 'notice',
          'isread': 0,
          'createdat': DateTime.now().toIso8601String(),
          'activestatus': 1,
        }).toList();

        // Insert in batches of 500
        for (var i = 0; i < notifications.length; i += 500) {
          final batch = notifications.sublist(i, i + 500 > notifications.length ? notifications.length : i + 500);
          try {
            await SupabaseService.client.from('notification').insert(batch);
          } catch (e) {
            debugPrint('Error inserting notification batch: $e');
          }
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Notice sent to ${targetStudents.length} students'),
            backgroundColor: AppColors.accent,
          ),
        );
        widget.onCreated();
      }
    } catch (e) {
      debugPrint('Error creating notice: $e');
      if (mounted) {
        setState(() => _isSending = false);
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
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_rounded, size: 20),
                onPressed: widget.onBack,
                tooltip: 'Back to notices',
              ),
              const SizedBox(width: 4),
              const Icon(Icons.edit_notifications_rounded, size: 20, color: AppColors.accent),
              const SizedBox(width: 8),
              const Text('Create Notice', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              const Spacer(),
              if (_isSending)
                const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
              else
                ElevatedButton.icon(
                  onPressed: _submitNotice,
                  icon: const Icon(Icons.send_rounded, size: 16),
                  label: const Text('Send Notice', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Form
        Expanded(
          child: SingleChildScrollView(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title
                  const Text('Notice Title', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      hintText: 'Enter notice title...',
                      hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),

                  // Target Audience
                  const Text('Target Audience', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: _targetTypes.map((t) {
                      final isSelected = _targetType == t;
                      return Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: GestureDetector(
                          onTap: () => setState(() {
                            _targetType = t;
                            if (t != 'Specific Classes') _selectedClasses.clear();
                          }),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected ? AppColors.accent : Colors.white,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  t == 'All Students' ? Icons.groups_rounded : t == 'Staff' ? Icons.badge_rounded : Icons.class_rounded,
                                  size: 16,
                                  color: isSelected ? Colors.white : AppColors.textSecondary,
                                ),
                                const SizedBox(width: 6),
                                Text(t, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? Colors.white : AppColors.textSecondary)),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // Class selection (shown when Specific Classes is selected)
                  if (_targetType == 'Specific Classes') ...[
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Text('Select Classes', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                              const Spacer(),
                              if (_selectedClasses.isNotEmpty)
                                GestureDetector(
                                  onTap: () => setState(() => _selectedClasses.clear()),
                                  child: const Text('Clear all', style: TextStyle(fontSize: 13, color: AppColors.error, fontWeight: FontWeight.w500)),
                                ),
                              const SizedBox(width: 12),
                              GestureDetector(
                                onTap: () => setState(() => _selectedClasses = List.from(_availableClasses)),
                                child: const Text('Select all', style: TextStyle(fontSize: 13, color: AppColors.accent, fontWeight: FontWeight.w500)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _isLoadingClasses
                              ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                              : Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _availableClasses.map((cls) {
                                    final isSelected = _selectedClasses.contains(cls);
                                    return GestureDetector(
                                      onTap: () {
                                        setState(() {
                                          if (isSelected) {
                                            _selectedClasses.remove(cls);
                                          } else {
                                            _selectedClasses.add(cls);
                                          }
                                        });
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: isSelected ? AppColors.accent.withValues(alpha: 0.1) : Colors.white,
                                          borderRadius: BorderRadius.circular(8),
                                          border: Border.all(color: isSelected ? AppColors.accent : AppColors.border),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isSelected ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                                              size: 16,
                                              color: isSelected ? AppColors.accent : AppColors.textSecondary,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(cls, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isSelected ? AppColors.accent : AppColors.textPrimary)),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                          if (_selectedClasses.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Text('${_selectedClasses.length} class${_selectedClasses.length > 1 ? 'es' : ''} selected',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: AppColors.accent)),
                          ],
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),

                  // Description
                  const Text('Description', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _descController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      hintText: 'Enter notice description...',
                      hintStyle: TextStyle(color: AppColors.textSecondary.withValues(alpha: 0.5), fontSize: 13),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: AppColors.accent, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 20),

                  // Priority & Category row
                  Row(
                    children: [
                      Expanded(child: _buildDropdown('Priority', _priority, _priorities, (v) => setState(() => _priority = v!))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDropdown('Category', _category, _categories, (v) => setState(() => _category = v!))),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // From Date & To Date row
                  Row(
                    children: [
                      Expanded(child: _buildDatePicker('From Date', _fromDate, (d) => setState(() => _fromDate = d))),
                      const SizedBox(width: 16),
                      Expanded(child: _buildDatePicker('To Date', _toDate, (d) => setState(() => _toDate = d))),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // From / To Date
                  const Text('Notice Period', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _pickDate(true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: _fromDate != null ? AppColors.accent : AppColors.border),
                              borderRadius: BorderRadius.circular(10),
                              color: AppColors.surface,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today_rounded, size: 15, color: _fromDate != null ? AppColors.accent : AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Text(
                                  _fromDate != null
                                      ? '${_fromDate!.day.toString().padLeft(2,'0')}/${_fromDate!.month.toString().padLeft(2,'0')}/${_fromDate!.year}'
                                      : 'From Date',
                                  style: TextStyle(fontSize: 13, color: _fromDate != null ? AppColors.textPrimary : AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Text('—', style: TextStyle(color: AppColors.textSecondary)),
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _pickDate(false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: _toDate != null ? AppColors.error : AppColors.border),
                              borderRadius: BorderRadius.circular(10),
                              color: AppColors.surface,
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.event_busy_rounded, size: 15, color: _toDate != null ? AppColors.error : AppColors.textSecondary),
                                const SizedBox(width: 8),
                                Text(
                                  _toDate != null
                                      ? '${_toDate!.day.toString().padLeft(2,'0')}/${_toDate!.month.toString().padLeft(2,'0')}/${_toDate!.year}'
                                      : 'To Date (Auto-expire)',
                                  style: TextStyle(fontSize: 13, color: _toDate != null ? AppColors.textPrimary : AppColors.textSecondary),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Notice will be automatically removed after the To Date.',
                    style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
                  ),

                  const SizedBox(height: 28),

                  // Preview section
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.accent.withValues(alpha: 0.15)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.preview_rounded, size: 16, color: AppColors.accent),
                            const SizedBox(width: 6),
                            const Text('Preview', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.accent)),
                          ],
                        ),
                        const Divider(height: 20, color: AppColors.border),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: _priorityColorForPreview.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(_priority, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _priorityColorForPreview)),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.surface,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(_category, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                            ),
                            const SizedBox(width: 8),
                            Icon(Icons.people_rounded, size: 12, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                            const SizedBox(width: 4),
                            Text(
                              _targetType == 'All Students' ? 'All Students' : _targetType == 'Staff' ? 'Staff' : '${_selectedClasses.length} classes',
                              style: TextStyle(fontSize: 13, color: AppColors.textSecondary.withValues(alpha: 0.7)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _titleController.text.isEmpty ? 'Notice title...' : _titleController.text,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: _titleController.text.isEmpty ? AppColors.textSecondary.withValues(alpha: 0.4) : AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _descController.text.isEmpty ? 'Notice description...' : _descController.text,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.4,
                            color: _descController.text.isEmpty ? AppColors.textSecondary.withValues(alpha: 0.4) : AppColors.textSecondary,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Color get _priorityColorForPreview {
    switch (_priority.toLowerCase()) {
      case 'high':
      case 'urgent':
        return AppColors.error;
      case 'medium':
        return AppColors.warning;
      default:
        return AppColors.accent;
    }
  }

  String _formatDateDisplay(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  Widget _buildDatePicker(String label, DateTime? selectedDate, ValueChanged<DateTime> onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: selectedDate ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked != null) onSelected(picked);
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    selectedDate != null ? _formatDateDisplay(selectedDate) : 'Select date...',
                    style: TextStyle(
                      fontSize: 13,
                      color: selectedDate != null ? AppColors.textPrimary : AppColors.textSecondary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
                Icon(Icons.calendar_today_rounded, size: 16, color: AppColors.textSecondary.withValues(alpha: 0.6)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown(String label, String value, List<String> items, ValueChanged<String?> onChanged) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
              items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
