import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/staff/auth/staff_session.dart';
import 'package:ccd_mobile/staff/staff_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_staff_repository.dart';
import 'staff_auth_test.dart' show FakeStaffSession;
import 'staff_dashboard_test.dart' as d;
import 'staff_reservations_test.dart' show FakeStaffApi;

const himala = Movie(id: 'himala', title: 'Himala', runtimeMinutes: 124, releaseYear: 1982, genres: ['Drama']);

class Harness {
  Harness(this.repo, this.api);
  final FakeStaffRepository repo;
  final FakeStaffApi api;
}

Future<Harness> pumpStaff(WidgetTester tester, {List<Screening>? screenings, List<Reservation> reservations = const []}) async {
  tester.view.physicalSize = const Size(1440, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = FakeStaffRepository(
    screenings: screenings ??
        [
          d.screening('m', 'Malvarosa', d.manila(9, 13), booked: 2),
          d.screening('old', 'Oro, Plata, Mata', d.manila(1, 18)),
        ],
    reservations: reservations,
    movies: const [himala],
  );
  final api = FakeStaffApi();
  final session = FakeStaffSession()..setState(StaffSessionStatus.signedIn, staff: FakeStaffSession.member);
  await tester.pumpWidget(StaffApp(
    startup: const FirebaseStartup.ready(),
    session: session,
    clock: FixedClock(d.now),
    api: api,
    data: repo,
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Attendance').first);
  await tester.pumpAndSettle();
  return Harness(repo, api);
}

void main() {
  testWidgets('Attendance: upcoming by default, past on request, search by title', (tester) async {
    await pumpStaff(tester);
    expect(find.text('Malvarosa'), findsOneWidget);
    expect(find.text('Oro, Plata, Mata'), findsNothing);

    await tester.tap(find.text('Past'));
    await tester.pumpAndSettle();
    expect(find.text('Oro, Plata, Mata'), findsOneWidget);
    expect(find.text('Malvarosa'), findsNothing);

    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'oro');
    await tester.pumpAndSettle();
    expect(find.text('Oro, Plata, Mata'), findsOneWidget);
    expect(find.text('Malvarosa'), findsNothing);
  });

  testWidgets('a screening page: figures, approve all pending (with confirmation), its bookings', (tester) async {
    final malvarosa = d.screening('m', 'Malvarosa', d.manila(9, 13), booked: 2);
    final h = await pumpStaff(tester, screenings: [malvarosa], reservations: [
      d.booking('ana', malvarosa, first: 'Ana'),
      d.booking('ben', malvarosa, first: 'Ben', status: ReservationStatus.confirmed),
    ]);
    await tester.tap(find.text('Malvarosa'));
    await tester.pumpAndSettle();

    expect(find.text('Friday · October 9, 2026 · 1:00 PM–3:00 PM · Free'), findsOneWidget);
    expect(find.text('2 / 120 seats booked', findRichText: true), findsOneWidget);
    expect(find.text('1 to approve', findRichText: true), findsOneWidget);
    expect(find.text('Ana Dela Cruz'), findsOneWidget);
    expect(find.text('Approved'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Approve all pending (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Approve 1 pending booking and email the e-tickets?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve all'));
    await tester.pumpAndSettle();
    expect(h.api.calls, ['approveAll m']);

    expect(find.widgetWithText(OutlinedButton, 'Delete screening'), findsOneWidget, reason: 'nobody has booked (hasReservations false)');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete screening'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete screening'));
    await tester.pumpAndSettle();
    expect(h.repo.screenings, isEmpty);
    expect(find.text('Deleted “Malvarosa”.'), findsOneWidget);
  });

  testWidgets('new screening: required fields first, then a film from the catalog with the end from its runtime', (tester) async {
    final h = await pumpStaff(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'New screening'));
    await tester.pumpAndSettle();
    expect(find.text('New screening'), findsWidgets);

    await tester.tap(find.widgetWithText(FilledButton, 'Create screening'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a film from the catalog.'), findsOneWidget);
    expect(find.text('Choose a date.'), findsOneWidget);
    expect(find.text('Choose a start time.'), findsOneWidget);

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Himala (1982)').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose a date').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('—').first); // Starts
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    expect(find.text('6:00 PM – 8:04 PM'), findsOneWidget, reason: 'summary: the end follows the 124-minute runtime');

    await tester.tap(find.text('Paid'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '150');
    await tester.pumpAndSettle();
    expect(find.text('₱150 per seat'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Create screening'));
    await tester.pumpAndSettle();
    final created = h.repo.screenings.last;
    expect(created.eventTitle, 'Himala');
    expect(created.movieId, 'himala');
    expect(created.movie?.runtimeMinutes, 124);
    expect(created.startAt, DateTime.utc(2026, 10, 8, 10));
    expect(created.endAt, DateTime.utc(2026, 10, 8, 12, 4));
    expect(created.type, ScreeningType.paid);
    expect(created.priceCentavos, 15000);
    expect(created.capacity, 120);
    expect(find.text('Screening created.'), findsOneWidget);
    expect(find.text('Himala'), findsWidgets, reason: 'now on its page');
  });

  testWidgets('editing a booked screening: title can change; date, time and price are locked', (tester) async {
    final booked = d.screening('m', 'Malvarosa', d.manila(9, 13), booked: 2).withHasReservations();
    final h = await pumpStaff(tester, screenings: [booked]);
    await tester.tap(find.text('Malvarosa'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(OutlinedButton, 'Delete screening'), findsNothing, reason: 'people have booked');
    await tester.tap(find.widgetWithText(OutlinedButton, 'Edit screening'));
    await tester.pumpAndSettle();
    expect(find.textContaining('can’t change'), findsNWidgets(2));

    await tester.enterText(find.byType(TextField).first, 'Malvarosa: 4K Restoration');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    final saved = h.repo.screenings.single;
    expect(saved.eventTitle, 'Malvarosa: 4K Restoration');
    expect(saved.startAt, booked.startAt);
    expect(saved.type, booked.type);
    expect(find.text('Changes saved.'), findsOneWidget);
  });
}

extension on Screening {
  Screening withHasReservations() => Screening(
        id: id,
        eventTitle: eventTitle,
        startAt: startAt,
        endAt: endAt,
        type: type,
        priceCentavos: priceCentavos,
        capacity: capacity,
        seatHolds: seatHolds,
        hasReservations: true,
      );
}
