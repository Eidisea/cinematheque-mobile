import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';

/// Slim progress indicator for the booking flow (as on the Laravel site):
/// Seats → Details → Pay (paid) / Confirm (free).
class BookingSteps extends StatelessWidget {
  const BookingSteps({super.key, required this.current, required this.paid});

  final int current; // 0, 1 or 2
  final bool paid;

  @override
  Widget build(BuildContext context) {
    final labels = ['Seats', 'Details', paid ? 'Pay' : 'Confirm'];
    return Semantics(
      label: 'Step ${current + 1} of 3: ${labels[current]}',
      excludeSemantics: true,
      child: Row(
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) const SizedBox(width: Space.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: SizedBox(
                      height: 4,
                      child: Stack(
                        children: [
                          const Positioned.fill(child: ColoredBox(color: CustomerColors.border)),
                          Positioned.fill(
                            child: AnimatedFractionallySizedBox(
                              duration: Motion.slow,
                              curve: Motion.easeOut,
                              alignment: Alignment.centerLeft,
                              widthFactor: i <= current ? 1 : 0,
                              heightFactor: 1,
                              child: const DecoratedBox(decoration: BoxDecoration(gradient: CustomerColors.goldGradient)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${i + 1}. ${labels[i]}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: i == current ? FontWeight.w700 : FontWeight.w500,
                      color: i <= current ? CustomerColors.ink : CustomerColors.faint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
