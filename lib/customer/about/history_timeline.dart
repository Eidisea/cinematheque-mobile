import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/scroll_motion.dart';
import 'fdcp_history.dart';

/// FDCP's "Our Story" as one continuous line through time — a prologue (1919),
/// then the four institutions as chapters with their dated milestones.
///
/// Every row draws its own piece of the rail, and the rows touch, so the line reads
/// as unbroken. As the reader scrolls, the line is drawn down to a reading line
/// ([pen]); each node fills when the line reaches it, and its entry settles in —
/// year first, then the name, then the text. Entries ahead stay quiet until reached.
class HistoryTimeline extends StatelessWidget {
  const HistoryTimeline({super.key, this.eraKeys, this.endKey});

  /// Optional keys on each era's opening row and on the end of the timeline, so the
  /// page can pin the current era's name while it is being read.
  final List<GlobalKey>? eraKeys;
  final GlobalKey? endKey;

  /// The reading line, as a fraction of the viewport height.
  static const pen = 0.62;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[
      const _Prologue(),
      // A wider gap closes each institution's time before the next one begins.
      for (final (e, era) in historyEras.indexed) ...[
        _EraOpening(key: eraKeys?[e], era: era, bottomSpace: era.milestones.isEmpty ? Space.section : Space.xl),
        for (final (i, m) in era.milestones.indexed)
          _Milestone(
            event: m,
            // The very last row needs no gap: the next chapter brings its own.
            bottomSpace: i < era.milestones.length - 1 ? Space.xl : (identical(era, historyEras.last) ? 0 : Space.section),
          ),
      ],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, row) in rows.indexed) _RailScope(first: i == 0, last: i == rows.length - 1, child: row),
        SizedBox(key: endKey, height: 0),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Rail
// ---------------------------------------------------------------------------

/// Tells a row whether the line continues above / below it.
class _RailScope extends InheritedWidget {
  const _RailScope({required this.first, required this.last, required super.child});

  final bool first;
  final bool last;

  static _RailScope of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_RailScope>()!;

  @override
  bool updateShouldNotify(_RailScope old) => old.first != first || old.last != last;
}

enum _Node { prologue, era, milestone }

/// A row of the timeline: the rail (line + node) on the left, content on the right.
/// [builder] receives the row's position so the content can reveal with the line.
class _RailRow extends StatelessWidget {
  const _RailRow({required this.node, required this.nodeY, required this.builder, this.bottomSpace = Space.xl});

  final _Node node;
  final double nodeY; // node centre, from the row top — aligned with the row's first line
  final Widget Function(BuildContext context, ViewportPos pos) builder;
  final double bottomSpace;

  static const railWidth = 34.0;

  @override
  Widget build(BuildContext context) {
    final scope = _RailScope.of(context);
    return InViewport(
      builder: (context, pos, _) => Stack(
        // The content sizes the row; the rail is stretched to match (no intrinsic layout).
        children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: railWidth,
            child: CustomPaint(
              painter: _RailPainter(
                node: node,
                nodeY: nodeY,
                lineAbove: !scope.first,
                lineBelow: !scope.last,
                drawnTo: pos.lineAt(HistoryTimeline.pen),
              ),
            ),
          ),
          Padding(padding: EdgeInsets.only(left: railWidth, bottom: bottomSpace), child: builder(context, pos)),
        ],
      ),
    );
  }
}

class _RailPainter extends CustomPainter {
  const _RailPainter({
    required this.node,
    required this.nodeY,
    required this.lineAbove,
    required this.lineBelow,
    required this.drawnTo,
  });

  final _Node node;
  final double nodeY;
  final bool lineAbove;
  final bool lineBelow;
  final double drawnTo; // local y the reading line has reached (∞ = all drawn)

  static const x = 7.0;

  @override
  void paint(Canvas canvas, Size size) {
    final top = lineAbove ? 0.0 : nodeY;
    final bottom = lineBelow ? size.height : nodeY;
    if (bottom > top) {
      // The track ahead, then the gold drawn over it as far as the reader has come.
      canvas.drawLine(Offset(x, top), Offset(x, bottom), Paint()..color = CustomerColors.border..strokeWidth = 1.5);
      final end = drawnTo.clamp(top, bottom);
      if (end > top) {
        canvas.drawLine(Offset(x, top), Offset(x, end), Paint()..color = CustomerColors.gold600..strokeWidth = 1.5);
      }
    }

    // 0 → 1 as the line reaches this node.
    final fill = ((drawnTo - nodeY + 6) / 22).clamp(0.0, 1.0);
    final c = Offset(x, nodeY);
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    switch (node) {
      case _Node.era:
        canvas.drawCircle(c, 7, Paint()..color = CustomerColors.background);
        canvas.drawCircle(c, 6.25, ring..color = Color.lerp(CustomerColors.borderStrong, CustomerColors.gold600, fill)!);
        if (fill > 0) canvas.drawCircle(c, 3 * Curves.easeOutBack.transform(fill), Paint()..color = CustomerColors.gold600);
      case _Node.milestone:
        canvas.drawCircle(c, 4, Paint()..color = CustomerColors.background);
        canvas.drawCircle(
          c,
          2.75 * (0.7 + 0.3 * fill),
          Paint()..color = Color.lerp(CustomerColors.borderStrong, CustomerColors.gold600, fill)!,
        );
      case _Node.prologue:
        // Hollow: the story before the institutions.
        canvas.drawCircle(c, 6, Paint()..color = CustomerColors.background);
        canvas.drawCircle(c, 5, ring..color = Color.lerp(CustomerColors.borderStrong, CustomerColors.faint, fill)!);
    }
  }

  @override
  bool shouldRepaint(_RailPainter old) =>
      old.drawnTo != drawnTo ||
      old.node != node ||
      old.nodeY != nodeY ||
      old.lineAbove != lineAbove ||
      old.lineBelow != lineBelow;
}

// ---------------------------------------------------------------------------
// Rows
// ---------------------------------------------------------------------------

const _bodyStyle = CcdType.reading;

/// Content ahead of the reader stays faintly visible — quieter, not hidden.
const _quiet = 0.14;

/// Fade from [_quiet] to full and slide by [dx]/[dy] as [t] goes 0 → 1.
Widget _settle(double t, Widget child, {double dx = 0, double dy = 0}) => Opacity(
      opacity: _quiet + (1 - _quiet) * t,
      child: Transform.translate(offset: Offset(dx * (1 - t), dy * (1 - t)), child: child),
    );

class _Prologue extends StatelessWidget {
  const _Prologue();

  @override
  Widget build(BuildContext context) {
    const e = historyPrologue;
    return _RailRow(
      node: _Node.prologue,
      nodeY: 30,
      bottomSpace: Space.section,
      builder: (context, pos) {
        final p = pos.progress(0.9, 0.5);
        return Semantics(
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _settle(
                stage(p, 0, 0.45),
                Text('1919', style: CcdType.display(TypeScale.hero, color: CustomerColors.faint, spacing: 1).copyWith(height: 1)),
                dx: -14,
              ),
              const SizedBox(height: Space.sm),
              _settle(
                stage(p, 0.2, 0.65),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.date.toUpperCase(), style: CcdType.eyebrow.copyWith(color: CustomerColors.muted)),
                    const SizedBox(height: Space.sm),
                    Text(
                      e.title,
                      style: CcdType.display(TypeScale.m, weight: 500, spacing: 0.3).copyWith(fontStyle: FontStyle.italic, height: 1.15),
                    ),
                  ],
                ),
                dy: 12,
              ),
              const SizedBox(height: Space.sm),
              _settle(stage(p, 0.4, 0.9), Text(e.text, style: _bodyStyle.copyWith(color: CustomerColors.muted)), dy: 10),
            ],
          ),
        );
      },
    );
  }
}

/// The start of an institution: a big year, the name, where it sat, and why it existed.
class _EraOpening extends StatelessWidget {
  const _EraOpening({super.key, required this.era, required this.bottomSpace});

  final HistoryEra era;
  final double bottomSpace;

  @override
  Widget build(BuildContext context) {
    final f = era.founding;
    return _RailRow(
      node: _Node.era,
      nodeY: 36,
      bottomSpace: bottomSpace,
      builder: (context, pos) {
        // Year → name → text, over the stretch where the row rises to the reading line.
        final p = pos.progress(0.9, 0.5);
        return Semantics(
          container: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _settle(
                stage(p, 0, 0.45),
                Semantics(
                  header: true,
                  label: '${era.years.replaceAll('–', ' to ')}. ${era.name}',
                  excludeSemantics: true,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(era.years.toUpperCase(), style: CcdType.display(TypeScale.numeral, spacing: 1).copyWith(height: 1)),
                  ),
                ),
                dx: -18,
              ),
              const SizedBox(height: Space.md),
              _settle(
                stage(p, 0.2, 0.65),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Eyebrow(era.context),
                    const SizedBox(height: 6),
                    ExcludeSemantics(
                      child: Text(era.name.toUpperCase(), style: CcdType.display(TypeScale.m, spacing: 0.5).copyWith(height: 1.1)),
                    ),
                  ],
                ),
                dy: 12,
              ),
              const SizedBox(height: Space.md),
              _settle(
                stage(p, 0.4, 0.9),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      [f.date, ?f.basis].join('  ·  '),
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, letterSpacing: 0.3, color: CustomerColors.goldText),
                    ),
                    const SizedBox(height: Space.md),
                    Text(f.text, style: _bodyStyle),
                  ],
                ),
                dy: 10,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// A later milestone within an institution's time: date on the left, event on the right.
/// Smaller and quicker than an era — the pace picks up through the later years.
class _Milestone extends StatelessWidget {
  const _Milestone({required this.event, required this.bottomSpace});

  final HistoryEvent event;
  final double bottomSpace;

  /// "30 October 2007" → ("30 OCT", "2007"); "January 2011" → ("JAN", "2011").
  static (String, String) _split(String date) {
    final parts = date.split(' ');
    final year = parts.last;
    final rest = parts.sublist(0, parts.length - 1).map((p) => p.length > 3 ? p.substring(0, 3) : p).join(' ');
    return (rest.toUpperCase(), year);
  }

  @override
  Widget build(BuildContext context) {
    final (dayMonth, year) = _split(event.date);
    final content = Semantics(
      container: true,
      label: event.date,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 64,
            child: ExcludeSemantics(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(year, style: CcdType.display(TypeScale.xs, color: CustomerColors.goldText, spacing: 0.4).copyWith(height: 1.1)),
                  Text(dayMonth, style: const TextStyle(fontSize: 11, letterSpacing: 1, fontWeight: FontWeight.w600, color: CustomerColors.faint)),
                ],
              ),
            ),
          ),
          const SizedBox(width: Space.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event.title, style: const TextStyle(fontSize: 15, height: 1.35, fontWeight: FontWeight.w700)),
                if (event.basis != null) ...[
                  const SizedBox(height: 2),
                  Text(event.basis!, style: const TextStyle(fontSize: 12, color: CustomerColors.faint, fontWeight: FontWeight.w500)),
                ],
                const SizedBox(height: 4),
                Text(event.text, style: const TextStyle(fontSize: 14, height: 1.55, color: CustomerColors.muted)),
              ],
            ),
          ),
        ],
      ),
    );
    return _RailRow(
      node: _Node.milestone,
      nodeY: 11,
      bottomSpace: bottomSpace,
      builder: (context, pos) => _settle(stage(pos.progress(0.9, 0.66), 0, 1), content, dy: 10),
    );
  }
}
