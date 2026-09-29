import 'dart:async';

import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/customer/widgets/brand.dart';
import 'package:ccd_mobile/customer/customer_app.dart';
import 'package:ccd_mobile/customer/seat_map/seat_map_logic.dart';
import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/data/models/seat_layout.dart';
import 'package:ccd_mobile/data/repositories/catalog_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 11, 20, 2); // 10:00 AM Manila
final start = DateTime.utc(2026, 11, 20, 10); // 6:00 PM Manila

Screening screeningWith({Map<String, SeatHold> holds = const {}, bool paid = true, DateTime? startAt}) => Screening(
      id: 's1',
      eventTitle: 'Film Night',
      startAt: startAt ?? start,
      endAt: (startAt ?? start).add(const Duration(hours: 2)),
      type: paid ? ScreeningType.paid : ScreeningType.free,
      priceCentavos: paid ? 15000 : null,
      capacity: 120,
      seatHolds: holds,
    );

const confirmed = SeatHold(reservationId: 'r1', state: SeatHoldState.confirmed);
const freePending = SeatHold(reservationId: 'r2', state: SeatHoldState.held);
SeatHold unpaid(Duration fromNow) => SeatHold(reservationId: 'r3', state: SeatHoldState.held, expiresAt: now.add(fromNow));

void main() {
  group('SeatMapState rules', () {
    final layout = SeatLayout.grid();

    test('seat states: taken (confirmed / free pending / unpaid within 15 min), free again when expired', () {
      final map = SeatMapState(
        layout: layout,
        now: now,
        screening: screeningWith(holds: {
          'A1': confirmed,
          'A2': freePending,
          'A3': unpaid(const Duration(minutes: 5)),
          'A4': unpaid(const Duration(minutes: -1)), // payment window over
        }),
      );
      expect(map.statusOf('A1'), SeatStatus.taken);
      expect(map.statusOf('A2'), SeatStatus.taken);
      expect(map.statusOf('A3'), SeatStatus.taken);
      expect(map.statusOf('A4'), SeatStatus.available);
      expect(map.availableCount, 117);
    });

    test('a released seat (hold removed on cancellation) is available again', () {
      final before = SeatMapState(layout: layout, now: now, screening: screeningWith(holds: {'B1': confirmed}));
      final (after, _) = before.refresh(screening: screeningWith(), layout: layout, now: now);
      expect(before.statusOf('B1'), SeatStatus.taken);
      expect(after.statusOf('B1'), SeatStatus.available);
    });

    test('switched-off seats cannot be chosen', () {
      final custom = SeatLayout(seats: [
        const SeatPosition(label: 'A1', row: 'A', number: 1),
        const SeatPosition(label: 'A2', row: 'A', number: 2, isActive: false),
      ]);
      final map = SeatMapState(layout: custom, now: now, screening: screeningWith());
      expect(map.statusOf('A2'), SeatStatus.unavailable);
      expect(map.tap('A2').$2, SeatTapResult.notAvailable);
      expect(map.availableCount, 1);
    });

    test('select, deselect, taken seats refused, 10-seat limit, total price', () {
      var map = SeatMapState(layout: layout, now: now, screening: screeningWith(holds: {'A1': confirmed}));
      expect(map.tap('A1').$2, SeatTapResult.notAvailable);

      for (final l in ['B3', 'B1', 'B2']) {
        map = map.tap(l).$1;
      }
      expect(map.selectedInOrder, ['B1', 'B2', 'B3'], reason: 'shown in seat order, not tap order');
      expect(map.totalCentavos, 45000);

      final (afterDeselect, result) = map.tap('B2');
      expect(result, SeatTapResult.deselected);
      expect(afterDeselect.selectedInOrder, ['B1', 'B3']);

      for (var n = 1; n <= 10; n++) {
        map = map.tap('C$n').$1;
      }
      expect(map.selected.length, 10);
      expect(map.tap('D1').$2, SeatTapResult.limitReached);
    });

    test('free screening total is 0', () {
      final map = SeatMapState(layout: layout, now: now, screening: screeningWith(paid: false)).tap('A1').$1;
      expect(map.totalCentavos, 0);
    });

    test('if someone else takes a selected seat, it is dropped and reported', () {
      var map = SeatMapState(layout: layout, now: now, screening: screeningWith());
      map = map.tap('E5').$1.tap('E6').$1;
      final (next, lost) = map.refresh(screening: screeningWith(holds: {'E6': confirmed}), layout: layout, now: now);
      expect(lost, ['E6']);
      expect(next.selectedInOrder, ['E5']);
    });

    test('booking closes when the screening starts', () {
      final map = SeatMapState(layout: layout, now: start, screening: screeningWith());
      expect(map.isClosed, isTrue);
      expect(map.tap('A5').$2, SeatTapResult.notAvailable);
      expect(map.canContinue, isFalse);
    });
  });

  group('Seat selection screen', () {
    late StreamController<Screening?> live;

    Future<void> openSeatMap(WidgetTester tester, Screening initial) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      live = StreamController<Screening?>.broadcast();
      addTearDown(live.close);
      final catalog = _LiveCatalog(live, initial);
      await tester.pumpWidget(
        CustomerApp(startup: const FirebaseStartup.ready(), catalog: catalog, clock: FixedClock(now), showIntro: false),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('FILM NIGHT'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(GoldButton, 'Choose seats'));
      await tester.pumpAndSettle();
    }

    Future<void> tapSeat(WidgetTester tester, String label) async {
      await tester.ensureVisible(find.byKey(ValueKey('seat-$label')));
      await tester.tap(find.byKey(ValueKey('seat-$label')));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the 120-seat map with availability and the running total', (tester) async {
      await openSeatMap(tester, screeningWith(holds: {'A1': confirmed, 'A2': unpaid(const Duration(minutes: -2))}));
      expect(find.text('Choose seats'), findsOneWidget);
      expect(find.text('119 of 120 seats available · up to 10 per booking'), findsOneWidget);
      expect(find.bySemanticsLabel('Seat A1, taken'), findsOneWidget);
      expect(find.bySemanticsLabel('Seat A2, available'), findsOneWidget);
      expect(find.text('No seats selected'), findsOneWidget);

      await tapSeat(tester, 'A2');
      await tapSeat(tester, 'A3');
      expect(find.text('2 seats selected'), findsOneWidget);
      expect(find.text('A2'), findsOneWidget); // selected-seat chips
      expect(find.text('A3'), findsOneWidget);
      expect(find.text('₱300'), findsOneWidget);

      await tapSeat(tester, 'A1'); // taken → nothing happens
      expect(find.text('2 seats selected'), findsOneWidget);
    });

    testWidgets('11th seat is refused with a message', (tester) async {
      await openSeatMap(tester, screeningWith());
      for (var n = 1; n <= 10; n++) {
        await tapSeat(tester, 'B$n');
      }
      await tapSeat(tester, 'B11');
      expect(find.text('10 seats selected'), findsOneWidget);
      expect(find.text('You can choose up to 10 seats per booking.'), findsOneWidget);
    });

    testWidgets('a seat taken by someone else while choosing is removed, with a message', (tester) async {
      await openSeatMap(tester, screeningWith());
      await tapSeat(tester, 'C4');
      await tapSeat(tester, 'C5');
      expect(find.text('2 seats selected'), findsOneWidget);

      live.add(screeningWith(holds: {'C5': freePending})); // another customer just booked C5
      await tester.pumpAndSettle();

      expect(find.text('1 seat selected'), findsOneWidget);
      expect(find.bySemanticsLabel('Seat C5, taken'), findsOneWidget);
      expect(find.textContaining('Seat C5 was just taken by someone else'), findsOneWidget);
    });

    testWidgets('no "taken by someone else" message once the customer has moved on to their details', (tester) async {
      // While the booking is being saved, the seat map (still open underneath the details
      // form) sees the customer's OWN seats become taken. That must not be announced.
      await openSeatMap(tester, screeningWith());
      await tapSeat(tester, 'C4');
      await tester.tap(find.widgetWithText(GoldButton, 'Continue'));
      await tester.pumpAndSettle();
      expect(find.text("Who's coming?"), findsWidgets);

      live.add(screeningWith(holds: {'C4': freePending}));
      await tester.pumpAndSettle();
      expect(find.textContaining('was just taken by someone else'), findsNothing);
    });

    testWidgets('a cancelled booking frees its seats live', (tester) async {
      await openSeatMap(tester, screeningWith(holds: {'D1': confirmed}));
      expect(find.bySemanticsLabel('Seat D1, taken'), findsOneWidget);
      live.add(screeningWith()); // server released D1
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Seat D1, available'), findsOneWidget);
    });
  });
}

/// Catalog whose screening updates can be pushed by the test (like Firestore live updates).
class _LiveCatalog implements CatalogRepository {
  _LiveCatalog(this.live, this.initial);

  final StreamController<Screening?> live;
  final Screening initial;

  @override
  Stream<List<Screening>> watchUpcomingScreenings({required DateTime from}) => Stream.value([initial]);

  @override
  Stream<Screening?> watchScreening(String id) async* {
    yield initial;
    yield* live.stream;
  }

  @override
  Stream<Movie?> watchMovie(String id) => Stream.value(null);

  @override
  Stream<List<Screening>> watchScreeningsForMovie(String movieId, {required DateTime from}) => Stream.value(const []);

  @override
  Stream<SeatLayout?> watchSeatLayout() => Stream.value(SeatLayout.grid());
}
