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
    final repo = services.dashboard;
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
    final ids = [for (final s in _screenings ?? const <Screening>[]) if (manilaDay(s.startAt) == manilaDay(now)) s.id];
    if (ids.join() == _todayIds.join()) return;
    _todayIds = ids;
    _admittedSub?.cancel();
    _admittedSub = StaffServices.of(context).dashboard.watchAdmittedCounts(ids).listen((v) => setState(() => _admitted = v));
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

    final todays = [for (final s in screenings) if (manilaDay(s.startAt) == today) s];
    final week = [
      for (final s in screenings)
        if (manilaDay(s.startAt).isAfter(today) && manilaDay(s.startAt).difference(today).inDays <= 7) s,
    ];
    final upcoming = screenings.where((s) => s.startAt.isAfter(now)).length;
    final awaitingPayment =
        pending.where((r) => r.screening.type == ScreeningType.paid && (r.expiresAt?.isAfter(now) ?? false)).length;
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
        _Block(
          title: 'Today',
          child: todays.isEmpty
              ? _NextUp(next: week.isNotEmpty ? week.first : (screenings.where((s) => s.startAt.isAfter(now)).firstOrNull), now: now)
              : _ScreeningTable(screenings: todays, now: now, pendingBy: pendingBy, admitted: _admitted, grouped: false),
        ),
        const SizedBox(height: 28),
        _Block(
          title: 'Next 7 days',
          trailing: _Link('Attendance', onTap: () => context.go('/attendance')),
          child: week.isEmpty
              ? const _Quiet('Nothing scheduled.')
              : _ScreeningTable(screenings: week, now: now, pendingBy: pendingBy, admitted: _admitted),
        ),
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Block(
          title: 'Needs action',
          count: toApprove.length + _refundRows.length,
          trailing: toApprove.length > 5 ? _Link('All ${toApprove.length}', onTap: () => context.go('/reservations')) : null,
          child: toApprove.isEmpty && _refundRows.isEmpty
              ? const _Quiet('Nothing to approve or refund.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (toApprove.isNotEmpty) ...[
                      const _DayLabel('To approve'),
                      _Rows([
                        for (final r in toApprove.take(5))
                          _BookingRow(reservation: r, now: now, showState: false, action: 'Review'),
                      ]),
                    ],
                    if (_refundRows.isNotEmpty) ...[
                      const _DayLabel('Refunds due'),
                      _Rows([for (final r in _refundRows) _BookingRow(reservation: r, now: now, showState: false)]),
                    ],
                  ],
                ),
        ),
        const SizedBox(height: 28),
        _Block(
          title: 'Recent bookings',
          trailing: _Link('View all', onTap: () => context.go('/reservations')),
          child: (_recent ?? const []).isEmpty
              ? const _Quiet('No bookings yet.')
              : _Rows([
                  for (final r in _recent!)
                    _BookingRow(reservation: r, now: now, refundDue: refundIds.contains(r.id)),
                ]),
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
              Semantics(
                header: true,
                child: const Text('Dashboard', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 18,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.end,
                children: [
                  _Figure(loading ? '–' : '$upcoming', upcoming == 1 ? 'upcoming screening' : 'upcoming screenings',
                      onTap: () => context.go('/attendance')),
                  _Figure(loading ? '–' : '$awaitingPayment', 'awaiting payment', onTap: () => context.go('/reservations')),
                  _Figure(loading ? '–' : formatPeso(paidCentavos), 'paid this week', onTap: () => context.go('/reports')),
                ],
              ),
              const SizedBox(height: 16),
              if (_error != null)
                const _Alert('Could not load the dashboard. Check your connection and reload the page.')
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

class _Figure extends StatelessWidget {
  const _Figure(this.value, this.label, {required this.onTap});

  final String value;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Text.rich(TextSpan(children: [
        TextSpan(
          text: '$value ',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: StaffColors.text, fontFeatures: [FontFeature.tabularFigures()]),
        ),
        TextSpan(text: label, style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
      ])),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.title, required this.child, this.trailing, this.count = 0});

  final String title;
  final Widget child;
  final Widget? trailing;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(title.toUpperCase(),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.56, color: StaffColors.gray600)),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: StaffColors.warningTint,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: StaffColors.warningBorder),
                ),
                child: Text('$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w600, color: StaffColors.warning)),
              ),
            ],
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class _Link extends StatelessWidget {
  const _Link(this.label, {required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Text(label, style: const TextStyle(fontSize: 13, color: StaffColors.brand)),
      );
}

class _Quiet extends StatelessWidget {
  const _Quiet(this.text);

  final String text;

  @override
  Widget build(BuildContext context) =>
      Padding(padding: const EdgeInsets.only(top: 2), child: Text(text, style: const TextStyle(color: StaffColors.textMuted)));
}

class _Alert extends StatelessWidget {
  const _Alert(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: StaffColors.dangerTint,
          border: Border.all(color: StaffColors.dangerBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: const TextStyle(color: StaffColors.danger)),
      );
}

/// "No screenings today. Next: Malvarosa, Friday at 1:00 PM."
class _NextUp extends StatelessWidget {
  const _NextUp({required this.next, required this.now});

  final Screening? next;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final s = next;
    if (s == null) return const _Quiet('No screenings today.');
    final inWeek = manilaDay(s.startAt).difference(manilaDay(now)).inDays <= 7;
    final when = inWeek
        ? ', ${DateFormat('EEEE').format(toManila(s.startAt))} at ${formatTime(s.startAt)}.'
        : ' on ${DateFormat('MMM d').format(toManila(s.startAt))}.';
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Text.rich(TextSpan(
        style: const TextStyle(color: StaffColors.textMuted),
        children: [
          const TextSpan(text: 'No screenings today. Next: '),
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InkWell(
              onTap: () => context.go('/attendance'),
              child: Text(s.eventTitle, style: const TextStyle(color: StaffColors.brand)),
            ),
          ),
          TextSpan(text: when),
        ],
      )),
    );
  }
}

/// Screenings as a table, grouped by day: time · screening · seats booked · admitted.
class _ScreeningTable extends StatelessWidget {
  const _ScreeningTable({
    required this.screenings,
    required this.now,
    required this.pendingBy,
    required this.admitted,
    this.grouped = true,
  });

  final List<Screening> screenings;
  final DateTime now;
  final Map<String, int> pendingBy;
  final Map<String, int> admitted;
  final bool grouped;

  static const _timeWidth = 104.0;
  static const _bookedWidth = 150.0;
  static const _admittedWidth = 84.0;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.gray600);
    final today = manilaDay(now);
    final rows = <Widget>[];
    DateTime? day;

    for (final s in screenings) {
      final d = manilaDay(s.startAt);
      if (grouped && d != day) {
        day = d;
        final diff = d.difference(today).inDays;
        rows.add(_GroupRow(
          label: switch (diff) { 0 => 'Today', 1 => 'Tomorrow', _ => DateFormat('EEEE').format(d) },
          date: DateFormat('MMMM d, y').format(d),
        ));
      }
      final booked = s.seatHolds.values.where((h) => h.isActiveAt(now)).length;
      final waiting = pendingBy[s.id] ?? 0;
      final isToday = d == today;
      rows.add(_Row(
        onTap: () => context.go('/attendance'),
        children: [
          SizedBox(width: _timeWidth, child: Text(formatTime(s.startAt), style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.eventTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
                    children: [
                      TextSpan(text: s.isPaid && s.priceCentavos != null ? formatPeso(s.priceCentavos!) : 'Free'),
                      if (waiting > 0) ...[
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: '$waiting ${s.isPaid ? 'awaiting payment' : 'to approve'}',
                          style: const TextStyle(color: StaffColors.warning),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _bookedWidth,
            child: Row(
              children: [
                _Fill(fraction: s.capacity == 0 ? 0 : booked / s.capacity),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('$booked / ${s.capacity}', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _admittedWidth,
            child: Text(isToday ? '${admitted[s.id] ?? 0}' : '—', textAlign: TextAlign.right),
          ),
        ],
      ));
    }

    return _Panel(
      children: [
        Container(
          color: StaffColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(
            children: [
              SizedBox(width: _timeWidth, child: Text('TIME', style: head)),
              Expanded(child: Text('SCREENING', style: head)),
              SizedBox(width: _bookedWidth, child: Text('BOOKED', style: head)),
              SizedBox(width: _admittedWidth, child: Text('ADMITTED', style: head, textAlign: TextAlign.right)),
            ],
          ),
        ),
        ...rows,
      ],
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: StaffColors.surface,
        border: Border.all(color: StaffColors.border),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            children[i],
          ],
        ],
      ),
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.label, required this.date});

  final String label;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: StaffColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        TextSpan(text: '   $date', style: const TextStyle(color: StaffColors.textMuted, fontSize: 13)),
      ])),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.children, required this.onTap});

  final List<Widget> children;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StaffColors.surface,
      child: InkWell(
        onTap: onTap,
        hoverColor: StaffColors.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
        ),
      ),
    );
  }
}

class _Fill extends StatelessWidget {
  const _Fill({required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 56,
        height: 4,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: StaffColors.gray200)),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: const ColoredBox(color: StaffColors.gray600),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayLabel extends StatelessWidget {
  const _DayLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
        child: Text(text.toUpperCase(),
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.textMuted)),
      );
}

class _Rows extends StatelessWidget {
  const _Rows(this.rows);

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) => _Panel(children: rows);
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
    final (label, tone) = _stateOf(r, now, refundDue);

    return Material(
      color: StaffColors.surface,
      child: InkWell(
        onTap: () => context.go('/reservations'),
        hoverColor: StaffColors.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('${r.booker.firstName} ${r.booker.lastName}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 1),
              Text.rich(
                TextSpan(
                  style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
                  children: [
                    TextSpan(text: r.bookingReference, style: staffMono.copyWith(fontSize: 12.5)),
                    TextSpan(
                      text: ' · $seats ${seats == 1 ? 'seat' : 'seats'}'
                          '${r.totalCentavos > 0 ? ' · ${formatPeso(r.totalCentavos)}' : ''}'
                          ' · ${r.screening.eventTitle}, ${DateFormat('MMM d').format(toManila(r.screening.startAt))}',
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  if (showState) _StateLabel(label, tone),
                  const Spacer(),
                  if (action != null) ...[
                    SizedBox(
                      height: 28,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        onPressed: () => context.go('/reservations'),
                        child: Text(action!),
                      ),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(_ago(r.createdAt, now),
                      style: const TextStyle(fontSize: 12, color: StaffColors.textMuted, fontFeatures: [FontFeature.tabularFigures()])),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _Tone { success, warning, error, neutral }

(String, _Tone) _stateOf(Reservation r, DateTime now, bool refundDue) {
  final paid = r.screening.type == ScreeningType.paid;
  if (refundDue) return ('Refund due', _Tone.error);
  return switch (r.status) {
    ReservationStatus.confirmed => (paid ? 'Approved · paid' : 'Approved', _Tone.success),
    ReservationStatus.cancelled => ('Cancelled', _Tone.neutral),
    ReservationStatus.pending when !paid => ('To approve', _Tone.warning),
    ReservationStatus.pending when !(r.expiresAt?.isAfter(now) ?? false) => ('Expired', _Tone.error),
    ReservationStatus.pending => ('Awaiting payment', _Tone.warning),
  };
}

/// "15h ago", as the website shows it.
String _ago(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${d.inDays ~/ 7}w ago';
}

/// A small state label with a dot (green / amber / red / gray).
class _StateLabel extends StatelessWidget {
  const _StateLabel(this.label, this.tone);

  final String label;
  final _Tone tone;

  @override
  Widget build(BuildContext context) {
    final (Color fg, Color bg, Color border) = switch (tone) {
      _Tone.success => (StaffColors.success, StaffColors.successTint, StaffColors.successBorder),
      _Tone.warning => (StaffColors.warning, StaffColors.warningTint, StaffColors.warningBorder),
      _Tone.error => (StaffColors.danger, StaffColors.dangerTint, StaffColors.dangerBorder),
      _Tone.neutral => (StaffColors.gray700, StaffColors.gray100, StaffColors.border),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(color: bg, border: Border.all(color: border), borderRadius: BorderRadius.circular(4)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w500, color: fg)),
        ],
      ),
    );
  }
}
