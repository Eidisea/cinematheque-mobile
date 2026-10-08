import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/models/seat_layout.dart';
import '../theme/customer_theme.dart';
import 'seat_map_logic.dart';

// Seat colours, as on the website's seat map.
const _seatBorder = Color(0xFFCDC7BC);
const _seatTaken = Color(0xFFEBE8E2);
const _exitRed = Color(0xFFD92D20);

/// The hall as on the website: the curved screen, rows A–J with their letters on both
/// sides, an EXIT on each side in line with row B, and the entrance at the back.
/// Seats shrink to fit narrow phones (up to 30 px wide, 26 px tall).
class SeatGrid extends StatelessWidget {
  const SeatGrid({super.key, required this.state, required this.onTap});

  final SeatMapState state;
  final void Function(String label) onTap;

  static const _gap = 4.0;
  static const _labelWidth = 12.0;
  static const _exitWidth = 14.0;
  static const _exitRowIndex = 1; // row B

  @override
  Widget build(BuildContext context) {
    final rows = state.layout.rows;
    final columns = rows.values.fold<int>(0, (m, r) => r.isEmpty ? m : (r.last.number > m ? r.last.number : m));

    return LayoutBuilder(
      builder: (context, constraints) {
        final gaps = (columns + 3) * _gap; // between: exit | label | seats… | label | exit
        final forSeats = constraints.maxWidth - 2 * (_exitWidth + _labelWidth) - gaps;
        final seatWidth = (forSeats / columns).clamp(12.0, 30.0);
        var index = 0;

        return Column(
          children: [
            const _ScreenBar(),
            const SizedBox(height: 24),
            for (final entry in rows.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: _gap),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _ExitSlot(show: index == _exitRowIndex),
                    const SizedBox(width: _gap),
                    _RowLabel(entry.key),
                    for (var n = 1; n <= columns; n++) ...[const SizedBox(width: _gap), _seatAt(entry.value, n, seatWidth)],
                    const SizedBox(width: _gap),
                    _RowLabel(entry.key),
                    const SizedBox(width: _gap),
                    _ExitSlot(show: index++ == _exitRowIndex),
                  ],
                ),
              ),
            const SizedBox(height: 22),
            const _Entrance(),
          ],
        );
      },
    );
  }

  Widget _seatAt(List<SeatPosition> seatsInRow, int number, double width) {
    for (final s in seatsInRow) {
      if (s.number == number) {
        return _Seat(label: s.label, number: number, status: state.statusOf(s.label), width: width, onTap: onTap);
      }
    }
    return SizedBox(width: width, height: _Seat.height); // no seat at this position (gap in the layout)
  }
}

const _seatRadius = BorderRadius.only(
  topLeft: Radius.circular(7),
  topRight: Radius.circular(7),
  bottomLeft: Radius.circular(4),
  bottomRight: Radius.circular(4),
);

class _Seat extends StatelessWidget {
  const _Seat({required this.label, required this.number, required this.status, required this.width, required this.onTap});

  final String label;
  final int number;
  final SeatStatus status;
  final double width;
  final void Function(String) onTap;

  static const height = 26.0;

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
    final (Color fill, Color border, Color text) = switch (status) {
      SeatStatus.available => (CustomerColors.surface, _seatBorder, CustomerColors.muted),
      SeatStatus.selected => (CustomerColors.gold, CustomerColors.gold600, CustomerColors.ink),
      SeatStatus.taken => (_seatTaken, Colors.transparent, CustomerColors.faint),
      SeatStatus.unavailable => (CustomerColors.neutralTint, Colors.transparent, CustomerColors.faint),
    };
    final dimmed = status == SeatStatus.taken || status == SeatStatus.unavailable;

    return Semantics(
      button: tappable,
      selected: selected,
      label: 'Seat $label, $stateWord',
      excludeSemantics: true,
      child: Opacity(
        opacity: dimmed ? 0.75 : 1,
        child: AnimatedContainer(
          duration: Motion.fast,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: _seatRadius,
            border: Border.all(color: border, width: 1.5),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              key: ValueKey('seat-$label'),
              borderRadius: _seatRadius,
              onTap: tappable
                  ? () {
                      HapticFeedback.selectionClick();
                      onTap(label);
                    }
                  : null,
              child: Center(
                // Taken seats keep their number, struck through, so all seats always show.
                child: status == SeatStatus.unavailable
                    ? Icon(Icons.close_rounded, size: 12, color: text)
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          '$number',
                          style: TextStyle(
                            fontSize: 10.5,
                            height: 1,
                            fontWeight: FontWeight.w600,
                            color: text,
                            decoration: status == SeatStatus.taken ? TextDecoration.lineThrough : null,
                            decorationColor: text,
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RowLabel extends StatelessWidget {
  const _RowLabel(this.row);

  final String row;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SeatGrid._labelWidth,
      child: ExcludeSemantics(
        child: Text(
          row,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: CustomerColors.faint),
        ),
      ),
    );
  }
}

/// A red EXIT sign at the side of the hall (row B), standing on its side to fit the column.
class _ExitSlot extends StatelessWidget {
  const _ExitSlot({required this.show});

  final bool show;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: SeatGrid._exitWidth,
      child: !show
          ? null
          : ExcludeSemantics(
              child: Center(
                child: RotatedBox(
                  quarterTurns: 3,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                    decoration: BoxDecoration(
                      color: _exitRed,
                      borderRadius: BorderRadius.circular(4),
                      boxShadow: const [BoxShadow(color: Color(0x2ED92D20), spreadRadius: 3)],
                    ),
                    child: const Text(
                      'EXIT',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

/// The screen: a curved gold bar with its label — where everyone should be looking.
class _ScreenBar extends StatelessWidget {
  const _ScreenBar();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FractionallySizedBox(
        widthFactor: 0.86,
        child: Column(
          children: [
            SizedBox(
              height: 12,
              width: double.infinity,
              child: CustomPaint(painter: _ScreenPainter()),
            ),
            const Text(
              'SCREEN',
              style: TextStyle(letterSpacing: 4.2, fontSize: 10.5, fontWeight: FontWeight.w600, color: CustomerColors.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScreenPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // The top half of a flat ellipse, like the website's rounded top border.
    final arc = Rect.fromLTWH(2, 2, size.width - 4, 28);
    canvas.drawArc(
      arc,
      3.1416,
      3.1416,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round
        ..color = CustomerColors.gold,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// The entrance at the back: from there you walk left or right to the aisles.
class _Entrance extends StatelessWidget {
  const _Entrance();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.arrow_back_rounded, size: 18, color: CustomerColors.faint),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: CustomerColors.surface,
              borderRadius: BorderRadius.circular(Radii.pill),
              border: Border.all(color: CustomerColors.borderStrong, width: 1.5),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.door_front_door_outlined, size: 15, color: CustomerColors.ink),
                SizedBox(width: 7),
                Text('ENTRANCE', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, letterSpacing: 2.1)),
              ],
            ),
          ),
          const SizedBox(width: 14),
          const Icon(Icons.arrow_forward_rounded, size: 18, color: CustomerColors.faint),
        ],
      ),
    );
  }
}

/// Explains the seat states.
class SeatLegend extends StatelessWidget {
  const SeatLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget item(Color fill, Color border, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 14,
          height: 12,
          decoration: BoxDecoration(
            color: fill,
            border: Border.all(color: border, width: 1.5),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
              bottomLeft: Radius.circular(2),
              bottomRight: Radius.circular(2),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(text, style: const TextStyle(fontSize: 12, color: CustomerColors.muted)),
      ],
    );

    return ExcludeSemantics(
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 18,
        runSpacing: 8,
        children: [
          item(CustomerColors.surface, _seatBorder, 'Available'),
          item(CustomerColors.gold, CustomerColors.gold600, 'Selected'),
          item(_seatTaken, Colors.transparent, 'Taken'),
        ],
      ),
    );
  }
}
