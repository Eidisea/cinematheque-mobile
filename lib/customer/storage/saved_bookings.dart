import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A booking remembered on THIS phone (customers have no accounts).
/// The access key lets the app open the booking's live status; nothing else is stored.
class SavedBooking {
  const SavedBooking({
    required this.bookingReference,
    required this.accessKey,
    required this.eventTitle,
    required this.startAt,
    required this.savedAt,
  });

  final String bookingReference;
  final String accessKey;
  final String eventTitle;
  final DateTime startAt;
  final DateTime savedAt;

  Map<String, Object?> toJson() => {
        'ref': bookingReference,
        'key': accessKey,
        'title': eventTitle,
        'startAt': startAt.toUtc().toIso8601String(),
        'savedAt': savedAt.toUtc().toIso8601String(),
      };

  static SavedBooking? fromJson(Object? j) {
    if (j is! Map) return null;
    try {
      return SavedBooking(
        bookingReference: j['ref'] as String,
        accessKey: j['key'] as String,
        eventTitle: j['title'] as String,
        startAt: DateTime.parse(j['startAt'] as String),
        savedAt: DateTime.parse(j['savedAt'] as String),
      );
    } catch (_) {
      return null;
    }
  }
}

/// The "On this phone" list in the Find my booking tab. Newest screening first.
abstract class SavedBookingsStore extends ChangeNotifier {
  List<SavedBooking> get bookings;

  /// Adds or refreshes a booking (same reference → replaced).
  Future<void> save(SavedBooking booking);

  Future<void> remove(String bookingReference);
}

class PrefsSavedBookingsStore extends SavedBookingsStore {
  PrefsSavedBookingsStore._(this._prefs, this._bookings);

  static const _key = 'saved_bookings_v1';

  final SharedPreferencesAsync _prefs;
  List<SavedBooking> _bookings;

  static Future<PrefsSavedBookingsStore> load() async {
    final prefs = SharedPreferencesAsync();
    List<SavedBooking> list = const [];
    try {
      final raw = await prefs.getString(_key);
      if (raw != null) {
        list = [for (final j in jsonDecode(raw) as List) ?SavedBooking.fromJson(j)];
      }
    } catch (e) {
      debugPrint('Saved bookings could not be read: $e');
    }
    return PrefsSavedBookingsStore._(prefs, _sorted(list));
  }

  static List<SavedBooking> _sorted(List<SavedBooking> list) =>
      [...list]..sort((a, b) => b.startAt.compareTo(a.startAt));

  @override
  List<SavedBooking> get bookings => List.unmodifiable(_bookings);

  @override
  Future<void> save(SavedBooking booking) async {
    _bookings = _sorted([..._bookings.where((b) => b.bookingReference != booking.bookingReference), booking]);
    notifyListeners();
    await _persist();
  }

  @override
  Future<void> remove(String bookingReference) async {
    _bookings = _bookings.where((b) => b.bookingReference != bookingReference).toList();
    notifyListeners();
    await _persist();
  }

  Future<void> _persist() => _prefs.setString(_key, jsonEncode([for (final b in _bookings) b.toJson()]));
}

/// In-memory version for tests.
class MemorySavedBookingsStore extends SavedBookingsStore {
  MemorySavedBookingsStore([List<SavedBooking> initial = const []]) : _bookings = [...initial];

  List<SavedBooking> _bookings;

  @override
  List<SavedBooking> get bookings => List.unmodifiable(_bookings);

  @override
  Future<void> save(SavedBooking booking) async {
    _bookings = [..._bookings.where((b) => b.bookingReference != booking.bookingReference), booking]
      ..sort((a, b) => b.startAt.compareTo(a.startAt));
    notifyListeners();
  }

  @override
  Future<void> remove(String bookingReference) async {
    _bookings = _bookings.where((b) => b.bookingReference != bookingReference).toList();
    notifyListeners();
  }
}
