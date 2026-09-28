import 'package:flutter/material.dart';

import '../navigation.dart';
import '../widgets/page_frame.dart';

/// Temporary page for sections built in later phases (Phase 9–11).
class PlaceholderScreen extends StatelessWidget {
  const PlaceholderScreen({super.key, required this.item});

  final StaffNavItem item;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      title: item.label,
      subtitle: item.summary,
      children: [
        EmptyStateCard(
          icon: item.icon,
          title: 'Not built yet',
          message: 'This section is part of a later development phase.',
        ),
      ],
    );
  }
}
