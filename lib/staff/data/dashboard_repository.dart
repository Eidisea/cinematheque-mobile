import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/firestore_collections.dart';

/// What the staff dashboard reads (all live). Staff may read these collections
/// (firestore.rules); they never write reservations or payments here.
abstract class DashboardRepository {
  /// Screenings starting at or after [from], soonest first.
  Stream<List<Screening>> watchScreeningsFrom(DateTime from);

  /// Every pending reservation (free ones waiting for approval, paid ones waiting for payment).
  Stream<List<Reservation>> watchPendingReservations();

  /// The newest bookings first.
  Stream<List<Reservation>> watchRecentReservations({int limit = 6});

  /// Payments recorded as paid at or after [from].
  Stream<List<Payment>> watchPaymentsPaidSince(DateTime from);

  /// Payments that arrived too late and must be refunded outside the system.
  Stream<List<Payment>> watchRefundsDue();

  /// The reservations with these IDs (at most 30).
  Stream<List<Reservation>> watchReservations(List<String> ids);

  /// Admitted seats per screening, for these screenings (at most 30).
  Stream<Map<String, int>> watchAdmittedCounts(List<String> screeningIds);
}

class FirestoreDashboardRepository implements DashboardRepository {
  FirestoreDashboardRepository([FirestoreCollections? collections])
      : _c = collections ?? FirestoreCollections(FirebaseFirestore.instance),
        _catalog = FirestoreCatalogRepository(collections);

  final FirestoreCollections _c;
  final FirestoreCatalogRepository _catalog;

  static List<T> _values<T>(QuerySnapshot<T> snap) => [for (final d in snap.docs) d.data()];

  @override
  Stream<List<Screening>> watchScreeningsFrom(DateTime from) => _catalog.watchUpcomingScreenings(from: from);

  @override
  Stream<List<Reservation>> watchPendingReservations() =>
      _c.reservations.where('status', isEqualTo: ReservationStatus.pending.name).snapshots().map(_values);

  @override
  Stream<List<Reservation>> watchRecentReservations({int limit = 6}) =>
      _c.reservations.orderBy('createdAt', descending: true).limit(limit).snapshots().map(_values);

  @override
  Stream<List<Payment>> watchPaymentsPaidSince(DateTime from) => _c.payments
      .where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .snapshots()
      .map(_values);

  @override
  Stream<List<Payment>> watchRefundsDue() => _c.payments.where('needsRefund', isEqualTo: true).snapshots().map(_values);

  @override
  Stream<List<Reservation>> watchReservations(List<String> ids) => ids.isEmpty
      ? Stream.value(const [])
      : _c.reservations.where(FieldPath.documentId, whereIn: ids.take(30).toList()).snapshots().map(_values);

  @override
  Stream<Map<String, int>> watchAdmittedCounts(List<String> screeningIds) => screeningIds.isEmpty
      ? Stream.value(const {})
      : _c.attendances.where('screeningId', whereIn: screeningIds.take(30).toList()).snapshots().map((snap) {
          final counts = <String, int>{};
          for (final d in snap.docs) {
            counts.update(d.data().screeningId, (n) => n + 1, ifAbsent: () => 1);
          }
          return counts;
        });
}
