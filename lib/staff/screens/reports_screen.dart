import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/reservation.dart';
import '../reports/csv_download.dart' as csv;
import '../reports/report.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/form_ui.dart';

enum ReportView { attendance, demographics }

/// The website's Reports page: one date range, two reports and a CSV of each.
///  - Attendance: seats reserved vs. admitted per screening, no-shows, verified payments.
///  - Demographics: everyone actually admitted, with the logsheet details they declared.
/// Cancelled bookings are left out of both.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, this.download = csv.downloadCsv});

  /// Saves a file in the browser; tests replace it.
  final void Function(String filename, String csv) download;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportView _view = ReportView.attendance;
  ReportRange? _range;
  Future<ReportData>? _data;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_range == null) _load(ReportRange.around(StaffServices.of(context).clock.now()));
  }

  void _load(ReportRange range) {
    _range = range;
    _data = StaffServices.of(context).data.loadReport(range.start, range.end);
  }

  void _setRange(ReportRange range) {
    if (range == _range) return;
    setState(() => _load(range));
  }

  Map<String, ReportRange> _presets(DateTime now) {
    final today = manilaDay(now);
    return {
      'Last 30 days': ReportRange(today.subtract(const Duration(days: 30)), today),
      'This month': ReportRange(DateTime.utc(today.year, today.month), DateTime.utc(today.year, today.month + 1, 0)),
      'Next 30 days': ReportRange(today, today.add(const Duration(days: 30))),
      'Last 30 + next 30': ReportRange.around(now),
    };
  }

  Future<void> _pick({required bool start}) async {
    final range = _range!;
    final current = start ? range.from : range.to;
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(current.year, current.month, current.day),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    final day = DateTime.utc(picked.year, picked.month, picked.day);
    // Keep the range the right way round, as the website requires.
    _setRange(start
        ? ReportRange(day, day.isAfter(range.to) ? day : range.to)
        : ReportRange(day.isBefore(range.from) ? day : range.from, day));
  }

  void _export(Report report) {
    final range = _range!;
    try {
      if (_view == ReportView.demographics) {
        widget.download('cinematheque-davao-demographics-${range.fileLabel}.csv', report.demographicsCsv());
      } else {
        widget.download('cinematheque-davao-report-${range.fileLabel}.csv', report.attendanceCsv());
      }
    } catch (_) {
      showMessage(context, 'Could not save the file. CSV export works in the browser only.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = StaffServices.of(context).clock.now();
    final range = _range!;
    final pad = MediaQuery.sizeOf(context).width < 600 ? 16.0 : 24.0;
    final presets = _presets(now);
    final preset = presets.entries.where((e) => e.value == range).firstOrNull?.key;

    return FutureBuilder<ReportData>(
      future: _data,
      builder: (context, snap) {
        final report = snap.hasData ? Report(snap.data!, now: now) : null;
        Widget body;
        if (snap.hasError) {
          body = const Notice('Could not load the report. Check your connection and reload the page.');
        } else if (report == null) {
          body = const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()));
        } else {
          body = _view == ReportView.attendance ? _attendance(report) : _demographics(report);
        }

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const PageTitle('Reports'),
                      Text(range.label, style: const TextStyle(fontSize: 14, color: StaffColors.textMuted)),
                    ]),
                  ),
                  AdminButton(label: 'Export CSV', onPressed: report == null ? null : () => _export(report)),
                ],
              ),
              const SizedBox(height: 16),
              _Tabs(current: _view, onSelect: (v) => setState(() => _view = v)),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilterChips<String?>(
                    values: presets.keys.toList(),
                    current: preset,
                    label: (v) => v ?? '',
                    onSelect: (v) => _setRange(presets[v]!),
                  ),
                  Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    const Text('From', style: TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                    SizedBox(
                      width: 150,
                      child: PickerButton(
                        text: DateFormat('MMM d, y').format(range.from),
                        icon: Icons.calendar_today_outlined,
                        onTap: () => _pick(start: true),
                      ),
                    ),
                    const Text('To', style: TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                    SizedBox(
                      width: 150,
                      child: PickerButton(
                        text: DateFormat('MMM d, y').format(range.to),
                        icon: Icons.calendar_today_outlined,
                        onTap: () => _pick(start: false),
                      ),
                    ),
                  ]),
                ],
              ),
              const SizedBox(height: 20),
              body,
            ],
          ),
        );
      },
    );
  }

  Widget _attendance(Report report) {
    final rate = report.reserved == 0 ? '' : ' (${(report.admitted / report.reserved * 100).round()}%)';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 18, runSpacing: 4, children: [
        Figure('${report.reserved}', 'seats reserved'),
        Figure('${report.admitted}', 'admitted$rate'),
        Text.rich(TextSpan(children: [
          TextSpan(
            text: '${report.noShows} ',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: StaffColors.warning),
          ),
          const TextSpan(text: 'no-shows', style: TextStyle(fontSize: 13, color: StaffColors.textMuted)),
        ])),
        Figure(formatPeso(report.paidCentavos), 'paid'),
      ]),
      const SizedBox(height: 20),
      AdminSection(
        title: 'Reserved vs. attended',
        trailing: const Text('Excludes cancelled bookings', style: TextStyle(fontSize: 13, color: StaffColors.textMuted)),
        child: report.rows.isEmpty
            ? const _Empty('No screenings in this range')
            : _Table(
                minWidth: 720,
                columns: const [
                  _Col('SCREENING', flex: 1),
                  _Col('RESERVED', width: 100, numeric: true),
                  _Col('ADMITTED', width: 100, numeric: true),
                  _Col('NO-SHOWS', width: 100, numeric: true),
                  _Col('PAYMENTS', width: 120, numeric: true),
                ],
                rows: [
                  for (final r in report.rows)
                    _TableRow(
                      onTap: () => context.go('/attendance/${r.screening.id}'),
                      cells: [
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(r.screening.eventTitle, style: const TextStyle(fontWeight: FontWeight.w600)),
                          Text(formatDateShort(r.screening.startAt),
                              style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                        ]),
                        Text('${r.reserved}'),
                        Text('${r.admitted}'),
                        Text(r.noShows == null ? '—' : '${r.noShows}'),
                        Text(r.paidCentavos > 0 ? formatPeso(r.paidCentavos) : '—'),
                      ],
                    ),
                ],
                footer: [
                  const Text('Total'),
                  Text('${report.reserved}'),
                  Text('${report.admitted}'),
                  Text('${report.noShows}'),
                  Text(formatPeso(report.paidCentavos)),
                ],
              ),
      ),
    ]);
  }

  Widget _demographics(Report report) {
    String or(String? v) => v == null || v.isEmpty ? '—' : v;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(spacing: 18, runSpacing: 4, children: [
        Figure('${report.people.length}', 'admitted'),
        Figure('${report.male}', 'male'),
        Figure('${report.female}', 'female'),
        Figure('${report.seniors}', 'senior citizens'),
        Figure('${report.pwd}', 'PWD'),
      ]),
      const SizedBox(height: 20),
      AdminSection(
        title: 'Admitted moviegoers',
        trailing: const Text('Excludes no-shows and cancelled bookings',
            style: TextStyle(fontSize: 13, color: StaffColors.textMuted)),
        child: report.people.isEmpty
            ? const _Empty('No one admitted in this range')
            : _Table(
                minWidth: 1240,
                columns: const [
                  _Col('DATE', width: 70),
                  _Col('EVENT', flex: 2),
                  _Col('NAME', flex: 2),
                  _Col('AGE', width: 50, numeric: true),
                  _Col('SEX', width: 56),
                  _Col('COMPANY / SCHOOL', flex: 2),
                  _Col('CONTACT NO.', width: 130),
                  _Col('EMAIL', flex: 2),
                  _Col('SENIOR ID', width: 110),
                  _Col('PWD', width: 50),
                ],
                rows: [
                  for (final p in report.people)
                    _TableRow(
                      onTap: () => context.go('/attendance/${p.screening.id}'),
                      cells: [
                        Text(DateFormat('MMM d').format(toManila(p.screening.startAt))),
                        Text(p.screening.eventTitle),
                        Text(p.attendee.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        Text(p.attendee.age?.toString() ?? '—'),
                        Text(p.attendee.sex?.dbValue ?? '—'),
                        Text(or(p.attendee.companySchool)),
                        Text(or(p.attendee.contactNo)),
                        Text(or(p.attendee.email)),
                        Text(or(p.attendee.seniorCardNo)),
                        Text(p.attendee.isPwd ? 'Yes' : '—'),
                      ],
                    ),
                ],
              ),
      ),
    ]);
  }
}

/// The website's underlined tabs (Attendance · Demographics).
class _Tabs extends StatelessWidget {
  const _Tabs({required this.current, required this.onSelect});

  final ReportView current;
  final ValueChanged<ReportView> onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: StaffColors.border))),
      child: Row(children: [
        for (final v in ReportView.values)
          Semantics(
            button: true,
            selected: v == current,
            child: InkWell(
              onTap: () => onSelect(v),
              child: Container(
                padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
                margin: const EdgeInsets.only(right: 20),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: v == current ? StaffColors.text : Colors.transparent, width: 2),
                  ),
                ),
                child: Text(
                  v == ReportView.attendance ? 'Attendance' : 'Demographics',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: v == current ? StaffColors.text : StaffColors.textMuted,
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Panel(children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 40),
          child: Center(child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600))),
        ),
      ]);
}

class _Col {
  const _Col(this.label, {this.width, this.flex, this.numeric = false});

  final String label;
  final double? width;
  final int? flex;
  final bool numeric;
}

class _TableRow {
  const _TableRow({required this.cells, this.onTap});

  final List<Widget> cells;
  final VoidCallback? onTap;
}

/// A website-style table: uppercase header, rows that open their record, optional total.
/// Scrolls sideways when the window is narrower than [minWidth].
class _Table extends StatelessWidget {
  const _Table({required this.columns, required this.rows, required this.minWidth, this.footer});

  final List<_Col> columns;
  final List<_TableRow> rows;
  final List<Widget>? footer;
  final double minWidth;

  Widget _line(List<Widget> cells, {TextStyle? style}) => Row(
        children: [
          for (var i = 0; i < columns.length; i++)
            () {
              final c = columns[i];
              Widget cell = Align(alignment: c.numeric ? Alignment.centerRight : Alignment.centerLeft, child: cells[i]);
              if (style != null) cell = DefaultTextStyle.merge(style: style, child: cell);
              cell = Padding(padding: EdgeInsets.only(left: i == 0 ? 0 : 12), child: cell);
              return c.width != null ? SizedBox(width: c.width! + (i == 0 ? 0 : 12), child: cell) : Expanded(flex: c.flex ?? 1, child: cell);
            }(),
        ],
      );

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.gray600);
    final table = Panel(children: [
      Container(
        color: StaffColors.surfaceAlt,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: _line([for (final c in columns) Text(c.label, style: head)]),
      ),
      for (final r in rows)
        Material(
          color: StaffColors.surface,
          child: InkWell(
            onTap: r.onTap,
            hoverColor: StaffColors.surfaceAlt,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: DefaultTextStyle.merge(
                style: const TextStyle(fontSize: 14, fontFeatures: [FontFeature.tabularFigures()]),
                child: _line(r.cells),
              ),
            ),
          ),
        ),
      if (footer != null)
        Container(
          color: StaffColors.surfaceAlt,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: _line(footer!, style: const TextStyle(fontWeight: FontWeight.w600, fontFeatures: [FontFeature.tabularFigures()])),
        ),
    ]);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= minWidth
          ? table
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: minWidth, child: table)),
    );
  }
}
