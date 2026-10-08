import 'package:ccd_mobile/core/clock.dart';
import 'package:ccd_mobile/data/models/attendance.dart';
import 'package:ccd_mobile/data/models/reservation.dart';
import 'package:ccd_mobile/staff/reports/report.dart';
import 'package:ccd_mobile/staff/screens/reports_screen.dart';
import 'package:ccd_mobile/staff/staff_services.dart';
import 'package:ccd_mobile/staff/theme/staff_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_staff_repository.dart';
import 'staff_dashboard_test.dart' as d;

Attendance admission(Reservation r, String seat) => Attendance(
      reservationId: r.id,
      bookingReference: r.bookingReference,
      screeningId: r.screeningId,
      seatLabel: seat,
      attendeeName: 'A B',
      checkedInBy: 'u1',
    );

Reservation withPeople(Reservation r) => Reservation(
      id: r.id,
      bookingReference: r.bookingReference,
      screeningId: r.screeningId,
      screening: r.screening,
      status: r.status,
      booker: r.booker,
      seats: const [
        ReservedSeat(
          label: 'B1',
          isBooker: true,
          attendee: Attendee(
            firstName: 'Maria',
            lastName: 'Santos, Jr.',
            age: 67,
            sex: Sex.female,
            companySchool: '=HYPERLINK("x")',
            contactNo: '+639171234567',
            email: 'maria@example.com',
            seniorCardNo: 'SC-123',
          ),
        ),
        ReservedSeat(
          label: 'B2',
          isBooker: false,
          attendee: Attendee(firstName: 'Jo', lastName: 'Reyes', age: 20, sex: Sex.male, isPwd: true),
        ),
      ],
      totalCentavos: r.totalCentavos,
      createdAt: r.createdAt,
    );

void main() {
  // Oct 1 (over), Oct 9 (upcoming, paid), and Dec 1 (outside the default range).
  final past = d.screening('past', 'Oro, Plata, Mata', d.manila(1, 18));
  final next = d.screening('next', 'It Was Just an Accident', d.manila(9, 15), paid: true);
  final later = d.screening('later', 'Case 137', DateTime.utc(2026, 12, 1, 10));

  final kept = withPeople(d.booking('kept', past, status: ReservationStatus.confirmed));
  final gone = d.booking('gone', past, status: ReservationStatus.cancelled, seats: 3);
  final paid = d.booking('paid', next, status: ReservationStatus.confirmed, seats: 2);
  final late = d.booking('late', next, status: ReservationStatus.cancelled, seats: 1);

  final data = ReportData(
    screenings: [past, next],
    reservations: [kept, gone, paid, late],
    attendances: [admission(kept, 'B1'), admission(kept, 'B2'), admission(gone, 'B1')],
    payments: [d.payment(paid), d.payment(late, refund: true)],
  );

  test('attendance: cancelled bookings and refunds left out; no-shows only once a screening is over', () {
    final report = Report(data, now: d.now);
    final [p, n] = report.rows;
    expect((p.reserved, p.admitted, p.noShows, p.paidCentavos), (2, 2, 0, 0));
    expect((n.reserved, n.admitted, n.noShows, n.paidCentavos), (2, 0, null, 30000));
    expect((report.reserved, report.admitted, report.noShows, report.paidCentavos), (4, 2, 0, 30000));
  });

  test('demographics: the people admitted, with their declared details', () {
    final report = Report(data, now: d.now);
    expect(report.people.map((p) => p.attendee.firstName), ['Maria', 'Jo']);
    expect((report.male, report.female, report.seniors, report.pwd), (1, 1, 1, 1));
  });

  test('CSV: the website columns, quoted where needed, no formulas, no senior ID numbers', () {
    final report = Report(data, now: d.now);
    expect(report.attendanceCsv().split('\r\n'), [
      'Date,Start,Event,Type,Seats reserved,Checked in,No-shows,Verified payments (PHP)',
      '2026-10-01,18:00,"Oro, Plata, Mata",free,2,2,0,0.00',
      '2026-10-09,15:00,It Was Just an Accident,paid,2,0,,300.00',
    ]);
    final rows = report.demographicsCsv().split('\r\n');
    expect(rows.first,
        'Date,Event,Last name,First name,Middle name,Age,Sex,Company/School,Contact no.,Email,Senior citizen,PWD');
    expect(rows[1],
        '2026-10-01,"Oro, Plata, Mata","Santos, Jr.",Maria,,67,F,"\'=HYPERLINK(""x"")",+639171234567,maria@example.com,Yes,');
    expect(rows[2], '2026-10-01,"Oro, Plata, Mata",Reyes,Jo,,20,M,,,,,Yes');
    expect(report.demographicsCsv(), isNot(contains('SC-123')));
  });

  test('ranges are Manila calendar days', () {
    final range = ReportRange.around(d.now);
    expect(range.label, 'Sep 8, 2026 – Nov 7, 2026');
    expect(range.start, DateTime.utc(2026, 9, 7, 16));
    expect(range.end, DateTime.utc(2026, 11, 7, 16));
  });

  testWidgets('the Reports page: both reports for the default range, and their CSV files', (tester) async {
    tester.view.physicalSize = const Size(1440, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = FakeStaffRepository(
      screenings: [past, next, later],
      reservations: [kept, gone, paid, late],
      attendances: data.attendances,
      payments: data.payments,
    );
    final saved = <String, String>{};
    await tester.pumpWidget(MaterialApp(
      theme: buildStaffTheme(),
      home: Scaffold(
        body: StaffServices(
          data: repo,
          clock: FixedClock(d.now),
          child: ReportsScreen(download: (name, csv) => saved[name] = csv),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Sep 8, 2026 – Nov 7, 2026'), findsOneWidget);
    expect(find.text('Oro, Plata, Mata'), findsOneWidget);
    expect(find.text('Case 137'), findsNothing, reason: 'December is outside the range');
    expect(find.text('4 seats reserved', findRichText: true), findsOneWidget);
    expect(find.text('2 admitted (50%)', findRichText: true), findsOneWidget);
    expect(find.text('₱300 paid', findRichText: true), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Export CSV'));
    expect(saved.keys, ['cinematheque-davao-report-2026-09-08-to-2026-11-07.csv']);

    await tester.tap(find.text('Demographics'));
    await tester.pumpAndSettle();
    expect(find.text('Maria Santos, Jr.'), findsOneWidget);
    expect(find.text('SC-123'), findsOneWidget, reason: 'staff see it on screen');
    expect(find.text('1 senior citizens', findRichText: true), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Export CSV'));
    expect(saved.keys.last, 'cinematheque-davao-demographics-2026-09-08-to-2026-11-07.csv');

    await tester.tap(find.text('Next 30 days'));
    await tester.pumpAndSettle();
    expect(find.text('Oct 8, 2026 – Nov 7, 2026'), findsOneWidget);
    expect(find.text('No one admitted in this range'), findsOneWidget);
  });
}
