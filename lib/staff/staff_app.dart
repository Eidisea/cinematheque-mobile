import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/firebase_bootstrap.dart';
import 'auth/staff_session.dart';
import 'staff_router.dart';
import 'theme/staff_theme.dart';
import '../core/clock.dart';
import 'data/dashboard_repository.dart';
import 'staff_services.dart';

/// Staff app (Flutter Web). Staff sign in with Firebase Authentication and must have an
/// active staff record; every page except /login is protected by the router.
class StaffApp extends StatefulWidget {
  const StaffApp({super.key, required this.startup, this.session, this.dashboard, this.clock = const Clock()});

  final FirebaseStartup startup;

  /// Tests pass fakes; the real app signs in with Firebase and reads Firestore.
  final StaffSession? session;
  final DashboardRepository? dashboard;
  final Clock clock;

  @override
  State<StaffApp> createState() => _StaffAppState();
}

class _StaffAppState extends State<StaffApp> {
  StaffSession? _session;
  GoRouter? _router;
  DashboardRepository? _dashboard;

  @override
  void initState() {
    super.initState();
    if (widget.startup.isReady || widget.session != null) {
      _session = widget.session ?? FirebaseStaffSession();
      _router = buildStaffRouter(_session!);
      _dashboard = widget.dashboard ?? FirestoreDashboardRepository();
    }
  }

  @override
  void dispose() {
    _router?.dispose();
    if (widget.session == null) _session?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = _router;
    if (router == null) {
      return MaterialApp(
        title: 'CCD Staff',
        debugShowCheckedModeBanner: false,
        theme: buildStaffTheme(),
        home: _StartupError(message: widget.startup.error ?? 'Unknown error'),
      );
    }

    return StaffServices(
      dashboard: _dashboard!,
      clock: widget.clock,
      child: MaterialApp.router(
        title: 'CCD Staff',
        debugShowCheckedModeBanner: false,
        theme: buildStaffTheme(),
        themeMode: ThemeMode.light,
        routerConfig: router,
      ),
    );
  }
}

class _StartupError extends StatelessWidget {
  const _StartupError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 40),
              const SizedBox(height: 12),
              Text('The staff app could not connect to Firebase.', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
