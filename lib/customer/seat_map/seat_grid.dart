import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/seat_layout.dart';
import '../theme/customer_theme.dart';
import 'seat_map_logic.dart';

/// The hall drawn as rows of seats, with a curved screen at the top and row letters on
/// both sides. Seat size adapts to the phone width (the layout has 12 seats per row).
class SeatGrid extends StatelessWidget {
  const SeatGrid({super.key, required this.state, required this.onTap});

  final SeatMapState state;
  final void Function(String label) onTap;

  static const _gap = 5.0;
  static const _rowLabelWidth = 20.0;

  @override
  Widget build(BuildContext context) {
    final rows = state.layout.rows;
    final columns = rows.values.fold<int>(0, (m, r) => r.isEmpty ? m : (r.last.number > m ? r.last.number : m));

    return LayoutBuilder(builder: (context, constraints) {
      final forSeats = constraints.maxWidth - 2 * (_rowLabelWidth + _gap) - (columns - 1) * _gap;
      final seat = (forSeats / columns).clamp(18.0, 38.0);

      return Column(
        children: [
          const _Screen(),
          const SizedBox(height: Space.xl),
          for (final entry in rows.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: _gap + 1),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _RowLabel(entry.key),
                  const SizedBox(width: _gap),
                  for (var n = 1; n <= columns; n++) ...[
                    if (n > 1) const SizedBox(width: _gap),
                    _seatAt(entry.value, n, seat),
                  ],
                  const SizedBox(width: _gap),
                  _RowLabel(entry.key),
                ],
              ),
            ),
        ],
      );
    });
  }

  Widget _seatAt(List<SeatPosition> seatsInRow, int number, double size) {
    for (final s in seatsInRow) {
      if (s.number == number) {
        return _Seat(label: s.label, number: number, status: state.statusOf(s.label), size: size, onTap: onTap);
      }
    }
    return SizedBox.square(dimension: size); // no seat at this position (gap in the layout)
  }
}

const _seatShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.vertical(top: Radius.circular(9), bottom: Radius.circular(4)),
);

class _Seat extends StatelessWidget {
  const _Seat({required this.label, required this.number, required this.status, required this.size, required this.onTap});

  final String label;
  final int number;
  final SeatStatus status;
  final double size;
  final void Function(String) onTap;

  @override
  Widget build(BuildContext context) {
    final selected = status == SeatStatus.selected;
    final tappable = status == SeatStatus.available || selected;
    final stateWord = switch (status) {
      SeatStatus.available => 'available',
      SeatStatus.selected => 'selected',
      SeatStatus.taken => 'taken',
      SeatStatus.unavailable => 'not available',
    };
    final textColor = switch (status) {
      SeatStatus.available => CustomerColors.ink,
      SeatStatus.selected => CustomerColors.ink,
      SeatStatus.taken => CustomerColors.faint,
      SeatStatus.unavailable => const Color(0xFFC4BFC9),
    };

    return Semantics(
      button: tappable,
      selected: selected,
      label: 'Seat $label, $stateWord',
      excludeSemantics: true,
      child: AnimatedScale(
        scale: selected ? 1.08 : 1,
        duration: Motion.fast,
        curve: Curves.easeOutBack,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: size,
          height: size,
          decoration: ShapeDecoration(
            shape: _seatShape.copyWith(
              side: BorderSide(
                color: switch (status) {
                  SeatStatus.available => CustomerColors.borderStrong,
                  SeatStatus.selected => CustomerColors.gold600,
                  _ => Colors.transparent,
                },
                width: 1.2,
              ),
            ),
            color: switch (status) {
              SeatStatus.available => CustomerColors.surface,
              SeatStatus.selected => null,
              SeatStatus.taken => const Color(0xFFE9E6EE),
              SeatStatus.unavailable => CustomerColors.neutralTint,
            },
            gradient: selected ? CustomerColors.goldGradient : null,
            shadows: selected ? const [BoxShadow(color: Color(0x40CC8500), blurRadius: 8, offset: Offset(0, 3))] : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('seat-$label'),
              customBorder: _seatShape,
              onTap: tappable
                  ? () {
                      HapticFeedback.selectionClick();
                      onTap(label);
                    }
                  : null,
              child: CustomPaint(
                painter: status == SeatStatus.taken ? _HatchPainter() : null,
                child: Center(
                  child: status == SeatStatus.unavailable
                      ? Icon(Icons.close_rounded, size: size * 0.45, color: textColor)
                      : size >= 22 && status != SeatStatus.taken
                          ? Text('$number',
                              style: TextStyle(fontSize: size * 0.34, color: textColor, fontWeight: FontWeight.w600, height: 1))
                          : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Diagonal hatching on taken seats — reads as "taken" without relying on colour alone.
class _HatchPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipPath(_seatShape.getOuterPath(Offset.zero & size));
    final p = Paint()
      ..color = const Color(0xFFD3CEDB)
      ..strokeWidth = 1.4;
    for (var x = -size.height; x < size.width; x += 5) {
      canvas.drawLine(Offset(x, size.height), Offset(x + size.height, 0), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.row);

  final String row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SeatGrid._rowLabelWidth,
      child: Text(row,
          textAlign: TextAlign.center,
          style: const TextStyle(fontFamily: 'Oswald', fontSize: 13, fontWeight: FontWeight.w600, color: CustomerColors.faint)),
    );
  }
}

/// A gently curved gold screen with its label — where everyone should be looking.
class _Screen extends StatelessWidget {
  const _Screen();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Column(
        children: [
          SizedBox(height: 26, width: double.infinity, child: CustomPaint(painter: _ScreenPainter())),
          const Text('SCREEN', style: TextStyle(letterSpacing: 5, fontSize: 10.5, fontWeight: FontWeight.w600, color: CustomerColors.faint)),
        ],
      ),
    );
  }
}

class _ScreenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final curve = Path()
      ..moveTo(w * 0.06, h * 0.9)
      ..quadraticBezierTo(w / 2, -h * 0.4, w * 0.94, h * 0.9);
    final rect = Offset.zero & size;
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..color = const Color(0x22EBBC00)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawPath(
      curve,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..shader = CustomerColors.goldGradient.createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Explains the seat states.
class SeatLegend extends StatelessWidget {
  const SeatLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(Widget swatch, String text) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [swatch, const SizedBox(width: 6), Text(text, style: const TextStyle(fontSize: 12.5, color: CustomerColors.muted))],
        );
    Widget box({Color? color, Gradient? gradient, Color border = Colors.transparent, bool hatch = false}) => Container(
          width: 16,
          height: 16,
          decoration: ShapeDecoration(
            shape: _seatShape.copyWith(side: BorderSide(color: border, width: 1.2)),
            color: color,
            gradient: gradient,
          ),
          child: hatch ? CustomPaint(painter: _HatchPainter()) : null,
        );

    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 18,
      runSpacing: 8,
      children: [
        item(box(color: CustomerColors.surface, border: CustomerColors.borderStrong), 'Available'),
        item(box(gradient: CustomerColors.goldGradient, border: CustomerColors.gold600), 'Selected'),
        item(box(color: const Color(0xFFE9E6EE), hatch: true), 'Taken'),
      ],
    );
  }
}
