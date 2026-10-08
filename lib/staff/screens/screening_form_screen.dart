import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/formatting.dart';
import '../../data/models/movie.dart';
import '../../data/models/screening.dart';
import '../staff_services.dart';
import '../widgets/admin_ui.dart';
import '../widgets/form_ui.dart';

/// New / Edit screening, as the website admin's dedicated page: what's showing (a film
/// from the catalog, or a special programme), the schedule (the end follows the film's
/// runtime), and admission (free, or paid per seat). A summary on the side holds Save.
/// Once anyone has booked, date, time, type and price are locked (firestore.rules agrees).
class ScreeningFormScreen extends StatefulWidget {
  const ScreeningFormScreen({super.key, this.screeningId, required this.staffUid, this.initialMovieId});

  /// null → a new screening.
  final String? screeningId;
  final String? staffUid;

  /// Opened from the film catalog ("Schedule"): that film is preselected.
  final String? initialMovieId;

  /// The hall: 10 rows of 12, fixed.
  static const hallSeats = 120;

  @override
  State<ScreeningFormScreen> createState() => _ScreeningFormScreenState();
}

enum _Kind { film, programme }

class _ScreeningFormScreenState extends State<ScreeningFormScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  List<Movie>? _movies;
  Screening? _existing;
  bool _loaded = false;

  _Kind _kind = _Kind.film;
  String? _movieId;
  final _title = TextEditingController();
  DateTime? _date; // Manila calendar date (UTC midnight)
  TimeOfDay? _start;
  TimeOfDay? _end;
  bool _endTouched = false;
  ScreeningType _type = ScreeningType.free;
  final _price = TextEditingController();
  Map<String, String> _errors = const {};
  bool _saving = false;

  bool get _isNew => widget.screeningId == null;
  bool get _locked => _existing?.hasReservations ?? false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty) return;
    final data = StaffServices.of(context).data;
    _subs.add(data.watchMovies().listen((v) => setState(() => _movies = v)));
    if (_isNew) {
      _loaded = true;
      _movieId = widget.initialMovieId;
    } else {
      _subs.add(data.watchScreening(widget.screeningId!).listen((s) {
        if (_existing == null && s != null) _fill(s);
        setState(() {
          _existing = s ?? _existing;
          _loaded = true;
        });
      }));
    }
  }

  void _fill(Screening s) {
    final start = toManila(s.startAt);
    final end = toManila(s.endAt);
    _kind = s.movieId == null ? _Kind.programme : _Kind.film;
    _movieId = s.movieId;
    _title.text = s.movie != null && s.movie!.title == s.eventTitle ? '' : s.eventTitle;
    _date = DateTime.utc(start.year, start.month, start.day);
    _start = TimeOfDay(hour: start.hour, minute: start.minute);
    _end = TimeOfDay(hour: end.hour, minute: end.minute);
    _endTouched = true;
    _type = s.type;
    _price.text = s.priceCentavos == null ? '' : (s.priceCentavos! / 100).toStringAsFixed(s.priceCentavos! % 100 == 0 ? 0 : 2);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _title.dispose();
    _price.dispose();
    super.dispose();
  }

  Movie? get _movie => _kind == _Kind.film ? _movies?.where((m) => m.id == _movieId).firstOrNull : null;

  /// The end follows the film's runtime until staff set it themselves.
  void _syncEnd() {
    final runtime = _movie?.runtimeMinutes;
    if (_endTouched || _start == null || runtime == null) return;
    final minutes = _start!.hour * 60 + _start!.minute + runtime;
    if (minutes < 24 * 60) _end = TimeOfDay(hour: minutes ~/ 60, minute: minutes % 60);
  }

  DateTime? _at(TimeOfDay? t) =>
      _date == null || t == null ? null : DateTime.utc(_date!.year, _date!.month, _date!.day, t.hour - 8, t.minute);

  String get _eventTitle {
    final typed = _title.text.trim();
    return typed.isNotEmpty ? typed : (_movie?.title ?? '');
  }

  Map<String, String> _validate(DateTime now) {
    final e = <String, String>{};
    if (_kind == _Kind.film && _movie == null) e['film'] = 'Choose a film from the catalog.';
    if (_kind == _Kind.programme && _title.text.trim().isEmpty) e['title'] = 'Enter the programme title.';
    if (_eventTitle.length > 150) e['title'] = 'Use at most 150 characters.';
    if (!_locked) {
      if (_date == null) e['date'] = 'Choose a date.';
      if (_start == null) e['start'] = 'Choose a start time.';
      if (_end == null) e['end'] = 'Choose an end time.';
      final start = _at(_start), end = _at(_end);
      if (start != null && end != null && !end.isAfter(start)) e['end'] = 'The end must be after the start.';
      if (start != null && _isNew && !start.isAfter(now)) e['start'] = 'That time has already passed.';
      if (_type == ScreeningType.paid) {
        final price = double.tryParse(_price.text.trim());
        if (price == null || price <= 0) {
          e['price'] = 'Enter the price per seat.';
        } else if (price > 100000) {
          e['price'] = 'That price looks too high.';
        }
      }
    }
    return e;
  }

  Future<void> _save() async {
    final now = StaffServices.of(context).clock.now();
    final errors = _validate(now);
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final movie = _movie;
    final existing = _existing;
    final screening = Screening(
      id: existing?.id ?? '',
      eventTitle: _eventTitle,
      movieId: movie?.id,
      movie: movie == null
          ? null
          : MovieSnapshot(title: movie.title, posterUrl: movie.poster?.url, runtimeMinutes: movie.runtimeMinutes, genres: movie.genres),
      startAt: _locked ? existing!.startAt : _at(_start)!,
      endAt: _locked ? existing!.endAt : _at(_end)!,
      type: _locked ? existing!.type : _type,
      priceCentavos: _locked
          ? existing!.priceCentavos
          : (_type == ScreeningType.paid ? (double.parse(_price.text.trim()) * 100).round() : null),
      capacity: existing?.capacity ?? ScreeningFormScreen.hallSeats,
      seatHolds: existing?.seatHolds ?? const {},
      hasReservations: existing?.hasReservations ?? false,
      createdBy: existing?.createdBy ?? widget.staffUid ?? '',
    );

    final data = StaffServices.of(context).data;
    setState(() => _saving = true);
    try {
      final id = existing == null ? await data.createScreening(screening, staffUid: widget.staffUid ?? '') : existing.id;
      if (existing != null) await data.updateScreening(screening);
      if (!mounted) return;
      showMessage(context, existing == null ? 'Screening created.' : 'Changes saved.');
      context.go('/attendance/$id');
    } catch (_) {
      if (mounted) {
        showMessage(context,
            'Could not save. ${_locked ? 'Date, time and price are locked once people have booked. ' : ''}Check your connection and try again.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() => context.go(_isNew ? '/attendance' : '/attendance/${widget.screeningId}');

  Future<void> _pickDate() async {
    final now = toManila(StaffServices.of(context).clock.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) setState(() => _date = DateTime.utc(picked.year, picked.month, picked.day));
  }

  Future<void> _pickTime({required bool start}) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: (start ? _start : _end) ?? const TimeOfDay(hour: 18, minute: 0),
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _start = picked;
        _syncEnd();
      } else {
        _end = picked;
        _endTouched = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;

    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (!_isNew && _existing == null) {
      return Padding(padding: EdgeInsets.all(pad), child: const Notice('This screening no longer exists.', tone: Tone.warning));
    }

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormPanel(title: 'What’s showing', children: [
          LabeledField(
            label: 'Type',
            child: ChoiceToggle<_Kind>(
              values: _Kind.values,
              current: _kind,
              label: (k) => k == _Kind.film ? 'Film' : 'Special programme',
              onSelect: (k) => setState(() {
                _kind = k;
                _syncEnd();
              }),
            ),
          ),
          if (_kind == _Kind.film)
            LabeledField(
              label: 'Film',
              required: true,
              error: _errors['film'],
              hint: (_movies?.isEmpty ?? false) ? 'No films in the catalog yet. Add one in Film catalog, or choose Special programme.' : null,
              child: SelectBox<String>(
                value: _movieId,
                hint: 'Choose a film',
                items: {
                  for (final m in _movies ?? const <Movie>[]) m.id: m.releaseYear == null ? m.title : '${m.title} (${m.releaseYear})',
                },
                onChanged: (v) => setState(() {
                  _movieId = v;
                  _syncEnd();
                }),
              ),
            ),
          LabeledField(
            label: _kind == _Kind.film ? 'Screening title' : 'Programme title',
            required: _kind == _Kind.programme,
            hint: _kind == _Kind.film ? 'Optional. Uses the film title if blank.' : null,
            error: _errors['title'],
            child: TextField(controller: _title, maxLength: 150, onChanged: (_) => setState(() {}), decoration: const InputDecoration(counterText: '')),
          ),
        ]),
        const SizedBox(height: 16),
        FormPanel(title: 'Schedule', children: [
          if (_locked) ...[
            const Notice('People have booked this screening, so its date and time can’t change.', tone: Tone.warning),
            const SizedBox(height: 12),
          ],
          Wrap(spacing: 16, runSpacing: 4, children: [
            SizedBox(
              width: 200,
              child: LabeledField(
                label: 'Date',
                required: true,
                error: _errors['date'],
                child: PickerButton(
                  text: _date == null ? 'Choose a date' : DateFormat('EEE, MMM d, y').format(_date!),
                  icon: Icons.calendar_today_outlined,
                  onTap: _locked ? null : _pickDate,
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: LabeledField(
                label: 'Starts',
                required: true,
                error: _errors['start'],
                child: PickerButton(
                  text: _start == null ? '—' : _start!.format(context),
                  icon: Icons.schedule,
                  onTap: _locked ? null : () => _pickTime(start: true),
                ),
              ),
            ),
            SizedBox(
              width: 150,
              child: LabeledField(
                label: 'Ends',
                required: true,
                error: _errors['end'],
                hint: !_endTouched && _movie?.runtimeMinutes != null ? 'From the runtime.' : null,
                child: PickerButton(
                  text: _end == null ? '—' : _end!.format(context),
                  icon: Icons.schedule,
                  onTap: _locked ? null : () => _pickTime(start: false),
                ),
              ),
            ),
          ]),
        ]),
        const SizedBox(height: 16),
        FormPanel(title: 'Admission', children: [
          if (_locked) ...[
            const Notice('People have booked this screening, so its admission type and price can’t change.', tone: Tone.warning),
            const SizedBox(height: 12),
          ],
          LabeledField(
            label: 'Admission type',
            required: true,
            child: ChoiceToggle<ScreeningType>(
              values: ScreeningType.values,
              current: _type,
              enabled: !_locked,
              label: (t) => t == ScreeningType.paid ? 'Paid' : 'Free',
              onSelect: (t) => setState(() => _type = t),
            ),
          ),
          if (_type == ScreeningType.paid)
            SizedBox(
              width: 220,
              child: LabeledField(
                label: 'Price per seat (₱)',
                required: true,
                error: _errors['price'],
                child: TextField(
                  controller: _price,
                  enabled: !_locked,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ),
        ]),
      ],
    );

    final start = _at(_start), end = _at(_end);
    final price = double.tryParse(_price.text.trim());
    final summary = FormPanel(title: 'Summary', children: [
      SummaryLine('Title', _eventTitle.isEmpty ? '—' : _eventTitle),
      SummaryLine('Type', _kind == _Kind.film ? 'Film' : 'Special programme'),
      SummaryLine('Date', _date == null ? '—' : DateFormat('EEE, MMM d, y').format(_date!)),
      SummaryLine('Time', start == null || end == null ? '—' : '${formatTime(start)} – ${formatTime(end)}'),
      SummaryLine(
          'Admission', _type == ScreeningType.free ? 'Free' : (price == null || price <= 0 ? 'Paid' : '${formatPeso((price * 100).round())} per seat')),
      SummaryLine('Capacity', '${_existing?.capacity ?? ScreeningFormScreen.hallSeats} seats'),
      const SizedBox(height: 12),
      SizedBox(
        width: double.infinity,
        child: AdminButton(label: _isNew ? 'Create screening' : 'Save changes', busy: _saving, onPressed: _save),
      ),
      const SizedBox(height: 8),
      SizedBox(
        width: double.infinity,
        child: AdminButton(label: 'Cancel', kind: AdminButtonKind.secondary, onPressed: _cancel),
      ),
    ]);

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackLink(_isNew ? 'Attendance' : (_existing?.eventTitle ?? 'Back'), onTap: _cancel),
          const SizedBox(height: 8),
          PageTitle(_isNew ? 'New screening' : 'Edit screening'),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 900
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: fields),
                    const SizedBox(width: 24),
                    SizedBox(width: 320, child: summary),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fields, const SizedBox(height: 16), summary]),
          ),
        ],
      ),
    );
  }
}
