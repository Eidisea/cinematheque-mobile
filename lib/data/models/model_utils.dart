import 'package:cloud_firestore/cloud_firestore.dart';

/// Small helpers shared by the models for reading Firestore values safely.

DateTime? dateOrNull(Object? value) => value is Timestamp ? value.toDate() : null;

DateTime requireDate(Object? value, String field) {
  final date = dateOrNull(value);
  if (date == null) throw FormatException('Missing or invalid timestamp "$field"');
  return date;
}

String requireString(Object? value, String field) {
  if (value is String && value.isNotEmpty) return value;
  throw FormatException('Missing or invalid text "$field"');
}

String? stringOrNull(Object? value) => value is String && value.isNotEmpty ? value : null;

int? intOrNull(Object? value) => value is int ? value : (value is num ? value.toInt() : null);

List<String> stringList(Object? value) =>
    value is List ? value.whereType<String>().toList(growable: false) : const [];

Map<String, dynamic> mapOrEmpty(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

Timestamp? timestampOrNull(DateTime? date) => date == null ? null : Timestamp.fromDate(date);

/// Finds the enum value whose [dbValue] matches what is stored in Firestore.
T enumFromDb<T extends Enum>(List<T> values, String Function(T) dbValue, Object? stored, String field) {
  for (final value in values) {
    if (dbValue(value) == stored) return value;
  }
  throw FormatException('Unknown value "$stored" for "$field"');
}
