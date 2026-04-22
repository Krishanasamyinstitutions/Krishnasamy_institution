import 'package:flutter/material.dart';
import 'app_icon.dart';

/// Pill-shaped search input with leading magnifier icon.
/// Used in place of raw TextField+InputDecoration for a consistent look
/// across all screens.
class AppSearchField extends StatelessWidget {
  final TextEditingController? controller;
  final String? hintText;
  final ValueChanged<String>? onChanged;
  final double? width;
  final double height;
  final FocusNode? focusNode;
  final bool autofocus;
  final Widget? suffixIcon;

  const AppSearchField({
    super.key,
    this.controller,
    this.hintText,
    this.onChanged,
    this.width,
    this.height = 40,
    this.focusNode,
    this.autofocus = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    const fieldBg = Color(0xFFF1F2F4);
    const hintColor = Color(0xFF9CA3AF);
    const textColor = Color(0xFF1F2937);

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: fieldBg,
        borderRadius: BorderRadius.circular(height / 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          const AppIcon.linear('search-normal', size: 16, color: hintColor),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              autofocus: autofocus,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 13, color: textColor),
              cursorHeight: 16,
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(fontSize: 13, color: hintColor),
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
