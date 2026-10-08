import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/formatting.dart';
import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../staff_services.dart';
import '../widgets/admin_ui.dart';
import '../widgets/screening_table.dart';

enum _When { upcoming, past, all }

/// The website admin's Attendance page: every screening as a table grouped by day (seats
/// booked, admitted), filtered by Upcoming / Past / All and a title search. A row opens
/// the screening; "New screening" schedules one.
class AttendanceScreen extends StatefulWidget {
  const AttendanceScreen({super.key});

  @override
  State<AttendanceScreen> createState() => _AttendanceScreenState();
}

class _AttendanceScreenState extends State<AttendanceScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  StreamSubscription<Map<String, int>>? _admittedSub;
  List<String> _admittedIds = const [];
  List<Screening>? _screenings;
  List<Reservation> _pending = const [];
  Map<String, int> _admitted = const {};
  Object? _error;

  _When _when = _When.upcoming;
  String _query = '';
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty) return;
    final data = StaffServices.of(context).data;
    _subs.addAll([
      data.watchAllScreenings().listen((v) => setState(() => _screenings = v), onError: (Object e) => setState(() => _error = e)),
      data.watchPendingReservations().listen((v) => setState(() => _pending = v)),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _admittedSub?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Admitted counts for the screenings on screen that have already started (at most 30).
  void _watchAdmitted(List<Screening> shown, DateTime today) {
    final ids = [for (final s in shown) if (!manilaDay(s.startAt).isAfter(today)) s.id].take(30).toList();
    if (ids.join() == _admittedIds.join()) return;
    _admittedIds = ids;
    _admittedSub?.cancel();
    _admittedSub = StaffServices.of(context).data.watchAdmittedCounts(ids).listen((v) => setState(() => _admitted = v));
  }

  @override
  Widget build(BuildContext context) {
    final now = StaffServices.of(context).clock.now();
    final today = manilaDay(now);
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;

    final all = _screenings ?? const <Screening>[];
    final q = _query.toLowerCase();
    var shown = [
      for (final s in all)
        if (switch (_when) {
              _When.upcoming => !manilaDay(s.startAt).isBefore(today),
              _When.past => manilaDay(s.startAt).isBefore(today),
              _When.all => true,
            } &&
            (q.isEmpty || s.eventTitle.toLowerCase().contains(q) || (s.movie?.title.toLowerCase().contains(q) ?? false)))
          s,
    ];
    if (_when == _When.past) shown = shown.reversed.toList(); // most recent first
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _watchAdmitted(shown, today);
    });

    final pendingBy = <String, int>{};
    for (final r in _pending) {
      final waiting = r.screening.type == ScreeningType.free || (r.expiresAt?.isAfter(now) ?? false);
      if (waiting) pendingBy.update(r.screeningId, (n) => n + 1, ifAbsent: () => 1);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(child: PageTitle('Attendance')),
              AdminButton(label: 'New screening', onPressed: () => context.go('/attendance/new')),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilterChips<_When>(
                values: _When.values,
                current: _when,
                label: (w) => switch (w) { _When.upcoming => 'Upcoming', _When.past => 'Past', _When.all => 'All' },
                onSelect: (w) => setState(() => _when = w),
              ),
              SearchField(controller: _search, hint: 'Search by title', onChanged: (v) => setState(() => _query = v.trim())),
            ],
          ),
          const SizedBox(height: 12),
          if (_error != null)
            const Notice('Could not load screenings. Check your connection and reload the page.')
          else if (_screenings == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
          else if (shown.isEmpty)
            Panel(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    q.isNotEmpty ? 'No matches' : (_when == _When.past ? 'No past screenings' : 'No upcoming screenings'),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ])
          else
            ScreeningTable(screenings: shown, now: now, pendingBy: pendingBy, admitted: _admitted),
        ],
      ),
    );
  }
}
