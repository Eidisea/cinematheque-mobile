import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';
import 'brand.dart';

/// Title block for the tab pages: gold eyebrow + condensed uppercase title (+ lead).
class PageHeader extends StatelessWidget {
  const PageHeader({super.key, required this.eyebrow, required this.title, this.lead, this.trailing});

  final String eyebrow;
  final String title;
  final String? lead;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(Space.gutter, MediaQuery.paddingOf(context).top + Space.xl, Space.gutter, Space.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Eyebrow(eyebrow),
                const SizedBox(height: 4),
                Semantics(header: true, child: Text(title.toUpperCase(), style: CcdType.display(34, spacing: 1))),
                if (lead != null) ...[
                  const SizedBox(height: Space.sm),
                  Text(lead!, style: const TextStyle(color: CustomerColors.muted, fontSize: 14, height: 1.45)),
                ],
              ],
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
