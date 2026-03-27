import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
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
              SupabaseService.client.from('notification').update({'isread': 1}).eq('noti_id', id).eq('ins_id', insId).then((_) {});
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
          padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 14.h),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10.r),
            border: Border.all(color: AppColors.border),
          ),
          child: Row(
            children: [
              Icon(Icons.notifications_rounded, color: AppColors.accent, size: 22.sp),
              SizedBox(width: 10.w),
              Text('Notifications', style: TextStyle(fontSize: 16.sp, fontWeight: FontWeight.w700)),
              if (_unreadCount > 0) ...[
                SizedBox(width: 10.w),
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                  decoration: BoxDecoration(
                    color: AppColors.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10.r),
                  ),
                  child: Text('$_unreadCount new', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w700, color: AppColors.error)),
                ),
              ],
              const Spacer(),
              // Filter chips
              ...['All', 'Unread', 'Read'].map((f) {
                final isActive = _filter == f;
                return Padding(
                  padding: EdgeInsets.only(left: 6.w),
                  child: GestureDetector(
                    onTap: () => setState(() => _filter = f),
                    child: Container(
                      padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.accent : Colors.transparent,
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(color: isActive ? AppColors.accent : AppColors.border),
                      ),
                      child: Text(f, style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: isActive ? Colors.white : AppColors.textSecondary)),
                    ),
                  ),
                );
              }),
              SizedBox(width: 10.w),
              if (_unreadCount > 0)
                TextButton.icon(
                  onPressed: _markAllAsRead,
                  icon: Icon(Icons.done_all_rounded, size: 16.sp),
                  label: Text('Mark all read', style: TextStyle(fontSize: 13.sp)),
                  style: TextButton.styleFrom(foregroundColor: AppColors.accent, padding: EdgeInsets.symmetric(horizontal: 28.w, vertical: 20.h)),
                ),
              TextButton.icon(
                onPressed: _fetchNotifications,
                icon: Icon(Icons.refresh_rounded, size: 16.sp),
                label: const Text('Refresh'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.textSecondary,
                  padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                  textStyle: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 16.h),

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
                          separatorBuilder: (_, __) => SizedBox(height: 6.h),
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
          Icon(Icons.notifications_off_rounded, size: 56.sp, color: AppColors.textSecondary.withValues(alpha: 0.3)),
          SizedBox(height: 14.h),
          Text(
            _filter == 'Unread' ? 'No unread notifications' : _filter == 'Read' ? 'No read notifications' : 'No notifications yet',
            style: TextStyle(fontSize: 15.sp, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          SizedBox(height: 6.h),
          Text('You\'re all caught up!', style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary)),
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
      borderRadius: BorderRadius.circular(12.r),
      child: Container(
        padding: EdgeInsets.all(18.w),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : AppColors.accent.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(12.r),
          border: Border.all(color: isRead ? AppColors.border : AppColors.accent.withValues(alpha: 0.2)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Icon
            Container(
              width: 44.w,
              height: 44.h,
              decoration: BoxDecoration(
                color: _typeColor(type).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12.r),
              ),
              child: Icon(_typeIcon(type), size: 22.sp, color: _typeColor(type)),
            ),
            SizedBox(width: 14.w),
            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (!isRead)
                        Container(
                          width: 7.w,
                          height: 7.h,
                          margin: EdgeInsets.only(right: 6.w),
                          decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                        ),
                      Expanded(
                        child: Text(title, style: TextStyle(fontSize: 14.sp, fontWeight: isRead ? FontWeight.w500 : FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                      if (type != null)
                        Container(
                          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                          decoration: BoxDecoration(
                            color: _typeColor(type).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6.r),
                          ),
                          child: Text(type, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: _typeColor(type))),
                        ),
                    ],
                  ),
                  if (body.isNotEmpty) ...[
                    SizedBox(height: 6.h),
                    Text(body, style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary, height: 1.4), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                  SizedBox(height: 8.h),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 12.sp, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                      SizedBox(width: 4.w),
                      Text(_formatDate(date), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                      SizedBox(width: 12.w),
                      Icon(Icons.access_time_rounded, size: 12.sp, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                      SizedBox(width: 4.w),
                      Text(_timeAgo(date), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                    ],
                  ),
                ],
              ),
            ),
            SizedBox(width: 8.w),
            Icon(Icons.chevron_right_rounded, size: 20.sp, color: AppColors.textSecondary),
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
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Back button
          Padding(
            padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 0),
            child: InkWell(
              onTap: () => setState(() => _selectedNotification = null),
              borderRadius: BorderRadius.circular(6.r),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 6.h),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(6.r),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.arrow_back_rounded, size: 16.sp, color: AppColors.accent),
                    SizedBox(width: 6.w),
                    Text('Back to Notifications', style: TextStyle(fontSize: 13.sp, fontWeight: FontWeight.w600, color: AppColors.accent)),
                  ],
                ),
              ),
            ),
          ),
          const Divider(color: AppColors.border),
          // Detail content
          Padding(
            padding: EdgeInsets.all(24.w),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48.w,
                      height: 48.h,
                      decoration: BoxDecoration(
                        color: _typeColor(type).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12.r),
                      ),
                      child: Icon(_typeIcon(type), size: 24.sp, color: _typeColor(type)),
                    ),
                    SizedBox(width: 16.w),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: TextStyle(fontSize: 18.sp, fontWeight: FontWeight.w700)),
                          SizedBox(height: 4.h),
                          Row(
                            children: [
                              if (type != null) ...[
                                Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 3.h),
                                  decoration: BoxDecoration(
                                    color: _typeColor(type).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6.r),
                                  ),
                                  child: Text(type, style: TextStyle(fontSize: 10.sp, fontWeight: FontWeight.w600, color: _typeColor(type))),
                                ),
                                SizedBox(width: 10.w),
                              ],
                              Icon(Icons.calendar_today_rounded, size: 12.sp, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                              SizedBox(width: 4.w),
                              Text(_formatDate(date), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                              SizedBox(width: 10.w),
                              Icon(Icons.access_time_rounded, size: 12.sp, color: AppColors.textSecondary.withValues(alpha: 0.6)),
                              SizedBox(width: 4.w),
                              Text(_timeAgo(date), style: TextStyle(fontSize: 13.sp, color: AppColors.textSecondary.withValues(alpha: 0.7))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                if (body.isNotEmpty) ...[
                  SizedBox(height: 20.h),
                  const Divider(color: AppColors.border),
                  SizedBox(height: 16.h),
                  Text(body, style: TextStyle(fontSize: 14.sp, color: AppColors.textPrimary, height: 1.6)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
