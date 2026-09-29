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

/// DEMO catalog: Cinematheque Centre Davao's real lineup as published by FDCP for May 2026
/// (https://fdcp.ph/events/cinematheque-centre-davao-may-showing) — the most recent Davao
/// schedule FDCP lists publicly. Titles, programmes, start times and prices are FDCP's; the
/// DATES are moved to the coming week so the demo always has upcoming screenings.
/// Film details are limited to facts that are certain (year, director); synopses, runtimes
/// and posters are left empty rather than invented.
Future<void> _seedCatalog(List<String> seatLabels) async {
  final now = DateTime.now().toUtc();
  // Days are counted in Manila time (UTC+8), starting tomorrow.
  final manilaToday = now.add(const Duration(hours: 8));
  DateTime at(int day, int hour, [int minute = 0]) =>
      DateTime.utc(manilaToday.year, manilaToday.month, manilaToday.day + 1 + day, hour - 8, minute);

  // Short forms of FDCP's programme names ("Pamanang Pelikula: A Tribute to …", "FDCP Presents: …"),
  // shown as each ticket's eyebrow.
  const lvn = 'Tribute to LVN Pictures';
  const nora = 'Tribute to Nora Aunor';
  const world = 'FDCP Presents: World Cinema';

  // id: (title, year, directors)
  const films = <String, (String, int?, List<String>)>{
    'malvarosa': ('Malvarosa', 1958, ['Gregorio Fernandez']),
    'biyaya-ng-lupa': ('Biyaya ng Lupa', 1959, ['Manuel Silos']),
    'anak-dalita': ('Anak Dalita', 1956, ['Lamberto V. Avellana']),
    'sumpaan': ('Sumpaan', null, <String>[]),
    'banaue': ('Banaue', 1975, ['Gerardo de León']),
    'himala': ('Himala', 1982, ['Ishmael Bernal']),
    'dont-tell-mother': ("Don't Tell Mother", null, <String>[]),
    'it-was-just-an-accident': ('It Was Just an Accident', 2025, ['Jafar Panahi']),
    'case-137': ('Case 137', 2025, ['Dominik Moll']),
    'the-secret-agent': ('The Secret Agent', 2025, ['Kleber Mendonça Filho']),
    'sound-of-falling': ('Sound of Falling', 2025, ['Mascha Schilinski']),
    'resurrection': ('Resurrection', 2025, ['Bi Gan']),
    'the-blue-trail': ('The Blue Trail', 2025, ['Gabriel Mascaro']),
    'sentimental-value': ('Sentimental Value', 2025, ['Joachim Trier']),
  };
  for (final e in films.entries) {
    final (title, year, directors) = e.value;
    await _writeDoc('movies/${e.key}', {
      'title': title,
      'synopsis': null,
      'runtimeMinutes': null,
      'rating': null,
      'releaseYear': year,
      'genres': <String>[],
      'directors': directors,
      'cast': <String>[],
      'poster': null,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  var count = 0;
  Future<void> screening(String movieId, DateTime start, {required String programme, int? price, Map<String, Object?> holds = const {}}) {
    count++;
    final title = films[movieId]!.$1;
    return _writeDoc('screenings/$movieId-${start.toIso8601String().substring(0, 10)}', {
      'eventTitle': title,
      'movieId': movieId,
      'movie': {'title': title, 'posterUrl': null, 'runtimeMinutes': null, 'genres': [programme]},
      'startAt': start,
      'endAt': start.add(const Duration(hours: 2)),
      'type': price == null ? 'free' : 'paid',
      'priceCentavos': price,
      'capacity': seatLabels.length,
      'seatHolds': holds,
      'hasReservations': holds.isNotEmpty,
      'createdBy': 'seed',
      'createdAt': now,
      'updatedAt': now,
    });
  }

  // A few seats already taken, so the seat map looks lived-in.
  Map<String, Object?> taken(List<String> seats) =>
      {for (final l in seats) l: {'reservationId': 'demo-${seats.first}', 'state': 'confirmed', 'expiresAt': null}};

  // Pamanang Pelikula: LVN Pictures (free)
  await screening('malvarosa', at(0, 13), programme: lvn, holds: taken(['E5', 'E6', 'E7']));
  await screening('biyaya-ng-lupa', at(0, 15), programme: lvn);
  await screening('anak-dalita', at(1, 13), programme: lvn);
  await screening('sumpaan', at(1, 15), programme: lvn);
  // Pamanang Pelikula: Nora Aunor (free)
  await screening('banaue', at(2, 15), programme: nora);
  await screening('himala', at(5, 17), programme: nora, holds: {
    for (final l in seatLabels.take(112)) l: {'reservationId': 'demo-himala', 'state': 'confirmed', 'expiresAt': null},
  });
  // FDCP Presents: world cinema (₱150)
  await screening('dont-tell-mother', at(3, 13), programme: world, price: 15000);
  await screening('it-was-just-an-accident', at(3, 15), programme: world, price: 15000, holds: taken(['D6', 'D7']));
  await screening('case-137', at(3, 17), programme: world, price: 15000);
  await screening('the-secret-agent', at(4, 12), programme: world, price: 15000);
  await screening('sound-of-falling', at(4, 15), programme: world, price: 15000);
  await screening('resurrection', at(6, 12), programme: world, price: 15000);
  await screening('the-blue-trail', at(6, 15), programme: world, price: 15000);
  await screening('sentimental-value', at(6, 17), programme: world, price: 15000, holds: taken(['F5', 'F6', 'F7', 'F8']));
  stdout.writeln('  demo catalog: Cinematheque Davao lineup (FDCP, May 2026) — ${films.length} films, $count screenings');
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
