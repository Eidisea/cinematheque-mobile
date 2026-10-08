import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/movie.dart';
import '../../data/models/screening.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';
import '../widgets/admin_ui.dart';

/// The website admin's Film catalog: one row per film (poster, title and rating, runtime,
/// genre, director, year, how many screenings) with "Schedule" to put it on. A row opens
/// the film.
class FilmsScreen extends StatefulWidget {
  const FilmsScreen({super.key});

  @override
  State<FilmsScreen> createState() => _FilmsScreenState();
}

class _FilmsScreenState extends State<FilmsScreen> {
  final _subs = <StreamSubscription<Object?>>[];
  List<Movie>? _movies;
  List<Screening> _screenings = const [];
  Object? _error;
  String _query = '';
  final _search = TextEditingController();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_subs.isNotEmpty) return;
    final data = StaffServices.of(context).data;
    _subs.addAll([
      data.watchMovies().listen((v) => setState(() => _movies = v), onError: (Object e) => setState(() => _error = e)),
      data.watchAllScreenings().listen((v) => setState(() => _screenings = v)),
    ]);
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final pad = width < 600 ? 16.0 : 24.0;
    final movies = _movies;
    final q = _query.toLowerCase();
    final shown = [
      for (final m in movies ?? const <Movie>[])
        if (q.isEmpty || m.title.toLowerCase().contains(q) || m.directors.any((d) => d.toLowerCase().contains(q))) m,
    ];
    final counts = <String, int>{};
    for (final s in _screenings) {
      if (s.movieId != null) counts.update(s.movieId!, (n) => n + 1, ifAbsent: () => 1);
    }

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const PageTitle('Film catalog'),
                    if (movies != null)
                      Text('${movies.length} ${movies.length == 1 ? 'film' : 'films'}',
                          style: const TextStyle(fontSize: 14, color: StaffColors.textMuted)),
                  ],
                ),
              ),
              AdminButton(label: 'Add film', onPressed: () => context.go('/settings/films/new')),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: SearchField(controller: _search, hint: 'Search by title or director', onChanged: (v) => setState(() => _query = v.trim())),
          ),
          const SizedBox(height: 12),
          if (_error != null)
            const Notice('Could not load the film catalog. Check your connection and reload the page.')
          else if (movies == null)
            const Padding(padding: EdgeInsets.symmetric(vertical: 48), child: Center(child: CircularProgressIndicator()))
          else if (shown.isEmpty)
            Panel(children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(q.isEmpty ? 'No films yet' : 'No matches', style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
              ),
            ])
          else
            _Table(movies: shown, counts: counts),
        ],
      ),
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.movies, required this.counts});

  final List<Movie> movies;
  final Map<String, int> counts;

  static const _minWidth = 900.0;

  @override
  Widget build(BuildContext context) {
    const head = TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.gray600);
    final table = Panel(children: [
      Container(
        color: StaffColors.surfaceAlt,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: const Row(children: [
          Expanded(flex: 4, child: Text('FILM', style: head)),
          SizedBox(width: 90, child: Text('RUNTIME', style: head)),
          Expanded(flex: 2, child: Text('GENRE', style: head)),
          Expanded(flex: 2, child: Text('DIRECTOR', style: head)),
          SizedBox(width: 60, child: Text('YEAR', style: head)),
          SizedBox(width: 100, child: Text('SCREENINGS', style: head, textAlign: TextAlign.center)),
          SizedBox(width: 100, child: Text('ACTIONS', style: head, textAlign: TextAlign.right)),
        ]),
      ),
      for (final m in movies)
        Material(
          color: StaffColors.surface,
          child: InkWell(
            onTap: () => context.go('/settings/films/${m.id}'),
            hoverColor: StaffColors.surfaceAlt,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(children: [
                Expanded(
                  flex: 4,
                  child: Row(children: [
                    PosterThumb(url: m.poster?.url, width: 26),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(m.title, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (m.rating != null) Text(m.rating!, style: const TextStyle(fontSize: 13, color: StaffColors.textMuted)),
                      ]),
                    ),
                  ]),
                ),
                SizedBox(width: 90, child: Text(m.runtimeMinutes == null ? '—' : '${m.runtimeMinutes} min')),
                Expanded(flex: 2, child: Text(m.genres.isEmpty ? '—' : m.genres.join(', '), overflow: TextOverflow.ellipsis)),
                Expanded(flex: 2, child: Text(m.directors.isEmpty ? '—' : m.directors.join(', '), overflow: TextOverflow.ellipsis)),
                SizedBox(width: 60, child: Text('${m.releaseYear ?? '—'}')),
                SizedBox(width: 100, child: Text('${counts[m.id] ?? 0}', textAlign: TextAlign.center)),
                SizedBox(
                  width: 100,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AdminButton(
                      label: 'Schedule',
                      small: true,
                      kind: AdminButtonKind.secondary,
                      onPressed: () => context.go('/attendance/new?movie=${m.id}'),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),
    ]);
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth >= _minWidth
          ? table
          : SingleChildScrollView(scrollDirection: Axis.horizontal, child: SizedBox(width: _minWidth, child: table)),
    );
  }
}

/// A small 2:3 poster, or a gray placeholder when there is none (never an invented image).
class PosterThumb extends StatelessWidget {
  const PosterThumb({super.key, required this.url, required this.width});

  final String? url;
  final double width;

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(width: width, height: width * 1.5, color: StaffColors.gray100);
    return ClipRRect(
      borderRadius: BorderRadius.circular(2),
      child: url == null
          ? placeholder
          : Image.network(url!, width: width, height: width * 1.5, fit: BoxFit.cover, errorBuilder: (_, _, _) => placeholder),
    );
  }
}
