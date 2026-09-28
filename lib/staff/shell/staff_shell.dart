import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/staff_member.dart';
import '../auth/staff_session.dart';
import '../navigation.dart';
import '../theme/staff_theme.dart';

/// Layout around every signed-in page: sidebar navigation + top bar with the user menu.
/// Wide screens (≥ 1024 px) keep the sidebar open; narrower screens use a drawer.
class StaffShell extends StatelessWidget {
  const StaffShell({super.key, required this.session, required this.location, required this.child});

  static const wideBreakpoint = 1024.0;

  final StaffSession session;
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.sizeOf(context).width >= wideBreakpoint;
    final current = navItemFor(location);

    final content = Column(
      children: [
        _TopBar(session: session, title: current.label, showMenuButton: !isWide),
        const Divider(),
        Expanded(child: child),
      ],
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 248, child: _Sidebar(current: current)),
            const VerticalDivider(width: 1),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      drawer: Drawer(
        width: 272,
        shape: const RoundedRectangleBorder(),
        child: _Sidebar(current: current, closeOnTap: true),
      ),
      body: content,
    );
  }
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.current, this.closeOnTap = false});

  final StaffNavItem current;
  final bool closeOnTap;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Material(
      color: StaffColors.surface,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 20),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cinematheque',
                      style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700, color: StaffColors.brand)),
                  Text('Centre Davao · Staff', style: textTheme.bodySmall?.copyWith(color: StaffColors.textMuted)),
                ],
              ),
            ),
            for (final section in staffNavigation) ...[
              if (section.title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 16, 12, 6),
                  child: Text(
                    section.title!.toUpperCase(),
                    style: textTheme.labelSmall?.copyWith(color: StaffColors.textMuted, letterSpacing: 0.8),
                  ),
                ),
              for (final item in section.items)
                _NavTile(
                  item: item,
                  selected: item.path == current.path,
                  onTap: () {
                    if (closeOnTap) Navigator.of(context).pop();
                    context.go(item.path);
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({required this.item, required this.selected, required this.onTap});

  final StaffNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? StaffColors.brand : StaffColors.text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        selected: selected,
        button: true,
        child: Material(
          color: selected ? StaffColors.brandTint : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: onTap,
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: selected
                  ? const BoxDecoration(border: Border(left: BorderSide(color: StaffColors.gold, width: 3)))
                  : null,
              child: Row(
                children: [
                  Icon(item.icon, size: 20, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: color, fontWeight: selected ? FontWeight.w600 : FontWeight.w500)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session, required this.title, required this.showMenuButton});

  final StaffSession session;
  final String title;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StaffColors.surface,
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 60,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                if (showMenuButton)
                  IconButton(
                    tooltip: 'Open navigation',
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                ),
                _UserMenu(session: session),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UserMenu extends StatelessWidget {
  const _UserMenu({required this.session});

  final StaffSession session;

  @override
  Widget build(BuildContext context) {
    final staff = session.staff;
    if (staff == null) return const SizedBox.shrink();
    final initials = '${staff.firstName[0]}${staff.lastName[0]}'.toUpperCase();

    return PopupMenuButton<String>(
      tooltip: 'Account',
      position: PopupMenuPosition.under,
      onSelected: (value) {
        if (value == 'signOut') session.signOut();
      },
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(staff.fullName, style: const TextStyle(fontWeight: FontWeight.w600, color: StaffColors.text)),
              Text('${staff.position.dbValue} · ${staff.email}',
                  style: const TextStyle(fontSize: 12, color: StaffColors.textMuted)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(
          value: 'signOut',
          child: Row(children: [Icon(Icons.logout, size: 18), SizedBox(width: 10), Text('Sign out')]),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: StaffColors.brandTint,
              child: Text(initials, style: const TextStyle(fontSize: 12, color: StaffColors.brand, fontWeight: FontWeight.w700)),
            ),
            if (MediaQuery.sizeOf(context).width >= 600) ...[
              const SizedBox(width: 8),
              Text(staff.firstName, style: const TextStyle(fontWeight: FontWeight.w500)),
            ],
            const Icon(Icons.expand_more, size: 18, color: StaffColors.textMuted),
          ],
        ),
      ),
    );
  }
}
