import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/attendance.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../data/staff_api.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/admission_table.dart';

/// One screening, as on the website admin: when and how much, its numbers (seats booked,
/// admitted, waiting), the actions (Approve all pending · Edit · Delete while unbooked),
/// and the bookings, where staff admit people at the door (AdmissionTable).
class ScreeningScreen extends StatefulWidget {
  const ScreeningScreen({super.key, required this.screeningId, this.staffUid});

  final String screeningId;

  /// The signed-in staff member, recorded on each admission.
  final String? staffUid;

  @override
  State<ScreeningScreen> createState() => _ScreeningScreenState();
}

class _ScreeningScreenState extends State<ScreeningScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  Screening? _screening;
  bool _loaded = false;
  List<Reservation> _bookings = const [];
  Map<String, Attendance> _admitted = const {};
  Map<String, String> _staffNames = const {};
  Object? _error;
  bool _busy = false;
  final _busyParties = <String>{};
  PartyState? _filter;
  final _search = TextEditingController();
  String _query = '';

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
      data.watchAttendancesFor(id).listen((v) => setState(() => _admitted = {for (final a in v) a.id: a})),
      data.watchStaff().listen((v) => setState(() => _staffNames = {for (final m in v) m.uid: m.firstName})),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _search.dispose();
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

  Future<void> _approve(Reservation r) async {
    final api = StaffServices.of(context).api;
    if (api == null) return showMessage(context, 'The booking server is not configured for this build.');
    setState(() => _busyParties.add(r.id));
    try {
      await api.approve(r.id);
      if (mounted) showMessage(context, 'Approved ${r.bookingReference}. The e-ticket was emailed.');
    } catch (e) {
      if (mounted) showMessage(context, staffApiMessage(e));
    } finally {
      if (mounted) setState(() => _busyParties.remove(r.id));
    }
  }

  /// → true when the seats were admitted.
  Future<bool> _admit(Reservation r, List<String> seatLabels) async {
    final uid = widget.staffUid;
    if (uid == null) return false;
    final seats = [for (final l in seatLabels) if (!_admitted.containsKey(Attendance.docId(r.id, l))) l];
    if (seats.isEmpty) return true;
    setState(() => _busyParties.add(r.id));
    try {
      await StaffServices.of(context).data.admit(r, seats, staffUid: uid);
      if (mounted) {
        showMessage(context, seats.length == 1 ? 'Seat ${seats.single} admitted.' : '${seats.length} admitted: ${seats.join(', ')}.');
      }
      return true;
    } catch (_) {
      if (mounted) {
        showMessage(context, 'No one was admitted. Someone may have just admitted them, or the booking is no longer approved.');
      }
      return false;
    } finally {
      if (mounted) setState(() => _busyParties.remove(r.id));
    }
  }

  Future<void> _undo(Reservation r, Attendance a) async {
    final ok = await confirmAction(
      context,
      title: 'Undo admission?',
      message: 'Mark ${a.attendeeName} (seat ${a.seatLabel}) as not admitted?',
      confirm: 'Undo admission',
    );
    if (!ok || !mounted) return;
    setState(() => _busyParties.add(r.id));
    try {
      await StaffServices.of(context).data.undoAdmission(a.id);
      if (mounted) showMessage(context, 'Seat ${a.seatLabel} is no longer admitted.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not undo it. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _busyParties.remove(r.id));
    }
  }

  Future<void> _note(Reservation r, ReservedSeat seat, Attendance a) async {
    final data = StaffServices.of(context).data;
    final remarks = await showDialog<String>(
      context: context,
      builder: (context) => _NoteDialog(seat: seat, remarks: a.remarks),
    );
    if (remarks == null || !mounted) return;
    try {
      await data.saveAdmissionNote(a.id, remarks);
      if (mounted) showMessage(context, 'Note saved.');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not save the note. Check your connection and try again.');
    }
  }

  bool _matches(Reservation r) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final compact = q.replaceAll('-', '');
    return r.bookingReference.toLowerCase().replaceAll('-', '').contains(compact) ||
        r.booker.fullName.toLowerCase().contains(q) ||
        r.booker.email.toLowerCase().contains(q) ||
        r.seats.any((s) => s.label.toLowerCase() == q || s.attendee.fullName.toLowerCase().contains(q));
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
            Figure('${_admitted.length}', 'admitted'),
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

    final isOver = !now.isBefore(s.endAt);
    final states = {for (final r in _bookings) r.id: partyState(r, _admitted, isOver: isOver)};
    final filters = <PartyState?>[
      null,
      isOver ? PartyState.noShow : PartyState.toAdmit,
      PartyState.admitted,
      PartyState.pending,
      PartyState.cancelled,
    ];
    final filter = filters.contains(_filter) ? _filter : null;
    final shown = [for (final r in _bookings) if ((filter == null || states[r.id] == filter) && _matches(r)) r];
    Widget empty(String text) => Panel(children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
          ),
        ]);

    final list = _bookings.isEmpty
        ? empty('No reservations yet')
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(
              spacing: 12,
              runSpacing: 10,
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilterChips<PartyState?>(
                  values: filters,
                  current: filter,
                  label: (v) => v?.label ?? 'All',
                  count: (v) => v == null ? _bookings.length : states.values.where((x) => x == v).length,
                  onSelect: (v) => setState(() => _filter = v),
                ),
                SearchField(
                  controller: _search,
                  hint: 'Name, reference or seat',
                  onChanged: (v) => setState(() => _query = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (shown.isEmpty)
              empty('No matches')
            else
              AdmissionTable(
                parties: shown,
                admitted: _admitted,
                staffNames: _staffNames,
                isOver: isOver,
                now: now,
                busy: _busyParties,
                onApprove: _approve,
                onAdmit: _admit,
                onUndo: _undo,
                onNote: _note,
              ),
          ]);

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

/// Remarks on one admission. → the new text, or null when cancelled.
class _NoteDialog extends StatefulWidget {
  const _NoteDialog({required this.seat, this.remarks});

  final ReservedSeat seat;
  final String? remarks;

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  late final _text = TextEditingController(text: widget.remarks ?? '');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Remarks · seat ${widget.seat.label}'),
        content: SizedBox(
          width: 400,
          child: TextField(
            controller: _text,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: 2000,
            decoration: InputDecoration(hintText: 'A note about ${widget.seat.attendee.fullName}'),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, _text.text), child: const Text('Save')),
        ],
      );
}
