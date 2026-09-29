import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../core/formatting.dart';
import '../theme/customer_theme.dart';
import 'ccd_mark.dart';

// ---------------------------------------------------------------------------
// Ticket shape — FDCP presents screenings as tear-off tickets: a date stub, a
// dashed perforation, and two half-circle notches cut into the top and bottom.
// ---------------------------------------------------------------------------

/// Rounded rectangle with two semicircle notches: at [notchX] on the top and bottom
/// edges (a stub on the left), or — with [notchY] — on the left and right edges (a stub
/// at the bottom, as on the e-ticket). Used as a Material shape, so shadows, clipping and
/// ink ripples follow the cut-outs.
class TicketBorder extends ShapeBorder {
  const TicketBorder({this.notchX, this.notchY, this.radius = Radii.lg, this.notchRadius = 9, this.side = BorderSide.none})
      : assert((notchX == null) != (notchY == null), 'Give notchX or notchY');

  final double? notchX;
  final double? notchY;
  final double radius;
  final double notchRadius;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  Path _path(Rect rect) {
    final outer = Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
    final notches = Path();
    if (notchX != null) {
      final x = rect.left + notchX!;
      notches
        ..addOval(Rect.fromCircle(center: Offset(x, rect.top), radius: notchRadius))
        ..addOval(Rect.fromCircle(center: Offset(x, rect.bottom), radius: notchRadius));
    } else {
      final y = rect.top + notchY!;
      notches
        ..addOval(Rect.fromCircle(center: Offset(rect.left, y), radius: notchRadius))
        ..addOval(Rect.fromCircle(center: Offset(rect.right, y), radius: notchRadius));
    }
    return Path.combine(PathOperation.difference, outer, notches);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) => _path(rect);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) => _path(rect.deflate(side.width));

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) return;
    canvas.drawPath(_path(rect.deflate(side.width / 2)), side.toPaint());
  }

  @override
  ShapeBorder scale(double t) => TicketBorder(
      notchX: notchX == null ? null : notchX! * t,
      notchY: notchY == null ? null : notchY! * t,
      radius: radius * t,
      notchRadius: notchRadius * t,
      side: side.scale(t));
}

/// The dashed tear line between the stub and the ticket body (vertical by default).
class Perforation extends StatelessWidget {
  const Perforation({super.key, this.color = CustomerColors.perforation, this.inset = 12, this.horizontal = false});

  final Color color;
  final double inset; // keep clear of the notches
  final bool horizontal;

  @override
  Widget build(BuildContext context) => horizontal
      ? SizedBox(height: 1.5, width: double.infinity, child: CustomPaint(painter: _DashPainter(color, inset, true)))
      : SizedBox(width: 1.5, child: CustomPaint(painter: _DashPainter(color, inset, false)));
}

class _DashPainter extends CustomPainter {
  _DashPainter(this.color, this.inset, this.horizontal);

  final Color color;
  final double inset;
  final bool horizontal;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;
    final length = horizontal ? size.width : size.height;
    for (var p = inset; p < length - inset; p += 7) {
      final e = (p + 3.5).clamp(0.0, length - inset);
      if (horizontal) {
        canvas.drawLine(Offset(p, 0.75), Offset(e, 0.75), paint);
      } else {
        canvas.drawLine(Offset(0.75, p), Offset(0.75, e), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashPainter old) => old.color != color || old.horizontal != horizontal;
}

/// Month / big day / weekday — the stub of every screening ticket (Manila time).
class DateStub extends StatelessWidget {
  const DateStub({super.key, required this.date, this.dayStyleSize = 34, this.muted = false});

  final DateTime date;
  final double dayStyleSize;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final m = toManila(date);
    return Semantics(
      label: formatDateLong(date),
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(DateFormat('MMM').format(m).toUpperCase(),
              style: CcdType.eyebrow.copyWith(color: muted ? CustomerColors.faint : CustomerColors.gold600, letterSpacing: 2)),
          Text('${m.day}', style: CcdType.display(dayStyleSize, color: muted ? CustomerColors.faint : CustomerColors.ink, spacing: 0)),
          Text(DateFormat('EEE').format(m).toUpperCase(),
              style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 1.4, color: CustomerColors.muted)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Typography helpers
// ---------------------------------------------------------------------------

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key, this.color, this.maxLines = 2});

  final String text;
  final Color? color;
  final int maxLines;

  @override
  Widget build(BuildContext context) => Text(
        text.toUpperCase(),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: color == null ? CcdType.eyebrow : CcdType.eyebrow.copyWith(color: color),
      );
}

/// Condensed uppercase section title with a short gold rule. (FDCP's purple→magenta
/// rule is kept for major section starts only — see the About page — so it still
/// means something when it appears.)
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing, this.size = TypeScale.s});

  final String title;
  final Widget? trailing;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(header: true, child: Text(title.toUpperCase(), style: CcdType.display(size, spacing: 1.4))),
              const SizedBox(height: 8),
              Container(width: 28, height: 2, color: CustomerColors.gold600),
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Buttons
// ---------------------------------------------------------------------------

/// Primary action: gold gradient with ink text (the Laravel site's primary button).
class GoldButton extends StatelessWidget {
  const GoldButton({super.key, required this.label, required this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null && !busy;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.fast,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: enabled || busy ? CustomerColors.goldGradient : null,
            color: enabled || busy ? null : CustomerColors.neutralTint,
            borderRadius: BorderRadius.circular(Radii.md),
            boxShadow: enabled
                ? const [BoxShadow(color: Color(0x33CC8500), blurRadius: 16, offset: Offset(0, 6))]
                : const [],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: enabled ? onPressed : null,
              borderRadius: BorderRadius.circular(Radii.md),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 54),
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    child: busy
                        ? const SizedBox.square(
                            key: ValueKey('busy'),
                            dimension: 22,
                            child: CircularProgressIndicator(strokeWidth: 2.5, color: CustomerColors.ink),
                          )
                        : Row(
                            key: const ValueKey('label'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(label,
                                  style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w700,
                                      color: enabled || busy ? CustomerColors.ink : CustomerColors.faint,
                                      letterSpacing: 0.2)),
                              if (icon != null) ...[
                                const SizedBox(width: 8),
                                Icon(icon, size: 20, color: enabled || busy ? CustomerColors.ink : CustomerColors.faint),
                              ],
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Small outlined gold pill (FDCP's "WALK-IN ONLY" pill) — secondary action on tickets.
class GoldPill extends StatelessWidget {
  const GoldPill({super.key, required this.label, this.onPressed, this.muted = false});

  final String label;
  final VoidCallback? onPressed;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final color = muted ? CustomerColors.faint : CustomerColors.goldText;
    return Material(
      color: Colors.transparent,
      shape: StadiumBorder(side: BorderSide(color: muted ? CustomerColors.border : CustomerColors.gold600, width: 1.4)),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onPressed,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 36, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Center(
              widthFactor: 1,
              child: Text(label.toUpperCase(),
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 1.6, color: color)),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Davao motifs (from the Laravel site): skyline, logo mark, generated poster art
// ---------------------------------------------------------------------------

/// Parses the absolute M/L/H/V/Z commands used by the site's skyline SVG.
Path _svgPath(String d, Size box, Size viewBox) {
  final sx = box.width / viewBox.width, sy = box.height / viewBox.height;
  final tokens = RegExp(r'[MLHVZ]|-?\d+(?:\.\d+)?').allMatches(d).map((m) => m.group(0)!).toList();
  final path = Path();
  var x = 0.0, y = 0.0;
  var cmd = 'M';
  var i = 0;
  double next() => double.parse(tokens[i++]);
  while (i < tokens.length) {
    if (RegExp('[MLHVZ]').hasMatch(tokens[i])) cmd = tokens[i++];
    switch (cmd) {
      case 'M':
        x = next();
        y = next();
        path.moveTo(x * sx, y * sy);
        cmd = 'L';
      case 'L':
        x = next();
        y = next();
        path.lineTo(x * sx, y * sy);
      case 'H':
        x = next();
        path.lineTo(x * sx, y * sy);
      case 'V':
        y = next();
        path.lineTo(x * sx, y * sy);
      case 'Z':
        path.close();
    }
  }
  return path;
}

const _ridge = 'M0 150 L140 120 L260 128 L420 70 L505 92 L560 48 L640 96 L760 112 L900 104 L1040 122 L1200 110 L1440 132 L1440 170 L0 170 Z';
const _city = 'M0 170 V138 H38 V120 H62 V140 H90 V104 H116 V96 H130 V140 H168 V126 H200 V146 H232 V112 H250 V84 H268 V112 '
    'H290 V142 H330 V122 H362 V150 H396 V130 H430 V100 H452 V92 H470 V132 H506 V146 H548 V118 H580 V136 H612 V108 H630 V72 '
    'H650 V108 H676 V140 H716 V124 H748 V150 H790 V118 H818 V98 H846 V130 H884 V146 H918 V114 H944 V132 H980 V92 H996 V78 '
    'H1012 V92 H1030 V140 H1070 V120 H1102 V148 H1140 V126 H1170 V106 H1196 V138 H1236 V116 H1262 V146 H1300 V124 H1334 V100 '
    'H1352 V132 H1390 V144 H1440 V170 Z';

/// Mount Apo ridge behind city blocks — the Laravel hero/footer silhouette. Decorative.
class DavaoSkyline extends StatelessWidget {
  const DavaoSkyline({super.key, this.color = CustomerColors.purple, this.opacity = 0.08, this.height = 64});

  final Color color;
  final double opacity;
  final double height;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
        child: SizedBox(height: height, width: double.infinity, child: CustomPaint(painter: _SkylinePainter(color.withValues(alpha: opacity)))),
      );
}

class _SkylinePainter extends CustomPainter {
  _SkylinePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const vb = Size(1440, 170);
    canvas.drawPath(_svgPath(_ridge, size, vb), Paint()..color = color.withValues(alpha: color.a * 0.55));
    canvas.drawPath(_svgPath(_city, size, vb), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SkylinePainter old) => old.color != color;
}

/// The in-app logo: the Cinematheque CD mark (the same mark as the launcher icon and the
/// splash), in gold. The perforation is left out where it would be too small to read.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 36});

  final double size;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(child: CcdMark(size: size, perforation: size >= 30));
}

/// Generated poster art for films without a real poster (as on the Laravel site): a
/// light beam, two gold rings and the skyline on a deep gradient. Never a fake image.
class GeneratedPosterArt extends StatelessWidget {
  const GeneratedPosterArt({super.key, required this.seed, this.title, this.titleSize = 20});

  final String seed;
  final String? title;
  final double titleSize;

  static const _variants = [
    (Color(0xFF580076), Color(0xFF141219)),
    (Color(0xFF8A5A00), Color(0xFF141219)),
    (Color(0xFF1F6F50), Color(0xFF141219)),
    (Color(0xFF3A1F5C), Color(0xFF0D0D0D)),
  ];

  @override
  Widget build(BuildContext context) {
    final v = _variants[seed.codeUnits.fold<int>(0, (a, b) => a + b) % _variants.length];
    return ExcludeSemantics(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [v.$1, v.$2], stops: const [0, 0.8]),
        ),
        child: CustomPaint(
          painter: _PosterArtPainter(),
          child: title == null
              ? const SizedBox.expand()
              : Padding(
                  padding: const EdgeInsets.all(14),
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Text(
                      title!.toUpperCase(),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: CcdType.display(titleSize, color: Colors.white, spacing: 0.8).copyWith(
                        shadows: const [Shadow(color: Color(0x66000000), blurRadius: 12)],
                      ),
                    ),
                  ),
                ),
        ),
      ),
    );
  }
}

class _PosterArtPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final beam = Path()
      ..moveTo(w, 0)
      ..lineTo(w, h * 0.13)
      ..lineTo(w * 0.13, h)
      ..lineTo(0, h)
      ..lineTo(0, h * 0.85)
      ..close();
    canvas.drawPath(
      beam,
      Paint()
        ..shader = ui.Gradient.linear(Offset.zero, Offset(w, h), [const Color(0x38FFFFFF), const Color(0x00FFFFFF)]),
    );
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final c = Offset(w * 0.87, h * 0.12);
    canvas.drawCircle(c, w * 0.2, ring..color = const Color(0x59EBBC00));
    canvas.drawCircle(c, w * 0.13, ring..color = const Color(0x40EBBC00));
    canvas.drawPath(_svgPath(_city, Size(w, h * 0.22), const Size(1440, 170)).shift(Offset(0, h * 0.78)),
        Paint()..color = const Color(0x59000000));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
