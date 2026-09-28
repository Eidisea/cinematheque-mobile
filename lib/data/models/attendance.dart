import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';

/// `attendances/{reservationId}_{seatLabel}` — exists ONLY when staff confirm the person
/// actually arrived. No document = not admitted (a no-show once the screening is over).
///
/// The document ID makes one admission per seat automatic. Staff create it from the
/// Flutter Web app; the rules only allow it for seats of a CONFIRMED reservation.
class Attendance {
  const Attendance({
    required this.reservationId,
    required this.bookingReference,
    required this.screeningId,
    required this.seatLabel,
    required this.attendeeName,
    required this.checkedInBy,
    this.checkedInAt,
    this.remarks,
  });

  final String reservationId;
  final String bookingReference;
  final String screeningId;
  final String seatLabel;
  final String attendeeName;
  final String checkedInBy; // staff UID
  final DateTime? checkedInAt;
  final String? remarks;

  static String docId(String reservationId, String seatLabel) => '${reservationId}_$seatLabel';

  String get id => docId(reservationId, seatLabel);

  factory Attendance.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      Attendance.fromMap(doc.id, doc.data() ?? const {});

  factory Attendance.fromMap(String id, Map<String, dynamic> d) {
    return Attendance(
      reservationId: requireString(d['reservationId'], 'reservationId'),
      bookingReference: requireString(d['bookingReference'], 'bookingReference'),
      screeningId: requireString(d['screeningId'], 'screeningId'),
      seatLabel: requireString(d['seatLabel'], 'seatLabel'),
      attendeeName: requireString(d['attendeeName'], 'attendeeName'),
      checkedInBy: requireString(d['checkedInBy'], 'checkedInBy'),
      checkedInAt: dateOrNull(d['checkedInAt']),
      remarks: stringOrNull(d['remarks']),
    );
  }

  /// New admission. [checkedInAt] is set by the Firestore server clock.
  static Map<String, Object?> toFirestore(Attendance a, SetOptions? _) => {
        'reservationId': a.reservationId,
        'bookingReference': a.bookingReference,
        'screeningId': a.screeningId,
        'seatLabel': a.seatLabel,
        'attendeeName': a.attendeeName,
        'checkedInBy': a.checkedInBy,
        'checkedInAt': FieldValue.serverTimestamp(),
        'remarks': a.remarks,
      };
}
