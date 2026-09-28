import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';
import '../widgets/scroll_motion.dart';

/// A Cinematheque Centre as listed on FDCP's Cinematheque Centres page
/// (https://fdcp.ph/index.php/cinematheques, read September 2026).
class Centre {
  const Centre({required this.name, required this.address, required this.lat, required this.lon, this.here = false});

  final String name; // the place: "Davao"
  final String address; // as FDCP lists it
  final double lat; // city coordinates (°N / °E), for placing the dot
  final double lon;
  final bool here; // this app's centre
}

/// In FDCP's order.
const centres = [
  Centre(
    name: 'Manila',
    address: 'Philippine Film Heritage Building, Sta. Lucia Street, Intramuros, Manila',
    lat: 14.59,
    lon: 120.98,
  ),
  Centre(name: 'Iloilo', address: 'Iznart cor. Solis Sts., Iloilo City', lat: 10.70, lon: 122.56),
  Centre(name: 'Davao', address: 'Palma Gil St., Davao City', lat: 7.07, lon: 125.61, here: true),
  Centre(name: 'Negros', address: 'Bacolod City, Negros', lat: 10.68, lon: 122.95),
];

/// The four centres, north to south: plain dots placed by their map coordinates —
/// no coastline, nothing drawn that FDCP didn't say — with Davao marked.
///
/// As it scrolls into view the parallels come first, then the centres arrive from
/// north to south, and Davao lands last.
class CentresMap extends StatelessWidget {
  const CentresMap({super.key});

  // The area shown (degrees). Taller than wide, like the country.
  static const _north = 15.1, _south = 6.3, _west = 120.2, _east = 126.4;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Map of the Cinematheque Centres, north to south: Manila; Iloilo and Negros; Davao, this centre.',
      excludeSemantics: true,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final h = w * 1.15; // vertically compressed a little so it fits a phone screen
          Offset at(double lat, double lon) =>
              Offset((lon - _west) / (_east - _west) * w, (_north - lat) / (_north - _south) * h);

          return InViewport(
            builder: (context, pos, _) {
              final p = pos.progress(0.95, 0.4);
              final shown = {for (final c in centres) c: _arrival(c, p)};
              return SizedBox(
                width: w,
                height: h,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _MapPainter(
                          points: [for (final c in centres) (at(c.lat, c.lon), c.here, shown[c]!)],
                          parallels: [
                            for (final lat in const [14.0, 10.0, 7.0]) (lat, at(lat, _west).dy),
                          ],
                          grid: stage(p, 0, 0.3),
                        ),
                      ),
                    ),
                    for (final c in centres) _Label(centre: c, point: at(c.lat, c.lon), width: w, opacity: shown[c]!),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// When each centre arrives within the map's reveal: by latitude, north first;
/// this centre last, after the others have settled.
double _arrival(Centre c, double p) {
  if (c.here) return stage(p, 0.6, 0.95);
  final north = (CentresMap._north - c.lat) / (CentresMap._north - CentresMap._south); // 0 north … 1 south
  final begin = 0.1 + 0.35 * north;
  return stage(p, begin, begin + 0.3);
}

class _Label extends StatelessWidget {
  const _Label({required this.centre, required this.point, required this.width, required this.opacity});

  final Centre centre;
  final Offset point;
  final double width;
  final double opacity; // arrives with its dot

  @override
  Widget build(BuildContext context) {
    // Labels sit on whichever side has room. Iloilo and Negros share a latitude a few
    // pixels apart, so Iloilo's name is lifted above the pair.
    final onLeft = point.dx > width * 0.6;
    final lifted = centre.name == 'Iloilo';
    final gap = centre.here ? 24.0 : 14.0; // clear of Davao's halo
    const labelWidth = 150.0;
    final name = Text(
      centre.name.toUpperCase(),
      style: CcdType.display(centre.here ? TypeScale.s : 16, color: centre.here ? CustomerColors.ink : CustomerColors.muted, spacing: 1),
    );
    return Positioned(
      top: point.dy - (centre.here ? 15 : (lifted ? 34 : 11)),
      left: onLeft ? point.dx - gap - labelWidth : point.dx + (lifted ? 4 : gap),
      width: labelWidth,
      child: Opacity(
        opacity: opacity,
        child: Column(
          crossAxisAlignment: onLeft ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            name,
            if (centre.here) Text('YOU ARE HERE', style: CcdType.eyebrow.copyWith(fontSize: 10.5)),
          ],
        ),
      ),
    );
  }
}

class _MapPainter extends CustomPainter {
  const _MapPainter({required this.points, required this.parallels, required this.grid});

  final List<(Offset, bool, double)> points; // (position, this centre, arrival 0…1)
  final List<(double, double)> parallels; // (latitude, y)
  final double grid; // parallels fading in 0…1

  @override
  void paint(Canvas canvas, Size size) {
    // Parallels as dashed hairlines, labelled at the left edge.
    final dash = Paint()
      ..color = CustomerColors.borderStrong.withValues(alpha: grid)
      ..strokeWidth = 1;
    for (final (lat, y) in parallels) {
      for (var x = 38.0; x < size.width; x += 8) {
        canvas.drawLine(Offset(x, y), Offset(x + 3, y), dash);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: '${lat.toStringAsFixed(0)}°N',
          style: TextStyle(fontSize: 10, color: CustomerColors.faint.withValues(alpha: grid), letterSpacing: 0.5),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    for (final (p, here, t) in points) {
      if (t <= 0) continue;
      if (here) {
        // Lands: drops in slightly large and settles, then the halo opens around it.
        final r = 7 * (1 + 0.6 * (1 - t));
        canvas.drawCircle(p, 16 * Curves.easeOut.transform(t), Paint()..color = CustomerColors.gold.withValues(alpha: 0.22 * t));
        canvas.drawCircle(p, r, Paint()..color = CustomerColors.gold600.withValues(alpha: t));
        canvas.drawCircle(
          p,
          r,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = CustomerColors.background.withValues(alpha: t),
        );
      } else {
        canvas.drawCircle(p, 5 * t, Paint()..color = CustomerColors.background);
        canvas.drawCircle(p, 4 * t, Paint()..color = CustomerColors.muted);
      }
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) => true; // cheap; redrawn only while its reveal is moving
}

/// The centres as a typeset list with their addresses; this centre is set apart.
class CentresList extends StatelessWidget {
  const CentresList({super.key});

  @override
  Widget build(BuildContext context) {
    const hairline = BorderSide(color: CustomerColors.border);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (i, c) in centres.indexed)
          Reveal(
            rise: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              decoration: BoxDecoration(
                border: Border(top: i == 0 ? hairline : BorderSide.none, bottom: hairline),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // A gold mark flags this centre; the others keep the same indent.
                  Container(
                    width: 3,
                    height: 22,
                    margin: const EdgeInsets.only(top: 3, right: Space.md),
                    color: c.here ? CustomerColors.gold600 : Colors.transparent,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Text(
                                'CINEMATHEQUE CENTRE ${c.name.toUpperCase()}',
                                style: CcdType.display(
                                  17,
                                  color: c.here ? CustomerColors.ink : CustomerColors.muted,
                                  spacing: 0.6,
                                ),
                              ),
                            ),
                            if (c.here) ...[
                              const SizedBox(width: Space.sm),
                              Text('YOU ARE HERE', style: CcdType.eyebrow.copyWith(fontSize: 10)),
                            ],
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(c.address, style: const TextStyle(fontSize: 14, height: 1.5, color: CustomerColors.muted)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
