import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/screening.dart';
import '../theme/staff_theme.dart';
import 'admin_ui.dart';

/// Screenings as a table, grouped by day: time · screening · seats booked · admitted.
class ScreeningTable extends StatelessWidget {
  const ScreeningTable({
    super.key,
    required this.screenings,
    required this.now,
    required this.pendingBy,
    required this.admitted,
    this.grouped = true,
  });

  final List<Screening> screenings;
  final DateTime now;
  final Map<String, int> pendingBy;
  final Map<String, int> admitted;
  final bool grouped;

  static const _timeWidth = 104.0;
  static const _bookedWidth = 150.0;
  static const _admittedWidth = 84.0;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.gray600);
    final today = manilaDay(now);
    final rows = <Widget>[];
    DateTime? day;

    for (final s in screenings) {
      final d = manilaDay(s.startAt);
      if (grouped && d != day) {
        day = d;
        final diff = d.difference(today).inDays;
        rows.add(_GroupRow(
          label: switch (diff) { 0 => 'Today', 1 => 'Tomorrow', _ => DateFormat('EEEE').format(d) },
          date: DateFormat('MMMM d, y').format(d),
        ));
      }
      final booked = s.seatHolds.values.where((h) => h.isActiveAt(now)).length;
      final waiting = pendingBy[s.id] ?? 0;
      final started = !d.isAfter(today); // today or earlier: admissions are known
      rows.add(_Row(
        onTap: () => context.go('/attendance/${s.id}'),
        children: [
          SizedBox(width: _timeWidth, child: Text(formatTime(s.startAt), style: const TextStyle(fontWeight: FontWeight.w500))),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.eventTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text.rich(
                  TextSpan(
                    style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
                    children: [
                      TextSpan(text: s.isPaid && s.priceCentavos != null ? formatPeso(s.priceCentavos!) : 'Free'),
                      if (waiting > 0) ...[
                        const TextSpan(text: ' · '),
                        TextSpan(
                          text: '$waiting ${s.isPaid ? 'awaiting payment' : 'to approve'}',
                          style: const TextStyle(color: StaffColors.warning),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _bookedWidth,
            child: Row(
              children: [
                FillBar(fraction: s.capacity == 0 ? 0 : booked / s.capacity),
                const SizedBox(width: 8),
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text('$booked / ${s.capacity}', style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()])),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: _admittedWidth,
            child: Text(started ? '${admitted[s.id] ?? 0}' : '—', textAlign: TextAlign.right),
          ),
        ],
      ));
    }

    return Panel(
      children: [
        Container(
          color: StaffColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: const Row(
            children: [
              SizedBox(width: _timeWidth, child: Text('TIME', style: head)),
              Expanded(child: Text('SCREENING', style: head)),
              SizedBox(width: _bookedWidth, child: Text('BOOKED', style: head)),
              SizedBox(width: _admittedWidth, child: Text('ADMITTED', style: head, textAlign: TextAlign.right)),
            ],
          ),
        ),
        ...rows,
      ],
    );
  }
}

class _GroupRow extends StatelessWidget {
  const _GroupRow({required this.label, required this.date});

  final String label;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: StaffColors.surfaceAlt,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text.rich(TextSpan(children: [
        TextSpan(text: label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        TextSpan(text: '   $date', style: const TextStyle(color: StaffColors.textMuted, fontSize: 13)),
      ])),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.children, required this.onTap});

  final List<Widget> children;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StaffColors.surface,
      child: InkWell(
        onTap: onTap,
        hoverColor: StaffColors.surfaceAlt,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: children),
        ),
      ),
    );
  }
}

