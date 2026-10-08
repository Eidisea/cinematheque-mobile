import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/data/models/payment.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/staff/auth/staff_session.dart';
import 'package:ccd_mobile/staff/staff_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_dashboard.dart';
import 'staff_auth_test.dart' show FakeStaffSession;

final now = DateTime.utc(2026, 10, 8, 2); // Thursday 10:00 AM Manila
DateTime manila(int day, int hour) => DateTime.utc(2026, 10, day, hour - 8);

const held = SeatHold(reservationId: 'r', state: SeatHoldState.confirmed);

Screening screening(String id, String title, DateTime start, {bool paid = false, int booked = 0}) => Screening(
      id: id,
      eventTitle: title,
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      type: paid ? ScreeningType.paid : ScreeningType.free,
      priceCentavos: paid ? 15000 : null,
      capacity: 120,
      seatHolds: {for (var i = 1; i <= booked; i++) 'A$i': held},
    );

Reservation booking(
  String id,
  Screening s, {
  ReservationStatus status = ReservationStatus.pending,
  int seats = 2,
  Duration age = const Duration(hours: 3),
  DateTime? expiresAt,
  String first = 'Juan',
}) =>
    Reservation(
      id: id,
      bookingReference: 'CCD-${id.toUpperCase().padRight(8, 'X').substring(0, 8)}',
      screeningId: s.id,
      screening: ScreeningSnapshot(eventTitle: s.eventTitle, startAt: s.startAt, endAt: s.endAt, type: s.type),
      status: status,
      booker: Booker(firstName: first, lastName: 'Dela Cruz', contactNo: '09171234567', email: 'j@example.com'),
      seats: [
        for (var i = 1; i <= seats; i++)
          ReservedSeat(label: 'B$i', isBooker: i == 1, attendee: const Attendee(firstName: 'A', lastName: 'B')),
      ],
      totalCentavos: s.isPaid ? 15000 * seats : 0,
      createdAt: now.subtract(age),
      expiresAt: expiresAt,
    );

Payment payment(Reservation r, {bool verified = true, bool refund = false, Duration ago = const Duration(days: 1)}) => Payment(
      reservationId: r.id,
      bookingReference: r.bookingReference,
      amountCentavos: r.totalCentavos,
      status: verified ? PaymentStatus.verified : PaymentStatus.pending,
      paidAt: verified ? now.subtract(ago) : null,
      needsRefund: refund,
      createdAt: now.subtract(ago),
    );

void main() {
  testWidgets('the website dashboard, from live data', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final today = screening('t', 'Morning Shorts', manila(8, 16), booked: 12);
    final malvarosa = screening('m', 'Malvarosa', manila(9, 13), booked: 5);
    final accident = screening('a', 'It Was Just an Accident', manila(12, 15), paid: true, booked: 3);
    final later = screening('l', 'Case 137', manila(20, 17), paid: true);

    final toApprove = booking('zetta', malvarosa, first: 'Zetta', age: const Duration(hours: 15));
    final awaiting = booking('kay', accident, first: 'Kay', seats: 3, expiresAt: now.add(const Duration(minutes: 10)));
    final paidOk = booking('joanie', accident, first: 'Joanie', status: ReservationStatus.confirmed, seats: 4);
    final late = booking('sin', accident, first: 'Sincere', status: ReservationStatus.cancelled, age: const Duration(days: 2));

    final session = FakeStaffSession()..setState(StaffSessionStatus.signedIn, staff: FakeStaffSession.member);
    await tester.pumpWidget(StaffApp(
      startup: const FirebaseStartup.ready(),
      session: session,
      clock: FixedClock(now),
      dashboard: FakeDashboardRepository(
        screenings: [today, malvarosa, accident, later],
        reservations: [toApprove, awaiting, paidOk, late],
        payments: [payment(paidOk), payment(late, refund: true), payment(awaiting, verified: false)],
        admitted: {'t': 7},
      ),
    ));
    await tester.pumpAndSettle();

    // Head: the date and the three figures.
    expect(find.text('Thursday, October 8, 2026'), findsOneWidget);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('4 upcoming screenings', findRichText: true), findsOneWidget);
    expect(find.text('1 awaiting payment', findRichText: true), findsOneWidget);
    expect(find.text('₱600 paid this week', findRichText: true), findsOneWidget, reason: 'the refund-due payment is not counted');

    // Today: admitted shows; the next 7 days are grouped by day; later screenings are left out.
    expect(find.text('Morning Shorts'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('Tomorrow   October 9, 2026', findRichText: true), findsOneWidget);
    expect(find.text('Monday   October 12, 2026', findRichText: true), findsOneWidget);
    expect(find.text('5 / 120'), findsOneWidget);
    expect(find.text('Free · 1 to approve', findRichText: true), findsOneWidget);
    expect(find.text('₱150 · 1 awaiting payment', findRichText: true), findsOneWidget);
    expect(find.text('Case 137'), findsNothing);

    // Needs action: one to approve + one refund; recent bookings with their states.
    expect(find.text('NEEDS ACTION'), findsOneWidget);
    expect(find.text('2'), findsWidgets);
    expect(find.text('TO APPROVE'), findsOneWidget);
    expect(find.text('REFUNDS DUE'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Review'), findsOneWidget);
    expect(find.text('Zetta Dela Cruz'), findsNWidgets(2));
    expect(find.text('Approved · paid'), findsOneWidget);
    expect(find.text('Awaiting payment'), findsOneWidget);
    expect(find.text('Refund due'), findsOneWidget);
    expect(find.text('15h ago'), findsNWidgets(2));

    // The sidebar counts free bookings waiting for approval.
    expect(find.descendant(of: find.byType(Drawer), matching: find.text('1')), findsNothing, reason: 'wide: no drawer');
    expect(find.text('Film catalog'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Review'));
    await tester.pumpAndSettle();
    expect(find.text('Find bookings, check payment status, approve or cancel'), findsOneWidget);
  });

  testWidgets('empty: quiet messages, no made-up numbers', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final session = FakeStaffSession()..setState(StaffSessionStatus.signedIn, staff: FakeStaffSession.member);
    await tester.pumpWidget(StaffApp(
      startup: const FirebaseStartup.ready(),
      session: session,
      clock: FixedClock(now),
      dashboard: FakeDashboardRepository(),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('0 upcoming screenings'), findsOneWidget);
    expect(find.textContaining('₱0 paid this week'), findsOneWidget);
    expect(find.text('No screenings today.'), findsOneWidget);
    expect(find.text('Nothing scheduled.'), findsOneWidget);
    expect(find.text('Nothing to approve or refund.'), findsOneWidget);
    expect(find.text('No bookings yet.'), findsOneWidget);
  });
}
