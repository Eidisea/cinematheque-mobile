import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../data/staff_api.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';

/// The website admin's Reservations page: quick filters with counts, a search and a
/// screening picker, then one row per booking (who, screening, party, amount, state, when)
/// with Approve on free bookings waiting for it. A row opens the booking.
class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key, this.initialScreeningId});

  /// Opened from a screening's page: show only its bookings.
  final String? initialScreeningId;

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

enum ReservationView {
  all('All'),
  approve('To approve'),
  payment('Awaiting payment'),
  approved('Approved'),
  refund('Refund due'),
  cancelled('Cancelled');

  const ReservationView(this.label);
  final String label;

  bool matches(Reservation r, Set<String> refundIds) => switch (this) {
    all => true,
    approve => r.status == ReservationStatus.pending && r.screening.type == ScreeningType.free,
    payment => r.status == ReservationStatus.pending && r.screening.type == ScreeningType.paid,
    approved => r.status == ReservationStatus.confirmed,
    refund => r.status == ReservationStatus.cancelled && refundIds.contains(r.id),
    cancelled => r.status == ReservationStatus.cancelled,
  };
}

class _ReservationsScreenState extends State<ReservationsScreen> {
  StreamSubscription<List<Reservation>>? _listSub;
  StreamSubscription<List<Payment>>? _refundSub;
  List<Reservation>? _all;
  Set<String> _refundIds = const {};
  Object? _error;

  ReservationView _view = ReservationView.all;
  String _query = '';
  late String? _screeningId = widget.initialScreeningId;
  final _search = TextEditingController();
  final _busy = <String>{};

  static const _maxRows = 200;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_listSub != null) return;
    final data = StaffServices.of(context).data;
    _listSub = data.watchReservationList().listen(
      (v) => setState(() => _all = v),
      onError: (Object e) => setState(() => _error = e),
    );
    _refundSub = data.watchRefundsDue().listen((v) => setState(() => _refundIds = {for (final p in v) p.reservationId}));
  }

  @override
  void dispose() {
    _listSub?.cancel();
    _refundSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  bool _matchesQuery(Reservation r) {
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    final compact = q.replaceAll(RegExp(r'[\s-]'), '');
    final digits = q.replaceAll(RegExp(r'\D'), '');
    final b = r.booker;
    return r.bookingReference.toLowerCase().replaceAll('-', '').contains(compact) ||
        '${b.firstName} ${b.lastName}'.toLowerCase().contains(q) ||
        b.email.toLowerCase().contains(q) ||
        (digits.length >= 4 && b.contactNo.replaceAll(RegExp(r'\D'), '').contains(digits));
  }

  Future<void> _approve(Reservation r) async {
    final api = StaffServices.of(context).api;
    final messenger = ScaffoldMessenger.of(context);
    if (api == null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('The booking server is not configured for this build.')));
      return;
    }
    setState(() => _busy.add(r.id));
    try {
      await api.approve(r.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('Approved ${r.bookingReference}. The e-ticket was emailed.')));
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(staffApiMessage(e))));
    } finally {
      if (mounted) setState(() => _busy.remove(r.id));
    }
  }

  void _clear() => setState(() {
    _search.clear();
    _query = '';
    _screeningId = null;
  });

  @override
  Widget build(BuildContext context) {
    final now = StaffServices.of(context).clock.now();
    final all = _all;
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;

    final inScreening = [
      for (final r in all ?? const <Reservation>[])
        if (_screeningId == null || r.screeningId == _screeningId) r,
    ];
    final counts = {for (final v in ReservationView.values) v: inScreening.where((r) => v.matches(r, _refundIds)).length};
    final shown = [
      for (final r in inScreening)
        if (_view.matches(r, _refundIds) && _matchesQuery(r)) r,
    ];

    // Screenings to pick from: those that have bookings, soonest first.
    final screenings = <String, ScreeningSnapshot>{};
    for (final r in all ?? const <Reservation>[]) {
      screenings.putIfAbsent(r.screeningId, () => r.screening);
    }
    final picker = screenings.entries.toList()..sort((a, b) => a.value.startAt.compareTo(b.value.startAt));

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Semantics(
            header: true,
            child: const Text('Reservations', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _Chips(current: _view, counts: counts, onSelect: (v) => setState(() => _view = v)),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    height: 34,
                    child: TextField(
                      controller: _search,
                      onChanged: (v) => setState(() => _query = v.trim()),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Reference, name, email or phone',
                        prefixIcon: Icon(Icons.search, size: 18, color: StaffColors.gray400),
                        prefixIconConstraints: BoxConstraints(minWidth: 34),
                        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      ),
                    ),
                  ),
                  Container(
                    width: 240,
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: StaffColors.surface,
                      border: Border.all(color: StaffColors.borderStrong),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String?>(
                        value: _screeningId,
                        isExpanded: true,
                        isDense: true,
                        style: const TextStyle(fontSize: 13, color: StaffColors.text),
                        hint: const Text('All screenings', style: TextStyle(fontSize: 13)),
                        items: [
                          const DropdownMenuItem<String?>(value: null, child: Text('All screenings')),
                          for (final e in picker)
                            DropdownMenuItem<String?>(
                              value: e.key,
                              child: Text(
                                '${DateFormat('MMM d').format(toManila(e.value.startAt))} · ${e.value.eventTitle}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (v) => setState(() => _screeningId = v),
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty || _screeningId != null) TextButton(onPressed: _clear, child: const Text('Clear')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            const Notice('Could not load reservations. Check your connection and reload the page.')
          else if (all == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (shown.isEmpty)
            _Empty(title: _query.isNotEmpty || _screeningId != null ? 'No matches' : 'No reservations')
          else ...[
            _Table(
              rows: shown.take(_maxRows).toList(),
              now: now,
              refundIds: _refundIds,
              busy: _busy,
              onOpen: (r) => context.go('/reservations/${r.id}'),
              onApprove: _approve,
            ),
            if (shown.length > _maxRows)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  'Showing the newest $_maxRows of ${shown.length}. Search or pick a screening to narrow the list.',
                  style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

/// Segmented quick filters with counts; the current one is dark.
class _Chips extends StatelessWidget {
  const _Chips({required this.current, required this.counts, required this.onSelect});

  final ReservationView current;
  final Map<ReservationView, int> counts;
  final ValueChanged<ReservationView> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: StaffColors.surface,
        border: Border.all(color: StaffColors.borderStrong),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Wrap(
        children: [
          for (final v in ReservationView.values)
            Semantics(
              button: true,
              selected: v == current,
              child: InkWell(
                onTap: () => onSelect(v),
                child: Container(
                  height: 32,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: v == current ? const Color(0xFF1F2937) : null,
                    border: v == ReservationView.values.last ? null : const Border(right: BorderSide(color: StaffColors.border)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        v.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: v == current ? Colors.white : StaffColors.gray700,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${counts[v] ?? 0}',
                        style: TextStyle(
                          fontSize: 12,
                          color: (v == current ? Colors.white : StaffColors.gray700).withValues(alpha: 0.7),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Panel(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Column(
            children: [
              const Icon(Icons.description_outlined, size: 28, color: StaffColors.gray400),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w600, color: StaffColors.gray700),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Reservation · Screening · Party · Amount · Status · Booked · Actions.
class _Table extends StatelessWidget {
  const _Table({
    required this.rows,
    required this.now,
    required this.refundIds,
    required this.busy,
    required this.onOpen,
    required this.onApprove,
  });

  final List<Reservation> rows;
  final DateTime now;
  final Set<String> refundIds;
  final Set<String> busy;
  final ValueChanged<Reservation> onOpen;
  final ValueChanged<Reservation> onApprove;

  static const _minWidth = 980.0;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.gray600);
    const sub = TextStyle(fontSize: 13, color: StaffColors.textMuted);

    Widget cells(List<Widget> c) => Row(crossAxisAlignment: CrossAxisAlignment.center, children: c);

    final table = Panel(
      children: [
        Container(
          color: StaffColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: cells(const [
            Expanded(flex: 3, child: Text('RESERVATION', style: head)),
            Expanded(flex: 3, child: Text('SCREENING', style: head)),
            SizedBox(width: 130, child: Text('PARTY', style: head)),
            SizedBox(
              width: 80,
              child: Text('AMOUNT', style: head, textAlign: TextAlign.right),
            ),
            SizedBox(width: 24),
            SizedBox(width: 160, child: Text('STATUS', style: head)),
            SizedBox(width: 120, child: Text('BOOKED', style: head)),
            SizedBox(
              width: 90,
              child: Text('ACTIONS', style: head, textAlign: TextAlign.right),
            ),
          ]),
        ),
        for (final r in rows)
          Builder(
            builder: (context) {
              final (label, tone) = bookingState(r, now, refundDue: refundIds.contains(r.id));
              final muted = r.status == ReservationStatus.cancelled;
              final color = muted ? StaffColors.gray400 : StaffColors.text;
              final labels = r.seatLabels;
              return Material(
                color: StaffColors.surface,
                child: InkWell(
                  onTap: () => onOpen(r),
                  hoverColor: StaffColors.surfaceAlt,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                    child: cells([
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${r.booker.firstName} ${r.booker.lastName}',
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w600, color: color),
                            ),
                            Text(r.bookingReference, style: staffMono.copyWith(fontSize: 12.5, color: StaffColors.textMuted)),
                          ],
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              r.screening.eventTitle,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: color),
                            ),
                            Text('${formatDateShort(r.screening.startAt)} · ${formatTime(r.screening.startAt)}', style: sub),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 130,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${labels.length} ${labels.length == 1 ? 'person' : 'people'}', style: TextStyle(color: color)),
                            Text(
                              '${labels.take(6).join(', ')}${labels.length > 6 ? ' …' : ''}',
                              overflow: TextOverflow.ellipsis,
                              style: staffMono.copyWith(fontSize: 12, color: StaffColors.textMuted),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 80,
                        child: Text(
                          r.totalCentavos > 0 ? formatPeso(r.totalCentavos) : 'Free',
                          textAlign: TextAlign.right,
                          style: TextStyle(color: color, fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                      const SizedBox(width: 24),
                      SizedBox(
                        width: 160,
                        child: Align(alignment: Alignment.centerLeft, child: StateLabel(label, tone)),
                      ),
                      SizedBox(width: 120, child: Text(DateFormat('MMM d, h:mm a').format(toManila(r.createdAt)), style: sub)),
                      SizedBox(
                        width: 90,
                        child: Align(
                          alignment: Alignment.centerRight,
                          child: canApprove(r, now)
                              ? AdminButton(
                                  label: 'Approve',
                                  small: true,
                                  busy: busy.contains(r.id),
                                  onPressed: () => onApprove(r),
                                )
                              : null,
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            },
          ),
      ],
    );

    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _minWidth
          ? table
          : SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SizedBox(width: _minWidth, child: table),
            ),
    );
  }
}
