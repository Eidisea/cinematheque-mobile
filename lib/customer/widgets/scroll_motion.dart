import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';

/// Scroll-linked motion for editorial pages (About).
///
/// Motion here is driven by *where things are on screen*, not by timers: it follows
/// the finger, and scrolling back reverses it. With the phone's "remove animations"
/// setting on, everything is simply shown in its final state.

/// Where a widget's top edge is inside its scroll viewport.
class ViewportPos {
  const ViewportPos(this.top, this.height);

  /// Reduced motion: every progress is complete.
  static const settled = ViewportPos(double.negativeInfinity, 1);

  final double top; // px from the viewport's top edge (negative once scrolled past)
  final double height; // viewport height

  bool get isSettled => top == double.negativeInfinity;

  /// 0 while the widget's top is below [from] × viewport height, rising to 1 as the
  /// top travels up to [to] × viewport height (e.g. from 0.95 to 0.6).
  double progress(double from, double to) {
    if (isSettled) return 1;
    final a = height * from, b = height * to;
    return ((a - top) / (a - b)).clamp(0.0, 1.0);
  }

  /// How far down this widget (local px) a horizontal line at [fraction] of the
  /// viewport currently reaches — used to "draw" lines as the reader moves down.
  double lineAt(double fraction) => isSettled ? double.infinity : height * fraction - top;
}

/// The part of [p] between [begin] and [end], eased — for staggering elements
/// within one reveal (year first, then title, then body).
double stage(double p, double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
    curve.transform(((p - begin) / (end - begin)).clamp(0.0, 1.0));

/// Rebuilds [builder] with this widget's [ViewportPos] as the page scrolls.
class InViewport extends StatefulWidget {
  const InViewport({super.key, required this.builder, this.child});

  final Widget Function(BuildContext context, ViewportPos pos, Widget? child) builder;
  final Widget? child;

  @override
  State<InViewport> createState() => _InViewportState();
}

class _InViewportState extends State<InViewport> {
  ScrollPosition? _position;
  ViewportPos _pos = const ViewportPos(double.infinity, 1); // below the fold until measured
  bool _reduced = false;

  // Where this widget sits in the scrolling content (its top at scroll offset 0), and
  // its size. Measured after layout; between layouts a scroll only shifts it by the
  // scroll offset, so scroll ticks update instantly without touching layout.
  double? _contentTop;
  double _extent = 0;
  double _viewportHeight = 1;
  bool _measureScheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = Motion.reduced(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_onScroll);
      _position = position?..addListener(_onScroll);
    }
    _scheduleMeasure();
  }

  @override
  void didUpdateWidget(InViewport old) {
    super.didUpdateWidget(old);
    _scheduleMeasure(); // content above may have changed size
  }

  @override
  void dispose() {
    _position?.removeListener(_onScroll);
    super.dispose();
  }

  void _scheduleMeasure() {
    if (_measureScheduled) return;
    _measureScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measureScheduled = false;
      _measure();
    });
  }

  /// After layout: find this widget's place in the content.
  void _measure() {
    if (!mounted || _reduced) return;
    final box = context.findRenderObject() as RenderBox?;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject() as RenderBox?;
    final position = _position;
    if (box == null || !box.attached || !box.hasSize || viewport == null || !viewport.hasSize) return;
    if (position == null || !position.hasPixels) return;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    _contentTop = top + position.pixels;
    _extent = box.size.height;
    _viewportHeight = viewport.size.height;
    _update();
  }

  void _onScroll() {
    if (_contentTop == null) {
      _scheduleMeasure();
      return;
    }
    _update();
    _scheduleMeasure(); // keep the cached place honest if layout shifts
  }

  void _update() {
    if (!mounted || _reduced || _contentTop == null) return;
    final position = _position;
    if (position == null || !position.hasPixels) return;
    final h = _viewportHeight;
    final top = _contentTop! - position.pixels;

    // Far off screen on the same side as last time: nothing visible changes, skip the rebuild.
    bool farBelow(double t) => t > h * 1.5;
    bool farAbove(double t) => t + _extent < -h * 0.5;
    if (h == _pos.height && ((farBelow(top) && farBelow(_pos.top)) || (farAbove(top) && farAbove(_pos.top)))) return;
    if (top == _pos.top && h == _pos.height) return;
    setState(() => _pos = ViewportPos(top, h));
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _reduced ? ViewportPos.settled : _pos, widget.child);
}

/// Fades and lifts [child] into place as it rises into view. [floor] keeps upcoming
/// content faintly visible ("quieter until you reach it") instead of absent.
class Reveal extends StatelessWidget {
  const Reveal({super.key, required this.child, this.from = 0.96, this.to = 0.72, this.rise = 16, this.floor = 0});

  final Widget child;
  final double from;
  final double to;
  final double rise;
  final double floor;

  @override
  Widget build(BuildContext context) => InViewport(
        child: child,
        builder: (context, pos, child) {
          final t = stage(pos.progress(from, to), 0, 1);
          return Opacity(
            opacity: floor + (1 - floor) * t,
            child: Transform.translate(offset: Offset(0, rise * (1 - t)), child: child),
          );
        },
      );
}
