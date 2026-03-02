import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class RecentActivitiesWidget extends StatelessWidget {
  const RecentActivitiesWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final activities = [
      _Activity(
        avatar: 'A',
        name: 'Anitha Sharma',
        action: 'submitted fee payment of ₹15,000',
        time: '5 mins ago',
        icon: Icons.payment_rounded,
        color: AppColors.success,
      ),
      _Activity(
        avatar: 'R',
        name: 'Rahul Menon',
        action: 'was marked absent for Class X-B',
        time: '15 mins ago',
        icon: Icons.person_off_rounded,
        color: AppColors.error,
      ),
      _Activity(
        avatar: 'P',
        name: 'Priya Nair',
        action: 'uploaded exam results for Class XII',
        time: '30 mins ago',
        icon: Icons.upload_file_rounded,
        color: AppColors.info,
      ),
      _Activity(
        avatar: 'S',
        name: 'System',
        action: 'generated monthly attendance report',
        time: '1 hour ago',
        icon: Icons.auto_awesome_rounded,
        color: AppColors.secondary,
      ),
      _Activity(
        avatar: 'K',
        name: 'Kumar Pillai',
        action: 'applied for casual leave (Mar 6-7)',
        time: '2 hours ago',
        icon: Icons.event_busy_rounded,
        color: AppColors.warning,
      ),
      _Activity(
        avatar: 'D',
        name: 'Deepa Rajan',
        action: 'registered 3 new students for Class I',
        time: '3 hours ago',
        icon: Icons.person_add_rounded,
        color: AppColors.accent,
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent Activity',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              TextButton(
                onPressed: () {},
                child: Text(
                  'View All',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.accent,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...activities.asMap().entries.map((entry) {
            final activity = entry.value;
            final isLast = entry.key == activities.length - 1;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Avatar
                      CircleAvatar(
                        radius: 18,
                        backgroundColor: activity.color.withValues(alpha: 0.12),
                        child: activity.name == 'System'
                            ? Icon(Icons.auto_awesome_rounded,
                                size: 16, color: activity.color)
                            : Text(
                                activity.avatar,
                                style: TextStyle(
                                  color: activity.color,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text.rich(
                              TextSpan(
                                children: [
                                  TextSpan(
                                    text: activity.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.textPrimary,
                                          fontSize: 13,
                                        ),
                                  ),
                                  TextSpan(
                                    text: ' ${activity.action}',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(
                                          color: AppColors.textSecondary,
                                          fontSize: 13,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              activity.time,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    fontSize: 11,
                                    color: AppColors.textLight,
                                  ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: activity.color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          activity.icon,
                          size: 16,
                          color: activity.color,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!isLast)
                  Divider(
                    color: AppColors.divider,
                    height: 1,
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _Activity {
  final String avatar;
  final String name;
  final String action;
  final String time;
  final IconData icon;
  final Color color;

  const _Activity({
    required this.avatar,
    required this.name,
    required this.action,
    required this.time,
    required this.icon,
    required this.color,
  });
}
