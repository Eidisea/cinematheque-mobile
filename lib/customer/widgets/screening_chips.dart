import 'package:flutter/material.dart';

import '../../core/formatting.dart';
import '../../data/models/screening.dart';
import '../theme/customer_theme.dart';

/// Small rounded label for price / seats / status.
class InfoChip extends StatelessWidget {
  const InfoChip({super.key, required this.label, required this.foreground, required this.background, this.icon, this.money = false});

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;
  final bool money; // prices use Oswald (Poppins has no ₱)

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(Radii.pill)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 14, color: foreground), const SizedBox(width: 5)],
          Text(
            label,
            style: money
                ? CcdType.money(14.5, color: foreground)
                : TextStyle(color: foreground, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// "Free" or "₱150".
class PriceChip extends StatelessWidget {
  const PriceChip({super.key, required this.screening});

  final Screening screening;

  @override
  Widget build(BuildContext context) {
    return screening.isPaid
        ? InfoChip(
            label: formatPeso(screening.priceCentavos ?? 0),
            foreground: CustomerColors.ink,
            background: CustomerColors.goldTint,
            money: true,
          )
        : const InfoChip(label: 'Free', foreground: CustomerColors.success, background: CustomerColors.successTint);
  }
}

enum Availability { open, fewLeft, soldOut, closed }

/// Few seats left = 10 or fewer.
Availability availabilityOf(Screening s, DateTime now) {
  if (!s.isBookableAt(now)) return Availability.closed;
  final left = s.availableSeatsAt(now);
  if (left == 0) return Availability.soldOut;
  return left <= 10 ? Availability.fewLeft : Availability.open;
}

/// "117 seats left", "3 seats left", "Sold out", "Booking closed" — as a chip.
class SeatsChip extends StatelessWidget {
  const SeatsChip({super.key, required this.screening, required this.now});

  final Screening screening;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final (label, fg, bg) = seatsLabel(screening, now);
    return InfoChip(label: label, icon: Icons.event_seat_outlined, foreground: fg, background: bg);
  }
}

/// Text + colours describing availability, shared by chips and ticket lines.
(String, Color, Color) seatsLabel(Screening s, DateTime now) {
  final left = s.availableSeatsAt(now);
  final seatsText = '$left ${left == 1 ? 'seat' : 'seats'} left';
  return switch (availabilityOf(s, now)) {
    Availability.open => (seatsText, CustomerColors.muted, CustomerColors.neutralTint),
    Availability.fewLeft => (seatsText, CustomerColors.warning, CustomerColors.warningTint),
    Availability.soldOut => ('Sold out', CustomerColors.danger, CustomerColors.dangerTint),
    Availability.closed => ('Booking closed', CustomerColors.muted, CustomerColors.neutralTint),
  };
}
