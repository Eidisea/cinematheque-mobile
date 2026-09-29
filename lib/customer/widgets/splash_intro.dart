import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/customer_theme.dart';
import 'ccd_mark.dart';

/// The opening of the app, played once over the first screen on a cold start.
///
/// One hero at a time, in a dark cinema that never tears:
///   the CD mark — picked up exactly where the Android splash leaves it, small, as on the
///   home screen — is brought forward and settles at hero size; CINEMATHEQUE / CENTRE DAVAO
///   resolves beneath it. Then an admission ticket falls in from above, turning as it
///   drops, lands with a little momentum and settles. A beat — its perforation catches the
///   light — and it tears there: the stub drops away, the ticket is flicked off, and where
///   it lay a window opens onto the Screenings page, widening until the app is all there is.
/// Screenings loads underneath the whole time (nothing waits on the intro). A tap skips it.
class SplashIntro extends StatefulWidget {
  const SplashIntro({super.key, required this.onDone});

  final VoidCallback onDone;

  /// The mark's box in the native splash (66 of the icon's 108 units, shown on a 248-unit
  /// window of the 288dp splash canvas): the size the intro starts from.
  static const markStart = 66 * 288 / 248;
  static const markHero = 128.0;

  static const ink = Color(0xFF141219); // the native splash colour: the intro starts on it
  static const inkLift = Color(0xFF1E1A1F);
  static const inkDeep = Color(0xFF0B0A0D);

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro> with SingleTickerProviderStateMixin {
  late final AnimationController _play = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));
  bool _started = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = Motion.reduced(context);
    // Reduced motion: the composed card, held briefly, then a plain fade — no fall, no tear.
    if (_reduced) _play.duration = const Duration(milliseconds: 800);
    // A status listener (not the forward() future), so a skip that re-targets the
    // animation still ends the intro.
    _play.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) widget.onDone();
    });
    _play.forward();
  }

  /// A tap goes straight to the tear.
  void _skip() {
    if (_play.value < 0.9) _play.animateTo(1, duration: const Duration(milliseconds: 450));
  }

  @override
  void dispose() {
    _play.dispose();
    super.dispose();
  }

  static double _at(double t, double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  // Emphasised deceleration: quick to start, a long unhurried settle — no bounce.
  static const _settle = Cubic(0.2, 0, 0, 1);

  // The choreography, as fractions of the whole.
  static const _fall = (0.30, 0.46); // drops in from above
  static const _land = (0.46, 0.62); // lands, rocks, settles
  static const _focus = (0.62, 0.70); // the perforation catches the light
  static const _tear = (0.70, 0.86); // tears; the pieces leave
  static const _open = (0.76, 1.0); // the window onto the app widens

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque, // the page underneath isn't usable until the intro is gone
          onTap: _skip,
          child: Material(
            // Its own text defaults: it sits above the app's pages, outside any Material.
            type: MaterialType.transparency,
            child: AnimatedBuilder(
              animation: _play,
              builder: (context, _) => LayoutBuilder(
                builder: (context, constraints) {
                  final p = _play.value;
                  if (_reduced) {
                    return Opacity(opacity: 1 - _at(p, 0.75, 1, Curves.easeIn), child: _scene(constraints.biggest, 0.64));
                  }
                  return _scene(constraints.biggest, p);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _scene(Size size, double t) {
    final full = Offset.zero & size;
    final centre = full.center;

    // 1 · the mark is brought forward
    final grow = _at(t, 0.04, 0.26, _settle);
    final markSize = ui.lerpDouble(SplashIntro.markStart, SplashIntro.markHero, grow)!;
    final heroCentre = Offset(size.width / 2, size.height * 0.17);
    final markCentre = Offset.lerp(centre, heroCentre, grow)!;

    // 2 · the name resolves beneath it
    final word1 = _at(t, 0.18, 0.36);
    final word2 = _at(t, 0.22, 0.40);
    final fdcp = _at(t, 0.28, 0.44);
    final wordTop = heroCentre.dy + SplashIntro.markHero * 0.27 + 16;

    // 3 · the ticket
    final ticketH = math.min(size.height * 0.40, 340.0);
    final ticket = Size(ticketH * 0.47, ticketH);
    final rest = Offset(size.width / 2, size.height * 0.635);
    const restAngle = -0.24; // tilted, like a ticket dropped on a table

    // Falls: accelerating from above the screen, turning as it comes.
    final fall = _at(t, _fall.$1, _fall.$2, Curves.easeInQuad);
    // Lands: a small rebound and a rock that dies away.
    final land = _at(t, _land.$1, _land.$2, Curves.linear);
    final rebound = land == 0 ? 0.0 : -16 * math.sin(math.pi * math.min(land * 1.8, 1)) * (1 - land);
    final rock = land == 0 ? 0.0 : 0.09 * math.exp(-5 * land) * math.cos(11 * land);
    final pos = Offset(rest.dx + 40 * (1 - fall), ui.lerpDouble(-ticketH * 0.8, rest.dy, fall)! + rebound);
    final angle = ui.lerpDouble(-0.95, restAngle, fall)! + rock;

    final focus = _at(t, _focus.$1, _focus.$2, Curves.easeInOut);
    final strain = t > _focus.$1 && t < _tear.$1 ? math.sin((t - _focus.$1) / (_tear.$1 - _focus.$1) * math.pi) : 0.0;
    final tear = _at(t, _tear.$1, _tear.$2, Curves.easeInCubic);

    // 4 · the window where the ticket lay opens onto the app
    final open = _at(t, _open.$1, _open.$2, const Cubic(0.65, 0, 0.35, 1));
    // It starts as the ticket's own footprint, at the ticket's tilt, and straightens as it
    // widens to the whole screen.
    final footprint = Rect.fromCenter(center: rest, width: ticket.width, height: ticket.height).deflate(10);
    final reach = full.inflate(size.longestSide * 0.35); // big enough to cover while still turning
    final window = tear == 0
        ? null
        : (
            rrect: RRect.fromRectAndRadius(Rect.lerp(footprint, reach, open)!, Radius.circular(ui.lerpDouble(14, 0, open)!)),
            angle: ui.lerpDouble(restAngle, 0, open)!,
          );

    Widget dark = Stack(
      children: [
        Positioned.fill(child: CustomPaint(painter: _CinemaDark(lift: _at(t, 0, 0.3)))),
        Positioned(
          left: markCentre.dx - markSize / 2,
          top: markCentre.dy - markSize / 2,
          width: markSize,
          height: markSize,
          child: CcdMark(size: markSize),
        ),
        Positioned(
          left: Space.gutter,
          right: Space.gutter,
          top: wordTop,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Column(
              children: [
                _Resolve(
                  progress: word1,
                  child: Text(
                    'CINEMATHEQUE',
                    style: CcdType.display(26, color: CustomerColors.background, spacing: 4.4).copyWith(height: 1.05),
                  ),
                ),
                const SizedBox(height: 6),
                _Resolve(
                  progress: word2,
                  child: Text(
                    'CENTRE DAVAO',
                    style: CcdType.eyebrow.copyWith(fontSize: 11.5, letterSpacing: 5.6, color: CustomerColors.gold),
                  ),
                ),
                const SizedBox(height: Space.md),
                Opacity(
                  opacity: fdcp,
                  child: const Text(
                    'AN FDCP CINEMATHEQUE CENTRE',
                    style: TextStyle(fontSize: 9.5, letterSpacing: 2.4, fontWeight: FontWeight.w600, color: Color(0xFF8E8796)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
    if (window != null) dark = ClipPath(clipper: _Window(window.rrect, window.angle), child: dark);

    return Stack(
      children: [
        Positioned.fill(child: dark),
        if (fall > 0 && tear < 1)
          Positioned(
            left: pos.dx - ticket.width / 2,
            top: pos.dy - ticket.height / 2,
            width: ticket.width,
            height: ticket.height,
            child: Transform.rotate(
              angle: angle,
              child: _TicketPieces(size: ticket, focus: focus, strain: strain, tear: tear),
            ),
          ),
      ],
    );
  }
}

/// The ticket, whole or as two pieces parting along the perforation — in the ticket's own
/// (upright) frame; the scene rotates it.
class _TicketPieces extends StatelessWidget {
  const _TicketPieces({required this.size, required this.focus, required this.strain, required this.tear});

  final Size size;
  final double focus;
  final double strain;
  final double tear;

  @override
  Widget build(BuildContext context) {
    final face = _Ticket(size: size, focus: focus);
    if (strain == 0 && tear == 0) return face;

    final perfY = size.height * _Ticket.perforation;
    final edge = _TearEdge(size.width, perfY);

    Widget piece(int side) {
      // Straining: the stub bends back a hair at the perforation. Tearing: the stub drops
      // and swings away; the ticket is flicked up and off.
      final pivot = Offset(side < 0 ? size.width : 0, perfY);
      final angle = side < 0 ? -0.05 * strain - 0.9 * tear : 0.03 * strain + 0.35 * tear;
      final drift = side < 0 ? Offset(-60 * tear, 3 * strain + 260 * tear) : Offset(150 * tear, -2 * strain - 230 * tear);
      return Transform(
        transform: Matrix4.identity()
          ..translateByDouble(drift.dx + pivot.dx, drift.dy + pivot.dy, 0, 1)
          ..rotateZ(angle)
          ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1),
        child: Opacity(
          opacity: (1 - tear * tear).clamp(0.0, 1.0), // solid while it moves, gone as it leaves
          child: ClipPath(
            clipper: _TicketHalf(edge, side),
            child: Stack(
              children: [
                face,
                Positioned.fill(child: CustomPaint(painter: _TornFibre(edge, (strain + tear * 2).clamp(0.0, 1.0)))),
              ],
            ),
          ),
        ),
      );
    }

    // side -1 is the stub (below the perforation), 1 the ticket above it.
    return Stack(clipBehavior: Clip.none, children: [piece(-1), piece(1)]);
  }
}

/// A Cinematheque admission ticket, designed as a printed object: scalloped ends, a gold
/// face with an inset frame and the name set along its length, and — past a perforation
/// with a notch at each edge — a cream stub with a barcode.
class _Ticket extends StatelessWidget {
  const _Ticket({required this.size, required this.focus});

  final Size size;
  final double focus; // 0…1: the perforation catching the light before the tear

  /// Where the perforation runs, as a fraction of the height.
  static const perforation = 0.72;

  @override
  Widget build(BuildContext context) {
    final perfY = size.height * perforation;
    final w = size.width;
    return SizedBox.fromSize(
      size: size,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _TicketPaper(focus: focus))),
          // The face: small mark at the head, the name running up the ticket.
          Positioned(
            left: 0,
            right: 0,
            top: size.height * 0.07,
            child: Center(child: CcdMark(size: w * 0.3, color: SplashIntro.ink, perforation: false)),
          ),
          Positioned(
            left: w * 0.14,
            right: w * 0.14,
            top: size.height * 0.25,
            height: perfY - size.height * 0.31,
            child: RotatedBox(
              quarterTurns: 3,
              child: FittedBox(
                fit: BoxFit.contain,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'CINEMATHEQUE',
                      style: CcdType.display(40, color: SplashIntro.ink, weight: 650, spacing: 1.6).copyWith(height: 0.95),
                    ),
                    Text(
                      'ADMIT ONE · DAVAO',
                      style: CcdType.display(17.5, color: const Color(0xFF6B4700), weight: 520, spacing: 3.2).copyWith(height: 1.2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The stub: barcode and number.
          Positioned(
            left: w * 0.2,
            right: w * 0.2,
            top: perfY + size.height * 0.05,
            height: size.height * 0.14,
            child: const CustomPaint(painter: _Barcode()),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: size.height * 0.035,
            child: Text(
              'Nº 0001',
              textAlign: TextAlign.center,
              style: CcdType.display(size.height * 0.03, color: const Color(0xFF6B4700), spacing: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}

class _TicketPaper extends CustomPainter {
  const _TicketPaper({required this.focus});

  final double focus;

  /// The ticket's outline: rounded corners, a row of scallops bitten into each end, and a
  /// notch at each edge where the perforation runs.
  static Path outline(Size size) {
    final w = size.width, h = size.height;
    final r = w * 0.07;
    final scallop = w * 0.07;
    final notch = w * 0.075;
    final perfY = h * _Ticket.perforation;
    final bites = Path();
    for (final x in [0.3, 0.5, 0.7]) {
      bites.addOval(Rect.fromCircle(center: Offset(w * x, 0), radius: scallop));
      bites.addOval(Rect.fromCircle(center: Offset(w * x, h), radius: scallop));
    }
    bites
      ..addOval(Rect.fromCircle(center: Offset(0, perfY), radius: notch))
      ..addOval(Rect.fromCircle(center: Offset(w, perfY), radius: notch));
    return Path.combine(
      PathOperation.difference,
      Path()..addRRect(RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(r))),
      bites,
    );
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final perfY = h * _Ticket.perforation;
    final body = outline(size);

    canvas.drawShadow(body, Colors.black, 14, false);
    canvas.save();
    canvas.clipPath(body);

    // The gold face, lit from the top left.
    final faceRect = Rect.fromLTWH(0, 0, w, perfY);
    canvas.drawRect(
      faceRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFFFD84D), CustomerColors.gold, CustomerColors.gold600],
          stops: [0, 0.45, 1],
        ).createShader(faceRect),
    );
    // A soft gloss band across the face, as on printed card.
    canvas.drawPath(
      Path()
        ..moveTo(0, h * 0.30)
        ..lineTo(w, h * 0.12)
        ..lineTo(w, h * 0.22)
        ..lineTo(0, h * 0.40)
        ..close(),
      Paint()..color = Colors.white.withValues(alpha: 0.13),
    );
    // Inset frame on the face.
    final inset = w * 0.075;
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTRB(inset, inset + w * 0.04, w - inset, perfY - inset * 0.8), Radius.circular(w * 0.04)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = const Color(0xFFFFF3CC).withValues(alpha: 0.75),
    );

    // The stub: cream card.
    final stubRect = Rect.fromLTWH(0, perfY, w, h - perfY);
    canvas.drawRect(
      stubRect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Color(0xFFFFF7E1), Color(0xFFF1E1B8)],
        ).createShader(stubRect),
    );
    // A faint shade where the card folds at the perforation.
    canvas.drawRect(
      Rect.fromLTWH(0, perfY, w, 6),
      Paint()..color = const Color(0xFF6B4700).withValues(alpha: 0.10),
    );
    canvas.restore();

    // The perforation: a row of punched holes, brightening before the tear.
    final hole = Paint()..color = Color.lerp(SplashIntro.ink.withValues(alpha: 0.55), Colors.white, focus)!;
    final notch = w * 0.075;
    final step = w * 0.058;
    for (var x = notch + step * 0.8; x < w - notch - step * 0.4; x += step) {
      canvas.drawCircle(Offset(x, perfY), 1.5 + 0.6 * focus, hole);
    }
    if (focus > 0) {
      // …and a thin line of light along it.
      canvas.drawLine(
        Offset(notch, perfY),
        Offset(w - notch, perfY),
        Paint()
          ..color = Colors.white.withValues(alpha: 0.35 * focus)
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(_TicketPaper old) => old.focus != focus;
}

/// A printed barcode on the stub: fixed bars, the same every time.
class _Barcode extends CustomPainter {
  const _Barcode();

  static const _bars = [2, 1, 1, 3, 1, 2, 1, 1, 2, 3, 1, 1, 2, 1, 3, 1, 2, 1, 1, 2, 1, 3, 2, 1];

  @override
  void paint(Canvas canvas, Size size) {
    final total = _bars.fold<int>(0, (a, b) => a + b) + _bars.length;
    final unit = size.width / total;
    final paint = Paint()..color = SplashIntro.ink.withValues(alpha: 0.85);
    var x = 0.0;
    for (final (i, b) in _bars.indexed) {
      if (i.isEven) canvas.drawRect(Rect.fromLTWH(x, 0, b * unit, size.height), paint);
      x += (b + 1) * unit;
    }
  }

  @override
  bool shouldRepaint(_Barcode old) => false;
}

/// The torn line across the perforation: a small, irregular zig-zag, the same every time.
class _TearEdge {
  _TearEdge(double width, double y) {
    var i = 0;
    for (var x = -4.0; x <= width + 4; x += 4.5) {
      final wobble = math.sin(i * 12.9898) * 43758.5453;
      final jitter = (wobble - wobble.floorToDouble()) * 2 - 1;
      points.add(Offset(x, y + (i.isEven ? 1.3 : -1.3) + jitter * 0.9));
      i++;
    }
  }

  final points = <Offset>[];
}

class _TicketHalf extends CustomClipper<Path> {
  const _TicketHalf(this.edge, this.side);

  final _TearEdge edge;
  final int side; // -1 the stub (below the tear), 1 the ticket above it

  @override
  Path getClip(Size size) {
    final far = side < 0 ? size.height + 20 : -20.0;
    final pts = edge.points;
    final path = Path()..moveTo(pts.first.dx, far);
    for (final p in pts) {
      path.lineTo(p.dx, p.dy);
    }
    return path
      ..lineTo(pts.last.dx, far)
      ..close();
  }

  @override
  bool shouldReclip(_TicketHalf old) => old.side != side || old.edge != edge;
}

/// The torn edge: paper fibre, lighter than the card, along the tear.
class _TornFibre extends CustomPainter {
  const _TornFibre(this.edge, this.strength);

  final _TearEdge edge;
  final double strength;

  @override
  void paint(Canvas canvas, Size size) {
    if (strength <= 0) return;
    canvas.drawPath(
      Path()..addPolygon(edge.points, false),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..color = const Color(0xFFFFFDF6).withValues(alpha: strength),
    );
  }

  @override
  bool shouldRepaint(_TornFibre old) => old.strength != strength;
}

/// The dark layer with the window cut out of it (turned by [angle] about its centre).
class _Window extends CustomClipper<Path> {
  const _Window(this.window, this.angle);

  final RRect window;
  final double angle;

  @override
  Path getClip(Size size) {
    final c = window.center;
    final hole = (Path()..addRRect(window)).transform(
      (Matrix4.identity()
            ..translateByDouble(c.dx, c.dy, 0, 1)
            ..rotateZ(angle)
            ..translateByDouble(-c.dx, -c.dy, 0, 1))
          .storage,
    );
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Offset.zero & size)
      ..addPath(hole, Offset.zero);
  }

  @override
  bool shouldReclip(_Window old) => old.window != window || old.angle != angle;
}

/// Cinema-dark: the flat ink of the native splash, then the faintest warm lift in the middle.
class _CinemaDark extends CustomPainter {
  const _CinemaDark({required this.lift});

  final double lift;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = SplashIntro.ink);
    if (lift <= 0) return;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = ui.Gradient.radial(
          Offset(size.width / 2, size.height * 0.4),
          size.longestSide * 0.7,
          [
            SplashIntro.inkLift.withValues(alpha: lift),
            SplashIntro.ink.withValues(alpha: lift),
            SplashIntro.inkDeep.withValues(alpha: lift),
          ],
          const [0, 0.6, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(_CinemaDark old) => old.lift != lift;
}

/// A line of the name resolving: rising a little from behind an edge as it fades in.
class _Resolve extends StatelessWidget {
  const _Resolve({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: FractionalTranslation(
          translation: Offset(0, 0.7 * (1 - progress)),
          child: Opacity(opacity: progress, child: child),
        ),
      );
}
