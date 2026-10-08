import 'dart:async';

import 'package:ccd_mobile/customer/widgets/spotlight_banner.dart';

/// Runs before every test file: the Screenings banner's slideshow would keep the screen
/// from ever settling, and the banner repeats titles that list tests look for — so it is
/// off here; test/spotlight_banner_test.dart turns it back on.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  SpotlightBanner.autoplay = false;
  SpotlightBanner.enabled = false;
  await testMain();
}
