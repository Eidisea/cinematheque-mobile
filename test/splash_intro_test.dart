import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/customer/customer_app.dart';
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
  testWidgets('the title card plays once over Screenings, then leaves', (tester) async {
    await pumpApp(tester);
    expect(find.byType(SplashIntro), findsOneWidget);

    // Mid-way: the name is being revealed over the page that is already loading beneath.
    await tester.pump(const Duration(milliseconds: 900));
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
    await tester.pump(); // the fade starts
    await tester.pump(const Duration(milliseconds: 400)); // …and ends, long before the card would have
    await tester.pump();
    expect(find.byType(SplashIntro), findsNothing);
  });

  testWidgets('reduced motion: the finished card, briefly, then gone', (tester) async {
    await pumpApp(tester, reducedMotion: true);
    await tester.pump();
    expect(find.text('AN FDCP CINEMATHEQUE CENTRE'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 550)); // held
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // quick fade
    await tester.pump();
    expect(find.byType(SplashIntro), findsNothing);
  });

  testWidgets('it starts exactly where the Android splash leaves the mark: 96dp wide, centred', (tester) async {
    await pumpApp(tester);
    final box = tester.getRect(find.descendant(of: find.byType(SplashIntro), matching: find.byType(Transform)).first);
    expect(box.center, const Offset(412 / 2, 915 / 2));
    expect(box.width * 36 / 40, closeTo(96, 0.01));
    await tester.pumpAndSettle();
  });
}
