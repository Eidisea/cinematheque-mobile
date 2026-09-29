import 'dart:async';

import 'package:ccd_mobile/api/booking_api.dart';
import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/customer/customer_app.dart';
import 'package:ccd_mobile/customer/widgets/brand.dart';
import 'package:ccd_mobile/customer/storage/saved_bookings.dart';
import 'package:ccd_mobile/data/models/booking_view.dart';
import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/payment.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/data/models/seat_layout.dart';
import 'package:ccd_mobile/data/repositories/booking_view_repository.dart';
import 'package:ccd_mobile/data/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 11, 20, 2); // 10:00 AM Manila
final start = DateTime.utc(2026, 11, 20, 10); // 6:00 PM Manila

Screening screening({bool paid = false}) => Screening(
      id: 's1',
      eventTitle: 'Film Night',
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      type: paid ? ScreeningType.paid : ScreeningType.free,
      priceCentavos: paid ? 15000 : null,
      capacity: 120,
    );

BookingView view({
  ReservationStatus status = ReservationStatus.pending,
  bool paid = false,
  CancellationReason? reason,
  DateTime? expiresAt,
}) =>
    BookingView(
      accessKey: 'key-1',
      bookingReference: 'CCD-7KQ2M9XA',
      status: status,
      cancellationReason: reason,
      screening: ScreeningSnapshot(
        eventTitle: 'Film Night',
        startAt: start,
        endAt: start.add(const Duration(hours: 2)),
        type: paid ? ScreeningType.paid : ScreeningType.free,
      ),
      seats: const [
        BookingViewSeat(label: 'A1', attendeeName: 'Juan Dela Cruz'),
        BookingViewSeat(label: 'A2', attendeeName: 'Maria Dela Cruz'),
      ],
      totalCentavos: paid ? 30000 : 0,
      paymentStatus: paid ? (status == ReservationStatus.confirmed ? PaymentStatus.verified : PaymentStatus.pending) : null,
      expiresAt: expiresAt,
    );

class FakeCatalog implements CatalogRepository {
  FakeCatalog(this.s);
  final Screening s;
  @override
  Stream<List<Screening>> watchUpcomingScreenings({required DateTime from}) => Stream.value([s]);
  @override
  Stream<Screening?> watchScreening(String id) => Stream.value(s);
  @override
  Stream<Movie?> watchMovie(String id) => Stream.value(null);
  @override
  Stream<List<Screening>> watchScreeningsForMovie(String movieId, {required DateTime from}) => Stream.value(const []);
  @override
  Stream<SeatLayout?> watchSeatLayout() => Stream.value(SeatLayout.grid());
}

class FakeViews implements BookingViewRepository {
  final controllers = <String, StreamController<BookingView?>>{};
  final latest = <String, BookingView?>{};

  void push(String key, BookingView? v) {
    latest[key] = v;
    controllers[key]?.add(v);
  }

  @override
  Future<BookingView?> get(String accessKey) async => latest[accessKey];

  @override
  Stream<BookingView?> watch(String accessKey) {
    final c = controllers.putIfAbsent(accessKey, () => StreamController<BookingView?>.broadcast());
    return Stream.multi((out) {
      if (latest.containsKey(accessKey)) out.add(latest[accessKey]);
      final sub = c.stream.listen(out.add);
      out.onCancel = sub.cancel;
    });
  }
}

class FakeApi implements BookingApi {
  FakeApi(this.views);
  final FakeViews views;
  ReservationRequest? lastRequest;
  ApiException? failCreateWith;
  int cancelCalls = 0;

  @override
  Future<CreatedBooking> createReservation(ReservationRequest request) async {
    lastRequest = request;
    if (failCreateWith != null) throw failCreateWith!;
    views.push('key-1', view());
    return const CreatedBooking(bookingReference: 'CCD-7KQ2M9XA', accessKey: 'key-1', requiresPayment: false, totalCentavos: 0);
  }

  @override
  Future<String> lookup({required String bookingReference, required String email}) async {
    if (bookingReference.toUpperCase().trim() == 'CCD-7KQ2M9XA' && email.trim().toLowerCase() == 'juan@example.com') {
      views.push('key-1', view(status: ReservationStatus.confirmed));
      return 'key-1';
    }
    throw const ApiException('not_found', status: 404);
  }

  @override
  Future<void> cancel(String accessKey) async {
    cancelCalls++;
    views.push(accessKey, view(status: ReservationStatus.cancelled, reason: CancellationReason.customerCancelled));
  }
}

class Harness {
  Harness(this.views, this.api, this.saved);
  final FakeViews views;
  final FakeApi api;
  final MemorySavedBookingsStore saved;
}

Future<Harness> pumpApp(WidgetTester tester, {bool paid = false, List<SavedBooking> saved = const []}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final views = FakeViews();
  final h = Harness(views, FakeApi(views), MemorySavedBookingsStore(saved));
  await tester.pumpWidget(CustomerApp(
    startup: const FirebaseStartup.ready(),
    catalog: FakeCatalog(screening(paid: paid)),
    bookingViews: views,
    savedBookings: h.saved,
    bookingApi: h.api,
    clock: FixedClock(now),
    showIntro: false,
  ));
  await tester.pumpAndSettle();
  return h;
}

Finder field(String label) => find.widgetWithText(TextFormField, label);

Future<void> openDetailsForm(WidgetTester tester) async {
  await tester.tap(find.text('FILM NIGHT'));
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(GoldButton, 'Choose seats'));
  await tester.pumpAndSettle();
  for (final s in ['A1', 'A2']) {
    await tester.tap(find.byKey(ValueKey('seat-$s')));
    await tester.pumpAndSettle();
  }
  await tester.tap(find.widgetWithText(GoldButton, 'Continue'));
  await tester.pumpAndSettle();
}

Future<void> tapFindBooking(WidgetTester tester) async {
  final button = find.widgetWithText(GoldButton, 'Find booking');
  await tester.ensureVisible(button);
  await tester.pumpAndSettle();
  await tester.tap(button);
}

Future<void> enter(WidgetTester tester, Finder f, String text) async {
  await tester.ensureVisible(f);
  await tester.enterText(f, text);
  await tester.pump();
}

/// A field inside one seat's card (the list is built lazily: scroll to it first).
Finder seatField(String seat, String label) => find.descendant(
      of: find.ancestor(of: find.text('Seat $seat'), matching: find.byType(Card)),
      matching: field(label),
    );

final formScroll = find.byType(Scrollable).first;

Future<void> enterIn(WidgetTester tester, String seat, String label, String text) async {
  final f = seatField(seat, label);
  await tester.scrollUntilVisible(f, 120, scrollable: formScroll);
  await tester.enterText(f, text);
  await tester.pump();
}

/// Fills one seat's card with every required detail.
Future<void> fillSeat(WidgetTester tester, String seat, {required String first, required String email, required String sex}) async {
  await enterIn(tester, seat, 'First name', first);
  await enterIn(tester, seat, 'Last name', 'Dela Cruz');
  await enterIn(tester, seat, 'Mobile number', '0917 123 4567');
  await enterIn(tester, seat, 'Email', email);
  await enterIn(tester, seat, 'Age', '30');
  final sexField = find.descendant(
    of: find.ancestor(of: find.text('Seat $seat'), matching: find.byType(Card)),
    matching: find.byType(DropdownButtonFormField<String>),
  );
  await tester.ensureVisible(sexField); // to the top of the view: clear of the sticky Reserve bar
  await tester.pumpAndSettle();
  await tester.tap(sexField);
  await tester.pumpAndSettle();
  await tester.tap(find.text(sex).last);
  await tester.pumpAndSettle();
  await enterIn(tester, seat, 'School or company', 'Ateneo de Davao');
}

/// Seat A1 is the primary booker (Juan); A2 is a guest (Maria).
Future<void> fillValidForm(WidgetTester tester) async {
  await fillSeat(tester, 'A1', first: 'Juan', email: 'juan@example.com', sex: 'Male');
  await fillSeat(tester, 'A2', first: 'Maria', email: 'maria@example.com', sex: 'Female');
}

Future<void> submit(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(GoldButton, 'Reserve seats'));
  await tester.pumpAndSettle();
}

void main() {
  group('Reservation form', () {
    testWidgets('free booking end to end: form → server → saved on phone → booking screen', (tester) async {
      final h = await pumpApp(tester);
      await openDetailsForm(tester);
      expect(find.text("Who's coming?"), findsWidgets);
      expect(find.text('You · primary booker'), findsOneWidget, reason: 'the first seat is the booker');
      expect(find.text('Guest'), findsOneWidget);

      await fillValidForm(tester);
      await submit(tester);

      final r = h.api.lastRequest!;
      expect(r.seats, ['A1', 'A2']);
      expect(r.bookerSeat, 'A1', reason: 'the first seat is always the primary booker');
      expect(r.booker['firstName'], 'Juan');
      expect(r.booker['email'], 'juan@example.com');
      expect(r.booker['middleName'], isNull, reason: 'empty optional text is sent as null');
      expect(r.attendees['A1']!['firstName'], 'Juan');
      expect(r.attendees['A2']!, containsPair('firstName', 'Maria'));
      expect(r.attendees['A2']!, containsPair('email', 'maria@example.com'));
      expect(r.attendees['A2']!, containsPair('age', 30));
      expect(r.attendees['A2']!, containsPair('sex', 'F'));
      expect(r.attendees['A2']!, containsPair('companySchool', 'Ateneo de Davao'));
      expect(r.attendees['A2']!['seniorCardNo'], isNull, reason: 'optional');
      expect(r.attendees['A2']!['isPwd'], isFalse);

      expect(h.saved.bookings.single.bookingReference, 'CCD-7KQ2M9XA');
      expect(find.text('Reservation received'), findsOneWidget);
      expect(find.text('CCD-7KQ2M9XA'), findsOneWidget);
      expect(find.text('Cancel booking'), findsOneWidget);
    });

    testWidgets('missing / invalid fields are highlighted and nothing is sent', (tester) async {
      final h = await pumpApp(tester);
      await openDetailsForm(tester);
      await enterIn(tester, 'A1', 'Email', 'not-an-email');
      await submit(tester);
      expect(h.api.lastRequest, isNull);
      expect(find.text('Please check the highlighted fields.'), findsOneWidget);
      expect(find.text('Enter a valid email address'), findsOneWidget);
      expect(find.text('Required'), findsWidgets);
    });

    testWidgets('seats taken meanwhile → explained, back to the seat map', (tester) async {
      final h = await pumpApp(tester);
      await openDetailsForm(tester);
      await fillValidForm(tester);
      h.api.failCreateWith = const ApiException('seats_taken', status: 409, seats: ['A2']);
      await submit(tester);
      expect(find.text('Seats no longer available'), findsOneWidget);
      expect(find.textContaining('Seat A2 was just reserved by someone else'), findsOneWidget);
      await tester.tap(find.text('Choose seats').last);
      await tester.pumpAndSettle();
      expect(find.text('Choose seats'), findsOneWidget, reason: 'seat map title');
      expect(h.saved.bookings, isEmpty);
    });

    testWidgets('server validation messages name the field', (tester) async {
      final h = await pumpApp(tester);
      await openDetailsForm(tester);
      await fillValidForm(tester);
      h.api.failCreateWith = const ApiException('validation', status: 400, fields: {'attendees.A2.age': 'Enter an age from 0 to 120.'});
      await submit(tester);
      await tester.scrollUntilVisible(find.text('Please fix the following:'), -200, scrollable: find.byType(Scrollable).first);
      expect(find.text('• Seat A2 — age: Enter an age from 0 to 120.'), findsOneWidget);
    });

    testWidgets('paid screening explains the 15-minute payment window', (tester) async {
      await pumpApp(tester, paid: true);
      await openDetailsForm(tester);
      expect(find.text('After reserving, you have 15 minutes to pay online or the seats are released.'), findsOneWidget);
      expect(find.text('₱300'), findsOneWidget);
    });
  });

  group('Booking screen', () {
    Future<Harness> openBooking(WidgetTester tester, BookingView v) async {
      final h = await pumpApp(tester, saved: [
        SavedBooking(bookingReference: 'CCD-7KQ2M9XA', accessKey: 'key-1', eventTitle: 'Film Night', startAt: start, savedAt: now),
      ]);
      h.views.push('key-1', v);
      await tester.tap(find.byKey(const ValueKey('nav-0'))); // Find my booking tab
      await tester.pumpAndSettle();
      await tester.tap(find.text('FILM NIGHT'));
      await tester.pumpAndSettle();
      return h;
    }

    testWidgets('confirmed → e-ticket with ADMIT count, reference, seats and names', (tester) async {
      await openBooking(tester, view(status: ReservationStatus.confirmed, paid: true));
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(find.text('ADMIT 2'), findsOneWidget);
      expect(find.text('Maria Dela Cruz'), findsOneWidget);
      expect(find.text('₱300 · Paid'), findsOneWidget);
      expect(find.text('Cancel booking'), findsNothing, reason: 'confirmed bookings are cancelled by staff');
    });

    testWidgets('paid + pending shows the payment deadline', (tester) async {
      await openBooking(tester, view(paid: true, expiresAt: now.add(const Duration(minutes: 15))));
      expect(find.text('Payment needed'), findsOneWidget);
      expect(find.textContaining('held until 10:15 AM'), findsOneWidget);
    });

    testWidgets('cancelled reasons are explained', (tester) async {
      await openBooking(tester, view(status: ReservationStatus.cancelled, reason: CancellationReason.paymentExpired));
      expect(find.textContaining('not completed within 15 minutes'), findsOneWidget);
    });

    testWidgets('customer cancels a pending booking (with confirmation)', (tester) async {
      final h = await openBooking(tester, view());
      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      expect(find.text('Cancel this booking?'), findsOneWidget);
      await tester.tap(find.text('Keep booking'));
      await tester.pumpAndSettle();
      expect(h.api.cancelCalls, 0);

      await tester.tap(find.text('Cancel booking'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel booking'));
      await tester.pumpAndSettle();
      expect(h.api.cancelCalls, 1);
      expect(find.text('Booking cancelled'), findsOneWidget);
      expect(find.text('You cancelled this booking. The seats were released.'), findsOneWidget);
    });
  });

  group('Find my booking tab', () {
    testWidgets('wrong details are refused; right ones are saved on this phone and opened', (tester) async {
      final h = await pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey('nav-0'))); // Find my booking tab
      await tester.pumpAndSettle();
      expect(find.textContaining('Bookings you make or find on this phone appear here'), findsOneWidget);

      await enter(tester, field('Booking reference'), 'ccd-7kq2m9xa');
      await enter(tester, field('Email used for the booking'), 'wrong@example.com');
      await tapFindBooking(tester);
      await tester.pumpAndSettle();
      expect(find.text('No booking matches that reference and email. Check both and try again.'), findsOneWidget);

      await enter(tester, field('Email used for the booking'), 'JUAN@example.com ');
      await tapFindBooking(tester);
      await tester.pumpAndSettle();
      expect(find.text('Booking confirmed'), findsOneWidget);
      expect(h.saved.bookings.single.accessKey, 'key-1');

      await tester.pageBack();
      await tester.pumpAndSettle();
      // Back on the tab: the form is cleared and the booking is listed under "On this phone".
      expect(find.text('ccd-7kq2m9xa'), findsNothing);
      expect(find.text('FILM NIGHT'), findsOneWidget);
      expect(find.text('CCD-7KQ2M9XA'), findsOneWidget);
    });

    testWidgets('removing from the phone asks first and does not cancel', (tester) async {
      final h = await pumpApp(tester, saved: [
        SavedBooking(bookingReference: 'CCD-7KQ2M9XA', accessKey: 'key-1', eventTitle: 'Film Night', startAt: start, savedAt: now),
      ]);
      await tester.tap(find.byKey(const ValueKey('nav-0'))); // Find my booking tab
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Booking options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from this phone'));
      await tester.pumpAndSettle();
      expect(find.textContaining('The booking itself is not cancelled'), findsOneWidget);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(h.saved.bookings, isEmpty);
      expect(h.api.cancelCalls, 0);
    });
  });
}
