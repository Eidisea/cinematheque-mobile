import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/movie.dart';
import '../models/screening.dart';
import '../models/seat_layout.dart';
import 'firestore_collections.dart';

/// Read-only access to the public catalog (screenings + movies) for the customer app.
/// All streams update live when staff change something.
abstract class CatalogRepository {
  /// Screenings that have not started yet, soonest first.
  Stream<List<Screening>> watchUpcomingScreenings({required DateTime from});

  /// null when the screening does not exist (or was deleted).
  Stream<Screening?> watchScreening(String id);

  Stream<Movie?> watchMovie(String id);

  /// Upcoming screenings of one movie, soonest first.
  Stream<List<Screening>> watchScreeningsForMovie(String movieId, {required DateTime from});

  /// The hall's seat layout (null if it has not been set up yet).
  Stream<SeatLayout?> watchSeatLayout();
}

class FirestoreCatalogRepository implements CatalogRepository {
  FirestoreCatalogRepository([FirestoreCollections? collections])
      : _c = collections ?? FirestoreCollections(FirebaseFirestore.instance);

  final FirestoreCollections _c;

  static const _listLimit = 100;

  @override
  Stream<List<Screening>> watchUpcomingScreenings({required DateTime from}) => _c.screeningsRaw
      .where('startAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .orderBy('startAt')
      .limit(_listLimit)
      .snapshots()
      .map((snap) => _screenings(snap.docs));

  @override
  Stream<Screening?> watchScreening(String id) => _c.screeningsRaw.doc(id).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : _parse(doc.id, data, Screening.fromMap);
      });

  @override
  Stream<Movie?> watchMovie(String id) => _c.db.collection(FirestoreCollections.moviesPath).doc(id).snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : _parse(doc.id, data, Movie.fromMap);
      });

  /// Filtered on movieId only (no composite index needed); date filter + sort on the phone.
  @override
  Stream<List<Screening>> watchScreeningsForMovie(String movieId, {required DateTime from}) => _c.screeningsRaw
      .where('movieId', isEqualTo: movieId)
      .limit(_listLimit)
      .snapshots()
      .map((snap) => _screenings(snap.docs).where((s) => !s.startAt.isBefore(from)).toList()
        ..sort((a, b) => a.startAt.compareTo(b.startAt)));

  @override
  Stream<SeatLayout?> watchSeatLayout() => _c.seatLayoutRaw.snapshots().map((doc) {
        final data = doc.data();
        return data == null ? null : _parse(doc.id, data, SeatLayout.fromMap);
      });

  List<Screening> _screenings(List<QueryDocumentSnapshot<Map<String, dynamic>>> docs) => [
        for (final doc in docs) ?_parse(doc.id, doc.data(), Screening.fromMap),
      ];

  /// One malformed document must not break the whole list: skip it and log why.
  static T? _parse<T>(String id, Map<String, dynamic> data, T Function(String, Map<String, dynamic>) fromMap) {
    try {
      return fromMap(id, data);
    } on FormatException catch (e) {
      debugPrint('Skipping malformed document $id: ${e.message}');
      return null;
    }
  }
}
