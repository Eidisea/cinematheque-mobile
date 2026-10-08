import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/movie.dart';
import '../data/staff_api.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';
import '../widgets/form_ui.dart';
import 'films_screen.dart';

/// Add / edit a film, as the website admin's film form: title, year, runtime, rating,
/// genres, director, actors, synopsis, and the poster. The poster goes straight from the
/// browser to Cloudinary, signed by the server; replaced or removed posters are deleted
/// once the film is saved. Saving also updates the film's upcoming screenings.
class FilmFormScreen extends StatefulWidget {
  const FilmFormScreen({super.key, this.movieId});

  /// null → a new film.
  final String? movieId;

  static const ratings = ['G', 'PG', 'PG-13', 'R-13', 'R-16', 'R-18'];
  static const genres = [
    'Drama', 'Comedy', 'Romance', 'Action', 'Thriller', 'Horror', //
    'Documentary', 'Animation', 'Musical', 'Historical', 'Experimental', 'Short Film',
  ];
  static const maxPosterBytes = 5 * 1024 * 1024;

  /// Opens the browser's file chooser for a poster image. Tests replace it.
  @visibleForTesting
  static Future<({Uint8List bytes, String name})?> Function() pickPoster = _pickWithFilePicker;

  static Future<({Uint8List bytes, String name})?> _pickWithFilePicker() async {
    final file = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['jpg', 'jpeg', 'png', 'webp']);
    if (file == null) return null;
    return (bytes: await file.xFile.readAsBytes(), name: file.name);
  }

  @override
  State<FilmFormScreen> createState() => _FilmFormScreenState();
}

class _FilmFormScreenState extends State<FilmFormScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  Movie? _existing;
  bool _loaded = false;
  int _screeningCount = 0;

  final _title = TextEditingController();
  final _year = TextEditingController();
  final _runtime = TextEditingController();
  final _directors = TextEditingController();
  final _cast = TextEditingController();
  final _synopsis = TextEditingController();
  String? _rating;
  final _genres = <String>{};
  Poster? _poster;
  final _uploaded = <Poster>[]; // uploaded on this page, not yet saved
  bool _uploading = false;
  bool _saving = false;
  Map<String, String> _errors = const {};

  bool get _isNew => widget.movieId == null;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty || _loaded) return;
    final data = StaffServices.of(context).data;
    if (_isNew) {
      _loaded = true;
      return;
    }
    _subs.add(data.watchMovies().listen((all) {
      final m = all.where((x) => x.id == widget.movieId).firstOrNull;
      if (_existing == null && m != null) _fill(m);
      setState(() {
        _existing = m ?? _existing;
        _loaded = true;
      });
    }));
    _subs.add(data.watchAllScreenings().listen((v) {
      setState(() => _screeningCount = v.where((s) => s.movieId == widget.movieId).length);
    }));
  }

  void _fill(Movie m) {
    _title.text = m.title;
    _year.text = m.releaseYear?.toString() ?? '';
    _runtime.text = m.runtimeMinutes?.toString() ?? '';
    _directors.text = m.directors.join(', ');
    _cast.text = m.cast.join(', ');
    _synopsis.text = m.synopsis ?? '';
    _rating = m.rating;
    _genres.addAll(m.genres);
    _poster = m.poster;
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    for (final c in [_title, _year, _runtime, _directors, _cast, _synopsis]) {
      c.dispose();
    }
    super.dispose();
  }

  static List<String> _names(String text) =>
      [for (final n in text.split(',')) if (n.trim().isNotEmpty) n.trim()];

  Map<String, String> _validate() {
    final e = <String, String>{};
    final title = _title.text.trim();
    if (title.isEmpty) e['title'] = 'Enter the film title.';
    if (title.length > 150) e['title'] = 'Use at most 150 characters.';
    final year = _year.text.trim(), runtime = _runtime.text.trim();
    if (year.isNotEmpty && (int.tryParse(year) == null || int.parse(year) < 1888 || int.parse(year) > 2100)) {
      e['year'] = 'Enter a year from 1888 to 2100.';
    }
    if (runtime.isNotEmpty && (int.tryParse(runtime) == null || int.parse(runtime) < 1 || int.parse(runtime) > 600)) {
      e['runtime'] = 'Enter minutes from 1 to 600.';
    }
    if (_names(_directors.text).length > 20) e['directors'] = 'At most 20 names.';
    if (_names(_cast.text).length > 60) e['cast'] = 'At most 60 names.';
    if (_synopsis.text.length > 5000) e['synopsis'] = 'Use at most 5,000 characters.';
    return e;
  }

  Future<void> _upload() async {
    final api = StaffServices.of(context).api;
    if (api == null) return showMessage(context, 'The booking server is not configured for this build.');
    final picked = await FilmFormScreen.pickPoster();
    if (picked == null || !mounted) return;
    if (picked.bytes.length > FilmFormScreen.maxPosterBytes) {
      return showMessage(context, 'That image is larger than 5 MB. Please choose a smaller one.');
    }
    setState(() => _uploading = true);
    try {
      final poster = await api.uploadPoster(picked.bytes, picked.name);
      setState(() {
        _poster = poster;
        _uploaded.add(poster);
      });
    } catch (e) {
      if (mounted) showMessage(context, staffApiMessage(e));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  /// Deletes posters that no film uses any more (best effort).
  void _cleanUp(Iterable<Poster?> posters, {Poster? keep}) {
    final api = StaffServices.of(context).api;
    if (api == null) return;
    for (final p in posters) {
      if (p != null && p.publicId != keep?.publicId) unawaited(api.deletePoster(p.publicId).catchError((_) {}));
    }
  }

  Future<void> _save() async {
    final errors = _validate();
    setState(() => _errors = errors);
    if (errors.isNotEmpty) return;

    final services = StaffServices.of(context);
    final existing = _existing;
    final movie = Movie(
      id: existing?.id ?? '',
      title: _title.text.trim(),
      synopsis: _synopsis.text.trim().isEmpty ? null : _synopsis.text.trim(),
      runtimeMinutes: int.tryParse(_runtime.text.trim()),
      rating: _rating,
      releaseYear: int.tryParse(_year.text.trim()),
      genres: _genres.toList(),
      directors: _names(_directors.text),
      cast: _names(_cast.text),
      poster: _poster,
      createdAt: existing?.createdAt,
    );

    setState(() => _saving = true);
    try {
      if (existing == null) {
        await services.data.createMovie(movie);
      } else {
        await services.data.updateMovie(movie);
        await services.data.refreshScreeningsOf(movie, now: services.clock.now());
      }
      _cleanUp([existing?.poster, ..._uploaded], keep: _poster);
      if (!mounted) return;
      showMessage(context, existing == null ? 'Film added.' : 'Changes saved.');
      context.go('/settings/films');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not save the film. Check your connection and try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _cancel() {
    _cleanUp(_uploaded); // uploaded here but never saved
    context.go('/settings/films');
  }

  Future<void> _delete(Movie m) async {
    final ok = await confirmAction(
      context,
      title: 'Delete film?',
      message: 'Delete “${m.title}” from the catalog? This cannot be undone.',
      confirm: 'Delete film',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await StaffServices.of(context).data.deleteMovie(m.id);
      _cleanUp([m.poster, ..._uploaded]);
      if (!mounted) return;
      showMessage(context, 'Deleted “${m.title}”.');
      context.go('/settings/films');
    } catch (_) {
      if (mounted) showMessage(context, 'Could not delete the film. Check your connection and try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (!_isNew && _existing == null) {
      return Padding(padding: EdgeInsets.all(pad), child: const Notice('This film no longer exists.', tone: Tone.warning));
    }

    final otherGenres = _genres.where((g) => !FilmFormScreen.genres.contains(g)).toList();

    final fields = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormPanel(title: 'Film', children: [
          LabeledField(
            label: 'Title',
            required: true,
            error: _errors['title'],
            child: TextField(controller: _title, maxLength: 150, onChanged: (_) => setState(() {}), decoration: const InputDecoration(counterText: '')),
          ),
          Wrap(spacing: 16, children: [
            SizedBox(
              width: 120,
              child: LabeledField(
                label: 'Year',
                error: _errors['year'],
                child: TextField(controller: _year, keyboardType: TextInputType.number),
              ),
            ),
            SizedBox(
              width: 150,
              child: LabeledField(
                label: 'Runtime (min)',
                error: _errors['runtime'],
                child: TextField(controller: _runtime, keyboardType: TextInputType.number),
              ),
            ),
            SizedBox(
              width: 180,
              child: LabeledField(
                label: 'Content rating',
                child: SelectBox<String>(
                  value: _rating,
                  hint: 'Not rated',
                  items: {for (final r in FilmFormScreen.ratings) r: r},
                  onChanged: (v) => setState(() => _rating = v),
                ),
              ),
            ),
          ]),
          LabeledField(
            label: 'Genre',
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final g in [...FilmFormScreen.genres, ...otherGenres])
                  FilterChip(
                    label: Text(g),
                    selected: _genres.contains(g),
                    showCheckmark: false,
                    selectedColor: StaffColors.brandTint,
                    side: BorderSide(color: _genres.contains(g) ? StaffColors.brand : StaffColors.borderStrong),
                    shape: const StadiumBorder(),
                    labelStyle: TextStyle(fontSize: 13, color: _genres.contains(g) ? StaffColors.brand : StaffColors.gray700),
                    onSelected: (on) => setState(() => on ? _genres.add(g) : _genres.remove(g)),
                  ),
              ],
            ),
          ),
          LabeledField(
            label: 'Director',
            error: _errors['directors'],
            hint: 'Separate names with commas.',
            child: TextField(controller: _directors, decoration: const InputDecoration(hintText: 'e.g. Ishmael Bernal')),
          ),
          LabeledField(
            label: 'Actors',
            error: _errors['cast'],
            hint: 'Separate names with commas.',
            child: TextField(
              controller: _cast,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(hintText: 'e.g. Nora Aunor, Veronica Palileo, Spanky Manikan'),
            ),
          ),
          LabeledField(
            label: 'Synopsis',
            error: _errors['synopsis'],
            child: TextField(controller: _synopsis, minLines: 3, maxLines: 8),
          ),
        ]),
      ],
    );

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FormPanel(title: 'Poster', children: [
          Center(child: _poster == null ? const PosterThumb(url: null, width: 140) : PosterThumb(url: _poster!.url, width: 140)),
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              AdminButton(
                label: _poster == null ? 'Upload poster' : 'Replace',
                kind: AdminButtonKind.secondary,
                busy: _uploading,
                onPressed: _upload,
              ),
              if (_poster != null)
                AdminButton(label: 'Remove', kind: AdminButtonKind.danger, onPressed: () => setState(() => _poster = null)),
            ],
          ),
          const SizedBox(height: 8),
          const Text('JPG, PNG or WebP, up to 5 MB. Portrait (2:3) looks best.',
              textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: StaffColors.textMuted)),
        ]),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: AdminButton(label: _isNew ? 'Add film' : 'Save changes', busy: _saving, onPressed: _uploading ? null : _save),
        ),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: AdminButton(label: 'Cancel', kind: AdminButtonKind.secondary, onPressed: _cancel)),
        if (!_isNew) ...[
          const SizedBox(height: 16),
          if (_screeningCount == 0)
            SizedBox(
              width: double.infinity,
              child: AdminButton(label: 'Delete film', kind: AdminButtonKind.danger, onPressed: () => _delete(_existing!)),
            )
          else
            Text('Used by $_screeningCount ${_screeningCount == 1 ? 'screening' : 'screenings'}, so it can’t be deleted.',
                textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, color: StaffColors.textMuted)),
        ],
      ],
    );

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          BackLink('Film catalog', onTap: _cancel),
          const SizedBox(height: 8),
          PageTitle(_isNew ? 'Add film' : 'Edit film'),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, box) => box.maxWidth >= 900
                ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(child: fields),
                    const SizedBox(width: 24),
                    SizedBox(width: 300, child: side),
                  ])
                : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [fields, const SizedBox(height: 16), side]),
          ),
        ],
      ),
    );
  }
}
