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
      if (mounted) {
        setState(() {
          _notices = List<Map<String, dynamic>>.from(data);
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
    if (_selectedNotice != null) {
      return _buildNoticeDetail(_selectedNotice!);
    }
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
            borderRadius: BorderRadius.circular(14),
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
                child: Text('${_notices.length} notices', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.accent)),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textSecondary),
                onPressed: _fetchNotices,
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
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Category icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _priorityColor(priority).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_categoryIcon(category), size: 22, color: _priorityColor(priority)),
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (priority != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _priorityColor(priority).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(priority, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _priorityColor(priority))),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(desc, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(_formatDate(date), style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                      const SizedBox(width: 12),
                      Icon(Icons.access_time_rounded, size: 12, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                      const SizedBox(width: 4),
                      Text(_timeAgo(date), style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                      if (category != null) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(category, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w500, color: AppColors.textSecondary)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, size: 20, color: AppColors.textSecondary),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
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
                  child: Text(priority, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: _priorityColor(priority))),
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
                borderRadius: BorderRadius.circular(14),
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
                          borderRadius: BorderRadius.circular(14),
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
                                Text(_formatDate(date), style: const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                                const SizedBox(width: 8),
                                Text(_timeAgo(date), style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.6))),
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

                  if (createdBy != null && createdBy.isNotEmpty) ...[
                    const SizedBox(height: 24),
                    const Divider(color: AppColors.border),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Icon(Icons.person_rounded, size: 16, color: AppColors.textSecondary),
                        const SizedBox(width: 6),
                        Text('Posted by: ', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
                        Text(createdBy, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
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
}
