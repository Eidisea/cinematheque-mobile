import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';
import 'brand.dart';

/// The opening of the app, played once over the first screen on a cold start.
///
/// It begins on exactly the frame the Android splash leaves behind — warm paper and
/// the Cinematheque mark, 96dp wide, dead centre (res/drawable/splash_mark.xml) — so
/// the hand-over is invisible. Then, like a title card: the mark rises and settles,
/// CINEMATHEQUE / CENTRE DAVAO is revealed beneath it, a gold rule draws out and the
/// FDCP line appears. The card then fades to the Screenings page, which has been
/// loading underneath the whole time (nothing waits on the intro). A tap skips it.
class SplashIntro extends StatefulWidget {
  const SplashIntro({super.key, required this.onDone});

  final VoidCallback onDone;

  /// The mark's frame is 36 of the painter's 40 units: 96dp wide, as in the native splash.
  static const markBox = 96 * 40 / 36;

  @override
  State<SplashIntro> createState() => _SplashIntroState();
}

class _SplashIntroState extends State<SplashIntro> with TickerProviderStateMixin {
  late final AnimationController _play = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500));
  late final AnimationController _out = AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  bool _started = false;
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _reduced = Motion.reduced(context);
    if (_reduced) {
      // Reduced motion: the finished card, held briefly, then a quick fade — no movement.
      _play.duration = const Duration(milliseconds: 500);
      _out.duration = const Duration(milliseconds: 200);
    }
    _play.forward().whenComplete(_leave);
  }

  void _leave() {
    if (!mounted || _out.isAnimating || _out.value > 0) return;
    _out.forward().whenComplete(() {
      if (mounted) widget.onDone();
    });
  }

  @override
  void dispose() {
    _play.dispose();
    _out.dispose();
    super.dispose();
  }

  static double _at(double t, double begin, double end, [Curve curve = Curves.easeOutCubic]) =>
      curve.transform(((t - begin) / (end - begin)).clamp(0.0, 1.0));

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque, // the page underneath isn't usable until the card is gone
        onTap: _leave,
        child: AnimatedBuilder(
          animation: Listenable.merge([_play, _out]),
          builder: (context, _) {
            final t = _reduced ? 1.0 : _play.value;
            final rise = _at(t, 0.12, 0.48, Curves.easeInOutCubic);
            final line1 = _at(t, 0.30, 0.62);
            final line2 = _at(t, 0.40, 0.72);
            final rule = _at(t, 0.55, 0.80);
            final fdcp = _at(t, 0.62, 0.86);

            return Opacity(
              opacity: 1 - Curves.easeIn.transform(_out.value),
              child: ColoredBox(
                color: CustomerColors.background,
                child: LayoutBuilder(builder: (context, constraints) {
                  final centre = constraints.biggest.center(Offset.zero);
                  const box = SplashIntro.markBox;
                  final scale = 1 - 0.28 * rise;
                  final markCentreY = centre.dy - 72 * rise;
                  final textTop = centre.dy - 72 + box * 0.72 / 2 + 18; // below the settled mark

                  return Stack(
                    children: [
                      Positioned(
                        left: centre.dx - box / 2,
                        top: markCentreY - box / 2,
                        width: box,
                        height: box,
                        child: Transform.scale(scale: scale, child: const BrandMark(size: box)),
                      ),
                      Positioned(
                        left: Space.gutter,
                        right: Space.gutter,
                        top: textTop,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Column(
                            children: [
                              _Reveal(
                                progress: line1,
                                child: Text('CINEMATHEQUE', style: CcdType.display(38, spacing: 3.4).copyWith(height: 1.05)),
                              ),
                              const SizedBox(height: 4),
                              _Reveal(
                                progress: line2,
                                child: Text(
                                  'CENTRE DAVAO',
                                  style: CcdType.eyebrow.copyWith(fontSize: 13.5, letterSpacing: 5.4, color: CustomerColors.goldText),
                                ),
                              ),
                              const SizedBox(height: Space.xl),
                              Container(width: 36 * rule, height: 2, color: CustomerColors.gold600),
                              const SizedBox(height: Space.lg),
                              Opacity(
                                opacity: fdcp,
                                child: const Text(
                                  'AN FDCP CINEMATHEQUE CENTRE',
                                  style: TextStyle(fontSize: 10.5, letterSpacing: 2.4, fontWeight: FontWeight.w600, color: CustomerColors.muted),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                }),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A line of the title card rising into view from behind an invisible edge.
class _Reveal extends StatelessWidget {
  const _Reveal({required this.progress, required this.child});

  final double progress;
  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: FractionalTranslation(
          translation: Offset(0, 1 - progress),
          child: Opacity(opacity: progress, child: child),
        ),
      );
}
