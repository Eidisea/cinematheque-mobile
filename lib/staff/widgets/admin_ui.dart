import 'package:flutter/material.dart';

import '../../data/models/reservation.dart';
import '../../data/models/screening.dart';
import '../theme/staff_theme.dart';

// Building blocks of the website's admin, shared by the staff pages.

/// A bold number with a quiet label ("12 upcoming screenings"), optionally a link.
class Figure extends StatelessWidget {
  const Figure(this.value, this.label, {super.key, this.onTap});

  final String value;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final text = Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: '$value ',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: StaffColors.text,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          TextSpan(
            text: label,
            style: const TextStyle(fontSize: 13, color: StaffColors.textMuted),
          ),
        ],
      ),
    );
    return onTap == null ? text : InkWell(onTap: onTap, child: text);
  }
}

/// A section: an uppercase gray heading (with an optional count and link), then content.
class AdminSection extends StatelessWidget {
  const AdminSection({super.key, required this.title, required this.child, this.trailing, this.count = 0});

  final String title;
  final Widget child;
  final Widget? trailing;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Semantics(
              header: true,
              child: Text(
                title.toUpperCase(),
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.56,
                  color: StaffColors.gray600,
                ),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                constraints: const BoxConstraints(minWidth: 20),
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  color: StaffColors.warningTint,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: StaffColors.warningBorder),
                ),
                child: Text(
                  '$count',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w600, color: StaffColors.warning),
                ),
              ),
            ],
            const Spacer(),
            ?trailing,
          ],
        ),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

class TextLink extends StatelessWidget {
  const TextLink(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Text(label, style: const TextStyle(fontSize: 13, color: StaffColors.brand)),
  );
}

class QuietText extends StatelessWidget {
  const QuietText(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(text, style: const TextStyle(color: StaffColors.textMuted)),
  );
}

/// An inline message: warning (amber) or error (red).
class Notice extends StatelessWidget {
  const Notice(this.text, {super.key, this.tone = Tone.error, this.title});

  final String text;
  final String? title;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text.rich(
        TextSpan(
          style: TextStyle(color: fg),
          children: [
            if (title != null)
              TextSpan(
                text: '$title ',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            TextSpan(text: text),
          ],
        ),
      ),
    );
  }
}

/// White box with a thin border; children separated by lines.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: StaffColors.surface,
        border: Border.all(color: StaffColors.border),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1), children[i]],
        ],
      ),
    );
  }
}

/// A thin 56 px bar showing how full something is.
class FillBar extends StatelessWidget {
  const FillBar({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: SizedBox(
        width: 56,
        height: 4,
        child: Stack(
          children: [
            const Positioned.fill(child: ColoredBox(color: StaffColors.gray200)),
            FractionallySizedBox(
              widthFactor: fraction.clamp(0.0, 1.0),
              child: const ColoredBox(color: StaffColors.gray600),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small uppercase label above a list ("To approve").
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.48, color: StaffColors.textMuted),
    ),
  );
}

enum Tone { success, warning, error, neutral }

(Color fg, Color bg, Color border) toneColors(Tone tone) => switch (tone) {
  Tone.success => (StaffColors.success, StaffColors.successTint, StaffColors.successBorder),
  Tone.warning => (StaffColors.warning, StaffColors.warningTint, StaffColors.warningBorder),
  Tone.error => (StaffColors.danger, StaffColors.dangerTint, StaffColors.dangerBorder),
  Tone.neutral => (StaffColors.gray700, StaffColors.gray100, StaffColors.border),
};

/// A booking's state in the website admin's words.
(String, Tone) bookingState(Reservation r, DateTime now, {bool refundDue = false}) {
  final paid = r.screening.type == ScreeningType.paid;
  final expired =
      r.cancellationReason == CancellationReason.paymentExpired ||
      (r.status == ReservationStatus.pending && paid && !(r.expiresAt?.isAfter(now) ?? false));
  if (r.status == ReservationStatus.cancelled && refundDue) return ('Refund due', Tone.error);
  if (expired) return ('Expired · not paid', Tone.neutral);
  return switch (r.status) {
    ReservationStatus.cancelled => ('Cancelled', Tone.neutral),
    ReservationStatus.confirmed => (paid ? 'Approved · paid' : 'Approved', Tone.success),
    ReservationStatus.pending => (paid ? 'Awaiting payment' : 'Awaiting approval', Tone.warning),
  };
}

/// Staff may approve a pending FREE booking whose screening has not started.
bool canApprove(Reservation r, DateTime now) =>
    r.status == ReservationStatus.pending && r.screening.type == ScreeningType.free && r.screening.startAt.isAfter(now);

/// A small state label with a dot (green / amber / red / gray).
class StateLabel extends StatelessWidget {
  const StateLabel(this.label, this.tone, {super.key});

  final String label;
  final Tone tone;

  @override
  Widget build(BuildContext context) {
    final (fg, bg, border) = toneColors(tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: bg,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: fg, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 18 / 12, fontWeight: FontWeight.w500, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// "15h ago", as the website shows it.
String timeAgo(DateTime then, DateTime now) {
  final d = now.difference(then);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes}m ago';
  if (d.inDays < 1) return '${d.inHours}h ago';
  if (d.inDays < 7) return '${d.inDays}d ago';
  return '${d.inDays ~/ 7}w ago';
}

/// Small purple primary button (Approve) and its outline variants.
class AdminButton extends StatelessWidget {
  const AdminButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.kind = AdminButtonKind.primary,
    this.small = false,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final AdminButtonKind kind;
  final bool small;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final height = small ? 28.0 : 36.0;
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(8));
    final text = TextStyle(fontFamily: 'Geist', fontSize: small ? 13 : 14, fontWeight: FontWeight.w600);
    final padding = EdgeInsets.symmetric(horizontal: small ? 10 : 14);
    final child = busy
        ? SizedBox.square(
            dimension: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: kind == AdminButtonKind.primary ? Colors.white : null),
          )
        : Text(label);
    final onTap = busy ? null : onPressed;
    return SizedBox(
      height: height,
      child: switch (kind) {
        AdminButtonKind.primary => FilledButton(
          style: FilledButton.styleFrom(minimumSize: Size(0, height), padding: padding, shape: shape, textStyle: text),
          onPressed: onTap,
          child: child,
        ),
        AdminButtonKind.secondary => OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, height),
            padding: padding,
            shape: shape,
            textStyle: text,
            foregroundColor: StaffColors.gray700,
            side: const BorderSide(color: StaffColors.borderStrong),
          ),
          onPressed: onTap,
          child: child,
        ),
        AdminButtonKind.danger => OutlinedButton(
          style: OutlinedButton.styleFrom(
            minimumSize: Size(0, height),
            padding: padding,
            shape: shape,
            textStyle: text,
            foregroundColor: StaffColors.danger,
            side: const BorderSide(color: StaffColors.dangerBorder),
          ),
          onPressed: onTap,
          child: child,
        ),
      },
    );
  }
}

enum AdminButtonKind { primary, secondary, danger }

/// The website's quick filters: separate pill chips ("All 4", "To approve 1", …); the
/// current one is filled dark.
class FilterChips<T> extends StatelessWidget {
  const FilterChips({super.key, required this.values, required this.current, required this.label, required this.onSelect, this.count});

  final List<T> values;
  final T current;
  final String Function(T) label;
  final int Function(T)? count;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final v in values)
          Builder(builder: (context) {
            final on = v == current;
            final fg = on ? Colors.white : StaffColors.gray700;
            return Semantics(
              button: true,
              selected: on,
              child: Material(
                color: on ? const Color(0xFF1F2937) : StaffColors.surface,
                shape: StadiumBorder(side: BorderSide(color: on ? const Color(0xFF1F2937) : StaffColors.borderStrong)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => onSelect(v),
                  child: Container(
                    height: 32,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(label(v), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: fg)),
                        if (count != null) ...[
                          const SizedBox(width: 6),
                          Text('${count!(v)}',
                              style: TextStyle(
                                  fontSize: 12, color: fg.withValues(alpha: 0.7), fontFeatures: const [FontFeature.tabularFigures()])),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),
      ],
    );
  }
}

/// The website's search box (34 px, with a magnifier).
class SearchField extends StatelessWidget {
  const SearchField({super.key, required this.controller, required this.hint, required this.onChanged, this.width = 280});

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: 34,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: const Icon(Icons.search, size: 18, color: StaffColors.gray400),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
      ),
    );
  }
}

/// Back link above a page title ("← Attendance").
class BackLink extends StatelessWidget {
  const BackLink(this.label, {super.key, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.arrow_back, size: 15, color: StaffColors.textMuted),
            const SizedBox(width: 6),
            Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: StaffColors.textMuted)),
          ],
        ),
      ),
    );
  }
}

/// A page title (22 px, as on the website).
class PageTitle extends StatelessWidget {
  const PageTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) =>
      Semantics(header: true, child: Text(text, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, height: 1.3)));
}

/// A yes/no question before something that cannot be undone. → true when confirmed.
Future<bool> confirmAction(BuildContext context,
    {required String title, required String message, required String confirm, bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep it')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: StaffColors.danger) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Shows [message] in place of any message already showing.
void showMessage(BuildContext context, String message) => ScaffoldMessenger.of(context)
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message)));
