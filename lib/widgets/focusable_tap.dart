import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// A tap control that also joins keyboard focus traversal.
///
/// Drop-in replacement for a tap-only [GestureDetector] form control (chips,
/// pill buttons, date pickers). Unlike a bare `GestureDetector`, it can hold
/// keyboard focus, so:
///  - **Tab / Shift+Tab** reach it,
///  - **Enter / Space** activate it (`onTap`),
///  - it shows a **1.5px accent focus ring** drawn via `foregroundDecoration`
///    (so focusing causes no layout shift),
///  - mouse behaviour is unchanged.
///
/// See docs/forms-focus-and-borders.md Part 1.
class FocusableTap extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  final BorderRadius? borderRadius;
  final bool autofocus;

  const FocusableTap({
    super.key,
    required this.onTap,
    required this.child,
    this.borderRadius,
    this.autofocus = false,
  });

  @override
  State<FocusableTap> createState() => _FocusableTapState();
}

class _FocusableTapState extends State<FocusableTap> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.circular(10);
    return FocusableActionDetector(
      autofocus: widget.autofocus,
      enabled: widget.onTap != null,
      mouseCursor: SystemMouseCursors.click,
      onShowFocusHighlight: (v) {
        if (v != _focused) setState(() => _focused = v);
      },
      actions: <Type, Action<Intent>>{
        ActivateIntent: CallbackAction<ActivateIntent>(
          onInvoke: (_) {
            widget.onTap?.call();
            return null;
          },
        ),
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: Container(
          foregroundDecoration: _focused
              ? BoxDecoration(
                  borderRadius: radius,
                  border: Border.all(color: AppColors.primary, width: 1.5),
                )
              : null,
          child: widget.child,
        ),
      ),
    );
  }
}
