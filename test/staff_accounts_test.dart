import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/data/models/staff_member.dart';
import 'package:ccd_mobile/staff/auth/staff_session.dart';
import 'package:ccd_mobile/staff/data/staff_api.dart';
import 'package:ccd_mobile/staff/staff_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_staff_repository.dart';
import 'staff_auth_test.dart' show FakeStaffSession;
import 'staff_dashboard_test.dart' as d;
import 'staff_reservations_test.dart' show FakeStaffApi;

const ben = StaffMember(uid: 'u2', firstName: 'Ben', lastName: 'Santos', email: 'ben@ccd.test', position: StaffPosition.avt, isActive: true);
const cara = StaffMember(uid: 'u3', firstName: 'Cara', lastName: 'Lim', email: 'cara@ccd.test', position: StaffPosition.pdo, isActive: false);

Future<FakeStaffApi> pumpAccounts(WidgetTester tester) async {
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
    data: FakeStaffRepository(staff: const [FakeStaffSession.member, ben, cara]),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Staff accounts').first);
  await tester.pumpAndSettle();
  return api;
}

void main() {
  testWidgets('everyone listed with position and status; nobody can deactivate themselves', (tester) async {
    final api = await pumpAccounts(tester);
    expect(find.text('Ana Reyes  you', findRichText: true), findsOneWidget, reason: 'the signed-in staff member');
    expect(find.text('Active'), findsNWidgets(2));
    expect(find.text('Inactive'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Deactivate'), findsOneWidget, reason: 'Ben only, not "you"');

    await tester.tap(find.widgetWithText(OutlinedButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(find.text('Deactivate account?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Deactivate'));
    await tester.pumpAndSettle();
    expect(api.calls, ['deactivate u2']);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Activate'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'activate u3');
  });

  testWidgets('new account: checks the form, then asks the server; server field errors show on the fields', (tester) async {
    final api = await pumpAccounts(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'New staff account'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Enter a first name.'), findsOneWidget);
    expect(find.text('Enter a password of at least 8 characters.'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Dana');
    await tester.enterText(fields.at(2), 'Cruz');
    await tester.enterText(fields.at(3), 'dana@ccd.test');
    await tester.tap(find.text('PDO'));
    await tester.enterText(fields.at(4), 'long-enough-1');
    await tester.enterText(fields.at(5), 'different');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('The passwords don’t match.'), findsOneWidget);

    await tester.enterText(fields.at(5), 'long-enough-1');
    api.failWith = const StaffApiException('email_exists', fields: {'email': 'Another account already uses this email.'});
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(find.text('Another account already uses this email.'), findsOneWidget);

    api.failWith = null;
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();
    expect(api.calls.last, 'createStaff dana@ccd.test PDO');
    expect(find.textContaining('Account created'), findsOneWidget);
  });

  testWidgets('edit: details filled in; a blank password keeps the current one', (tester) async {
    final api = await pumpAccounts(tester);
    await tester.tap(find.text('Ben Santos', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('Edit staff account'), findsOneWidget);
    await tester.enterText(find.byType(TextField).at(2), 'Santos-Cruz');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();
    expect(api.calls, ['updateStaff u2 Santos-Cruz password:kept']);
  });
}
