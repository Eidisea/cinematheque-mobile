import 'package:flutter/widgets.dart';

import '../api/booking_api.dart';
import '../core/clock.dart';
import '../data/repositories/booking_view_repository.dart';
import '../data/repositories/catalog_repository.dart';
import 'storage/saved_bookings.dart';

/// Makes the data sources, the booking API and the clock available to every customer
/// screen (`CustomerServices.of(context).catalog`). Tests put fakes here.
class CustomerServices extends InheritedWidget {
  const CustomerServices({
    super.key,
    required this.catalog,
    required this.clock,
    required this.bookingViews,
    required this.savedBookings,
    required this.bookingApi,
    required super.child,
  });

  final CatalogRepository catalog;
  final Clock clock;
  final BookingViewRepository bookingViews;
  final SavedBookingsStore savedBookings;

  /// null when no API address was configured for this build (booking unavailable).
  final BookingApi? bookingApi;

  static CustomerServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<CustomerServices>();
    assert(services != null, 'CustomerServices missing above this widget');
    return services!;
  }

  @override
  bool updateShouldNotify(CustomerServices oldWidget) =>
      catalog != oldWidget.catalog ||
      clock != oldWidget.clock ||
      bookingViews != oldWidget.bookingViews ||
      savedBookings != oldWidget.savedBookings ||
      bookingApi != oldWidget.bookingApi;
}
