import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../data/models/screening.dart';
import '../theme/customer_theme.dart';
import 'brand.dart';
import 'screening_chips.dart';

/// A screening as a tear-off ticket (after FDCP's Cinematheque listings):
///
///   ┌────────┬┄┬──────────────────────────────┐
///   │  SEP   │ ┆ DRAMA                         │
///   │   28   │ ┆ LUNGSOD NG ULAN               │
///   │  MON   │ ┆ 11:00 AM · Free · 1h 58m       │
///   │        │ ┆ 117 seats left      (RESERVE) │
///   └────────┴┄┴──────────────────────────────┘
///
/// Tapping the ticket opens the screening; the Reserve pill goes straight to seats.
class ScreeningCard extends StatelessWidget {
  const ScreeningCard({super.key, required this.screening, required this.now, required this.onTap, this.onReserve});

  final Screening screening;
  final DateTime now;
  final VoidCallback onTap;
  final VoidCallback? onReserve;

  static const stubWidth = 78.0;

  /// The gold line above the title: the film (if the event is named differently),
  /// otherwise its genres, or "Special programme" for events without a film.
  /// (Runtime lives in the meta line below, so it is never repeated here.)
  static String eyebrowFor(Screening s) {
    final movie = s.movie;
    if (movie == null) return 'Special programme';
    if (movie.title.toLowerCase() != s.eventTitle.toLowerCase()) return movie.title;
    return movie.genres.isEmpty ? 'Film screening' : movie.genres.take(2).join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final availability = availabilityOf(screening, now);
    final (seatsText, seatsColor, _) = seatsLabel(screening, now);
    final bookable = availability == Availability.open || availability == Availability.fewLeft;
    final dim = availability == Availability.closed;

    return Semantics(
      container: true,
      label: '${screening.eventTitle}, ${formatDateLong(screening.startAt)}, ${formatTime(screening.startAt)}, '
          '${screening.isPaid ? formatPeso(screening.priceCentavos ?? 0) : 'free'}, $seatsText',
      child: Material(
        color: CustomerColors.surface,
        elevation: 2,
        shadowColor: const Color(0x40141219),
        clipBehavior: Clip.antiAlias,
        shape: const TicketBorder(notchX: stubWidth),
        child: InkWell(
          onTap: onTap,
          customBorder: const TicketBorder(notchX: stubWidth),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: stubWidth,
                  color: dim ? CustomerColors.neutralTint : CustomerColors.stub,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: Space.lg),
                  child: Hero(
                    tag: 'date-${screening.id}',
                    child: Material(type: MaterialType.transparency, child: DateStub(date: screening.startAt, muted: dim)),
                  ),
                ),
                const Perforation(),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(Space.lg, Space.lg, Space.md, Space.md),
                    child: ExcludeSemantics(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Eyebrow(eyebrowFor(screening), maxLines: 1),
                          const SizedBox(height: 3),
                          Text(
                            screening.eventTitle.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: CcdType.display(20, color: dim ? CustomerColors.muted : CustomerColors.ink),
                          ),
                          const SizedBox(height: 6),
                          _MetaLine(screening: screening),
                          const SizedBox(height: Space.md),
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  seatsText,
                                  style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: seatsColor),
                                ),
                              ),
                              if (bookable)
                                GoldPill(label: 'Reserve', onPressed: onReserve ?? onTap)
                              else
                                GoldPill(label: availability == Availability.soldOut ? 'Sold out' : 'Closed', muted: true),
                            ],
                          ),
                        ],
                      ),
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

/// "11:00 AM · ₱150 · 1h 58m" — time bold, price in Oswald (has ₱).
class _MetaLine extends StatelessWidget {
  const _MetaLine({required this.screening});

  final Screening screening;

  @override
  Widget build(BuildContext context) {
    final runtime = screening.movie?.runtimeMinutes;
    return Text.rich(
      TextSpan(
        style: CcdType.meta,
        children: [
          TextSpan(text: formatTime(screening.startAt), style: const TextStyle(fontWeight: FontWeight.w700, color: CustomerColors.ink)),
          const TextSpan(text: '  ·  '),
          screening.isPaid
              ? TextSpan(text: formatPeso(screening.priceCentavos ?? 0), style: CcdType.money(14))
              : const TextSpan(text: 'Free'),
          if (runtime != null) TextSpan(text: '  ·  ${formatDuration(runtime)}'),
        ],
      ),
    );
  }
}
