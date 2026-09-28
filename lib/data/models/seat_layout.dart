import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';

/// One seat in the hall. [label] (e.g. "C7") is the seat's permanent ID.
class SeatPosition {
  const SeatPosition({
    required this.label,
    required this.row,
    required this.number,
    this.section,
    this.isActive = true,
  });

  final String label;
  final String row;
  final int number;
  final String? section; // optional grouping if Cinematheque provides one
  final bool isActive; // inactive seats are never offered (broken seat, blocked view…)

  factory SeatPosition.fromMap(Map<String, dynamic> m) => SeatPosition(
        label: requireString(m['label'], 'seats.label'),
        row: requireString(m['row'], 'seats.row'),
        number: intOrNull(m['number']) ?? 0,
        section: stringOrNull(m['section']),
        isActive: m['isActive'] != false,
      );

  Map<String, Object?> toMap() => {
        'label': label,
        'row': row,
        'number': number,
        'section': section,
        'isActive': isActive,
      };
}

/// `settings/seatLayout` — the whole hall in ONE document.
///
/// Why one document instead of a `seats` collection with 120 documents: the customer
/// seat map then costs 1 Firestore read instead of 120, which matters on the free
/// Spark plan (50,000 reads/day). Changing the physical arrangement later means
/// editing this one document (staff settings, Phase 9) or regenerating it with [grid].
class SeatLayout {
  const SeatLayout({required this.seats, this.updatedAt, this.updatedBy});

  static const docPath = 'settings/seatLayout';

  /// Current working layout: 10 rows (A–J) × 12 seats = 120 seats.
  /// [NEEDS CONFIRMATION] of the real physical arrangement; only these two values change.
  static const defaultRows = 'ABCDEFGHIJ';
  static const defaultSeatsPerRow = 12;

  final List<SeatPosition> seats;
  final DateTime? updatedAt;
  final String? updatedBy;

  /// Builds a simple rectangular layout (rows × seatsPerRow).
  factory SeatLayout.grid({String rows = defaultRows, int seatsPerRow = defaultSeatsPerRow}) {
    return SeatLayout(seats: [
      for (final row in rows.split(''))
        for (var n = 1; n <= seatsPerRow; n++) SeatPosition(label: '$row$n', row: row, number: n),
    ]);
  }

  List<SeatPosition> get activeSeats => seats.where((s) => s.isActive).toList(growable: false);

  /// Capacity used when a new screening is created.
  int get activeCount => activeSeats.length;

  /// Seats grouped by row, in order — what the seat map draws.
  Map<String, List<SeatPosition>> get rows {
    final result = <String, List<SeatPosition>>{};
    for (final seat in seats) {
      result.putIfAbsent(seat.row, () => []).add(seat);
    }
    for (final list in result.values) {
      list.sort((a, b) => a.number.compareTo(b.number));
    }
    return result;
  }

  factory SeatLayout.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      SeatLayout.fromMap(doc.id, doc.data() ?? const {});

  factory SeatLayout.fromMap(String id, Map<String, dynamic> d) {
    final raw = d['seats'];
    return SeatLayout(
      seats: raw is List ? raw.whereType<Map>().map((m) => SeatPosition.fromMap(Map<String, dynamic>.from(m))).toList() : const [],
      updatedAt: dateOrNull(d['updatedAt']),
      updatedBy: stringOrNull(d['updatedBy']),
    );
  }

  /// [updatedBy] must be the signed-in staff member's UID (checked by the rules).
  Map<String, Object?> toFirestore(String updatedBy) => {
        'seats': seats.map((s) => s.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': updatedBy,
      };
}
