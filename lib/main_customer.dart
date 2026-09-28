import 'package:flutter/material.dart';

import 'core/firebase_bootstrap.dart';
import 'customer/customer_app.dart';
import 'customer/storage/saved_bookings.dart';

/// Customer app entry point (Android).
///   flutter run -t lib/main_customer.dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final startup = await startFirebase();
  final savedBookings = await PrefsSavedBookingsStore.load(); // the "On this phone" list in Find my booking
  runApp(CustomerApp(startup: startup, savedBookings: savedBookings));
}
