import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../theme/customer_theme.dart';
import 'ccd_nav_bar.dart';

/// The three destinations, exactly: Find my booking · Screenings · About.
/// Screenings sits in the middle and is where the app opens. Each tab keeps its own
/// scroll position and history when you switch away and back.
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const items = [
    CcdNavItem(label: 'Find my booking', icon: CcdNavGlyph.ticket),
    CcdNavItem(label: 'Screenings', icon: CcdNavGlyph.film, primary: true),
    CcdNavItem(label: 'About', icon: CcdNavGlyph.reel),
  ];

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> with SingleTickerProviderStateMixin {
  // Switching tabs: the new page fades in while rising 8px, in step with the nav rule.
  late final AnimationController _enter = AnimationController(vsync: this, duration: const Duration(milliseconds: 260), value: 1);
  late final Animation<double> _t = CurvedAnimation(parent: _enter, curve: Motion.easeOut);

  @override
  void didUpdateWidget(CustomerShell old) {
    super.didUpdateWidget(old);
    if (old.shell.currentIndex != widget.shell.currentIndex && !Motion.reduced(context)) {
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _enter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;
    return Scaffold(
      body: AnimatedBuilder(
        animation: _t,
        builder: (context, child) => Opacity(
          opacity: _t.value,
          child: Transform.translate(offset: Offset(0, 8 * (1 - _t.value)), child: child),
        ),
        child: shell,
      ),
      bottomNavigationBar: CcdNavBar(
        items: CustomerShell.items,
        currentIndex: shell.currentIndex,
        // Tapping the current tab again returns it to its first page.
        onSelected: (index) => shell.goBranch(index, initialLocation: index == shell.currentIndex),
      ),
    );
  }
}
