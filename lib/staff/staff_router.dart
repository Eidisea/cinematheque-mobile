import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'auth/staff_session.dart';
import 'navigation.dart';
import 'screens/attendance_screen.dart';
import 'screens/dashboard_screen.dart';
import 'screens/film_form_screen.dart';
import 'screens/films_screen.dart';
import 'screens/loading_screen.dart';
import 'screens/login_screen.dart';
import 'screens/not_found_screen.dart';
import 'screens/placeholder_screen.dart';
import 'screens/reservation_screen.dart';
import 'screens/reservations_screen.dart';
import 'screens/screening_form_screen.dart';
import 'screens/screening_screen.dart';
import 'screens/staff_account_form_screen.dart';
import 'screens/staff_accounts_screen.dart';
import 'shell/staff_shell.dart';

const loginPath = '/login';
const loadingPath = '/loading';

/// Decides where a staff user may go. Returns a new location, or null to stay.
///
/// - Not signed in → every page sends you to /login (remembering where you were going).
/// - Still checking (Firebase restoring the login / checking staff/{uid}) → /loading.
/// - Signed in as active staff → /login and /loading send you on to the page you wanted.
String? staffRedirect(StaffSessionStatus status, Uri uri) {
  final path = uri.path;
  final from = uri.queryParameters['from'];

  switch (status) {
    case StaffSessionStatus.starting:
    case StaffSessionStatus.verifying:
      if (path == loadingPath) return null;
      return _withFrom(loadingPath, path == loginPath ? from : uri.toString());
    case StaffSessionStatus.signedOut:
      if (path == loginPath) return null;
      return _withFrom(loginPath, path == loadingPath ? from : uri.toString());
    case StaffSessionStatus.signedIn:
      if (path == loginPath || path == loadingPath) return _safeReturnPath(from) ?? '/';
      return null;
  }
}

String _withFrom(String target, String? from) {
  final safe = _safeReturnPath(from);
  return safe == null || safe == '/' ? target : '$target?from=${Uri.encodeQueryComponent(safe)}';
}

/// Only same-site paths are accepted as a return location (no "//evil.com", no loops).
String? _safeReturnPath(String? from) {
  if (from == null || !from.startsWith('/') || from.startsWith('//')) return null;
  final path = Uri.tryParse(from)?.path;
  if (path == null || path == loginPath || path == loadingPath) return null;
  return from;
}

GoRouter buildStaffRouter(StaffSession session) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: session,
    redirect: (context, state) => staffRedirect(session.status, state.uri),
    errorBuilder: (context, state) => const NotFoundScreen(),
    routes: [
      GoRoute(path: loadingPath, builder: (context, state) => const LoadingScreen()),
      GoRoute(
        path: loginPath,
        builder: (context, state) => LoginScreen(session: session),
      ),
      ShellRoute(
        builder: (context, state, child) => StaffShell(session: session, location: state.uri.path, child: child),
        routes: [
          for (final item in allStaffNavItems)
            GoRoute(
              path: item.path,
              pageBuilder: (context, state) => NoTransitionPage(
                key: ValueKey(item.path),
                child: switch (item.path) {
                  '/' => DashboardScreen(session: session),
                  '/reservations' => ReservationsScreen(initialScreeningId: state.uri.queryParameters['screening']),
                  '/attendance' => const AttendanceScreen(),
                  '/settings/films' => const FilmsScreen(),
                  '/settings/staff' => StaffAccountsScreen(myUid: session.staff?.uid),
                  _ => PlaceholderScreen(item: item),
                },
              ),
              routes: [
                if (item.path == '/attendance') ...[
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) => NoTransitionPage(
                      key: const ValueKey('screening-new'),
                      child: ScreeningFormScreen(staffUid: session.staff?.uid, initialMovieId: state.uri.queryParameters['movie']),
                    ),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => NoTransitionPage(
                      key: ValueKey('screening-${state.pathParameters['id']}'),
                      child: ScreeningScreen(screeningId: state.pathParameters['id']!),
                    ),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        pageBuilder: (context, state) => NoTransitionPage(
                          key: ValueKey('screening-edit-${state.pathParameters['id']}'),
                          child: ScreeningFormScreen(screeningId: state.pathParameters['id']!, staffUid: session.staff?.uid),
                        ),
                      ),
                    ],
                  ),
                ],
                if (item.path == '/settings/films') ...[
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(key: ValueKey('film-new'), child: FilmFormScreen()),
                  ),
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => NoTransitionPage(
                      key: ValueKey('film-${state.pathParameters['id']}'),
                      child: FilmFormScreen(movieId: state.pathParameters['id']!),
                    ),
                  ),
                ],
                if (item.path == '/settings/staff') ...[
                  GoRoute(
                    path: 'new',
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(key: ValueKey('staff-new'), child: StaffAccountFormScreen()),
                  ),
                  GoRoute(
                    path: ':uid',
                    pageBuilder: (context, state) => NoTransitionPage(
                      key: ValueKey('staff-${state.pathParameters['uid']}'),
                      child: StaffAccountFormScreen(uid: state.pathParameters['uid']!),
                    ),
                  ),
                ],
                if (item.path == '/reservations')
                  GoRoute(
                    path: ':id',
                    pageBuilder: (context, state) => NoTransitionPage(
                      key: ValueKey('reservation-${state.pathParameters['id']}'),
                      child: ReservationScreen(reservationId: state.pathParameters['id']!),
                    ),
                  ),
              ],
            ),
        ],
      ),
    ],
  );
}
