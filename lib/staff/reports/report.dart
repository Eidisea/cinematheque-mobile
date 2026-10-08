import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/attendance.dart';
import '../../data/models/payment.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';

/// Everything the Reports page needs for one date range, read once.
class ReportData {
  const ReportData({
    this.screenings = const [],
    this.reservations = const [],
    this.attendances = const [],
    this.payments = const [],
  });

  /// Screenings starting within the range, soonest first.
  final List<Screening> screenings;

  /// Bookings for those screenings (any status).
  final List<Reservation> reservations;

  /// Admissions to those screenings.
  final List<Attendance> attendances;

  /// Verified payments (the report keeps only those of bookings above).
  final List<Payment> payments;
}

/// A range of Manila calendar days, both ends included. Days are `DateTime.utc(y, m, d)`.
class ReportRange {
  const ReportRange(this.from, this.to);

  final DateTime from;
  final DateTime to;

  /// The website's default: the last 30 days and the next 30.
  factory ReportRange.around(DateTime now) {
    final today = manilaDay(now);
    return ReportRange(today.subtract(const Duration(days: 30)), today.add(const Duration(days: 30)));
  }

  /// Midnight Manila at the start of [from], as an instant.
  DateTime get start => from.subtract(const Duration(hours: 8));

  /// Midnight Manila after [to], as an instant (exclusive).
  DateTime get end => to.add(const Duration(days: 1)).subtract(const Duration(hours: 8));

  String get label => '${DateFormat('MMM d, y').format(from)} – ${DateFormat('MMM d, y').format(to)}';

  String get fileLabel => '${DateFormat('yyyy-MM-dd').format(from)}-to-${DateFormat('yyyy-MM-dd').format(to)}';

  @override
  bool operator ==(Object other) => other is ReportRange && other.from == from && other.to == to;

  @override
  int get hashCode => Object.hash(from, to);
}

/// Reserved vs. admitted for one screening. Cancelled bookings are left out.
class ScreeningReportRow {
  const ScreeningReportRow({
    required this.screening,
    required this.reserved,
    required this.admitted,
    required this.noShows,
    required this.paidCentavos,
  });

  final Screening screening;
  final int reserved;
  final int admitted;

  /// Reserved seats nobody was admitted to; null until the screening has ended.
  final int? noShows;

  /// Verified payments for this screening, minus those owed back as refunds.
  final int paidCentavos;
}

/// One admitted moviegoer, with the logsheet details they declared.
class AdmittedPerson {
  const AdmittedPerson({required this.screening, required this.seatLabel, required this.attendee});

  final Screening screening;
  final String seatLabel;
  final Attendee attendee;
}

class Report {
  Report(ReportData data, {required DateTime now}) {
    final screenings = {for (final s in data.screenings) s.id: s};
    final active = {
      for (final r in data.reservations)
        if (r.status != ReservationStatus.cancelled && screenings.containsKey(r.screeningId)) r.id: r,
    };
    final admitted = [for (final a in data.attendances) if (active.containsKey(a.reservationId)) a];

    final paidBy = <String, int>{};
    for (final p in data.payments) {
      final r = data.reservations.where((r) => r.id == p.reservationId).firstOrNull;
      if (r == null || p.status != PaymentStatus.verified || p.needsRefund) continue;
      paidBy.update(r.screeningId, (n) => n + p.amountCentavos, ifAbsent: () => p.amountCentavos);
    }

    rows = [
      for (final s in data.screenings)
        () {
          final reserved = active.values.where((r) => r.screeningId == s.id).fold<int>(0, (n, r) => n + r.seats.length);
          final inside = admitted.where((a) => a.screeningId == s.id).length;
          return ScreeningReportRow(
            screening: s,
            reserved: reserved,
            admitted: inside,
            noShows: now.isBefore(s.endAt) ? null : reserved - inside,
            paidCentavos: paidBy[s.id] ?? 0,
          );
        }(),
    ];

    people = [
      for (final a in admitted)
        if (active[a.reservationId]!.seats.where((s) => s.label == a.seatLabel).firstOrNull case final seat?)
          AdmittedPerson(screening: screenings[a.screeningId]!, seatLabel: seat.label, attendee: seat.attendee),
    ]..sort((a, b) {
        final byTime = a.screening.startAt.compareTo(b.screening.startAt);
        return byTime != 0 ? byTime : _seatOrder(a.seatLabel, b.seatLabel);
      });
  }

  late final List<ScreeningReportRow> rows;
  late final List<AdmittedPerson> people;

  int get reserved => rows.fold(0, (n, r) => n + r.reserved);
  int get admitted => rows.fold(0, (n, r) => n + r.admitted);
  int get noShows => rows.fold(0, (n, r) => n + (r.noShows ?? 0));
  int get paidCentavos => rows.fold(0, (n, r) => n + r.paidCentavos);

  int get male => people.where((p) => p.attendee.sex == Sex.male).length;
  int get female => people.where((p) => p.attendee.sex == Sex.female).length;
  int get seniors => people.where((p) => p.attendee.seniorCardNo != null).length;
  int get pwd => people.where((p) => p.attendee.isPwd).length;

  /// The attendance report as CSV (the website's columns).
  String attendanceCsv() => _csv([
        ['Date', 'Start', 'Event', 'Type', 'Seats reserved', 'Checked in', 'No-shows', 'Verified payments (PHP)'],
        for (final r in rows)
          [
            DateFormat('yyyy-MM-dd').format(toManila(r.screening.startAt)),
            DateFormat('HH:mm').format(toManila(r.screening.startAt)),
            r.screening.eventTitle,
            r.screening.type.name,
            '${r.reserved}',
            '${r.admitted}',
            r.noShows == null ? '' : '${r.noShows}',
            (r.paidCentavos / 100).toStringAsFixed(2),
          ],
      ]);

  /// Everyone admitted, one row each, with the logsheet columns. Senior citizen ID numbers
  /// stay in the staff app: the file only says whether one was declared.
  String demographicsCsv() => _csv([
        [
          'Date', 'Event', 'Last name', 'First name', 'Middle name', 'Age', 'Sex', //
          'Company/School', 'Contact no.', 'Email', 'Senior citizen', 'PWD',
        ],
        for (final p in people)
          [
            DateFormat('yyyy-MM-dd').format(toManila(p.screening.startAt)),
            p.screening.eventTitle,
            p.attendee.lastName,
            p.attendee.firstName,
            p.attendee.middleName ?? '',
            p.attendee.age?.toString() ?? '',
            p.attendee.sex?.dbValue ?? '',
            p.attendee.companySchool ?? '',
            p.attendee.contactNo ?? '',
            p.attendee.email ?? '',
            p.attendee.seniorCardNo != null ? 'Yes' : '',
            p.attendee.isPwd ? 'Yes' : '',
          ],
      ]);
}

/// "A2" before "A10".
int _seatOrder(String a, String b) {
  final row = a.substring(0, 1).compareTo(b.substring(0, 1));
  if (row != 0) return row;
  return (int.tryParse(a.substring(1)) ?? 0).compareTo(int.tryParse(b.substring(1)) ?? 0);
}

/// RFC 4180 CSV with CRLF line ends. Text a spreadsheet would run as a formula
/// (starting with = @ or a tab/return, or + and - unless it is a phone number) gets a leading '.
String _csv(List<List<String>> rows) => rows.map((row) => row.map(_cell).join(',')).join('\r\n');

String _cell(String v) {
  var s = v;
  if (s.isNotEmpty && RegExp(r'^[=@\t\r]|^[+-](?![0-9 ]+$)').hasMatch(s)) s = "'$s";
  if (s.contains(RegExp(r'[",\r\n]'))) s = '"${s.replaceAll('"', '""')}"';
  return s;
}
