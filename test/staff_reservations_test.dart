import 'dart:typed_data';

import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/staff/auth/staff_session.dart';
import 'package:ccd_mobile/staff/data/staff_api.dart';
import 'package:ccd_mobile/staff/staff_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_staff_repository.dart';
import 'staff_auth_test.dart' show FakeStaffSession;
import 'staff_dashboard_test.dart' as d;

class FakeStaffApi implements StaffApi {
  final calls = <String>[];
  StaffApiException? failWith;

  Future<void> _record(String call) async {
    calls.add(call);
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> approve(String reservationId) => _record('approve $reservationId');

  @override
  Future<int> approveAll(String screeningId) async {
    await _record('approveAll $screeningId');
    return 1;
  }

  @override
  Future<void> cancel(String reservationId) => _record('cancel $reservationId');

  @override
  Future<String> resendEmail(String reservationId) async {
    await _record('resend $reservationId');
    return 'sent';
  }

  @override
  Future<Poster> uploadPoster(Uint8List bytes, String filename) async {
    await _record('upload $filename');
    return Poster(url: 'https://res.cloudinary.com/tjdy4j9n/image/upload/v1/ccd/posters/$filename', publicId: 'ccd/posters/$filename');
  }

  @override
  Future<void> deletePoster(String publicId) => _record('deletePoster $publicId');

  @override
  Future<String> createStaff(StaffAccountForm form) async {
    await _record('createStaff ${form.email} ${form.position}');
    return 'newuid';
  }

  @override
  Future<void> updateStaff(String uid, StaffAccountForm form) =>
      _record('updateStaff $uid ${form.lastName} password:${form.password == null ? 'kept' : 'new'}');

  @override
  Future<void> setStaffActive(String uid, bool active) => _record('${active ? 'activate' : 'deactivate'} $uid');
}

final malvarosa = d.screening('m', 'Malvarosa', d.manila(9, 13), booked: 5);
final accident = d.screening('a', 'It Was Just an Accident', d.manila(12, 15), paid: true, booked: 3);
final zetta = d.booking('zetta', malvarosa, first: 'Zetta');
final kay = d.booking('kay', accident, first: 'Kay', seats: 3, expiresAt: d.now.add(const Duration(minutes: 10)));
final joanie = d.booking('joanie', accident, first: 'Joanie', status: ReservationStatus.confirmed, seats: 4);
final sincere = d.booking('sin', accident, first: 'Sincere', status: ReservationStatus.cancelled);

Future<FakeStaffApi> pumpStaff(WidgetTester tester, {String at = '/reservations'}) async {
  tester.view.physicalSize = const Size(1440, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final api = FakeStaffApi();
  final session = FakeStaffSession()..setState(StaffSessionStatus.signedIn, staff: FakeStaffSession.member);
  await tester.pumpWidget(StaffApp(
    startup: const FirebaseStartup.ready(),
    session: session,
    clock: FixedClock(d.now),
    api: api,
    data: FakeStaffRepository(
      screenings: [malvarosa, accident],
      reservations: [zetta, kay, joanie, sincere],
      payments: [d.payment(joanie), d.payment(sincere, refund: true), d.payment(kay, verified: false)],
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Reservations').first);
  await tester.pumpAndSettle();
  return api;
}

Finder chip(String label) => find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

void main() {
  group('Reservations list', () {
    testWidgets('quick filters with counts; each booking with its state; Approve only on free ones waiting', (tester) async {
      await pumpStaff(tester);
      expect(find.text('RESERVATION'), findsOneWidget);
      for (final name in ['Zetta Dela Cruz', 'Kay Dela Cruz', 'Joanie Dela Cruz', 'Sincere Dela Cruz']) {
        expect(find.text(name), findsOneWidget, reason: name);
      }
      expect(find.text('Awaiting approval'), findsOneWidget);
      expect(find.text('Awaiting payment'), findsWidgets);
      expect(find.text('Approved · paid'), findsOneWidget);
      expect(find.text('Refund due'), findsWidgets);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsOneWidget);
      expect(find.text('3 people'), findsOneWidget);

      await tester.tap(chip('To approve'));
      await tester.pumpAndSettle();
      expect(find.text('Zetta Dela Cruz'), findsOneWidget);
      expect(find.text('Kay Dela Cruz'), findsNothing);

      await tester.tap(chip('Refund due'));
      await tester.pumpAndSettle();
      expect(find.text('Sincere Dela Cruz'), findsOneWidget);
      expect(find.text('Joanie Dela Cruz'), findsNothing);
    });

    testWidgets('search by reference, name or email', (tester) async {
      await pumpStaff(tester);
      await tester.enterText(find.byType(TextField), 'joanie');
      await tester.pumpAndSettle();
      expect(find.text('Joanie Dela Cruz'), findsOneWidget);
      expect(find.text('Zetta Dela Cruz'), findsNothing);

      await tester.enterText(find.byType(TextField), zetta.bookingReference.toLowerCase().replaceAll('-', ''));
      await tester.pumpAndSettle();
      expect(find.text('Zetta Dela Cruz'), findsOneWidget);
      expect(find.text('Joanie Dela Cruz'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nobody');
      await tester.pumpAndSettle();
      expect(find.text('No matches'), findsOneWidget);
    });

    testWidgets('Approve asks the server and says so', (tester) async {
      final api = await pumpStaff(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(api.calls, ['approve zetta']);
      expect(find.textContaining('The e-ticket was emailed'), findsOneWidget);

      api.failWith = const StaffApiException('not_approvable', detail: 'already confirmed');
      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(find.text('This booking can no longer be approved (already confirmed).'), findsOneWidget);
    });
  });

  group('Booking page', () {
    testWidgets('a free booking waiting: details, attendees, and Approve / Resend / Cancel (with confirmation)', (tester) async {
      final api = await pumpStaff(tester);
      await tester.tap(find.text('Zetta Dela Cruz'));
      await tester.pumpAndSettle();

      expect(find.text('Booking ${zetta.bookingReference}', findRichText: true), findsOneWidget);
      expect(find.text('Zetta Dela Cruz'), findsOneWidget);
      expect(find.text('Awaiting approval'), findsOneWidget);
      expect(find.text('ATTENDEE DETAILS'), findsOneWidget);
      expect(find.text('B1'), findsOneWidget);
      expect(find.text('Free screening.'), findsOneWidget);
      expect(find.text('09171234567'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Resend email'));
      await tester.pumpAndSettle();
      expect(find.text('Email sent again to j@example.com.'), findsOneWidget);

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel booking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel booking?'), findsOneWidget);
      await tester.tap(find.text('Keep booking'));
      await tester.pumpAndSettle();
      expect(api.calls, ['resend zetta'], reason: 'kept');

      await tester.tap(find.widgetWithText(OutlinedButton, 'Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cancel booking'));
      await tester.pumpAndSettle();
      expect(api.calls, ['resend zetta', 'cancel zetta']);

      await tester.tap(find.widgetWithText(FilledButton, 'Approve'));
      await tester.pumpAndSettle();
      expect(api.calls.last, 'approve zetta');
    });

    testWidgets('paid bookings: payment facts; no Approve; a cancelled paid one shows Refund due', (tester) async {
      await pumpStaff(tester);
      await tester.tap(find.text('Joanie Dela Cruz'));
      await tester.pumpAndSettle();
      expect(find.text('Approved · paid'), findsOneWidget);
      expect(find.text('₱600.00'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'Approve'), findsNothing);

      await tester.tap(find.text('Reservations').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Sincere Dela Cruz'));
      await tester.pumpAndSettle();
      expect(find.text('Refund due.', findRichText: true), findsNothing);
      expect(find.textContaining('Refund due.', findRichText: true), findsOneWidget);
      expect(find.text('Paid · refund due'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Cancel booking'), findsNothing, reason: 'already cancelled');
    });
  });
}
