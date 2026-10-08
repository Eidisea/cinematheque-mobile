import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/booking_rules.dart';
import '../../core/formatting.dart';
import '../../data/models/screening.dart';
import '../../data/models/seat_layout.dart';
import '../customer_services.dart';
import '../seat_map/seat_grid.dart';
import '../seat_map/seat_map_logic.dart';
import '../theme/customer_theme.dart';
import '../widgets/booking_steps.dart';
import '../widgets/brand.dart';
import '../widgets/poster.dart';
import '../widgets/state_views.dart';

/// Step 1 of booking: choose up to 10 seats on the live seat map.
///
/// Seats others reserve while you are choosing turn grey immediately; if one of YOUR
/// picks is taken, it is removed and you are told. Nothing is reserved until the
/// booking is submitted (next step) — the server re-checks every seat then.
class SeatSelectionScreen extends StatefulWidget {
  const SeatSelectionScreen({super.key, required this.screeningId});

  final String screeningId;

  @override
  State<SeatSelectionScreen> createState() => _SeatSelectionScreenState();
}

class _SeatSelectionScreenState extends State<SeatSelectionScreen> {
  StreamSubscription<Screening?>? _screeningSub;
  StreamSubscription<SeatLayout?>? _layoutSub;
  Timer? _tick;

  Screening? _screening;
  SeatLayout? _layout;
  bool _screeningLoaded = false;
  bool _layoutLoaded = false;
  Object? _error;
  SeatMapState? _map;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_screeningSub == null) _subscribe();
  }

  void _subscribe() {
    final catalog = CustomerServices.of(context).catalog;
    _error = null;
    _screeningSub = catalog.watchScreening(widget.screeningId).listen((s) {
      _screeningLoaded = true;
      _screening = s;
      _rebuildMap();
    }, onError: _onError);
    _layoutSub = catalog.watchSeatLayout().listen((l) {
      _layoutLoaded = true;
      _layout = l;
      _rebuildMap();
    }, onError: _onError);
    // Unpaid holds expire and screenings start as time passes — re-check regularly.
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => _rebuildMap());
  }

  void _onError(Object e) {
    if (mounted) setState(() => _error = e);
  }

  void _retry() {
    _cancel();
    setState(_subscribe);
  }

  void _cancel() {
    _screeningSub?.cancel();
    _layoutSub?.cancel();
    _tick?.cancel();
    _screeningSub = null;
  }

  void _rebuildMap() {
    if (!mounted) return;
    final screening = _screening;
    final layout = _layout;
    final now = CustomerServices.of(context).clock.now();
    if (screening == null || layout == null) {
      setState(() => _map = null);
      return;
    }
    final current = _map;
    if (current == null) {
      setState(() => _map = SeatMapState(layout: layout, screening: screening, now: now));
      return;
    }
    final (next, lost) = current.refresh(screening: screening, layout: layout, now: now);
    setState(() => _map = next);
    // Only warn while the seat map is the screen in front. Once the customer has moved on
    // to the details form, a change here is usually their OWN booking claiming the seats;
    // real conflicts are reported by the server when they submit.
    if (lost.isNotEmpty && (ModalRoute.of(context)?.isCurrent ?? true)) {
      _toast(
        lost.length == 1
            ? 'Seat ${lost.first} was just taken by someone else, so it was removed from your selection.'
            : 'Seats ${lost.join(', ')} were just taken by someone else, so they were removed from your selection.',
      );
    }
  }

  void _onSeatTap(String label) {
    final map = _map;
    if (map == null) return;
    final (next, result) = map.tap(label);
    setState(() => _map = next);
    if (result == SeatTapResult.limitReached) {
      _toast('You can choose up to ${BookingRules.maxSeatsPerReservation} seats per booking.');
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message), behavior: SnackBarBehavior.floating));
  }

  @override
  void dispose() {
    _cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final map = _map;
    final Widget body;
    if (_error != null) {
      body = ErrorView(onRetry: _retry);
    } else if (!_screeningLoaded || !_layoutLoaded) {
      body = const LoadingView(label: 'Loading seats…');
    } else if (_screening == null) {
      body = const MessageView(
        icon: Icons.event_busy_outlined,
        title: 'Screening not found',
        message: 'It may have been removed or rescheduled.',
      );
    } else if (_layout == null || _layout!.activeSeats.isEmpty) {
      body = const MessageView(
        icon: Icons.event_seat_outlined,
        title: 'Seat map not available',
        message: 'Seats for this screening cannot be chosen right now. Please try again later.',
      );
    } else {
      body = _SeatMapBody(map: map!, onSeatTap: _onSeatTap);
    }

    return Scaffold(
      appBar: AppBar(title: Text(_screening?.eventTitle ?? 'Choose seats', overflow: TextOverflow.ellipsis)),
      body: body,
    );
  }
}

/// As on the website: the steps, the seat map card, then the "Your screening" summary
/// with the Continue button.
class _SeatMapBody extends StatelessWidget {
  const _SeatMapBody({required this.map, required this.onSeatTap});

  final SeatMapState map;
  final void Function(String) onSeatTap;

  @override
  Widget build(BuildContext context) {
    final available = map.availableCount;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Space.lg, Space.sm, Space.lg, Space.xxl),
      children: [
        ContentWidth(
          maxWidth: 560,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BookingSteps(current: 0, paid: map.screening.isPaid),
              const SizedBox(height: Space.xl),
              if (map.isClosed) ...[
                const _Notice(icon: Icons.lock_clock_outlined, text: 'This screening has started. Booking is closed.'),
                const SizedBox(height: Space.lg),
              ] else if (available == 0 && map.selected.isEmpty) ...[
                const _Notice(icon: Icons.event_busy_outlined, text: 'All seats have been reserved.'),
                const SizedBox(height: Space.lg),
              ],
              _Card(
                padding: const EdgeInsets.fromLTRB(8, 18, 8, 16),
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Expanded(
                            child: Semantics(
                              header: true,
                              child: Text('SELECT YOUR SEATS', style: CcdType.display(24, spacing: 0.5)),
                            ),
                          ),
                          const SizedBox(width: Space.md),
                          Text(
                            '$available of ${map.layout.activeCount} left',
                            style: const TextStyle(color: CustomerColors.muted, fontSize: 12.5),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: Space.lg),
                    SeatGrid(state: map, onTap: onSeatTap),
                    const SizedBox(height: 14),
                    const SeatLegend(),
                  ],
                ),
              ),
              const SizedBox(height: Space.xl),
              _Summary(map: map),
            ],
          ),
        ),
      ],
    );
  }
}

/// White card with the website's soft shadow.
class _Card extends StatelessWidget {
  const _Card({required this.child, this.padding = EdgeInsets.zero});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: CustomerColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        boxShadow: const [BoxShadow(color: Color(0x2E141219), blurRadius: 20, spreadRadius: -10, offset: Offset(0, 6))],
      ),
      child: child,
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.md),
      decoration: BoxDecoration(color: CustomerColors.dangerTint, borderRadius: BorderRadius.circular(Radii.md)),
      child: Row(
        children: [
          Icon(icon, color: CustomerColors.danger),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: CustomerColors.danger)),
          ),
        ],
      ),
    );
  }
}

/// "Your screening": the poster on a gold block, the seats picked, price and total, and
/// Continue — the website's summary card.
class _Summary extends StatelessWidget {
  const _Summary({required this.map});

  final SeatMapState map;

  @override
  Widget build(BuildContext context) {
    final screening = map.screening;
    final seats = map.selectedInOrder;
    final count = seats.length;
    final price = screening.priceCentavos;

    Widget line(String label, String value) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontSize: 13.5, color: CustomerColors.muted)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: CustomerColors.stub,
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                PosterOnBlock(screening: screening, width: 104),
                const SizedBox(width: 18),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'YOUR SCREENING',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.9,
                            color: CustomerColors.goldText,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(screening.eventTitle.toUpperCase(), style: CcdType.display(22, spacing: 0.4)),
                        const SizedBox(height: 4),
                        Text(
                          '${formatDateShort(screening.startAt)} · ${formatTime(screening.startAt)}',
                          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                        ),
                        const Text('Cinematheque Centre Davao', style: TextStyle(fontSize: 12, color: CustomerColors.muted)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Perforation(horizontal: true, inset: 0),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Semantics(
                  label: count == 0 ? 'No seats selected' : 'Seats ${seats.join(', ')}',
                  excludeSemantics: true,
                  child: line('Seats', count == 0 ? '—' : seats.join(', ')),
                ),
                line('Price', screening.isPaid && price != null ? '${formatPeso(price)} per seat' : 'Free'),
                const SizedBox(height: 6),
                const Perforation(horizontal: true, inset: 0),
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Expanded(
                        child: Text(
                          '$count ${count == 1 ? 'seat' : 'seats'}',
                          style: const TextStyle(fontSize: 13.5, color: CustomerColors.muted),
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: Motion.fast,
                        child: Text(
                          screening.isPaid ? formatPeso(map.totalCentavos) : 'Free',
                          key: ValueKey(map.totalCentavos),
                          style: CcdType.money(22),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                GoldButton(
                  label: 'Continue',
                  icon: Icons.arrow_forward_rounded,
                  onPressed: map.canContinue
                      ? () => context.push('/screenings/${screening.id}/details', extra: map.selectedInOrder)
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  'Up to ${BookingRules.maxSeatsPerReservation} seats. The first seat you pick is yours.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12.5, color: CustomerColors.muted),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
