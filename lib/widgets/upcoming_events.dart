import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

import './app_icon.dart';
class UpcomingEventsWidget extends StatelessWidget {
  const UpcomingEventsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final events = [
      _EventData(
        title: 'Parent-Teacher Meeting',
        date: 'Mar 5, 2026',
        time: '10:00 AM',
        type: 'Meeting',
        color: AppColors.accent,
      ),
      _EventData(
        title: 'Annual Science Exhibition',
        date: 'Mar 8, 2026',
        time: '9:00 AM',
        type: 'Event',
        color: AppColors.secondary,
      ),
      _EventData(
        title: 'Mid-Term Exam Begins',
        date: 'Mar 15, 2026',
        time: 'Full Day',
        type: 'Exam',
        color: AppColors.error,
      ),
      _EventData(
        title: 'Sports Day Practice',
        date: 'Mar 10, 2026',
        time: '3:00 PM',
        type: 'Sports',
        color: AppColors.info,
      ),
      _EventData(
        title: 'Staff Development Workshop',
        date: 'Mar 12, 2026',
        time: '2:00 PM',
        type: 'Workshop',
        color: AppColors.accentDark,
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
                'Upcoming Events',
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
          const SizedBox(height: 16),
          ...events.map((event) => _EventTile(event: event)),
        ],
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  final _EventData event;

  const _EventTile({required this.event});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 52,
            decoration: BoxDecoration(
              color: event.color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    AppIcon('calendar-1',
                        size: 12, color: AppColors.textLight),
                    const SizedBox(width: 4),
                    Text(
                      event.date,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                    ),
                    const SizedBox(width: 12),
                    AppIcon('clock',
                        size: 12, color: AppColors.textLight),
                    const SizedBox(width: 4),
                    Text(
                      event.time,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontSize: 11,
                            color: AppColors.textSecondary,
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: event.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              event.type,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: event.color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EventData {
  final String title;
  final String date;
  final String time;
  final String type;
  final Color color;

  const _EventData({
    required this.title,
    required this.date,
    required this.time,
    required this.type,
    required this.color,
  });
}
