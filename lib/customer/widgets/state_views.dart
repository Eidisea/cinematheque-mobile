import 'package:flutter/material.dart';

import '../theme/customer_theme.dart';

/// Consistent loading / empty / error screens for the customer app.

class LoadingView extends StatelessWidget {
  const LoadingView({super.key, this.label = 'Loading…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 2.6)),
            const SizedBox(height: Space.lg),
            Text(label, style: const TextStyle(color: CustomerColors.muted)),
          ],
        ),
      ),
    );
  }
}

class MessageView extends StatelessWidget {
  const MessageView({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl, vertical: Space.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Open, not boxed: a quiet icon, a short gold rule, then the words.
              Icon(icon, size: 30, color: CustomerColors.faint),
              const SizedBox(height: Space.md),
              Container(width: 28, height: 2, color: CustomerColors.gold600),
              const SizedBox(height: Space.lg),
              Text(title, textAlign: TextAlign.center, style: CcdType.display(TypeScale.s + 2, spacing: 0.6)),
              const SizedBox(height: Space.sm),
              Text(message, textAlign: TextAlign.center, style: const TextStyle(color: CustomerColors.muted, height: 1.5)),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: Space.xl),
                OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.onRetry, this.message});

  final VoidCallback onRetry;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return MessageView(
      icon: Icons.wifi_off_rounded,
      title: "Couldn't load this",
      message: message ?? 'Check your internet connection and try again.',
      actionLabel: 'Try again',
      onAction: onRetry,
    );
  }
}

/// Keeps content at a comfortable width on tablets / large phones in landscape.
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, this.maxWidth = 640});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    // heightFactor: 1 → only as tall as the content (a plain Center would expand to fill
    // all available height, e.g. taking over the whole screen in a bottom bar).
    return Center(
      heightFactor: 1,
      child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
    );
  }
}

/// Sticky bottom action area used by booking steps: white, hairline top, safe-area aware.
class BottomActionBar extends StatelessWidget {
  const BottomActionBar({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: CustomerColors.surface,
        border: Border(top: BorderSide(color: CustomerColors.border)),
        boxShadow: [BoxShadow(color: Color(0x14141219), blurRadius: 20, offset: Offset(0, -6))],
      ),
      child: SafeArea(
        top: false,
        child: ContentWidth(
          child: Padding(padding: const EdgeInsets.fromLTRB(Space.gutter, Space.md, Space.gutter, Space.md), child: child),
        ),
      ),
    );
  }
}

/// Page-coloured strip behind the status bar, so scrolled content never runs under
/// the clock on pages without an app bar. [opacity] lets a page fade it in once its
/// own opening (which is designed to sit behind the status bar) has scrolled away.
class StatusBarScrim extends StatelessWidget {
  const StatusBarScrim({super.key, this.opacity = 1});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return Positioned(
      left: 0,
      right: 0,
      top: 0,
      height: top,
      child: IgnorePointer(
        child: Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: const ColoredBox(color: CustomerColors.background),
        ),
      ),
    );
  }
}
