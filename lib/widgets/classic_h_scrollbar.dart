import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Classic Windows-style horizontal scrollbar.
/// Left/right chevron buttons + draggable thumb.
/// Use it just below a [SingleChildScrollView] (Axis.horizontal) to give
/// every project table the same look.
class ClassicHScrollbar extends StatefulWidget {
  const ClassicHScrollbar({
    super.key,
    required this.controller,
    required this.contentWidth,
    required this.viewportWidth,
  });

  final ScrollController controller;
  final double contentWidth;
  final double viewportWidth;

  @override
  State<ClassicHScrollbar> createState() => _ClassicHScrollbarState();
}

class _ClassicHScrollbarState extends State<ClassicHScrollbar> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    final maxExtent = (widget.contentWidth - widget.viewportWidth).clamp(0.0, double.infinity);
    final offset = (ctrl.hasClients && ctrl.positions.isNotEmpty)
        ? ctrl.offset.clamp(0.0, maxExtent > 0 ? maxExtent : 0.0)
        : 0.0;

    return Container(
      height: 20,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F0F0),
        border: Border(top: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
      ),
      child: Row(
        children: [
          InkWell(
            onTap: () {
              if (!ctrl.hasClients) return;
              ctrl.animateTo(
                (ctrl.offset - 100).clamp(0.0, ctrl.position.maxScrollExtent),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFFE0E0E0),
                border: Border(right: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
              ),
              child: Icon(Icons.chevron_left, size: 16.sp, color: const Color(0xFF333333)),
            ),
          ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final thumbRatio = (widget.viewportWidth / widget.contentWidth).clamp(0.1, 1.0);
                final thumbWidth = (c.maxWidth * thumbRatio).clamp(30.0, c.maxWidth);
                final trackSpace = c.maxWidth - thumbWidth;
                final scrollRatio = maxExtent > 0 ? (offset / maxExtent).clamp(0.0, 1.0) : 0.0;
                final thumbOffset = trackSpace * scrollRatio;
                return GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (trackSpace > 0 && ctrl.hasClients && maxExtent > 0) {
                      final newRatio = ((thumbOffset + details.delta.dx) / trackSpace).clamp(0.0, 1.0);
                      ctrl.jumpTo(newRatio * maxExtent);
                    }
                  },
                  child: Container(
                    color: const Color(0xFFF0F0F0),
                    height: 20,
                    child: Stack(
                      children: [
                        Positioned(
                          left: thumbOffset,
                          top: 2,
                          child: Container(
                            width: thumbWidth,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFFC0C0C0),
                              borderRadius: BorderRadius.circular(2),
                              border: Border.all(color: const Color(0xFFB0B0B0)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          InkWell(
            onTap: () {
              if (!ctrl.hasClients) return;
              ctrl.animateTo(
                (ctrl.offset + 100).clamp(0.0, ctrl.position.maxScrollExtent),
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOut,
              );
            },
            child: Container(
              width: 20,
              height: 20,
              decoration: const BoxDecoration(
                color: Color(0xFFE0E0E0),
                border: Border(left: BorderSide(color: Color(0xFFD0D0D0), width: 1)),
              ),
              child: Icon(Icons.chevron_right, size: 16.sp, color: const Color(0xFF333333)),
            ),
          ),
        ],
      ),
    );
  }
}
