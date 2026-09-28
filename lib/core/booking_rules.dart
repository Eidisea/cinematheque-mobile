/// Business rules shared by the apps. The server enforces the same values
/// (server/lib/booking-rules.js) — the app only uses them to guide the customer.
abstract final class BookingRules {
  /// One reservation may contain at most 10 seats.
  static const maxSeatsPerReservation = 10;

  /// A paid reservation holds its seats for 15 minutes while the customer pays.
  static const paymentWindow = Duration(minutes: 15);
}
