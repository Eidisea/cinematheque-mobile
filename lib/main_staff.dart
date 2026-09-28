import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'core/firebase_bootstrap.dart';
import 'staff/staff_app.dart';

/// Staff app entry point (Flutter Web).
///   flutter run -d chrome -t lib/main_staff.dart
///   flutter build web -t lib/main_staff.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  usePathUrlStrategy(); // clean URLs: /reservations instead of /#/reservations
  final startup = await startFirebase();
  runApp(StaffApp(startup: startup));
}
