import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../data/staff_api.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';

/// One screening, as on the website admin: when and how much, its numbers (seats booked,
/// admitted, waiting), the actions (Approve all pending · Edit · Delete while unbooked),
/// and one row per booking. Admitting people at the door comes with Phase 10.
class ScreeningScreen extends StatefulWidget {
  const ScreeningScreen({super.key, required this.screeningId});

  final String screeningId;

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  Screening? _screening;
  bool _loaded = false;
  List<Reservation> _bookings = const [];
  int _admitted = 0;
  Object? _error;
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty) return;
    final data = StaffServices.of(context).data;
    final id = widget.screeningId;
    _subs.addAll([
      data.watchScreening(id).listen(
            (s) => setState(() {
              _screening = s;
              _loaded = true;
            }),
            onError: (Object e) => setState(() => _error = e),
          ),
      data.watchReservationsFor(id).listen((v) => setState(() => _bookings = v)),
      data.watchAdmittedCounts([id]).listen((v) => setState(() => _admitted = v[id] ?? 0)),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _approveAll(int pending) async {
    final api = StaffServices.of(context).api;
    if (api == null) return showMessage(context, 'The booking server is not configured for this build.');
    final ok = await confirmAction(
      context,
      title: 'Approve all pending?',
      message: 'Approve $pending pending ${pending == 1 ? 'booking' : 'bookings'} and email the e-tickets?',
      confirm: 'Approve all',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final n = await api.approveAll(widget.screeningId);
      if (mounted) showMessage(context, 'Approved $n ${n == 1 ? 'booking' : 'bookings'}. The e-tickets were emailed.');
    } catch (e) {
      if (mounted) showMessage(context, staffApiMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete(Screening s) async {
    final ok = await confirmAction(
      context,
      title: 'Delete screening?',
      message: 'Delete “${s.eventTitle}”? This cannot be undone.',
      confirm: 'Delete screening',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await StaffServices.of(context).data.deleteScreening(s.id);
      if (!mounted) return;
      showMessage(context, 'Deleted “${s.eventTitle}”.');
      context.go('/attendance');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not delete it. Someone may have just booked; reload the page.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = StaffServices.of(context).clock.now();
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;
    final s = _screening;

    Widget body;
    if (_error != null) {
      body = const Notice('Could not load this screening. Check your connection and reload the page.');
    } else if (!_loaded) {
      body = const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()));
    } else if (s == null) {
      body = const Notice('This screening no longer exists.', tone: Tone.warning);
    } else {
      body = _content(s, now);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackLink('Attendance', onTap: () => context.go('/attendance')),
          const SizedBox(height: 8),
          body,
        ],
      ),
    );
  }

  Widget _content(Screening s, DateTime now) {
    final booked = s.seatHolds.values.where((h) => h.isActiveAt(now)).length;
    final waiting = _bookings
        .where((r) =>
            r.status == ReservationStatus.pending && (r.screening.type == ScreeningType.free || (r.expiresAt?.isAfter(now) ?? false)))
        .length;
    final paidTotal = _bookings
        .where((r) => r.status == ReservationStatus.confirmed)
        .fold<int>(0, (sum, r) => sum + r.totalCentavos);
    final day = manilaDay(s.startAt).difference(manilaDay(now)).inDays == 0 ? 'Today' : DateFormat('EEEE').format(toManila(s.startAt));

    final head = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$day · ${DateFormat('MMMM d, y').format(toManila(s.startAt))} · ${formatTime(s.startAt)}–${formatTime(s.endAt)}'
          ' · ${s.isPaid && s.priceCentavos != null ? '${formatPeso(s.priceCentavos!)} per seat' : 'Free'}',
          style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
        ),
        const SizedBox(height: 2),
        PageTitle(s.eventTitle),
        const SizedBox(height: 6),
        Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            Figure('$booked', '/ ${s.capacity} seats booked'),
            Figure('$_admitted', 'admitted'),
            if (waiting > 0)
              Text.rich(TextSpan(children: [
                TextSpan(
                    text: '$waiting ',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: StaffColors.warning)),
                TextSpan(
                    text: s.isPaid ? 'awaiting payment' : 'to approve',
                    style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
              ])),
            if (s.isPaid) Figure(formatPeso(paidTotal), 'paid'),
            if (s.movie != null && s.movie!.title != s.eventTitle)
              Text('Film: ${s.movie!.title}', style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
          ],
        ),
      ],
    );

    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (!s.isPaid && waiting > 0)
          AdminButton(
            label: 'Approve all pending ($waiting)',
            kind: AdminButtonKind.secondary,
            busy: _busy,
            onPressed: () => _approveAll(waiting),
          ),
        AdminButton(
          label: 'Edit screening',
          kind: AdminButtonKind.secondary,
          onPressed: () => context.go('/attendance/${s.id}/edit'),
        ),
        AdminButton(
          label: 'Reservations list',
          kind: AdminButtonKind.secondary,
          onPressed: () => context.go('/reservations?screening=${s.id}'),
        ),
        if (!s.hasReservations)
          AdminButton(label: 'Delete screening', kind: AdminButtonKind.danger, onPressed: () => _delete(s)),
      ],
    );

    final list = AdminSection(
      title: 'Reservations',
      count: 0,
      child: _bookings.isEmpty
          ? Panel(children: const [
              Padding(
                padding: EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text('No reservations yet', style: TextStyle(fontWeight: FontWeight.w600))),
              ),
            ])
          : Panel(children: [for (final r in _bookings) _Party(reservation: r, now: now)]),
    );

    return LayoutBuilder(builder: (context, box) {
      final wide = box.maxWidth >= 1000;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide)
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: head), actions])
          else ...[
            head,
            const SizedBox(height: 12),
            actions,
          ],
          const SizedBox(height: 20),
          list,
        ],
      );
    });
  }
}

/// One booking (party) on the screening: who, reference and seats, state, when.
class _Party extends StatelessWidget {
  const _Party({required this.reservation, required this.now});

  final Reservation reservation;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final r = reservation;
    final (label, tone) = bookingState(r, now);
    return Material(
      color: StaffColors.surface,
      child: InkWell(
        onTap: () => context.go('/reservations/${r.id}'),
        hoverColor: StaffColors.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${r.booker.firstName} ${r.booker.lastName}', style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: StaffColors.textMuted), children: [
                      TextSpan(text: r.bookingReference, style: staffMono.copyWith(fontSize: 12.5)),
                      TextSpan(text: ' · ${r.seats.length} ${r.seats.length == 1 ? 'seat' : 'seats'} · ${r.seatLabels.join(', ')}'),
                    ])),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              StateLabel(label, tone),
              const SizedBox(width: 16),
              SizedBox(
                width: 64,
                child: Text(timeAgo(r.createdAt, now),
                    textAlign: TextAlign.right, style: const TextStyle(fontSize: 12, color: StaffColors.textMuted)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
