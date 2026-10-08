import 'dart:typed_data';

import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/core/firebase_bootstrap.dart';
import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/staff/auth/staff_session.dart';
import 'package:ccd_mobile/staff/screens/film_form_screen.dart';
import 'package:ccd_mobile/staff/staff_app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_staff_repository.dart';
import 'staff_auth_test.dart' show FakeStaffSession;
import 'staff_dashboard_test.dart' as d;
import 'staff_reservations_test.dart' show FakeStaffApi;

const oldPoster = Poster(url: 'https://res.cloudinary.com/tjdy4j9n/image/upload/v1/ccd/posters/old', publicId: 'ccd/posters/old');
const himala = Movie(
  id: 'himala',
  title: 'Himala',
  runtimeMinutes: 124,
  releaseYear: 1982,
  rating: 'PG',
  genres: ['Drama'],
  directors: ['Ishmael Bernal'],
  poster: oldPoster,
);
const unused = Movie(id: 'unused', title: 'Unused Film');

class Harness {
  Harness(this.repo, this.api);
  final FakeStaffRepository repo;
  final FakeStaffApi api;
}

Future<Harness> pumpFilms(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final screening = d.screening('h', 'Himala', d.manila(9, 18));
  final repo = FakeStaffRepository(
    screenings: [Screening(id: 'h', eventTitle: 'Himala', movieId: 'himala', startAt: screening.startAt, endAt: screening.endAt, type: ScreeningType.free, capacity: 120)],
    movies: const [himala, unused],
  );
  final api = FakeStaffApi();
  final session = FakeStaffSession()..setState(StaffSessionStatus.signedIn, staff: FakeStaffSession.member);
  await tester.pumpWidget(StaffApp(startup: const FirebaseStartup.ready(), session: session, clock: FixedClock(d.now), api: api, data: repo));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Film catalog').first);
  await tester.pumpAndSettle();
  return Harness(repo, api);
}

void main() {
  setUp(() => FilmFormScreen.pickPoster = () async => (bytes: Uint8List.fromList([1, 2, 3]), name: 'new.jpg'));

  testWidgets('the catalog: one row per film with its details and screenings; Schedule preselects the film', (tester) async {
    await pumpFilms(tester);
    expect(find.text('2 films'), findsOneWidget);
    expect(find.text('Himala'), findsOneWidget);
    expect(find.text('124 min'), findsOneWidget);
    expect(find.text('Ishmael Bernal'), findsOneWidget);
    expect(find.text('1982'), findsOneWidget);
    expect(find.text('PG'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'bernal');
    await tester.pumpAndSettle();
    expect(find.text('Unused Film'), findsNothing);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Schedule'));
    await tester.pumpAndSettle();
    expect(find.text('New screening'), findsWidgets);
    expect(find.text('Himala (1982)'), findsOneWidget, reason: 'preselected');
  });

  testWidgets('add a film with a poster', (tester) async {
    final h = await pumpFilms(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Add film'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Add film').last);
    await tester.pumpAndSettle();
    expect(find.text('Enter the film title.'), findsOneWidget);

    final fields = find.byType(TextField);
    await tester.enterText(fields.at(0), 'Oro, Plata, Mata');
    await tester.enterText(fields.at(1), '1982');
    await tester.enterText(fields.at(2), '194');
    await tester.enterText(fields.at(3), 'Peque Gallaga');
    await tester.tap(find.text('Drama'));
    await tester.tap(find.widgetWithText(OutlinedButton, 'Upload poster'));
    await tester.pumpAndSettle();
    expect(h.api.calls, ['upload new.jpg']);
    expect(find.widgetWithText(OutlinedButton, 'Replace'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Add film').last);
    await tester.pumpAndSettle();
    final film = h.repo.movies.last;
    expect(film.title, 'Oro, Plata, Mata');
    expect(film.releaseYear, 1982);
    expect(film.runtimeMinutes, 194);
    expect(film.directors, ['Peque Gallaga']);
    expect(film.genres, ['Drama']);
    expect(film.poster?.publicId, 'ccd/posters/new.jpg');
    expect(find.text('Film added.'), findsOneWidget);
    expect(find.text('3 films'), findsOneWidget);
  });

  testWidgets('edit: replacing the poster deletes the old one after saving, and upcoming screenings are refreshed', (tester) async {
    final h = await pumpFilms(tester);
    await tester.tap(find.text('Himala'));
    await tester.pumpAndSettle();
    expect(find.text('Used by 1 screening, so it can’t be deleted.'), findsOneWidget);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Replace'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Himala (Restored)');
    await tester.tap(find.widgetWithText(FilledButton, 'Save changes'));
    await tester.pumpAndSettle();

    final film = h.repo.movies.firstWhere((m) => m.id == 'himala');
    expect(film.title, 'Himala (Restored)');
    expect(film.poster?.publicId, 'ccd/posters/new.jpg');
    expect(h.repo.refreshed, ['himala']);
    expect(h.api.calls, ['upload new.jpg', 'deletePoster ccd/posters/old']);
  });

  testWidgets('a film no screening uses can be deleted (after confirming)', (tester) async {
    final h = await pumpFilms(tester);
    await tester.tap(find.text('Unused Film'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, 'Delete film'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete film'));
    await tester.pumpAndSettle();
    expect(h.repo.movies.map((m) => m.id), ['himala']);
    expect(find.text('Deleted “Unused Film”.'), findsOneWidget);
  });
}
