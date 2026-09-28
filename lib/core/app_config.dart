import 'firebase_bootstrap.dart';

/// Where the booking API (Vercel) lives.
///
/// Set at build time: `--dart-define=API_BASE_URL=https://YOUR-PROJECT.vercel.app`
/// In emulator mode it defaults to the local dev server (server/dev-server.js), which the
/// Android emulator reaches through `adb reverse tcp:3000 tcp:3000`.
abstract final class AppConfig {
  static const _configured = String.fromEnvironment('API_BASE_URL');

  static String get apiBaseUrl {
    if (_configured.isNotEmpty) return _configured;
    return useEmulators ? 'http://127.0.0.1:3000' : '';
  }

  static bool get hasApi => apiBaseUrl.isNotEmpty;
}
