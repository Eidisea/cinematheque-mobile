import 'package:go_router/go_router.dart';

import 'screens/about_screen.dart';
import 'screens/booking_screen.dart';
import 'screens/find_my_booking_screen.dart';
import 'screens/movie_details_screen.dart';
import 'screens/reservation_details_screen.dart';
import 'screens/screening_details_screen.dart';
import 'screens/screenings_screen.dart';
import 'screens/seat_selection_screen.dart';
import 'shell/customer_shell.dart';

/// Customer app pages. The three tabs (Find my booking · Screenings · About) live in the
/// bottom-navigation shell, Screenings in the middle and opened first; detail pages open
/// full-screen on top of it (with a back button).
GoRouter buildCustomerRouter() {
  return GoRouter(
    initialLocation: '/screenings',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => CustomerShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [GoRoute(path: '/find', builder: (context, state) => const FindMyBookingScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/screenings', builder: (context, state) => const ScreeningsScreen())]),
          StatefulShellBranch(routes: [GoRoute(path: '/about', builder: (context, state) => const AboutScreen())]),
        ],
      ),
      // Older paths (before the three tabs were reorganised).
      GoRoute(path: '/bookings', redirect: (context, state) => '/find'),
      GoRoute(path: '/booking/find', redirect: (context, state) => '/find'),
      GoRoute(path: '/more', redirect: (context, state) => '/about'),
      GoRoute(
        path: '/screenings/:id',
        builder: (context, state) => ScreeningDetailsScreen(screeningId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/screenings/:id/seats',
        builder: (context, state) => SeatSelectionScreen(screeningId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/screenings/:id/details',
        // The chosen seats travel with the navigation. Without them (e.g. restored after
        // the app was closed) the customer goes back to the seat map.
        redirect: (context, state) => state.extra is List<String> ? null : '/screenings/${state.pathParameters['id']}/seats',
        builder: (context, state) => ReservationDetailsScreen(
          screeningId: state.pathParameters['id']!,
          seats: state.extra! as List<String>,
        ),
      ),
      GoRoute(
        path: '/booking/:key',
        builder: (context, state) => BookingScreen(accessKey: state.pathParameters['key']!),
      ),
      GoRoute(
        path: '/movies/:id',
        builder: (context, state) => MovieDetailsScreen(movieId: state.pathParameters['id']!),
      ),
    ],
  );
}
