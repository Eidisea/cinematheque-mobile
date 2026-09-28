import 'package:flutter/material.dart';

import '../auth/staff_session.dart';
import '../navigation.dart';
import '../widgets/page_frame.dart';

/// Dashboard shell. Real summaries (today's screenings, bookings to approve, payments,
/// admissions) are added once that data exists (Phase 9). No placeholder numbers.
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.session});

  final StaffSession session;

  @override
  Widget build(BuildContext context) {
    final name = session.staff?.firstName;
    final dashboard = allStaffNavItems.first;

    return PageFrame(
      title: name == null ? 'Dashboard' : 'Welcome, $name',
      subtitle: dashboard.summary,
      children: const [
        EmptyStateCard(
          icon: Icons.space_dashboard_outlined,
          title: 'Summaries will appear here',
          message: "Today's screenings, bookings to approve, payment status and admissions "
              'are added in a later phase.',
        ),
      ],
    );
  }
}
