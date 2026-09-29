import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/customer/customer_app.dart';
import 'package:ccd_mobile/customer/widgets/ccd_mark.dart';
import 'package:ccd_mobile/customer/widgets/splash_intro.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'customer_app_test.dart' show FakeCatalog, catalogData, now;

Future<void> pumpApp(WidgetTester tester, {bool reducedMotion = false}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final app = CustomerApp(startup: const FirebaseStartup.ready(), catalog: FakeCatalog(catalogData), clock: FixedClock(now));
  await tester.pumpWidget(
    reducedMotion ? MediaQuery(data: const MediaQueryData(size: Size(412, 915), disableAnimations: true), child: app) : app,
  );
}

void main() {
  testWidgets('the intro plays once over Screenings, the ticket tears, and it leaves', (tester) async {
    await pumpApp(tester);
    expect(find.byType(SplashIntro), findsOneWidget);

    // Mid-way: the name is being revealed over the page that is already loading beneath.
    await tester.pump(const Duration(milliseconds: 1100));
    expect(find.text('CINEMATHEQUE'), findsWidgets);
    expect(find.descendant(of: find.byType(SplashIntro), matching: find.text('CENTRE DAVAO')), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.byType(SplashIntro), findsNothing);
    expect(find.text('NOW SHOWING'), findsOneWidget);
  });

  testWidgets('a tap skips it', (tester) async {
    await pumpApp(tester);
    await tester.pump(const Duration(milliseconds: 200));
    await tester.tap(find.byType(SplashIntro));
    await tester.pump(); // straight to the tear
    await tester.pump(const Duration(milliseconds: 500)); // …done long before the card would have been
    await tester.pump();
    expect(find.byType(SplashIntro), findsNothing);
  });

  testWidgets('reduced motion: the finished card, briefly, then gone', (tester) async {
    await pumpApp(tester, reducedMotion: true);
    await tester.pump();
    expect(find.text('AN FDCP CINEMATHEQUE CENTRE'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 850)); // held, then a plain fade
    await tester.pump();
    expect(find.byType(SplashIntro), findsNothing);
  });

  testWidgets('it starts exactly where the Android splash leaves the mark: icon-sized, centred', (tester) async {
    await pumpApp(tester);
    final mark = tester.getRect(find.descendant(of: find.byType(SplashIntro), matching: find.byType(CcdMark)).first);
    expect(mark.center, const Offset(412 / 2, 915 / 2));
    expect(mark.width, closeTo(SplashIntro.markStart, 0.01));

    // …and is brought forward to hero size before the ticket arrives.
    await tester.pump(const Duration(milliseconds: 650));
    final hero = tester.getRect(find.descendant(of: find.byType(SplashIntro), matching: find.byType(CcdMark)).first);
    expect(hero.width, closeTo(SplashIntro.markHero, 1));
    await tester.pumpAndSettle();
  });
}
