import 'package:cloud_firestore/cloud_firestore.dart';

import 'model_utils.dart';

/// verified = the server asked PayMongo and PayMongo reported it paid (exact amount).
enum PaymentStatus { pending, verified }

/// `payments/{reservationId}` — one per PAID reservation (free ones have none).
/// Written ONLY by the server (checkout, webhook, refresh); readable only by staff.
class Payment {
  const Payment({
    required this.reservationId,
    required this.bookingReference,
    required this.amountCentavos,
    required this.status,
    this.checkoutSessionId,
    this.paymongoPaymentId,
    this.method,
    this.paidAt,
    this.needsRefund = false,
    required this.createdAt,
  });

  final String reservationId;
  final String bookingReference;
  final int amountCentavos;
  final PaymentStatus status;
  final String? checkoutSessionId; // PayMongo checkout session (cs_…)
  final String? paymongoPaymentId; // PayMongo payment (pay_…)
  final String? method; // e.g. gcash, card, paymaya — as reported by PayMongo
  final DateTime? paidAt;
  final bool needsRefund; // paid after the booking was cancelled/expired → staff refund outside the system
  final DateTime createdAt;

  factory Payment.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, [SnapshotOptions? _]) =>
      Payment.fromMap(doc.id, doc.data() ?? const {});

  factory Payment.fromMap(String id, Map<String, dynamic> d) {
    return Payment(
      reservationId: id,
      bookingReference: requireString(d['bookingReference'], 'bookingReference'),
      amountCentavos: intOrNull(d['amountCentavos']) ?? 0,
      status: enumFromDb(PaymentStatus.values, (s) => s.name, d['status'], 'status'),
      checkoutSessionId: stringOrNull(d['checkoutSessionId']),
      paymongoPaymentId: stringOrNull(d['paymongoPaymentId']),
      method: stringOrNull(d['method']),
      paidAt: dateOrNull(d['paidAt']),
      needsRefund: d['needsRefund'] == true,
      createdAt: requireDate(d['createdAt'], 'createdAt'),
    );
  }

  static Map<String, Object?> toFirestore(Payment _, SetOptions? _) =>
      throw UnsupportedError('payments are written by the server only');
}
