import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../utils/app_theme.dart';
import '../../utils/auth_provider.dart';
import '../../services/supabase_service.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  bool _isLoading = false;
  List<Map<String, dynamic>> _notifications = [];
  String _filter = 'All'; // All, Unread, Read

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
          .order('createdat', ascending: false);
      // Deduplicate: group by title+body+type, show unique notifications only
      final allNotifications = List<Map<String, dynamic>>.from(data);
      final seen = <String>{};
      final unique = <Map<String, dynamic>>[];
      for (final n in allNotifications) {
        final key = '${n['notititle']}|${n['notibody']}|${n['notitype']}';
        if (!seen.contains(key)) {
          seen.add(key);
          unique.add(n);
        }
      }
      if (mounted) {
        setState(() {
          _notifications = unique;
          _isLoading = false;
        });
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
    final id = notif['noti_id'] ?? notif['id'];
    if (id == null) return;
    try {
      await SupabaseService.client.from('notification').update({'isread': 1}).eq('noti_id', id);
      _fetchNotifications();
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
      _fetchNotifications();
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
            borderRadius: BorderRadius.circular(14),
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
                  style: TextButton.styleFrom(foregroundColor: AppColors.accent),
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
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _typeColor(type).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(_typeIcon(type), size: 20, color: _typeColor(type)),
            ),
            const SizedBox(width: 12),
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
                        child: Text(title, style: TextStyle(fontSize: 13, fontWeight: isRead ? FontWeight.w500 : FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      Text(_timeAgo(date), style: TextStyle(fontSize: 10, color: AppColors.textSecondary.withValues(alpha: 0.6))),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(body, style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.3), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
