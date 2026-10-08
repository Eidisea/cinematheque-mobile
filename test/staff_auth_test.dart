import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/data/models/staff_member.dart';
import 'package:ccd_mobile/staff/auth/staff_session.dart';
import 'package:ccd_mobile/staff/staff_app.dart';
import 'package:ccd_mobile/staff/staff_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_staff_repository.dart';

/// A session we control directly — no Firebase involved.
class FakeStaffSession extends StaffSession {
  StaffSessionStatus _status = StaffSessionStatus.signedOut;
  StaffMember? _staff;
  String? _notice;
  String? rejectWith; // makes the next signIn fail with this message
  int signOutCalls = 0;

  static const member = StaffMember(
    uid: 'u1',
    firstName: 'Ana',
    lastName: 'Reyes',
    email: 'ana@example.test',
    position: StaffPosition.pdo,
    isActive: true,
  );

  @override
  StaffSessionStatus get status => _status;
  @override
  StaffMember? get staff => _staff;
  @override
  String? get notice => _notice;

  void setState(StaffSessionStatus status, {StaffMember? staff, String? notice}) {
    _status = status;
    _staff = staff;
    _notice = notice;
    notifyListeners();
  }

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (rejectWith != null) throw StaffSignInException(rejectWith!);
    setState(StaffSessionStatus.signedIn, staff: member);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    setState(StaffSessionStatus.signedOut);
  }
}

void main() {
  group('staffRedirect (route protection rules)', () {
    Uri u(String s) => Uri.parse(s);

    test('signed-out users are sent to /login, remembering where they were going', () {
      expect(staffRedirect(StaffSessionStatus.signedOut, u('/')), '/login');
      expect(staffRedirect(StaffSessionStatus.signedOut, u('/reservations')), '/login?from=%2Freservations');
      expect(staffRedirect(StaffSessionStatus.signedOut, u('/settings/staff')), '/login?from=%2Fsettings%2Fstaff');
      expect(staffRedirect(StaffSessionStatus.signedOut, u('/login')), isNull);
    });

    test('while checking access, pages wait on /loading', () {
      expect(staffRedirect(StaffSessionStatus.starting, u('/reports')), '/loading?from=%2Freports');
      expect(staffRedirect(StaffSessionStatus.verifying, u('/login?from=%2Freports')), '/loading?from=%2Freports');
      expect(staffRedirect(StaffSessionStatus.verifying, u('/loading')), isNull);
    });

    test('signed-in staff skip /login and return to the page they wanted', () {
      expect(staffRedirect(StaffSessionStatus.signedIn, u('/login')), '/');
      expect(staffRedirect(StaffSessionStatus.signedIn, u('/login?from=%2Freservations')), '/reservations');
      expect(staffRedirect(StaffSessionStatus.signedIn, u('/loading?from=%2Freports')), '/reports');
      expect(staffRedirect(StaffSessionStatus.signedIn, u('/attendance')), isNull);
    });

    test('return locations must stay on this site', () {
      expect(staffRedirect(StaffSessionStatus.signedIn, u('/login?from=https%3A%2F%2Fevil.example')), '/');
      expect(staffRedirect(StaffSessionStatus.signedIn, u('/login?from=%2F%2Fevil.example')), '/');
      expect(staffRedirect(StaffSessionStatus.signedIn, u('/login?from=%2Flogin')), '/');
    });
  });

  group('Staff app screens', () {
    const ready = FirebaseStartup.ready();

    Future<FakeStaffSession> pumpApp(WidgetTester tester, {Size size = const Size(1280, 800)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final session = FakeStaffSession();
      await tester.pumpWidget(StaffApp(startup: ready, session: session, data: FakeStaffRepository()));
      await tester.pumpAndSettle();
      return session;
    }

    testWidgets('signed out → login screen; staff pages are not shown', (tester) async {
      await pumpApp(tester);
      expect(find.text('Staff sign in'), findsOneWidget);
      expect(find.text('Operations'), findsNothing);
    });

    testWidgets('empty form shows validation messages', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Enter your email.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
    });

    testWidgets('wrong credentials show a readable error', (tester) async {
      final session = await pumpApp(tester);
      session.rejectWith = 'Incorrect email or password.';
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ana@example.test');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'wrong');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();
      expect(find.text('Incorrect email or password.'), findsOneWidget);
      expect(find.text('Staff sign in'), findsOneWidget);
    });

    testWidgets('a deactivated / non-staff account sees why it was signed out', (tester) async {
      final session = await pumpApp(tester);
      session.setState(StaffSessionStatus.signedOut, notice: 'This staff account has been deactivated.');
      await tester.pumpAndSettle();
      expect(find.text('This staff account has been deactivated.'), findsOneWidget);
    });

    testWidgets('sign in → dashboard with grouped navigation; sign out → login', (tester) async {
      final session = await pumpApp(tester);
      await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ana@example.test');
      await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'secret');
      await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
      await tester.pumpAndSettle();

      expect(find.text('NEXT 7 DAYS'), findsOneWidget, reason: 'the dashboard');
      for (final label in ['OPERATIONS', 'INSIGHTS', 'SETTINGS', 'Attendance', 'Reservations', 'Reports', 'Film catalog', 'Staff accounts']) {
        expect(find.text(label), findsWidgets, reason: label);
      }

      await tester.tap(find.text('Reservations'));
      await tester.pumpAndSettle();
      expect(find.text('No reservations'), findsOneWidget, reason: 'the Reservations page, empty');

      await tester.tap(find.byTooltip('Account'));
      await tester.pumpAndSettle();
      expect(find.text('PDO · ana@example.test'), findsOneWidget);
      await tester.tap(find.text('Sign out'));
      await tester.pumpAndSettle();
      expect(session.signOutCalls, 1);
      expect(find.text('Staff sign in'), findsOneWidget);
    });

    testWidgets('a session that goes inactive mid-work is sent back to login', (tester) async {
      final session = await pumpApp(tester);
      session.setState(StaffSessionStatus.signedIn, staff: FakeStaffSession.member);
      await tester.pumpAndSettle();
      expect(find.text('NEXT 7 DAYS'), findsOneWidget, reason: 'the dashboard');

      session.setState(StaffSessionStatus.signedOut, notice: 'This staff account has been deactivated.');
      await tester.pumpAndSettle();
      expect(find.text('Staff sign in'), findsOneWidget);
      expect(find.text('This staff account has been deactivated.'), findsOneWidget);
    });

    testWidgets('narrow screens use a drawer instead of a sidebar', (tester) async {
      final session = await pumpApp(tester, size: const Size(390, 800));
      session.setState(StaffSessionStatus.signedIn, staff: FakeStaffSession.member);
      await tester.pumpAndSettle();
      expect(find.text('OPERATIONS'), findsNothing);
      await tester.tap(find.byTooltip('Open navigation'));
      await tester.pumpAndSettle();
      expect(find.text('OPERATIONS'), findsOneWidget);
      await tester.tap(find.descendant(of: find.byType(Drawer), matching: find.text('Attendance')));
      await tester.pumpAndSettle();
      expect(find.text('No upcoming screenings'), findsOneWidget, reason: 'the Attendance page, empty');
    });
  });
}
