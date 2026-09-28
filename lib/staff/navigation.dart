import 'package:flutter/material.dart';

/// Staff navigation, grouped by TASK (not one item per database collection).
/// Payment status lives inside Reservations; the admission checklist lives in Admission.
class StaffNavItem {
  const StaffNavItem({required this.label, required this.path, required this.icon, required this.summary});

  final String label;
  final String path;
  final IconData icon;
  final String summary; // shown on the page header
}

class StaffNavSection {
  const StaffNavSection({this.title, required this.items});

  final String? title;
  final List<StaffNavItem> items;
}

const staffNavigation = <StaffNavSection>[
  StaffNavSection(items: [
    StaffNavItem(
      label: 'Dashboard',
      path: '/',
      icon: Icons.space_dashboard_outlined,
      summary: 'Today at Cinematheque Centre Davao',
    ),
  ]),
  StaffNavSection(title: 'Operations', items: [
    StaffNavItem(
      label: 'Screenings',
      path: '/screenings',
      icon: Icons.event_outlined,
      summary: 'Schedule screenings and see how each one is booked',
    ),
    StaffNavItem(
      label: 'Reservations',
      path: '/reservations',
      icon: Icons.confirmation_number_outlined,
      summary: 'Find bookings, check payment status, approve or cancel',
    ),
    StaffNavItem(
      label: 'Admission',
      path: '/admission',
      icon: Icons.how_to_reg_outlined,
      summary: 'Admit moviegoers at the door and record attendance',
    ),
  ]),
  StaffNavSection(title: 'Insights', items: [
    StaffNavItem(
      label: 'Reports',
      path: '/reports',
      icon: Icons.insights_outlined,
      summary: 'Reservations vs. attendance, payments, exports',
    ),
  ]),
  StaffNavSection(title: 'Settings', items: [
    StaffNavItem(
      label: 'Movies',
      path: '/settings/movies',
      icon: Icons.movie_outlined,
      summary: 'Film catalog and posters',
    ),
    StaffNavItem(
      label: 'Seat layout',
      path: '/settings/seats',
      icon: Icons.event_seat_outlined,
      summary: 'The 120-seat hall layout',
    ),
    StaffNavItem(
      label: 'Staff accounts',
      path: '/settings/staff',
      icon: Icons.badge_outlined,
      summary: 'AVT and PDO accounts',
    ),
  ]),
];

Iterable<StaffNavItem> get allStaffNavItems => staffNavigation.expand((s) => s.items);

/// The nav item for a location ("/settings/movies/123" → Movies).
StaffNavItem navItemFor(String location) {
  StaffNavItem best = allStaffNavItems.first;
  for (final item in allStaffNavItems) {
    final matches = item.path == '/' ? location == '/' : location == item.path || location.startsWith('${item.path}/');
    if (matches && item.path.length >= best.path.length) best = item;
  }
  return best;
}
