import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/screening.dart';
import '../../data/models/staff_member.dart';
import '../auth/staff_session.dart';
import '../navigation.dart';
import '../staff_services.dart';
import '../theme/staff_theme.dart';

/// Layout around every signed-in page, as on the website's admin: a dark sidebar with the
/// grouped navigation, and a slim top bar with the account menu.
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
        _TopBar(session: session, showMenuButton: !isWide),
        Expanded(child: child),
      ],
    );

    if (isWide) {
      return Scaffold(
        body: Row(
          children: [
            SizedBox(width: 224, child: _Sidebar(current: current)),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Scaffold(
      drawer: Drawer(
        width: 248,
        backgroundColor: StaffColors.sideBg,
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
    final services = StaffServices.of(context);
    return Material(
      color: StaffColors.sideBg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(10, 16, 10, 16),
          children: [
            const _Brand(),
            for (final section in staffNavigation) ...[
              if (section.title != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 16, 10, 4),
                  child: Text(
                    section.title!.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.66, color: StaffColors.sideMuted),
                  ),
                ),
              for (final item in section.items)
                _NavTile(
                  item: item,
                  selected: item.path == current.path,
                  // Free reservations waiting for approval, as on the website.
                  count: item.path == '/reservations'
                      ? StreamBuilder(
                          stream: services.data.watchPendingReservations(),
                          builder: (context, snap) {
                            final now = services.clock.now();
                            final n = (snap.data ?? const [])
                                .where((r) => r.screening.type == ScreeningType.free && r.screening.startAt.isAfter(now))
                                .length;
                            return n == 0 ? const SizedBox.shrink() : _Count(n);
                          },
                        )
                      : null,
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

/// The website admin's mark: a dark tile with a gold film frame and a mountain ridge.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 16),
      child: Row(
        children: [
          SizedBox.square(dimension: 30, child: CustomPaint(painter: _BrandPainter())),
          const SizedBox(width: 10),
          const Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CINEMATHEQUE',
                      style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.8)),
                  Text('Centre Davao', style: TextStyle(color: StaffColors.sideMuted, fontSize: 11)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 40;
    canvas.scale(k);
    canvas.drawRRect(RRect.fromLTRBR(1, 1, 39, 39, const Radius.circular(9)), Paint()..color = const Color(0xFF1F2937));
    canvas.drawRRect(
      RRect.fromLTRBR(7, 9, 33, 31, const Radius.circular(4)),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = StaffColors.gold,
    );
    final ridge = Path()
      ..moveTo(11, 27)
      ..lineTo(16, 19)
      ..lineTo(19, 23)
      ..lineTo(23, 15)
      ..lineTo(29, 27)
      ..close();
    canvas.drawPath(ridge, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Count extends StatelessWidget {
  const _Count(this.n);

  final int n;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(color: StaffColors.count, borderRadius: BorderRadius.circular(999)),
      child: Text('$n',
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.white, fontSize: 11, height: 18 / 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _NavTile extends StatefulWidget {
  const _NavTile({required this.item, required this.selected, required this.onTap, this.count});

  final StaffNavItem item;
  final bool selected;
  final VoidCallback onTap;
  final Widget? count;

  @override
  State<_NavTile> createState() => _NavTileState();
}

class _NavTileState extends State<_NavTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;
    final color = selected || _hover ? Colors.white : StaffColors.sideFg;
    final count = widget.count;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Semantics(
        selected: selected,
        button: true,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: selected ? StaffColors.sideActive : (_hover ? StaffColors.sideHover : Colors.transparent),
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: widget.onTap,
                onHover: (h) => setState(() => _hover = h),
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: Row(
                    children: [
                      Icon(widget.item.icon, size: 17, color: color.withValues(alpha: 0.85)),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(widget.item.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: color, fontSize: 14, fontWeight: selected ? FontWeight.w500 : FontWeight.w400)),
                      ),
                      ?count,
                    ],
                  ),
                ),
              ),
            ),
            if (selected)
              const Positioned(
                left: -10,
                top: 6,
                bottom: 6,
                child: SizedBox(
                  width: 3,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.horizontal(right: Radius.circular(3)),
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

class _TopBar extends StatelessWidget {
  const _TopBar({required this.session, required this.showMenuButton});

  final StaffSession session;
  final bool showMenuButton;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: StaffColors.surface,
      child: SafeArea(
        bottom: false,
        child: Container(
          height: 56,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: StaffColors.border))),
          child: Row(
            children: [
              if (showMenuButton)
                IconButton(
                  tooltip: 'Open navigation',
                  style: IconButton.styleFrom(
                    foregroundColor: StaffColors.gray700,
                    side: const BorderSide(color: StaffColors.borderStrong),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  icon: const Icon(Icons.menu, size: 20),
                  onPressed: () => Scaffold.of(context).openDrawer(),
                ),
              const Spacer(),
              _UserMenu(session: session),
            ],
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
              backgroundColor: StaffColors.brand,
              child: Text(initials, style: const TextStyle(fontSize: 12, color: Colors.white, fontWeight: FontWeight.w600)),
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
