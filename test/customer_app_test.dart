import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/core/formatting.dart';
import 'package:ccd_mobile/customer/customer_app.dart';
import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/data/models/seat_layout.dart';
import 'package:ccd_mobile/data/repositories/catalog_repository.dart';
import 'package:ccd_mobile/customer/screens/screening_details_screen.dart';
import 'package:ccd_mobile/customer/shell/ccd_nav_bar.dart';
import 'package:ccd_mobile/customer/widgets/brand.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// "Now" = Nov 20, 2026, 10:00 AM Manila (02:00 UTC).
final now = DateTime.utc(2026, 11, 20, 2);
DateTime manila(int day, int hour, [int minute = 0]) => DateTime.utc(2026, 11, day, hour - 8, minute);

/// The page's main scroll area (the search box has its own tiny scrollable too).
final mainScroll = find.byType(Scrollable).first;

/// Ticket titles are set in uppercase Oswald.
Finder title(String text) => find.text(text.toUpperCase());

/// Text inside a Text.rich (e.g. the ticket meta line "6:00 PM · ₱150 · 2h 4m").
Finder rich(String text) => find.textContaining(text, findRichText: true);

const himala = Movie(
  id: 'm1',
  title: 'Himala',
  synopsis: 'A sample synopsis.',
  runtimeMinutes: 124,
  rating: 'PG',
  releaseYear: 1982,
  genres: ['Drama'],
  directors: ['Director Name'],
  cast: ['Actor One', 'Actor Two'],
);

Screening screening(
  String id, {
  required DateTime start,
  String title = 'Film Night',
  String? movieId,
  bool paid = false,
  int capacity = 120,
  Map<String, SeatHold> holds = const {},
}) =>
    Screening(
      id: id,
      eventTitle: title,
      movieId: movieId,
      movie: movieId == null ? null : const MovieSnapshot(title: 'Himala', runtimeMinutes: 124, genres: ['Drama']),
      startAt: start,
      endAt: start.add(const Duration(hours: 2)),
      type: paid ? ScreeningType.paid : ScreeningType.free,
      priceCentavos: paid ? 15000 : null,
      capacity: capacity,
      seatHolds: holds,
    );

class FakeCatalog implements CatalogRepository {
  FakeCatalog(this.screenings, {this.failFirst = false});

  final List<Screening> screenings;
  bool failFirst;
  int listCalls = 0;

  @override
  Stream<List<Screening>> watchUpcomingScreenings({required DateTime from}) {
    listCalls++;
    if (failFirst) {
      failFirst = false;
      return Stream.error(Exception('offline'));
    }
    return Stream.value(screenings.where((s) => !s.startAt.isBefore(from)).toList()
      ..sort((a, b) => a.startAt.compareTo(b.startAt)));
  }

  @override
  Stream<Screening?> watchScreening(String id) => Stream.value(screenings.where((s) => s.id == id).firstOrNull);

  @override
  Stream<Movie?> watchMovie(String id) => Stream.value(id == himala.id ? himala : null);

  @override
  Stream<List<Screening>> watchScreeningsForMovie(String movieId, {required DateTime from}) =>
      Stream.value(screenings.where((s) => s.movieId == movieId && !s.startAt.isBefore(from)).toList());

  @override
  Stream<SeatLayout?> watchSeatLayout() => Stream.value(SeatLayout.grid());
}

final catalogData = [
  screening('today-free', start: manila(20, 18), title: 'Himala: Restored', movieId: 'm1'),
  screening('tomorrow-paid', start: manila(21, 19), title: 'Evening Feature', paid: true, capacity: 5, holds: {
    'A1': const SeatHold(reservationId: 'r1', state: SeatHoldState.confirmed),
    'A2': const SeatHold(reservationId: 'r2', state: SeatHoldState.held), // free-style hold, no expiry
    // Unpaid hold whose 15 minutes are over → does NOT count
    'A3': SeatHold(reservationId: 'r3', state: SeatHoldState.held, expiresAt: now.subtract(const Duration(minutes: 1))),
  }),
  screening('sold-out', start: manila(25, 18), title: 'Sold Out Show', capacity: 1, holds: {
    'A1': const SeatHold(reservationId: 'r4', state: SeatHoldState.confirmed),
  }),
  screening('later-himala', start: manila(27, 15), title: 'Himala: Encore', movieId: 'm1'),
  screening('already-started', start: manila(20, 9), title: 'Morning Show'), // started 1h ago
];

Future<FakeCatalog> pumpApp(WidgetTester tester, {List<Screening>? data, bool failFirst = false}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final catalog = FakeCatalog(data ?? catalogData, failFirst: failFirst);
  await tester.pumpWidget(
    CustomerApp(startup: const FirebaseStartup.ready(), catalog: catalog, clock: FixedClock(now), showIntro: false),
  );
  await tester.pumpAndSettle();
  return catalog;
}

void main() {
  group('formatting (always Manila time)', () {
    test('times, dates, pesos, durations', () {
      final t = manila(20, 18, 30);
      expect(formatTime(t), '6:30 PM');
      expect(formatDateLong(t), 'Friday, November 20, 2026');
      expect(dayLabel(t, now), 'Today');
      expect(dayLabel(manila(21, 0, 5), now), 'Tomorrow');
      expect(dayLabel(manila(25, 18), now), 'Wed, Nov 25');
      expect(formatPeso(15000), '₱150');
      expect(formatPeso(15050), '₱150.50');
      expect(formatPeso(125000), '₱1,250');
      expect(formatDuration(124), '2h 4m');
      expect(formatDuration(45), '45m');
    });
  });

  group('Screenings tab', () {
    testWidgets('lists upcoming screenings by day, hides ones that already started', (tester) async {
      await pumpApp(tester);
      expect(find.text('NOW SHOWING'), findsOneWidget);
      // Each ticket's stub carries its date (no separate day headers).
      expect(find.text('FRI'), findsOneWidget);
      expect(find.text('SAT'), findsOneWidget);
      expect(title('Himala: Restored'), findsOneWidget);
      expect(title('Morning Show'), findsNothing);
    });

    testWidgets('shows price and live seat counts (expired unpaid holds are free again)', (tester) async {
      await pumpApp(tester);
      expect(rich('6:00 PM  ·  Free'), findsOneWidget);
      expect(rich('₱150'), findsOneWidget);
      expect(find.text('3 seats left'), findsOneWidget); // capacity 5 − confirmed − free hold
      await tester.scrollUntilVisible(find.text('SOLD OUT'), 200, scrollable: mainScroll);
      expect(find.text('Sold out'), findsOneWidget); // seats line
      expect(find.text('SOLD OUT'), findsOneWidget); // muted pill instead of "Reserve"
    });

    testWidgets('search and Free/Paid filter', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.byKey(const ValueKey('filter-paid')));
      await tester.pumpAndSettle();
      expect(title('Evening Feature'), findsOneWidget);
      expect(title('Himala: Restored'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('filter-all')));
      await tester.enterText(find.byType(TextField), 'himala');
      await tester.pumpAndSettle();
      expect(title('Himala: Restored'), findsOneWidget);
      expect(title('Evening Feature'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pumpAndSettle();
      expect(find.text('No matching screenings'), findsOneWidget);
      await tester.tap(find.text('Clear search and filter'));
      await tester.pumpAndSettle();
      expect(title('Evening Feature'), findsOneWidget);
    });

    testWidgets('empty state when nothing is scheduled', (tester) async {
      await pumpApp(tester, data: []);
      expect(find.text('No upcoming screenings'), findsOneWidget);
    });

    testWidgets('error state with a working "Try again"', (tester) async {
      final catalog = await pumpApp(tester, failFirst: true);
      expect(find.text("Couldn't load this"), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(catalog.listCalls, 2);
      expect(title('Himala: Restored'), findsOneWidget);
    });
  });

  group('Details', () {
    testWidgets('screening details show when, admission, the film and other dates', (tester) async {
      await pumpApp(tester);
      await tester.tap(title('Himala: Restored'));
      await tester.pumpAndSettle();

      expect(find.text('Friday, November 20, 2026'), findsOneWidget);
      expect(find.text('6:00 PM – 8:00 PM'), findsOneWidget);
      expect(find.text('ABOUT THE FILM'), findsOneWidget);
      expect(find.text('A sample synopsis.'), findsOneWidget);
      expect(find.text('Director Name'), findsOneWidget);
      final button = tester.widget<GoldButton>(find.widgetWithText(GoldButton, 'Choose seats'));
      expect(button.onPressed, isNotNull);

      await tester.scrollUntilVisible(find.text('OTHER DATES FOR THIS FILM'), 200, scrollable: mainScroll);
      // Nov 27, 3:00 PM (Himala: Encore) as a small ticket.
      expect(find.widgetWithText(MiniTicket, '3:00 PM'), findsOneWidget);
    });

    testWidgets('movie page lists its upcoming screenings', (tester) async {
      await pumpApp(tester);
      await tester.tap(title('Himala: Restored'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('More about this film'), 200, scrollable: mainScroll);
      await tester.drag(mainScroll, const Offset(0, -200)); // clear of the bottom booking bar
      await tester.pumpAndSettle();
      await tester.tap(find.text('More about this film'));
      await tester.pumpAndSettle();
      expect(find.text('FILM'), findsOneWidget);
      expect(find.text('HIMALA'), findsWidgets);
      await tester.scrollUntilVisible(find.text('UPCOMING SCREENINGS'), 200, scrollable: mainScroll);
      await tester.scrollUntilVisible(title('Himala: Encore'), 200, scrollable: mainScroll);
      expect(title('Himala: Encore'), findsOneWidget);
    });

    testWidgets('sold-out screening says so', (tester) async {
      await pumpApp(tester);
      await tester.scrollUntilVisible(title('Sold Out Show'), 200, scrollable: mainScroll);
      await tester.tap(title('Sold Out Show'));
      await tester.pumpAndSettle();
      expect(find.text('All seats have been reserved.'), findsOneWidget);
      final button = tester.widget<GoldButton>(find.widgetWithText(GoldButton, 'Sold out'));
      expect(button.onPressed, isNull);
    });
  });

  testWidgets('bottom navigation: exactly Find my booking · Screenings · About, opening on Screenings', (tester) async {
    await pumpApp(tester);
    final bar = tester.widget<CcdNavBar>(find.byType(CcdNavBar));
    expect(bar.items.map((d) => d.label), ['Find my booking', 'Screenings', 'About']);
    expect(bar.currentIndex, 1);
    expect(find.byType(NavigationBar), findsNothing, reason: 'custom editorial bar, not the Material one');
    expect(find.text('NOW SHOWING'), findsOneWidget);

    // Screen readers hear one selected tab, in plain case.
    final screenings = tester.getSemantics(find.byKey(const ValueKey('nav-1')).first);
    expect(screenings.label, 'Screenings');
    expect(screenings.getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);

    await tester.tap(find.byKey(const ValueKey('nav-0')));
    await tester.pumpAndSettle();
    expect(tester.widget<CcdNavBar>(find.byType(CcdNavBar)).currentIndex, 0);
    expect(find.text('FIND MY BOOKING'), findsNWidgets(2)); // page title + tab label
    expect(find.widgetWithText(GoldButton, 'Find booking'), findsOneWidget);
    expect(find.text('ON THIS PHONE'), findsOneWidget);
    // Booking education lives here now, not in About.
    await tester.scrollUntilVisible(find.text('HOW BOOKING WORKS'), 200, scrollable: find.byType(Scrollable).first);

    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();
    // Opening: one header for the three title lines, read as a name.
    expect(find.bySemanticsLabel('Cinematheque Centre Davao'), findsOneWidget);
    expect(find.text('PALMA GIL ST. · DAVAO CITY'), findsOneWidget);
    final about = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text('An alternative screen for independent, classic and world cinema.'), 200, scrollable: about);
    await tester.scrollUntilVisible(find.text('THE INSTITUTION'), 200, scrollable: about);
    expect(find.text('FILM DEVELOPMENT COUNCIL OF THE PHILIPPINES'), findsWidgets);
    // Our story: 1919 prologue, then the four institutions as headed chapters.
    await tester.scrollUntilVisible(find.text('FROM A FILM BOARD TO A FILM COUNCIL'), 200, scrollable: about);
    await tester.scrollUntilVisible(find.text('Dalagang Bukid'), 200, scrollable: about);
    for (final era in const [
      '1981. Filipino Motion Picture Development Board',
      '1982 to 1985. Experimental Cinema of the Philippines',
      '1985 to 2002. Film Development Foundation of the Philippines, Inc.',
      '2002 to present. Film Development Council of the Philippines',
    ]) {
      await tester.scrollUntilVisible(find.byWidgetPredicate((w) => w is Semantics && w.properties.label == era), 200, scrollable: about);
    }
    await tester.scrollUntilVisible(find.text('Philippine Film Archive'), 200, scrollable: about);
    // The Centres: FDCP's four, with this one marked; then back to what's showing.
    await tester.scrollUntilVisible(find.text('ACROSS THE COUNTRY'), 200, scrollable: about);
    for (final place in const ['MANILA', 'ILOILO', 'DAVAO', 'NEGROS']) {
      await tester.scrollUntilVisible(find.text('CINEMATHEQUE CENTRE $place'), 200, scrollable: about);
    }
    expect(find.text('Palma Gil St., Davao City'), findsWidgets);
    final showing = find.widgetWithText(GoldButton, "See what's showing");
    await tester.scrollUntilVisible(showing, 200, scrollable: about);
    await tester.tap(showing);
    await tester.pumpAndSettle();
    expect(find.text('NOW SHOWING'), findsOneWidget);
    expect(tester.widget<CcdNavBar>(find.byType(CcdNavBar)).currentIndex, 1);
    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.textContaining('Sources: Film Development Council'), 200, scrollable: about);
    expect(find.text('HOW BOOKING WORKS'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('nav-1')));
    await tester.pumpAndSettle();
    expect(find.text('NOW SHOWING'), findsOneWidget);
  });

  testWidgets('nav bar survives large text and narrow phones', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(320, 640), textScaler: TextScaler.linear(2)),
      child: CustomerApp(startup: const FirebaseStartup.ready(), catalog: FakeCatalog(catalogData), clock: FixedClock(now)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('nav-2')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
