import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';

enum ScreeningType { free, paid }

enum SeatHoldState { held, confirmed }

/// A seat taken by a reservation for one screening.
///
/// - held + expiresAt → paid booking waiting for payment (15-minute window)
/// - held, no expiresAt → free booking waiting for staff approval (never expires)
/// - confirmed → approved/paid booking
///
/// Holds contain no personal data (the map is publicly readable for the seat map).
/// [reservationId] is the reservation's random document ID, not the booking reference.
class SeatHold {
  const SeatHold({required this.reservationId, required this.state, this.expiresAt});

  final String reservationId;
  final SeatHoldState state;
  final DateTime? expiresAt;

  /// An unpaid hold whose payment window has passed no longer blocks the seat,
  /// even before the expiry job has cleaned it up.
  bool isActiveAt(DateTime now) =>
      state == SeatHoldState.confirmed || expiresAt == null || expiresAt!.isAfter(now);

  factory SeatHold.fromMap(Map<String, dynamic> m) => SeatHold(
        reservationId: requireString(m['reservationId'], 'seatHolds.reservationId'),
        state: enumFromDb(SeatHoldState.values, (s) => s.name, m['state'], 'seatHolds.state'),
        expiresAt: dateOrNull(m['expiresAt']),
      );
}

/// Copy of the movie details a screening needs for lists (avoids an extra read per card).
class MovieSnapshot {
  const MovieSnapshot({required this.title, this.posterUrl, this.runtimeMinutes, this.genres = const []});

  final String title;
  final String? posterUrl;
  final int? runtimeMinutes;
  final List<String> genres;

  static MovieSnapshot? fromMap(Object? value) {
    if (value is! Map) return null;
    final m = Map<String, dynamic>.from(value);
    return MovieSnapshot(
      title: requireString(m['title'], 'movie.title'),
      posterUrl: stringOrNull(m['posterUrl']),
      runtimeMinutes: intOrNull(m['runtimeMinutes']),
      genres: stringList(m['genres']),
    );
  }

  Map<String, Object?> toMap() => {
        'title': title,
        'posterUrl': posterUrl,
        'runtimeMinutes': runtimeMinutes,
        'genres': genres,
      };
}

/// `screenings/{screeningId}` — one event on one date/time. Readable by everyone.
///
/// Staff (Flutter Web) write the event fields. The server alone writes [seatHolds]
/// and [hasReservations]; the security rules reject any client change to them.
class Screening {
  const Screening({
    this.id = '',
    required this.eventTitle,
    this.movieId,
    this.movie,
    required this.startAt,
    required this.endAt,
    required this.type,
    this.priceCentavos,
    required this.capacity,
    this.seatHolds = const {},
    this.hasReservations = false,
    this.createdBy = '',
    this.createdAt,
    this.updatedAt,
  });

  /// The only fields staff may change after creation.
  static const staffEditableFields = [
    'eventTitle', 'movieId', 'movie', 'startAt', 'endAt', 'type', 'priceCentavos', 'capacity', 'updatedAt',
  ];

  final String id;
  final String eventTitle;
  final String? movieId; // null → not tied to a movie (festival, talk, shorts program…)
  final MovieSnapshot? movie;
  final DateTime startAt;
  final DateTime endAt;
  final ScreeningType type;
  final int? priceCentavos; // per seat; null when free. Stored in centavos to avoid rounding errors.
  final int capacity; // number of active seats when the screening was created
  final Map<String, SeatHold> seatHolds; // key = seat label
  final bool hasReservations; // true once anyone reserved → cannot be deleted; type/price/capacity/date/time frozen
  final String createdBy;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPaid => type == ScreeningType.paid;

  /// Booking closes when the screening starts.
  bool isBookableAt(DateTime now) => now.isBefore(startAt);

  Set<String> takenSeatLabelsAt(DateTime now) =>
      {for (final e in seatHolds.entries) if (e.value.isActiveAt(now)) e.key};

  int availableSeatsAt(DateTime now) =>
      (capacity - takenSeatLabelsAt(now).length).clamp(0, capacity);

  factory Screening.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      Screening.fromMap(doc.id, doc.data() ?? const {});

  factory Screening.fromMap(String id, Map<String, dynamic> d) {
    return Screening(
      id: id,
      eventTitle: requireString(d['eventTitle'], 'eventTitle'),
      movieId: stringOrNull(d['movieId']),
      movie: MovieSnapshot.fromMap(d['movie']),
      startAt: requireDate(d['startAt'], 'startAt'),
      endAt: requireDate(d['endAt'], 'endAt'),
      type: enumFromDb(ScreeningType.values, (t) => t.name, d['type'], 'type'),
      priceCentavos: intOrNull(d['priceCentavos']),
      capacity: intOrNull(d['capacity']) ?? 0,
      seatHolds: {
        for (final e in mapOrEmpty(d['seatHolds']).entries)
          if (e.value is Map) e.key: SeatHold.fromMap(Map<String, dynamic>.from(e.value as Map)),
      },
      hasReservations: d['hasReservations'] == true,
      createdBy: stringOrNull(d['createdBy']) ?? '',
      createdAt: dateOrNull(d['createdAt']),
      updatedAt: dateOrNull(d['updatedAt']),
    );
  }

  Map<String, Object?> _eventFields() => {
        'eventTitle': eventTitle,
        'movieId': movieId,
        'movie': movie?.toMap(),
        'startAt': Timestamp.fromDate(startAt),
        'endAt': Timestamp.fromDate(endAt),
        'type': type.name,
        'priceCentavos': isPaid ? priceCentavos : null,
        'capacity': capacity,
        'updatedAt': FieldValue.serverTimestamp(),
      };

  /// Full document for CREATING a screening (staff). Starts with no seat holds.
  Map<String, Object?> toNewDocument(String staffUid) => {
        ..._eventFields(),
        'seatHolds': <String, Object?>{},
        'hasReservations': false,
        'createdBy': staffUid,
        'createdAt': FieldValue.serverTimestamp(),
      };

  /// The same screening under another document ID (e.g. once created).
  Screening withId(String newId) => Screening(
        id: newId,
        eventTitle: eventTitle,
        movieId: movieId,
        movie: movie,
        startAt: startAt,
        endAt: endAt,
        type: type,
        priceCentavos: priceCentavos,
        capacity: capacity,
        seatHolds: seatHolds,
        hasReservations: hasReservations,
        createdBy: createdBy,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );

  /// Fields for UPDATING a screening (staff) with `update()`, never `set()`,
  /// so seat holds written by the server are not overwritten.
  Map<String, Object?> toStaffUpdate() => _eventFields();
}
