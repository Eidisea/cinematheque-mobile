import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../auth/staff_session.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/screening_table.dart';

/// The website admin's dashboard, from live data: the date and three figures (upcoming
/// screenings, bookings awaiting payment, paid this week), today's screenings, the next 7
/// days as a table (seats booked, admitted), and on the side what needs action (free
/// bookings to approve, refunds due) and the most recent bookings.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});

  final StaffSession session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<List<Reservation>>? _refundRowsSub;
  StreamSubscription<Map<String, int>>? _admittedSub;
  List<String> _refundIds = const [];
  List<String> _todayIds = const [];

  List<Screening>? _screenings;
  List<Reservation>? _pending;
  List<Reservation>? _recent;
  List<Payment>? _paidThisWeek;
  List<Payment> _refunds = const [];
  List<Reservation> _refundRows = const [];
  Map<String, int> _admitted = const {};
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isEmpty) _subscribe();
  }

  void _subscribe() {
    final services = StaffServices.of(context);
    final repo = services.data;
    final now = services.clock.now();
    final startOfToday = manilaDay(now).subtract(const Duration(hours: 8)); // Manila midnight, as an instant

    void onError(Object e) {
      if (mounted) setState(() => _error = e);
    }

    _subs.addAll([
      repo.watchScreeningsFrom(startOfToday).listen((v) {
        setState(() => _screenings = v);
        _watchAdmitted();
      }, onError: onError),
      repo.watchPendingReservations().listen((v) => setState(() => _pending = v), onError: onError),
      repo.watchRecentReservations().listen((v) => setState(() => _recent = v), onError: onError),
      repo
          .watchPaymentsPaidSince(now.subtract(const Duration(days: 7)))
          .listen((v) => setState(() => _paidThisWeek = v), onError: onError),
      repo.watchRefundsDue().listen((v) {
        setState(() => _refunds = v);
        final ids = [for (final p in v) p.reservationId];
        if (ids.join() != _refundIds.join()) {
          _refundIds = ids;
          _refundRowsSub?.cancel();
          _refundRowsSub = repo.watchReservations(ids).listen((r) => setState(() => _refundRows = r), onError: onError);
        }
      }, onError: onError),
    ]);
  }

  /// Admitted counts only matter for screenings that are today (later ones show "—").
  void _watchAdmitted() {
    final now = StaffServices.of(context).clock.now();
    final ids = [
      for (final s in _screenings ?? const <Screening>[])
        if (manilaDay(s.startAt) == manilaDay(now)) s.id,
    ];
    if (ids.join() == _todayIds.join()) return;
    _todayIds = ids;
    _admittedSub?.cancel();
    _admittedSub = StaffServices.of(context).data.watchAdmittedCounts(ids).listen((v) => setState(() => _admitted = v));
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _refundRowsSub?.cancel();
    _admittedSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = StaffServices.of(context).clock.now();
    final today = manilaDay(now);
    final screenings = _screenings ?? const <Screening>[];
    final pending = _pending ?? const <Reservation>[];

    final todays = [
      for (final s in screenings)
        if (manilaDay(s.startAt) == today) s,
    ];
    final week = [
      for (final s in screenings)
        if (manilaDay(s.startAt).isAfter(today) && manilaDay(s.startAt).difference(today).inDays <= 7) s,
    ];
    final upcoming = screenings.where((s) => s.startAt.isAfter(now)).length;
    final awaitingPayment = pending
        .where((r) => r.screening.type == ScreeningType.paid && (r.expiresAt?.isAfter(now) ?? false))
        .length;
    final paidCentavos = (_paidThisWeek ?? const <Payment>[])
        .where((p) => p.status == PaymentStatus.verified && !p.needsRefund)
        .fold<int>(0, (sum, p) => sum + p.amountCentavos);

    final toApprove = pending.where((r) => r.screening.type == ScreeningType.free && r.screening.startAt.isAfter(now)).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final pendingBy = <String, int>{};
    for (final r in pending) {
      final waiting = r.screening.type == ScreeningType.free || (r.expiresAt?.isAfter(now) ?? false);
      if (waiting) pendingBy.update(r.screeningId, (n) => n + 1, ifAbsent: () => 1);
    }
    final refundIds = {for (final p in _refunds) p.reservationId};

    final loading = _screenings == null || _pending == null || _recent == null || _paidThisWeek == null;
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;

    final main = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(
          title: 'Today',
          child: todays.isEmpty
              ? _NextUp(
                  next: week.isNotEmpty ? week.first : (screenings.where((s) => s.startAt.isAfter(now)).firstOrNull),
                  now: now,
                )
              : ScreeningTable(screenings: todays, now: now, pendingBy: pendingBy, admitted: _admitted, grouped: false),
        ),
        const SizedBox(height: 28),
        AdminSection(
          title: 'Next 7 days',
          trailing: TextLink('Attendance', onTap: () => context.go('/attendance')),
          child: week.isEmpty
              ? const QuietText('Nothing scheduled.')
              : ScreeningTable(screenings: week, now: now, pendingBy: pendingBy, admitted: _admitted),
        ),
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSection(
          title: 'Needs action',
          count: toApprove.length + _refundRows.length,
          trailing: toApprove.length > 5 ? TextLink('All ${toApprove.length}', onTap: () => context.go('/reservations')) : null,
          child: toApprove.isEmpty && _refundRows.isEmpty
              ? const QuietText('Nothing to approve or refund.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (toApprove.isNotEmpty) ...[
                      const SectionLabel('To approve'),
                      Panel(
                        children: [
                          for (final r in toApprove.take(5))
                            _BookingRow(reservation: r, now: now, showState: false, action: 'Review'),
                        ],
                      ),
                    ],
                    if (_refundRows.isNotEmpty) ...[
                      const SectionLabel('Refunds due'),
                      Panel(
                        children: [for (final r in _refundRows) _BookingRow(reservation: r, now: now, showState: false)],
                      ),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 28),
        AdminSection(
          title: 'Recent bookings',
          trailing: TextLink('View all', onTap: () => context.go('/reservations')),
          child: (_recent ?? const []).isEmpty
              ? const QuietText('No bookings yet.')
              : Panel(
                  children: [
                    for (final r in _recent!) _BookingRow(reservation: r, now: now, refundDue: refundIds.contains(r.id)),
                  ],
                ),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1440),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(formatDateLong(now), style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
              const SizedBox(height: 2),
              Row(
                children: [
                  const Expanded(child: PageTitle('Dashboard')),
                  AdminButton(label: 'New screening', onPressed: () => context.go('/attendance/new')),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 18,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  Figure(
                    loading ? '–' : '$upcoming',
                    upcoming == 1 ? 'upcoming screening' : 'upcoming screenings',
                    onTap: () => context.go('/attendance'),
                  ),
                  Figure(loading ? '–' : '$awaitingPayment', 'awaiting payment', onTap: () => context.go('/reservations')),
                  Figure(loading ? '–' : formatPeso(paidCentavos), 'paid this week', onTap: () => context.go('/reports')),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                const Notice('Could not load the dashboard. Check your connection and reload the page.')
              else if (loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                LayoutBuilder(
                  builder: (context, box) => box.maxWidth >= 1000
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: main),
                            const SizedBox(width: 24),
                            SizedBox(width: 360, child: side),
                          ],
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [main, const SizedBox(height: 28), side],
                        ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Pieces, styled as on the website's admin ────────────────────────────────────

/// "No screenings today. Next: Malvarosa, Friday at 1:00 PM."
class _NextUp extends StatelessWidget {
  const _NextUp({required this.next, required this.now});

  final Screening? next;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = next;
    if (s == null) return const QuietText('No screenings today.');
    final inWeek = manilaDay(s.startAt).difference(manilaDay(now)).inDays <= 7;
    final when = inWeek
        ? ', ${DateFormat('EEEE').format(toManila(s.startAt))} at ${formatTime(s.startAt)}.'
        : ' on ${DateFormat('MMM d').format(toManila(s.startAt))}.';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(
        TextSpan(
          style: const TextStyle(color: StaffColors.textMuted),
          children: [
            const TextSpan(text: 'No screenings today. Next: '),
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: InkWell(
                onTap: () => context.go('/attendance/${s.id}'),
                child: Text(s.eventTitle, style: const TextStyle(color: StaffColors.brand)),
              ),
            ),
            TextSpan(text: when),
          ],
        ),
      ),
    );
  }
}

/// One booking: who · reference, seats, amount, screening · state · next action · how long ago.
class _BookingRow extends StatelessWidget {
  const _BookingRow({required this.reservation, required this.now, this.showState = true, this.action, this.refundDue = false});

  final Reservation reservation;
  final DateTime now;
  final bool showState;
  final String? action;
  final bool refundDue;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final seats = r.seats.length;
    final (label, tone) = bookingState(r, now, refundDue: refundDue);

    return Material(
      color: StaffColors.surface,
      child: InkWell(
        onTap: () => context.go('/reservations/${r.id}'),
        hoverColor: StaffColors.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${r.booker.firstName} ${r.booker.lastName}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 1),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
                  children: [
                    TextSpan(text: r.bookingReference, style: staffMono.copyWith(fontSize: 12.5)),
                    TextSpan(
                      text:
                          ' · $seats ${seats == 1 ? 'seat' : 'seats'}'
                          '${r.totalCentavos > 0 ? ' · ${formatPeso(r.totalCentavos)}' : ''}'
                          ' · ${r.screening.eventTitle}, ${DateFormat('MMM d').format(toManila(r.screening.startAt))}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (showState) StateLabel(label, tone),
                  const Spacer(),
                  if (action != null) ...[
                    AdminButton(label: action!, small: true, onPressed: () => context.go('/reservations/${r.id}')),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    timeAgo(r.createdAt, now),
                    style: const TextStyle(
                      fontSize: 12,
                      color: StaffColors.textMuted,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
