import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/attendance.dart';
import '../models/booking_view.dart';
import '../models/movie.dart';
import '../models/payment.dart';
import '../models/reservation.dart';
import '../models/screening.dart';
import '../models/seat_layout.dart';
import '../models/staff_member.dart';

/// The one place that knows every Firestore collection name.
///
/// The typed references turn documents into model objects when reading
/// (`FirestoreCollections(db).movies.get()` → `Movie`s).
///
/// Who may write what is enforced by `firestore.rules`, not by this file:
///   staff (Web)   → movies, screenings (event fields only), settings/seatLayout, attendances
///   server only   → staff, reservations, payments, bookingViews, screening seat holds
///   customers     → read-only (they act through the server API)
class FirestoreCollections {
  FirestoreCollections(this.db);

  final FirebaseFirestore db;

  static const staffPath = 'staff';
  static const moviesPath = 'movies';
  static const screeningsPath = 'screenings';
  static const reservationsPath = 'reservations';
  static const paymentsPath = 'payments';
  static const attendancesPath = 'attendances';
  static const bookingViewsPath = 'bookingViews';

  CollectionReference<StaffMember> get staff => db
      .collection(staffPath)
      .withConverter(fromFirestore: StaffMember.fromFirestore, toFirestore: StaffMember.toFirestore);

  CollectionReference<Movie> get movies =>
      db.collection(moviesPath).withConverter(fromFirestore: Movie.fromFirestore, toFirestore: Movie.toFirestore);

  /// Typed for READING. To write, use [screeningsRaw] with
  /// `Screening.toNewDocument()` (create) or `Screening.toStaffUpdate()` (update).
  CollectionReference<Screening> get screenings => screeningsRaw.withConverter(
        fromFirestore: Screening.fromFirestore,
        toFirestore: (_, _) => throw UnsupportedError('use toNewDocument()/toStaffUpdate() with screeningsRaw'),
      );

  CollectionReference<Map<String, dynamic>> get screeningsRaw => db.collection(screeningsPath);

  /// Typed for READING. To write, use [seatLayoutRaw] with `SeatLayout.toFirestore(uid)`.
  DocumentReference<SeatLayout> get seatLayout => seatLayoutRaw.withConverter(
        fromFirestore: SeatLayout.fromFirestore,
        toFirestore: (_, _) => throw UnsupportedError('use SeatLayout.toFirestore(uid) with seatLayoutRaw'),
      );

  DocumentReference<Map<String, dynamic>> get seatLayoutRaw => db.doc(SeatLayout.docPath);

  CollectionReference<Reservation> get reservations => db
      .collection(reservationsPath)
      .withConverter(fromFirestore: Reservation.fromFirestore, toFirestore: Reservation.toFirestore);

  CollectionReference<Payment> get payments =>
      db.collection(paymentsPath).withConverter(fromFirestore: Payment.fromFirestore, toFirestore: Payment.toFirestore);

  CollectionReference<Attendance> get attendances => db
      .collection(attendancesPath)
      .withConverter(fromFirestore: Attendance.fromFirestore, toFirestore: Attendance.toFirestore);

  /// Customers may only `get()` one document by its access key — never list.
  DocumentReference<BookingView> bookingView(String accessKey) => db
      .collection(bookingViewsPath)
      .doc(accessKey)
      .withConverter(fromFirestore: BookingView.fromFirestore, toFirestore: BookingView.toFirestore);
}
