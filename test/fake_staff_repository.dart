import 'dart:async';

import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/payment.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/data/models/staff_member.dart';
import 'package:ccd_mobile/staff/data/staff_repository.dart';

/// Staff data held in memory — no Firebase involved.
class FakeStaffRepository implements StaffRepository {
  FakeStaffRepository({
    List<Screening> screenings = const [],
    this.reservations = const [],
    this.payments = const [],
    this.admitted = const {},
    List<Movie> movies = const [],
    this.staff = const [],
    this.hasSeatLayout = true,
  })  : screenings = [...screenings],
        movies = [...movies];

  /// Screenings are editable so tests can see what the staff pages saved.
  final List<Screening> screenings;
  final List<Movie> movies;
  final List<StaffMember> staff;
  bool hasSeatLayout;
  final refreshed = <String>[];

  /// Like Firestore, film and screening lists update live after a write.
  final _changes = StreamController<void>.broadcast();

  Stream<T> _live<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }
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
  Stream<List<Reservation>> watchReservationList({int limit = 500}) => watchRecentReservations(limit: limit);

  @override
  Stream<Reservation?> watchReservation(String id) => Stream.value(reservations.where((r) => r.id == id).firstOrNull);

  @override
  Stream<Payment?> watchPayment(String reservationId) =>
      Stream.value(payments.where((p) => p.reservationId == reservationId).firstOrNull);

  @override
  Stream<List<Screening>> watchAllScreenings() => _live(() => [...screenings]..sort((a, b) => a.startAt.compareTo(b.startAt)));

  @override
  Stream<Screening?> watchScreening(String id) => Stream.value(screenings.where((s) => s.id == id).firstOrNull);

  @override
  Stream<List<Reservation>> watchReservationsFor(String screeningId) =>
      Stream.value([for (final r in reservations) if (r.screeningId == screeningId) r]);

  @override
  Stream<List<Movie>> watchMovies() => _live(() => [...movies]);

  @override
  Future<String> createScreening(Screening screening, {required String staffUid}) async {
    final id = 'new${screenings.length + 1}';
    screenings.add(screening.withId(id));
    return id;
  }

  @override
  Future<void> updateScreening(Screening screening) async {
    screenings[screenings.indexWhere((s) => s.id == screening.id)] = screening;
  }

  @override
  Future<void> deleteScreening(String id) async => screenings.removeWhere((s) => s.id == id);

  @override
  Future<String> createMovie(Movie movie) async {
    final id = 'film${movies.length + 1}';
    movies.add(movie.withId(id));
    _changes.add(null);
    return id;
  }

  @override
  Future<void> updateMovie(Movie movie) async {
    movies[movies.indexWhere((m) => m.id == movie.id)] = movie;
    _changes.add(null);
  }

  @override
  Future<void> deleteMovie(String id) async {
    movies.removeWhere((m) => m.id == id);
    _changes.add(null);
  }

  @override
  Future<void> refreshScreeningsOf(Movie movie, {required DateTime now}) async => refreshed.add(movie.id);

  @override
  Stream<List<StaffMember>> watchStaff() => Stream.value(staff);

  @override
  Stream<bool> watchHasSeatLayout() => _live(() => hasSeatLayout);

  @override
  Future<void> createSeatLayout({required String staffUid}) async {
    hasSeatLayout = true;
    _changes.add(null);
  }

  @override
  Stream<Map<String, int>> watchAdmittedCounts(List<String> screeningIds) =>
      Stream.value({for (final e in admitted.entries) if (screeningIds.contains(e.key)) e.key: e.value});
}
