import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/customer_theme.dart';

/// One destination of the bottom bar.
class CcdNavItem {
  const CcdNavItem({required this.label, required this.icon, this.primary = false});

  final String label; // sentence case; shown uppercase, read out as written
  final CcdNavGlyph icon;
  final bool primary; // the home destination is set slightly heavier
}

enum CcdNavGlyph { ticket, film, reel }

/// The customer app's bottom bar, designed as an editorial control strip rather
/// than a Material NavigationBar: a hairline on the page colour, thin drawn icons,
/// condensed uppercase labels, and ONE gold rule that travels between them.
///
/// The rule morphs instead of jumping: its leading edge sets off first and the
/// trailing edge follows, so it stretches toward the new destination and then
/// settles to that label's width.
class CcdNavBar extends StatefulWidget {
  const CcdNavBar({super.key, required this.items, required this.currentIndex, required this.onSelected});

  final List<CcdNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelected;

  @override
  State<CcdNavBar> createState() => _CcdNavBarState();
}

class _CcdNavBarState extends State<CcdNavBar> with SingleTickerProviderStateMixin {
  static const _ruleHeight = 2.0;
  static const _iconSize = 24.0;

  late final AnimationController _move = AnimationController(vsync: this, duration: Motion.slow, value: 1);

  // Where the rule is drawn from during a move (absolute x), and the last drawn position.
  double? _fromLeft, _fromRight, _lastLeft, _lastRight;

  @override
  void didUpdateWidget(CcdNavBar old) {
    super.didUpdateWidget(old);
    if (old.currentIndex != widget.currentIndex) {
      // Start from wherever the rule is right now (also mid-move).
      _fromLeft = _lastLeft;
      _fromRight = _lastRight;
      if (Motion.reduced(context)) {
        _move.value = 1;
      } else {
        _move.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _move.dispose();
    super.dispose();
  }

  TextStyle _labelStyle(CcdNavItem item, bool active) => CcdType.display(
        item.primary ? 14 : 12.5,
        color: active ? CustomerColors.ink : CustomerColors.muted,
        weight: (item.primary ? 560 : 480) + (active ? 90 : 0),
        spacing: 1.3,
      );

  @override
  Widget build(BuildContext context) {
    // Labels grow with the phone's text size, within reason (the bar must stay a bar).
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.3);
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return LayoutBuilder(builder: (context, constraints) {
      final n = widget.items.length;
      final colWidth = constraints.maxWidth / n;
      final maxLabelWidth = colWidth - 12;

      // Measure each label (in its active style, the widest) to size the rule.
      final sizes = [
        for (final item in widget.items)
          (TextPainter(
            text: TextSpan(text: item.label.toUpperCase(), style: _labelStyle(item, true)),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout())
              .size,
      ];
      final labelHeight = sizes.map((s) => s.height).reduce((a, b) => a > b ? a : b);
      double ruleLeft(int i) => colWidth * i + (colWidth - _ruleWidth(sizes[i].width, maxLabelWidth)) / 2;
      double ruleRight(int i) => ruleLeft(i) + _ruleWidth(sizes[i].width, maxLabelWidth);

      const top = 10.0, iconGap = 6.0, ruleGap = 6.0, bottom = 8.0;
      final ruleY = top + _iconSize + iconGap + labelHeight + ruleGap;
      final barHeight = ruleY + _ruleHeight + bottom;

      return DecoratedBox(
        decoration: const BoxDecoration(
          color: CustomerColors.background,
          border: Border(top: BorderSide(color: CustomerColors.border)),
        ),
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: SizedBox(
            height: barHeight,
            child: Stack(
              children: [
                Row(
                  children: [
                    for (var i = 0; i < n; i++)
                      Expanded(
                        child: _Destination(
                          key: ValueKey('nav-$i'),
                          item: widget.items[i],
                          active: i == widget.currentIndex,
                          labelStyle: _labelStyle(widget.items[i], i == widget.currentIndex),
                          labelHeight: labelHeight,
                          maxLabelWidth: maxLabelWidth,
                          scaler: scaler,
                          top: top,
                          iconGap: iconGap,
                          onTap: () {
                            if (i != widget.currentIndex) HapticFeedback.selectionClick();
                            widget.onSelected(i);
                          },
                        ),
                      ),
                  ],
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  top: ruleY,
                  height: _ruleHeight,
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _move,
                      builder: (context, _) {
                        final toL = ruleLeft(widget.currentIndex), toR = ruleRight(widget.currentIndex);
                        final fromL = _fromLeft ?? toL, fromR = _fromRight ?? toR;
                        final t = _move.value;
                        final movingRight = toL > fromL;
                        // Leading edge first, trailing edge catches up.
                        final lead = _leadCurve.transform(t), trail = _trailCurve.transform(t);
                        final l = _lerp(fromL, toL, movingRight ? trail : lead);
                        final r = _lerp(fromR, toR, movingRight ? lead : trail);
                        _lastLeft = l;
                        _lastRight = r;
                        return CustomPaint(painter: _RulePainter(left: l, right: r));
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  static double _ruleWidth(double labelWidth, double max) => labelWidth < max ? labelWidth : max;
  static double _lerp(double a, double b, double t) => a + (b - a) * t;
  static const _leadCurve = Interval(0, 0.62, curve: Curves.easeOutCubic);
  static const _trailCurve = Interval(0.28, 1, curve: Curves.easeInOutCubic);
}

class _Destination extends StatelessWidget {
  const _Destination({
    super.key,
    required this.item,
    required this.active,
    required this.labelStyle,
    required this.labelHeight,
    required this.maxLabelWidth,
    required this.scaler,
    required this.top,
    required this.iconGap,
    required this.onTap,
  });

  final CcdNavItem item;
  final bool active;
  final TextStyle labelStyle;
  final double labelHeight;
  final double maxLabelWidth;
  final TextScaler scaler;
  final double top;
  final double iconGap;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return Semantics(
      button: true,
      selected: active,
      inMutuallyExclusiveGroup: true,
      label: item.label,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        containedInkWell: true,
        highlightShape: BoxShape.rectangle,
        splashFactory: NoSplash.splashFactory, // the rule is the feedback, not a ripple
        highlightColor: CustomerColors.neutralTint.withValues(alpha: 0.5),
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: Column(
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(end: active ? 1 : 0),
                duration: reduced ? Duration.zero : Motion.medium,
                curve: Motion.easeOut,
                builder: (context, t, _) => CustomPaint(
                  size: const Size.square(_CcdNavBarState._iconSize),
                  painter: _GlyphPainter(item.icon, t),
                ),
              ),
              SizedBox(height: iconGap),
              SizedBox(
                height: labelHeight,
                width: maxLabelWidth,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: AnimatedDefaultTextStyle(
                    duration: reduced ? Duration.zero : Motion.medium,
                    curve: Motion.easeOut,
                    style: labelStyle,
                    child: Text(item.label.toUpperCase(), maxLines: 1, textScaler: scaler),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RulePainter extends CustomPainter {
  const _RulePainter({required this.left, required this.right});

  final double left;
  final double right;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTRB(left, 0, right, size.height);
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(size.height / 2)),
      Paint()..shader = CustomerColors.goldGradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_RulePainter old) => old.left != left || old.right != right;
}

/// Thin line icons drawn to match the brand (ticket notches, film sprockets, a reel).
/// [t] = 0 inactive (muted line) … 1 active (ink line + a gold detail).
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.t);

  final CcdNavGlyph glyph;
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..color = Color.lerp(CustomerColors.faint, CustomerColors.ink, t)!;
    final accent = Paint()..color = CustomerColors.gold600.withValues(alpha: t);

    switch (glyph) {
      case CcdNavGlyph.ticket:
        // Ticket with notches where the stub tears off, and its perforation.
        const stubX = 9.0;
        final body = Path()..addRRect(RRect.fromLTRBR(2.5, 6, 21.5, 18, const Radius.circular(2)));
        final notches = Path()
          ..addOval(Rect.fromCircle(center: const Offset(stubX, 6), radius: 2.2))
          ..addOval(Rect.fromCircle(center: const Offset(stubX, 18), radius: 2.2));
        canvas.drawPath(Path.combine(PathOperation.difference, body, notches), line);
        // Perforation: grey when idle, gold when active.
        final perf = Paint()
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round
          ..color = Color.lerp(CustomerColors.faint, CustomerColors.gold600, t)!;
        for (var y = 10.0; y < 15; y += 2.5) {
          canvas.drawLine(Offset(stubX, y), Offset(stubX, y + 1), perf);
        }
      case CcdNavGlyph.film:
        // A film frame between two sprocket strips; the picture fills gold.
        canvas.drawRRect(RRect.fromLTRBR(2.5, 4, 21.5, 20, const Radius.circular(2)), line);
        canvas.drawLine(const Offset(2.5, 8), const Offset(21.5, 8), line);
        canvas.drawLine(const Offset(2.5, 16), const Offset(21.5, 16), line);
        final hole = Paint()..color = line.color;
        for (final x in const [5.5, 9.8, 14.2, 18.5]) {
          canvas.drawRect(Rect.fromCenter(center: Offset(x, 6), width: 1.6, height: 1.4), hole);
          canvas.drawRect(Rect.fromCenter(center: Offset(x, 18), width: 1.6, height: 1.4), hole);
        }
        canvas.drawRect(const Rect.fromLTRB(5, 10, 19, 14), accent);
      case CcdNavGlyph.reel:
        // A film reel — the archive, the history.
        const c = Offset(12, 12);
        canvas.drawCircle(c, 9, line);
        for (final o in const [Offset(0, -4.6), Offset(4.4, -1.4), Offset(2.7, 3.7), Offset(-2.7, 3.7), Offset(-4.4, -1.4)]) {
          canvas.drawCircle(c + o, 1.7, line);
        }
        canvas.drawCircle(c, 1.3, Paint()..color = Color.lerp(line.color, CustomerColors.gold600, t)!);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.t != t || old.glyph != glyph;
}
