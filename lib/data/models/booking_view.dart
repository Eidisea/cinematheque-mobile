import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';
import 'payment.dart';
import 'reservation.dart';
import 'screening.dart';

class BookingViewSeat {
  const BookingViewSeat({required this.label, required this.attendeeName});

  final String label;
  final String attendeeName;

  factory BookingViewSeat.fromMap(Map<String, dynamic> m) => BookingViewSeat(
        label: requireString(m['label'], 'seats.label'),
        attendeeName: requireString(m['attendeeName'], 'seats.attendeeName'),
      );
}

/// `bookingViews/{accessKey}` — the customer's copy of their booking, without sensitive
/// details (no ages, contact numbers, senior card numbers…).
///
/// The document ID is a long random [accessKey] given to the customer's phone when they
/// book or look up (reference + email). Firestore rules allow reading one document by its
/// exact key but never listing the collection. Written ONLY by the server; the customer
/// app listens to it so status changes (paid, approved, cancelled) appear live.
class BookingView {
  const BookingView({
    required this.accessKey,
    required this.bookingReference,
    required this.status,
    this.cancellationReason,
    required this.screening,
    this.posterUrl,
    required this.seats,
    required this.totalCentavos,
    this.paymentStatus,
    this.expiresAt,
    this.updatedAt,
  });

  final String accessKey;
  final String bookingReference;
  final ReservationStatus status;
  final CancellationReason? cancellationReason;
  final ScreeningSnapshot screening;
  final String? posterUrl;
  final List<BookingViewSeat> seats;
  final int totalCentavos;
  final PaymentStatus? paymentStatus; // null for free screenings
  final DateTime? expiresAt;
  final DateTime? updatedAt;

  /// The e-ticket is shown only for confirmed bookings.
  bool get hasTicket => status == ReservationStatus.confirmed;

  bool get isFree => screening.type == ScreeningType.free;

  factory BookingView.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      BookingView.fromMap(doc.id, doc.data() ?? const {});

  factory BookingView.fromMap(String id, Map<String, dynamic> d) {
    final rawSeats = d['seats'];
    return BookingView(
      accessKey: id,
      bookingReference: requireString(d['bookingReference'], 'bookingReference'),
      status: enumFromDb(ReservationStatus.values, (s) => s.name, d['status'], 'status'),
      cancellationReason: d['cancellationReason'] == null
          ? null
          : enumFromDb(CancellationReason.values, (r) => r.dbValue, d['cancellationReason'], 'cancellationReason'),
      screening: ScreeningSnapshot.fromMap(mapOrEmpty(d['screening'])),
      posterUrl: stringOrNull(d['posterUrl']),
      seats: rawSeats is List
          ? rawSeats.whereType<Map>().map((m) => BookingViewSeat.fromMap(Map<String, dynamic>.from(m))).toList()
          : const [],
      totalCentavos: intOrNull(d['totalCentavos']) ?? 0,
      paymentStatus: d['paymentStatus'] == null
          ? null
          : enumFromDb(PaymentStatus.values, (s) => s.name, d['paymentStatus'], 'paymentStatus'),
      expiresAt: dateOrNull(d['expiresAt']),
      updatedAt: dateOrNull(d['updatedAt']),
    );
  }

  static Map<String, Object?> toFirestore(BookingView _, SetOptions? _) =>
      throw UnsupportedError('booking views are written by the server only');
}
