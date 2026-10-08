import 'package:flutter/widgets.dart';

import '../core/clock.dart';
import 'data/dashboard_repository.dart';

/// Makes the staff data sources and the clock available to every staff page
/// (`StaffServices.of(context).dashboard`). Tests put fakes here.
class StaffServices extends InheritedWidget {
  const StaffServices({super.key, required this.dashboard, required this.clock, required super.child});

  final DashboardRepository dashboard;
  final Clock clock;

  static StaffServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<StaffServices>();
    assert(services != null, 'StaffServices missing above this widget');
    return services!;
  }

  @override
  bool updateShouldNotify(StaffServices oldWidget) => dashboard != oldWidget.dashboard || clock != oldWidget.clock;
}
