import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../api/booking_api.dart';
import '../core/app_config.dart';
import '../core/clock.dart';
import '../core/firebase_bootstrap.dart';
import '../data/repositories/booking_view_repository.dart';
import '../data/repositories/catalog_repository.dart';
import 'customer_router.dart';
import 'customer_services.dart';
import 'storage/saved_bookings.dart';
import 'theme/customer_theme.dart';
import 'widgets/splash_intro.dart';
import 'widgets/state_views.dart';

/// Customer app (Android). No login — customers never have accounts.
class CustomerApp extends StatefulWidget {
  const CustomerApp({
    super.key,
    required this.startup,
    this.catalog,
    this.bookingViews,
    this.savedBookings,
    this.bookingApi,
    this.clock = const Clock(),
    this.showIntro = true,
  });

  final FirebaseStartup startup;

  /// Tests pass fakes; the real app reads Firestore and calls the server.
  final CatalogRepository? catalog;
  final BookingViewRepository? bookingViews;
  final SavedBookingsStore? savedBookings;
  final BookingApi? bookingApi;
  final Clock clock;

  /// Plays the opening title card over the first screen (off in most widget tests).
  final bool showIntro;

  @override
  State<CustomerApp> createState() => _CustomerAppState();
}

class _CustomerAppState extends State<CustomerApp> {
  late final GoRouter _router = buildCustomerRouter();
  late bool _intro = widget.showIntro; // the opening title card, once per cold start
  CatalogRepository? _catalog;
  late final BookingViewRepository? _bookingViews;
  late final SavedBookingsStore _savedBookings = widget.savedBookings ?? MemorySavedBookingsStore();
  late final BookingApi? _bookingApi =
      widget.bookingApi ?? (AppConfig.hasApi ? HttpBookingApi(AppConfig.apiBaseUrl) : null);

  @override
  void initState() {
    super.initState();
    final firebaseReady = widget.startup.isReady;
    if (widget.catalog != null || firebaseReady) {
      _catalog = widget.catalog ?? FirestoreCatalogRepository();
    }
    _bookingViews = widget.bookingViews ?? (firebaseReady ? FirestoreBookingViewRepository() : null);
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = _catalog;
    final bookingViews = _bookingViews;
    if (catalog == null || bookingViews == null) {
      return MaterialApp(
        title: 'Cinematheque Centre Davao',
        debugShowCheckedModeBanner: false,
        theme: buildCustomerTheme(),
        home: Scaffold(
          body: MessageView(
            icon: Icons.cloud_off_outlined,
            title: "The app couldn't start",
            message: 'Please check your internet connection and open the app again.\n\n(${widget.startup.error})',
          ),
        ),
      );
    }

    return CustomerServices(
      catalog: catalog,
      clock: widget.clock,
      bookingViews: bookingViews,
      savedBookings: _savedBookings,
      bookingApi: _bookingApi,
      child: MaterialApp.router(
        title: 'Cinematheque Centre Davao',
        debugShowCheckedModeBanner: false,
        theme: buildCustomerTheme(),
        themeMode: ThemeMode.light,
        routerConfig: _router,
        // Light app → dark status-bar icons, also on screens without an app bar.
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.dark.copyWith(statusBarColor: Colors.transparent),
          child: Stack(
            children: [
              child!,
              if (_intro) Positioned.fill(child: SplashIntro(onDone: () => setState(() => _intro = false))),
            ],
          ),
        ),
      ),
    );
  }
}
