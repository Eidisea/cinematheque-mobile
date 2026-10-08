import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/screening.dart';
import '../theme/customer_theme.dart';
import 'poster.dart';

/// The website's spotlight banner: the soonest films as white cards, the current one in
/// the middle with its neighbours peeking in. Each card: a big outlined number, the
/// poster on a gold offset block, a kicker ("Now showing" / "Opens Oct 12"), the title,
/// the next screening, tags and "Book seats". Plays by itself (the active dot fills as
/// the card's time runs); swiping or the pause button stops it. No autoplay when the
/// phone asks for reduced motion.
class SpotlightBanner extends StatefulWidget {
  const SpotlightBanner({super.key, required this.screenings, required this.now, required this.onOpen});

  /// The films to feature, one screening each — see [featured].
  final List<Screening> screenings;
  final DateTime now;
  final ValueChanged<Screening> onOpen;

  static const maxSlides = 5;
  static const slideDuration = Duration(seconds: 7);
  static const _nowShowingDays = 7; // as on the website

  /// Widget tests turn autoplay off so the screen can settle, and hide the banner where
  /// they test the list below it.
  @visibleForTesting
  static bool autoplay = true;
  static bool enabled = true;

  /// The soonest films (one card per film), each with its next screening that still has seats.
  static List<Screening> featured(List<Screening> upcoming, DateTime now) {
    final byFilm = <String, List<Screening>>{};
    for (final s in upcoming) {
      if (!s.isBookableAt(now)) continue;
      byFilm.putIfAbsent(s.movieId ?? s.eventTitle.toLowerCase(), () => []).add(s);
    }
    return [
      for (final shows in byFilm.values.take(maxSlides))
        shows.firstWhere((s) => s.availableSeatsAt(now) > 0, orElse: () => shows.first),
    ];
  }

  @override
  State<SpotlightBanner> createState() => _SpotlightBannerState();
}

class _SpotlightBannerState extends State<SpotlightBanner> with SingleTickerProviderStateMixin {
  final _pages = PageController(viewportFraction: 0.86);
  late final AnimationController _progress = AnimationController(vsync: this, duration: SpotlightBanner.slideDuration);
  int _current = 0;
  bool _paused = false;

  int get _count => widget.screenings.length;
  bool get _playing => SpotlightBanner.autoplay && !_paused && _count > 1 && !Motion.reduced(context);

  @override
  void initState() {
    super.initState();
    _progress.addStatusListener((status) {
      if (status == AnimationStatus.completed && _pages.hasClients) {
        _pages.animateToPage((_current + 1) % _count, duration: Motion.slow, curve: Motion.easeOut);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _restart();
  }

  @override
  void didUpdateWidget(SpotlightBanner old) {
    super.didUpdateWidget(old);
    if (_current >= _count && _count > 0) _current = 0;
  }

  void _restart() {
    if (_playing) {
      _progress.forward(from: 0);
    } else {
      _progress.stop();
    }
  }

  void _togglePause() {
    setState(() => _paused = !_paused);
    _restart();
  }

  @override
  void dispose() {
    _progress.dispose();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_count == 0) return const SizedBox.shrink();
    final scale = MediaQuery.textScalerOf(context).scale(1).clamp(1.0, 1.6);

    return Semantics(
      container: true,
      label: 'Featured films',
      child: Column(
        children: [
          SizedBox(
            height: 470 + 60 * (scale - 1),
            child: NotificationListener<ScrollStartNotification>(
              // A swipe means the visitor is in control: stop playing.
              onNotification: (n) {
                if (n.dragDetails != null && _playing) _togglePause();
                return false;
              },
              child: PageView.builder(
                controller: _pages,
                itemCount: _count,
                onPageChanged: (i) {
                  setState(() => _current = i);
                  _restart();
                },
                itemBuilder: (context, i) => AnimatedBuilder(
                  animation: _pages,
                  builder: (context, child) {
                    final page = _pages.hasClients && _pages.position.haveDimensions ? _pages.page! : _current.toDouble();
                    final distance = (page - i).abs().clamp(0.0, 1.0);
                    return Transform.scale(
                      scale: 1 - 0.06 * distance,
                      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: child),
                    );
                  },
                  child: _Slide(
                    screening: widget.screenings[i],
                    index: i,
                    of: _count,
                    now: widget.now,
                    current: i == _current,
                    onOpen: () => i == _current
                        ? widget.onOpen(widget.screenings[i])
                        : _pages.animateToPage(i, duration: Motion.slow, curve: Motion.easeOut),
                  ),
                ),
              ),
            ),
          ),
          if (_count > 1) ...[
            const SizedBox(height: Space.lg),
            _Controls(
              count: _count,
              current: _current,
              paused: !_playing,
              progress: _progress,
              onPause: _togglePause,
              onDot: (i) => _pages.animateToPage(i, duration: Motion.slow, curve: Motion.easeOut),
              titles: [for (final s in widget.screenings) s.eventTitle],
            ),
          ],
        ],
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({
    required this.screening,
    required this.index,
    required this.of,
    required this.now,
    required this.current,
    required this.onOpen,
  });

  final Screening screening;
  final int index;
  final int of;
  final DateTime now;
  final bool current;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = screening;
    final soon = !s.startAt.isBefore(now.add(const Duration(days: SpotlightBanner._nowShowingDays)));
    final kicker = soon ? 'Opens ${DateFormat('MMM d').format(toManila(s.startAt))}' : 'Now showing';
    final movie = s.movie;
    final facts = [
      if (movie?.runtimeMinutes != null) formatDuration(movie!.runtimeMinutes!),
      if (movie != null && movie.genres.isNotEmpty) movie.genres.take(2).join(' · '),
    ].join(' · ');
    final hasSeats = s.availableSeatsAt(now) > 0;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onOpen,
          child: PosterOnBlock(screening: s, width: 112, offset: 9),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Container(width: 26, height: 2, color: CustomerColors.goldText),
            const SizedBox(width: 10),
            Flexible(
              child: Text(
                kicker.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.4,
                  color: CustomerColors.goldText,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          s.eventTitle.toUpperCase(),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: CcdType.display(32, spacing: 0.2).copyWith(height: 1),
        ),
        const SizedBox(height: 10),
        Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 14, color: CustomerColors.muted),
            children: [
              const TextSpan(text: 'Next screening '),
              TextSpan(
                text: '${formatDateShort(s.startAt)} · ${formatTime(s.startAt)}',
                style: const TextStyle(fontWeight: FontWeight.w600, color: CustomerColors.ink),
              ),
            ],
          ),
        ),
        if (facts.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            facts,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, color: CustomerColors.muted),
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _Tag(s.isPaid && s.priceCentavos != null ? formatPeso(s.priceCentavos!) : 'Free', money: s.isPaid),
          ],
        ),
        const SizedBox(height: 20),
        _BookButton(label: hasSeats ? 'Book seats' : 'Details', onPressed: onOpen),
      ],
    );

    return Semantics(
      container: true,
      label: '${index + 1} of $of: ${s.eventTitle}',
      child: AnimatedOpacity(
        duration: Motion.medium,
        opacity: current ? 1 : 0.55,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: CustomerColors.surface,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: CustomerColors.border),
            boxShadow: const [BoxShadow(color: Color(0x59121212), blurRadius: 48, spreadRadius: -28, offset: Offset(0, 22))],
          ),
          child: Stack(
            children: [
              // A faint spotlight cone from the upper right…
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment(0.7, -1),
                      radius: 0.9,
                      colors: [Color(0x2EEBBC00), Color(0x00EBBC00)],
                    ),
                  ),
                ),
              ),
              // …a gold rule along the top edge…
              const Positioned(
                left: 0,
                right: 0,
                top: 0,
                child: SizedBox(
                  height: 4,
                  child: DecoratedBox(decoration: BoxDecoration(gradient: CustomerColors.goldGradient)),
                ),
              ),
              // …and the big outlined number.
              Positioned(
                right: 16,
                top: 8,
                child: ExcludeSemantics(
                  child: Text(
                    (index + 1).toString().padLeft(2, '0'),
                    style: CcdType.display(120, spacing: -2).copyWith(
                      height: 1,
                      foreground: Paint()
                        ..style = PaintingStyle.stroke
                        ..strokeWidth = 2
                        ..color = const Color(0x1A18181B),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
                child: LayoutBuilder(
                  builder: (context, box) => FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.topLeft,
                    child: SizedBox(width: box.maxWidth, child: content),
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

/// Cream tag with a gold edge, as on the website ("Free", "₱150", the programme).
class _Tag extends StatelessWidget {
  const _Tag(this.label, {this.money = false});

  final String label;
  final bool money;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: CustomerColors.stub,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: CustomerColors.perforation),
      ),
      child: Text(
        money ? label : label.toUpperCase(),
        style: money
            ? CcdType.money(13, color: CustomerColors.goldText)
            : const TextStyle(
                fontSize: 10.5,
                height: 1.2,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
                color: CustomerColors.goldText,
              ),
      ),
    );
  }
}

/// The website's gold pill button.
class _BookButton extends StatelessWidget {
  const _BookButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: CustomerColors.goldGradient,
        borderRadius: BorderRadius.circular(Radii.pill),
        boxShadow: const [BoxShadow(color: Color(0x40CC8500), blurRadius: 16, offset: Offset(0, 6))],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
            child: Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: CustomerColors.ink),
            ),
          ),
        ),
      ),
    );
  }
}

/// Pause / play and one dot per film; the active dot fills while its card is shown.
class _Controls extends StatelessWidget {
  const _Controls({
    required this.count,
    required this.current,
    required this.paused,
    required this.progress,
    required this.onPause,
    required this.onDot,
    required this.titles,
  });

  final int count;
  final int current;
  final bool paused;
  final Animation<double> progress;
  final VoidCallback onPause;
  final ValueChanged<int> onDot;
  final List<String> titles;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(6, 6, 14, 6),
      decoration: BoxDecoration(
        color: CustomerColors.surface,
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: CustomerColors.border),
        boxShadow: const [BoxShadow(color: Color(0x47141219), blurRadius: 20, spreadRadius: -10, offset: Offset(0, 6))],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              iconSize: 16,
              tooltip: paused ? 'Play slideshow' : 'Pause slideshow',
              onPressed: onPause,
              icon: Icon(paused ? Icons.play_arrow_rounded : Icons.pause_rounded, color: const Color(0xFF18181B)),
            ),
          ),
          const SizedBox(width: 4),
          for (var i = 0; i < count; i++)
            Semantics(
              button: true,
              selected: i == current,
              label: 'Show ${titles[i]}',
              excludeSemantics: true,
              child: GestureDetector(
                onTap: () => onDot(i),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 12),
                  child: AnimatedContainer(
                    duration: Motion.medium,
                    curve: Motion.easeOut,
                    width: i == current ? 36 : 8,
                    height: 8,
                    clipBehavior: Clip.antiAlias,
                    decoration: BoxDecoration(
                      color: i == current ? const Color(0x4DEBBC00) : const Color(0x3818181B),
                      borderRadius: BorderRadius.circular(Radii.pill),
                    ),
                    child: i != current
                        ? null
                        : AnimatedBuilder(
                            animation: progress,
                            builder: (context, _) => FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: paused ? 1 : progress.value,
                              child: const ColoredBox(color: CustomerColors.gold),
                            ),
                          ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
