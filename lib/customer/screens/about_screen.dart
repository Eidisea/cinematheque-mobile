import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../about/centres_section.dart';
import '../about/fdcp_history.dart';
import '../about/history_timeline.dart';
import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/scroll_motion.dart';
import '../widgets/state_views.dart';

/// "About": an editorial story, not an info page —
/// Cinematheque Centre Davao → what a Cinematheque is → FDCP, the institution behind it
/// → how Philippine film institutions evolved into FDCP (its "Our Story" timeline)
/// → the Cinematheque Centres around the country → back to Davao.
///
/// Facts come from the official FDCP website (fdcp.ph/about and the Cinematheque
/// Centres page), paraphrased for reading on a phone. No invented dates, quotes or images.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  /// The venue itself: the Cinematheque Centre Davao marquee, from the Centre's own
  /// Instagram (27 October 2022, during the Ngilngig festival). Set to '' to fall
  /// back to the drawn projector-light treatment.
  static const heroPhoto = 'assets/images/about/ccd_facade.jpg';
  static const heroPhotoCredit = 'Opening photo: Cinematheque Centre Davao (FDCP) on Instagram, 27 October 2022.';

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();

  // Let the page know where each era starts, to pin the one being read.
  final _eraKeys = [for (final _ in historyEras) GlobalKey()];
  final _timelineEnd = GlobalKey();

  // Opening choreography: eyebrow → title lines → address, while the light comes up.
  late final AnimationController _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1300));
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (Motion.reduced(context)) {
      _intro.value = 1;
    } else {
      _intro.forward();
    }
  }

  @override
  void dispose() {
    _intro.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.sizeOf(context);
    final heroHeight = (screen.height * 0.64).clamp(440.0, 640.0);

    return Scaffold(
      body: Stack(
        children: [
          CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(
                child: _Opening(height: heroHeight, scroll: _scroll, intro: _intro),
              ),
              const SliverToBoxAdapter(child: ContentWidth(child: _TheCinematheque())),
              const SliverToBoxAdapter(child: ContentWidth(child: _TheInstitution())),
              SliverToBoxAdapter(
                child: ContentWidth(
                  child: _OurStory(eraKeys: _eraKeys, endKey: _timelineEnd),
                ),
              ),
              const SliverToBoxAdapter(child: ContentWidth(child: _TheCentres())),
              const SliverToBoxAdapter(child: ContentWidth(child: _Closing())),
            ],
          ),
          if (!Motion.reduced(context)) _EraStrip(scroll: _scroll, eraKeys: _eraKeys, endKey: _timelineEnd),
          // The opening's light may sit behind the status bar; the reading text may not.
          AnimatedBuilder(
            animation: _scroll,
            builder: (context, _) {
              final offset = _scroll.hasClients ? _scroll.offset : 0.0;
              return StatusBarScrim(opacity: (offset - heroHeight * 0.5) / (heroHeight * 0.3));
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Opening
// ---------------------------------------------------------------------------

class _Opening extends StatelessWidget {
  const _Opening({required this.height, required this.scroll, required this.intro});

  final double height;
  final ScrollController scroll;
  final Animation<double> intro;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    final reduced = Motion.reduced(context);

    return SizedBox(
      height: height,
      child: AnimatedBuilder(
        animation: Listenable.merge([scroll, intro]),
        builder: (context, _) {
          // 0 at rest … 1 when the opening has scrolled away.
          final offset = scroll.hasClients ? scroll.offset.clamp(0.0, height) : 0.0;
          final away = reduced ? 0.0 : offset / height;
          final t = intro.value;

          return ClipRect(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The image moves slower than the page and its crop tightens (parallax).
                Transform.translate(
                  offset: Offset(0, offset * 0.45 * (reduced ? 0 : 1)),
                  child: Transform.scale(
                    scale: 1 + 0.07 * away,
                    alignment: Alignment.topCenter,
                    child: _OpeningImage(
                      light: const Interval(0.1, 1, curve: Curves.easeOutCubic).transform(t),
                      topInset: topInset,
                    ),
                  ),
                ),
                // Soft fade into the page, fixed to the frame (not the moving image), so the
                // opening never ends on a hard edge — also mid-parallax.
                const Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: 140,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Color(0x00FAF9F7), CustomerColors.background],
                        ),
                      ),
                    ),
                  ),
                ),
                // Title block drifts a little and fades as the story takes over.
                Positioned(
                  left: Space.gutter,
                  right: Space.gutter,
                  bottom: Space.xxxl,
                  child: Opacity(
                    opacity: (1 - away * 1.4).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, offset * 0.18 * (reduced ? 0 : 1)),
                      child: _OpeningTitle(t: t),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _OpeningImage extends StatelessWidget {
  const _OpeningImage({required this.light, required this.topInset});

  final double light; // 0 … 1 as the projector light comes up
  final double topInset;

  @override
  Widget build(BuildContext context) {
    final photo = AboutScreen.heroPhoto;
    return ExcludeSemantics(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (photo.isNotEmpty)
            _VenuePhoto(asset: photo, light: light)
          else
            CustomPaint(
              painter: _ProjectorLightPainter(light: light, topInset: topInset),
            ),
          const Positioned(left: 0, right: 0, bottom: 0, child: DavaoSkyline(height: 96, opacity: 0.10)),
        ],
      ),
    );
  }
}

/// The building, framed in the upper part of the opening. It comes up and settles
/// (a slow push-out from 106%), then fades into the page so the title below sits
/// on paper, not on the photo. A soft paper wash at the very top keeps the status
/// bar readable over the dark facade.
class _VenuePhoto extends StatelessWidget {
  const _VenuePhoto({required this.asset, required this.light});

  final String asset;
  final double light;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final h = constraints.maxHeight * 0.72;
      return Stack(
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: h,
            child: Opacity(
              opacity: light,
              child: Transform.scale(
                scale: 1.06 - 0.06 * light,
                child: Image.asset(
                  asset,
                  fit: BoxFit.cover,
                  // Keep the marquee ("CINEMATHEQUE DAVAO") in frame when the sides are cropped.
                  alignment: const Alignment(-0.12, 0.1),
                  filterQuality: FilterQuality.medium,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            ),
          ),
          // Into the page: the lower part of the photo dissolves into paper.
          Positioned(
            left: 0,
            right: 0,
            top: h * 0.36,
            height: h * 0.64 + 1,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00FAF9F7), Color(0xD9FAF9F7), CustomerColors.background],
                  stops: [0, 0.5, 0.9],
                ),
              ),
            ),
          ),
          Positioned(left: 0, right: 0, top: h, bottom: 0, child: const ColoredBox(color: CustomerColors.background)),
          // Status bar wash.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: MediaQuery.paddingOf(context).top + 36,
            child: const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xCCFAF9F7), Color(0x00FAF9F7)],
                ),
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _OpeningTitle extends StatelessWidget {
  const _OpeningTitle({required this.t});

  final double t;

  static double _at(double t, double begin, double end) => Interval(begin, end, curve: Motion.easeOut).transform(t);

  @override
  Widget build(BuildContext context) {
    const lines = ['CINEMATHEQUE', 'CENTRE', 'DAVAO'];
    final eyebrow = _at(t, 0, 0.35);
    final address = _at(t, 0.5, 0.85);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(opacity: eyebrow, child: const Eyebrow('About · An FDCP Cinematheque Centre', maxLines: 1)),
        const SizedBox(height: Space.md),
        Semantics(
          header: true,
          label: 'Cinematheque Centre Davao',
          excludeSemantics: true,
          // One block, scaled down together on narrow phones so the lines stay aligned.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final (i, line) in lines.indexed)
                  _MaskReveal(
                    progress: _at(t, 0.08 + 0.09 * i, 0.55 + 0.09 * i),
                    child: Text(line, style: CcdType.display(TypeScale.hero, spacing: 1.2).copyWith(height: 0.98)),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: Space.lg),
        Opacity(
          opacity: address,
          child: Transform.translate(
            offset: Offset(-12 * (1 - address), 0),
            child: Row(
              children: [
                Container(width: 28, height: 2, color: CustomerColors.gold600),
                const SizedBox(width: Space.md),
                const Flexible(
                  child: Text(
                    'PALMA GIL ST. · DAVAO CITY',
                    style: TextStyle(fontSize: 12, letterSpacing: 2, fontWeight: FontWeight.w600, color: CustomerColors.muted),
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

/// A line of a title card rising into view from behind an invisible edge.
class _MaskReveal extends StatelessWidget {
  const _MaskReveal({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
    child: FractionalTranslation(
      translation: Offset(0, 1 - progress),
      child: Opacity(opacity: progress.clamp(0.0, 1.0), child: child),
    ),
  );
}

/// Placeholder for a venue photo: warm light from a projector falling across the
/// frame, with viewfinder corner marks. Drawn, so nothing is pretended to be a photo.
class _ProjectorLightPainter extends CustomPainter {
  const _ProjectorLightPainter({required this.light, required this.topInset});

  final double light;
  final double topInset;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;

    // Paper, slightly cooler at the top (the Laravel hero tint).
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [CustomerColors.heroTint, CustomerColors.background],
        ).createShader(Offset.zero & size),
    );

    final source = Offset(w * 0.9, topInset + h * 0.04);
    final reach = 0.55 + 0.45 * light; // the beam extends as the light comes up
    Offset toward(Offset p) => Offset.lerp(source, p, reach)!;

    void beam(Offset a, Offset b, double alpha) {
      final far = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      final path = Path()
        ..moveTo(source.dx, source.dy)
        ..lineTo(toward(a).dx, toward(a).dy)
        ..lineTo(toward(b).dx, toward(b).dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = ui.Gradient.linear(
            source,
            toward(far),
            [
              CustomerColors.gold300.withValues(alpha: alpha * light),
              CustomerColors.gold.withValues(alpha: alpha * 0.35 * light),
              CustomerColors.gold.withValues(alpha: 0),
            ],
            const [0, 0.55, 1],
          ),
      );
    }

    beam(Offset(-w * 0.15, h * 0.62), Offset(w * 0.5, h * 1.05), 0.26); // wide spill
    beam(Offset(w * 0.02, h * 0.74), Offset(w * 0.3, h * 0.92), 0.22); // brighter core

    // The lamp itself.
    canvas.drawCircle(
      source,
      110,
      Paint()
        ..shader = ui.Gradient.radial(source, 110, [
          CustomerColors.gold300.withValues(alpha: 0.55 * light),
          CustomerColors.gold300.withValues(alpha: 0),
        ]),
    );

    // Viewfinder corner marks (top-left, bottom-right) — a frame, quietly.
    final mark = Paint()
      ..color = CustomerColors.ink.withValues(alpha: 0.16 * light)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const len = 16.0, inset = Space.gutter;
    final tl = Offset(inset, topInset + 18);
    canvas.drawPath(
      Path()
        ..moveTo(tl.dx, tl.dy + len)
        ..lineTo(tl.dx, tl.dy)
        ..lineTo(tl.dx + len, tl.dy),
      mark,
    );
    final br = Offset(w - inset, h * 0.40); // clear of the title, also while it drifts
    canvas.drawPath(
      Path()
        ..moveTo(br.dx, br.dy - len)
        ..lineTo(br.dx, br.dy)
        ..lineTo(br.dx - len, br.dy),
      mark,
    );
  }

  @override
  bool shouldRepaint(_ProjectorLightPainter old) => old.light != light || old.topInset != topInset;
}

// ---------------------------------------------------------------------------
// Pinned era
// ---------------------------------------------------------------------------

/// While an era is being read, its years and name stay pinned under the status bar,
/// like an intertitle. The next era's opening pushes the strip up and out, then its
/// own strip fades in once its big year has passed beneath.
class _EraStrip extends StatelessWidget {
  const _EraStrip({required this.scroll, required this.eraKeys, required this.endKey});

  final ScrollController scroll;
  final List<GlobalKey> eraKeys;
  final GlobalKey endKey;

  static const height = 46.0;
  static const _yearDepth = 72.0; // how far down an era's row its big year reaches

  static double? _topOf(GlobalKey key) {
    final box = key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero).dy;
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 0,
      right: 0,
      top: topInset,
      height: height,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: scroll,
          builder: (context, _) {
            final line = topInset + height;
            int? current;
            double currentTop = 0;
            for (final (i, key) in eraKeys.indexed) {
              final t = _topOf(key);
              if (t != null && t + _yearDepth < line) {
                current = i;
                currentTop = t;
              }
            }
            if (current == null) return const SizedBox.shrink();

            final nextTop = current + 1 < eraKeys.length ? _topOf(eraKeys[current + 1]) : _topOf(endKey);
            final push = nextTop == null ? 0.0 : (nextTop - line).clamp(-height, 0.0);
            if (push <= -height) return const SizedBox.shrink();
            // Drops in from under the status bar as the era's big year passes beneath —
            // opaque, so nothing ever shows through it — and leaves pushed up by the next.
            final appear = Curves.easeOut.transform(((line - (currentTop + _yearDepth)) / 36).clamp(0.0, 1.0));
            final era = historyEras[current];

            return ExcludeSemantics(
              child: Transform.translate(
                offset: Offset(0, push < -height * (1 - appear) ? push : -height * (1 - appear)),
                child: Container(
                  decoration: const BoxDecoration(
                    color: CustomerColors.background,
                    border: Border(bottom: BorderSide(color: CustomerColors.border)),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
                  alignment: Alignment.centerLeft,
                  child: ContentWidth(
                    child: Row(
                      children: [
                        Text(era.years.toUpperCase(), style: CcdType.display(16, color: CustomerColors.goldText, spacing: 0.8)),
                        const SizedBox(width: Space.md),
                        Container(width: 1, height: 16, color: CustomerColors.borderStrong),
                        const SizedBox(width: Space.md),
                        // The full name when it fits on one line, otherwise FDCP's own
                        // abbreviation — never a name cut off mid-word.
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final style = CcdType.display(14, spacing: 0.6);
                              final full = era.name.toUpperCase();
                              final painter = TextPainter(
                                text: TextSpan(text: full, style: style),
                                textDirection: TextDirection.ltr,
                                textScaler: MediaQuery.textScalerOf(context),
                                maxLines: 1,
                              )..layout(maxWidth: constraints.maxWidth);
                              return Text(painter.didExceedMaxLines ? era.short : full, maxLines: 1, style: style);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chapters
// ---------------------------------------------------------------------------

/// Chapter content settles in piece by piece as it rises into view. The timeline and
/// the map choreograph themselves; spacers stay as they are.
List<Widget> _staged(List<Widget> children) => [
  for (final c in children) c is SizedBox || c is HistoryTimeline || c is CentresMap || c is CentresList ? c : Reveal(child: c),
];

/// "01 ── THE CINEMATHEQUE": chapter number, a short gold rule and the chapter name.
class _ChapterMark extends StatelessWidget {
  const _ChapterMark(this.number, this.label);

  final String number;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(number, style: CcdType.display(14, color: CustomerColors.goldText, spacing: 1)),
      const SizedBox(width: Space.md),
      Container(width: 28, height: 1.5, color: CustomerColors.gold600),
      const SizedBox(width: Space.md),
      Flexible(
        child: Text(label.toUpperCase(), style: CcdType.eyebrow.copyWith(color: CustomerColors.muted)),
      ),
    ],
  );
}

const _body = CcdType.reading;
const _bodyMuted = CcdType.readingMuted;

class _TheCinematheque extends StatelessWidget {
  const _TheCinematheque();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _staged([
          const _ChapterMark('01', 'The Cinematheque'),
          const SizedBox(height: Space.xl),
          Text(
            'An alternative screen for independent, classic and world cinema.',
            style: CcdType.display(TypeScale.l, weight: 470, spacing: 0.1).copyWith(height: 1.15),
          ),
          const SizedBox(height: Space.xl),
          const Text(
            'Commercial cinemas mostly show what the market dictates. The Film Development Council of the '
            'Philippines runs its own Cinematheque Centres around the country, as venues that bring more '
            'diverse films to the regions.',
            style: _body,
          ),
          const SizedBox(height: Space.lg),
          const Text(
            'They are more than places to watch. Each centre is where a local film community comes together — '
            'nurturing its own filmmakers and building an audience for its own stories.',
            style: _bodyMuted,
          ),
          const SizedBox(height: Space.xxl),
          // Davao's place among them, set off by a gold thread rather than a box.
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 2, color: CustomerColors.gold600),
                const SizedBox(width: Space.lg),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CINEMATHEQUE CENTRE DAVAO', style: CcdType.display(TypeScale.xs, spacing: 0.8)),
                        const SizedBox(height: 4),
                        const Text('is one of these centres, on Palma Gil St., Davao City.', style: _bodyMuted),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _TheInstitution extends StatelessWidget {
  const _TheInstitution();

  static const _roles = [
    ('Support', 'Filipino films from development to production, distribution and exhibition.'),
    ('Promote', 'Philippine cinema in film markets and festivals, at home and abroad.'),
    ('Preserve', 'Films as part of the national cultural heritage, through film archiving.'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.chapter, Space.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _staged([
          const _ChapterMark('02', 'The institution'),
          const SizedBox(height: Space.xl),
          Semantics(
            header: true,
            child: Text(
              'FILM DEVELOPMENT COUNCIL OF THE PHILIPPINES',
              style: CcdType.display(TypeScale.l, spacing: 0.6).copyWith(height: 1.05),
            ),
          ),
          const SizedBox(height: Space.md),
          // FDCP's purple→magenta: used here, at a major section start, not on every heading.
          Container(
            width: 56,
            height: 4,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(Radii.pill),
              gradient: const LinearGradient(colors: [CustomerColors.purple, CustomerColors.magenta]),
            ),
          ),
          const SizedBox(height: Space.xl),
          const Text(
            'FDCP is the government agency responsible for the growth and development of the Philippine film '
            'industry — for its economic, cultural and educational contribution to the nation — and for '
            "preserving the country's film heritage.",
            style: _body,
          ),
          const SizedBox(height: Space.xxl),
          for (final (i, role) in _roles.indexed) _Role(verb: role.$1, text: role.$2, first: i == 0),
        ]),
      ),
    );
  }
}

/// One of FDCP's roles as an open typographic row between hairlines (no card).
class _Role extends StatelessWidget {
  const _Role({required this.verb, required this.text, required this.first});

  final String verb;
  final String text;
  final bool first;

  @override
  Widget build(BuildContext context) {
    const hairline = BorderSide(color: CustomerColors.border);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      decoration: BoxDecoration(
        border: Border(top: first ? hairline : BorderSide.none, bottom: hairline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: math.min(110, MediaQuery.sizeOf(context).width * 0.28),
            child: Text(verb.toUpperCase(), style: CcdType.display(TypeScale.xs, color: CustomerColors.goldText, spacing: 1.2)),
          ),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 14.5, height: 1.55, color: CustomerColors.ink)),
          ),
        ],
      ),
    );
  }
}

class _OurStory extends StatelessWidget {
  const _OurStory({required this.eraKeys, required this.endKey});

  final List<GlobalKey> eraKeys;
  final GlobalKey endKey;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.chapter, Space.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _staged([
          const _ChapterMark('03', 'Our story'),
          const SizedBox(height: Space.xl),
          Semantics(
            header: true,
            child: Text(
              'FROM A FILM BOARD TO A FILM COUNCIL',
              style: CcdType.display(TypeScale.l, spacing: 0.6).copyWith(height: 1.05),
            ),
          ),
          const SizedBox(height: Space.lg),
          // All four institutions ran a film archive among their duties (per FDCP's history).
          Text(
            'Four institutions carried the same work — developing Philippine film and keeping its archive — '
            'before FDCP took its present name in 2002.',
            style: CcdType.display(TypeScale.s, weight: 460, color: CustomerColors.muted, spacing: 0.1).copyWith(height: 1.3),
          ),
          const SizedBox(height: Space.section),
          HistoryTimeline(eraKeys: eraKeys, endKey: endKey),
        ]),
      ),
    );
  }
}

class _TheCentres extends StatelessWidget {
  const _TheCentres();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.chapter, Space.gutter, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _staged([
          const _ChapterMark('04', 'The Centres'),
          const SizedBox(height: Space.xl),
          Semantics(
            header: true,
            child: Text('ACROSS THE COUNTRY', style: CcdType.display(TypeScale.l, spacing: 0.6).copyWith(height: 1.05)),
          ),
          const SizedBox(height: Space.lg),
          const Text(
            'FDCP runs its Cinematheque Centres as venues for its programmes, reaching local film communities '
            'around the country. Its website currently lists these four.',
            style: _body,
          ),
          const SizedBox(height: Space.xxl),
          const CentresMap(),
          const SizedBox(height: Space.sm),
          Text(
            'North to south · placed by map coordinates',
            style: CcdType.meta.copyWith(fontSize: 11.5, color: CustomerColors.faint),
          ),
          const SizedBox(height: Space.xxl),
          const CentresList(),
        ]),
      ),
    );
  }
}

/// Back where the story started: this centre, and the way to what's on.
class _Closing extends StatelessWidget {
  const _Closing();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.chapter, Space.gutter, Space.xxxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: _staged([
          const BrandMark(size: 44),
          const SizedBox(height: Space.lg),
          Semantics(
            header: true,
            child: Text('CINEMATHEQUE CENTRE DAVAO', style: CcdType.display(TypeScale.l, spacing: 0.8).copyWith(height: 1.05)),
          ),
          const SizedBox(height: Space.sm),
          const Text('Palma Gil St., Davao City', style: _bodyMuted),
          const SizedBox(height: Space.xl),
          GoldButton(label: "See what's showing", icon: Icons.arrow_forward_rounded, onPressed: () => context.go('/screenings')),
          const SizedBox(height: Space.xxl),
          const Divider(height: 1, color: CustomerColors.border),
          const SizedBox(height: Space.lg),
          Text(
            'Sources: Film Development Council of the Philippines — fdcp.ph/about (Our Story) and '
            'fdcp.ph Cinematheque Centres. Wording shortened for mobile; dates and names as published. '
            '${AboutScreen.heroPhotoCredit}',
            style: CcdType.meta.copyWith(fontSize: 12, color: CustomerColors.faint),
          ),
        ]),
      ),
    );
  }
}
