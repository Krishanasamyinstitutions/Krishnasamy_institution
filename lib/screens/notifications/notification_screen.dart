import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class NotificationScreen extends StatefulWidget {
  final VoidCallback? onReadChanged;
  const NotificationScreen({super.key, this.onReadChanged});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _notifications = [];
  String _filter = 'All'; // All, Unread, Read
  Map<String, dynamic>? _selectedNotification;

  @override
  void initState() {
    super.initState();
    _fetchNotifications();
  }

  Future<void> _fetchNotifications() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;

    setState(() => _isLoading = true);
    try {
      final data = await SupabaseService.client
          .from('notification')
          .select()
          .eq('ins_id', insId)
          .eq('activestatus', 1)
          .isFilter('stu_id', null)
          .order('createdat', ascending: false);
      final allNotifications = List<Map<String, dynamic>>.from(data);
      // Deduplicate: group by title+body+type, show unique notifications only
      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      // Track which unique entries are read
      final Map<String, bool> readStatus = {};
      for (final n in allNotifications) {
        final key = '${n['notititle']}|${n['notibody']}|${n['notitype']}';
        final isRead = n['isread'] == true || n['isread'] == 1;
        if (!seen.contains(key)) {
          seen.add(key);
          unique.add(n);
          readStatus[key] = isRead;
        } else {
          // If unique entry is read but this duplicate is unread, mark it as read in DB
          if (readStatus[key] == true && !isRead) {
            final id = n['noti_id'];
            if (id != null) {
              SupabaseService.client.from('notification').update({'isread': 1}).eq('noti_id', id).then((_) {});
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _notifications = unique;
          _isLoading = false;
        });
        // Refresh dashboard badge after syncing duplicates
        widget.onReadChanged?.call();
      }
    } catch (e) {
      debugPrint('Error fetching notifications: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  List<Map<String, dynamic>> get _filteredNotifications {
    if (_filter == 'Unread') return _notifications.where((n) => n['isread'] != true && n['isread'] != 1).toList();
    if (_filter == 'Read') return _notifications.where((n) => n['isread'] == true || n['isread'] == 1).toList();
    return _notifications;
  }

  int get _unreadCount => _notifications.where((n) => n['isread'] != true && n['isread'] != 1).length;

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
      if (diff.inDays > 30) return '${(diff.inDays / 30).floor()}mo ago';
      if (diff.inDays > 0) return '${diff.inDays}d ago';
      if (diff.inHours > 0) return '${diff.inHours}h ago';
      if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
      return 'Just now';
    } catch (_) {
      return '';
    }
  }

  IconData _typeIcon(String? type) {
    switch (type?.toLowerCase()) {
      case 'fee':
      case 'payment':
        return Icons.payments_rounded;
      case 'exam':
        return Icons.quiz_rounded;
      case 'attendance':
        return Icons.fact_check_rounded;
      case 'notice':
        return Icons.campaign_rounded;
      case 'alert':
        return Icons.warning_rounded;
      case 'message':
        return Icons.message_rounded;
      default:
        return Icons.notifications_rounded;
    }
  }

  Color _typeColor(String? type) {
    switch (type?.toLowerCase()) {
      case 'fee':
      case 'payment':
        return AppColors.accent;
      case 'alert':
        return AppColors.error;
      case 'exam':
        return Colors.orange;
      case 'attendance':
        return Colors.purple;
      case 'notice':
        return Colors.blue;
      default:
        return AppColors.textSecondary;
    }
  }

  Future<void> _markAsRead(Map<String, dynamic> notif) async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      // Mark all duplicates with same title+body+type as read
      var query = SupabaseService.client.from('notification').update({'isread': 1}).eq('ins_id', insId).eq('activestatus', 1);
      final title = notif['notititle']?.toString();
      final body = notif['notibody']?.toString();
      final type = notif['notitype']?.toString();
      if (title != null) query = query.eq('notititle', title);
      if (body != null) query = query.eq('notibody', body);
      if (type != null) query = query.eq('notitype', type);
      await query;
      await _fetchNotifications();
      widget.onReadChanged?.call();
    } catch (e) {
      debugPrint('Error marking as read: $e');
    }
  }

  Future<void> _markAllAsRead() async {
    final auth = context.read<AuthProvider>();
    final insId = auth.insId;
    if (insId == null) return;
    try {
      await SupabaseService.client.from('notification').update({'isread': 1}).eq('ins_id', insId).eq('activestatus', 1);
      await _fetchNotifications();
      widget.onReadChanged?.call();
    } catch (e) {
      debugPrint('Error marking all as read: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredNotifications;

    return Column(
      children: [
        // Header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              const Icon(Icons.notifications_rounded, color: AppColors.accent, size: 22),
              const SizedBox(width: 10),
              const Text('Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              if (_unreadCount > 0) ...[
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('$_unreadCount new', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error)),
                ),
              ],
              const Spacer(),
              // Filter chips
              ...['All', 'Unread', 'Read'].map((f) {
                final isActive = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(left: 6),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
                      ),
                      child: Text(f, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isActive ? Colors.white : AppColors.textSecondary)),
                    ),
                  ),
                );
              }),
              const SizedBox(width: 10),
              if (_unreadCount > 0)
                TextButton.icon(
                  onPressed: _markAllAsRead,
                  icon: const Icon(Icons.done_all_rounded, size: 16),
                  label: const Text('Mark all read', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20)),
                ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 18, color: AppColors.textSecondary),
                onPressed: _fetchNotifications,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _selectedNotification != null
                  ? _buildNotificationDetail(_selectedNotification!)
                  : filtered.isEmpty
                      ? _buildEmptyState()
                      : ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: filtered.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (context, index) => _buildNotificationTile(filtered[index]),
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
          Icon(Icons.notifications_off_rounded, size: 56, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          const SizedBox(height: 14),
          Text(
            _filter == 'Unread' ? 'No unread notifications' : _filter == 'Read' ? 'No read notifications' : 'No notifications yet',
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 6),
          const Text('You\'re all caught up!', style: TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }

  Widget _buildNotificationTile(Map<String, dynamic> notif) {
    final title = notif['notititle']?.toString() ?? notif['title']?.toString() ?? 'Notification';
    final body = notif['notibody']?.toString() ?? notif['body']?.toString() ?? notif['notidesc']?.toString() ?? '';
    final date = notif['createdat']?.toString();
    final type = notif['notitype']?.toString() ?? notif['type']?.toString();
    final isRead = notif['isread'] == true || notif['isread'] == 1;

    return InkWell(
      onTap: () {
        if (!isRead) _markAsRead(notif);
        setState(() => _selectedNotification = notif);
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : AppColors.accent.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isRead ? AppColors.border : AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _typeColor(type).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_typeIcon(type), size: 22, color: _typeColor(type)),
            ),
            const SizedBox(width: 14),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!isRead)
                        Container(
                          width: 7,
                          height: 7,
                          margin: const EdgeInsets.only(right: 6),
                          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                        ),
                      Expanded(
                        child: Text(title, style: TextStyle(fontSize: 14, fontWeight: isRead ? FontWeight.w500 : FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (type != null)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _typeColor(type).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _typeColor(type))),
                        ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(body, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
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

  Widget _buildNotificationDetail(Map<String, dynamic> notif) {
    final title = notif['notititle']?.toString() ?? notif['title']?.toString() ?? 'Notification';
    final body = notif['notibody']?.toString() ?? notif['body']?.toString() ?? notif['notidesc']?.toString() ?? '';
    final date = notif['createdat']?.toString();
    final type = notif['notitype']?.toString() ?? notif['type']?.toString();

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: InkWell(
              onTap: () => setState(() => _selectedNotification = null),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 16, color: AppColors.accent),
                    SizedBox(width: 6),
                    Text('Back to Notifications', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.accent)),
                  ],
                ),
              ),
            ),
          ),
          const Divider(color: AppColors.border),
          // Detail content
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: _typeColor(type).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(_typeIcon(type), size: 24, color: _typeColor(type)),
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
                              if (type != null) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: _typeColor(type).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(type, style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _typeColor(type))),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Icon(Icons.calendar_today_rounded, size: 12, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Text(_formatDate(date), style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                              const SizedBox(width: 10),
                              Icon(Icons.access_time_rounded, size: 12, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                              const SizedBox(width: 4),
                              Text(_timeAgo(date), style: TextStyle(fontSize: 11, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  const Divider(color: AppColors.border),
                  const SizedBox(height: 16),
                  Text(body, style: const TextStyle(fontSize: 14, color: AppColors.textPrimary, height: 1.6)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
