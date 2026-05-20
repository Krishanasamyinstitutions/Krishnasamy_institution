import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

/// A classic desktop-style vertical scrollbar — a ▲ button on top, a visible
/// track lane with a draggable thumb, and a ▼ button on the bottom.
///
/// It owns its own [ScrollController]; just build the scrollable in [builder]
/// and pass the supplied controller to it:
///
/// ```dart
/// AppVerticalScrollbar(
///   builder: (context, controller) => ListView(
///     controller: controller,
///     children: [...],
///   ),
/// )
/// ```
///
/// When the scrollable cannot be wrapped directly — e.g. a vertical scroll
/// nested inside a horizontal scroll, where the bar would scroll off-screen
/// with the content — use [AppScrollbarBar] instead: place the bar in the
/// visible viewport and share the same [ScrollController] with the scrollable.
class AppVerticalScrollbar extends StatefulWidget {
  /// Builds the scrollable child. Pass the supplied [controller] to the
  /// scroll view (`ListView`, `SingleChildScrollView`, …).
  final Widget Function(BuildContext context, ScrollController controller)
      builder;

  /// Optional fixed header (e.g. a table heading row) shown above the
  /// scrollable. It is kept inside the same content column as the body, so
  /// the scrollbar lane is reserved for the header too and column widths
  /// stay aligned between the header and the scrolling rows.
  final Widget? header;

  const AppVerticalScrollbar({super.key, required this.builder, this.header});

  @override
  State<AppVerticalScrollbar> createState() => _AppVerticalScrollbarState();
}

class _AppVerticalScrollbarState extends State<AppVerticalScrollbar> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // The scrollable content — the framework scrollbar is suppressed here so
    // only this custom one shows.
    final scrollable = ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: widget.builder(context, _controller),
    );
    if (widget.header == null) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: scrollable),
          AppScrollbarBar(controller: _controller),
        ],
      );
    }
    // Header spans the full table width (right edge of the card). The
    // scrollbar lane is only reserved alongside the body rows below it, so
    // the bar never appears next to the header — the look the table designs
    // are standardising on. Callers that need column boundaries to line up
    // between header and body should add a right padding equal to the
    // scrollbar width (16) inside the header's content row themselves.
    return Column(
      children: [
        widget.header!,
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: scrollable),
              AppScrollbarBar(controller: _controller),
            ],
          ),
        ),
      ],
    );
  }
}

/// The bar-only piece of [AppVerticalScrollbar]: a ▲ button, a visible track
/// lane with a draggable thumb, and a ▼ button — 16px wide, driven by an
/// externally-supplied [controller].
///
/// Use this when the scrollable can't be wrapped by [AppVerticalScrollbar]
/// (e.g. a vertical scroll nested inside a horizontal scroll). Place this bar
/// in the visible viewport and give the same [controller] to the scrollable.
class AppScrollbarBar extends StatefulWidget {
  final ScrollController controller;

  const AppScrollbarBar({super.key, required this.controller});

  @override
  State<AppScrollbarBar> createState() => _AppScrollbarBarState();
}

class _AppScrollbarBarState extends State<AppScrollbarBar> {
  static const double _barWidth = 16;
  static const double _arrowHeight = 18;
  static const double _minThumb = 36;

  // Cache of the last-seen content dimensions so we can detect when the
  // underlying scrollable swapped its content (e.g. paginated table moved
  // to a page with a different row count) and force a thumb re-measure.
  double _lastMaxScroll = -1;
  double _lastViewport = -1;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChange);
    // The ScrollController only gets a ScrollPosition once the ListView (or
    // other scrollable) has built and attached. Until then `hasClients` is
    // false and the thumb falls back to filling the whole track. Force a
    // rebuild after the first frame so we pick up the real content/viewport
    // dimensions and render the correctly-sized thumb on initial display.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void didUpdateWidget(AppScrollbarBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChange);
      widget.controller.addListener(_onChange);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChange);
    super.dispose();
  }

  void _onChange() {
    if (mounted) setState(() {});
  }

  /// ScrollController's listener only fires on pixel changes, not when the
  /// underlying scrollable's content dimensions change (e.g. paged table
  /// swaps in a new page with a different row count). Check after each frame
  /// and rebuild if dimensions shifted, so the thumb size matches the new
  /// content instead of staying frozen at the previous page's ratio.
  void _scheduleDimensionRecheck() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!widget.controller.hasClients) return;
      final p = widget.controller.position;
      if (!p.hasContentDimensions) return;
      if (p.maxScrollExtent != _lastMaxScroll ||
          p.viewportDimension != _lastViewport) {
        _lastMaxScroll = p.maxScrollExtent;
        _lastViewport = p.viewportDimension;
        setState(() {});
      }
    });
  }

  /// Step-scroll by ~one screenful (page up / page down).
  void _step({required bool down}) {
    if (!widget.controller.hasClients) return;
    final p = widget.controller.position;
    final delta = p.viewportDimension * 0.85;
    final target = (down ? p.pixels + delta : p.pixels - delta)
        .clamp(p.minScrollExtent, p.maxScrollExtent);
    widget.controller.animateTo(target,
        duration: const Duration(milliseconds: 220), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    _scheduleDimensionRecheck();
    // Only render the bar (taking up the 16px lane) when the content actually
    // overflows. When everything fits in the viewport there's nothing to
    // scroll, so the bar collapses to zero width and the body uses the full
    // table card width.
    final hasOverflow = widget.controller.hasClients &&
        widget.controller.positions.isNotEmpty &&
        widget.controller.position.hasContentDimensions &&
        widget.controller.position.maxScrollExtent > 0;
    if (!hasOverflow) return const SizedBox.shrink();
    return SizedBox(
      width: _barWidth,
      child: Column(
        children: [
          _arrowButton(down: false),
          Expanded(child: _trackAndThumb()),
          _arrowButton(down: true),
        ],
      ),
    );
  }

  Widget _arrowButton({required bool down}) {
    return Material(
      color: AppColors.primary.withValues(alpha: 0.10),
      child: InkWell(
        onTap: () => _step(down: down),
        child: SizedBox(
          height: _arrowHeight,
          child: Icon(
            down ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
            size: 16,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }

  Widget _trackAndThumb() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final controller = widget.controller;
        final trackHeight = constraints.maxHeight;
        var thumbTop = 0.0;
        var thumbHeight = trackHeight;

        if (controller.hasClients &&
            controller.position.hasContentDimensions) {
          final p = controller.position;
          final maxScroll = p.maxScrollExtent;
          final viewport = p.viewportDimension;
          final content = maxScroll + viewport;
          if (content > viewport && content > 0 && trackHeight > 0) {
            thumbHeight = (viewport / content * trackHeight)
                .clamp(_minThumb, trackHeight);
            final fraction = maxScroll > 0
                ? (p.pixels.clamp(0.0, maxScroll) / maxScroll)
                : 0.0;
            thumbTop = fraction * (trackHeight - thumbHeight);
          }
        }

        return Container(
          color: const Color(0xFFC9CED6), // the track lane
          child: Stack(
            children: [
              Positioned(
                top: thumbTop,
                left: 2,
                right: 2,
                height: thumbHeight,
                child: GestureDetector(
                  onVerticalDragUpdate: (d) {
                    if (!controller.hasClients) return;
                    final p = controller.position;
                    final maxScroll = p.maxScrollExtent;
                    final travel = trackHeight - thumbHeight;
                    if (maxScroll <= 0 || travel <= 0) return;
                    final next = (p.pixels + d.delta.dy / travel * maxScroll)
                        .clamp(0.0, maxScroll);
                    controller.jumpTo(next);
                  },
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.75),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
