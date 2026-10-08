import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';
import 'screening.dart';

enum ReservationStatus { pending, confirmed, cancelled }

enum CancellationReason { customerCancelled, staffCancelled, paymentExpired }

extension CancellationReasonDb on CancellationReason {
  String get dbValue => switch (this) {
        CancellationReason.customerCancelled => 'customer_cancelled',
        CancellationReason.staffCancelled => 'staff_cancelled',
        CancellationReason.paymentExpired => 'payment_expired',
      };
}

enum Sex { male, female }

extension SexDb on Sex {
  String get dbValue => this == Sex.male ? 'M' : 'F';
}

/// The person who made the booking (receives the emails).
class Booker {
  const Booker({
    required this.firstName,
    this.middleName,
    required this.lastName,
    required this.contactNo,
    required this.email,
  });

  final String firstName;
  final String? middleName;
  final String lastName;
  final String contactNo;
  final String email;

  String get fullName => [firstName, middleName, lastName].whereType<String>().join(' ');

  factory Booker.fromMap(Map<String, dynamic> m) => Booker(
        firstName: requireString(m['firstName'], 'booker.firstName'),
        middleName: stringOrNull(m['middleName']),
        lastName: requireString(m['lastName'], 'booker.lastName'),
        contactNo: requireString(m['contactNo'], 'booker.contactNo'),
        email: requireString(m['email'], 'booker.email'),
      );
}

/// The declared person for one seat (Cinematheque logsheet details).
class Attendee {
  const Attendee({
    required this.firstName,
    this.middleName,
    required this.lastName,
    this.age,
    this.sex,
    this.companySchool,
    this.contactNo,
    this.email,
    this.seniorCardNo,
    this.isPwd = false,
  });

  final String firstName;
  final String? middleName;
  final String lastName;
  final int? age;
  final Sex? sex;
  final String? companySchool;
  final String? contactNo;
  final String? email;
  final String? seniorCardNo; // sensitive: staff-only, excluded from exports by default
  final bool isPwd;

  String get fullName => [firstName, middleName, lastName].whereType<String>().join(' ');

  factory Attendee.fromMap(Map<String, dynamic> m) => Attendee(
        firstName: requireString(m['firstName'], 'attendee.firstName'),
        middleName: stringOrNull(m['middleName']),
        lastName: requireString(m['lastName'], 'attendee.lastName'),
        age: intOrNull(m['age']),
        sex: m['sex'] == null ? null : enumFromDb(Sex.values, (s) => s.dbValue, m['sex'], 'attendee.sex'),
        companySchool: stringOrNull(m['companySchool']),
        contactNo: stringOrNull(m['contactNo']),
        email: stringOrNull(m['email']),
        seniorCardNo: stringOrNull(m['seniorCardNo']),
        isPwd: m['isPwd'] == true,
      );
}

/// One reserved seat + the person declared for it (was `reservation_seats` +
/// `reservation_attendees` in the Laravel ERD).
class ReservedSeat {
  const ReservedSeat({required this.label, required this.isBooker, required this.attendee});

  final String label;
  final bool isBooker;
  final Attendee attendee;

  factory ReservedSeat.fromMap(Map<String, dynamic> m) => ReservedSeat(
        label: requireString(m['label'], 'seats.label'),
        isBooker: m['isBooker'] == true,
        attendee: Attendee.fromMap(mapOrEmpty(m['attendee'])),
      );
}

/// Screening details copied into the reservation when it was made.
class ScreeningSnapshot {
  const ScreeningSnapshot({required this.eventTitle, required this.startAt, required this.endAt, required this.type});

  final String eventTitle;
  final DateTime startAt;
  final DateTime endAt;
  final ScreeningType type;

  factory ScreeningSnapshot.fromMap(Map<String, dynamic> m) => ScreeningSnapshot(
        eventTitle: requireString(m['eventTitle'], 'screening.eventTitle'),
        startAt: requireDate(m['startAt'], 'screening.startAt'),
        endAt: requireDate(m['endAt'], 'screening.endAt'),
        type: enumFromDb(ScreeningType.values, (t) => t.name, m['type'], 'screening.type'),
      );
}

/// `reservations/{reservationId}` — random document ID; [bookingReference] (CCD-XXXXXXXX)
/// is what the customer sees. Written ONLY by the server; readable only by active staff.
///
/// Reservation ≠ Payment ≠ Attendance: payment lives in `payments/{reservationId}`,
/// admission in `attendances/{reservationId}_{seatLabel}`.
///
/// Besides the fields read below, the server also stores `seatLabels` (a plain list of the
/// seat labels) and `bookerEmailLower` (for reference + email lookup). The security rules
/// use `seatLabels` to check that an admission belongs to this reservation.
class Reservation {
  const Reservation({
    required this.id,
    required this.bookingReference,
    required this.screeningId,
    required this.screening,
    required this.status,
    this.cancellationReason,
    required this.booker,
    required this.seats,
    required this.totalCentavos,
    required this.createdAt,
    this.expiresAt,
    this.confirmedAt,
    this.cancelledAt,
    this.emails = const {},
  });

  final String id;
  final String bookingReference;
  final String screeningId;
  final ScreeningSnapshot screening;
  final ReservationStatus status;
  final CancellationReason? cancellationReason;
  final Booker booker;
  final List<ReservedSeat> seats; // 1–10
  final int totalCentavos; // 0 for free screenings
  final DateTime createdAt;
  final DateTime? expiresAt; // paid + pending only: end of the 15-minute payment window
  final DateTime? confirmedAt;
  final DateTime? cancelledAt;

  /// The email sent for each status ("pending" / "confirmed" / "cancelled") and how it went:
  /// "sending", "sent" or "failed" (server-written; see server/lib/email.js).
  final Map<String, String> emails;

  List<String> get seatLabels => seats.map((s) => s.label).toList(growable: false);

  factory Reservation.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      Reservation.fromMap(doc.id, doc.data() ?? const {});

  factory Reservation.fromMap(String id, Map<String, dynamic> d) {
    final rawSeats = d['seats'];
    return Reservation(
      id: id,
      bookingReference: requireString(d['bookingReference'], 'bookingReference'),
      screeningId: requireString(d['screeningId'], 'screeningId'),
      screening: ScreeningSnapshot.fromMap(mapOrEmpty(d['screening'])),
      status: enumFromDb(ReservationStatus.values, (s) => s.name, d['status'], 'status'),
      cancellationReason: d['cancellationReason'] == null
          ? null
          : enumFromDb(CancellationReason.values, (r) => r.dbValue, d['cancellationReason'], 'cancellationReason'),
      booker: Booker.fromMap(mapOrEmpty(d['booker'])),
      seats: rawSeats is List
          ? rawSeats.whereType<Map>().map((m) => ReservedSeat.fromMap(Map<String, dynamic>.from(m))).toList()
          : const [],
      totalCentavos: intOrNull(d['totalCentavos']) ?? 0,
      createdAt: requireDate(d['createdAt'], 'createdAt'),
      expiresAt: dateOrNull(d['expiresAt']),
      confirmedAt: dateOrNull(d['confirmedAt']),
      cancelledAt: dateOrNull(d['cancelledAt']),
      emails: {
        for (final e in mapOrEmpty(d['emails']).entries)
          if (e.value is Map && (e.value as Map)['state'] is String) e.key: (e.value as Map)['state'] as String,
      },
    );
  }

  static Map<String, Object?> toFirestore(Reservation _, SetOptions? _) =>
      throw UnsupportedError('reservations are written by the server only');
}
