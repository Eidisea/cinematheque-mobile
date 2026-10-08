import 'package:flutter/material.dart';

/// Staff navigation, grouped by TASK (not one item per database collection) — the same
/// menu as the website's admin. Payment status lives inside Reservations; checking people
/// in at the door lives in Attendance. Seats are fixed at 120, so there is no seat page.
class StaffNavItem {
  const StaffNavItem({required this.label, required this.path, required this.icon, required this.summary});

  final String label;
  final String path;
  final IconData icon;
  final String summary; // what the page is for (shown while the page is not built yet)
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
      label: 'Attendance',
      path: '/attendance',
      icon: Icons.fact_check_outlined,
      summary: 'Screenings, how each one is booked, and admitting moviegoers at the door',
    ),
    StaffNavItem(
      label: 'Reservations',
      path: '/reservations',
      icon: Icons.confirmation_number_outlined,
      summary: 'Find bookings, check payment status, approve or cancel',
    ),
  ]),
  StaffNavSection(title: 'Insights', items: [
    StaffNavItem(
      label: 'Reports',
      path: '/reports',
      icon: Icons.bar_chart_rounded,
      summary: 'Reservations vs. attendance, payments, exports',
    ),
  ]),
  StaffNavSection(title: 'Settings', items: [
    StaffNavItem(
      label: 'Film catalog',
      path: '/settings/films',
      icon: Icons.menu_book_outlined,
      summary: 'Films and posters',
    ),
    StaffNavItem(
      label: 'Staff accounts',
      path: '/settings/staff',
      icon: Icons.person_outline_rounded,
      summary: 'AVT and PDO accounts',
    ),
  ]),
];

Iterable<StaffNavItem> get allStaffNavItems => staffNavigation.expand((s) => s.items);

/// The nav item for a location ("/settings/films/123" → Film catalog).
StaffNavItem navItemFor(String location) {
  StaffNavItem best = allStaffNavItems.first;
  for (final item in allStaffNavItems) {
    final matches = item.path == '/' ? location == '/' : location == item.path || location.startsWith('${item.path}/');
    if (matches && item.path.length >= best.path.length) best = item;
  }
  return best;
}
