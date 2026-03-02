import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class QuickActionsWidget extends StatelessWidget {
  const QuickActionsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final actions = [
      _QuickAction(
        icon: Icons.person_add_rounded,
        label: 'Add Student',
        color: AppColors.accent,
      ),
      _QuickAction(
        icon: Icons.fact_check_rounded,
        label: 'Mark Attendance',
        color: AppColors.success,
      ),
      _QuickAction(
        icon: Icons.receipt_long_rounded,
        label: 'Collect Fee',
        color: AppColors.secondary,
      ),
      _QuickAction(
        icon: Icons.campaign_rounded,
        label: 'Send Notice',
        color: AppColors.info,
      ),
      _QuickAction(
        icon: Icons.assignment_rounded,
        label: 'Create Exam',
        color: AppColors.error,
      ),
      _QuickAction(
        icon: Icons.bar_chart_rounded,
        label: 'View Reports',
        color: AppColors.primaryLight,
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
          Text(
            'Quick Actions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: actions
                .map((action) => _QuickActionChip(action: action))
                .toList(),
          ),
        ],
      ),
    );
  }
}

class _QuickActionChip extends StatefulWidget {
  final _QuickAction action;

  const _QuickActionChip({required this.action});

  @override
  State<_QuickActionChip> createState() => _QuickActionChipState();
}

class _QuickActionChipState extends State<_QuickActionChip> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${widget.action.label} — Coming soon!'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 1),
            ),
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: _isHovered
                ? widget.action.color.withValues(alpha: 0.08)
                : AppColors.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isHovered
                  ? widget.action.color.withValues(alpha: 0.3)
                  : AppColors.border,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.action.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.action.icon,
                  size: 16,
                  color: widget.action.color,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                widget.action.label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w500,
                      fontSize: 13,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickAction {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickAction({
    required this.icon,
    required this.label,
    required this.color,
  });
}
