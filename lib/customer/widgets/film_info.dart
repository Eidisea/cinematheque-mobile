import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../data/models/movie.dart';
import '../theme/customer_theme.dart';

/// Film facts: runtime / rating / year, genres, synopsis, director(s), cast.
/// Only shows what the catalog actually contains.
class FilmInfo extends StatelessWidget {
  const FilmInfo({super.key, required this.movie, this.showSynopsisTitle = true});

  final Movie movie;
  final bool showSynopsisTitle;

  @override
  Widget build(BuildContext context) {
    final facts = [
      if (movie.runtimeMinutes != null) formatDuration(movie.runtimeMinutes!),
      if (movie.rating != null) movie.rating!,
      if (movie.releaseYear != null) '${movie.releaseYear}',
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (facts.isNotEmpty || movie.genres.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final f in facts) _Tag(f, filled: true),
              for (final g in movie.genres) _Tag(g),
            ],
          ),
        if (movie.synopsis != null) ...[
          const SizedBox(height: Space.lg),
          if (showSynopsisTitle) const SectionTitle('Synopsis'),
          Text(movie.synopsis!, style: const TextStyle(fontSize: 15, height: 1.65)),
        ],
        if (movie.directors.isNotEmpty || movie.cast.isNotEmpty) ...[
          const SizedBox(height: Space.lg),
          if (movie.directors.isNotEmpty) _KeyValue(movie.directors.length == 1 ? 'Director' : 'Directors', movie.directors.join(', ')),
          if (movie.cast.isNotEmpty) _KeyValue('Cast', movie.cast.join(', ')),
        ],
      ],
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, {this.filled = false});

  final String text;
  final bool filled;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: filled ? CustomerColors.neutralTint : CustomerColors.surface,
          border: filled ? null : Border.all(color: CustomerColors.border),
          borderRadius: BorderRadius.circular(Radii.pill),
        ),
        child: Text(text, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500)),
      );
}

/// Laravel's key/value rows: small uppercase label, value underneath.
class _KeyValue extends StatelessWidget {
  const _KeyValue(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label.toUpperCase(),
                style: const TextStyle(fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.w600, color: CustomerColors.faint)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 14.5, height: 1.45)),
          ],
        ),
      );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.sm),
      child: Semantics(
        header: true,
        child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      ),
    );
  }
}
