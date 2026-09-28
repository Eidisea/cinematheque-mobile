import 'package:ccd_mobile/customer/screens/about_screen.dart';
import 'package:ccd_mobile/customer/theme/customer_theme.dart';
import 'package:ccd_mobile/customer/widgets/scroll_motion.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpAbout(WidgetTester tester, {bool reducedMotion = false}) async {
  tester.view.physicalSize = const Size(412, 915);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildCustomerTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: const Size(412, 915), disableAnimations: reducedMotion),
      child: const AboutScreen(),
    ),
  ));
  await tester.pumpAndSettle();
}

/// The opacity actually applied to [finder]: the product of its Opacity ancestors.
double shownOpacity(WidgetTester tester, Finder finder) => tester
    .widgetList<Opacity>(find.ancestor(of: finder, matching: find.byType(Opacity)))
    .fold(1.0, (value, o) => value * o.opacity);

final page = find.byType(Scrollable).first;
final fdcpEra = find.text('2002–PRESENT');

void main() {
  group('ViewportPos', () {
    test('progress rises from 0 to 1 as the top travels from `from` to `to`', () {
      expect(const ViewportPos(1000, 1000).progress(0.9, 0.5), 0);
      expect(const ViewportPos(700, 1000).progress(0.9, 0.5), closeTo(0.5, 1e-9));
      expect(const ViewportPos(100, 1000).progress(0.9, 0.5), 1);
      expect(ViewportPos.settled.progress(0.9, 0.5), 1);
    });

    test('lineAt is how far down the widget the reading line reaches', () {
      expect(const ViewportPos(400, 1000).lineAt(0.62), closeTo(220, 1e-9));
      expect(ViewportPos.settled.lineAt(0.62), double.infinity);
    });
  });

  testWidgets('an era ahead stays quiet, settles once scrolled up to the reading line, and reverses', (tester) async {
    await pumpAbout(tester);

    // scrollUntilVisible ends with the era at the top of the screen: read, fully shown.
    await tester.scrollUntilVisible(fdcpEra, 100, scrollable: page);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, fdcpEra), closeTo(1, 1e-6));

    // Pushed back down to the bottom of the screen: still ahead of the reader — quiet.
    await tester.drag(page, const Offset(0, 850));
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, fdcpEra), lessThan(0.5));

    // Up again: settled again.
    await tester.drag(page, const Offset(0, -850));
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, fdcpEra), closeTo(1, 1e-6));
  });

  testWidgets("while reading an era, its name is pinned under the status bar", (tester) async {
    await pumpAbout(tester);
    await tester.scrollUntilVisible(find.text('Created to replace the Film Development Foundation. The Cinema Evaluation Board '
        'replaced the Film Ratings Board, grading films submitted to FDCP under the Cinema Evaluation System.'), 100, scrollable: page);
    await tester.drag(page, const Offset(0, -300));
    await tester.pumpAndSettle();
    // The strip repeats the era's name in one line (the era's own heading has scrolled away).
    expect(find.text('FILM DEVELOPMENT COUNCIL OF THE PHILIPPINES'), findsWidgets);
    expect(find.text('2002–PRESENT'), findsWidgets);
  });

  testWidgets('reduced motion: everything is shown settled and nothing is pinned', (tester) async {
    await pumpAbout(tester, reducedMotion: true);
    await tester.scrollUntilVisible(fdcpEra, 100, scrollable: page);
    await tester.drag(page, const Offset(0, 850)); // ahead of the reader, yet not dimmed
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, fdcpEra), 1);
    await tester.scrollUntilVisible(find.text('ACROSS THE COUNTRY'), 100, scrollable: page);
    await tester.pumpAndSettle();
    expect(shownOpacity(tester, find.text('ACROSS THE COUNTRY')), 1);
    expect(shownOpacity(tester, find.text('DAVAO')), 1);
  });
}
