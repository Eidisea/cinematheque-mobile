import 'package:cloud_firestore/cloud_firestore.dart';

import '../../data/models/movie.dart';
import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../../data/models/seat_layout.dart';
import '../../data/models/staff_member.dart';
import '../../data/repositories/catalog_repository.dart';
import '../../data/repositories/firestore_collections.dart';

/// What the staff pages read (all live). Staff may read these collections
/// (firestore.rules); reservations and payments are changed only through the server
/// (StaffApi), never written here.
abstract class StaffRepository {
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

  /// Bookings for the Reservations page, newest first.
  Stream<List<Reservation>> watchReservationList({int limit = 500});

  /// One booking (null if it does not exist).
  Stream<Reservation?> watchReservation(String id);

  /// The payment of a paid booking (null for free ones).
  Stream<Payment?> watchPayment(String reservationId);

  // ── Screenings (staff write these directly; firestore.rules checks every field) ──

  /// Every screening, soonest first (past and upcoming).
  Stream<List<Screening>> watchAllScreenings();

  Stream<Screening?> watchScreening(String id);

  /// Bookings for one screening, oldest first.
  Stream<List<Reservation>> watchReservationsFor(String screeningId);

  /// The film catalog, by title.
  Stream<List<Movie>> watchMovies();

  /// → the new screening's ID.
  Future<String> createScreening(Screening screening, {required String staffUid});

  /// Saves event fields only (the server owns seat holds).
  Future<void> updateScreening(Screening screening);

  /// Allowed only while nobody has booked.
  Future<void> deleteScreening(String id);

  // ── Film catalog (staff write these directly; firestore.rules checks every field) ──

  /// → the new film's ID.
  Future<String> createMovie(Movie movie);

  Future<void> updateMovie(Movie movie);

  Future<void> deleteMovie(String id);

  /// Upcoming screenings of [movie] show its current title, poster, runtime and genres.
  Future<void> refreshScreeningsOf(Movie movie, {required DateTime now});

  /// Every staff account (active and inactive). Changed only through the server (StaffApi).
  Stream<List<StaffMember>> watchStaff();

  /// Whether settings/seatLayout exists (bookings need it).
  Stream<bool> watchHasSeatLayout();

  /// Saves the standard hall: 10 rows (A–J) × 12 seats.
  Future<void> createSeatLayout({required String staffUid});
}

class FirestoreStaffRepository implements StaffRepository {
  FirestoreStaffRepository([FirestoreCollections? collections])
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
  Stream<List<Payment>> watchPaymentsPaidSince(DateTime from) =>
      _c.payments.where('paidAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from)).snapshots().map(_values);

  @override
  Stream<List<Payment>> watchRefundsDue() => _c.payments.where('needsRefund', isEqualTo: true).snapshots().map(_values);

  @override
  Stream<List<Reservation>> watchReservations(List<String> ids) => ids.isEmpty
      ? Stream.value(const [])
      : _c.reservations.where(FieldPath.documentId, whereIn: ids.take(30).toList()).snapshots().map(_values);

  @override
  Stream<List<Reservation>> watchReservationList({int limit = 500}) =>
      _c.reservations.orderBy('createdAt', descending: true).limit(limit).snapshots().map(_values);

  @override
  Stream<Reservation?> watchReservation(String id) => _c.reservations.doc(id).snapshots().map((d) => d.exists ? d.data() : null);

  @override
  Stream<Payment?> watchPayment(String reservationId) =>
      _c.payments.doc(reservationId).snapshots().map((d) => d.exists ? d.data() : null);

  @override
  Stream<List<Screening>> watchAllScreenings() =>
      _c.screenings.orderBy('startAt').limit(500).snapshots().map(_values);

  @override
  Stream<Screening?> watchScreening(String id) => _catalog.watchScreening(id);

  @override
  Stream<List<Reservation>> watchReservationsFor(String screeningId) => _c.reservations
      .where('screeningId', isEqualTo: screeningId)
      .snapshots()
      .map((snap) => _values(snap)..sort((a, b) => a.createdAt.compareTo(b.createdAt)));

  @override
  Stream<List<Movie>> watchMovies() => _c.movies.orderBy('title').snapshots().map(_values);

  @override
  Future<String> createScreening(Screening screening, {required String staffUid}) async =>
      (await _c.screeningsRaw.add(screening.toNewDocument(staffUid))).id;

  @override
  Future<void> updateScreening(Screening screening) => _c.screeningsRaw.doc(screening.id).update(screening.toStaffUpdate());

  @override
  Future<void> deleteScreening(String id) => _c.screeningsRaw.doc(id).delete();

  @override
  Future<String> createMovie(Movie movie) async => (await _c.movies.add(movie)).id;

  /// Every field except createdAt, which must stay exactly as stored (firestore.rules).
  @override
  Future<void> updateMovie(Movie movie) {
    final fields = Movie.toFirestore(movie, null)..remove('createdAt');
    return _c.db.collection(FirestoreCollections.moviesPath).doc(movie.id).update(fields);
  }

  @override
  Future<void> deleteMovie(String id) => _c.movies.doc(id).delete();

  @override
  Future<void> refreshScreeningsOf(Movie movie, {required DateTime now}) async {
    // One equality filter (no composite index needed); past screenings keep what they showed.
    final snap = await _c.screeningsRaw.where('movieId', isEqualTo: movie.id).get();
    final snapshot = MovieSnapshot(
      title: movie.title,
      posterUrl: movie.poster?.url,
      runtimeMinutes: movie.runtimeMinutes,
      genres: movie.genres,
    ).toMap();
    for (final doc in snap.docs) {
      final startAt = doc.data()['startAt'];
      if (startAt is! Timestamp || startAt.toDate().isBefore(now)) continue;
      await doc.reference.update({'movie': snapshot, 'updatedAt': FieldValue.serverTimestamp()});
    }
  }

  @override
  Stream<List<StaffMember>> watchStaff() => _c.staff.snapshots().map(
        (snap) => _values(snap)..sort((a, b) => '${a.lastName} ${a.firstName}'.compareTo('${b.lastName} ${b.firstName}')),
      );

  @override
  Stream<bool> watchHasSeatLayout() => _c.seatLayoutRaw.snapshots().map((d) => d.exists);

  @override
  Future<void> createSeatLayout({required String staffUid}) => _c.seatLayoutRaw.set(SeatLayout.grid().toFirestore(staffUid));

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
