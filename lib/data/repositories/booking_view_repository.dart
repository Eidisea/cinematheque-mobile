import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../models/booking_view.dart';
import 'firestore_collections.dart';

/// The customer's live copy of ONE booking, opened with its access key.
/// Security rules allow reading a single document by key, never listing.
abstract class BookingViewRepository {
  /// null when no booking has this key.
  Stream<BookingView?> watch(String accessKey);

  /// One-time read (e.g. right after "Find a booking").
  Future<BookingView?> get(String accessKey);
}

class FirestoreBookingViewRepository implements BookingViewRepository {
  FirestoreBookingViewRepository([this._given]);

  final FirestoreCollections? _given;

  // Connects on first use (keeps tests that never open a booking free of Firebase).
  late final FirestoreCollections _c = _given ?? FirestoreCollections(FirebaseFirestore.instance);

  DocumentReference<Map<String, dynamic>> _doc(String key) =>
      _c.db.collection(FirestoreCollections.bookingViewsPath).doc(key);

  @override
  Stream<BookingView?> watch(String accessKey) => _doc(accessKey).snapshots().map(_parse);

  @override
  Future<BookingView?> get(String accessKey) async => _parse(await _doc(accessKey).get());

  static BookingView? _parse(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    if (data == null) return null;
    try {
      return BookingView.fromMap(doc.id, data);
    } on FormatException catch (e) {
      debugPrint('Malformed booking view: ${e.message}');
      return null;
    }
  }
}
