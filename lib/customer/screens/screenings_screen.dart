import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/screening.dart';
import '../customer_services.dart';
import '../theme/customer_theme.dart';
import '../widgets/brand.dart';
import '../widgets/motion.dart';
import '../widgets/screening_card.dart';
import '../widgets/spotlight_banner.dart';
import '../widgets/state_views.dart';

enum _TypeFilter { all, free, paid }

/// Home tab: a light Cinematheque hero, search + Free/Paid filter, and upcoming
/// screenings as tickets (soonest first).
class ScreeningsScreen extends StatefulWidget {
  const ScreeningsScreen({super.key});

  @override
  State<ScreeningsScreen> createState() => _ScreeningsScreenState();
}

class _ScreeningsScreenState extends State<ScreeningsScreen> {
  Stream<List<Screening>>? _stream;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  String _query = '';
  _TypeFilter _filter = _TypeFilter.all;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _load();
  }

  Stream<List<Screening>> _load() {
    final services = CustomerServices.of(context);
    return services.catalog.watchUpcomingScreenings(from: services.clock.now());
  }

  void _retry() => setState(() => _stream = _load());

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  bool _matches(Screening s) {
    if (_filter == _TypeFilter.free && s.isPaid) return false;
    if (_filter == _TypeFilter.paid && !s.isPaid) return false;
    if (_query.isEmpty) return true;
    final q = _query.toLowerCase();
    return s.eventTitle.toLowerCase().contains(q) || (s.movie?.title.toLowerCase().contains(q) ?? false);
  }

  void _clear() => setState(() {
    _search.clear();
    _query = '';
    _filter = _TypeFilter.all;
  });

  @override
  Widget build(BuildContext context) {
    final now = CustomerServices.of(context).clock.now();

    return Scaffold(
      body: StreamBuilder<List<Screening>>(
        stream: _stream,
        builder: (context, snapshot) {
          final upcoming = snapshot.data?.where((s) => s.isBookableAt(now)).toList();
          final shown = upcoming?.where(_matches).toList();

          final Widget body;
          if (snapshot.hasError) {
            body = SliverFillRemaining(hasScrollBody: false, child: ErrorView(onRetry: _retry));
          } else if (upcoming == null) {
            body = const SliverToBoxAdapter(child: _TicketSkeletons());
          } else if (upcoming.isEmpty) {
            body = const SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(
                icon: Icons.event_outlined,
                title: 'No upcoming screenings',
                message: 'New programmes are posted here as soon as they are confirmed. Check back soon.',
              ),
            );
          } else if (shown!.isEmpty) {
            body = SliverFillRemaining(
              hasScrollBody: false,
              child: MessageView(
                icon: Icons.search_off_rounded,
                title: 'No matching screenings',
                message: 'Try another title, or show both free and paid screenings.',
                actionLabel: 'Clear search and filter',
                onAction: _clear,
              ),
            );
          } else {
            body = SliverPadding(
              padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
              sliver: SliverList.separated(
                itemCount: shown.length,
                separatorBuilder: (_, _) => const SizedBox(height: Space.lg),
                itemBuilder: (context, i) {
                  final s = shown[i];
                  return ContentWidth(
                    child: Entrance(
                      index: i,
                      child: ScreeningCard(
                        screening: s,
                        now: now,
                        onTap: () => context.push('/screenings/${s.id}'),
                        onReserve: () => context.push('/screenings/${s.id}/seats'),
                      ),
                    ),
                  );
                },
              ),
            );
          }

          return Stack(
            children: [
              CustomScrollView(
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(
                    child: _Hero(
                      search: _search,
                      onSearch: (v) => setState(() => _query = v.trim()),
                      query: _query,
                      banner: !SpotlightBanner.enabled || upcoming == null || upcoming.isEmpty
                          ? null
                          : SpotlightBanner(
                              screenings: SpotlightBanner.featured(upcoming, now),
                              now: now,
                              onOpen: (s) => context.push('/screenings/${s.id}'),
                            ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: ContentWidth(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.lg, Space.gutter, Space.md),
                        child: _Filters(filter: _filter, onChanged: (f) => setState(() => _filter = f), count: shown?.length),
                      ),
                    ),
                  ),
                  body,
                  const SliverToBoxAdapter(child: _Footer()),
                ],
              ),
              // The hero's tint may sit behind the status bar; tickets scrolling up may not.
              AnimatedBuilder(
                animation: _scroll,
                builder: (context, _) => StatusBarScrim(opacity: ((_scroll.hasClients ? _scroll.offset : 0) - 160) / 80),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Light hero (Laravel): paper with soft purple/gold glows, the Davao skyline at the
/// bottom, gold eyebrow and a big condensed title. The search card overlaps its edge.
class _Hero extends StatelessWidget {
  const _Hero({required this.search, required this.onSearch, required this.query, this.banner});

  final TextEditingController search;
  final ValueChanged<String> onSearch;
  final String query;

  /// The website's spotlight banner, between the wordmark and the title.
  final Widget? banner;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: CustomerColors.heroTint,
            borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            children: [
              const Positioned(left: -60, top: -40, child: _Glow(color: Color(0x1F580076), size: 260)),
              const Positioned(right: -70, top: 40, child: _Glow(color: Color(0x2EEBBC00), size: 240)),
              const Positioned(left: 0, right: 0, bottom: 0, child: DavaoSkyline(height: 70, opacity: 0.09)),
              Column(
                children: [
                  ContentWidth(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(Space.gutter, top + Space.lg, Space.gutter, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const BrandMark(size: 34),
                              const SizedBox(width: 10),
                              // The wordmark shrinks rather than overflowing at very large text sizes.
                              Flexible(
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('CINEMATHEQUE', style: CcdType.display(17, spacing: 1.6)),
                                      Text('CENTRE DAVAO', style: CcdType.eyebrow.copyWith(fontSize: 9.5, letterSpacing: 2.2)),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (banner != null) ...[const SizedBox(height: Space.xl), ContentWidth(maxWidth: 720, child: banner!)],
                  ContentWidth(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(Space.gutter, Space.xxl, Space.gutter, 64),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Eyebrow('FDCP · Davao City · Philippine cinema'),
                          const SizedBox(height: 6),
                          Semantics(header: true, child: Text('NOW SHOWING', style: CcdType.display(44, spacing: 1.2))),
                          const SizedBox(height: Space.sm),
                          const Text(
                            'Screenings, retrospectives and talks. Reserve your seats — no account needed.',
                            style: TextStyle(fontSize: 14.5, height: 1.5, color: CustomerColors.muted),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: -26,
          child: ContentWidth(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.gutter),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.lg),
                  boxShadow: const [BoxShadow(color: Color(0x1F141219), blurRadius: 24, offset: Offset(0, 10))],
                ),
                child: TextField(
                  controller: search,
                  onChanged: onSearch,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search by title or film',
                    prefixIcon: const Icon(Icons.search_rounded, color: CustomerColors.muted),
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(Radii.lg), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(Radii.lg),
                      borderSide: const BorderSide(color: CustomerColors.gold600, width: 1.6),
                    ),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () {
                              search.clear();
                              onSearch('');
                            },
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color, required this.size});

  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
    ),
  );
}

class _Filters extends StatelessWidget {
  const _Filters({required this.filter, required this.onChanged, required this.count});

  final _TypeFilter filter;
  final ValueChanged<_TypeFilter> onChanged;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 26), // room for the overlapping search card
      child: Row(
        children: [
          // Editorial toggles in the nav bar's language (condensed caps + a gold rule),
          // not Material chips. Wraps instead of overflowing on narrow phones / large text.
          Expanded(
            child: Wrap(
              spacing: Space.xs,
              children: [
                for (final f in _TypeFilter.values)
                  _FilterToggle(
                    key: ValueKey('filter-${f.name}'),
                    label: switch (f) {
                      _TypeFilter.all => 'All',
                      _TypeFilter.free => 'Free',
                      _TypeFilter.paid => 'Paid',
                    },
                    selected: filter == f,
                    onTap: () => onChanged(f),
                  ),
              ],
            ),
          ),
          const SizedBox(width: Space.sm),
          if (count != null)
            AnimatedSwitcher(
              duration: Motion.fast,
              child: Text(
                '$count ${count == 1 ? 'screening' : 'screenings'}',
                key: ValueKey(count),
                style: const TextStyle(color: CustomerColors.muted, fontSize: 13),
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterToggle extends StatelessWidget {
  const _FilterToggle({super.key, required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final reduced = Motion.reduced(context);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.md),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 8),
                AnimatedDefaultTextStyle(
                  duration: reduced ? Duration.zero : Motion.medium,
                  style: CcdType.display(
                    15,
                    color: selected ? CustomerColors.ink : CustomerColors.muted,
                    weight: selected ? 600 : 480,
                    spacing: 1.2,
                  ),
                  child: Text(label.toUpperCase()),
                ),
                const SizedBox(height: 5),
                AnimatedContainer(
                  duration: reduced ? Duration.zero : Motion.medium,
                  curve: Motion.easeOut,
                  height: 2,
                  width: selected ? 22 : 0,
                  decoration: const BoxDecoration(gradient: CustomerColors.goldGradient),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Placeholder tickets while the list loads.
class _TicketSkeletons extends StatelessWidget {
  const _TicketSkeletons();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Loading screenings',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.gutter, Space.sm, Space.gutter, 0),
        child: Column(
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: Space.lg),
                child: ContentWidth(
                  child: Material(
                    color: CustomerColors.surface,
                    shape: const TicketBorder(notchX: ScreeningCard.stubWidth),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      height: 132,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(width: ScreeningCard.stubWidth, color: CustomerColors.stub),
                          const Perforation(),
                          const Expanded(
                            child: Padding(
                              padding: EdgeInsets.all(Space.lg),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SkeletonBox(width: 90, height: 10),
                                  SizedBox(height: 10),
                                  SkeletonBox(width: 180, height: 20),
                                  SizedBox(height: 10),
                                  SkeletonBox(width: 140, height: 12),
                                  Spacer(),
                                  SkeletonBox(width: 110, height: 12),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: Space.xxxl),
      child: Column(
        children: [
          Text(
            'An FDCP Cinematheque Centre · Davao City',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: CustomerColors.faint),
          ),
          SizedBox(height: Space.sm),
          DavaoSkyline(height: 48, opacity: 0.07),
        ],
      ),
    );
  }
}
