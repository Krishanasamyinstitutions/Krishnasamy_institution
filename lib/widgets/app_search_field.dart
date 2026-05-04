import 'package:flutter/material.dart';
import 'app_icon.dart';

/// Pill-shaped search input with leading magnifier icon.
/// Used in place of raw TextField+InputDecoration for a consistent look
/// across all screens. Compacts at width <= 1366 to match the project's
/// responsive action-button spec.
class AppSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final double? width;

  /// Optional height override. When null (the default), the field uses
  /// 40 px at 1920+ and 30 px at <= 1366 so it lines up with action buttons.
  final double? height;

  final FocusNode? focusNode;
  final bool autofocus;
  final Widget? suffixIcon;

  const AppSearchField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.width,
    this.height,
    this.focusNode,
    this.autofocus = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    const fieldBg = Color(0xFFF1F2F4);
    const hintColor = Color(0xFF9CA3AF);
    const textColor = Color(0xFF1F2937);

    final compact = MediaQuery.of(context).size.width <= 1366;
    final effectiveHeight = height ?? (compact ? 30.0 : 40.0);
    final hPad = compact ? 10.0 : 14.0;
    final iconSize = compact ? 12.0 : 16.0;
    final iconGap = compact ? 6.0 : 10.0;
    final textSize = compact ? 11.0 : 13.0;
    final cursorH = compact ? 14.0 : 16.0;

    return Container(
      width: width,
      height: effectiveHeight,
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(effectiveHeight / 2),
      ),
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Row(
        children: [
          AppIcon.linear('search-normal', size: iconSize, color: hintColor),
          SizedBox(width: iconGap),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              onChanged: onChanged,
              style: TextStyle(fontSize: textSize, color: textColor),
              cursorHeight: cursorH,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(fontSize: textSize, color: hintColor),
                isCollapsed: true,
                filled: false,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                contentPadding: EdgeInsets.zero,
              ),
            ),
          ),
          if (suffixIcon != null) suffixIcon!,
        ],
      ),
    );
  }
}
