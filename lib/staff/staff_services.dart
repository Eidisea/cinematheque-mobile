import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import 'data/staff_api.dart';
import 'data/staff_repository.dart';

/// Makes the staff data sources and the clock available to every staff page
/// (`StaffServices.of(context).data`). Tests put fakes here.
class StaffServices extends InheritedWidget {
  const StaffServices({super.key, required this.data, required this.clock, this.api, required super.child});

  final StaffRepository data;
  final Clock clock;

  /// Server actions (approve, cancel, resend). null when this build has no API address.
  final StaffApi? api;

  static StaffServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<StaffServices>();
    assert(services != null, 'StaffServices missing above this widget');
    return services!;
  }

  @override
  bool updateShouldNotify(StaffServices oldWidget) => data != oldWidget.data || clock != oldWidget.clock || api != oldWidget.api;
}
