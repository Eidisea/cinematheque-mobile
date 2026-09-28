import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting.dart';
import '../../data/models/movie.dart';
import '../../data/models/screening.dart';
import '../customer_services.dart';
import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/film_info.dart';
import '../widgets/poster.dart';
import '../widgets/screening_card.dart';
import '../widgets/screening_chips.dart';
import '../widgets/state_views.dart';

/// One screening: the film header, the facts on a ticket strip, the film, other dates
/// of the same film, and "Choose seats".
class ScreeningDetailsScreen extends StatefulWidget {
  const ScreeningDetailsScreen({super.key, required this.screeningId});

  final String screeningId;

  @override
  State<ScreeningDetailsScreen> createState() => _ScreeningDetailsScreenState();
}

class _ScreeningDetailsScreenState extends State<ScreeningDetailsScreen> {
  Stream<Screening?>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= CustomerServices.of(context).catalog.watchScreening(widget.screeningId);
  }

  @override
  Widget build(BuildContext context) {
    final now = CustomerServices.of(context).clock.now();

    return StreamBuilder<Screening?>(
      stream: _stream,
      builder: (context, snapshot) {
        final screening = snapshot.data;
        final Widget body;
        if (snapshot.hasError) {
          body = ErrorView(
            onRetry: () => setState(() => _stream = CustomerServices.of(context).catalog.watchScreening(widget.screeningId)),
          );
        } else if (snapshot.connectionState == ConnectionState.waiting && screening == null) {
          body = const LoadingView();
        } else if (screening == null) {
          body = const MessageView(
            icon: Icons.event_busy_outlined,
            title: 'Screening not found',
            message: 'It may have been removed or rescheduled. Please check the screenings list.',
          );
        } else {
          body = _Details(screening: screening, now: now);
        }

        return Scaffold(
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            leading: const RoundBackButton(),
            automaticallyImplyLeading: false,
          ),
          body: body,
          bottomNavigationBar: screening == null ? null : _BookingBar(screening: screening, now: now),
        );
      },
    );
  }
}

/// White circular back button that floats over light headers.
class RoundBackButton extends StatelessWidget {
  const RoundBackButton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Material(
        color: CustomerColors.surface.withValues(alpha: 0.92),
        shape: const CircleBorder(side: BorderSide(color: CustomerColors.border)),
        child: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_rounded, size: 20),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

class _Details extends StatefulWidget {
  const _Details({required this.screening, required this.now});

  final Screening screening;
  final DateTime now;

  @override
  State<_Details> createState() => _DetailsState();
}

class _DetailsState extends State<_Details> {
  // Kept in state so live updates of the screening don't restart these lookups.
  String? _movieId;
  Stream<Movie?>? _film;
  Stream<List<Screening>>? _otherDates;

  void _subscribe() {
    _movieId = widget.screening.movieId;
    final catalog = CustomerServices.of(context).catalog;
    _film = _movieId == null ? null : catalog.watchMovie(_movieId!);
    _otherDates = _movieId == null ? null : catalog.watchScreeningsForMovie(_movieId!, from: widget.now);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_film == null && _otherDates == null) _subscribe();
  }

  @override
  void didUpdateWidget(covariant _Details oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.screening.movieId != _movieId) _subscribe();
  }

  @override
  Widget build(BuildContext context) {
    final screening = widget.screening;
    final now = widget.now;
    final movie = screening.movie;
    final top = MediaQuery.paddingOf(context).top;

    return ListView(
      padding: EdgeInsets.zero,
      children: [
        // ---- Film header (light, like the home hero) ----
        Container(
          decoration: const BoxDecoration(
            color: CustomerColors.heroTint,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              const Positioned(left: 0, right: 0, bottom: 0, child: DavaoSkyline(height: 56, opacity: 0.08)),
              ContentWidth(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(Space.gutter, top + 52, Space.gutter, Space.xxl),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // No caption on the art: the title is right beside it.
                      PosterImage(url: movie?.posterUrl, title: movie?.title ?? screening.eventTitle, width: 118, showTitle: false),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Eyebrow(ScreeningCard.eyebrowFor(screening)),
                            const SizedBox(height: 6),
                            Semantics(
                              header: true,
                              child: Text(screening.eventTitle.toUpperCase(), style: CcdType.display(28, spacing: 0.6)),
                            ),
                            const SizedBox(height: Space.md),
                            PriceChip(screening: screening),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        ContentWidth(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xxl),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _FactsTicket(screening: screening, now: now),
                if (_film != null)
                  StreamBuilder<Movie?>(
                    stream: _film,
                    builder: (context, snap) {
                      final film = snap.data;
                      if (film == null) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: Space.xxl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeading('About the film', size: 20),
                            const SizedBox(height: Space.lg),
                            FilmInfo(movie: film, showSynopsisTitle: false),
                            TextButton.icon(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero),
                              onPressed: () => context.push('/movies/${film.id}'),
                              iconAlignment: IconAlignment.end,
                              icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                              label: const Text('More about this film'),
                            ),
                          ],
                        ),
                      );
                    },
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(top: Space.xl),
                    child: Text(
                      'A special programme — such as a festival block, a talk or a shorts selection — rather than a single film.',
                      style: TextStyle(color: CustomerColors.muted, height: 1.5),
                    ),
                  ),
                if (_otherDates != null)
                  StreamBuilder<List<Screening>>(
                    stream: _otherDates,
                    builder: (context, snap) {
                      final others = (snap.data ?? const <Screening>[])
                          .where((s) => s.id != screening.id && s.isBookableAt(now))
                          .toList();
                      if (others.isEmpty) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: Space.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SectionHeading('Other dates for this film', size: 20),
                            const SizedBox(height: Space.lg),
                            SizedBox(
                              height: 112,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                clipBehavior: Clip.none,
                                itemCount: others.length,
                                separatorBuilder: (_, _) => const SizedBox(width: Space.md),
                                itemBuilder: (context, i) => MiniTicket(
                                  screening: others[i],
                                  onTap: () => context.pushReplacement('/screenings/${others[i].id}'),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Date stub + time, admission and seats — the screening's facts as a ticket.
class _FactsTicket extends StatelessWidget {
  const _FactsTicket({required this.screening, required this.now});

  final Screening screening;
  final DateTime now;

  static const _stub = 84.0;

  @override
  Widget build(BuildContext context) {
    final left = screening.availableSeatsAt(now);
    final taken = (screening.capacity - left).clamp(0, screening.capacity);
    final (seatsText, seatsColor, _) = seatsLabel(screening, now);

    return Material(
      color: CustomerColors.surface,
      elevation: 2,
      shadowColor: const Color(0x40141219),
      clipBehavior: Clip.antiAlias,
      shape: const TicketBorder(notchX: _stub),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: _stub,
              color: CustomerColors.stub,
              alignment: Alignment.center,
              child: Hero(
                tag: 'date-${screening.id}',
                child: Material(type: MaterialType.transparency, child: DateStub(date: screening.startAt, dayStyleSize: 38)),
              ),
            ),
            const Perforation(),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatDateLong(screening.startAt), style: const TextStyle(fontSize: 13, color: CustomerColors.muted)),
                    const SizedBox(height: 2),
                    Text(formatTimeRange(screening.startAt, screening.endAt), style: CcdType.display(22, spacing: 0.2)),
                    const SizedBox(height: Space.md),
                    Text.rich(
                      TextSpan(
                        style: const TextStyle(fontSize: 13.5, color: CustomerColors.ink),
                        children: [
                          const TextSpan(text: 'Admission  ', style: TextStyle(color: CustomerColors.muted)),
                          screening.isPaid
                              ? TextSpan(text: formatPeso(screening.priceCentavos ?? 0), style: CcdType.money(15))
                              : const TextSpan(text: 'Free', style: TextStyle(fontWeight: FontWeight.w600)),
                          TextSpan(
                            text: screening.isPaid ? ' per seat · pay online' : ' · approved by staff',
                            style: const TextStyle(color: CustomerColors.muted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.md),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(Radii.pill),
                      child: LinearProgressIndicator(
                        value: screening.capacity == 0 ? 0 : taken / screening.capacity,
                        minHeight: 6,
                        backgroundColor: CustomerColors.neutralTint,
                        valueColor: const AlwaysStoppedAnimation(CustomerColors.gold),
                        semanticsLabel: 'Seats reserved',
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      availabilityOf(screening, now) == Availability.open ? '$left of ${screening.capacity} seats left' : seatsText,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: seatsColor),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact ticket (date + time + price) — "Other dates" rows.
class MiniTicket extends StatelessWidget {
  const MiniTicket({super.key, required this.screening, required this.onTap});

  final Screening screening;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${formatDateLong(screening.startAt)}, ${formatTime(screening.startAt)}',
      child: SizedBox(
        width: 168,
        child: Material(
          color: CustomerColors.surface,
          elevation: 1,
          shadowColor: const Color(0x33141219),
          clipBehavior: Clip.antiAlias,
          shape: const TicketBorder(notchX: 62, notchRadius: 7),
          child: InkWell(
            onTap: onTap,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 62,
                  color: CustomerColors.stub,
                  alignment: Alignment.center,
                  child: DateStub(date: screening.startAt, dayStyleSize: 26),
                ),
                const Perforation(inset: 10),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.md),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(formatTime(screening.startAt), style: CcdType.display(17, spacing: 0.2)),
                        const SizedBox(height: 4),
                        screening.isPaid
                            ? Text(formatPeso(screening.priceCentavos ?? 0),
                                style: CcdType.money(14, color: CustomerColors.goldText))
                            : const Text('Free',
                                style: TextStyle(fontSize: 13, color: CustomerColors.success, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Sticky bottom bar with the booking action.
class _BookingBar extends StatelessWidget {
  const _BookingBar({required this.screening, required this.now});

  final Screening screening;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final availability = availabilityOf(screening, now);
    final canBook = availability == Availability.open || availability == Availability.fewLeft;
    final note = switch (availability) {
      Availability.closed => 'This screening has started. Booking is closed.',
      Availability.soldOut => 'All seats have been reserved.',
      _ => null,
    };

    return BottomActionBar(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (note != null) ...[
            Text(note, textAlign: TextAlign.center, style: const TextStyle(color: CustomerColors.muted, fontSize: 13)),
            const SizedBox(height: Space.sm),
          ],
          GoldButton(
            label: switch (availability) {
              Availability.closed => 'Booking closed',
              Availability.soldOut => 'Sold out',
              _ => 'Choose seats',
            },
            icon: canBook ? Icons.arrow_forward_rounded : null,
            onPressed: canBook ? () => context.push('/screenings/${screening.id}/seats') : null,
          ),
        ],
      ),
    );
  }
}
