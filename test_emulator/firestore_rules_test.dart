// Security-rules tests. They run against the LOCAL Firestore emulator only:
//
//   firebase emulators:exec --only firestore --project demo-ccd "flutter test test_emulator"
//
// 200 = the rules allowed the operation, 403 = the rules denied it.

import 'package:flutter_test/flutter_test.dart';

import 'support/emulator_client.dart';

const allowed = 200;
const denied = 403;

final admin = EmulatorClient.admin(); // test setup only (acts like the server)
final guest = EmulatorClient.guest(); // customer — no login
final stranger = EmulatorClient.user('someoneElse'); // has a Firebase Auth account, NOT staff
final inactiveStaff = EmulatorClient.user('staffInactive');
final staff = EmulatorClient.user('staffActive');

final start = DateTime.utc(2026, 11, 20, 10); // 6:00 PM Manila
final end = start.add(const Duration(hours: 2));
final created = DateTime.utc(2026, 9, 1);

Map<String, Object?> staffDoc({required bool active}) => {
      'firstName': 'Test',
      'middleName': null,
      'lastName': 'Staff',
      'email': 'staff@example.test',
      'position': 'AVT',
      'isActive': active,
      'createdAt': created,
    };

Map<String, Object?> movie({Object? poster, String title = 'Himala'}) => {
      'title': title,
      'synopsis': 'A sample synopsis.',
      'runtimeMinutes': 124,
      'rating': 'PG',
      'releaseYear': 1982,
      'genres': ['Drama'],
      'directors': ['Ishmael Bernal'],
      'cast': ['Nora Aunor'],
      'poster': poster,
      'createdAt': serverTime,
      'updatedAt': serverTime,
    };

Map<String, Object?> screening({
  String type = 'free',
  int? price,
  Map<String, Object?> seatHolds = const {},
  bool hasReservations = false,
  String createdBy = 'staffActive',
  DateTime? endAt,
}) =>
    {
      'eventTitle': 'Film Night',
      'movieId': null,
      'movie': null,
      'startAt': start,
      'endAt': endAt ?? end,
      'type': type,
      'priceCentavos': price,
      'capacity': 120,
      'seatHolds': seatHolds,
      'hasReservations': hasReservations,
      'createdBy': createdBy,
      'createdAt': serverTime,
      'updatedAt': serverTime,
    };

Map<String, Object?> reservation({required String status, List<String> seats = const ['A1', 'A2']}) => {
      'bookingReference': 'CCD-TEST${status.substring(0, 4).toUpperCase()}',
      'screeningId': 's-booked',
      'screening': {'eventTitle': 'Film Night', 'startAt': start, 'endAt': end, 'type': 'paid'},
      'status': status,
      'cancellationReason': null,
      'booker': {
        'firstName': 'Juan',
        'middleName': 'Santos',
        'lastName': 'Dela Cruz',
        'contactNo': '09170000000',
        'email': 'juan@example.test',
      },
      'bookerEmailLower': 'juan@example.test',
      'seats': [
        for (final s in seats)
          {
            'label': s,
            'isBooker': s == seats.first,
            'attendee': {'firstName': 'Guest', 'lastName': s},
          },
      ],
      'seatLabels': seats,
      'totalCentavos': 30000,
      'accessKey': 'k-$status',
      'createdAt': created,
    };

Map<String, Object?> admission(String reservationId, String seat,
        {String screeningId = 's-booked', String checkedInBy = 'staffActive', String? ref}) =>
    {
      'reservationId': reservationId,
      'bookingReference': ref ?? (reservationId == 'r-confirmed' ? 'CCD-TESTCONF' : 'CCD-TESTPEND'),
      'screeningId': screeningId,
      'seatLabel': seat,
      'attendeeName': 'Guest $seat',
      'checkedInBy': checkedInBy,
      'checkedInAt': serverTime,
      'remarks': null,
    };

Future<void> seed() async {
  await EmulatorClient.clearAll();
  Future<void> put(String path, Map<String, Object?> data) async {
    final status = await admin.set(path, data);
    if (status != allowed) throw StateError('seed failed for $path: $status');
  }

  await put('staff/staffActive', staffDoc(active: true));
  await put('staff/staffInactive', staffDoc(active: false));
  await put('movies/m1', {...movie(), 'createdAt': created, 'updatedAt': created});
  await put('settings/seatLayout', {
    'seats': [
      {'label': 'A1', 'row': 'A', 'number': 1, 'section': null, 'isActive': true},
    ],
    'updatedAt': created,
    'updatedBy': 'staffActive',
  });
  await put('screenings/s-empty', {...screening(), 'createdAt': created, 'updatedAt': created});
  await put('screenings/s-booked', {
    ...screening(type: 'paid', price: 15000, hasReservations: true, seatHolds: {
      'A1': {'reservationId': 'r-confirmed', 'state': 'confirmed', 'expiresAt': null},
      'A2': {'reservationId': 'r-confirmed', 'state': 'confirmed', 'expiresAt': null},
    }),
    'createdAt': created,
    'updatedAt': created,
  });
  await put('reservations/r-confirmed', reservation(status: 'confirmed'));
  await put('reservations/r-pending', reservation(status: 'pending', seats: ['B1']));
  await put('payments/r-confirmed', {
    'bookingReference': 'CCD-TESTCONF',
    'amountCentavos': 30000,
    'status': 'verified',
    'createdAt': created,
  });
  await put('bookingViews/k-confirmed', {
    'bookingReference': 'CCD-TESTCONF',
    'status': 'confirmed',
    'screening': {'eventTitle': 'Film Night', 'startAt': start, 'endAt': end, 'type': 'paid'},
    'seats': [
      {'label': 'A1', 'attendeeName': 'Guest A1'},
    ],
    'totalCentavos': 30000,
    'paymentStatus': 'verified',
  });
  await put('attendances/r-confirmed_A2', {...admission('r-confirmed', 'A2'), 'checkedInAt': created});
}

void main() {
  setUp(seed);

  group('Customers (no login)', () {
    test('can read the public catalog: movies, screenings, seat layout', () async {
      expect(await guest.get('movies/m1'), allowed);
      expect(await guest.list('movies'), allowed);
      expect(await guest.get('screenings/s-booked'), allowed);
      expect(await guest.list('screenings'), allowed);
      expect(await guest.get('settings/seatLayout'), allowed);
    });

    test('can open ONE booking by its access key, but cannot list bookings', () async {
      expect(await guest.get('bookingViews/k-confirmed'), allowed);
      expect(await guest.list('bookingViews'), denied);
    });

    test('cannot read reservations, payments, attendance or staff', () async {
      expect(await guest.get('reservations/r-confirmed'), denied);
      expect(await guest.list('reservations'), denied);
      expect(await guest.get('payments/r-confirmed'), denied);
      expect(await guest.get('attendances/r-confirmed_A2'), denied);
      expect(await guest.get('staff/staffActive'), denied);
    });

    test('cannot write anything directly (bookings go through the server)', () async {
      expect(await guest.create('movies/new', movie()), denied);
      expect(await guest.create('screenings/new', screening()), denied);
      expect(await guest.set('reservations/fake', reservation(status: 'confirmed')), denied);
      expect(await guest.update('screenings/s-empty', {'seatHolds': {'C1': {'reservationId': 'x', 'state': 'held'}}}), denied);
      expect(await guest.set('bookingViews/k-new', {'status': 'confirmed'}), denied);
      expect(await guest.create('attendances/r-confirmed_A1', admission('r-confirmed', 'A1')), denied);
    });
  });

  group('Signed-in accounts that are NOT active staff', () {
    test('a random Firebase Auth account gets no staff access', () async {
      expect(await stranger.create('movies/new', movie()), denied);
      expect(await stranger.get('reservations/r-confirmed'), denied);
      expect(await stranger.get('staff/staffActive'), denied);
    });

    test('cannot make itself staff', () async {
      expect(await stranger.set('staff/someoneElse', staffDoc(active: true)), denied);
    });

    test('an INACTIVE staff member is locked out but can see their own staff record', () async {
      expect(await inactiveStaff.get('staff/staffInactive'), allowed);
      expect(await inactiveStaff.create('movies/new', movie()), denied);
      expect(await inactiveStaff.get('reservations/r-confirmed'), denied);
      expect(await inactiveStaff.update('staff/staffInactive', {'isActive': true}), denied);
    });
  });

  group('Active staff — movies and seat layout', () {
    test('can create, edit and delete a valid movie', () async {
      expect(await staff.create('movies/new', movie()), allowed);
      expect(await staff.update('movies/m1', {'title': 'Himala (Restored)', 'updatedAt': serverTime}), allowed);
      expect(await staff.delete('movies/m1'), allowed);
    });

    test('invalid movies are rejected', () async {
      expect(await staff.create('movies/bad', movie(title: '')), denied, reason: 'empty title');
      expect(await staff.create('movies/bad', {...movie(), 'runtimeMinutes': -5}), denied, reason: 'bad runtime');
      expect(await staff.create('movies/bad', {...movie(), 'extra': 'x'}), denied, reason: 'unknown field');
      expect(
        await staff.create('movies/bad', movie(poster: {'url': 'https://evil.example/p.jpg', 'publicId': 'p'})),
        denied,
        reason: 'poster must be a Cloudinary URL',
      );
      expect(
        await staff.create('movies/ok', movie(poster: {'url': 'https://res.cloudinary.com/demo/image/upload/p.jpg', 'publicId': 'p'})),
        allowed,
      );
    });

    test('can update the seat layout, stamped with their own UID', () async {
      final layout = {
        'seats': [
          {'label': 'A1', 'row': 'A', 'number': 1, 'section': null, 'isActive': false},
        ],
        'updatedAt': serverTime,
      };
      expect(await staff.set('settings/seatLayout', {...layout, 'updatedBy': 'staffActive'}), allowed);
      expect(await staff.set('settings/seatLayout', {...layout, 'updatedBy': 'someoneElse'}), denied);
      expect(await staff.delete('settings/seatLayout'), denied);
    });
  });

  group('Active staff — screenings', () {
    test('can create a valid free or paid screening', () async {
      expect(await staff.create('screenings/free1', screening()), allowed);
      expect(await staff.create('screenings/paid1', screening(type: 'paid', price: 15000)), allowed);
    });

    test('invalid screenings are rejected', () async {
      expect(await staff.create('screenings/x', screening(type: 'paid')), denied, reason: 'paid without price');
      expect(await staff.create('screenings/x', screening(price: 15000)), denied, reason: 'free with price');
      expect(await staff.create('screenings/x', screening(endAt: start)), denied, reason: 'ends before it starts');
      expect(await staff.create('screenings/x', screening(createdBy: 'someoneElse')), denied, reason: 'createdBy spoofed');
      expect(
        await staff.create('screenings/x', screening(seatHolds: {'A1': {'reservationId': 'x', 'state': 'confirmed'}})),
        denied,
        reason: 'cannot start with seats taken',
      );
      expect(await staff.create('screenings/x', screening(hasReservations: true)), denied);
    });

    test('can edit event details but never seat holds', () async {
      expect(await staff.update('screenings/s-empty', {'eventTitle': 'Renamed', 'updatedAt': serverTime}), allowed);
      expect(
        await staff.update('screenings/s-booked', {'seatHolds': <String, Object?>{}, 'updatedAt': serverTime}),
        denied,
        reason: 'releasing seats is a server action',
      );
      expect(await staff.update('screenings/s-empty', {'hasReservations': true, 'updatedAt': serverTime}), denied);
    });

    test('type, price, capacity and date/time are frozen once a screening has reservations', () async {
      final later = start.add(const Duration(days: 1));
      expect(await staff.update('screenings/s-booked', {'priceCentavos': 1, 'updatedAt': serverTime}), denied);
      expect(await staff.update('screenings/s-booked', {'capacity': 10, 'updatedAt': serverTime}), denied);
      expect(await staff.update('screenings/s-booked', {'startAt': later, 'endAt': later.add(const Duration(hours: 2)), 'updatedAt': serverTime}),
          denied, reason: 'cannot reschedule after people reserved');
      expect(await staff.update('screenings/s-booked', {'eventTitle': 'Typo fixed', 'updatedAt': serverTime}), allowed);
      expect(await staff.update('screenings/s-empty', {'capacity': 100, 'updatedAt': serverTime}), allowed);
      expect(await staff.update('screenings/s-empty', {'startAt': later, 'endAt': later.add(const Duration(hours: 2)), 'updatedAt': serverTime}),
          allowed);
    });

    test('can delete a screening only if it never had reservations', () async {
      expect(await staff.delete('screenings/s-booked'), denied);
      expect(await staff.delete('screenings/s-empty'), allowed);
    });
  });

  group('Active staff — reservations and payments', () {
    test('can read reservations and payments', () async {
      expect(await staff.get('reservations/r-confirmed'), allowed);
      expect(await staff.list('reservations'), allowed);
      expect(await staff.get('payments/r-confirmed'), allowed);
    });

    test('cannot change reservations or payments directly (e.g. approve a paid booking)', () async {
      expect(await staff.update('reservations/r-pending', {'status': 'confirmed'}), denied);
      expect(await staff.update('payments/r-confirmed', {'status': 'pending'}), denied);
      expect(await staff.delete('reservations/r-pending'), denied);
      expect(await staff.set('bookingViews/k-confirmed', {'status': 'cancelled'}), denied);
    });
  });

  group('Active staff — attendance (reservation ≠ attendance)', () {
    test('can admit a seat of a CONFIRMED reservation', () async {
      expect(await staff.create('attendances/r-confirmed_A1', admission('r-confirmed', 'A1')), allowed);
    });

    test('cannot admit a PENDING (unpaid / unapproved) reservation', () async {
      expect(await staff.create('attendances/r-pending_B1', admission('r-pending', 'B1')), denied);
    });

    test('cannot admit a seat that is not part of the reservation', () async {
      expect(await staff.create('attendances/r-confirmed_Z9', admission('r-confirmed', 'Z9')), denied);
    });

    test('record must match its reservation, seat and staff member', () async {
      expect(await staff.create('attendances/wrong-id', admission('r-confirmed', 'A1')), denied, reason: 'doc ID');
      expect(await staff.create('attendances/r-confirmed_A1', admission('r-confirmed', 'A1', screeningId: 's-empty')),
          denied, reason: 'screening mismatch');
      expect(await staff.create('attendances/r-confirmed_A1', admission('r-confirmed', 'A1', ref: 'CCD-OTHER')),
          denied, reason: 'reference mismatch');
      expect(await staff.create('attendances/r-confirmed_A1', admission('r-confirmed', 'A1', checkedInBy: 'someoneElse')),
          denied, reason: 'cannot admit in someone else\'s name');
      expect(await staff.create('attendances/ghost_A1', admission('ghost', 'A1')), denied, reason: 'no such reservation');
    });

    test('the same seat cannot be admitted twice', () async {
      expect(await staff.set('attendances/r-confirmed_A2', admission('r-confirmed', 'A2')), denied);
    });

    test('can add a note, but not change who/what/when', () async {
      expect(await staff.update('attendances/r-confirmed_A2', {'remarks': 'Arrived late'}), allowed);
      expect(await staff.update('attendances/r-confirmed_A2', {'seatLabel': 'A1'}), denied);
      expect(await staff.update('attendances/r-confirmed_A2', {'checkedInBy': 'someoneElse'}), denied);
    });

    test('can undo an admission made by mistake', () async {
      expect(await staff.delete('attendances/r-confirmed_A2'), allowed);
    });
  });
}
