import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart';

/// Development only: `--dart-define=USE_EMULATORS=true` sends all Firestore and Auth
/// traffic to the LOCAL Firebase emulators instead of the real servers. Normal builds
/// never set it.
///
/// The project ID stays the real one (Android reads it from google-services.json and
/// cannot override it), so start the emulators with `--project cinematheque-48a54`.
/// Data still never leaves this computer: every request goes to [emulatorHost].
/// Android emulator: run `adb reverse tcp:8080 tcp:8080` and `adb reverse tcp:9099 tcp:9099`
/// so the phone's 127.0.0.1 reaches this computer.
const useEmulators = bool.fromEnvironment('USE_EMULATORS');
const emulatorHost = String.fromEnvironment('EMULATOR_HOST', defaultValue: '127.0.0.1');

/// Result of starting Firebase. Both apps start even if Firebase fails,
/// so the problem can be shown on screen instead of a blank/crashed app.
class FirebaseStartup {
  const FirebaseStartup.ready() : error = null;
  const FirebaseStartup.failed(this.error);

  final String? error;

  bool get isReady => error == null;
}

/// Called once from main_customer.dart and main_staff.dart.
Future<FirebaseStartup> startFirebase() async {
  try {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    if (useEmulators) {
      await FirebaseAuth.instance.useAuthEmulator(emulatorHost, 9099);
      if (kIsWeb) {
        // A saved emulator login would be "restored" against the REAL Google servers on
        // the next page load, before the emulator switch applies. Not saving it keeps
        // emulator mode fully local. (Emulator mode only: reloading signs you out.)
        await FirebaseAuth.instance.setPersistence(Persistence.NONE);
      }
      FirebaseFirestore.instance.useFirestoreEmulator(emulatorHost, 8080);
      debugPrint('Using LOCAL Firebase emulators at $emulatorHost');
    }
    return const FirebaseStartup.ready();
  } catch (e) {
    debugPrint('Firebase failed to start: $e');
    return FirebaseStartup.failed(e.toString());
  }
}
