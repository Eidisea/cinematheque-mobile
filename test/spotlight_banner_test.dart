import 'dart:ui' show Tristate;

import 'package:ccd_mobile/customer/theme/customer_theme.dart';
import 'package:ccd_mobile/customer/widgets/spotlight_banner.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 11, 20, 2); // 10:00 AM Manila

Screening show(String id, String title, {required int inDays, String? movieId, bool paid = false, Map<String, SeatHold> holds = const {}}) {
  final start = now.add(Duration(days: inDays, hours: 8));
  return Screening(
    id: id,
    eventTitle: title,
    movieId: movieId,
    startAt: start,
    endAt: start.add(const Duration(hours: 2)),
    type: paid ? ScreeningType.paid : ScreeningType.free,
    priceCentavos: paid ? 15000 : null,
    capacity: 1,
    seatHolds: holds,
  );
}

Future<List<Screening>> pumpBanner(WidgetTester tester, List<Screening> screenings) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final opened = <Screening>[];
  await tester.pumpWidget(MaterialApp(
    theme: buildCustomerTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: SpotlightBanner(screenings: screenings, now: now, onOpen: opened.add),
      ),
    ),
  ));
  await tester.pump();
  return opened;
}

void main() {
  test('one card per film, soonest first, at most five; a sold-out show gives way to the next one with seats', () {
    const full = SeatHold(reservationId: 'r', state: SeatHoldState.confirmed);
    final featured = SpotlightBanner.featured([
      show('a1', 'Himala', inDays: 1, movieId: 'm1', holds: {'A1': full}),
      show('a2', 'Himala', inDays: 2, movieId: 'm1'),
      show('b', 'Oro, Plata, Mata', inDays: 1, movieId: 'm2'),
      show('c', 'Shorts Night', inDays: 3),
      show('d', 'Anak Dalita', inDays: 4, movieId: 'm3'),
      show('e', 'Sumpaan', inDays: 5, movieId: 'm4'),
      show('f', 'Biyaya ng Lupa', inDays: 6, movieId: 'm5'),
      show('past', 'Old Show', inDays: -1, movieId: 'm6'),
    ], now);
    expect(featured.map((s) => s.id), ['a2', 'b', 'c', 'd', 'e']);
  });

  group('banner', () {
    setUp(() => SpotlightBanner.autoplay = false);
    tearDown(() => SpotlightBanner.autoplay = false);

    testWidgets('kicker, title, number, tag and "Book seats" for the current film', (tester) async {
      final opened = await pumpBanner(tester, [
        show('s1', 'Himala', inDays: 1, movieId: 'm1', paid: true),
        show('s2', 'Sumpaan', inDays: 9, movieId: 'm2'),
      ]);
      expect(find.text('HIMALA'), findsWidgets); // title (and the generated poster art)
      expect(find.text('NOW SHOWING'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('₱150'), findsOneWidget);
      expect(find.text('OPENS NOV 29'), findsOneWidget, reason: 'the later film shows when it opens');

      await tester.tap(find.text('Book seats').first);
      expect(opened.map((s) => s.id), ['s1']);
    });

    testWidgets('dots switch films; autoplay moves on by itself and the pause button stops it', (tester) async {
      SpotlightBanner.autoplay = true;
      final semantics = tester.ensureSemantics();
      await pumpBanner(tester, [
        show('s1', 'Himala', inDays: 1, movieId: 'm1'),
        show('s2', 'Sumpaan', inDays: 2, movieId: 'm2'),
        show('s3', 'Anak Dalita', inDays: 3, movieId: 'm3'),
      ]);
      bool isCurrent(String title) =>
          tester.getSemantics(find.bySemanticsLabel('Show $title')).flagsCollection.isSelected == Tristate.isTrue;
      expect(isCurrent('Himala'), isTrue);

      // Let the slide's time run out, then a second of frames for the page to move.
      await tester.pump();
      await tester.pump(SpotlightBanner.slideDuration);
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(isCurrent('Sumpaan'), isTrue, reason: 'autoplay advanced');

      await tester.tap(find.byTooltip('Pause slideshow'));
      await tester.pump(SpotlightBanner.slideDuration * 2);
      expect(isCurrent('Sumpaan'), isTrue, reason: 'paused');
      expect(find.byTooltip('Play slideshow'), findsOneWidget);

      await tester.tap(find.bySemanticsLabel('Show Anak Dalita'));
      await tester.pumpAndSettle();
      expect(isCurrent('Anak Dalita'), isTrue);
      semantics.dispose();
    });
  });
}
