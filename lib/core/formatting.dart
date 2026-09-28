import 'package:intl/intl.dart';

/// Cinematheque Centre Davao runs on Philippine time (UTC+8, no daylight saving).
/// Every date/time is shown in Manila time, whatever time zone the phone is set to.
DateTime toManila(DateTime time) => time.toUtc().add(const Duration(hours: 8));

/// Midnight (in Manila) of the day [time] falls on — used to group screenings by day.
DateTime manilaDay(DateTime time) {
  final m = toManila(time);
  return DateTime.utc(m.year, m.month, m.day);
}

String formatTime(DateTime time) => DateFormat('h:mm a').format(toManila(time));

String formatTimeRange(DateTime start, DateTime end) => '${formatTime(start)} – ${formatTime(end)}';

String formatDateShort(DateTime time) => DateFormat('EEE, MMM d').format(toManila(time));

String formatDateLong(DateTime time) => DateFormat('EEEE, MMMM d, y').format(toManila(time));

/// "Today", "Tomorrow", or e.g. "Sat, Nov 21".
String dayLabel(DateTime time, DateTime now) {
  final days = manilaDay(time).difference(manilaDay(now)).inDays;
  return switch (days) { 0 => 'Today', 1 => 'Tomorrow', _ => formatDateShort(time) };
}

/// 15000 → "₱150", 15050 → "₱150.50".
String formatPeso(int centavos) {
  if (centavos % 100 == 0) return '₱${NumberFormat('#,##0').format(centavos ~/ 100)}';
  return '₱${NumberFormat('#,##0.00').format(centavos / 100)}';
}

/// 124 → "2h 4m", 90 → "1h 30m", 45 → "45m".
String formatDuration(int minutes) {
  final h = minutes ~/ 60;
  final m = minutes % 60;
  if (h == 0) return '${m}m';
  return m == 0 ? '${h}h' : '${h}h ${m}m';
}
