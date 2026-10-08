import 'package:flutter/material.dart';

import '../../data/models/screening.dart';
import '../theme/customer_theme.dart';
import 'brand.dart';

/// A 2:3 movie poster. Without a real poster (or if it fails to load) the generated
/// Cinematheque poster art is shown — never an invented image.
class PosterImage extends StatelessWidget {
  const PosterImage({super.key, required this.url, required this.title, required this.width, this.showTitle = true});

  final String? url;
  final String title;
  final double width;
  final bool showTitle;

  @override
  Widget build(BuildContext context) {
    final height = width * 1.5;
    final art = SizedBox(
      width: width,
      height: height,
      // Caption scales with the poster so long words don't break mid-word.
      child: GeneratedPosterArt(seed: title, title: showTitle && width >= 100 ? title : null, titleSize: width * 0.12),
    );

    return Semantics(
      label: url == null ? 'No poster available' : 'Poster for $title',
      image: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(width < 100 ? Radii.sm : Radii.lg),
          boxShadow: const [BoxShadow(color: Color(0x33141219), blurRadius: 24, offset: Offset(0, 12))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(width < 100 ? Radii.sm : Radii.lg),
          child: url == null
              ? art
              : Image.network(
                  url!,
                  width: width,
                  height: height,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stack) => art,
                  // Generated art until the real poster's first frame arrives, then a short fade.
                  frameBuilder: (context, child, frame, sync) =>
                      sync ? child : AnimatedSwitcher(duration: Motion.medium, child: frame == null ? art : child),
                ),
        ),
      ),
    );
  }
}

/// The poster resting on the website's gold offset block.
class PosterOnBlock extends StatelessWidget {
  const PosterOnBlock({super.key, required this.screening, required this.width, this.offset = 10});

  final Screening screening;
  final double width;
  final double offset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(right: offset, bottom: offset),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: offset,
            top: offset,
            right: -offset,
            bottom: -offset,
            child: DecoratedBox(
              decoration: BoxDecoration(color: CustomerColors.gold, borderRadius: BorderRadius.circular(Radii.md)),
            ),
          ),
          PosterImage(url: screening.movie?.posterUrl, title: screening.movie?.title ?? screening.eventTitle, width: width),
        ],
      ),
    );
  }
}
