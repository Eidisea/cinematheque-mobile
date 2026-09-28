// Seeds the LOCAL Firebase emulators for development.
// It cannot touch the real project: it only talks to 127.0.0.1.
//
//   1. firebase emulators:start --only auth,firestore --project cinematheque-48a54
//   2. dart run tool/seed_emulator.dart
//   3. flutter run -d chrome -t lib/main_staff.dart --dart-define=USE_EMULATORS=true
//
// The emulators use the real project ID (Android cannot change it), but everything
// here — and everything the app does in emulator mode — stays on this computer.
//
// The accounts below exist ONLY inside the emulator. Their passwords are test values.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const projectId = 'cinematheque-48a54'; // namespace inside the LOCAL emulators only
const authBase = 'http://127.0.0.1:9099';
const firestoreBase = 'http://127.0.0.1:8080';
const testPassword = 'emulator-only-pass-1';

const accounts = [
  (email: 'avt.active@ccd.test', first: 'Ana', last: 'Reyes', position: 'AVT', staff: true, active: true),
  (email: 'pdo.inactive@ccd.test', first: 'Ben', last: 'Santos', position: 'PDO', staff: true, active: false),
  (email: 'not.staff@ccd.test', first: 'Cara', last: 'Lim', position: 'AVT', staff: false, active: false),
];

Future<void> main() async {
  try {
    await _clear();
    for (final a in accounts) {
      final uid = await _createAuthUser(a.email);
      if (a.staff) {
        await _writeDoc('staff/$uid', {
          'firstName': a.first,
          'middleName': null,
          'lastName': a.last,
          'email': a.email,
          'position': a.position,
          'isActive': a.active,
          'createdAt': DateTime.now().toUtc(),
        });
      }
      stdout.writeln('  ${a.email.padRight(24)} ${a.staff ? (a.active ? 'active staff' : 'INACTIVE staff') : 'not staff'}');
    }

    // Same grid as SeatLayout.grid() in the app: rows A–J × 12 seats = 120.
    final seats = [
      for (final row in 'ABCDEFGHIJ'.split(''))
        for (var n = 1; n <= 12; n++) {'label': '$row$n', 'row': row, 'number': n, 'section': null, 'isActive': true},
    ];
    await _writeDoc('settings/seatLayout', {
      'seats': seats,
      'updatedAt': DateTime.now().toUtc(),
      'updatedBy': 'seed',
    });
    stdout.writeln('  seat layout: ${seats.length} seats');

    await _seedCatalog(seats.map((s) => s['label'] as String).toList());
    stdout.writeln('Seeded. All accounts use the test password in tool/seed_emulator.dart.');
  } on SocketException {
    stderr.writeln('Emulators are not running. Start them first:\n'
        '  firebase emulators:start --only auth,firestore --project $projectId');
    exitCode = 1;
  }
}

/// SAMPLE catalog for local testing only — fictional titles, no posters (none provided).
Future<void> _seedCatalog(List<String> seatLabels) async {
  final now = DateTime.now().toUtc();
  final hour = DateTime.utc(now.year, now.month, now.day, now.hour);
  DateTime at(Duration d) => hour.add(d);

  const films = {
    'sample-film-1': (
      title: 'Lungsod ng Ulan',
      synopsis: 'Sample data for local testing only. A fictional drama used to check the customer app layout.',
      runtime: 118,
      rating: 'PG',
      year: 2024,
      genres: ['Drama'],
      directors: ['Sample Director'],
      cast: ['Sample Actor One', 'Sample Actor Two'],
    ),
    'sample-film-2': (
      title: 'Dagat at Liwanag',
      synopsis: 'Sample data for local testing only. A fictional documentary.',
      runtime: 92,
      rating: 'G',
      year: 2023,
      genres: ['Documentary', 'Family'],
      directors: ['Another Sample Director'],
      cast: <String>[],
    ),
  };
  for (final e in films.entries) {
    final f = e.value;
    await _writeDoc('movies/${e.key}', {
      'title': f.title,
      'synopsis': f.synopsis,
      'runtimeMinutes': f.runtime,
      'rating': f.rating,
      'releaseYear': f.year,
      'genres': f.genres,
      'directors': f.directors,
      'cast': f.cast,
      'poster': null,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Map<String, Object?> movieSnap(String id) {
    final f = films[id]!;
    return {'title': f.title, 'posterUrl': null, 'runtimeMinutes': f.runtime, 'genres': f.genres};
  }

  Future<void> screening(String id, String title, Duration startsIn, {String? movieId, int? price, Map<String, Object?> holds = const {}}) =>
      _writeDoc('screenings/$id', {
        'eventTitle': title,
        'movieId': movieId,
        'movie': movieId == null ? null : movieSnap(movieId),
        'startAt': at(startsIn),
        'endAt': at(startsIn + const Duration(hours: 2)),
        'type': price == null ? 'free' : 'paid',
        'priceCentavos': price,
        'capacity': seatLabels.length,
        'seatHolds': holds,
        'hasReservations': holds.isNotEmpty,
        'createdBy': 'seed',
        'createdAt': now,
        'updatedAt': now,
      });

  await screening('sample-today', 'Lungsod ng Ulan', const Duration(hours: 6), movieId: 'sample-film-1');
  await screening('sample-tomorrow-paid', 'Dagat at Liwanag: Special Screening', const Duration(days: 1, hours: 3),
      movieId: 'sample-film-2', price: 15000, holds: {
        'A1': {'reservationId': 'sample-r1', 'state': 'confirmed', 'expiresAt': null},
        'A2': {'reservationId': 'sample-r1', 'state': 'confirmed', 'expiresAt': null},
        'B5': {'reservationId': 'sample-r2', 'state': 'held', 'expiresAt': now.add(const Duration(minutes: 10))},
        'C7': {'reservationId': 'sample-r3', 'state': 'held', 'expiresAt': now.subtract(const Duration(minutes: 5))},
      });
  await screening('sample-festival', 'Short Film Showcase (sample)', const Duration(days: 3, hours: 2));
  await screening('sample-sold-out', 'Lungsod ng Ulan: Encore', const Duration(days: 5, hours: 4),
      movieId: 'sample-film-1', price: 20000, holds: {
        for (final l in seatLabels) l: {'reservationId': 'sample-full', 'state': 'confirmed', 'expiresAt': null},
      });
  await screening('sample-started', 'Already Started (hidden)', const Duration(minutes: -30));
  stdout.writeln('  sample catalog: ${films.length} films, 5 screenings');
}

Future<void> _clear() async {
  await http.delete(Uri.parse('$authBase/emulator/v1/projects/$projectId/accounts'));
  await http.delete(Uri.parse('$firestoreBase/emulator/v1/projects/$projectId/databases/(default)/documents'));
}

Future<String> _createAuthUser(String email) async {
  final res = await http.post(
    Uri.parse('$authBase/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator'),
    headers: {'Content-Type': 'application/json'},
    body: jsonEncode({'email': email, 'password': testPassword, 'returnSecureToken': true}),
  );
  if (res.statusCode != 200) throw StateError('Auth emulator: ${res.body}');
  return (jsonDecode(res.body) as Map<String, dynamic>)['localId'] as String;
}

Future<void> _writeDoc(String path, Map<String, Object?> data) async {
  final res = await http.patch(
    Uri.parse('$firestoreBase/v1/projects/$projectId/databases/(default)/documents/$path'),
    headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer owner'},
    body: jsonEncode({'fields': {for (final e in data.entries) e.key: _encode(e.value)}}),
  );
  if (res.statusCode != 200) throw StateError('Firestore emulator ($path): ${res.body}');
}

Map<String, Object?> _encode(Object? v) => switch (v) {
      null => {'nullValue': null},
      bool b => {'booleanValue': b},
      int i => {'integerValue': '$i'},
      String s => {'stringValue': s},
      DateTime d => {'timestampValue': d.toIso8601String()},
      List l => {'arrayValue': {'values': l.map(_encode).toList()}},
      Map m => {'mapValue': {'fields': {for (final e in m.entries) e.key as String: _encode(e.value)}}},
      _ => throw ArgumentError('Unsupported: ${v.runtimeType}'),
    };
