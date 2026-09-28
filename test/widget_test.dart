import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/customer/customer_app.dart';
import 'package:ccd_mobile/staff/staff_app.dart';
import 'package:flutter_test/flutter_test.dart';

// Smoke tests: both apps build and show a Firebase failure on screen
// instead of crashing. (Real Firebase is not available in unit tests.)
void main() {
  const failed = FirebaseStartup.failed('not configured (test)');

  testWidgets('customer app starts', (tester) async {
    await tester.pumpWidget(const CustomerApp(startup: failed));
    expect(find.text("The app couldn't start"), findsOneWidget);
    expect(find.textContaining('not configured (test)'), findsOneWidget);
  });

  testWidgets('staff app starts', (tester) async {
    await tester.pumpWidget(const StaffApp(startup: failed));
    expect(find.text('The staff app could not connect to Firebase.'), findsOneWidget);
    expect(find.textContaining('not configured (test)'), findsOneWidget);
  });
}
