import 'package:ccd_mobile/data/models/payment.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/staff/data/dashboard_repository.dart';

/// Dashboard data held in memory — no Firebase involved.
class FakeDashboardRepository implements DashboardRepository {
  FakeDashboardRepository({
    this.screenings = const [],
    this.reservations = const [],
    this.payments = const [],
    this.admitted = const {},
  });

  final List<Screening> screenings;
  final List<Reservation> reservations;
  final List<Payment> payments;
  final Map<String, int> admitted;

  @override
  Stream<List<Screening>> watchScreeningsFrom(DateTime from) =>
      Stream.value([for (final s in screenings) if (!s.startAt.isBefore(from)) s]..sort((a, b) => a.startAt.compareTo(b.startAt)));

  @override
  Stream<List<Reservation>> watchPendingReservations() =>
      Stream.value([for (final r in reservations) if (r.status == ReservationStatus.pending) r]);

  @override
  Stream<List<Reservation>> watchRecentReservations({int limit = 6}) =>
      Stream.value((reservations.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt))).take(limit).toList());

  @override
  Stream<List<Payment>> watchPaymentsPaidSince(DateTime from) =>
      Stream.value([for (final p in payments) if (p.paidAt != null && !p.paidAt!.isBefore(from)) p]);

  @override
  Stream<List<Payment>> watchRefundsDue() => Stream.value([for (final p in payments) if (p.needsRefund) p]);

  @override
  Stream<List<Reservation>> watchReservations(List<String> ids) =>
      Stream.value([for (final r in reservations) if (ids.contains(r.id)) r]);

  @override
  Stream<Map<String, int>> watchAdmittedCounts(List<String> screeningIds) =>
      Stream.value({for (final e in admitted.entries) if (screeningIds.contains(e.key)) e.key: e.value});
}
