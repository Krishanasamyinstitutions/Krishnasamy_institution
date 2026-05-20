import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// Horizontal scrollbar — the horizontal twin of [AppVerticalScrollbar]'s
/// bar: a ◄ button, a visible track lane with a draggable thumb, and a ►
/// button, sharing the same navy/grey palette and 16px thickness.
///
/// Use it just below a [SingleChildScrollView] (Axis.horizontal) to give
/// every project table the same look.
class ClassicHScrollbar extends StatefulWidget {
  const ClassicHScrollbar({
    super.key,
    required this.controller,
    this.contentWidth,
    this.viewportWidth,
  });

  final ScrollController controller;

  /// Width of the scrollable content. When null, the value is read from
  /// `controller.position` at build time (after the underlying scrollable
  /// has laid out and attached).
  final double? contentWidth;

  /// Width of the visible viewport. When null, the value is read from
  /// `controller.position.viewportDimension`.
  final double? viewportWidth;

  @override
  State<ClassicHScrollbar> createState() => _ClassicHScrollbarState();
}

class _ClassicHScrollbarState extends State<ClassicHScrollbar> {
  static const double _barHeight = 16;
  static const double _arrowWidth = 18;
  static const double _minThumb = 36;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
    // Same first-frame attach issue as AppScrollbarBar: ScrollController has
    // no ScrollPosition until the SingleChildScrollView has built, so force a
    // rebuild after the first frame to pick up the real dimensions.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(ClassicHScrollbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    super.dispose();
  }

  void _onScroll() {
    if (mounted) setState(() {});
  }

  /// Step-scroll by ~one screenful (page left / page right).
  void _step({required bool right}) {
    final ctrl = widget.controller;
    if (!ctrl.hasClients) return;
    final p = ctrl.position;
    final delta = p.viewportDimension * 0.85;
    final target = (right ? p.pixels + delta : p.pixels - delta)
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    ctrl.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = widget.controller;
    // Fall back to the controller's measured dimensions when explicit widths
    // weren't supplied — lets callers drop the bar in without lifting layout
    // computations out of a deeper LayoutBuilder.
    final hasPosition = ctrl.hasClients &&
        ctrl.positions.isNotEmpty &&
        ctrl.position.hasContentDimensions;
    final viewportW = widget.viewportWidth ??
        (hasPosition ? ctrl.position.viewportDimension : 0.0);
    final contentW = widget.contentWidth ??
        (hasPosition
            ? ctrl.position.maxScrollExtent + ctrl.position.viewportDimension
            : viewportW);
    final maxExtent =
        (contentW - viewportW).clamp(0.0, double.infinity);
    final offset = (ctrl.hasClients && ctrl.positions.isNotEmpty)
        ? ctrl.offset.clamp(0.0, maxExtent > 0 ? maxExtent : 0.0)
        : 0.0;

    // Hide entirely when the content fits in the viewport — no point drawing
    // a draggable bar with a full-width thumb if there's nothing to scroll.
    if (maxExtent <= 0) return const SizedBox.shrink();

    return SizedBox(
      height: _barHeight,
      child: Row(
        children: [
          _arrowButton(right: false),
          Expanded(
            child: LayoutBuilder(
              builder: (context, c) {
                final thumbRatio = contentW > 0
                    ? (viewportW / contentW).clamp(0.1, 1.0)
                    : 1.0;
                final thumbWidth =
                    (c.maxWidth * thumbRatio).clamp(_minThumb, c.maxWidth);
                final trackSpace = c.maxWidth - thumbWidth;
                final scrollRatio =
                    maxExtent > 0 ? (offset / maxExtent).clamp(0.0, 1.0) : 0.0;
                final thumbOffset = trackSpace * scrollRatio;
                return GestureDetector(
                  onHorizontalDragUpdate: (details) {
                    if (trackSpace > 0 && ctrl.hasClients && maxExtent > 0) {
                      final newRatio =
                          ((thumbOffset + details.delta.dx) / trackSpace)
                              .clamp(0.0, 1.0);
                      ctrl.jumpTo(newRatio * maxExtent);
                    }
                  },
                  child: Container(
                    color: const Color(0xFFC9CED6), // the track lane
                    height: _barHeight,
                    child: Stack(
                      children: [
                        Positioned(
                          left: thumbOffset,
                          top: 2,
                          bottom: 2,
                          width: thumbWidth,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.75),
                              borderRadius: BorderRadius.circular(6),
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
          _arrowButton(right: true),
        ],
      ),
    );
  }

  Widget _arrowButton({required bool right}) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.10),
      child: InkWell(
        onTap: () => _step(right: right),
        child: SizedBox(
          width: _arrowWidth,
          height: _barHeight,
          child: Icon(
            right ? Icons.keyboard_arrow_right : Icons.keyboard_arrow_left,
            size: 16,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
