import 'package:ccd_mobile/data/models/attendance.dart';
import 'package:ccd_mobile/data/models/booking_view.dart';
import 'package:ccd_mobile/data/models/movie.dart';
import 'package:ccd_mobile/data/models/payment.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/data/models/screening.dart';
import 'package:ccd_mobile/data/models/seat_layout.dart';
import 'package:ccd_mobile/data/models/staff_member.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Timestamp ts(DateTime d) => Timestamp.fromDate(d);

void main() {
  final start = DateTime.utc(2026, 11, 20, 10);
  final now = DateTime.utc(2026, 11, 20, 8);

  group('SeatLayout', () {
    test('default layout has 120 unique seats, 10 rows of 12', () {
      final layout = SeatLayout.grid();
      expect(layout.seats.length, 120);
      expect(layout.activeCount, 120);
      expect(layout.seats.map((s) => s.label).toSet().length, 120);
      expect(layout.rows.keys, 'ABCDEFGHIJ'.split(''));
      expect(layout.rows['J']!.map((s) => s.label).last, 'J12');
    });

    test('inactive seats reduce capacity', () {
      final layout = SeatLayout.fromMap('seatLayout', {
        'seats': [
          {'label': 'A1', 'row': 'A', 'number': 1, 'isActive': true},
          {'label': 'A2', 'row': 'A', 'number': 2, 'isActive': false},
        ],
      });
      expect(layout.activeCount, 1);
    });
  });

  group('Screening seat availability', () {
    Screening screeningWith(Map<String, Object?> holds) => Screening.fromMap('s1', {
          'eventTitle': 'Film Night',
          'movieId': null,
          'movie': null,
          'startAt': ts(start),
          'endAt': ts(start.add(const Duration(hours: 2))),
          'type': 'paid',
          'priceCentavos': 15000,
          'capacity': 120,
          'seatHolds': holds,
          'hasReservations': true,
        });

    test('confirmed, free-pending and unexpired paid holds take seats', () {
      final s = screeningWith({
        'A1': {'reservationId': 'r1', 'state': 'confirmed'},
        'A2': {'reservationId': 'r2', 'state': 'held'}, // free booking awaiting approval
        'A3': {'reservationId': 'r3', 'state': 'held', 'expiresAt': ts(now.add(const Duration(minutes: 5)))},
      });
      expect(s.takenSeatLabelsAt(now), {'A1', 'A2', 'A3'});
      expect(s.availableSeatsAt(now), 117);
    });

    test('an EXPIRED unpaid hold does not block the seat', () {
      final s = screeningWith({
        'A3': {'reservationId': 'r3', 'state': 'held', 'expiresAt': ts(now.subtract(const Duration(minutes: 1)))},
      });
      expect(s.takenSeatLabelsAt(now), isEmpty);
      expect(s.availableSeatsAt(now), 120);
    });

    test('booking closes when the screening starts', () {
      final s = screeningWith({});
      expect(s.isBookableAt(start.subtract(const Duration(minutes: 1))), isTrue);
      expect(s.isBookableAt(start), isFalse);
      expect(s.isBookableAt(start.add(const Duration(minutes: 1))), isFalse);
    });
  });

  group('Reading documents', () {
    test('movie without a poster', () {
      final m = Movie.fromMap('m1', {'title': 'Himala', 'genres': ['Drama'], 'poster': null});
      expect(m.poster, isNull);
      expect(m.genres, ['Drama']);
    });

    test('reservation with seats, attendees and a cancellation reason', () {
      final r = Reservation.fromMap('r1', {
        'bookingReference': 'CCD-ABCD2345',
        'screeningId': 's1',
        'screening': {'eventTitle': 'Film Night', 'startAt': ts(start), 'endAt': ts(start), 'type': 'paid'},
        'status': 'cancelled',
        'cancellationReason': 'payment_expired',
        'booker': {'firstName': 'Juan', 'lastName': 'Dela Cruz', 'contactNo': '0917', 'email': 'j@example.test'},
        'seats': [
          {
            'label': 'A1',
            'isBooker': true,
            'attendee': {'firstName': 'Juan', 'lastName': 'Dela Cruz', 'sex': 'M', 'isPwd': true, 'age': 70},
          },
        ],
        'totalCentavos': 15000,
        'createdAt': ts(now),
      });
      expect(r.status, ReservationStatus.cancelled);
      expect(r.cancellationReason, CancellationReason.paymentExpired);
      expect(r.seatLabels, ['A1']);
      expect(r.seats.single.attendee.sex, Sex.male);
      expect(r.seats.single.attendee.isPwd, isTrue);
    });

    test('payment, attendance, booking view and staff', () {
      expect(
        Payment.fromMap('r1', {'bookingReference': 'CCD-X', 'amountCentavos': 15000, 'status': 'verified', 'createdAt': ts(now)})
            .status,
        PaymentStatus.verified,
      );
      expect(Attendance.docId('r1', 'A1'), 'r1_A1');
      final view = BookingView.fromMap('key', {
        'bookingReference': 'CCD-X',
        'status': 'confirmed',
        'screening': {'eventTitle': 'Film Night', 'startAt': ts(start), 'endAt': ts(start), 'type': 'free'},
        'seats': [
          {'label': 'A1', 'attendeeName': 'Juan Dela Cruz'},
        ],
      });
      expect(view.hasTicket, isTrue);
      expect(view.isFree, isTrue);
      final staff = StaffMember.fromMap('uid1', {
        'firstName': 'Ana',
        'lastName': 'Reyes',
        'email': 'ana@example.test',
        'position': 'PDO',
        'isActive': true,
      });
      expect(staff.position, StaffPosition.pdo);
    });

    test('unknown stored values are reported, not silently accepted', () {
      expect(
        () => Payment.fromMap('r1', {'bookingReference': 'CCD-X', 'status': 'rejected', 'createdAt': ts(now)}),
        throwsFormatException,
      );
    });
  });
}
