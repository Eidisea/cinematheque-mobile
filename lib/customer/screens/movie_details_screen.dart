import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/movie.dart';
import '../../data/models/screening.dart';
import '../customer_services.dart';
import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/film_info.dart';
import '../widgets/motion.dart';
import '../widgets/poster.dart';
import '../widgets/screening_card.dart';
import '../widgets/state_views.dart';
import 'screening_details_screen.dart' show RoundBackButton;

/// A film from the catalog and its upcoming screenings.
class MovieDetailsScreen extends StatefulWidget {
  const MovieDetailsScreen({super.key, required this.movieId});

  final String movieId;

  @override
  State<MovieDetailsScreen> createState() => _MovieDetailsScreenState();
}

class _MovieDetailsScreenState extends State<MovieDetailsScreen> {
  Stream<Movie?>? _movie;
  Stream<List<Screening>>? _screenings;

  void _load() {
    final services = CustomerServices.of(context);
    _movie = services.catalog.watchMovie(widget.movieId);
    _screenings = services.catalog.watchScreeningsForMovie(widget.movieId, from: services.clock.now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_movie == null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final now = CustomerServices.of(context).clock.now();
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(backgroundColor: Colors.transparent, leading: const RoundBackButton(), automaticallyImplyLeading: false),
      body: StreamBuilder<Movie?>(
        stream: _movie,
        builder: (context, snapshot) {
          if (snapshot.hasError) return ErrorView(onRetry: () => setState(_load));
          if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) return const LoadingView();
          final movie = snapshot.data;
          if (movie == null) {
            return const MessageView(
              icon: Icons.movie_outlined,
              title: 'Film not found',
              message: 'This film is no longer in the catalog.',
            );
          }

          return ListView(
            padding: EdgeInsets.zero,
            children: [
              Container(
                decoration: const BoxDecoration(
                  color: CustomerColors.heroTint,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    const Positioned(left: 0, right: 0, bottom: 0, child: DavaoSkyline(height: 64, opacity: 0.08)),
                    ContentWidth(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(Space.gutter, top + 64, Space.gutter, Space.xxl),
                        child: Column(
                          children: [
                            PosterImage(url: movie.poster?.url, title: movie.title, width: 170),
                            const SizedBox(height: Space.xl),
                            const Eyebrow('Film'),
                            const SizedBox(height: 6),
                            Semantics(
                              header: true,
                              child: Text(movie.title.toUpperCase(), textAlign: TextAlign.center, style: CcdType.display(32, spacing: 0.8)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ContentWidth(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xl, Space.gutter, Space.xxxl),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilmInfo(movie: movie),
                      const SizedBox(height: Space.xl),
                      const SectionHeading('Upcoming screenings', size: 20),
                      const SizedBox(height: Space.lg),
                      StreamBuilder<List<Screening>>(
                        stream: _screenings,
                        builder: (context, snap) {
                          if (snap.hasError) return const Text('Could not load screenings.');
                          if (!snap.hasData) {
                            return const Padding(padding: EdgeInsets.all(Space.lg), child: Center(child: CircularProgressIndicator()));
                          }
                          final upcoming = snap.data!.where((s) => s.isBookableAt(now)).toList();
                          if (upcoming.isEmpty) {
                            return const Text('No upcoming screenings of this film yet.', style: TextStyle(color: CustomerColors.muted));
                          }
                          return Column(
                            children: [
                              for (final (i, s) in upcoming.indexed)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: Space.lg),
                                  child: Entrance(
                                    index: i,
                                    child: ScreeningCard(
                                      screening: s,
                                      now: now,
                                      onTap: () => context.push('/screenings/${s.id}'),
                                      onReserve: () => context.push('/screenings/${s.id}/seats'),
                                    ),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
