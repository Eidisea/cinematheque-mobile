import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting.dart';
import '../../data/models/attendance.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../theme/staff_theme.dart';
import 'admin_ui.dart';

/// Where one booking (party) stands at the door. Drives the quick filters.
enum PartyState {
  toAdmit('To admit'),
  noShow('No-show'),
  admitted('Admitted'),
  pending('Pending'),
  cancelled('Cancelled');

  const PartyState(this.label);
  final String label;
}

PartyState partyState(Reservation r, Map<String, Attendance> admitted, {required bool isOver}) {
  if (r.status == ReservationStatus.cancelled) return PartyState.cancelled;
  if (r.status == ReservationStatus.pending) return PartyState.pending;
  final inside = r.seats.where((s) => admitted.containsKey(Attendance.docId(r.id, s.label))).length;
  if (inside == r.seats.length) return PartyState.admitted;
  return isOver ? PartyState.noShow : PartyState.toAdmit;
}

/// The booker first, then the seats in order.
List<ReservedSeat> partySeats(Reservation r) =>
    [...r.seats]..sort((a, b) => a.isBooker != b.isBooker ? (a.isBooker ? -1 : 1) : a.label.compareTo(b.label));

/// The website's attendance table: one row per booking (party), its people beneath.
///
/// A party of 1 is admitted straight from its row ("Admit"). For 2 or more, "Admit party"
/// opens the people with everyone ticked; staff untick anyone who isn't here and confirm
/// ("Admit 3"). Admitted people get Note and Undo. Only confirmed bookings can be admitted.
class AdmissionTable extends StatefulWidget {
  const AdmissionTable({
    super.key,
    required this.parties,
    required this.admitted,
    required this.staffNames,
    required this.isOver,
    required this.now,
    required this.busy,
    required this.onApprove,
    required this.onAdmit,
    required this.onUndo,
    required this.onNote,
  });

  final List<Reservation> parties;

  /// Admissions by attendance ID (`{reservationId}_{seat}`).
  final Map<String, Attendance> admitted;

  /// Staff first names by UID ("by Ana").
  final Map<String, String> staffNames;

  /// The screening has ended: anyone not admitted is a no-show.
  final bool isOver;
  final DateTime now;

  /// Bookings with an action in progress.
  final Set<String> busy;
  final void Function(Reservation) onApprove;
  final Future<bool> Function(Reservation, List<String> seatLabels) onAdmit;
  final void Function(Reservation, Attendance) onUndo;
  final void Function(Reservation, ReservedSeat, Attendance) onNote;

  @override
  State<AdmissionTable> createState() => _AdmissionTableState();
}

class _AdmissionTableState extends State<AdmissionTable> {
  final _open = <String>{};
  final _picked = <String, Set<String>>{};

  static const _seatsWidth = 170.0;
  static const _statusWidth = 150.0;
  static const _admittedWidth = 130.0;
  static const _actionsWidth = 190.0;
  static const _minWidth = 900.0;

  Attendance? _admission(Reservation r, ReservedSeat s) => widget.admitted[Attendance.docId(r.id, s.label)];

  List<ReservedSeat> _admittable(Reservation r) => r.status == ReservationStatus.confirmed
      ? [for (final s in r.seats) if (_admission(r, s) == null) s]
      : const [];

  void _toggle(Reservation r) => setState(() {
        if (!_open.remove(r.id)) _open.add(r.id);
      });

  void _startParty(Reservation r) => setState(() {
        _open.add(r.id);
        _picked[r.id] = {for (final s in _admittable(r)) s.label};
      });

  Set<String> _pickedFor(Reservation r) {
    final open = {for (final s in _admittable(r)) s.label};
    return (_picked[r.id] ??= {...open})..retainAll(open);
  }

  Future<void> _admitPicked(Reservation r) async {
    final seats = _pickedFor(r).toList()..sort();
    if (seats.isEmpty) return showMessage(context, 'Tick at least one person to admit.');
    final ok = await widget.onAdmit(r, seats);
    if (ok && mounted) setState(() => _picked.remove(r.id));
  }

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.gray600);
    final table = Panel(children: [
      Container(
        color: StaffColors.surfaceAlt,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: const Row(children: [
          Expanded(child: Text('RESERVATION', style: head)),
          SizedBox(width: _seatsWidth, child: Text('SEATS', style: head)),
          SizedBox(width: _statusWidth, child: Text('STATUS', style: head)),
          SizedBox(width: _admittedWidth, child: Text('ADMITTED', style: head)),
          SizedBox(width: _actionsWidth, child: Text('ACTIONS', style: head, textAlign: TextAlign.right)),
        ]),
      ),
      for (final r in widget.parties) ..._party(r),
    ]);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _minWidth
          ? table
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: _minWidth, child: table)),
    );
  }

  List<Widget> _party(Reservation r) {
    final seats = partySeats(r);
    final single = seats.length == 1 ? seats.single : null;
    final admittable = _admittable(r);
    final open = single == null && _open.contains(r.id);
    final busy = widget.busy.contains(r.id);
    final state = partyState(r, widget.admitted, isOver: widget.isOver);
    final (label, tone) = bookingState(r, widget.now);
    final inside = seats.where((s) => _admission(r, s) != null).length;
    final muted = state == PartyState.cancelled;
    final flags = [
      if (seats.any((s) => s.attendee.seniorCardNo != null)) 'Senior',
      if (seats.any((s) => s.attendee.isPwd)) 'PWD',
    ];

    Widget admittedCell;
    if (single != null && _admission(r, single) != null) {
      admittedCell = _InAt(_admission(r, single)!, widget.staffNames);
    } else if (state == PartyState.cancelled || state == PartyState.pending) {
      admittedCell = const Text('—', style: TextStyle(color: StaffColors.textMuted));
    } else if (single == null) {
      admittedCell = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text.rich(
          TextSpan(children: [
            TextSpan(text: '$inside', style: const TextStyle(fontWeight: FontWeight.w600)),
            TextSpan(text: ' / ${seats.length}'),
          ]),
          style: TextStyle(color: inside == seats.length ? StaffColors.success : StaffColors.text),
        ),
        if (widget.isOver && inside < seats.length)
          Text('${seats.length - inside} no-show', style: const TextStyle(fontSize: 12, color: StaffColors.danger)),
      ]);
    } else if (widget.isOver) {
      admittedCell = const Text('No-show', style: TextStyle(color: StaffColors.danger));
    } else {
      admittedCell = const Text('Not in', style: TextStyle(color: StaffColors.textMuted));
    }

    final canApprove = r.status == ReservationStatus.pending &&
        r.screening.type == ScreeningType.free &&
        widget.now.isBefore(r.screening.startAt);
    final actions = <Widget>[
      if (canApprove)
        AdminButton(label: 'Approve', small: true, busy: busy, onPressed: () => widget.onApprove(r))
      else if (single != null)
        ..._seatActions(r, single, busy: busy)
      else if (admittable.isNotEmpty && !open)
        AdminButton(label: 'Admit party', small: true, busy: busy, onPressed: () => _startParty(r)),
    ];

    final rows = <Widget>[
      _Row(
        muted: muted,
        onTap: () => context.go('/reservations/${r.id}'),
        children: [
          Expanded(
            child: Row(children: [
              if (single == null)
                IconButton(
                  tooltip: open ? 'Hide the ${seats.length} people' : 'Show the ${seats.length} people',
                  visualDensity: VisualDensity.compact,
                  iconSize: 18,
                  onPressed: () => _toggle(r),
                  icon: AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: const Icon(Icons.chevron_right),
                  ),
                )
              else
                const SizedBox(width: 8),
              const SizedBox(width: 4),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(r.booker.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                    if (single == null)
                      Text(' · Party of ${seats.length}', style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                  ]),
                  Text.rich(TextSpan(style: const TextStyle(fontSize: 13, color: StaffColors.textMuted), children: [
                    TextSpan(text: r.bookingReference, style: staffMono.copyWith(fontSize: 12.5)),
                    if (single != null && single.attendee.fullName != r.booker.fullName)
                      TextSpan(text: ' · ${single.attendee.fullName}'),
                    for (final f in flags)
                      TextSpan(text: ' · $f', style: const TextStyle(fontWeight: FontWeight.w700, color: StaffColors.text)),
                  ])),
                ]),
              ),
            ]),
          ),
          SizedBox(
            width: _seatsWidth,
            child: Wrap(spacing: 4, runSpacing: 4, children: [for (final s in seats) _SeatTag(s.label)]),
          ),
          SizedBox(width: _statusWidth, child: Align(alignment: Alignment.centerLeft, child: StateLabel(label, tone))),
          SizedBox(width: _admittedWidth, child: admittedCell),
          SizedBox(
            width: _actionsWidth,
            child: Wrap(alignment: WrapAlignment.end, spacing: 6, runSpacing: 6, children: actions),
          ),
        ],
      ),
    ];

    if (open) {
      final picked = _pickedFor(r);
      for (final s in seats) {
        final a = _admission(r, s);
        final canPick = a == null && r.status == ReservationStatus.confirmed;
        rows.add(_Row(
          muted: muted,
          indent: true,
          children: [
            Expanded(
              child: Row(children: [
                SizedBox(
                  width: 40,
                  child: canPick
                      ? Checkbox(
                          value: picked.contains(s.label),
                          visualDensity: VisualDensity.compact,
                          semanticLabel: 'Admit ${s.attendee.fullName}, seat ${s.label}',
                          onChanged: (on) => setState(() => on == true ? picked.add(s.label) : picked.remove(s.label)),
                        )
                      : null,
                ),
                Expanded(
                  child: Text.rich(TextSpan(children: [
                    TextSpan(text: s.attendee.fullName),
                    if (s.isBooker) const TextSpan(text: ' · Booker', style: TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                    if (s.attendee.seniorCardNo != null)
                      const TextSpan(text: ' · Senior', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                    if (s.attendee.isPwd) const TextSpan(text: ' · PWD', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                  ])),
                ),
              ]),
            ),
            SizedBox(width: _seatsWidth, child: Align(alignment: Alignment.centerLeft, child: _SeatTag(s.label))),
            const SizedBox(width: _statusWidth),
            SizedBox(
              width: _admittedWidth,
              child: a != null
                  ? _InAt(a, widget.staffNames)
                  : r.status == ReservationStatus.confirmed && widget.isOver
                      ? const Text('No-show', style: TextStyle(color: StaffColors.danger))
                      : const Text('—', style: TextStyle(color: StaffColors.textMuted)),
            ),
            SizedBox(
              width: _actionsWidth,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 6,
                children: [if (a != null) ..._seatActions(r, s, busy: busy)],
              ),
            ),
          ],
        ));
      }
      if (admittable.isNotEmpty) {
        rows.add(_Row(
          muted: muted,
          indent: true,
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 40),
                child: Text('Untick anyone who isn’t here.', style: TextStyle(fontSize: 13, color: StaffColors.textMuted)),
              ),
            ),
            SizedBox(
              width: _actionsWidth,
              child: Align(
                alignment: Alignment.centerRight,
                child: AdminButton(
                  label: 'Admit ${picked.length}',
                  small: true,
                  busy: busy,
                  onPressed: picked.isEmpty ? null : () => _admitPicked(r),
                ),
              ),
            ),
          ],
        ));
      }
    }
    return rows;
  }

  /// One person's actions: Admit, or Note + Undo once admitted.
  List<Widget> _seatActions(Reservation r, ReservedSeat s, {required bool busy}) {
    final a = _admission(r, s);
    if (a != null) {
      return [
        AdminButton(
          label: a.remarks == null ? 'Note' : 'Note ●',
          kind: AdminButtonKind.secondary,
          small: true,
          onPressed: () => widget.onNote(r, s, a),
        ),
        AdminButton(
          label: 'Undo',
          kind: AdminButtonKind.secondary,
          small: true,
          busy: busy,
          onPressed: () => widget.onUndo(r, a),
        ),
      ];
    }
    if (r.status != ReservationStatus.confirmed) return const [];
    return [AdminButton(label: 'Admit', small: true, busy: busy, onPressed: () => widget.onAdmit(r, [s.label]))];
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.children, this.onTap, this.muted = false, this.indent = false});

  final List<Widget> children;
  final VoidCallback? onTap;
  final bool muted;
  final bool indent;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: EdgeInsets.fromLTRB(indent ? 30 : 6, indent ? 6 : 10, 14, indent ? 6 : 10),
      child: Row(children: children),
    );
    return Opacity(
      opacity: muted ? 0.6 : 1,
      child: Material(
        color: indent ? StaffColors.surfaceAlt : StaffColors.surface,
        child: onTap == null ? row : InkWell(onTap: onTap, hoverColor: StaffColors.surfaceAlt, child: row),
      ),
    );
  }
}

/// "In 1:05 PM · by Ana".
class _InAt extends StatelessWidget {
  const _InAt(this.admission, this.staffNames);

  final Attendance admission;
  final Map<String, String> staffNames;

  @override
  Widget build(BuildContext context) {
    final at = admission.checkedInAt;
    final by = staffNames[admission.checkedInBy];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(at == null ? 'In' : 'In ${formatTime(at)}', style: const TextStyle(color: StaffColors.success)),
      if (by != null) Text('by $by', style: const TextStyle(fontSize: 12, color: StaffColors.textMuted)),
    ]);
  }
}

class _SeatTag extends StatelessWidget {
  const _SeatTag(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: StaffColors.gray100,
          border: Border.all(color: StaffColors.border),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(label, style: staffMono.copyWith(fontSize: 12, color: StaffColors.gray700)),
      );
}
