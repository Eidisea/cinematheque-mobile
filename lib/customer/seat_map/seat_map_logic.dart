import '../../core/booking_rules.dart';
import '../../data/models/screening.dart';
import '../../data/models/seat_layout.dart';

enum SeatStatus {
  available,
  selected, // chosen by this customer (not reserved until they submit — Phase 6)
  taken, // held or confirmed by a reservation
  unavailable, // switched off in the seat layout (broken seat, blocked view…)
}

/// Why a tap on a seat was refused.
enum SeatTapResult { selected, deselected, notAvailable, limitReached }

/// What the seat map shows, computed from the live screening + layout + the
/// customer's current selection. No widgets here so it can be tested directly.
///
/// This is only a guide for the customer: the server re-checks everything
/// inside a transaction when the reservation is submitted.
class SeatMapState {
  SeatMapState({required this.layout, required this.screening, required this.now, Set<String> selected = const {}})
      : selected = Set.unmodifiable(selected);

  final SeatLayout layout;
  final Screening screening;
  final DateTime now;
  final Set<String> selected;

  late final Set<String> _taken = screening.takenSeatLabelsAt(now);
  late final Set<String> _active = {for (final s in layout.activeSeats) s.label};

  SeatStatus statusOf(String label) {
    if (!_active.contains(label)) return SeatStatus.unavailable;
    if (_taken.contains(label)) return SeatStatus.taken;
    if (selected.contains(label)) return SeatStatus.selected;
    return SeatStatus.available;
  }

  bool get isClosed => !screening.isBookableAt(now);

  int get availableCount => _active.where((l) => !_taken.contains(l)).length;

  /// Selected seats in seat-map order (A1, A2, …, B1…), not tap order.
  List<String> get selectedInOrder => [
        for (final seat in layout.seats)
          if (selected.contains(seat.label)) seat.label,
      ];

  int get totalCentavos => screening.isPaid ? (screening.priceCentavos ?? 0) * selected.length : 0;

  bool get canContinue => !isClosed && selected.isNotEmpty;

  /// Tapping a seat: select it, unselect it, or explain why not.
  (SeatMapState, SeatTapResult) tap(String label) {
    if (selected.contains(label)) {
      return (_with(selected.difference({label})), SeatTapResult.deselected);
    }
    if (isClosed || statusOf(label) != SeatStatus.available) return (this, SeatTapResult.notAvailable);
    if (selected.length >= BookingRules.maxSeatsPerReservation) return (this, SeatTapResult.limitReached);
    return (_with({...selected, label}), SeatTapResult.selected);
  }

  /// New live data arrived. Any selected seat that someone else just took (or that was
  /// switched off) is dropped, and returned so the customer can be told.
  (SeatMapState, List<String>) refresh({required Screening screening, required SeatLayout layout, required DateTime now}) {
    final next = SeatMapState(layout: layout, screening: screening, now: now, selected: selected);
    final lost = [for (final l in selectedInOrder) if (next.statusOf(l) != SeatStatus.selected) l];
    return (lost.isEmpty ? next : next._with(selected.difference(lost.toSet())), lost);
  }

  SeatMapState _with(Set<String> newSelection) =>
      SeatMapState(layout: layout, screening: screening, now: now, selected: newSelection);
}
