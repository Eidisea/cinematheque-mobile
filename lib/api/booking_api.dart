import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// What the customer submits: seats, the booker, and one attendee per seat.
class ReservationRequest {
  const ReservationRequest({
    required this.screeningId,
    required this.seats,
    required this.booker,
    required this.attendees,
    this.bookerSeat,
  });

  final String screeningId;
  final List<String> seats;
  final String? bookerSeat;
  final Map<String, Object?> booker;
  final Map<String, Map<String, Object?>> attendees;

  Map<String, Object?> toJson() => {
        'screeningId': screeningId,
        'seats': seats,
        'bookerSeat': bookerSeat,
        'booker': booker,
        'attendees': attendees,
      };
}

class CreatedBooking {
  const CreatedBooking({
    required this.bookingReference,
    required this.accessKey,
    required this.requiresPayment,
    required this.totalCentavos,
    this.expiresAt,
  });

  final String bookingReference;
  final String accessKey;
  final bool requiresPayment;
  final int totalCentavos;
  final DateTime? expiresAt;
}

/// An error answer from the API, e.g. code "seats_taken" with the seats in [seats].
class ApiException implements Exception {
  const ApiException(this.code, {this.status, this.fields = const {}, this.seats = const []});

  final String code;
  final int? status;
  final Map<String, String> fields; // validation messages per field ("booker.email" → "…")
  final List<String> seats; // for seats_taken

  bool get isNetwork => code == 'network';

  @override
  String toString() => 'ApiException($code)';
}

/// Talks to the server (Vercel). Customers have no login: the booking reference + email,
/// or the access key saved on the phone, is what identifies a booking.
abstract class BookingApi {
  Future<CreatedBooking> createReservation(ReservationRequest request);

  /// Find my booking by reference → that booking's access key.
  Future<String> lookup({required String bookingReference});

  /// Find my booking by email: the server emails that address its upcoming booking
  /// references (the answer is the same whether or not it has any).
  Future<void> emailBookings(String email);

  Future<void> cancel(String accessKey);

  /// PayMongo's payment page for a pending PAID booking, or null if PayMongo already has
  /// the payment (the booking then updates by itself).
  Future<Uri?> startCheckout(String accessKey);

  /// Asks the server to check with PayMongo now, e.g. when the customer comes back from
  /// the payment page. Any change arrives through the booking view.
  Future<void> refreshPayment(String accessKey);
}

class HttpBookingApi implements BookingApi {
  HttpBookingApi(this.baseUrl, {http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final http.Client _client;

  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> _post(String path, Map<String, Object?> body) async {
    final http.Response res;
    try {
      res = await _client
          .post(Uri.parse('$baseUrl$path'), headers: {'Content-Type': 'application/json'}, body: jsonEncode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw const ApiException('network');
    } catch (_) {
      throw const ApiException('network');
    }

    Map<String, dynamic> json;
    try {
      json = (jsonDecode(res.body) as Map).cast<String, dynamic>();
    } catch (_) {
      throw ApiException('server_error', status: res.statusCode);
    }
    if (res.statusCode >= 200 && res.statusCode < 300) return json;

    throw ApiException(
      json['error'] as String? ?? 'server_error',
      status: res.statusCode,
      fields: {
        for (final e in ((json['fields'] as Map?) ?? const {}).entries) e.key.toString(): e.value.toString(),
      },
      seats: [for (final s in (json['seats'] as List?) ?? const []) s.toString()],
    );
  }

  @override
  Future<CreatedBooking> createReservation(ReservationRequest request) async {
    final j = await _post('/api/reservations/create', request.toJson());
    return CreatedBooking(
      bookingReference: j['bookingReference'] as String,
      accessKey: j['accessKey'] as String,
      requiresPayment: j['requiresPayment'] == true,
      totalCentavos: (j['totalCentavos'] as num?)?.toInt() ?? 0,
      expiresAt: j['expiresAt'] == null ? null : DateTime.parse(j['expiresAt'] as String),
    );
  }

  @override
  Future<String> lookup({required String bookingReference}) async {
    final j = await _post('/api/bookings/lookup', {'bookingReference': bookingReference});
    return j['accessKey'] as String;
  }

  @override
  Future<void> emailBookings(String email) => _post('/api/bookings/lookup', {'email': email});

  @override
  Future<void> cancel(String accessKey) => _post('/api/bookings/cancel', {'accessKey': accessKey});

  @override
  Future<Uri?> startCheckout(String accessKey) async {
    final j = await _post('/api/payments/checkout', {'accessKey': accessKey});
    final url = j['checkoutUrl'] as String?;
    return url == null ? null : Uri.parse(url);
  }

  @override
  Future<void> refreshPayment(String accessKey) => _post('/api/payments/refresh', {'accessKey': accessKey});
}
