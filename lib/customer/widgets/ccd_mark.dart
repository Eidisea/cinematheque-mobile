import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';

/// The Cinematheque Centre Davao mark: a gold CD monogram with a short ticket perforation
/// in the mouth of the C. The launcher icon, the hero of the splash and the in-app logo.
///
/// Geometry is a 100×100 box, the same numbers as tool/icon/ccd_mark.svg.html (the icon
/// source) — keep them in sync. Drawn as vectors, so it stays sharp at any size.
class CcdMark extends StatelessWidget {
  const CcdMark({super.key, required this.size, this.color, this.perforation = true});

  /// The side of the mark's square box; the monogram is about 88% of it wide, 54% tall.
  final double size;

  /// A flat colour, or null for the gold gradient (icon and splash).
  final Color? color;

  /// The perforation dots can be left out where they would be too small to read.
  final bool perforation;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: CustomPaint(painter: CcdMarkPainter(color: color, perforation: perforation)),
      );
}

class CcdMarkPainter extends CustomPainter {
  const CcdMarkPainter({this.color, this.perforation = true});

  final Color? color;
  final bool perforation;

  static const _stroke = 9.5;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 100, size.height / 100);
    final paint = Paint()..isAntiAlias = true;
    if (color != null) {
      paint.color = color!;
    } else {
      paint.shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [CustomerColors.gold, CustomerColors.gold600],
      ).createShader(const Rect.fromLTWH(0, 22, 100, 56));
    }
    final stroke = Paint()
      ..isAntiAlias = true
      ..style = PaintingStyle.stroke
      ..strokeWidth = _stroke
      ..strokeCap = StrokeCap.butt
      ..strokeJoin = StrokeJoin.miter
      ..color = paint.color
      ..shader = paint.shader;

    // C: an arc open to the right.
    canvas.drawPath(
      Path()
        ..moveTo(48.85, 35.86)
        ..arcToPoint(const Offset(48.85, 64.14), radius: const Radius.circular(22), largeArc: true, clockwise: false),
      stroke,
    );
    // D: stem and bowl.
    canvas.drawPath(
      Path()
        ..moveTo(62, 28)
        ..lineTo(62, 72)
        ..moveTo(57.25, 28)
        ..lineTo(66, 28)
        ..arcToPoint(const Offset(66, 72), radius: const Radius.circular(22))
        ..lineTo(57.25, 72),
      stroke,
    );
    // The perforation, in the mouth of the C.
    if (perforation) {
      final dot = Paint()
        ..isAntiAlias = true
        ..color = paint.color
        ..shader = paint.shader;
      for (final y in const [40.5, 46.8, 53.2, 59.5]) {
        canvas.drawCircle(Offset(52.8, y), 1.55, dot);
      }
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CcdMarkPainter old) => old.color != color || old.perforation != perforation;
}
