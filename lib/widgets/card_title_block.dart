import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../utils/app_theme.dart';
import 'app_icon.dart';

/// Shared card-header title block — plain accent icon beside a bold title.
/// Used as the standard header pattern across every card/section in the
/// project (Fee Master, Master Data, Admission Master, Admin Creation, Fee
/// Concession, etc.).
class CardTitleBlock extends StatelessWidget {
  final String icon;
  final String title;
  final double iconSize;

  const CardTitleBlock({
    super.key,
    required this.icon,
    required this.title,
    // Accepted for call-site compatibility; no longer rendered.
    String? subtitle,
    this.iconSize = 20,
  });

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppIcon(icon, size: iconSize, color: AppColors.accent),
      SizedBox(width: 10.w),
      Text(title,
          style: TextStyle(
              fontSize: 16.sp,
              fontWeight: FontWeight.w700,
              color: AppColors.textPrimary)),
    ]);
  }
}
